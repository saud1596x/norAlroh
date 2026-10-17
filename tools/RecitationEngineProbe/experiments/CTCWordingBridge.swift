import Foundation

// Executes the unchanged production wording policy on actual Apple CTC output.
// Character-frame timings and posterior scores are development evidence, not
// calibrated learner-error probabilities or independently reviewed boundaries.
@main struct CTCWordingBridge {
    struct Word: Decodable {
        let text: String
        let start: Double
        let end: Double
        let posterior: Double
        let complete: Bool
    }
    struct Case: Decodable { let name: String; let words: [Word]; let samples: Int }
    struct Row: Encodable {
        let name: String
        let rawObservedWords: [String]
        let events: [QuranWordingEvent]
        let confirmedErrors = 0
    }
    static func main() throws {
        let source = URL(fileURLWithPath: CommandLine.arguments[1])
        let cases = try JSONDecoder().decode([Case].self, from: Data(contentsOf: source))
        let tokens = ["قل", "هو", "الله", "أحد", "الله", "الصمد"]
        let expected = tokens.enumerated().map {
            QuranAlignedWord(id: $0.offset + 1, verse: $0.offset < 4 ? "112:1" : "112:2", page: 604,
                             aliases: [[QuranAlignedWord.normalize($0.element)]])
        }
        var results: [Row] = []
        for item in cases where item.name.hasPrefix("public-") || item.name == "digital-silence" {
            let words = item.words.enumerated().map { index, word in
                QuranObservedWord(occurrenceIndex: index, runIndex: 0, observedText: word.text,
                    startInTakeSeconds: word.start, endInTakeSeconds: word.end,
                    backendConfidence: word.posterior,
                    recognitionState: word.complete && word.posterior >= 0.75 ? "accepted" : "unassessable",
                    timingSource: "ctc-character-frame-receptive-field-development")
            }
            var span = QuranObservedSpeech(takeID: UUID(), start: 0, end: Double(item.samples) / 16_000,
                words: words.map(\.observedText), unresolved: words.contains { $0.recognitionState != "accepted" },
                backendID: "actual-apple-ctc-investigation")
            span.evidenceVersion = 1; span.recognitionWindowID = UUID(); span.recognitionRevision = 0
            span.wordObservations = words
            let before = span.wordObservations
            let events = QuranWordingAssessment.evaluate([span], expected: expected)
            guard before == span.wordObservations, events.allSatisfy({ $0.state == "provisional" }) else {
                throw NSError(domain: "CTCEvidenceMutation", code: 1)
            }
            if item.name == "digital-silence" || item.name == "public-composite" {
                guard events.isEmpty else { throw NSError(domain: "CTCFalseBaselineEvent", code: 1) }
            }
            if item.name == "public-cut" {
                guard events.contains(where: { $0.category == "omission" && $0.referenceIDs == [3] }) else {
                    throw NSError(domain: "CTCActualSpliceNotDetected", code: 1)
                }
            }
            results.append(.init(name: item.name, rawObservedWords: words.map(\.observedText), events: events))
        }
        guard results.count == 5 else { throw NSError(domain: "CTCCaseLoss", code: 1) }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(results).write(to: URL(fileURLWithPath: "ctc-production-wording.json"), options: .atomic)
        // Deliberately report actual categories; this splice experiment cannot
        // establish the original learner-error precision/recall requirements.
        for row in results { print("ACTUAL_CTC_WORDING \(row.name) categories=\(row.events.map(\.category)) confirmed=0") }
    }
}
