import AVKit
import UIKit

/// Renders the prompter text into a Picture-in-Picture window that keeps floating
/// on top of other apps (like the Camera) after Reeb goes to the background.
final class PipController: NSObject, ObservableObject {

    @Published private(set) var isActive = false
    @Published private(set) var canFloat = false
    let isSupported = AVPictureInPictureController.isPictureInPictureSupported()
    /// Called when the user taps the skip buttons inside the floating window
    /// (true = forward). The prompter maps this to jumping a few words.
    var onSkip: ((Bool) -> Void)?

    let displayLayer = AVSampleBufferDisplayLayer()
    private var controller: AVPictureInPictureController?
    private var possibleObservation: NSKeyValueObservation?
    private var frameTimer: Timer?
    // Portrait-ish frame → a taller floating window showing many script lines.
    private var renderSize = CGSize(width: 480, height: 600)
    private var lastWords: [String] = []
    private var lastPosition = 0
    private var pendingStart = false

    override init() {
        super.init()
        displayLayer.videoGravity = .resizeAspect
        // A running control timebase is what makes the PiP renderer actually
        // display enqueued frames; without it the window can stay black.
        var timebase: CMTimebase?
        CMTimebaseCreateWithSourceClock(allocator: kCFAllocatorDefault,
                                        sourceClock: CMClockGetHostTimeClock(),
                                        timebaseOut: &timebase)
        if let timebase {
            CMTimebaseSetTime(timebase, time: .zero)
            CMTimebaseSetRate(timebase, rate: 1.0)
            displayLayer.controlTimebase = timebase
        }
    }

    func setUp() {
        guard controller == nil, isSupported else { return }
        let source = AVPictureInPictureController.ContentSource(
            sampleBufferDisplayLayer: displayLayer,
            playbackDelegate: self
        )
        let c = AVPictureInPictureController(contentSource: source)
        c.delegate = self
        c.canStartPictureInPictureAutomaticallyFromInline = true
        // Linear playback off so the floating window shows skip buttons,
        // which we repurpose as "jump back / forward a few words".
        c.requiresLinearPlayback = false
        controller = c

        possibleObservation = c.observe(\.isPictureInPicturePossible, options: [.initial, .new]) { [weak self] controller, _ in
            DispatchQueue.main.async {
                self?.canFloat = controller.isPictureInPicturePossible
                if controller.isPictureInPicturePossible, self?.pendingStart == true {
                    self?.pendingStart = false
                    controller.startPictureInPicture()
                }
            }
        }

        // A PiP window sourced from a sample-buffer layer needs a steady stream
        // of frames to stay alive and start reliably — keep feeding it.
        frameTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.renderFrame()
        }
    }

    func tearDown() {
        frameTimer?.invalidate()
        frameTimer = nil
        possibleObservation = nil
        if isActive { controller?.stopPictureInPicture() }
        controller = nil
    }

    func start() {
        guard let controller else { return }
        if controller.isPictureInPicturePossible {
            controller.startPictureInPicture()
        } else {
            // Not ready yet — start the moment iOS says it's possible.
            pendingStart = true
        }
    }

    func stop() { controller?.stopPictureInPicture() }

    func update(words: [String], position: Int) {
        lastWords = words
        lastPosition = position
        renderFrame()
    }

    private func renderFrame() {
        guard !lastWords.isEmpty else { return }
        let timestamp = displayLayer.controlTimebase.map { CMTimebaseGetTime($0) }
        guard let sample = PipFrameRenderer.makeFrame(words: lastWords,
                                                      position: lastPosition,
                                                      size: renderSize,
                                                      timestamp: timestamp) else { return }
        if displayLayer.status == .failed { displayLayer.flush() }
        displayLayer.enqueue(sample)
    }
}

extension PipController: AVPictureInPictureControllerDelegate {
    func pictureInPictureControllerDidStartPictureInPicture(_ c: AVPictureInPictureController) {
        DispatchQueue.main.async { self.isActive = true }
    }
    func pictureInPictureControllerDidStopPictureInPicture(_ c: AVPictureInPictureController) {
        DispatchQueue.main.async { self.isActive = false }
    }
    func pictureInPictureController(_ c: AVPictureInPictureController,
                                    failedToStartPictureInPictureWithError error: Error) {
        DispatchQueue.main.async { self.isActive = false }
    }
}

extension PipController: AVPictureInPictureSampleBufferPlaybackDelegate {
    func pictureInPictureController(_ c: AVPictureInPictureController, setPlaying playing: Bool) {}

    func pictureInPictureControllerTimeRangeForPlayback(_ c: AVPictureInPictureController) -> CMTimeRange {
        CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)
    }

    func pictureInPictureControllerIsPlaybackPaused(_ c: AVPictureInPictureController) -> Bool { false }

    func pictureInPictureController(_ c: AVPictureInPictureController,
                                    didTransitionToRenderSize newRenderSize: CMVideoDimensions) {
        guard newRenderSize.width > 0, newRenderSize.height > 0 else { return }
        renderSize = CGSize(width: CGFloat(newRenderSize.width), height: CGFloat(newRenderSize.height))
        renderFrame()
    }

    func pictureInPictureController(_ c: AVPictureInPictureController,
                                    skipByInterval skipInterval: CMTime,
                                    completion completionHandler: @escaping () -> Void) {
        let forward = skipInterval.seconds > 0
        DispatchQueue.main.async { self.onSkip?(forward) }
        completionHandler()
    }
}
