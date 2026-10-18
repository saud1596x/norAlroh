import Foundation

/// Text already shown during practice can remain visible independently of
/// later acoustic revisions. This never creates evidence, mastery or a score.
public struct QuranPracticeVisibility: Sendable {
    private let idsByVerse: [String: Set<Int>]
    public init(expected: [QuranAlignedWord]) {
        idsByVerse = Dictionary(grouping: expected, by: \.verse).mapValues { Set($0.map(\.id)) }
    }
    public func newlyShownVerses(evidence: [QuranWordEvidence]) -> Set<String> {
        let observed = Dictionary(grouping: evidence, by: \.verse).mapValues { Set($0.map(\.nativeID)) }
        return Set(observed.compactMap { verse, ids in
            guard let expected = idsByVerse[verse], !expected.isEmpty, expected.isSubset(of: ids) else { return nil }
            return verse
        })
    }
    public func visibleIDs(verses: [String]) -> Set<Int> {
        verses.reduce(into: Set<Int>()) { result, verse in result.formUnion(idsByVerse[verse] ?? []) }
    }
}
