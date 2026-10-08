import Foundation
import WhisperKit

actor QuranRecognitionWorker {
    struct Result {
        let runs: [[QuranHeardWord]]
        let hasUnresolvedSpeech: Bool
    }
    private var engine: WhisperKit?
    func prepare() async throws {
        if engine != nil { return }
        guard let root = Bundle.main.url(forResource: "RecitationModel", withExtension: nil) else {
            throw CocoaError(.fileNoSuchFile)
        }
        engine = try await WhisperKit(WhisperKitConfig(
            modelFolder: root.appendingPathComponent("model").path,
            tokenizerFolder: root.appendingPathComponent("tokenizer", isDirectory: true),
            verbose: false, logLevel: .error, prewarm: false, load: true, download: false))
    }
    func recognize(_ window: QuranAudioWindow) async throws -> Result {
        try await prepare()
        guard let engine else { throw CocoaError(.fileReadCorruptFile) }
        let options = DecodingOptions(language: "ar", temperatureFallbackCount: 0,
            skipSpecialTokens: true, withoutTimestamps: false, wordTimestamps: true,
            suppressBlank: true, concurrentWorkerCount: 1)
        let output = try await engine.transcribe(audioArray: window.samples, decodeOptions: options)
        var runs: [[QuranHeardWord]] = [[]]
        var unresolved = false
        for word in output.flatMap(\.allWords) {
            let evidence = AudioEvidenceGate.Evidence(start: word.start, end: word.end, probability: word.probability)
            if AudioEvidenceGate.rejection(evidence, samples: window.samples) != nil
                || QuranAlignedWord.tokens([word.word]).count != 1 {
                runs.append([]); unresolved = true
            } else {
                runs[runs.count - 1].append(.init(text: word.word, start: Double(word.start),
                    end: Double(word.end), probability: Double(word.probability)))
            }
        }
        return Result(runs: runs.filter { !$0.isEmpty }, hasUnresolvedSpeech: unresolved)
    }
}
