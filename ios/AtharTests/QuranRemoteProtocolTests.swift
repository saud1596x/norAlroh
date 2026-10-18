import XCTest
@testable import Athar

final class QuranRemoteProtocolTests: XCTestCase {
    private final class Preference: @unchecked Sendable {
        private let lock = NSLock()
        private var enabled = false
        func read() -> Bool { lock.lock(); defer { lock.unlock() }; return enabled }
        func write(_ value: Bool) { lock.lock(); defer { lock.unlock() }; enabled = value }
    }
    private actor PolicyProvider: QuranSpeechRecognitionProvider {
        nonisolated let capabilities: QuranRecognitionCapabilities
        private(set) var decodes = 0
        private(set) var endings = 0
        init(id: String, local: Bool) {
            capabilities = .init(backendID: id, modelID: id, modelRevision: "policy-fixture",
                configuredLanguage: "ar", delivery: .overlappingAudioWindows, processesLocally: local,
                wordTimestamps: true, wordConfidence: true, phonemeEvidence: false,
                calibratedWordingAssessment: false, validatedTajweedAssessment: false)
        }
        func prepare() async throws {}
        func recognize(_ window: QuranAudioWindow) async throws -> QuranRecognitionWorker.Result {
            decodes += 1; return .init(runs: [], hasUnresolvedSpeech: false)
        }
        func endTake() async { endings += 1 }
    }
    func testChangingPreferenceCannotRelabelAnAlreadyLocalTakeAsRemote() async throws {
        let preference = Preference()
        let local = PolicyProvider(id: "local-policy-fixture", local: true)
        let remote = PolicyProvider(id: "remote-policy-fixture", local: false)
        let router = QuranRecognitionRouter(local: local, remoteAllowed: { preference.read() }, makeRemote: { remote })
        try await router.prepare()
        preference.write(true)
        let window = QuranAudioWindow(samples: [0.06], startFrame: 0, endFrame: 1)
        _ = try await router.recognize(window)
        XCTAssertEqual(router.capabilities.backendID, "local-policy-fixture")
        let localCalls = await local.decodes, remoteCalls = await remote.decodes
        XCTAssertEqual(localCalls, 1); XCTAssertEqual(remoteCalls, 0)
        await router.endTake(); try await router.prepare()
        _ = try await router.recognize(window)
        XCTAssertEqual(router.capabilities.backendID, "remote-policy-fixture")
        let nextRemoteCalls = await remote.decodes
        XCTAssertEqual(nextRemoteCalls, 1)
        await router.endTake()
    }
    func testRevokingRemoteConsentStopsBeforeAnotherWindowIsSent() async throws {
        let preference = Preference(); preference.write(true)
        let local = PolicyProvider(id: "local-policy-fixture", local: true)
        let remote = PolicyProvider(id: "remote-policy-fixture", local: false)
        let router = QuranRecognitionRouter(local: local, remoteAllowed: { preference.read() }, makeRemote: { remote })
        try await router.prepare(); preference.write(false)
        do {
            _ = try await router.recognize(.init(samples: [0.06], startFrame: 0, endFrame: 1))
            XCTFail("Revoked consent must not upload or silently reclassify a window")
        } catch QuranRemoteRecognitionFailure.consentRequired {}
        XCTAssertEqual(router.capabilities.backendID, "local-policy-fixture")
        let remoteCalls = await remote.decodes, endings = await remote.endings
        XCTAssertEqual(remoteCalls, 0); XCTAssertEqual(endings, 1)
    }
    func testStreamClockConversionDoesNotRejectAZeroOffsetThroughRounding() throws {
        let start = Double(29-2) / 16000
        let source = QuranRemoteWordEvidence.Observation(occurrence_index: 0, run_index: 0, text: "قل",
            start: start, end: start+0.2, confidence: 0.99, recognition_state: "accepted")
        let window = QuranAudioWindow(samples: Array(repeating: 0.06, count: 16_000), startFrame: 29, endFrame: 16_029)
        let result = try QuranRemoteWordEvidence.resolve(words: accepted([source]), observations: [source],
            window: window, baseFrame: 2, unresolved: false)
        XCTAssertEqual(result.runs.first?.first?.start, 0)
        XCTAssertEqual(result.observations?.first?.startInTakeSeconds, window.offset)
    }
    private func source(_ texts: [String], rejected: Set<Int> = []) -> [QuranRemoteWordEvidence.Observation] {
        var run = 0
        return texts.enumerated().map { index, text in
            let value = QuranRemoteWordEvidence.Observation(occurrence_index: index, run_index: run, text: text,
                start: 1 + Double(index) * 0.3, end: 1.2 + Double(index) * 0.3,
                confidence: rejected.contains(index) ? 0.4 : 0.99,
                recognition_state: rejected.contains(index) ? "unassessable" : "accepted")
            if rejected.contains(index) { run += 1 }
            return value
        }
    }
    private func accepted(_ observations: [QuranRemoteWordEvidence.Observation]) -> [QuranRemoteWordEvidence.Word] {
        observations.filter { $0.recognition_state == "accepted" }.map {
            .init(text: $0.text, start: $0.start!, end: $0.end!, confidence: $0.confidence!, run_index: $0.run_index)
        }
    }
    func testUncertainRemoteWordSeparatesRunsAndPreservesSourceInsteadOfFillingReference() throws {
        let observations = source(["قل", "هو", "سيارة", "الله", "أحد"], rejected: [2])
        // Policy-only PCM fixture, not microphone or acoustic accuracy evidence.
        let window = QuranAudioWindow(samples: Array(repeating: 0.06, count: 64_000), startFrame: 32_000, endFrame: 96_000)
        let result = try QuranRemoteWordEvidence.resolve(words: accepted(observations), observations: observations,
            window: window, baseFrame: 16_000, unresolved: true)
        XCTAssertEqual(result.runs.map { $0.map(\.text) }, [["قل", "هو"], ["الله", "أحد"]])
        XCTAssertEqual(result.observations?.map(\.observedText), ["قل", "هو", "سيارة", "الله", "أحد"])
        XCTAssertEqual(result.observations?[2].recognitionState, "unassessable")
        XCTAssertEqual(result.observations?[2].backendConfidence, 0.4)
        XCTAssertEqual(try XCTUnwrap(result.observations?[2].startInTakeSeconds), 2.6, accuracy: 0.00001)
    }
    func testRemoteTextCannotReplaceOrForgeItsIndependentWordObservations() throws {
        let observations = source(["قل", "هو", "الله", "أحد"])
        var words = accepted(observations)
        words[2] = .init(text: "سيارة", start: words[2].start, end: words[2].end, confidence: 0.99, run_index: 0)
        let window = QuranAudioWindow(samples: Array(repeating: 0.06, count: 64_000), startFrame: 0, endFrame: 64_000)
        XCTAssertThrowsError(try QuranRemoteWordEvidence.resolve(words: words, observations: observations,
            window: window, baseFrame: 0, unresolved: false))
        XCTAssertThrowsError(try QuranRemoteWordEvidence.resolve(words: accepted(observations), observations: [],
            window: window, baseFrame: 0, unresolved: false))
    }
    func testRemoteConfidenceNeverOverridesActualSilentPCM() throws {
        let observations = source(["قل", "هو", "الله", "أحد"])
        let window = QuranAudioWindow(samples: Array(repeating: 0, count: 64_000), startFrame: 0, endFrame: 64_000)
        let result = try QuranRemoteWordEvidence.resolve(words: accepted(observations), observations: observations,
            window: window, baseFrame: 0, unresolved: false)
        XCTAssertTrue(result.runs.isEmpty); XCTAssertTrue(result.hasUnresolvedSpeech)
        XCTAssertEqual(result.observations?.count, 4)
        XCTAssertTrue(result.observations?.allSatisfy { $0.recognitionState == "unassessable" } == true)
    }
    func testUntimedRejectedRemoteObservationSurvivesWithoutInventedTimestamps() throws {
        let source = QuranRemoteWordEvidence.Observation(occurrence_index: 0, run_index: 0, text: "كلام",
            start: nil, end: nil, confidence: nil, recognition_state: "unassessable")
        let window = QuranAudioWindow(samples: Array(repeating: 0.06, count: 16_000), startFrame: 0, endFrame: 16_000)
        let result = try QuranRemoteWordEvidence.resolve(words: [], observations: [source],
            window: window, baseFrame: 0, unresolved: true)
        XCTAssertTrue(result.runs.isEmpty); XCTAssertNil(result.observations?.first?.startInTakeSeconds)
        XCTAssertEqual(result.observations?.first?.timingSource, "unavailable")
    }
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
