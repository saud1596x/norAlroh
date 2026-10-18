import XCTest
import AVFoundation
import UIKit
import WhisperKit
import CryptoKit
@testable import Athar

/// Real Core ML inference on identified reference audio; this is not a live
/// microphone journey and must not be presented as one in release evidence.
final class QuranRecognitionIntegrationTests: XCTestCase {
    @MainActor func testOpeningAndResumingCaptureDoesNotWaitForModelPreparation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let snapshot = try JSONDecoder().decode(QCFV2Snapshot.self,
            from: XCTUnwrap(QCFV2ContentCache.bundledSnapshot())).validated()
        let provider = UnavailableStartupProvider()
        // Empty injected capture verifies lifecycle ordering only, never
        // microphone hardware, recognition accuracy, or recitation progress.
        let controller = QuranRecitationController(requestPermission: { true }, archiveRoot: root,
            recognitionProvider: provider,
            makeCapture: { writer, _ in ReferenceCapture(writer: writer, samples: []) }, setSessionActive: { _ in })
        await controller.start(keys: ["112:1"], page: 604, snapshot: snapshot, corpus: try XCTUnwrap(QuranResources.corpus))
        XCTAssertEqual(controller.state, .listening)
        XCTAssertNotNil(controller.record?.takes.first)
        XCTAssertTrue(controller.record?.evidence.isEmpty == true)
        await controller.pause()
        XCTAssertEqual(controller.state, .paused)
        await controller.resume()
        XCTAssertEqual(controller.state, .listening)
        XCTAssertEqual(controller.record?.takes.count, 2)
        await controller.finish()
        let attempts = await provider.prepareAttempts
        XCTAssertEqual(attempts, 0, "No audio window exists; model loading must not gate opening capture")
    }
    @MainActor func testPauseClosesActualAudioWhileAnalysisSaveIsDelayedWithoutReopeningTake() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let snapshot = try JSONDecoder().decode(QCFV2Snapshot.self,
            from: XCTUnwrap(QCFV2ContentCache.bundledSnapshot())).validated()
        let reference = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "112001", withExtension: "mp3"))
        let samples = try AudioProcessor.loadAudioAsFloatArray(fromPath: reference.path)
        var saveReached = false
        var shouldDelay = true
        var releaseSave: CheckedContinuation<Void, Never>?
        let controller = QuranRecitationController(requestPermission: { true }, archiveRoot: root, drainTimeout: 120,
            analysisPersistence: { value in
                if shouldDelay {
                    await withCheckedContinuation { continuation in releaseSave = continuation; saveReached = true }
                }
                try QuranRecitationJournal(root: root).save(value)
            }, makeCapture: { writer, _ in ReferenceCapture(writer: writer, samples: samples) }, setSessionActive: { _ in })
        await controller.start(keys: ["112:1"], page: 604, snapshot: snapshot, corpus: try XCTUnwrap(QuranResources.corpus))
        for _ in 0..<1000 where !saveReached { try await Task.sleep(nanoseconds: 20_000_000) }
        guard saveReached else {
            shouldDelay = false; await controller.pause()
            XCTFail("Actual analysis did not reach persistence"); return
        }
        XCTAssertTrue(controller.revealed.isEmpty, "Uncommitted analysis must not reveal Quran words")
        let pause = Task { @MainActor in await controller.pause() }
        for _ in 0..<100 where controller.record?.takes.last?.closed != true { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertEqual(controller.record?.takes.last?.closed, true)
        shouldDelay = false; releaseSave?.resume(); releaseSave = nil
        await pause.value
        XCTAssertEqual(controller.state, .paused)
        let record = try XCTUnwrap(controller.record)
        XCTAssertTrue(record.takes.allSatisfy(\.closed))
        XCTAssertGreaterThanOrEqual(record.evidence.count, 2)
        XCTAssertEqual(try QuranRecitationJournal(root: root).load(record.id).phase, .paused)
        await controller.finish()
    }
    @MainActor func testActualReferenceFindsItsVerseAcrossEntireQuranWithoutStartingPageHint() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let snapshot = try JSONDecoder().decode(QCFV2Snapshot.self,
            from: XCTUnwrap(QCFV2ContentCache.bundledSnapshot())).validated()
        let corpus = try XCTUnwrap(QuranResources.corpus)
        let keys = corpus.flatMap { surah in surah.ayahs.map { "\(surah.number):\($0.number)" } }
        XCTAssertEqual(keys.count, 6236)
        let reference = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "112001", withExtension: "mp3"))
        let samples = try AudioProcessor.loadAudioAsFloatArray(fromPath: reference.path)
        let controller = QuranRecitationController(requestPermission: { true }, archiveRoot: root, drainTimeout: 120,
            makeCapture: { writer, _ in ReferenceCapture(writer: writer, samples: samples) }, setSessionActive: { _ in })
        await controller.start(keys: keys, page: 1, snapshot: snapshot, corpus: corpus, automaticScope: true)
        await controller.pause()
        let saved = try XCTUnwrap(controller.record)
        XCTAssertEqual(saved.textExposureOccurred, true, "An ordinary visible-text session is assisted practice")
        XCTAssertGreaterThanOrEqual(saved.evidence.count, 3)
        XCTAssertTrue(saved.evidence.allSatisfy { $0.verse == "112:1" })
        XCTAssertEqual(controller.currentVerse, "112:1", "Origin page must not bias recognition toward Al-Fatiha")
        XCTAssertEqual(Set(saved.evidence.map(\.verse)), Set(["112:1"]))
        XCTAssertTrue(controller.hiddenIDs.isEmpty, "Visible-text tracking must never hide the rest of the Quran")
        var silent = saved; silent.evidence = []; silent.wordingEvents = []
        XCTAssertTrue(silent.evidence.isEmpty, "Silence supplies no evidence or correctness grade")
        let reopened = QuranRecitationController(archiveRoot: root)
        await reopened.restore(id: saved.id, snapshot: snapshot, corpus: corpus)
        XCTAssertEqual(reopened.currentVerse, "112:1")
        await controller.finish()
    }
    @MainActor func testClosedTextStartsHiddenAndHintsNeverBecomeRecognitionEvidence() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let bytes = try XCTUnwrap(QCFV2ContentCache.bundledSnapshot())
        let snapshot = try JSONDecoder().decode(QCFV2Snapshot.self, from: bytes).validated()
        let corpus = try XCTUnwrap(QuranResources.corpus)
        // Silent injected capture checks state/assistance, not acoustic accuracy.
        let controller = QuranRecitationController(requestPermission: { true }, archiveRoot: root,
            makeCapture: { writer, _ in ReferenceCapture(writer: writer, samples: []) }, setSessionActive: { _ in })
        await controller.start(keys: ["112:1"], page: 604, snapshot: snapshot, corpus: corpus, closedText: true)
        XCTAssertEqual(controller.state, .listening)
        XCTAssertEqual(controller.hiddenIDs.count, 4)
        XCTAssertTrue(controller.revealed.isEmpty)
        await controller.revealNextWord(in: "112:1")
        XCTAssertEqual(controller.hiddenIDs.count, 3)
        XCTAssertTrue(controller.revealed.isEmpty)
        XCTAssertTrue(controller.record?.evidence.isEmpty == true)
        let saved = try XCTUnwrap(controller.record)
        XCTAssertEqual(saved.textExposureOccurred, false)
        let journal = QuranRecitationJournal(root: root)
        XCTAssertEqual(try journal.load(saved.id).closedTextRequested, true)
        await controller.resume()
        XCTAssertEqual(controller.record?.takes.last?.textHintIDs, saved.textHintIDs)
        await controller.pause()
        let restored = QuranRecitationController(archiveRoot: root)
        await restored.restore(id: saved.id, snapshot: snapshot, corpus: corpus)
        XCTAssertEqual(restored.hiddenIDs.count, 3)
        XCTAssertTrue(restored.revealed.isEmpty)
        await controller.finish()
    }
    @MainActor func testClosedTextCaptureFailureRestoresReadingAndRecordsExposedAssistance() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let bytes = try XCTUnwrap(QCFV2ContentCache.bundledSnapshot())
        let snapshot = try JSONDecoder().decode(QCFV2Snapshot.self, from: bytes).validated()
        let controller = QuranRecitationController(requestPermission: { true }, archiveRoot: root,
            makeCapture: { _, _ in throw CocoaError(.fileWriteUnknown) }, setSessionActive: { _ in })
        await controller.start(keys: ["112:1"], page: 604, snapshot: snapshot,
                               corpus: try XCTUnwrap(QuranResources.corpus), closedText: true)
        XCTAssertEqual(controller.state, .paused)
        XCTAssertTrue(controller.hiddenIDs.isEmpty)
        XCTAssertEqual(controller.record?.textExposureOccurred, true)
        XCTAssertTrue((controller.record?.textHintIDs ?? []).isEmpty, "Exposing a page is assistance, not four invented hint requests")
        XCTAssertTrue(controller.record?.evidence.isEmpty == true)
        XCTAssertTrue(controller.record?.recognitionUnavailable == true)
        await controller.finish()
    }
    /// Diagnostic edited-reference regression, not a human-reviewed learner
    /// benchmark. It exposes model normalization/abstention rather than claiming
    /// production error accuracy from a splice based on estimated word timing.
    func testActualBackendOnReferenceAndEditedOmissionKeepsAssessmentProvisional() async throws {
        let bundle = Bundle(for: Self.self)
        let one = try XCTUnwrap(bundle.url(forResource: "112001", withExtension: "mp3"))
        let two = try XCTUnwrap(bundle.url(forResource: "112002", withExtension: "mp3"))
        let correct = try AudioProcessor.loadAudioAsFloatArray(fromPath: one.path)
            + AudioProcessor.loadAudioAsFloatArray(fromPath: two.path)
        let worker = QuranRecognitionWorker()
        let base = try await worker.recognize(.init(samples: correct, startFrame: 0, endFrame: Int64(correct.count)))
        let observed = try XCTUnwrap(base.observations)
        let removed = try XCTUnwrap(observed.first { QuranAlignedWord.normalize($0.observedText) == "الله" && $0.recognitionState == "accepted" })
        let from = Int(try XCTUnwrap(removed.startInTakeSeconds) * 16_000)
        let to = Int(try XCTUnwrap(removed.endInTakeSeconds) * 16_000)
        XCTAssertGreaterThan(to, from); XCTAssertLessThanOrEqual(to, correct.count)
        let edited = Array(correct[..<from]) + Array(correct[to...])
        let started = Date()
        let result = try await worker.recognize(.init(samples: edited, startFrame: 0, endFrame: Int64(edited.count)))
        let tokens = ["قل", "هو", "الله", "أحد", "الله", "الصمد"]
        let expected = tokens.enumerated().map {
            QuranAlignedWord(id: $0.offset + 1, verse: $0.offset < 4 ? "112:1" : "112:2", page: 604,
                aliases: [[QuranAlignedWord.normalize($0.element)]])
        }
        var span = QuranObservedSpeech(takeID: UUID(), start: 0, end: Double(edited.count) / 16_000,
            words: result.runs.flatMap { $0.map(\.text) }, unresolved: result.hasUnresolvedSpeech, backendID: worker.capabilities.backendID)
        span.evidenceVersion = 1; span.recognitionWindowID = result.windowID; span.recognitionRevision = 0
        span.wordObservations = result.observations
        let events = QuranWordingAssessment.evaluate([span], expected: expected)
        XCTAssertTrue(events.allSatisfy { $0.state == "provisional" })
        XCTAssertEqual(span.wordObservations, result.observations, "Assessment must not repair observed speech into the reference")
        print("EDITED_PUBLIC_REFERENCE_OMISSION elapsedMs=\(Int(Date().timeIntervalSince(started) * 1000)) observations=\(result.observations?.count ?? 0) unresolved=\(result.hasUnresolvedSpeech) omissionCandidates=\(events.filter { $0.category == "omission" }.count) confirmed=0")
        // Only this explicitly public fixture may log decoded text. Production
        // microphone diagnostics remain numeric and never print a transcript.
        let diagnostic = try JSONEncoder().encode(result.observations ?? [])
        print("PUBLIC_FIXTURE_OBSERVED_WORDS " + (String(data: diagnostic, encoding: .utf8) ?? "unreadable"))
    }
    func testShortStreamingReferenceWindowsAnchorOnlyTheActuallySpokenVerse() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "112001", withExtension: "mp3"))
        let samples = try AudioProcessor.loadAudioAsFloatArray(fromPath: url.path)
        let scriptURL = try XCTUnwrap(Bundle.main.url(forResource: "recitation-word-script", withExtension: "json"))
        let script = try JSONDecoder().decode(QuranWordScript.self, from: Data(contentsOf: scriptURL))
        let groups = try XCTUnwrap(script.groups["112:1"])
        let expected = groups.enumerated().map { index, group in
            QuranAlignedWord(id: index + 1, verse: "112:1", page: group.page,
                aliases: Set([QuranAlignedWord.tokens(group.imlaei), QuranAlignedWord.tokens(group.canonical),
                              QuranAlignedWord.tokens(group.canonical, expandDaggerAlif: true)]))
        }
        let worker = QuranRecognitionWorker()
        var tracker = QuranRecitationTracker(expected: expected)
        let take = UUID()
        var firstAnchorSeconds: Double?
        for end in Set([min(samples.count, 32_000), min(samples.count, 48_000), samples.count]).sorted() {
            let prefix = Array(samples.prefix(end))
            let started = Date()
            let result = try await worker.recognize(.init(samples: prefix, startFrame: 0, endFrame: Int64(end)))
            for run in result.runs { try tracker.consume(run, takeID: take) }
            if !tracker.revealedIDs.isEmpty && firstAnchorSeconds == nil { firstAnchorSeconds = Double(end) / 16_000 }
            print("PUBLIC_REFERENCE_STREAM seconds=\(Double(end) / 16_000) inferenceMs=\(Int(Date().timeIntervalSince(started) * 1000)) anchored=\(tracker.revealedIDs.count)")
            XCTAssertTrue(tracker.evidence.allSatisfy { $0.verse == "112:1" && $0.end <= Double(end) / 16_000 + 0.1 })
        }
        XCTAssertGreaterThanOrEqual(tracker.revealedIDs.count, min(2, expected.count))
        XCTAssertNotNil(firstAnchorSeconds)
        let silence = Array(repeating: Float(0), count: 32_000)
        let silentResult = try await worker.recognize(.init(samples: silence, startFrame: 0, endFrame: 32_000))
        var silentTracker = QuranRecitationTracker(expected: expected)
        for run in silentResult.runs { try silentTracker.consume(run, takeID: UUID()) }
        XCTAssertTrue(silentTracker.revealedIDs.isEmpty)
    }
    func testVerifiedReferenceMatrixProducesUsefulAnchorsAtOrdinaryAndQuietLevels() async throws {
        struct Fixture: Decodable { let verse: String; let file: String; let sha256: String }
        let bundle = Bundle(for: Self.self)
        let manifest = try XCTUnwrap(bundle.url(forResource: "recitation-reference-sources", withExtension: "json"))
        let fixtures = try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: manifest))
        XCTAssertEqual(fixtures.count, 10)
        let scriptURL = try XCTUnwrap(Bundle.main.url(forResource: "recitation-word-script", withExtension: "json"))
        let script = try JSONDecoder().decode(QuranWordScript.self, from: Data(contentsOf: scriptURL))
        let worker = QuranRecognitionWorker()
        for fixture in fixtures {
            let name = (fixture.file as NSString).deletingPathExtension
            let url = try XCTUnwrap(bundle.url(forResource: name, withExtension: "mp3"))
            let digest = SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
            XCTAssertEqual(digest, fixture.sha256, "Reference audio must match the independently pinned fixture")
            let original = try AudioProcessor.loadAudioAsFloatArray(fromPath: url.path)
            let groups = try XCTUnwrap(script.groups[fixture.verse])
            let expected = groups.enumerated().map { index, group in
                QuranAlignedWord(id: index + 1, verse: fixture.verse, page: group.page,
                    aliases: Set([QuranAlignedWord.tokens(group.imlaei), QuranAlignedWord.tokens(group.canonical),
                                  QuranAlignedWord.tokens(group.canonical, expandDaggerAlif: true)]))
            }
            for level in [Float(1), Float(0.03)] {
                let samples = original.map { $0 * level }
                let output = try await worker.recognize(.init(samples: samples, startFrame: 0, endFrame: Int64(samples.count)))
                var tracker = QuranRecitationTracker(expected: expected)
                let take = UUID()
                for run in output.runs { try tracker.consume(run, takeID: take) }
                XCTAssertGreaterThanOrEqual(tracker.revealedIDs.count, min(2, expected.count),
                    "Identified public fixture \(fixture.verse), level \(level) must establish a useful exact anchor")
                XCTAssertTrue(tracker.evidence.allSatisfy { $0.end <= Double(samples.count) / 16_000 + 0.1 })
            }
        }
    }

    @MainActor func testInterruptedActualReferenceProgressStaysVisibleThroughEmptyResumeUntilFreshRecognition() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let bytes = try XCTUnwrap(QCFV2ContentCache.bundledSnapshot())
        let snapshot = try JSONDecoder().decode(QCFV2Snapshot.self, from: bytes).validated()
        let corpus = try XCTUnwrap(QuranResources.corpus)
        let reference = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "112001", withExtension: "mp3"))
        let samples = try AudioProcessor.loadAudioAsFloatArray(fromPath: reference.path)
        let original = QuranRecitationController(requestPermission: { true }, archiveRoot: root, drainTimeout: 120,
            makeCapture: { writer, _ in ReferenceCapture(writer: writer, samples: samples) }, setSessionActive: { _ in })
        // Full surah scope leaves later words to hide; a complete one-verse
        // fixture alone could make an empty hidden set pass vacuously.
        await original.start(keys: ["112:1", "112:2", "112:3", "112:4"], page: 604, snapshot: snapshot, corpus: corpus)
        await original.pause()
        XCTAssertGreaterThanOrEqual(original.record?.evidence.count ?? 0, 2)
        XCTAssertTrue(original.record?.evidence.allSatisfy { $0.verse == "112:1" } == true,
            "The identified first-verse clip must not anchor an unspoken verse in the full-surah scope")
        XCTAssertFalse(original.hiddenIDs.isEmpty)
        let journal = QuranRecitationJournal(root: root)
        var interrupted = try XCTUnwrap(original.record)
        let first = try XCTUnwrap(interrupted.takes.first)
        let originalBytes = try Data(contentsOf: journal.audio(session: interrupted.id, take: first.id))
        // Deliberately simulate the durable metadata of an interrupted process;
        // the PCM and recognized evidence above came from actual inference.
        interrupted.phase = .recording; interrupted.takes[0].closed = false
        try journal.save(interrupted)
        var acceptActualRecognition = false
        var rejectedWindows = 0
        let reopened = QuranRecitationController(requestPermission: { true }, archiveRoot: root, drainTimeout: 120,
            recognizeWindow: { window in
                if !acceptActualRecognition {
                    rejectedWindows += 1
                    return .init(runs: [], hasUnresolvedSpeech: true)
                }
                return try await QuranRecognitionWorker.shared.recognize(window)
            }, makeCapture: { writer, _ in ReferenceCapture(writer: writer, samples: samples) }, setSessionActive: { _ in })
        await reopened.restore(id: interrupted.id, snapshot: snapshot, corpus: corpus)
        XCTAssertEqual(reopened.state, .paused)
        XCTAssertEqual(reopened.revealed, Set(interrupted.evidence.map(\.nativeID)))
        XCTAssertFalse(reopened.recognitionAvailable)
        XCTAssertTrue(reopened.hiddenIDs.isEmpty, "An interrupted engine must expose text despite older valid evidence")
        await reopened.resume()
        XCTAssertFalse(reopened.recognitionAvailable, "A running microphone is not new recognition proof")
        XCTAssertTrue(reopened.hiddenIDs.isEmpty)
        await reopened.pause()
        XCTAssertGreaterThan(rejectedWindows, 0)
        XCTAssertFalse(reopened.recognitionAvailable, "Successful decoding with no accepted anchors cannot restore tracking")
        XCTAssertTrue(reopened.hiddenIDs.isEmpty)
        XCTAssertTrue(try journal.load(interrupted.id).recognitionUnavailable)
        acceptActualRecognition = true
        await reopened.resume()
        XCTAssertFalse(reopened.recognitionAvailable)
        await reopened.pause()
        XCTAssertTrue(reopened.recognitionAvailable, "Actual new-take reference evidence can restore tracking")
        XCTAssertFalse(reopened.hiddenIDs.isEmpty)
        XCTAssertFalse(try journal.load(interrupted.id).recognitionUnavailable)
        XCTAssertTrue(reopened.record?.evidence.allSatisfy { $0.verse == "112:1" } == true)
        XCTAssertEqual(try Data(contentsOf: journal.audio(session: interrupted.id, take: first.id)), originalBytes)
        let beforeHint = reopened.record?.evidence
        await reopened.revealNextWord(in: "112:2")
        let hintIDs = try XCTUnwrap(reopened.record?.textHintIDs)
        XCTAssertEqual(hintIDs.count, 1, "Graduated help reveals one authored word at a time")
        XCTAssertEqual(reopened.record?.evidence, beforeHint, "Revealing Quran text cannot manufacture heard speech")
        XCTAssertTrue(Set(hintIDs).isDisjoint(with: reopened.hiddenIDs))
        XCTAssertEqual(try journal.load(interrupted.id).textHintIDs, hintIDs)
        let withHints = QuranRecitationController(archiveRoot: root)
        await withHints.restore(id: interrupted.id, snapshot: snapshot, corpus: corpus)
        XCTAssertEqual(withHints.record?.textHintIDs, hintIDs)
        XCTAssertTrue(Set(hintIDs).isDisjoint(with: withHints.hiddenIDs), "Saved assistance survives reopening")
    }

    @MainActor func testDrainTimeoutWithActualPriorEvidenceExposesTextAndRejectsLateDecode() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let bytes = try XCTUnwrap(QCFV2ContentCache.bundledSnapshot())
        let snapshot = try JSONDecoder().decode(QCFV2Snapshot.self, from: bytes).validated()
        let corpus = try XCTUnwrap(QuranResources.corpus)
        let reference = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "112001", withExtension: "mp3"))
        // Explicit silence tail makes this short identified clip produce a live
        // four-second window before pause; it is not additional spoken evidence.
        let samples = try AudioProcessor.loadAudioAsFloatArray(fromPath: reference.path)
            + Array(repeating: Float(0), count: 32_000)
        let original = QuranRecitationController(requestPermission: { true }, archiveRoot: root, drainTimeout: 120,
            makeCapture: { writer, _ in ReferenceCapture(writer: writer, samples: samples) }, setSessionActive: { _ in })
        await original.start(keys: ["112:1", "112:2", "112:3", "112:4"], page: 604, snapshot: snapshot, corpus: corpus)
        await original.pause()
        let record = try XCTUnwrap(original.record)
        XCTAssertGreaterThanOrEqual(record.evidence.count, 2)
        XCTAssertTrue(record.evidence.allSatisfy { $0.verse == "112:1" })
        var late: CheckedContinuation<QuranRecognitionWorker.Result, Never>?
        let entered = expectation(description: "Explicit fault simulation begins")
        let reopened = QuranRecitationController(requestPermission: { true }, archiveRoot: root, drainTimeout: 0.05,
            recognitionTimeout: 60, recognizeWindow: { _ in
                await withCheckedContinuation { late = $0; entered.fulfill() }
            }, makeCapture: { writer, _ in ReferenceCapture(writer: writer, samples: samples) }, setSessionActive: { _ in })
        await reopened.restore(id: record.id, snapshot: snapshot, corpus: corpus)
        XCTAssertFalse(reopened.hiddenIDs.isEmpty)
        await reopened.resume()
        await fulfillment(of: [entered], timeout: 5)
        await reopened.pause()
        XCTAssertEqual(reopened.state, .paused)
        XCTAssertFalse(reopened.recognitionAvailable)
        XCTAssertTrue(reopened.hiddenIDs.isEmpty)
        XCTAssertTrue(try QuranRecitationJournal(root: root).load(record.id).recognitionUnavailable)
        try XCTUnwrap(late).resume(returning: .init(runs: [], hasUnresolvedSpeech: false))
        await Task.yield()
        XCTAssertEqual(reopened.record?.evidence, record.evidence, "No late decode may overwrite paused proof")
        XCTAssertTrue(reopened.hiddenIDs.isEmpty)
    }
    @MainActor func testHungLiveRecognitionKeepsAudioAndCannotRevealLateWords() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let bytes = try XCTUnwrap(QCFV2ContentCache.bundledSnapshot())
        let snapshot = try JSONDecoder().decode(QCFV2Snapshot.self, from: bytes).validated()
        let corpus = try XCTUnwrap(QuranResources.corpus)
        let reference = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "112001", withExtension: "mp3"))
        let samples = try AudioProcessor.loadAudioAsFloatArray(fromPath: reference.path)
            + Array(repeating: Float(0), count: 32_000)
        var late: CheckedContinuation<QuranRecognitionWorker.Result, Never>?
        let controller = QuranRecitationController(requestPermission: { true }, archiveRoot: root,
            recognitionTimeout: 0.05, recognizeWindow: { _ in
                await withCheckedContinuation { late = $0 }
            }, makeCapture: { writer, _ in ReferenceCapture(writer: writer, samples: samples) },
            setSessionActive: { _ in })
        await controller.start(keys: ["112:1"], page: 604, snapshot: snapshot, corpus: corpus)
        let limit = Date().addingTimeInterval(3)
        while controller.recognitionAvailable && Date() < limit {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(controller.state, .listening, "Recognition failure must not erase or stop independent recording")
        XCTAssertFalse(controller.recognitionAvailable)
        XCTAssertTrue(controller.hiddenIDs.isEmpty)
        XCTAssertNotNil(controller.message)
        // Explicitly injected recognition is fault simulation, not ASR evidence.
        let continuation = try XCTUnwrap(late)
        continuation.resume(returning: .init(runs: [
            [.init(text: "قل", start: 0, end: 0.5, probability: 1),
             .init(text: "هو", start: 0.5, end: 1, probability: 1)]
        ], hasUnresolvedSpeech: false))
        await Task.yield()
        await controller.finish()
        XCTAssertEqual(controller.state, .stopped)
        let record = try XCTUnwrap(controller.record)
        XCTAssertTrue(record.evidence.isEmpty, "Timed-out recognition must not create late progress")
        let journal = QuranRecitationJournal(root: root)
        let take = try XCTUnwrap(record.takes.first)
        let audio = try AVAudioFile(forReading: journal.audio(session: record.id, take: take.id))
        XCTAssertEqual(audio.length, Int64(samples.count))
        XCTAssertTrue(try journal.load(record.id).evidence.isEmpty)
    }
    @MainActor func testInterruptedPermissionCannotStartLateSession() async throws {
        let pending = expectation(description: "Permission boundary")
        var answer: CheckedContinuation<Bool, Never>?
        let controller = QuranRecitationController(requestPermission: {
            await withCheckedContinuation { answer = $0; pending.fulfill() }
        })
        let unused = QCFV2Snapshot(resource_group: "mushafs", resource_id: 1,
            resource_content_id: 382, schema_version: 1, sync_sequence: 0, records: [])
        let start = Task { await controller.start(keys: ["112:1"], page: 604, snapshot: unused, corpus: []) }
        await fulfillment(of: [pending], timeout: 3)
        XCTAssertEqual(controller.state, .permission)
        await controller.pause()
        try XCTUnwrap(answer).resume(returning: true)
        await start.value
        XCTAssertEqual(controller.state, .idle)
        XCTAssertNil(controller.record); XCTAssertTrue(controller.hiddenIDs.isEmpty)
    }

    @MainActor func testCaptureStartupFailureClosesAudioAndRetainsResumableSession() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let bytes = try XCTUnwrap(QCFV2ContentCache.bundledSnapshot())
        let snapshot = try JSONDecoder().decode(QCFV2Snapshot.self, from: bytes).validated()
        let corpus = try XCTUnwrap(QuranResources.corpus)
        var activations: [Bool] = []
        let controller = QuranRecitationController(requestPermission: { true }, archiveRoot: root,
            makeCapture: { _, _ in throw CocoaError(.fileWriteUnknown) },
            setSessionActive: { activations.append($0) })
        await controller.start(keys: ["112:1"], page: 604, snapshot: snapshot, corpus: corpus)
        XCTAssertEqual(controller.state, .paused); XCTAssertNotNil(controller.message)
        XCTAssertEqual(activations, [true, false], "Release audio ownership once, including startup failure")
        let record = try XCTUnwrap(controller.record)
        let saved = try QuranRecitationJournal(root: root).load(record.id)
        XCTAssertEqual(saved.phase, .paused)
        XCTAssertEqual(saved.takes.count, 1); XCTAssertTrue(saved.takes[0].closed)
        XCTAssertEqual(saved.takes[0].frames, 0); XCTAssertTrue(saved.evidence.isEmpty)
        XCTAssertTrue(try MushafRecordingArchive.takes(session: saved.id, base: root).isEmpty)
    }
    /// Uses actual reference PCM, model, alignment, journal and reopened files.
    /// It exercises the controller lifecycle without pretending to be a live mic.
    @MainActor func testActualRecognitionSessionPausesRestoresResumesAndFinishesWithoutReplacingAudio() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let bytes = try XCTUnwrap(QCFV2ContentCache.bundledSnapshot())
        let snapshot = try JSONDecoder().decode(QCFV2Snapshot.self, from: bytes).validated()
        let corpus = try XCTUnwrap(QuranResources.corpus)
        let reference = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "112001", withExtension: "mp3"))
        let samples = try AudioProcessor.loadAudioAsFloatArray(fromPath: reference.path)
        func controller() -> QuranRecitationController {
            QuranRecitationController(requestPermission: { true }, archiveRoot: root, drainTimeout: 120,
                makeCapture: { writer, _ in ReferenceCapture(writer: writer, samples: samples) },
                setSessionActive: { _ in })
        }
        NSLog("NOOR_SESSION_INTEGRATION begin")
        let original = controller()
        NSLog("NOOR_SESSION_INTEGRATION start.begin")
        await original.start(keys: ["112:1"], page: 604, snapshot: snapshot, corpus: corpus)
        XCTAssertEqual(original.state, .listening)
        XCTAssertTrue(original.hiddenIDs.isEmpty, "Opening the microphone must not blank the page before real recognized word evidence")
        NSLog("NOOR_SESSION_INTEGRATION pause.begin")
        await original.pause()
        NSLog("NOOR_SESSION_INTEGRATION pause.end")
        XCTAssertEqual(original.state, .paused); XCTAssertNil(original.message)
        let first = try XCTUnwrap(original.record)
        XCTAssertEqual(first.takes.count, 1); XCTAssertTrue(first.takes[0].closed)
        XCTAssertEqual(first.takes[0].frames, Int64(samples.count))
        XCTAssertGreaterThanOrEqual(first.evidence.count, 2, "Actual reference speech must produce authentic native word evidence")
        let observed = try XCTUnwrap(first.observedSpeech)
        XCTAssertFalse(observed.isEmpty)
        XCTAssertEqual(first.wordingEvents, [], "Correct real reference speech must not produce unsupported error alerts")
        let timed = observed.flatMap { $0.wordObservations ?? [] }
        XCTAssertFalse(timed.isEmpty, "Actual backend word evidence must reach the saved session")
        XCTAssertTrue(timed.contains { $0.startInTakeSeconds != nil && $0.endInTakeSeconds != nil })
        XCTAssertTrue(observed.allSatisfy { $0.evidenceVersion == 1 && $0.recognitionWindowID != nil && $0.processingConfiguration != nil })
        XCTAssertTrue(observed.contains { !$0.words.isEmpty }, "The real backend must persist its observed words, not only reference matches")
        XCTAssertTrue(observed.allSatisfy { $0.takeID == first.takes[0].id && $0.end <= first.duration + 0.1 })
        let independentlyLoaded = try QuranRecitationJournal(root: root).load(first.id)
        XCTAssertEqual(independentlyLoaded.observedSpeech, observed, "Decoded speech must survive a separate journal read")
        XCTAssertTrue(observed.allSatisfy {
            $0.modelRevision == QuranRecognitionWorker.shared.capabilities.modelRevision
                && $0.modelID == QuranRecognitionWorker.shared.capabilities.modelID
        })
        let verseKeys = corpus.flatMap { surah in surah.ayahs.map { "\(surah.number):\($0.number)" } }
        let verseID = try XCTUnwrap(verseKeys.firstIndex(of: "112:1")) + 1
        XCTAssertEqual(original.hiddenIDs, Set(snapshot.records.filter {
            $0.record_type == "mushaf_word" && $0.char_type_name == "word" && $0.verse_id == verseID
        }.map(\.id)).subtracting(original.revealed))
        let journal = QuranRecitationJournal(root: root)
        let firstURL = journal.audio(session: first.id, take: first.takes[0].id)
        let firstAudio = try Data(contentsOf: firstURL)
        let removedTake = try XCTUnwrap(MushafRecordingArchive.takes(session: first.id, base: root).first)
        try MushafRecordingArchive.moveAudio(removedTake, toDeleted: true, base: root)
        let reopened = controller()
        NSLog("NOOR_SESSION_INTEGRATION restore.begin")
        await reopened.restore(id: first.id, snapshot: snapshot, corpus: corpus)
        XCTAssertEqual(reopened.state, .paused); XCTAssertNil(reopened.message)
        XCTAssertEqual(reopened.revealed, Set(first.evidence.map(\.nativeID)))
        XCTAssertEqual(reopened.record?.observedSpeech, observed)
        XCTAssertEqual(reopened.hiddenIDs, original.hiddenIDs,
            "Restoring a session must preserve the same hidden-word scope and durable progress")
        let recoverable = try XCTUnwrap(MushafRecordingArchive.deletedTakes(session: first.id, base: root).first)
        XCTAssertEqual(try Data(contentsOf: recoverable.url), firstAudio)
        try MushafRecordingArchive.moveAudio(recoverable, toDeleted: false, base: root)
        NSLog("NOOR_SESSION_INTEGRATION resume.begin")
        await reopened.resume(); XCTAssertEqual(reopened.state, .listening)
        NSLog("NOOR_SESSION_INTEGRATION finish.begin")
        await reopened.finish();
        NSLog("NOOR_SESSION_INTEGRATION finish.end")
        XCTAssertEqual(reopened.state, .stopped)
        XCTAssertFalse(reopened.hasSession); XCTAssertTrue(reopened.hiddenIDs.isEmpty)
        let finished = try journal.load(first.id)
        XCTAssertEqual(finished.phase, .finished); XCTAssertNotNil(finished.finishedAt)
        XCTAssertEqual(finished.takes.count, 2); XCTAssertTrue(finished.takes.allSatisfy(\.closed))
        XCTAssertEqual(Set(finished.evidence.map(\.takeID)), Set(finished.takes.map(\.id)))
        XCTAssertEqual(try Data(contentsOf: firstURL), firstAudio)
        let playable = try MushafRecordingArchive.takes(session: first.id, base: root)
        XCTAssertEqual(playable.count, 2)
        for take in playable {
            let file = try AVAudioFile(forReading: take.url)
            XCTAssertEqual(file.length, Int64(samples.count))
            NSLog("NOOR_SESSION_INTEGRATION audio.prepare.begin")
            XCTAssertTrue(try AVAudioPlayer(contentsOf: take.url).prepareToPlay())
            NSLog("NOOR_SESSION_INTEGRATION audio.prepare.end")
        }
        NSLog("NOOR_SESSION_INTEGRATION reopen.finished")
        let finishedReopened = controller()
        await finishedReopened.restore(id: first.id, snapshot: snapshot, corpus: corpus)
        XCTAssertEqual(finishedReopened.state, .stopped)
        XCTAssertEqual(finishedReopened.record?.evidence.count, finished.evidence.count)
    }
    @MainActor func testRecognizedRevealKeepsActualPageAndAccessibleTextStable() async throws {
        let bytes = try XCTUnwrap(QCFV2ContentCache.bundledSnapshot())
        let snapshot = try JSONDecoder().decode(QCFV2Snapshot.self, from: bytes).validated()
        let rows = try OriginalMushafRows.load(); try rows.validate(snapshot)
        try OriginalMushafCompanion.register()
        let fonts = MushafFonts(); await fonts.load("QCF2604"); XCTAssertNil(fonts.error)
        let corpus = try XCTUnwrap(QuranResources.corpus)
        let keys = corpus.flatMap { surah in surah.ayahs.map { "\(surah.number):\($0.number)" } }
        let page = OriginalPageData.page(604, snapshot: snapshot, rows: rows, keys: keys)
        let canvas = OriginalMushafCanvas(frame: CGRect(origin: .zero, size: OriginalMushafCanvas.pageSize))
        canvas.hiddenTextAccessibilityHint = "نص الآية مخفي للتسميع؛ يظهر عندما يتعرف النظام على تلاوتك."
        canvas.allowsVerseSelection = false
        canvas.configure(page: page, corpus: corpus)
        XCTAssertTrue(canvas.renderedSuccessfully)
        let original = canvas.regions.map(\.rect)
        let lines = canvas.rowGeometry.map(\.ink)
        let ornaments = canvas.ornamentBounds
        let hidden = Set(MushafStudyWordIndex(snapshot: snapshot, keys: keys).words["112:1"] ?? [])
        XCTAssertFalse(hidden.isEmpty)
        canvas.hiddenWordIDs = hidden
        let elements = canvas.accessibilityElements as? [UIAccessibilityElement] ?? []
        let verse = try XCTUnwrap(elements.first { $0.accessibilityIdentifier == "reader.verse.112:1" })
        XCTAssertTrue(verse.accessibilityLabel?.contains("مخفي للتسميع") == true)
        XCTAssertFalse(verse.accessibilityLabel?.contains("كشف الآية") == true)
        XCTAssertFalse(verse.accessibilityLabel?.contains(corpus[111].ayahs[0].text) == true)
        for id in hidden {
            canvas.hiddenWordIDs.remove(id)
            XCTAssertEqual(canvas.regions.map(\.rect), original)
            XCTAssertEqual(canvas.rowGeometry.map(\.ink), lines)
            XCTAssertEqual(canvas.ornamentBounds, ornaments)
        }
        XCTAssertTrue(verse.accessibilityLabel?.contains(corpus[111].ayahs[0].text) == true)
    }
    @MainActor func testRecitationBuildContainsCompleteMushafResources() async throws {
        XCTAssertNotNil(Bundle.main.url(forResource: "qcf-v2-manifest", withExtension: "json"))
        for page in 1...604 {
            XCTAssertNotNil(Bundle.main.url(forResource: "p\(page)", withExtension: "ttf"), "Missing authentic page font \(page)")
        }
        try OriginalMushafCompanion.register()
        let fonts = MushafFonts()
        await fonts.load("QCF2001"); await fonts.load("QCF2604")
        XCTAssertNil(fonts.error)
        XCTAssertNotNil(fonts.names["QCF2001"])
        XCTAssertNotNil(fonts.names["QCF2604"])
    }

    @MainActor func testDeniedMicrophoneDoesNotCreateOrHideSession() async throws {
        let controller = QuranRecitationController(requestPermission: { false })
        // Denial must stop before binding fonts, loading the model, or creating
        // any recording. An empty snapshot verifies that boundary.
        let unused = QCFV2Snapshot(resource_group: "mushafs", resource_id: 1,
            resource_content_id: 382, schema_version: 1, sync_sequence: 0, records: [])
        await controller.start(keys: ["112:1"], page: 604, snapshot: unused, corpus: [])
        XCTAssertEqual(controller.state, .idle)
        XCTAssertTrue(controller.permissionDenied)
        XCTAssertNil(controller.record)
        XCTAssertFalse(controller.hasSession)
        XCTAssertTrue(controller.hiddenIDs.isEmpty)
        XCTAssertNotNil(controller.message)
    }

    func testBundledOfflineModelProducesTimedQuranAnchorsAndRejectsSilence() async throws {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(bundle.url(forResource: "112001", withExtension: "mp3"))
        let samples = try AudioProcessor.loadAudioAsFloatArray(fromPath: url.path)
        let worker = QuranRecognitionWorker()
        try await worker.prepare()
        let result = try await worker.recognize(.init(samples: samples, startFrame: 0, endFrame: Int64(samples.count)))
        let expected = ["قل", "هو", "الله", "احد"].enumerated().map {
            QuranAlignedWord(id: $0.offset + 1, verse: "112:1", page: 604, aliases: [[$0.element]])
        }
        var tracker = QuranRecitationTracker(expected: expected)
        let take = UUID()
        for run in result.runs { try tracker.consume(run, takeID: take) }
        XCTAssertGreaterThanOrEqual(tracker.revealedIDs.count, 2, "A bundled model must demonstrate useful timed Quran recognition, not merely load.")
        XCTAssertTrue(tracker.evidence.allSatisfy { $0.end <= Double(samples.count) / 16_000 + 0.1 })
        let silent = try await worker.recognize(.init(samples: Array(repeating: 0, count: 128_000), startFrame: 0, endFrame: 128_000))
        XCTAssertTrue(silent.runs.isEmpty, "No acoustic evidence means no progressive reveal.")
    }

    func testQuietActualReferenceStillAnchorsWhileNoiseCannotRevealWords() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "112001", withExtension: "mp3"))
        let original = try AudioProcessor.loadAudioAsFloatArray(fromPath: url.path)
        let quiet = original.map { $0 * 0.03 }
        let expected = ["قل", "هو", "الله", "احد"].enumerated().map {
            QuranAlignedWord(id: $0.offset + 1, verse: "112:1", page: 604, aliases: [[$0.element]])
        }
        let worker = QuranRecognitionWorker()
        let result = try await worker.recognize(.init(samples: quiet, startFrame: 0, endFrame: Int64(quiet.count)))
        var tracker = QuranRecitationTracker(expected: expected)
        for run in result.runs { try tracker.consume(run, takeID: UUID()) }
        XCTAssertGreaterThanOrEqual(tracker.revealedIDs.count, 2,
            "Actual quiet speech must produce real timed Quran anchors; a working level meter is insufficient")
        // Deterministic broadband acoustic control, not spoken fixture text.
        var seed: UInt32 = 14
        let noise: [Float] = (0..<128000).map { _ in
            seed = 1664525 &* seed &+ 1013904223
            return (Float(seed) / Float(UInt32.max) * 2 - 1) * 0.08
        }
        let control = try await worker.recognize(.init(samples: noise, startFrame: 0, endFrame: Int64(noise.count)))
        var controlTracker = QuranRecitationTracker(expected: expected)
        for run in control.runs { try controlTracker.consume(run, takeID: UUID()) }
        XCTAssertTrue(controlTracker.revealedIDs.isEmpty, "Noise must not create Quran progress after conditioning")
    }

    func testVeryWeakActualSpeechAnchorsButAmplifiedWeakNoiseDoesNot() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "112001", withExtension: "mp3"))
        let original = try AudioProcessor.loadAudioAsFloatArray(fromPath: url.path)
        let expected = ["قل", "هو", "الله", "احد"].enumerated().map {
            QuranAlignedWord(id: $0.offset + 1, verse: "112:1", page: 604, aliases: [[$0.element]])
        }
        let worker = QuranRecognitionWorker()
        let weakSpeech = original.map { $0 * 0.003 }
        let result = try await worker.recognize(.init(samples: weakSpeech, startFrame: 0, endFrame: Int64(weakSpeech.count)))
        var speechTracker = QuranRecitationTracker(expected: expected)
        for run in result.runs { try speechTracker.consume(run, takeID: UUID()) }
        XCTAssertGreaterThanOrEqual(speechTracker.revealedIDs.count, 2,
            "Increased gain must improve actual very weak speech recognition")
        var seed: UInt32 = 14
        let weakNoise: [Float] = (0..<128000).map { _ in
            seed = 1664525 &* seed &+ 1013904223
            return (Float(seed) / Float(UInt32.max) * 2 - 1) * 0.0005
        }
        let amplified = try QuranRecognitionAudio.conditioned(weakNoise)
        XCTAssertGreaterThan(amplified.map { abs($0) }.max() ?? 0, 0.05,
            "The negative control must exercise amplification, not bypass inference as silence")
        let control = try await worker.recognize(.init(samples: weakNoise, startFrame: 0, endFrame: Int64(weakNoise.count)))
        var noiseTracker = QuranRecitationTracker(expected: expected)
        for run in control.runs { try noiseTracker.consume(run, takeID: UUID()) }
        XCTAssertTrue(noiseTracker.revealedIDs.isEmpty, "Amplified background noise must not advance Quran words")
    }

    func testActualQuietReferenceWithDCFaultStillAnchorsAndFlatlineCannotRevealWords() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "112001", withExtension: "mp3"))
        XCTAssertEqual(SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined(),
                       "2b0db8027952e0e7f1620467a34ed908f117a67399765ef538e182e7fb83f7ec")
        let original = try AudioProcessor.loadAudioAsFloatArray(fromPath: url.path)
        let faulted = original.map { $0 * 0.03 + 0.15 }
        let expected = ["قل", "هو", "الله", "أحد"].enumerated().map {
            QuranAlignedWord(id: $0.offset + 1, verse: "112:1", page: 604,
                aliases: [[QuranAlignedWord.normalize($0.element)]])
        }
        let worker = QuranRecognitionWorker()
        let output = try await worker.recognize(.init(samples: faulted, startFrame: 0, endFrame: Int64(faulted.count)))
        var tracker = QuranRecitationTracker(expected: expected)
        for run in output.runs { try tracker.consume(run, takeID: UUID()) }
        XCTAssertGreaterThanOrEqual(tracker.revealedIDs.count, 2,
            "Real quiet speech with an injected DC fault must still establish actual word evidence")
        let constant = Array(repeating: Float(0.15), count: 64000)
        let control = try await worker.recognize(.init(samples: constant, startFrame: 0, endFrame: 64000))
        XCTAssertTrue(control.runs.isEmpty, "A flat digital signal cannot become Quran progress")
        XCTAssertEqual(faulted, original.map { $0 * 0.03 + 0.15 }, "Original input remains unchanged")
    }
    func testActualAudioAndSessionEvidenceSurviveIndependentReopening() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let journal = QuranRecitationJournal(root: root)
        var record = QuranRecitationRecord(keys: ["112:1"], originPage: 604)
        try journal.create(record)
        var take = QuranRecitationTake()
        let file = journal.audio(session: record.id, take: take.id)
        record.takes = [take]; record.phase = .recording; try journal.save(record)
        let writer = try QuranPCMWriter(url: file, onWindow: { _ in }, onFailure: { XCTFail("Unexpected recording failure: \($0)") })
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "112001", withExtension: "mp3"))
        let samples = try AudioProcessor.loadAudioAsFloatArray(fromPath: url.path)
        for start in stride(from: 0, to: samples.count, by: 4096) {
            writer.append(Array(samples[start..<min(start + 4096, samples.count)]))
        }
        let saved: Result<Int64, Error> = await withCheckedContinuation { continuation in
            writer.finish { continuation.resume(returning: $0) }
        }
        take.frames = try saved.get(); take.closed = true
        record.takes = [take]; record.phase = .paused; record.recognitionUnavailable = true
        try journal.save(record)
        let reopened = try QuranRecitationJournal(root: root).load(record.id)
        XCTAssertEqual(reopened.takes[0].frames, Int64(samples.count))
        let audio = try AVAudioFile(forReading: file)
        XCTAssertEqual(audio.length, Int64(samples.count))
        let player = try AVAudioPlayer(contentsOf: file)
        XCTAssertTrue(player.prepareToPlay())
        XCTAssertEqual(player.duration, Double(samples.count) / 16_000, accuracy: 0.02)
        let archived = try MushafRecordingArchive.takes(session: record.id, base: root)
        XCTAssertEqual(archived.map(\.id), [take.id])
        XCTAssertEqual(archived.first?.duration ?? 0, player.duration, accuracy: 0.02)
        let metadata = try XCTUnwrap(MushafRecordingArchive.metadata(session: record.id, base: root))
        XCTAssertEqual(metadata.keys, record.keys)
        let export = try XCTUnwrap(MushafRecordingArchive.exportMetadata(base: root).first)
        XCTAssertEqual(export.files.map(\.id), [take.id])
        let rawSession = try XCTUnwrap(export.recognizedSession)
        let recovered = try JSONDecoder().decode(QuranRecitationRecord.self, from: rawSession)
        XCTAssertEqual(recovered.takes, record.takes)
    }
}

private final class ReferenceCapture: QuranAudioCapture {
    let writer: QuranPCMWriter
    let samples: [Float]
    init(writer: QuranPCMWriter, samples: [Float]) { self.writer = writer; self.samples = samples }
    func start() throws {
        for start in stride(from: 0, to: samples.count, by: 16_000) {
            writer.append(Array(samples[start..<min(start + 16_000, samples.count)]))
        }
    }
    func stop() async -> Result<Int64, Error> {
        await withCheckedContinuation { continuation in writer.finish { continuation.resume(returning: $0) } }
    }
}

private actor UnavailableStartupProvider: QuranSpeechRecognitionProvider {
    private(set) var prepareAttempts = 0
    nonisolated var capabilities: QuranRecognitionCapabilities { QuranRecognitionWorker.shared.capabilities }
    func prepare() async throws { prepareAttempts += 1; throw CocoaError(.fileNoSuchFile) }
    func recognize(_ window: QuranAudioWindow) async throws -> QuranRecognitionWorker.Result {
        throw CocoaError(.fileNoSuchFile)
    }
}
