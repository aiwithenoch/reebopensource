import Foundation
import SwiftWhisper

/// The "careful ear": open-source Whisper (via SwiftWhisper / whisper.cpp,
/// tiny English model) re-transcribes the last few seconds of mic audio in the
/// background. If it heard script words the fast streaming engine missed, the
/// tracker nudges the prompter position forward. Fully on-device and offline.
final class WhisperVerifier {

    private let whisper: Whisper
    private var busy = false

    init?() {
        guard let url = Bundle.main.url(forResource: "ggml-tiny.en-q5_1", withExtension: "bin") else {
            return nil
        }
        let params = WhisperParams(strategy: .greedy)
        params.language = .english
        params.no_context = true
        params.suppress_blank = true
        whisper = Whisper(fromFileURL: url, withParams: params)
    }

    /// Transcribe 16kHz mono float samples. Skips the call if a previous
    /// transcription is still running (tiny model, so that's rare).
    func transcribe(_ samples: [Float], completion: @escaping ([String]) -> Void) {
        guard !busy, samples.count > 16000 else { return }
        busy = true
        whisper.transcribe(audioFrames: samples) { [weak self] result in
            DispatchQueue.main.async {
                self?.busy = false
                let words = ((try? result.get()) ?? [])
                    .flatMap { $0.text.split(whereSeparator: { $0.isWhitespace }).map(String.init) }
                completion(words)
            }
        }
    }
}
