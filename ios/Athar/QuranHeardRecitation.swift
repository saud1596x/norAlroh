import Foundation

/// Bounded presentation history of already accepted words. This never writes
/// recognition evidence, reveals a reference remainder, or claims current speech.
struct QuranHeardRecitation: Equatable {
    struct Fragment: Equatable {
        struct Word: Equatable {
            let nativeID: Int
            let text: String
        }
        let verse: String
        fileprivate var words: [Word]
        var text: String { words.map(\.text).joined(separator: " ") }
        var nativeIDs: [Int] { words.map(\.nativeID) }
    }
    private var sessionID: UUID?
    private var takeID: UUID?
    private(set) var fragments: [Fragment] = []

    mutating func begin(sessionID: UUID) {
        self.sessionID = sessionID; takeID = nil; fragments = []
    }
    mutating func beginTake(sessionID: UUID, takeID: UUID) {
        guard self.sessionID == sessionID else { return }
        self.takeID = takeID
    }
    static func sourcesForRestoration(_ spans: [QuranObservedSpeech], evidenceByTake: [UUID: [QuranWordEvidence]]) -> [QuranObservedSpeech] {
        var result: [QuranObservedSpeech] = []
        for span in spans.reversed() {
            guard (span.wordObservations ?? []).contains(where: {
                $0.recognitionState == "accepted" && $0.startInTakeSeconds != nil && $0.endInTakeSeconds != nil
            }), (evidenceByTake[span.takeID] ?? []).contains(where: {
                $0.start >= span.start && $0.end <= span.end
            }) else { continue }
            result.append(span)
            if result.count == 16 { break }
        }
        return Array(result.reversed())
    }
    mutating func accept(sessionID: UUID, takeID: UUID, evidence: [QuranWordEvidence],
                         expected: [Int: QuranAlignedWord], runs: [[QuranHeardWord]], offset: Double) {
        guard self.sessionID == sessionID, self.takeID == takeID,
              offset.isFinite, offset >= 0 else { return }
        for accepted in evidence.sorted(by: { $0.start < $1.start }) {
            guard accepted.takeID == takeID, let word = expected[accepted.nativeID],
                  accepted.verse == word.verse, accepted.start.isFinite, accepted.end.isFinite,
                  accepted.start >= offset, accepted.end > accepted.start,
                  accepted.minimumConfidence.isFinite, (0.75...1).contains(accepted.minimumConfidence),
                  !evidence.contains(where: { $0.takeID == takeID && $0.start == accepted.start
                      && $0.end == accepted.end && ($0.nativeID != accepted.nativeID || $0.verse != accepted.verse) }) else { continue }
            // Use the actual recognized strings only when one complete native
            // group's exact interval and lexical form match accepted evidence.
            // Unlocated/raw hypotheses and hints cannot populate this header.
            let matches = runs.compactMap { run -> [QuranHeardWord]? in
                guard let first = run.firstIndex(where: { $0.start + offset == accepted.start }),
                      let last = run.lastIndex(where: { $0.end + offset == accepted.end }), first <= last else { return nil }
                let source = Array(run[first...last])
                guard source.allSatisfy({ $0.start.isFinite && $0.end.isFinite && $0.end > $0.start
                    && $0.start + offset >= accepted.start && $0.end + offset <= accepted.end
                    && $0.probability.isFinite && (0.75...1).contains($0.probability)
                    && !$0.text.isEmpty && $0.text.utf8.count <= 1024 }),
                      word.aliases.contains(QuranAlignedWord.tokens(source.map(\.text))) else { return nil }
                return source
            }
            let strings = Set(matches.map { $0.map(\.text).joined(separator: " ") })
            guard strings.count == 1, let text = strings.first else { continue }
            if fragments.last?.verse != word.verse { fragments.append(.init(verse: word.verse, words: [])) }
            let index = fragments.count - 1
            if let existing = fragments[index].words.firstIndex(where: { $0.nativeID == word.id }) {
                fragments[index].words[existing] = .init(nativeID: word.id, text: text)
            } else { fragments[index].words.append(.init(nativeID: word.id, text: text)) }
            fragments[index].words = Array(fragments[index].words.suffix(24))
            fragments = Array(fragments.suffix(2))
        }
    }
}
