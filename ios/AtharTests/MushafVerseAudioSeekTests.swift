import XCTest
@testable import Athar

/// These exercise the same epoch used by the real AVPlayer observers. They
/// establish ownership only, never actual media playback or acoustic accuracy.
final class MushafVerseAudioSeekTests: XCTestCase {
    func testPreSeekObservationCannotRestoreAWordDuringOrAfterSeek() throws {
        var clock = MushafPlaybackClockEpoch()
        let oldObservation = try XCTUnwrap(clock.observationToken)
        let seek = clock.beginSeek()
        XCTAssertNil(clock.observationToken)
        XCTAssertFalse(clock.acceptsObservation(oldObservation))
        XCTAssertTrue(clock.endSeek(seek))
        XCTAssertFalse(clock.acceptsObservation(oldObservation))
        XCTAssertTrue(clock.acceptsObservation(try XCTUnwrap(clock.observationToken)))
    }

    func testOlderSeekCompletionCannotFinishItsReplacement() throws {
        var clock = MushafPlaybackClockEpoch()
        let first = clock.beginSeek()
        let second = clock.beginSeek()
        XCTAssertFalse(clock.endSeek(first))
        XCTAssertNil(clock.observationToken)
        XCTAssertTrue(clock.endSeek(second))
        XCTAssertFalse(clock.acceptsObservation(first))
        XCTAssertTrue(clock.acceptsObservation(second))
    }

    func testReleasedPlayerInvalidatesBothPendingSeekAndQueuedObservation() throws {
        var clock = MushafPlaybackClockEpoch()
        let observation = try XCTUnwrap(clock.observationToken)
        let seek = clock.beginSeek()
        clock.invalidate()
        XCTAssertFalse(clock.endSeek(seek))
        XCTAssertFalse(clock.acceptsObservation(observation))
        XCTAssertFalse(clock.acceptsObservation(seek))
        XCTAssertTrue(clock.acceptsObservation(try XCTUnwrap(clock.observationToken)))
    }

    func testEachSeekCompletionCanSettleOnlyOnce() throws {
        var clock = MushafPlaybackClockEpoch()
        let seek = clock.beginSeek()
        XCTAssertTrue(clock.endSeek(seek))
        XCTAssertFalse(clock.endSeek(seek))
        XCTAssertTrue(clock.acceptsObservation(try XCTUnwrap(clock.observationToken)))
    }
}
