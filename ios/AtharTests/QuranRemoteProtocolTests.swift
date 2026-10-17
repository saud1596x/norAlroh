import XCTest
@testable import Athar

final class QuranRemoteProtocolTests: XCTestCase {
    func testCloudConsentDoesNotTransferToGuestOrAnotherAppleIdentity() throws {
        let suite = "noor.remote-consent-test." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName:suite))
        defer { defaults.removePersistentDomain(forName:suite) }
        QuranRemoteConsent.configure(true, owner:"first-test-user", defaults:defaults)
        XCTAssertTrue(QuranRemoteConsent.permits(owner:"first-test-user", defaults:defaults))
        XCTAssertFalse(QuranRemoteConsent.permits(owner:"second-test-user", defaults:defaults))
        XCTAssertFalse(QuranRemoteConsent.permits(owner:nil, defaults:defaults))
        QuranRemoteConsent.configure(false, owner:nil, defaults:defaults)
        XCTAssertFalse(QuranRemoteConsent.permits(owner:"first-test-user", defaults:defaults))
    }
    private func events(ids: [Int] = [1, 2], source: String = "1968cf3a4e8338ae2056b5fba309099d2f7645b1609062cc1a52eac1804c5951") throws -> [QuranRemoteEventReducer.Event] {
        let value: [[String: Any]] = ids.enumerated().map { index, id in [
            "schema_version":1, "event_id":id, "type":index == 0 ? "AUDIO_ACCEPTED" : "PARTIAL_RECOGNITION",
            "session_id":"local-contract-test", "audio_sequence":0, "audio_start_frame":0, "audio_end_frame":16000,
            "engine_version":"noor-session-1", "model_id":"OdyAsh/faster-whisper-base-ar-quran",
            "model_revision":"8578bafd427d122f671b187706650e76edf6f86f", "corpus_version":source] }
        return try JSONDecoder().decode([QuranRemoteEventReducer.Event].self, from: JSONSerialization.data(withJSONObject:value))
    }
    func testSourceAndContiguousOrderingAreTransactional() throws {
        var reducer = QuranRemoteEventReducer()
        XCTAssertThrowsError(try reducer.consume(events(ids:[1,3]), session:"local-contract-test", sequence:0, startFrame:0, endFrame:16000))
        XCTAssertEqual(reducer.lastEventID,0)
        try reducer.consume(events(), session:"local-contract-test", sequence:0, startFrame:0, endFrame:16000)
        XCTAssertEqual(reducer.lastEventID,2)
        XCTAssertThrowsError(try reducer.consume(events(), session:"local-contract-test", sequence:0, startFrame:0, endFrame:16000))
        XCTAssertEqual(reducer.lastEventID,2)
    }
    func testAnotherEditionOrTakeCannotRevealWords() throws {
        var reducer = QuranRemoteEventReducer()
        XCTAssertThrowsError(try reducer.consume(events(source:"other-edition"), session:"local-contract-test", sequence:0, startFrame:0, endFrame:16000))
        XCTAssertThrowsError(try reducer.consume(events(), session:"another-session", sequence:0, startFrame:0, endFrame:16000))
        XCTAssertThrowsError(try reducer.consume(events(), session:"local-contract-test", sequence:1, startFrame:0, endFrame:16000))
        XCTAssertEqual(reducer.lastEventID,0)
    }
    func testOnlyExplicitCredentialFreeHTTPSConfigurationIsAccepted() {
        for value in ["http://127.0.0.1:8000", "https://user:secret@example.com", "https://example.com?token=secret", "https://example.com/inference"] {
            XCTAssertNil(QuranRemoteRecognitionConfiguration(url:URL(string:value)!))
        }
        XCTAssertNotNil(QuranRemoteRecognitionConfiguration(url:URL(string:"https://example.com")!))
    }
}
