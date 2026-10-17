import XCTest
import UIKit
import WhisperKit
@testable import Athar

@MainActor final class NoorContinuousMushafTests: XCTestCase {
    func testEveryCatalogRecordingHasASelectableStableIdentityAndRestorableKeys() throws {
        let voices = NoorMushafReciter.all
        XCTAssertEqual(voices.count, NoorVerseReciter.all.count + NoorReciterCatalog.reciters.count)
        XCTAssertGreaterThan(voices.count, 5)
        XCTAssertEqual(Set(voices.map(\.id)).count, voices.count)
        for voice in voices {
            XCTAssertEqual(NoorMushafReciter.selected(voice.id)?.id, voice.id)
            let keys = voice.playbackKeys(["2:1", "2:2", "19:16", "19:17"])
            if let recording = voice.recording {
                XCTAssertEqual(keys.count, 2)
                XCTAssertEqual(keys.compactMap { NoorAudioIntegrity.reciterRecording($0)?.0 }, [recording, recording])
                XCTAssertEqual(voice.playbackKeys(keys), keys, "Saved whole-surah ranges remain restorable")
                XCTAssertTrue(keys.allSatisfy { NoorAudioIntegrity.url($0) != nil })
            } else { XCTAssertEqual(keys, ["2:1", "2:2", "19:16", "19:17"]) }
        }
    }
    func testSelectingEveryReciterPreservesRecordingOwnershipAndDoesNotStartPlayback() throws {
        let audio = MushafVerseAudio(), lease = UUID()
        XCTAssertTrue(NoorAudioFocus.shared.acquireRecording(lease))
        defer { NoorAudioFocus.shared.releaseRecording(lease) }
        for voice in NoorMushafReciter.all {
            audio.selectReciter(voice)
            XCTAssertEqual(audio.selectedCatalogReciter?.id, voice.id)
            XCTAssertNil(audio.playing); XCTAssertNil(audio.loadingKey)
            XCTAssertFalse(NoorAudioFocus.shared.preparePlayback(UUID()), "Changing preference cannot release the microphone")
        }
    }
    func testAll604OriginalPagesRenderWithoutClippingAndCacheMatchesExactSource() async throws {
        executionTimeAllowance = 180
        try OriginalMushafCompanion.register()
        let snapshot = try JSONDecoder().decode(QCFV2Snapshot.self, from: XCTUnwrap(QCFV2ContentCache.bundledSnapshot())).validated()
        let rows = try OriginalMushafRows.load(), corpus = try XCTUnwrap(QuranResources.corpus)
        let keys = corpus.flatMap { s in s.ayahs.map { "\(s.number):\($0.number)" } }
        let fonts = MushafFonts(), canvas = OriginalMushafCanvas(frame: CGRect(origin: .zero, size: OriginalMushafCanvas.pageSize))
        var rendered = 0
        for number in 1...604 {
            await fonts.load(String(format: "QCF2%03d", number))
            XCTAssertNil(fonts.error)
            let page = OriginalPageData.page(number, snapshot: snapshot, rows: rows, keys: keys)
            canvas.configure(page: page, corpus: corpus)
            XCTAssertTrue(canvas.renderedSuccessfully, "Page \(number): \(canvas.failureReason ?? "")")
            XCTAssertEqual(Set(canvas.regions.map(\.word)), Set(page.words.map(\.id)))
            XCTAssertTrue(canvas.regions.allSatisfy { canvas.bounds.contains($0.rect) })
            let passes = canvas.shapingPasses, geometry = canvas.rowGeometry.map(\.ink)
            canvas.configure(page: page, corpus: corpus)
            XCTAssertEqual(canvas.shapingPasses, passes)
            XCTAssertEqual(canvas.rowGeometry.map(\.ink), geometry)
            // Exercise actual Core Text drawing, not metadata validation alone.
            autoreleasepool {
                let renderer = UIGraphicsImageRenderer(size: OriginalMushafCanvas.pageSize)
                let image = renderer.image { context in canvas.layer.render(in: context.cgContext) }
                if let pixels = image.cgImage?.dataProvider?.data, let bytes = CFDataGetBytePtr(pixels) {
                    XCTAssertTrue(stride(from: 0, to: CFDataGetLength(pixels), by: 113).contains { bytes[$0] != 0 }, "Blank rendering on page \(number)")
                } else { XCTFail("Missing rendered pixels on page \(number)") }
                if [1, 2, 151, 305, 560, 604].contains(number) {
                    let attachment = XCTAttachment(image: image)
                    attachment.name = "native-canvas-page-\(number)"; attachment.lifetime = .keepAlways
                    add(attachment)
                }
            }
            rendered += 1
        }
        XCTAssertEqual(rendered, 604)
    }
    func testVoiceActivityRetainsAllRealReferenceClipsAndRejectsDigitalSilence() throws {
        XCTAssertFalse(try QuranVoiceActivity.scan([Float](repeating: 0, count: 32_000)).hasSpeech)
        XCTAssertThrowsError(try QuranVoiceActivity.scan([.nan]))
        for name in ["001001", "001002", "001003", "112001", "112002", "112003", "112004", "114001", "114002", "114003"] {
            let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "mp3"))
            let samples = try AudioProcessor.loadAudioAsFloatArray(fromPath: url.path)
            let scan = try QuranVoiceActivity.scan(QuranRecognitionAudio.conditioned(samples))
            XCTAssertTrue(scan.hasSpeech, name)
            XCTAssertTrue(scan.intervals.allSatisfy { $0.start >= 0 && $0.end <= Double(samples.count) / 16_000 })
        }
    }
    func testRealPCMChangesSurahWithinOneListeningSessionWithoutStoppingForResults() async throws {
        executionTimeAllowance = 120
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let snapshot = try JSONDecoder().decode(QCFV2Snapshot.self, from: XCTUnwrap(QCFV2ContentCache.bundledSnapshot())).validated()
        let corpus = try XCTUnwrap(QuranResources.corpus), keys = corpus.flatMap { s in s.ayahs.map { "\(s.number):\($0.number)" } }
        var input: ContinuousReferenceCapture?
        let controller = QuranRecitationController(requestPermission: { true }, archiveRoot: root,
            makeCapture: { writer, _ in let feed = ContinuousReferenceCapture(writer); input = feed; return feed }, setSessionActive: { _ in })
        await controller.start(keys: keys, page: 2, snapshot: snapshot, corpus: corpus, automaticScope: true)
        XCTAssertEqual(controller.state, .listening)
        let id = try XCTUnwrap(controller.record?.id)
        for (file, expected) in [("112001", "112:1"), ("114001", "114:1")] {
            let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: file, withExtension: "mp3"))
            let samples = try AudioProcessor.loadAudioAsFloatArray(fromPath: url.path)
            input?.append(samples)
            let started = Date()
            for _ in 0..<400 where controller.currentVerse != expected { try await Task.sleep(nanoseconds: 50_000_000) }
            XCTAssertEqual(controller.currentVerse, expected, "Real decoded PCM must find \(expected) before stopping")
            XCTAssertEqual(controller.state, .listening)
            XCTAssertEqual(controller.record?.id, id)
            XCTAssertTrue(controller.hiddenIDs.isEmpty)
            let proof = XCTAttachment(string: "Public fixture \(file); buffer-feed-to-location \(Date().timeIntervalSince(started)) seconds; actual model; injected PCM transport, not a device microphone")
            proof.lifetime = .keepAlways; add(proof)
        }
        let position = controller.currentVerse
        await controller.finish()
        XCTAssertEqual(controller.state, .stopped)
        XCTAssertEqual(controller.currentVerse, position)
        XCTAssertEqual(controller.record?.id, id)
    }
}

private final class ContinuousReferenceCapture: QuranAudioCapture {
    private let writer: QuranPCMWriter
    init(_ writer: QuranPCMWriter) { self.writer = writer }
    func start() throws {}
    func append(_ samples: [Float]) {
        for offset in stride(from: 0, to: samples.count, by: 16_000) {
            writer.append(Array(samples[offset..<min(samples.count, offset + 16_000)]))
        }
    }
    func stop() async -> Result<Int64, Error> {
        await withCheckedContinuation { continuation in writer.finish { continuation.resume(returning: $0) } }
    }
}
