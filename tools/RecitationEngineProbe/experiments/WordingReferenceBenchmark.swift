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
        // Exercise authentic complete short ayahs in the full installed scope,
        // outside the CPU timing above. These are explicit injected observations.
        func strong(_ texts: [String]) -> [QuranHeardWord] {
            texts.enumerated().map { .init(text: $0.element, start: Double($0.offset),
                end: Double($0.offset) + 0.8, probability: 0.98) }
        }
        var one = QuranRecitationTracker(expected: words)
        var two = QuranRecitationTracker(expected: words)
        var ambiguous = QuranRecitationTracker(expected: words)
        let oneIDs = try one.consume(strong(["مدهامتان"]), takeID: UUID()).map(\.nativeID)
        let twoIDs = try two.consume(strong(["الله", "الصمد"]), takeID: UUID()).map(\.nativeID)
        guard oneIDs == words.filter({ $0.verse == "55:64" }).map(\.id), oneIDs.count == 1,
              twoIDs == words.filter({ $0.verse == "112:2" }).map(\.id), twoIDs.count == 2,
              try ambiguous.consume(strong(["الرحمن"]), takeID: UUID()).isEmpty,
              try ambiguous.consume(strong(["الرحمن", "الرحيم"]), takeID: UUID()).isEmpty,
              try ambiguous.consume(strong(["يس"]), takeID: UUID()).isEmpty else {
            throw QuranAlignmentFailure.invalidEvidence
        }
        let byVerse = Dictionary(grouping: words, by: \.verse)
        let baseTracker = QuranRecitationTracker(expected: words)
        var shortFormsChecked = 0, locatedShortForms = 0, unresolvedShortForms = 0
        for key in input.keys {
            guard let verse = byVerse[key], (1...2).contains(verse.count),
                  !verse.contains(where: \.requiresFollowingContext) else { continue }
            var variants: [[String]] = [[]]
            for word in verse {
                variants = variants.flatMap { prefix in word.aliases.map { prefix + $0 } }
            }
            for tokens in variants {
                var tracker = baseTracker
                let ids = try tracker.consume(strong(tokens), takeID: UUID()).map(\.nativeID)
                // With no page/ayah prior, abstention is legitimate. Locating
                // another passage or filling unheard groups is never allowed.
                guard ids.isEmpty || ids == verse.map(\.id) else { throw QuranAlignmentFailure.invalidEvidence }
                shortFormsChecked += 1
                if ids.isEmpty { unresolvedShortForms += 1 } else { locatedShortForms += 1 }
            }
        }
        let result: [String: Any] = [
            "scope": "ACTUAL_PRODUCTION_LEXICAL_CPU_ONLY_INJECTED_OBSERVATIONS",
            "nativeWordCount": words.count, "iterations": iterations,
            "uncachedTotalSeconds": uncachedSeconds, "firstIndexSeconds": firstSeconds,
            "cachedTotalSeconds": warmSeconds, "identicalFindings": true,
            "sourceObservationsUnchanged": true, "emptyInputDoesNotReuseFindings": true,
            "fullNativeShortAyahsAndAmbiguityGuards": true,
            "shortAyahFormsChecked": shortFormsChecked,
            "shortAyahFormsLocated": locatedShortForms,
            "shortAyahFormsUnresolved": unresolvedShortForms,
            "wrongShortAyahBindings": 0,
            "eventCount": uncached.count, "learnerAccuracy": NSNull(), "phoneLatency": NSNull(),
            "limits": "Uncached versus cached path in this source; no earlier-source speed claim, ASR inference, microphone or acoustic acceptance."
        ]
        let bytes = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print("NOOR_WORDING_REFERENCE_BENCH " + String(decoding: bytes, as: UTF8.self))
    }
}
