import Foundation
import WhisperKit
import os
import CryptoKit

/// Keep the bundled decoder's source uncertainty before exact Quran anchoring.
/// This gate is independently testable without constructing a Core ML model.
struct QuranLocalWordEvidence {
    private(set) var runs: [[QuranHeardWord]] = [[]]
    private(set) var observations: [QuranObservedWord] = []
    private(set) var unresolved = false
    private var previousEnd: Double = 0
    private(set) var rejectedAudio = 0, rejectedTiming = 0, rejectedConfidence = 0
    private(set) var rejectedQuiet = 0, rejectedTokenBoundary = 0, accepted = 0

    mutating func consume(text: String, start: Float, end: Float, confidence: Float,
                          speechSegment: Bool, samples: [Float], offset: Double) {
        var rejection = AudioEvidenceGate.rejection(.init(start: start, end: end, probability: confidence), samples: samples)
        let timing = start.isFinite && end.isFinite && start >= 0 && end > start
            && Double(end) <= Double(samples.count) / 16_000
        if !timing || Double(start) < previousEnd { rejection = .invalidTiming }
        if timing { previousEnd = max(previousEnd, Double(end)) }
        if !speechSegment, rejection == nil { rejection = .lowConfidence }
        let invalidBoundary = QuranAlignedWord.tokens([text]).count != 1
        let usable = rejection == nil && !invalidBoundary && !text.isEmpty
        if !text.isEmpty {
            observations.append(.init(occurrenceIndex: observations.count, runIndex: runs.count-1,
                observedText: text, startInTakeSeconds: timing ? offset + Double(start) : nil,
                endInTakeSeconds: timing ? offset + Double(end) : nil,
                backendConfidence: confidence.isFinite && (0...1).contains(confidence) ? Double(confidence) : nil,
                recognitionState: usable ? "accepted" : "unassessable", timingSource: timing ? "backend-word" : "unavailable"))
        }
        switch rejection {
        case .invalidAudio: rejectedAudio += 1
        case .invalidTiming: rejectedTiming += 1
        case .lowConfidence: rejectedConfidence += 1
        case .insufficientAudio: rejectedQuiet += 1
        case nil: break
        }
        if invalidBoundary { rejectedTokenBoundary += 1 }
        if usable {
            accepted += 1
            runs[runs.count-1].append(.init(text: text, start: Double(start), end: Double(end), probability: Double(confidence)))
        } else { unresolved = true; runs.append([]) }
    }
    mutating func interrupt(unassessableText: String? = nil) {
        if let text = unassessableText?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            // A bounded raw segment hypothesis is not a timed/accepted word.
            observations.append(.init(occurrenceIndex: observations.count, runIndex: runs.count-1,
                observedText: String(text.prefix(128)), startInTakeSeconds: nil, endInTakeSeconds: nil,
                backendConfidence: nil, recognitionState: "unassessable", timingSource: "unavailable"))
        }
        unresolved = true; runs.append([])
    }
}

