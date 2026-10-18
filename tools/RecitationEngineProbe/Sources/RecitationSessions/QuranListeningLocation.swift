import Foundation
#if canImport(RecitationAlignment)
import RecitationAlignment
#endif

/// Display location only, never additional word/correctness evidence.
/// Overlapping decode revisions may withdraw a highlight but cannot send the
/// viewport backward to older audio. A genuine later rereading can go anywhere.
public struct QuranListeningLocation: Sendable {
    public private(set) var verse: String?
    public private(set) var activeNativeID: Int?
    private var takeID: UUID?
    private var frontier: Double = -1
    private var anchor: QuranWordEvidence?
    public init() {}

    public mutating func begin(takeID: UUID) {
        self.takeID = takeID; frontier = -1; anchor = nil; activeNativeID = nil
    }

    public mutating func update(_ evidence: [QuranWordEvidence]) {
        let current = evidence.filter {
            $0.takeID == takeID && $0.start.isFinite && $0.end.isFinite
                && $0.start >= 0 && $0.end > $0.start && $0.nativeID > 0
                && $0.minimumConfidence.isFinite && (0.75...1).contains($0.minimumConfidence)
        }
        if let newestEnd = current.map(\.end).max(), newestEnd >= frontier {
            // Advance the source frontier even when its latest interpretation
            // conflicts. Otherwise an older, still-retained accepted word can
            // remain highlighted as though it were current speech. Equality
            // permits a later coherent revision of that same acoustic interval.
            frontier = newestEnd
            let newest = current.filter { $0.end == newestEnd }
            // Conflicting identities on the same final acoustic interval do
            // not authorize picking a page according to collection order.
            if let word = newest.first, newest.allSatisfy({
                $0.nativeID == word.nativeID && $0.verse == word.verse && $0.start == word.start
            }) {
                anchor = word; verse = word.verse
            } else { anchor = nil }
        }
        guard let anchor, current.contains(where: {
            $0.nativeID == anchor.nativeID && $0.verse == anchor.verse
                && $0.start == anchor.start && $0.end == anchor.end
        }) else { activeNativeID = nil; return }
        activeNativeID = anchor.nativeID
    }
}
