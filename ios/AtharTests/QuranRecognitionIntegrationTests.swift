import XCTest
import AVFoundation
import UIKit
import WhisperKit
@testable import Athar

/// Real Core ML inference on identified reference audio; this is not a live
/// microphone journey and must not be presented as one in release evidence.
final class QuranRecognitionIntegrationTests: XCTestCase {
    @MainActor func testInterruptedActualReferenceProgressStaysVisibleThroughEmptyResumeUntilFreshRecognition() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let (bytes, response) = try await URLSession.shared.data(from:
            URL(string: "https://noor-quran-sync.onrender.com/v1/mushaf/snapshot")!)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
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
    }

    @MainActor func testDrainTimeoutWithActualPriorEvidenceExposesTextAndRejectsLateDecode() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let (bytes, _) = try await URLSession.shared.data(from:
            URL(string: "https://noor-quran-sync.onrender.com/v1/mushaf/snapshot")!)
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
        let (bytes, response) = try await URLSession.shared.data(from:
            URL(string: "https://noor-quran-sync.onrender.com/v1/mushaf/snapshot")!)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
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
        let endpoint = try XCTUnwrap(URL(string: "https://noor-quran-sync.onrender.com/v1/mushaf/snapshot"))
        let (bytes, response) = try await URLSession.shared.data(from: endpoint)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
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
        let endpoint = try XCTUnwrap(URL(string: "https://noor-quran-sync.onrender.com/v1/mushaf/snapshot"))
        let (bytes, response) = try await URLSession.shared.data(from: endpoint)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        let snapshot = try JSONDecoder().decode(QCFV2Snapshot.self, from: bytes).validated()
        let corpus = try XCTUnwrap(QuranResources.corpus)
        let reference = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "112001", withExtension: "mp3"))
        let samples = try AudioProcessor.loadAudioAsFloatArray(fromPath: reference.path)
        func controller() -> QuranRecitationController {
            QuranRecitationController(requestPermission: { true }, archiveRoot: root, drainTimeout: 120,
                makeCapture: { writer, _ in ReferenceCapture(writer: writer, samples: samples) },
                setSessionActive: { _ in })
        }
        let original = controller()
        await original.start(keys: ["112:1"], page: 604, snapshot: snapshot, corpus: corpus)
        XCTAssertEqual(original.state, .listening)
        XCTAssertTrue(original.hiddenIDs.isEmpty, "Opening the microphone must not blank the page before real recognized word evidence")
        await original.pause()
        XCTAssertEqual(original.state, .paused); XCTAssertNil(original.message)
        let first = try XCTUnwrap(original.record)
        XCTAssertEqual(first.takes.count, 1); XCTAssertTrue(first.takes[0].closed)
        XCTAssertEqual(first.takes[0].frames, Int64(samples.count))
        XCTAssertGreaterThanOrEqual(first.evidence.count, 2, "Actual reference speech must produce authentic native word evidence")
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
        await reopened.restore(id: first.id, snapshot: snapshot, corpus: corpus)
        XCTAssertEqual(reopened.state, .paused); XCTAssertNil(reopened.message)
        XCTAssertEqual(reopened.revealed, Set(first.evidence.map(\.nativeID)))
        XCTAssertEqual(reopened.hiddenIDs, original.hiddenIDs,
            "Restoring a session must preserve the same hidden-word scope and durable progress")
        let recoverable = try XCTUnwrap(MushafRecordingArchive.deletedTakes(session: first.id, base: root).first)
        XCTAssertEqual(try Data(contentsOf: recoverable.url), firstAudio)
        try MushafRecordingArchive.moveAudio(recoverable, toDeleted: false, base: root)
        await reopened.resume(); XCTAssertEqual(reopened.state, .listening)
        await reopened.finish(); XCTAssertEqual(reopened.state, .stopped)
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
            XCTAssertTrue(try AVAudioPlayer(contentsOf: take.url).prepareToPlay())
        }
        let finishedReopened = controller()
        await finishedReopened.restore(id: first.id, snapshot: snapshot, corpus: corpus)
        XCTAssertEqual(finishedReopened.state, .stopped)
        XCTAssertEqual(finishedReopened.record?.evidence.count, finished.evidence.count)
    }
    @MainActor func testRecognizedRevealKeepsActualPageAndAccessibleTextStable() async throws {
        let endpoint = try XCTUnwrap(URL(string: "https://noor-quran-sync.onrender.com/v1/mushaf/snapshot"))
        let (bytes, response) = try await URLSession.shared.data(from: endpoint)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
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
