import Foundation
import WhisperKit
import os

actor QuranRecognitionWorker {
    static let shared = QuranRecognitionWorker()
    private static let diagnostics = OSLog(subsystem: "com.noor.recitation", category: "Recognition evidence")
    struct Result: Sendable {
        let runs: [[QuranHeardWord]]
        let hasUnresolvedSpeech: Bool
    }
    private var engine: WhisperKit?
    private var loading: Task<WhisperKit, Error>?
    private var inference: Task<Result, Error>?
    private var inferenceID: UUID?
    private var boundNative: [QuranNativeWord] = []
    private var boundKeys: [String] = []
    private var boundWords: [QuranAlignedWord] = []
    private let decodeOverride: ((QuranAudioWindow) async throws -> Result)?
    init(decodeOverride: ((QuranAudioWindow) async throws -> Result)? = nil) {
        self.decodeOverride = decodeOverride
    }
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
        if let loading { engine = try await loading.value; return }
        guard let root = Bundle.main.url(forResource: "RecitationModel", withExtension: nil) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let task = Task { try await WhisperKit(WhisperKitConfig(
            modelFolder: root.appendingPathComponent("model").path,
            tokenizerFolder: root.appendingPathComponent("tokenizer", isDirectory: true),
            verbose: false, logLevel: .error, prewarm: false, load: true, download: false)) }
        loading = task
        defer { loading = nil }
        engine = try await task.value
    }
    func recognize(_ window: QuranAudioWindow) async throws -> Result {
        let previous = inference
        // Cancellation of Core ML does not guarantee that the model call has
        // returned. A later session must not silently wait behind that call.
        if previous?.isCancelled == true {
            throw QuranRecognitionFailure.previousInferenceStillRunning
        }
        let id = UUID()
        let task = Task {
            _ = try? await previous?.value
            try Task.checkCancellation()
            if let decodeOverride = self.decodeOverride { return try await decodeOverride(window) }
            return try await self.decode(window)
        }
        inference = task
        inferenceID = id
        defer {
            if inferenceID == id { inference = nil; inferenceID = nil }
        }
        return try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
    }
    private func decode(_ window: QuranAudioWindow) async throws -> Result {
        try await prepare()
        try Task.checkCancellation()
        guard let engine else { throw CocoaError(.fileReadCorruptFile) }
        let options = DecodingOptions(language: "ar", temperatureFallbackCount: 0,
            skipSpecialTokens: true, withoutTimestamps: false, wordTimestamps: true,
            suppressBlank: true, concurrentWorkerCount: 1)
        let output = try await engine.transcribe(audioArray: window.samples, decodeOptions: options)
        var runs: [[QuranHeardWord]] = [[]]
        var unresolved = false
        var rejectedAudio = 0, rejectedTiming = 0, rejectedConfidence = 0
        var rejectedQuiet = 0, rejectedTokenBoundary = 0, accepted = 0
        for word in output.flatMap(\.allWords) {
            let evidence = AudioEvidenceGate.Evidence(start: word.start, end: word.end, probability: word.probability)
            let rejection = AudioEvidenceGate.rejection(evidence, samples: window.samples)
            let invalidBoundary = QuranAlignedWord.tokens([word.word]).count != 1
            switch rejection {
            case .invalidAudio: rejectedAudio += 1
            case .invalidTiming: rejectedTiming += 1
            case .lowConfidence: rejectedConfidence += 1
            case .insufficientAudio: rejectedQuiet += 1
            case nil: break
            }
            if invalidBoundary { rejectedTokenBoundary += 1 }
            if rejection != nil || invalidBoundary {
                runs.append([]); unresolved = true
            } else {
                accepted += 1
                runs[runs.count - 1].append(.init(text: word.word, start: Double(word.start),
                    end: Double(word.end), probability: Double(word.probability)))
            }
        }
        // Numeric counters only: no recognized text, samples, account or session
        // identifier. A listening UI cannot distinguish an acoustic rejection
        // from an alignment miss without measuring these separate boundaries.
        os_signpost(.event, log: Self.diagnostics, name: "Recognition gate counts",
            "accepted=%{public}d invalidAudio=%{public}d timing=%{public}d confidence=%{public}d quiet=%{public}d tokenBoundary=%{public}d",
            accepted, rejectedAudio, rejectedTiming, rejectedConfidence, rejectedQuiet, rejectedTokenBoundary)
        return Result(runs: runs.filter { !$0.isEmpty }, hasUnresolvedSpeech: unresolved)
    }
}

enum QuranRecognitionFailure: Error {
    case previousInferenceStillRunning
}
