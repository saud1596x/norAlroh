import XCTest
import AVFoundation
import WhisperKit
@testable import Athar

/// Injected lifecycle notifications and identified reference PCM. These tests
/// do not connect Bluetooth hardware or claim to exercise an iPhone microphone.
final class QuranMicrophoneInputLifecycleTests: XCTestCase {
    @MainActor func testLiveCaptureRequestsInputOnlyMeasurementWithoutSpeakerPlayback() async throws {
        // Actual AVAudioSession policy, injected empty capture. This does not
        // claim that physical/Simulator hardware opened or recognized speech.
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var inspected = false
        let controller = QuranRecitationController(requestPermission: { true }, archiveRoot: root,
            makeCapture: { writer, _ in
                inspected = true
                let session = AVAudioSession.sharedInstance()
                XCTAssertEqual(session.category, .record)
                XCTAssertEqual(session.mode, .measurement)
                XCTAssertFalse(session.categoryOptions.contains(.defaultToSpeaker))
                return EmptyPolicyCapture(writer: writer)
            }, setSessionActive: { _ in })
        let snapshot = try JSONDecoder().decode(QCFV2Snapshot.self, from: XCTUnwrap(QCFV2ContentCache.bundledSnapshot())).validated()
        await controller.start(keys: ["112:1"], page: 604, snapshot: snapshot, corpus: try XCTUnwrap(QuranResources.corpus))
        XCTAssertTrue(inspected); XCTAssertEqual(controller.state, .listening)
        await controller.finish(); XCTAssertTrue(controller.revealed.isEmpty)
    }
    private final class EmptyPolicyCapture: QuranAudioCapture {
        private let writer: QuranPCMWriter
        init(writer: QuranPCMWriter) { self.writer = writer }
        func start() throws {}
        func stop() async -> Result<Int64, Error> {
            await withCheckedContinuation { reply in writer.finish { reply.resume(returning: $0) } }
        }
    }

    func testDeviceSampleClockRejectsMissingDuplicatedAndReorderedInputBeforeJoiningPCM() throws {
        for nextStart in [Int64(8_191), 8_193, 4_096] {
            var clock = QuranCaptureClock()
            try clock.consume(frames: 4_096, rate: 48_000, sampleTime: 4_096, sampleRate: 48_000, hostTime: nil)
            XCTAssertThrowsError(try clock.consume(frames: 4_096, rate: 48_000,
                sampleTime: nextStart, sampleRate: 48_000, hostTime: nil))
            // A rejected input never advances the accepted device clock.
            XCTAssertNoThrow(try clock.consume(frames: 2_048, rate: 48_000,
                sampleTime: 8_192, sampleRate: 48_000, hostTime: nil))
        }
        var clock = QuranCaptureClock()
        try clock.consume(frames: 512, rate: 44_100, sampleTime: -512, sampleRate: 44_100, hostTime: nil)
        try clock.consume(frames: 1_024, rate: 44_100, sampleTime: 0, sampleRate: 44_100, hostTime: nil)
        XCTAssertThrowsError(try clock.consume(frames: 512, rate: 48_000, sampleTime: 1_024, sampleRate: 48_000, hostTime: nil))
        XCTAssertThrowsError(try clock.consume(frames: 512, rate: 44_100, sampleTime: nil, sampleRate: nil, hostTime: 100))
    }

