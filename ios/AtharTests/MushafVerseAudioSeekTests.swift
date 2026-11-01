import XCTest
@testable import Athar

/// The epoch cases exercise production ownership without inventing audio.
/// The separate actual-file case requires AVPlayer; none establish physical
/// speaker output, learner recognition accuracy or all-recording alignment.
final class MushafVerseAudioSeekTests: XCTestCase {
    @MainActor func testActualNonzeroFixtureStartPublishesOnlyTheObservedSeekClock() async throws {
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "112001", withExtension: "mp3"))
        let audio = MushafVerseAudio(source: { _ in fixture })
        let started = expectation(description: "Actual file starts after its initial seek")
        var observedSeconds: Double?
        audio.onVerse = { [weak audio] key in
            XCTAssertEqual(key, "112:1")
            observedSeconds = audio?.currentSeconds
            started.fulfill()
        }
        defer { audio.onVerse = nil; audio.stop() }
        audio.play(["112:1"], seconds: 1)
        await fulfillment(of: [started], timeout: 15)
        XCTAssertNil(audio.error, audio.playbackDiagnostic)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(observedSeconds), 0.95,
                                    "A playback-start event at zero would move the reader to the wrong page")
    }

    func testNonzeroInitialPositionCannotPlayBeforeItsSeekCompletes() throws {
        var clock = MushafPlaybackClockEpoch()
        clock.prepareInitialPosition(42.75)
        XCTAssertTrue(clock.requiresInitialSeek)
        XCTAssertFalse(clock.permitsPlayback)
        XCTAssertNil(clock.observationToken)
        let seek = clock.beginSeek(to: 42.75)
        XCTAssertFalse(clock.requiresInitialSeek)
        XCTAssertFalse(clock.permitsPlayback)
        XCTAssertTrue(clock.endSeek(seek))
        XCTAssertTrue(clock.permitsPlayback)
        XCTAssertTrue(clock.awaitingInitialClock)
    }

    func testInitialPositionRequiresAnActualObservedMediaClock() throws {
        var clock = MushafPlaybackClockEpoch()
        clock.prepareInitialPosition(42.75)
        let seek = clock.beginSeek(to: 42.75)
        XCTAssertFalse(clock.recordObservedClock(42.75), "A requested time is not an observation while seeking")
        XCTAssertTrue(clock.endSeek(seek))
        XCTAssertFalse(clock.recordObservedClock(0))
        XCTAssertFalse(clock.recordObservedClock(42.69))
        XCTAssertFalse(clock.recordObservedClock(.nan))
        XCTAssertTrue(clock.awaitingInitialClock)
        XCTAssertTrue(clock.recordObservedClock(42.75))
        XCTAssertFalse(clock.awaitingInitialClock)
    }

    func testReplacementInitialSeekKeepsItsOwnObservedClockFloor() throws {
        var clock = MushafPlaybackClockEpoch()
        clock.prepareInitialPosition(10)
        let old = clock.beginSeek(to: 10)
        let current = clock.beginSeek(to: 80)
        XCTAssertFalse(clock.endSeek(old))
        XCTAssertFalse(clock.permitsPlayback)
        XCTAssertTrue(clock.endSeek(current))
        XCTAssertFalse(clock.recordObservedClock(10))
        XCTAssertTrue(clock.recordObservedClock(80))
    }

    func testReleasedInitialPositionCannotConstrainItsReplacementPlayer() throws {
        var clock = MushafPlaybackClockEpoch()
        clock.prepareInitialPosition(80)
        let old = clock.beginSeek(to: 80)
        clock.invalidate()
        XCTAssertFalse(clock.endSeek(old))
        XCTAssertFalse(clock.requiresInitialSeek)
        XCTAssertFalse(clock.awaitingInitialClock)
        XCTAssertTrue(clock.permitsPlayback)
        XCTAssertTrue(clock.recordObservedClock(0))
    }

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
