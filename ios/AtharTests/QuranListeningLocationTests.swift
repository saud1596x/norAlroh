import XCTest
@testable import Athar

/// Injected source metadata tests display policy, not microphone/ASR accuracy.
final class QuranListeningLocationTests: XCTestCase {
    private let take = UUID()
    private func word(_ id: Int, _ verse: String, _ start: Double, _ end: Double, takeID: UUID? = nil) -> QuranWordEvidence {
        .init(nativeID: id, verse: verse, takeID: takeID ?? take, start: start, end: end, minimumConfidence: 0.99)
    }
    func testOverlapRevisionCannotMoveDisplayBackToOlderAudioOrKeepRetractedHighlight() {
        var location = QuranListeningLocation(); location.begin(takeID: take)
        let old = word(3, "1:2", 1, 2), latest = word(8, "1:3", 4, 5)
        location.update([old, latest]); XCTAssertEqual(location.verse, "1:3")
        XCTAssertEqual(location.activeNativeID, 8)
        location.update([old])
        XCTAssertEqual(location.verse, "1:3", "Last location is display history, not accepted recitation evidence")
        XCTAssertNil(location.activeNativeID, "Withdrawn evidence cannot remain highlighted as heard")
        location.update([]); XCTAssertEqual(location.verse, "1:3"); XCTAssertNil(location.activeNativeID)
    }
    func testActualLaterReturnAndRepetitionUseTheirNewAudioClockWithoutForcingForwardVerses() {
        var location = QuranListeningLocation(); location.begin(takeID: take)
        location.update([word(8, "1:3", 4, 5)])
        location.update([word(3, "1:2", 6, 7)])
        XCTAssertEqual(location.verse, "1:2"); XCTAssertEqual(location.activeNativeID, 3)
        location.update([word(4, "1:2", 8, 9)])
        XCTAssertEqual(location.verse, "1:2"); XCTAssertEqual(location.activeNativeID, 4)
    }
    func testNewTakeCannotUseOldSessionEvidenceAndRestartsOnlyTheAcousticClock() {
        var location = QuranListeningLocation(); location.begin(takeID: take)
        let previous = word(8, "1:3", 30, 31); location.update([previous])
        let next = UUID(); location.begin(takeID: next)
        location.update([previous]); XCTAssertEqual(location.verse, "1:3"); XCTAssertNil(location.activeNativeID)
        location.update([previous, word(2, "1:1", 0.1, 0.5, takeID: next)])
        XCTAssertEqual(location.verse, "1:1"); XCTAssertEqual(location.activeNativeID, 2)
    }
    func testUnorderedEvidenceAndConflictingFinalIntervalsCannotSelectByArrayPosition() {
        var location = QuranListeningLocation(); location.begin(takeID: take)
        let old = word(3, "1:2", 1, 2), latest = word(8, "1:3", 4, 5)
        location.update([latest, old]); XCTAssertEqual(location.activeNativeID, 8)
        location.update([old, word(11, "1:4", 7, 8), word(22, "2:2", 7, 8)])
        XCTAssertEqual(location.verse, "1:3"); XCTAssertNil(location.activeNativeID)
    }
}
