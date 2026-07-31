import Foundation
import AVFoundation
import Speech

/// Listens to the microphone and tracks how far into the script the speaker has read.
@MainActor
final class SpeechTracker: ObservableObject {

    enum Status: Equatable {
        case idle
        case listening
        case denied(String)
        case error(String)
    }

    @Published private(set) var status: Status = .idle
    /// Index of the next script word expected to be spoken (everything before it has been read).
    @Published private(set) var position: Int = 0

    private(set) var words: [String] = []          // original words, for display
    private var normalized: [String] = []          // matching keys

    private let audioEngine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var processedWordCount = 0
    private var lastSpoken: String?
    /// The last three words heard, for re-syncing after the reader goes off script.
    private var recentSpoken: [String] = []
    private var misses = 0
    /// True once listening has worked at least once — after that, failures are
    /// retried quietly by the watchdog instead of killing the session.
    private var hasStarted = false
    /// Invalidates callbacks from cancelled recognition tasks so a stale
    /// error can't fight the restart logic.
    private var generation = 0
    private var watchdog: Timer?

    /// How many upcoming script words to search when matching a spoken word.
    private let lookahead = 10

    // MARK: Whisper (open-source second engine)

    private var whisper: WhisperVerifier?
    private var whisperTimer: Timer?
    /// Last ~8s of 16kHz mono audio, fed from the mic tap (audio thread-safe).
    nonisolated let ringStore = AudioRingStore()

    /// When true, audio arrives via ingest(_:) from the in-app camera instead
    /// of our own microphone engine — no mic contention while recording.
    private var usesExternalAudio = false
    /// Thread-safe handle to the live recognition request for external feeding.
    nonisolated let requestBox = RequestBox()

    final class RequestBox: @unchecked Sendable {
        private let lock = NSLock()
        private var request: SFSpeechAudioBufferRecognitionRequest?
        func set(_ r: SFSpeechAudioBufferRecognitionRequest?) {
            lock.lock(); request = r; lock.unlock()
        }
        func append(_ sampleBuffer: CMSampleBuffer) {
            lock.lock(); request?.appendAudioSampleBuffer(sampleBuffer); lock.unlock()
        }
    }

    /// Feed a camera audio buffer into recognition + the Whisper ring.
    /// Called from the capture queue.
    nonisolated func ingest(_ sampleBuffer: CMSampleBuffer) {
        requestBox.append(sampleBuffer)
        if let pcm = Self.pcmBuffer(from: sampleBuffer) {
            ringStore.feedAuto(pcm)
        }
    }

