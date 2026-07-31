import AVFoundation

/// Thread-safe rolling buffer of the last ~8 seconds of microphone audio,
/// downsampled to the 16kHz mono format Whisper expects. Fed from the audio
/// tap thread, read from the main thread.
final class AudioRingStore: @unchecked Sendable {

    private let lock = NSLock()
    private var samples: [Float] = []
    private var converter: AVAudioConverter?
    private var inputFormat: AVAudioFormat?

    private let capacity = 16000 * 8
    private let outputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                             sampleRate: 16000, channels: 1, interleaved: false)!

    func setInputFormat(_ format: AVAudioFormat) {
        lock.lock()
        defer { lock.unlock() }
        converter = AVAudioConverter(from: format, to: outputFormat)
        inputFormat = format
        samples.removeAll(keepingCapacity: true)
    }

    /// Feed a buffer whose format may not be known up front (camera audio) —
    /// builds or rebuilds the converter to match automatically.
    func feedAuto(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        if converter == nil || inputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: outputFormat)
            inputFormat = buffer.format
        }
        lock.unlock()
        feed(buffer)
    }

    func feed(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }
        guard let converter else { return }

        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let outCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 16)
        guard let out = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outCapacity) else { return }

        var fed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, outStatus in
            if fed {
                outStatus.pointee = .noDataNow
                return nil
            }
            fed = true
            outStatus.pointee = .haveData
            return buffer
        }
        guard error == nil, out.frameLength > 0, let channel = out.floatChannelData else { return }

        samples.append(contentsOf: UnsafeBufferPointer(start: channel[0], count: Int(out.frameLength)))
        if samples.count > capacity {
            samples.removeFirst(samples.count - capacity)
        }
    }

    func snapshot() -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        return samples
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        samples.removeAll()
    }
}
