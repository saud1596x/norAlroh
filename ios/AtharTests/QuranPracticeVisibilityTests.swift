import XCTest
import AVFoundation
import WhisperKit
@testable import Athar

/// Display/persistence policy over original public PCM with injected words.
/// This does not measure real ASR, microphone quality or correct recitation.
@MainActor final class QuranPracticeVisibilityTests: XCTestCase {
    func testShownFatihaAyahStaysVisibleWhenTheNextWindowRetractsItsInterpretation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let snapshot = try JSONDecoder().decode(QCFV2Snapshot.self,
            from: XCTUnwrap(QCFV2ContentCache.bundledSnapshot())).validated()
        let corpus = try XCTUnwrap(QuranResources.corpus)
        let url = try XCTUnwrap(Bundle(for:Self.self).url(forResource:"001002",withExtension:"mp3"))
        let samples = try AudioProcessor.loadAudioAsFloatArray(fromPath:url.path)
        XCTAssertGreaterThanOrEqual(samples.count,48_000)
        let heard = ["الحمد","لله","رب","العالمين"].enumerated().map {
            QuranHeardWord(text:$0.element,start:0.1+Double($0.offset)*0.4,
                           end:0.4+Double($0.offset)*0.4,probability:0.99)
        }
        var capture: SteppedCapture?
        let controller = QuranRecitationController(requestPermission:{true},archiveRoot:root,
            recognitionProvider: VisibilityFixtureProvider(heard: heard),
            makeCapture:{ writer,_ in
                let value = SteppedCapture(writer:writer,initial:Array(samples.prefix(32_000)))
                capture=value;return value
            },setSessionActive:{_ in})
        await controller.start(keys:["1:2","1:3"],page:1,snapshot:snapshot,corpus:corpus,closedText:true)
        try await eventually { controller.record?.retainedVisibleVerses == ["1:2"] }
        let firstIDs = Set(try XCTUnwrap(controller.record).evidence.map(\.nativeID))
        XCTAssertEqual(firstIDs.count,4)
        XCTAssertNotNil(controller.activeWordID)
        XCTAssertTrue(controller.hiddenIDs.isDisjoint(with:firstIDs))
        let stillHidden = controller.hiddenIDs
        XCTAssertFalse(stillHidden.isEmpty,"The next unread ayah must stay hidden")
        try XCTUnwrap(capture).append(Array(samples[32_000..<48_000]))
        try await eventually { (controller.record?.observedSpeech?.count ?? 0) >= 2 }
        XCTAssertTrue(controller.revealed.isEmpty,"Revisable evidence must actually retract")
        XCTAssertTrue(controller.record?.evidence.isEmpty == true,"Display history cannot award progress")
        XCTAssertNil(controller.activeWordID,"Retracted speech must not leave a stale heard-word highlight")
        XCTAssertTrue(controller.hiddenIDs.isDisjoint(with:firstIDs),"Previously shown ayah must not disappear")
        XCTAssertEqual(controller.hiddenIDs,stillHidden,"Retention must not reveal the next ayah")
        await controller.pause()
        let saved = try XCTUnwrap(controller.record)
        XCTAssertEqual(saved.retainedVisibleVerses,["1:2"])
        XCTAssertTrue(Set(saved.takes[0].textHintIDs ?? []).isSuperset(of:firstIDs),"Visible retracted text is assistance, not mastery")
        let journal = QuranRecitationJournal(root:root)
        XCTAssertEqual(try AudioProcessor.loadAudioAsFloatArray(fromPath:journal.audio(session:saved.id,take:saved.takes[0].id).path),Array(samples.prefix(48_000)))
        let restored = QuranRecitationController(requestPermission:{true},archiveRoot:root,
            recognitionProvider: VisibilityFixtureProvider(heard: []),
            makeCapture:{writer,_ in SteppedCapture(writer:writer,initial:[])},setSessionActive:{_ in})
        await restored.restore(id:saved.id,snapshot:snapshot,corpus:corpus)
        XCTAssertEqual(restored.state,.paused)
        XCTAssertEqual(restored.hiddenIDs,stillHidden,"Pause/relaunch cannot erase displayed ayah history")
        XCTAssertTrue(restored.record?.evidence.isEmpty == true)
        await restored.finish()
        await restored.start(keys:["1:3"],page:1,snapshot:snapshot,corpus:corpus,closedText:true)
        XCTAssertNil(restored.record?.retainedVisibleVerses,"A new practice session starts independently")
        XCTAssertNil(restored.record?.takes.first?.textHintIDs)
        await restored.finish()
    }

    func testRecognitionFailureWithdrawsCurrentHighlightWithoutErasingShownAyahOrPriorEvidence() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let snapshot = try JSONDecoder().decode(QCFV2Snapshot.self,
            from: XCTUnwrap(QCFV2ContentCache.bundledSnapshot())).validated()
        let corpus = try XCTUnwrap(QuranResources.corpus)
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "001002", withExtension: "mp3"))
        let samples = try AudioProcessor.loadAudioAsFloatArray(fromPath: url.path)
        let heard = ["الحمد", "لله", "رب", "العالمين"].enumerated().map {
            QuranHeardWord(text: $0.element, start: 0.1 + Double($0.offset) * 0.4,
                           end: 0.4 + Double($0.offset) * 0.4, probability: 0.99)
        }
        var capture: SteppedCapture?
        let controller = QuranRecitationController(requestPermission: { true }, archiveRoot: root,
            recognitionProvider: VisibilityFixtureProvider(heard: heard, failAfterFirstWindow: true),
            makeCapture: { writer, _ in
                let value = SteppedCapture(writer: writer, initial: Array(samples.prefix(32_000)))
                capture = value; return value
            }, setSessionActive: { _ in })
        await controller.start(keys: ["1:2", "1:3"], page: 1, snapshot: snapshot, corpus: corpus, closedText: true)
        try await eventually { controller.record?.retainedVisibleVerses == ["1:2"] }
        let evidence = try XCTUnwrap(controller.record).evidence
        XCTAssertEqual(evidence.count, 4)
        XCTAssertNotNil(controller.activeWordID)
        let shown = Set(evidence.map(\.nativeID))
        try XCTUnwrap(capture).append(Array(samples[32_000..<48_000]))
        try await eventually { !controller.recognitionAvailable }
        XCTAssertEqual(controller.state, .listening, "Recognition failure must not stop independent input")
        XCTAssertNil(controller.activeWordID, "An old accepted word is not current audio after inference fails")
        XCTAssertEqual(controller.currentVerse, "1:2")
        XCTAssertEqual(controller.record?.retainedVisibleVerses, ["1:2"])
        XCTAssertEqual(controller.record?.evidence, evidence, "Failure cannot erase valid earlier speech")
        XCTAssertTrue(controller.hiddenIDs.isDisjoint(with: shown), "Failure must not re-hide an already shown ayah")
        await controller.finish()
    }

    private struct VisibilityFixtureProvider: QuranSpeechRecognitionProvider {
        let heard: [QuranHeardWord]
        var failAfterFirstWindow = false
        var capabilities: QuranRecognitionCapabilities {
            .init(backendID: "display-policy-fixture", modelID: "injected-words-not-ASR", modelRevision: "1",
                  configuredLanguage: "ar", delivery: .overlappingAudioWindows, processesLocally: true,
                  wordTimestamps: true, wordConfidence: true, phonemeEvidence: false,
                  calibratedWordingAssessment: false, validatedTajweedAssessment: false)
        }
        func prepare() async throws {}
        func recognize(_ window: QuranAudioWindow) async throws -> QuranRecognitionWorker.Result {
            if failAfterFirstWindow && window.endFrame > 32_000 { throw URLError(.timedOut) }
            return .init(runs: window.endFrame == 32_000 && !heard.isEmpty ? [heard] : [], hasUnresolvedSpeech: false)
        }
    }
    private func eventually(_ condition:() -> Bool) async throws {
        let end=Date().addingTimeInterval(12)
        while !condition(),Date() < end { try await Task.sleep(nanoseconds:20_000_000) }
        XCTAssertTrue(condition(),"Timed out waiting for the actual durable analysis")
    }
    private final class SteppedCapture: QuranAudioCapture {
        let writer:QuranPCMWriter
        let initial:[Float]
        init(writer:QuranPCMWriter,initial:[Float]) { self.writer=writer;self.initial=initial }
        func start() throws { if !initial.isEmpty { writer.append(initial) } }
        func append(_ samples:[Float]) { writer.append(samples) }
        func stop() async -> Result<Int64,Error> {
            await withCheckedContinuation { continuation in writer.finish { continuation.resume(returning:$0) } }
        }
    }
}
