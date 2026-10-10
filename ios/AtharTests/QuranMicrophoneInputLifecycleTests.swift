import XCTest
import AVFoundation
import WhisperKit
@testable import Athar

/// Injected lifecycle notifications and identified reference PCM. These tests
/// do not connect Bluetooth hardware or claim to exercise an iPhone microphone.
final class QuranMicrophoneInputLifecycleTests: XCTestCase {
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
        let (bytes, response) = try await URLSession.shared.data(from:
            URL(string: "https://noor-quran-sync.onrender.com/v1/mushaf/snapshot")!)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
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
