import XCTest
import AVFoundation
import UIKit
import WhisperKit
@testable import Athar

/// Real Core ML inference on identified reference audio; this is not a live
/// microphone journey and must not be presented as one in release evidence.
final class QuranRecognitionIntegrationTests: XCTestCase {
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
