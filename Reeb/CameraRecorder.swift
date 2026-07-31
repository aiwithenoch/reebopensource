import AVFoundation
import Photos
import UIKit

/// In-app camera: preview + video recording via AVAssetWriter, with the audio
/// stream forked out (onAudioBuffer) so speech recognition runs during the
/// recording — no microphone contention, everything in one app.
final class CameraRecorder: NSObject, ObservableObject {

    @Published var isRecording = false
    @Published var isFront = true
    @Published var justSaved = false
    @Published var errorMessage: String?

    let session = AVCaptureSession()
    /// Set on the capture queue; forks camera audio to the speech tracker.
    var onAudioBuffer: ((CMSampleBuffer) -> Void)?

    private let sessionQueue = DispatchQueue(label: "reeb.camera.session")
    private let outputQueue = DispatchQueue(label: "reeb.camera.output")
    private let videoOutput = AVCaptureVideoDataOutput()
    private let audioOutput = AVCaptureAudioDataOutput()
    private var videoDeviceInput: AVCaptureDeviceInput?

    private var writer: AVAssetWriter?
    private var videoWriterInput: AVAssetWriterInput?
    private var audioWriterInput: AVAssetWriterInput?
    private var writerSessionStarted = false
    private var outputURL: URL?
    /// Read from the capture queue, toggled from main.
    private let recordingFlag = LockedFlag()

    final class LockedFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        func get() -> Bool { lock.lock(); defer { lock.unlock() }; return value }
        func set(_ v: Bool) { lock.lock(); value = v; lock.unlock() }
    }

    func startPreview() async {
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        guard granted else {
            await MainActor.run { errorMessage = "Camera permission is needed. Enable it in Settings > Privacy." }
            return
        }
        sessionQueue.async { self.configureAndRun() }
    }

    private func configureAndRun() {
        guard session.inputs.isEmpty else {
            if !session.isRunning { session.startRunning() }
            return
        }
        session.beginConfiguration()
        session.sessionPreset = .hd1920x1080
        addVideoInput(front: true)
        if let mic = AVCaptureDevice.default(for: .audio),
           let micInput = try? AVCaptureDeviceInput(device: mic),
           session.canAddInput(micInput) {
            session.addInput(micInput)
        }
        videoOutput.setSampleBufferDelegate(self, queue: outputQueue)
        if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }
        audioOutput.setSampleBufferDelegate(self, queue: outputQueue)
        if session.canAddOutput(audioOutput) { session.addOutput(audioOutput) }
        orientConnection()
        session.commitConfiguration()
        session.startRunning()
    }

    private func addVideoInput(front: Bool) {
        if let existing = videoDeviceInput { session.removeInput(existing) }
        let type: AVCaptureDevice.DeviceType = .builtInWideAngleCamera
        guard let device = AVCaptureDevice.default(type, for: .video, position: front ? .front : .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return }
        session.addInput(input)
        videoDeviceInput = input
    }

    private func orientConnection() {
        guard let connection = videoOutput.connection(with: .video) else { return }
        if connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90   // portrait
        }
    }

    func flipCamera() {
        let front = !isFront
        isFront = front
        sessionQueue.async {
            self.session.beginConfiguration()
            self.addVideoInput(front: front)
            self.orientConnection()
            self.session.commitConfiguration()
        }
    }

    // MARK: Recording

    func startRecording() {
        outputQueue.async {
            do {
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("reeb-\(UUID().uuidString).mov")
                let writer = try AVAssetWriter(outputURL: url, fileType: .mov)

                let videoSettings = self.videoOutput.recommendedVideoSettingsForAssetWriter(writingTo: .mov)
                let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
                videoInput.expectsMediaDataInRealTime = true
                if writer.canAdd(videoInput) { writer.add(videoInput) }

                let audioSettings = self.audioOutput.recommendedAudioSettingsForAssetWriter(writingTo: .mov)
                let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
                audioInput.expectsMediaDataInRealTime = true
                if writer.canAdd(audioInput) { writer.add(audioInput) }

                writer.startWriting()
                self.writer = writer
                self.videoWriterInput = videoInput
                self.audioWriterInput = audioInput
                self.writerSessionStarted = false
                self.outputURL = url
                self.recordingFlag.set(true)
                DispatchQueue.main.async { self.isRecording = true }
            } catch {
                DispatchQueue.main.async { self.errorMessage = "Could not start recording: \(error.localizedDescription)" }
            }
        }
    }

    func stopRecording() {
        recordingFlag.set(false)
        DispatchQueue.main.async { self.isRecording = false }
        outputQueue.async {
            guard let writer = self.writer, let url = self.outputURL else { return }
            self.writer = nil
            guard self.writerSessionStarted else { return }
            self.videoWriterInput?.markAsFinished()
            self.audioWriterInput?.markAsFinished()
            writer.finishWriting {
                self.saveToPhotos(url)
            }
        }
    }

    private func saveToPhotos(_ url: URL) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async {
                    self.errorMessage = "Allow Photos access in Settings to save your videos."
                }
                return
            }
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            } completionHandler: { success, _ in
                try? FileManager.default.removeItem(at: url)
                DispatchQueue.main.async {
                    if success {
                        self.justSaved = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { self.justSaved = false }
                    } else {
                        self.errorMessage = "Saving to Photos failed."
                    }
                }
            }
        }
    }

    func shutdown() {
        recordingFlag.set(false)
        sessionQueue.async {
            if self.session.isRunning { self.session.stopRunning() }
        }
    }
}

extension CameraRecorder: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        if output === audioOutput {
            onAudioBuffer?(sampleBuffer)
        }
        guard recordingFlag.get(), let writer, writer.status == .writing else { return }

        if output === videoOutput {
            if !writerSessionStarted {
                writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
                writerSessionStarted = true
            }
            if let videoWriterInput, videoWriterInput.isReadyForMoreMediaData {
                videoWriterInput.append(sampleBuffer)
            }
        } else if writerSessionStarted,
                  let audioWriterInput, audioWriterInput.isReadyForMoreMediaData {
            audioWriterInput.append(sampleBuffer)
        }
    }
}