    private nonisolated static func pcmBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let description = CMSampleBufferGetFormatDescription(sampleBuffer) else { return nil }
        let format = AVAudioFormat(cmAudioFormatDescription: description)
        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        buffer.frameLength = frames
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer, at: 0, frameCount: Int32(frames), into: buffer.mutableAudioBufferList)
        return status == noErr ? buffer : nil
    }

    func load(script: String) {
        words = script.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        normalized = words.map(Self.normalize)
        position = 0
        lastSpoken = nil
    }

    static func normalize(_ word: String) -> String {
        word.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    func start(externalAudio: Bool = false) async {
        usesExternalAudio = externalAudio
        let speechAuth = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
        }
        guard speechAuth == .authorized else {
            status = .denied("Speech recognition permission is needed. Enable it in Settings > Privacy.")
            return
        }
        let micGranted = await AVAudioApplication.requestRecordPermission()
        guard micGranted else {
            status = .denied("Microphone permission is needed. Enable it in Settings > Privacy.")
            return
        }
        observeInterruptions()
        startWatchdog()
        beginRecognition()
        startWhisper()
    }

    /// Load the Whisper model off the main thread and start the verify loop.
    private func startWhisper() {
        guard whisper == nil else { return }
        Task.detached(priority: .userInitiated) { [weak self] in
            let verifier = WhisperVerifier()
            await MainActor.run {
                guard let self, verifier != nil else { return }
                self.whisper = verifier
                self.whisperTimer?.invalidate()
                self.whisperTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
                    Task { @MainActor in self.runWhisperPass() }
                }
            }
        }
    }

    private func runWhisperPass() {
        guard status == .listening, let whisper, position < normalized.count else { return }
        let samples = ringStore.snapshot()
        guard samples.count > 16000 * 2 else { return }
        whisper.transcribe(samples) { [weak self] words in
            Task { @MainActor in self?.applyWhisper(words) }
        }
    }

    /// Whisper heard the last few seconds. If its final words line up with
    /// script words ahead of the current position (three in a row, so noise
    /// can't cause jumps), pull the prompter forward to catch up.
    private func applyWhisper(_ raw: [String]) {
        let heard = raw.map(Self.normalize).filter { !$0.isEmpty }
        guard heard.count >= 3, position < normalized.count else { return }
        let tail = Array(heard.suffix(3))
        let upper = min(position + 40, normalized.count)
        var j = max(position, 2)
        while j < upper {
            if normalized[j] == tail[2], normalized[j - 1] == tail[1], normalized[j - 2] == tail[0] {
                if j + 1 > position { position = j + 1 }
                return
            }
            j += 1
        }
    }

    private func beginRecognition() {
        guard let recognizer = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US")),
              recognizer.isAvailable else {
            // Mid-session, keep the status so the watchdog retries; only a
            // failure on the very first start is a real error to show.
            if !hasStarted {
                status = .error("Speech recognition is not available on this device right now.")
            }
            return
        }
        self.recognizer = recognizer
        stopEngineOnly()
        generation += 1
        let gen = generation

        do {
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            if recognizer.supportsOnDeviceRecognition {
                request.requiresOnDeviceRecognition = true
            }
            self.request = request
            processedWordCount = 0

            if !usesExternalAudio {
                // playAndRecord + mixWithOthers keeps the mic available while
                // other apps are active, and lets us run in the background.
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playAndRecord, mode: .default,
                                        options: [.mixWithOthers, .defaultToSpeaker, .allowBluetoothHFP])
                try session.setActive(true, options: .notifyOthersOnDeactivation)

                let input = audioEngine.inputNode
                let format = input.outputFormat(forBus: 0)
                let ring = ringStore
                ring.setInputFormat(format)
                input.removeTap(onBus: 0)
                input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                    request.append(buffer)
                    ring.feed(buffer)
                }
                audioEngine.prepare()
                try audioEngine.start()
            }
            requestBox.set(request)

            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    guard let self, gen == self.generation else { return }
                    self.handle(result: result, error: error)
                }
            }
            status = .listening
            hasStarted = true
        } catch {
            // The Camera (or any other app) grabbing the mic lands here.
            // Keep listening status so the watchdog reclaims the mic the
            // moment it's free again; only fail hard on the first start.
            if !hasStarted {
                status = .error("Could not start the microphone: \(error.localizedDescription)")
            }
        }
    }

    private func handle(result: SFSpeechRecognitionResult?, error: Error?) {
        if let result {
            let spoken = result.bestTranscription.segments.map(\.substring)
            if spoken.count > processedWordCount {
                advance(with: Array(spoken[processedWordCount...]))
                processedWordCount = spoken.count
            }
            // Recognizers finalize after silence; start a fresh utterance so we keep listening.
            if result.isFinal, status == .listening {
                beginRecognition()
            }
        } else if error != nil, status == .listening {
            beginRecognition()
        }
    }

    /// Recognition can die quietly (interruptions, route changes, engine stalls).
    /// Every 2 seconds, make sure the mic is actually running and revive it if not.
    private func startWatchdog() {
        watchdog?.invalidate()
        watchdog = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.status == .listening else { return }
                let dead = self.usesExternalAudio ? self.task == nil : !self.audioEngine.isRunning
                if dead {
                    self.beginRecognition()
                }
            }
        }
    }

    /// Match newly spoken words against the upcoming script and move the position.
    /// Small steps (the next word or the one after) match on a single word, but a
    /// bigger jump needs two consecutive matching words as evidence — so repeated
    /// common words ("the", "and") can't yank the prompter ahead of the reader.
    private func advance(with spokenWords: [String]) {
        for raw in spokenWords {
            let spoken = Self.normalize(raw)
            guard !spoken.isEmpty else { continue }
            let prev = lastSpoken
            lastSpoken = spoken
            recentSpoken.append(spoken)
            if recentSpoken.count > 3 { recentSpoken.removeFirst() }
            guard position < normalized.count else { continue }

            if normalized[position] == spoken {
                position += 1
                misses = 0
                continue
            }
            // Tolerate one misheard or skipped word.
            if position + 1 < normalized.count, normalized[position + 1] == spoken {
                position += 2
                misses = 0
                continue
            }
            // Bigger jumps require a two-word (bigram) match.
            if let prev, !prev.isEmpty {
                let upper = min(position + lookahead, normalized.count)
                var j = position + 2
                var matched = false
                while j < upper {
                    if normalized[j] == spoken, normalized[j - 1] == prev {
                        position = j + 1
                        misses = 0
                        matched = true
                        break
                    }
                    j += 1
                }
                if matched { continue }
            }

            // Lost the reader (mistake, side conversation, skipped section).
            // After enough unmatched words, re-sync: find the last three heard
            // words anywhere in the script — slightly behind or far ahead —
            // and jump to wherever the reader actually is.
            misses += 1
            if misses >= 6, recentSpoken.count == 3 {
                let lower = max(2, position - 10)
                var j = lower
                while j < normalized.count {
                    if normalized[j] == recentSpoken[2],
                       normalized[j - 1] == recentSpoken[1],
                       normalized[j - 2] == recentSpoken[0] {
                        position = j + 1
                        misses = 0
                        break
                    }
                    j += 1
                }
            }
        }
    }

    /// Manual controls: jump to an exact word (tap a line) or step by a few
    /// words (the skip buttons inside the floating window).
    func setPosition(_ index: Int) {
        position = max(0, min(index, words.count))
        misses = 0
    }

    func nudge(byWords delta: Int) {
        setPosition(position + delta)
    }

    private var interruptionObserver: NSObjectProtocol?

    /// The Camera app can briefly take the microphone (an audio session
    /// interruption). Resume recognition as soon as the interruption ends.
    private func observeInterruptions() {
        guard interruptionObserver == nil else { return }
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let self,
                  let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            Task { @MainActor in
                switch type {
                case .began:
                    self.stopEngineOnly()
                case .ended:
                    if self.status == .listening { self.beginRecognition() }
                @unknown default:
                    break
                }
            }
        }
    }

    func stop() {
        status = .idle
        watchdog?.invalidate()
        watchdog = nil
        whisperTimer?.invalidate()
        whisperTimer = nil
        ringStore.reset()
        stopEngineOnly()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func stopEngineOnly() {
        generation += 1
        requestBox.set(nil)
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil
        if !usesExternalAudio {
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.stop()
        }
    }
}
