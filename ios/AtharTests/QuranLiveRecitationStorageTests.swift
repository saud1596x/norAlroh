import XCTest
import AVFoundation
import WhisperKit
@testable import Athar

final class QuranLiveRecitationStorageTests: XCTestCase {
    func testUpgradeDeletesOnlyLearnerRecordingsAndExpiredWorkspaces() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let support = root.appendingPathComponent("Support"), caches = root.appendingPathComponent("Caches")
        let discarded = ["Support/NoorMushafRecordings/old.caf", "Support/NoorRecitation/latest-recitation.m4a",
                         "Caches/NoorLiveRecitation/previous/session.caf"]
        let retained = ["Support/bookmarks.json", "Support/khatmah.json", "Support/account.json",
                        "Caches/reciters/surah.mp3", "Caches/NoorLiveRecitation/current/session.caf"]
        let original = Data([1, 5, 9, 21])
        for name in discarded + retained {
            let file = root.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try original.write(to: file)
        }
        try QuranLiveRecitationStorage.removePreviousRecordings(support: support, caches: caches, keepingProcess: "current")
        for name in discarded { XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(name).path), name) }
        for name in retained { XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(name)), original, name) }
    }

    func testDisposedSessionCannotBeResurrectedByLateAnalysisAndDoesNotEraseAnotherSession() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let journal = QuranRecitationJournal(root: root)
        let first = QuranRecitationRecord(keys: ["112:1"], originPage: 604)
        let second = QuranRecitationRecord(keys: ["1:2"], originPage: 1)
        try journal.create(first); try journal.create(second)
        let original = Data([2, 3, 4])
        try original.write(to: journal.audio(session: first.id, take: UUID()))
        try journal.discard(first.id)
        XCTAssertThrowsError(try journal.saveAnalysis(first))
        XCTAssertThrowsError(try journal.save(first))
        XCTAssertFalse(FileManager.default.fileExists(atPath: journal.folder(first.id).path))
        XCTAssertEqual(try journal.load(second.id).keys, second.keys)
        XCTAssertNoThrow(try journal.discard(first.id), "Repeated close is harmless")
    }

    @MainActor func testFinishClosesActualReferencePCMAndDeletesItsWorkingFiles() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let snapshot = try JSONDecoder().decode(QCFV2Snapshot.self, from: XCTUnwrap(QCFV2ContentCache.bundledSnapshot())).validated()
        let source = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "112001", withExtension: "mp3"))
        let samples = Array(try AudioProcessor.loadAudioAsFloatArray(fromPath: source.path).prefix(16_000))
        XCTAssertEqual(samples.count, 16_000)
        let controller = QuranRecitationController(requestPermission: { true }, archiveRoot: root,
            recognizeWindow: { _ in .init(runs: [], hasUnresolvedSpeech: false) },
            makeCapture: { writer, _ in ReferenceCapture(writer: writer, samples: samples) }, setSessionActive: { _ in })
        await controller.start(keys: ["112:1"], page: 604, snapshot: snapshot, corpus: try XCTUnwrap(QuranResources.corpus))
        XCTAssertEqual(controller.state, .listening)
        await controller.pause()
        let record = try XCTUnwrap(controller.record), take = try XCTUnwrap(record.takes.first)
        let journal = QuranRecitationJournal(root: root)
        XCTAssertEqual(try AudioProcessor.loadAudioAsFloatArray(fromPath: journal.audio(session: record.id, take: take.id).path), samples)
        await controller.finish()
        XCTAssertEqual(controller.state, .stopped)
        XCTAssertFalse(FileManager.default.fileExists(atPath: journal.folder(record.id).path))
        XCTAssertThrowsError(try journal.load(record.id))
    }

    @MainActor func testFinishDuringPermissionCannotOpenCaptureAfterPermissionReturns() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var reply: CheckedContinuation<Bool, Never>?
        var captureOpened = false
        let controller = QuranRecitationController(requestPermission: {
            await withCheckedContinuation { reply = $0 }
        }, archiveRoot: root, makeCapture: { writer, _ in
            captureOpened = true; return ReferenceCapture(writer: writer, samples: [])
        }, setSessionActive: { _ in })
        let snapshot = try JSONDecoder().decode(QCFV2Snapshot.self, from: XCTUnwrap(QCFV2ContentCache.bundledSnapshot())).validated()
        let corpus = try XCTUnwrap(QuranResources.corpus)
        let start = Task { await controller.start(keys: ["112:1"], page: 604, snapshot: snapshot, corpus: corpus) }
        for _ in 0..<100 where reply == nil { await Task.yield() }
        let permission = try XCTUnwrap(reply)
        await controller.finish(); permission.resume(returning: true); await start.value
        XCTAssertEqual(controller.state, .idle); XCTAssertFalse(captureOpened); XCTAssertNil(controller.record)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }

    private final class ReferenceCapture: QuranAudioCapture {
        let writer: QuranPCMWriter, samples: [Float]
        init(writer: QuranPCMWriter, samples: [Float]) { self.writer = writer; self.samples = samples }
        func start() throws { writer.append(samples) }
        func stop() async -> Result<Int64, Error> {
            await withCheckedContinuation { continuation in writer.finish { continuation.resume(returning: $0) } }
        }
    }
}
