import XCTest
import AVFoundation
import WhisperKit
@testable import Athar

/// Display/persistence policy over original public PCM with injected words.
/// This does not measure real ASR, microphone quality or correct recitation.
@MainActor final class QuranPracticeVisibilityTests: XCTestCase {
    func testHeardHeaderUsesOnlyAcceptedNativeIntervalsWithoutCompletingHiddenAyah() {
        let session = UUID(), take = UUID()
        var header = QuranHeardRecitation()
        header.begin(sessionID: session); header.beginTake(sessionID: session, takeID: take)
        let expected = [1: QuranAlignedWord(id: 1, verse: "112:1", page: 604, aliases: [["قل"]]),
                        2: QuranAlignedWord(id: 2, verse: "112:1", page: 604, aliases: [["هو"]])]
        let heard = [QuranHeardWord(text: "قل", start: 0, end: 0.4, probability: 0.99),
                     QuranHeardWord(text: "خطأ", start: 0.5, end: 0.9, probability: 0.99)]
        header.accept(sessionID: session, takeID: take, evidence: [], expected: expected, runs: [heard], offset: 0)
        XCTAssertTrue(header.fragments.isEmpty, "Unlocated hypotheses never become confirmed Quran")
        let evidence = QuranWordEvidence(nativeID: 1, verse: "112:1", takeID: take, start: 0, end: 0.4, minimumConfidence: 0.99)
        header.accept(sessionID: session, takeID: take, evidence: [evidence], expected: expected, runs: [heard], offset: 0)
        XCTAssertEqual(header.fragments.map(\.text), ["قل"])
        XCTAssertEqual(header.fragments.flatMap(\.nativeIDs), [1])
        XCTAssertFalse(header.fragments[0].text.contains("هو"), "An expected remainder is never a heard word")
    }

    func testHeardHeaderRetainsAcceptedTextAcrossSilenceResumeAndAyahTransitionButRejectsOldTakeAndSession() {
        let session = UUID(), firstTake = UUID(), nextTake = UUID()
        var header = QuranHeardRecitation()
        header.begin(sessionID: session); header.beginTake(sessionID: session, takeID: firstTake)
        let expected = [1: QuranAlignedWord(id: 1, verse: "112:1", page: 604, aliases: [["احد"]]),
                        2: QuranAlignedWord(id: 2, verse: "112:2", page: 604, aliases: [["الصمد"]])]
        func evidence(_ id: Int, verse: String, take: UUID) -> QuranWordEvidence {
            .init(nativeID: id, verse: verse, takeID: take, start: 0, end: 0.4, minimumConfidence: 0.99)
        }
        header.accept(sessionID: session, takeID: firstTake, evidence: [evidence(1, verse: "112:1", take: firstTake)], expected: expected,
                      runs: [[.init(text: "أحد", start: 0, end: 0.4, probability: 0.99)]], offset: 0)
        let accepted = header.fragments
        header.accept(sessionID: session, takeID: firstTake, evidence: [], expected: expected, runs: [], offset: 2)
        XCTAssertEqual(header.fragments, accepted, "Silence cannot replace heard text with meter status")
        header.beginTake(sessionID: session, takeID: nextTake)
        XCTAssertEqual(header.fragments, accepted, "Resume retains this session's heard text")
        header.accept(sessionID: session, takeID: firstTake, evidence: [evidence(2, verse: "112:2", take: firstTake)], expected: expected,
                      runs: [[.init(text: "الصمد", start: 0, end: 0.4, probability: 0.99)]], offset: 0)
        XCTAssertEqual(header.fragments, accepted, "A delayed old-take result cannot change the resumed header")
        header.accept(sessionID: session, takeID: nextTake, evidence: [evidence(2, verse: "112:2", take: nextTake)], expected: expected,
                      runs: [[.init(text: "الصمد", start: 0, end: 0.4, probability: 0.99)]], offset: 0)
        XCTAssertEqual(header.fragments.map(\.verse), ["112:1", "112:2"])
        XCTAssertEqual(header.fragments.map(\.text), ["أحد", "الصمد"])
        header.begin(sessionID: UUID())
        XCTAssertTrue(header.fragments.isEmpty)
        header.beginTake(sessionID: session, takeID: nextTake)
        header.accept(sessionID: session, takeID: nextTake, evidence: [evidence(2, verse: "112:2", take: nextTake)], expected: expected,
                      runs: [[.init(text: "الصمد", start: 0, end: 0.4, probability: 0.99)]], offset: 0)
        XCTAssertTrue(header.fragments.isEmpty, "A new session cannot inherit a late old-session header")
    }

