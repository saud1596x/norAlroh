import XCTest
@testable import Athar

final class QuranGuidedPracticeTests: XCTestCase {
    @MainActor func testStoppingActualReferenceDuringPreparationDoesNotWaitForMediaTiming() async throws {
        let file = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "112001", withExtension: "mp3"))
        let player = MushafVerseAudio(source: { _ in file })
        var finished = false
        player.play(["112:1"], onFinished: { finished = true })
        let started = Date()
        player.stop()
        XCTAssertLessThan(Date().timeIntervalSince(started), 2,
            "Stop must not synchronously wait for unloaded media timing")
        XCTAssertNil(player.playing)
        XCTAssertNil(player.loadingKey)
        XCTAssertEqual(player.currentSeconds, 0)
        XCTAssertEqual(player.durationSeconds, 0)
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertFalse(finished, "Stopping is not evidence that the reference was heard")
        XCTAssertNil(player.playing, "Late readiness callbacks cannot restart a stopped item")
        XCTAssertEqual(player.currentSeconds, 0)
    }
    @MainActor func testReplacingOrStoppingReferenceCannotFinishAnUnheardGuide() {
        let controller = QuranRecitationController(requestPermission: { false })
        let player = MushafVerseAudio(resolveSource: { _ in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            return nil
        })
        defer { controller.cancelGuided(); player.stop() }
        controller.listenFirst(["112:1"], audio: player, repetitions: 1, responsePause: 1)
        player.play(["112:2"])
        XCTAssertEqual(controller.guidedPhase, .inactive,
            "An unrelated sequence must never invoke the earlier guide's completion")
        XCTAssertNil(controller.record)
        controller.listenFirst(["112:1"], audio: player, repetitions: 1, responsePause: 1)
        player.stop()
        XCTAssertEqual(controller.guidedPhase, .inactive)
        XCTAssertNil(controller.record)
    }
    @MainActor func testAsynchronousReferenceFailureReleasesGuidedGateWithoutOpeningMicrophone() async throws {
        var permissionRequests = 0
        let controller = QuranRecitationController(requestPermission: { permissionRequests += 1; return false })
        let player = MushafVerseAudio(resolveSource: { _ in await Task.yield(); return nil })
        defer { controller.cancelGuided(); player.stop() }
        controller.listenFirst(["112:1"], audio: player, repetitions: 1, responsePause: 1)
        XCTAssertEqual(controller.guidedPhase, .reference)
        let deadline = Date().addingTimeInterval(2)
        while controller.guidedPhase == .reference && Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertNotNil(player.error)
        XCTAssertNotNil(controller.message)
        XCTAssertEqual(controller.guidedPhase, .inactive)
        XCTAssertEqual(controller.state, .idle)
        XCTAssertNil(controller.record)
        XCTAssertEqual(permissionRequests, 0)
        controller.listenFirst(["112:1"], audio: player, repetitions: 1, responsePause: 1)
        XCTAssertEqual(controller.guidedPhase, .reference, "A stale published error must not reject an explicit retry")
        XCTAssertNil(controller.message)
    }
    @MainActor func testCancelledReferenceFailureCannotCancelAReplacementGuide() async throws {
        let controller = QuranRecitationController(requestPermission: { false })
        let old = MushafVerseAudio(resolveSource: { _ in
            try? await Task.sleep(nanoseconds: 100_000_000)
            return nil
        })
        let replacement = MushafVerseAudio(resolveSource: { _ in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            return nil
        })
        defer { controller.cancelGuided(); old.stop(); replacement.stop() }
        controller.listenFirst(["112:1"], audio: old, repetitions: 1, responsePause: 1)
        controller.listenFirst(["112:1"], audio: replacement, repetitions: 1, responsePause: 1)
        // Simulates an asynchronously published failure from the replaced
        // player, not a fabricated recognition result or microphone sample.
        old.error = "Previous reference failed"
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(controller.guidedPhase, .reference)
        XCTAssertNil(controller.message)
        XCTAssertNil(controller.record)
    }
    @MainActor func testActualReferencePlaybackNeverOpensMicrophoneOrAwardsProgress() async throws {
        let file = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "112001", withExtension: "mp3"))
        var permissionRequests = 0
        let controller = QuranRecitationController(requestPermission: { permissionRequests += 1; return false })
        let player = MushafVerseAudio(source: { _ in file })
        defer { controller.cancelGuided(); player.stop() }
        controller.listenFirst(["112:1"], audio: player, repetitions: 1, responsePause: 1)
        XCTAssertEqual(controller.guidedPhase, .reference)
        let deadline = Date().addingTimeInterval(25)
        while controller.guidedPhase != .ready && Date() < deadline && player.error == nil {
            XCTAssertNil(controller.record)
            XCTAssertTrue(controller.revealed.isEmpty)
            XCTAssertEqual(permissionRequests, 0)
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertNil(player.error, player.playbackDiagnostic)
        XCTAssertEqual(controller.guidedPhase, .ready, player.playbackDiagnostic)
        XCTAssertEqual(permissionRequests, 0, "Reference playback must not start a learner microphone")
        XCTAssertNil(controller.record, "Pressing play cannot create independent recall evidence")
        XCTAssertTrue(controller.revealed.isEmpty)
    }
}