    func testHostOnlyAcousticClockUsesDeviceTicksAndDoesNotGuessMissingTimestamps() throws {
        let origin = AVAudioTime.hostTime(forSeconds: 10)
        var clock = QuranCaptureClock()
        try clock.consume(frames: 4_800, rate: 48_000, sampleTime: nil, sampleRate: nil, hostTime: origin)
        let next = origin + AVAudioTime.hostTime(forSeconds: 0.1)
        try clock.consume(frames: 4_800, rate: 48_000, sampleTime: nil, sampleRate: nil, hostTime: next)
        XCTAssertThrowsError(try clock.consume(frames: 4_800, rate: 48_000,
            sampleTime: nil, sampleRate: nil, hostTime: origin + AVAudioTime.hostTime(forSeconds: 0.3)))
        XCTAssertThrowsError(try clock.consume(frames: 4_800, rate: 48_000,
            sampleTime: nil, sampleRate: nil, hostTime: nil))
        var unstamped = QuranCaptureClock()
        XCTAssertThrowsError(try unstamped.consume(frames: 512, rate: 48_000, sampleTime: nil, sampleRate: nil, hostTime: nil))
        var overflow = QuranCaptureClock()
        XCTAssertThrowsError(try overflow.consume(frames: 512, rate: 48_000, sampleTime: .max, sampleRate: 48_000, hostTime: nil))
    }
    @MainActor func testBackgroundInputNotificationCanHandOffToMainActor() async {
        let center = NotificationCenter(), engine = NSObject()
        let received = expectation(description: "Background input failure reaches the UI actor")
        let events = QuranAudioInputEvents(engine: engine, center: center) { error in
            Task { @MainActor in
                XCTAssertTrue(error is QuranAudioInputFailure)
                received.fulfill()
            }
        }
        events.arm()
        DispatchQueue.global().async {
            center.post(name: .AVAudioEngineConfigurationChange, object: engine)
        }
        await fulfillment(of: [received], timeout: 3)
        withExtendedLifetime(events) {}
    }

    func testEngineConfigurationChangeReportsOwnedInputLossOnlyOnceWhileArmed() {
        let center = NotificationCenter(), engine = NSObject(), otherEngine = NSObject()
        var failures = 0
        let events = QuranAudioInputEvents(engine: engine, center: center) { error in
            XCTAssertTrue(error is QuranAudioInputFailure); failures += 1
        }
        center.post(name: .AVAudioEngineConfigurationChange, object: engine)
        XCTAssertEqual(failures, 0, "Inactive takes must ignore engine notifications")
        events.arm()
        center.post(name: .AVAudioEngineConfigurationChange, object: otherEngine)
        XCTAssertEqual(failures, 0, "Another player's engine must not stop this microphone take")
        center.post(name: .AVAudioEngineConfigurationChange, object: engine)
        center.post(name: .AVAudioEngineConfigurationChange, object: engine)
        XCTAssertEqual(failures, 1)
        events.arm(); events.disarm()
        center.post(name: .AVAudioEngineConfigurationChange, object: engine)
        XCTAssertEqual(failures, 1, "Shutdown notifications must not request another pause")
    }

    func testNewAndRemovedInputRoutesAndMediaServiceLossRequireExplicitResume() {
        let reasons: [AVAudioSession.RouteChangeReason] = [.newDeviceAvailable, .oldDeviceUnavailable,
            .routeConfigurationChange, .noSuitableRouteForCategory]
        for reason in reasons {
            let center = NotificationCenter(), engine = NSObject()
            var failures = 0
            let events = QuranAudioInputEvents(engine: engine, center: center) { _ in failures += 1 }
            events.arm()
            center.post(name: AVAudioSession.routeChangeNotification, object: nil,
                userInfo: [AVAudioSessionRouteChangeReasonKey: reason.rawValue])
            center.post(name: .AVAudioEngineConfigurationChange, object: engine)
            XCTAssertEqual(failures, 1, "Route plus engine events must close the same take once")
        }
        for name in [AVAudioSession.mediaServicesWereLostNotification, AVAudioSession.mediaServicesWereResetNotification] {
            let center = NotificationCenter(), engine = NSObject()
            var failures = 0
            let events = QuranAudioInputEvents(engine: engine, center: center) { _ in failures += 1 }
            events.arm(); center.post(name: name, object: nil)
            XCTAssertEqual(failures, 1)
        }
    }