    func testHeardHeaderRejectsWrongAliasAndIncompleteCompoundDespiteMatchingTimes() {
        let session = UUID(), take = UUID()
        var header = QuranHeardRecitation()
        header.begin(sessionID: session); header.beginTake(sessionID: session, takeID: take)
        let expected = [1: QuranAlignedWord(id: 1, verse: "2:21", page: 4, aliases: [["يا", "ايها"]])]
        let evidence = QuranWordEvidence(nativeID: 1, verse: "2:21", takeID: take, start: 3, end: 3.8, minimumConfidence: 0.99)
        for text in ["يا", "خطأ"] {
            header.accept(sessionID: session, takeID: take, evidence: [evidence], expected: expected,
                          runs: [[.init(text: text, start: 0, end: 0.8, probability: 0.99)]], offset: 3)
            XCTAssertTrue(header.fragments.isEmpty)
        }
        header.accept(sessionID: session, takeID: take, evidence: [evidence], expected: expected,
                      runs: [[.init(text: "يا", start: 0, end: 0.3, probability: 0.99),
                              .init(text: "أيها", start: 0.4, end: 0.8, probability: 0.99)]], offset: 3)
        XCTAssertEqual(header.fragments.map(\.text), ["يا أيها"])
    }

    func testHeardHeaderBoundsPresentationWithoutAddingExpectedWordsOrProgress() {
        let session = UUID(), take = UUID()
        var header = QuranHeardRecitation()
        header.begin(sessionID: session); header.beginTake(sessionID: session, takeID: take)
        let expected = Dictionary(uniqueKeysWithValues: (1...32).map { id in
            (id, QuranAlignedWord(id: id, verse: id <= 30 ? "2:1" : "2:\(id - 29)", page: 2, aliases: [["قال"]]))
        })
        let evidence = (1...32).map { id in
            QuranWordEvidence(nativeID: id, verse: expected[id]!.verse, takeID: take,
                              start: Double(id), end: Double(id) + 0.4, minimumConfidence: 0.99)
        }
        let run = evidence.map { QuranHeardWord(text: "قال", start: $0.start, end: $0.end, probability: 0.99) }
        header.accept(sessionID: session, takeID: take, evidence: Array(evidence.prefix(30)), expected: expected, runs: [run], offset: 0)
        XCTAssertEqual(header.fragments[0].nativeIDs, Array(7...30))
        header.accept(sessionID: session, takeID: take, evidence: Array(evidence.suffix(2)), expected: expected, runs: [run], offset: 0)
        XCTAssertEqual(header.fragments.map(\.verse), ["2:2", "2:3"])
        XCTAssertEqual(header.fragments.flatMap(\.nativeIDs), [31, 32])
        XCTAssertEqual(evidence.count, 32, "Bounded display never deletes or adds recognition evidence")
    }

    func testHeardHeaderRestorationSkipsSilenceBeforeBoundingItsAcceptedSources() {
        let take = UUID()
        let evidence = QuranWordEvidence(nativeID: 1, verse: "112:1", takeID: take, start: 0, end: 0.4, minimumConfidence: 0.99)
        var accepted = QuranObservedSpeech(takeID: take, start: 0, end: 2, words: ["قل"], unresolved: false, backendID: "display-policy-fixture")
        accepted.wordObservations = [.init(occurrenceIndex: 0, runIndex: 0, observedText: "قل", startInTakeSeconds: 0,
                                          endInTakeSeconds: 0.4, backendConfidence: 0.99, recognitionState: "accepted", timingSource: "fixture")]
        let silent = QuranObservedSpeech(takeID: take, start: 0, end: 2, words: [], unresolved: false, backendID: "display-policy-fixture")
        var unrelated = QuranObservedSpeech(takeID: UUID(), start: 0, end: 2, words: ["قل"], unresolved: false, backendID: "display-policy-fixture")
        unrelated.wordObservations = accepted.wordObservations
        let sources = QuranHeardRecitation.sourcesForRestoration([accepted] + Array(repeating: silent, count: 32) + [unrelated],
                                                                evidenceByTake: [take: [evidence]])
        XCTAssertEqual(sources, [accepted], "Quiet windows and another take cannot evict the last accepted heard text")
    }

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
        XCTAssertEqual(controller.heardRecitation.fragments.map(\.text), ["الحمد لله رب العالمين"])
        let heardHeader = controller.heardRecitation
        XCTAssertTrue(controller.setPracticeTextHidden(false))
        XCTAssertEqual(controller.heardRecitation, heardHeader, "Showing Quran text cannot add heard words")
        XCTAssertTrue(controller.setPracticeTextHidden(true))
        XCTAssertTrue(controller.hiddenIDs.isDisjoint(with:firstIDs))
        let stillHidden = controller.hiddenIDs
        XCTAssertFalse(stillHidden.isEmpty,"The next unread ayah must stay hidden")
        try XCTUnwrap(capture).append(Array(samples[32_000..<48_000]))
        try await eventually { (controller.record?.observedSpeech?.count ?? 0) >= 2 }
        XCTAssertTrue(controller.revealed.isEmpty,"Revisable evidence must actually retract")
        XCTAssertTrue(controller.record?.evidence.isEmpty == true,"Display history cannot award progress")
        XCTAssertNil(controller.activeWordID,"Retracted speech must not leave a stale heard-word highlight")
        XCTAssertEqual(controller.heardRecitation, heardHeader, "Earlier accepted text remains display history, not a current-word claim")
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
        XCTAssertTrue(restored.heardRecitation.fragments.isEmpty, "A new session starts without heard text")
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
