import XCTest
@testable import Athar

final class QuranGuidedPracticeTests: XCTestCase {
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