actor QuranRecognitionWorker {
    static let shared = QuranRecognitionWorker()
    private static let diagnostics = OSLog(subsystem: "com.noor.recitation", category: "Recognition evidence")
    struct Result: Sendable {
        let runs: [[QuranHeardWord]]
        let hasUnresolvedSpeech: Bool
        var observations: [QuranObservedWord]? = nil
        var windowID: UUID? = nil
        var processingConfiguration: String? = nil
        var independentRecognition: QuranIndependentObservation? = nil
    }
    private var engine: WhisperKit?
    private var loading: Task<Void, Error>?
    private var inference: Task<Result, Error>?
    private var inferenceID: UUID?
    private let decodeOverride: ((QuranAudioWindow) async throws -> Result)?
    init(decodeOverride: ((QuranAudioWindow) async throws -> Result)? = nil) {
        self.decodeOverride = decodeOverride
    }
    // Script validation has its own executor: an SDK decode/model load must
    // never hold the reference binding needed before starting the microphone.
    nonisolated func bind(snapshot: QCFV2Snapshot, verseKeys: [String]) async throws -> [QuranAlignedWord] {
        try await QuranRecognitionReference.shared.bind(snapshot: snapshot, verseKeys: verseKeys)
    }
    func prepare() async throws {
        if engine != nil { return }
        if let loading { try await loading.value; return }
        // The independent model has no dependency on Whisper. Warming it
        // first serially delays the first captured utterance unnecessarily.
        // Capture remains immediate, and actual recognition still awaits both
        // models before paired evidence can retain any words.
        async let independentWarmup: Void? = try? QuranIndependentCTC.shared.prepare()
        guard let root = Bundle.main.url(forResource: "RecitationModel", withExtension: nil) else {
            throw CocoaError(.fileNoSuchFile)
        }
        guard QuranRecognitionModelDescriptor.bundled != nil else { throw CocoaError(.fileReadCorruptFile) }
        let task = Task { self.engine = try await WhisperKit(WhisperKitConfig(
            modelFolder: root.appendingPathComponent("model").path,
            tokenizerFolder: root.appendingPathComponent("tokenizer", isDirectory: true),
            verbose: false, logLevel: .error, prewarm: false, load: true, download: false)) }
        loading = task
        defer { loading = nil }
        try await task.value
        _ = await independentWarmup
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
        let inferenceSamples = try QuranRecognitionAudio.conditioned(window.samples)
        if let activity = try? QuranVoiceActivity.scan(inferenceSamples), !activity.hasSpeech {
            return Result(runs: [], hasUnresolvedSpeech: false, observations: [],
                          processingConfiguration: "NoorVAD/webrtc-no-speech/no-ASR")
        }
        try await prepare()
        try Task.checkCancellation()
        guard let engine else { throw CocoaError(.fileReadCorruptFile) }
        let options = DecodingOptions(language: "ar", temperatureFallbackCount: 0,
            skipSpecialTokens: true, withoutTimestamps: false, wordTimestamps: true,
            suppressBlank: true, concurrentWorkerCount: 1)
        let output = try await engine.transcribe(audioArray: inferenceSamples, decodeOptions: options)
        var decoded = QuranLocalWordEvidence()
        for segment in output.flatMap(\.segments) {
        guard let words = segment.words, !words.isEmpty else {
            decoded.interrupt(unassessableText: segment.text)
            continue
        }
        // Amplification must not turn a decoder's no-speech segment into
        // Quran progress. Missing/non-finite confidence stays unresolved.
        let speech = segment.noSpeechProb.isFinite && (0...1).contains(segment.noSpeechProb) && segment.noSpeechProb < 0.6
        if !speech { decoded.interrupt() }
        for word in words {
            decoded.consume(text: word.word, start: word.start, end: word.end, confidence: word.probability,
                speechSegment: speech, samples: inferenceSamples, offset: window.offset)
        }
        }
        // Numeric counters only: no recognized text, samples, account or session
        // identifier. A listening UI cannot distinguish an acoustic rejection
        // from an alignment miss without measuring these separate boundaries.
        os_signpost(.event, log: Self.diagnostics, name: "Recognition gate counts",
            "accepted=%{public}d invalidAudio=%{public}d timing=%{public}d confidence=%{public}d quiet=%{public}d tokenBoundary=%{public}d",
            decoded.accepted, decoded.rejectedAudio, decoded.rejectedTiming, decoded.rejectedConfidence, decoded.rejectedQuiet, decoded.rejectedTokenBoundary)
        let sourceConfiguration = QuranRecognitionModelDescriptor.bundled.map {
            $0.configuration + "/run-evidence2/untimed-segment1/dc-copy1/" + QuranSpokenInitials.revision
        } ?? "bundled-primary"
        let independent: QuranIndependentObservation
        do {
            independent = try await QuranIndependentCTC.shared.recognize(window)
        } catch is CancellationError { throw CancellationError() }
        catch {
            // Keep the genuine primary hypothesis, but do not let an absent
            // verifier silently masquerade as agreement. Capture stays alive.
            let raw = decoded.observations.map { word in QuranObservedWord(
                observationID:word.observationID,occurrenceIndex:word.occurrenceIndex,runIndex:word.runIndex,
                observedText:word.observedText,startInTakeSeconds:word.startInTakeSeconds,
                endInTakeSeconds:word.endInTakeSeconds,backendConfidence:word.backendConfidence,
                recognitionState:"unassessable",timingSource:word.timingSource) }
            return Result(runs:[],hasUnresolvedSpeech:true,observations:raw,windowID:UUID(),
                          processingConfiguration:sourceConfiguration+"/independent-unavailable1")
        }
        try Task.checkCancellation()
        let expectedSHA = window.samples.withUnsafeBufferPointer { buffer in
            SHA256.hash(data:Data(buffer:buffer)).map{String(format:"%02x",$0)}.joined()
        }
        guard independent.sourceSHA256 == expectedSHA,
              independent.valid(start:window.offset,end:Double(window.endFrame)/16_000) else {
            throw QuranAlignmentFailure.invalidEvidence
        }
        let agreement = try QuranIndependentAgreement.evaluate(decoded.runs,independent:independent.words,
                                                                duration:Double(window.samples.count)/16_000)
        let accepted = Set(agreement.retained.map { QuranIndependentAgreement.Key(text:$0.text,
            start:window.offset+$0.start,end:window.offset+$0.end) })
        let starts = Set(agreement.runs.compactMap { $0.first }.map {
            QuranIndependentAgreement.Key(text:$0.text,start:window.offset+$0.start,end:window.offset+$0.end)
        })
        var raw: [QuranObservedWord] = [], runIndex = 0, previousOriginalRun: Int?
        for word in decoded.observations {
            if let previousOriginalRun, word.runIndex != previousOriginalRun { runIndex += 1 }
            previousOriginalRun = word.runIndex
            let retained = word.recognitionState == "accepted" && word.startInTakeSeconds != nil
                && word.endInTakeSeconds != nil && accepted.contains(.init(text:word.observedText,
                    start:word.startInTakeSeconds!,end:word.endInTakeSeconds!))
            if retained, starts.contains(.init(text:word.observedText,start:word.startInTakeSeconds!,end:word.endInTakeSeconds!)) {
                runIndex += 1
            }
            raw.append(QuranObservedWord(observationID:word.observationID,occurrenceIndex:word.occurrenceIndex,
                runIndex:runIndex,observedText:word.observedText,startInTakeSeconds:word.startInTakeSeconds,
                endInTakeSeconds:word.endInTakeSeconds,backendConfidence:word.backendConfidence,
                recognitionState:retained ? "accepted" : "unassessable",timingSource:word.timingSource))
            if !retained { runIndex += 1 }
        }
        return Result(runs:agreement.runs,hasUnresolvedSpeech:decoded.unresolved || agreement.disagreements > 0 || agreement.hasIndependentOnlyWords,
                      observations:raw,windowID:UUID(),processingConfiguration:sourceConfiguration+"/paired-ctc1",
                      independentRecognition:independent)
    }
}

enum QuranRecognitionFailure: Error {
    case previousInferenceStillRunning
}

/// Immutable Quran/script binding is independent of the inference actor. This
/// cache still compares the complete edition and keys, never only a revision.
actor QuranRecognitionReference {
    static let shared = QuranRecognitionReference()
    private var boundNative: [QuranNativeWord] = []
    private var boundSnapshot: QCFV2Snapshot?
    private var boundKeys: [String] = []
    private var boundWords: [QuranAlignedWord] = []
    // Decode, validate and normalize the full edition away from the UI actor.
    // Reuse only after comparing every native ID, glyph, position and page.
    func bind(snapshot: QCFV2Snapshot, verseKeys: [String]) throws -> [QuranAlignedWord] {
        guard verseKeys.count == 6236 else { throw QuranAlignmentFailure.invalidEdition }
        // Reuse only an exactly equal, previously validated immutable copy.
        // Array value equality also permits the shared COW storage fast path.
        // IDs, revision numbers, or counts alone are insufficient evidence.
        if snapshot == boundSnapshot, verseKeys == boundKeys, !boundWords.isEmpty { return boundWords }
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
        boundNative = native; boundKeys = verseKeys; boundWords = words; boundSnapshot = snapshot
        return words
    }
}
