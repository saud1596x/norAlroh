import Foundation

/// Lexical CPU benchmark on the exact installed edition. The observations are
/// explicitly injected; this is never ASR, learner accuracy or iPhone latency.
@main struct WordingReferenceBenchmark {
    struct Input: Decodable {
        struct Word: Decodable {
            let id: Int; let verse: String; let position: Int; let page: Int; let glyph: String
        }
        let words: [Word]
        let keys: [String]
    }
    static func main() throws {
        let input = try JSONDecoder().decode(Input.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
        let script = try JSONDecoder().decode(QuranWordScript.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2])))
        let words = try script.bind(native: input.words.map {
            QuranNativeWord(id: $0.id, verse: $0.verse, position: $0.position, page: $0.page, glyph: $0.glyph)
        }, verseKeys: input.keys)
        guard words.count == 77_429 else { throw QuranAlignmentFailure.invalidEdition }
        let take = UUID()
        let tokens = ["قل", "هو", "شيء", "أحد", "الله", "الصمد"]
        var speech = QuranObservedSpeech(takeID: take, start: 0, end: 6,
            words: tokens, unresolved: false, backendID: "injected-lexical-benchmark-NOT-ASR")
        speech.wordObservations = tokens.enumerated().map { index, text in
            .init(occurrenceIndex: index, runIndex: 0, observedText: text,
                startInTakeSeconds: Double(index), endInTakeSeconds: Double(index) + 0.8,
                backendConfidence: 0.95, recognitionState: "accepted", timingSource: "injected-test-boundary")
        }
        let original = speech
        let iterations = 3
        let startCold = ProcessInfo.processInfo.systemUptime
        var uncached: [QuranWordingEvent] = []
        for _ in 0..<iterations { uncached = QuranWordingAssessment.evaluate([speech], expected: words) }
        let uncachedSeconds = ProcessInfo.processInfo.systemUptime - startCold

        var prepared = QuranWordingAssessment.Reference(expected: words)
        guard QuranWordingAssessment.evaluate([], reference: &prepared).isEmpty,
              prepared.indexedWordCount == 0 else { throw QuranAlignmentFailure.invalidEvidence }
        let startFirst = ProcessInfo.processInfo.systemUptime
        let first = QuranWordingAssessment.evaluate([speech], reference: &prepared)
        let firstSeconds = ProcessInfo.processInfo.systemUptime - startFirst
        guard first == uncached, prepared.indexedWordCount == words.count else { throw QuranAlignmentFailure.invalidEvidence }
        let startWarm = ProcessInfo.processInfo.systemUptime
        for _ in 0..<iterations {
            guard QuranWordingAssessment.evaluate([speech], reference: &prepared) == uncached else {
                throw QuranAlignmentFailure.invalidEvidence
            }
        }
        let warmSeconds = ProcessInfo.processInfo.systemUptime - startWarm
        guard QuranWordingAssessment.evaluate([], reference: &prepared).isEmpty, speech == original else {
            throw QuranAlignmentFailure.invalidEvidence
        }
        let result: [String: Any] = [
            "scope": "ACTUAL_PRODUCTION_LEXICAL_CPU_ONLY_INJECTED_OBSERVATIONS",
            "nativeWordCount": words.count, "iterations": iterations,
            "uncachedTotalSeconds": uncachedSeconds, "firstIndexSeconds": firstSeconds,
            "cachedTotalSeconds": warmSeconds, "identicalFindings": true,
            "sourceObservationsUnchanged": true, "emptyInputDoesNotReuseFindings": true,
            "eventCount": uncached.count, "learnerAccuracy": NSNull(), "phoneLatency": NSNull(),
            "limits": "Uncached versus cached path in this source; no earlier-source speed claim, ASR inference, microphone or acoustic acceptance."
        ]
        let bytes = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print("NOOR_WORDING_REFERENCE_BENCH " + String(decoding: bytes, as: UTF8.self))
    }
}