    @MainActor func testConfigurationEventDuringStartPausesActualReferenceAudioAndRouteChangeOnResumePreservesBothTakes() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let bytes = try XCTUnwrap(QCFV2ContentCache.bundledSnapshot())
        let snapshot = try JSONDecoder().decode(QCFV2Snapshot.self, from: bytes).validated()
        let corpus = try XCTUnwrap(QuranResources.corpus)
        let reference = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "112001", withExtension: "mp3"))
        let samples = try AudioProcessor.loadAudioAsFloatArray(fromPath: reference.path)
        var captureCount = 0
        let controller = QuranRecitationController(requestPermission: { true }, archiveRoot: root,
            recognizeWindow: { _ in .init(runs: [], hasUnresolvedSpeech: true) },
            makeCapture: { writer, failure in
                captureCount += 1
                return NotificationCapture(writer: writer, samples: samples,
                    changeRoute: captureCount > 1, onFailure: failure)
            }, setSessionActive: { _ in })
        await controller.start(keys: ["112:1"], page: 604, snapshot: snapshot, corpus: corpus)
        try await waitForPause(controller)
        XCTAssertNotNil(controller.message)
        let firstRecord = try XCTUnwrap(controller.record)
        let firstTake = try XCTUnwrap(firstRecord.takes.first)
        XCTAssertTrue(firstTake.closed)
        XCTAssertEqual(firstTake.frames, Int64(samples.count))
        XCTAssertTrue(controller.hiddenIDs.isEmpty)
        let journal = QuranRecitationJournal(root: root)
        let firstURL = journal.audio(session: firstRecord.id, take: firstTake.id)
        XCTAssertEqual(try AudioProcessor.loadAudioAsFloatArray(fromPath: firstURL.path), samples)
        let preserved = try Data(contentsOf: firstURL)
        await controller.resume()
        try await waitForPause(controller)
        XCTAssertEqual(controller.record?.takes.count, 2, "Explicit resume creates a new take, not a claimed engine restart")
        let saved = try journal.load(firstRecord.id)
        XCTAssertEqual(saved.phase, .paused)
        XCTAssertTrue(saved.takes.allSatisfy { $0.closed && $0.frames == Int64(samples.count) })
        XCTAssertEqual(try Data(contentsOf: firstURL), preserved)
        XCTAssertTrue(saved.evidence.isEmpty, "Injected lifecycle events and empty recognition are not ASR proof")
    }

    @MainActor private func waitForPause(_ controller: QuranRecitationController) async throws {
        let deadline = Date().addingTimeInterval(10)
        while controller.state != .paused && Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(controller.state, .paused, "A stopped input engine must not remain listening without PCM")
    }

    private final class NotificationCapture: QuranAudioCapture {
        private let center: NotificationCenter
        private let engine: NSObject
        private let writer: QuranPCMWriter
        private let samples: [Float]
        private let changeRoute: Bool
        private let events: QuranAudioInputEvents
        init(writer: QuranPCMWriter, samples: [Float], changeRoute: Bool, onFailure: @escaping (Error) -> Void) {
            let center = NotificationCenter(), engine = NSObject()
            self.center = center; self.engine = engine
            self.writer = writer; self.samples = samples; self.changeRoute = changeRoute
            events = QuranAudioInputEvents(engine: engine, center: center, onFailure: onFailure)
        }
        func start() throws {
            events.arm()
            for start in stride(from: 0, to: samples.count, by: 16_000) {
                writer.append(Array(samples[start..<min(start + 16_000, samples.count)]))
            }
            // Synchronous notification before start returns reproduces the
            // startup-boundary race without pretending an AVAudioEngine ran.
            if changeRoute {
                center.post(name: AVAudioSession.routeChangeNotification, object: nil,
                    userInfo: [AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.newDeviceAvailable.rawValue])
            } else { center.post(name: .AVAudioEngineConfigurationChange, object: engine) }
        }
        func stop() async -> Result<Int64, Error> {
            events.disarm()
            return await withCheckedContinuation { continuation in writer.finish { continuation.resume(returning: $0) } }
        }
    }
}
