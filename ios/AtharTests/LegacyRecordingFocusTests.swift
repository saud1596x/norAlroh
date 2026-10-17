import XCTest
@testable import Athar

/// Ownership tests do not substitute media samples or claim microphone success.
final class LegacyRecordingFocusTests: XCTestCase {
    @MainActor func testIdleLegacyStopDoesNotDeactivateAnotherAudioOwner() {
        var activations: [Bool] = []
        let legacy = LocalRecitationRecorder(setSessionActive: { activations.append($0) })
        let owner = UUID()
        XCTAssertTrue(NoorAudioFocus.shared.acquireRecording(owner))
        defer { NoorAudioFocus.shared.releaseRecording(owner) }
        legacy.stop()
        legacy.stop()
        XCTAssertTrue(activations.isEmpty, "An idle disappearing view cannot deactivate another capture")
        XCTAssertFalse(NoorAudioFocus.shared.preparePlayback(UUID()), "Idle cleanup cannot release someone else's lease")
    }

    @MainActor func testLegacyStartCannotTakeAudioFromActiveRecitation() async {
        var activations: [Bool] = []
        let legacy = LocalRecitationRecorder(permission: { true }, isActive: { true },
            setSessionActive: { activations.append($0) })
        let owner = UUID()
        XCTAssertTrue(NoorAudioFocus.shared.acquireRecording(owner))
        defer { NoorAudioFocus.shared.releaseRecording(owner) }
        await legacy.start()
        XCTAssertFalse(legacy.recording)
        XCTAssertFalse(legacy.requestingPermission)
        XCTAssertNotNil(legacy.message)
        XCTAssertTrue(activations.isEmpty, "Competing recording must be rejected before changing the system session")
        XCTAssertFalse(NoorAudioFocus.shared.preparePlayback(UUID()))
    }
}
