import Foundation

/// Unconfirmed word differences, retained only for the current recording session.
/// A later match at the same corpus position resolves the candidate automatically.
struct RecitationObservation: Identifiable {
    var id: Int { wordIndex }
    let wordIndex: Int
    let expected: String
    var heard: String?
    let firstSeen: Date
    var lastSeen: Date
    var corrected = false
    var dismissed = false
    func readyForReview(at date: Date) -> Bool { !corrected && !dismissed && date.timeIntervalSince(firstSeen) >= 8 }
}
struct RecitationObservationLedger {
    private(set) var notes: [Int: RecitationObservation] = [:]
    var ordered: [RecitationObservation] { notes.values.sorted { $0.wordIndex < $1.wordIndex } }
    mutating func ingest(_ comparison: RecitationComparison, expected: [RecitationExpectedWord], at date: Date) {
        guard comparison.reliableAlignment else { return }
        for index in comparison.matchedIndices where notes[index] != nil { notes[index]?.corrected = true }
        for difference in comparison.possibleDifferences {
            guard let index = difference.wordIndex, expected.indices.contains(index) else { continue }
            // A resolved candidate can recur, but a user-excluded ASR mistake stays excluded.
            if let existing = notes[index], existing.dismissed { continue }
            if var existing = notes[index], !existing.corrected {
                existing.heard = difference.heard; existing.lastSeen = date; notes[index] = existing
            } else {
                notes[index] = .init(wordIndex: index, expected: expected[index].text, heard: difference.heard, firstSeen: date, lastSeen: date)
            }
        }
    }
    mutating func dismiss(_ index: Int) { notes[index]?.dismissed = true }
}
