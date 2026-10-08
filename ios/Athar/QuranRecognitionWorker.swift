import Foundation
import WhisperKit

actor QuranRecognitionWorker {
    struct Result: Sendable {
        let runs: [[QuranHeardWord]]
        let hasUnresolvedSpeech: Bool
    }
    private var engine: WhisperKit?
    private var boundNative: [QuranNativeWord] = []
    private var boundKeys: [String] = []
    private var boundWords: [QuranAlignedWord] = []
    // Decode, validate and normalize the full edition away from the UI actor.
    // Reuse only after comparing every native ID, glyph, position and page.
    func bind(snapshot: QCFV2Snapshot, verseKeys: [String]) throws -> [QuranAlignedWord] {
        guard verseKeys.count == 6236 else { throw QuranAlignmentFailure.invalidEdition }
        let native = try snapshot.validated().records
            .filter { $0.record_type == "mushaf_word" && $0.char_type_name == "word" }
            .map { QuranNativeWord(id: $0.id, verse: verseKeys[$0.verse_id! - 1],
                position: $0.position_in_verse!, page: $0.page_number!, glyph: $0.text!) }
        if native == boundNative, verseKeys == boundKeys, !boundWords.isEmpty { return boundWords }
        guard let url = Bundle.main.url(forResource: "recitation-word-script", withExtension: "json") else {
            throw QuranAlignmentFailure.invalidScript
        }
        let script = try JSONDecoder().decode(QuranWordScript.self, from: Data(contentsOf: url))
        let words = try script.bind(native: native, verseKeys: verseKeys)
        boundNative = native; boundKeys = verseKeys; boundWords = words
        return words
    }
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
