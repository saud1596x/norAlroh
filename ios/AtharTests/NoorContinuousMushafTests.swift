import XCTest
import UIKit
import WhisperKit
@testable import Athar

@MainActor final class NoorContinuousMushafTests: XCTestCase {
    func testRollingWindowTracksIndependentPassagesInAudioOrderWithoutFillingTheGap() throws {
        let first = ["قل", "هو", "الله", "أحد"], second = ["قل", "أعوذ", "برب", "الناس"]
        let words = first.enumerated().map { QuranAlignedWord(id: $0.offset + 1, verse: "112:1", page: 604, aliases: [[QuranAlignedWord.normalize($0.element)]]) }
            + (5...30).map { QuranAlignedWord(id: $0, verse: "113:1", page: 604, aliases: [["فاصل"]]) }
            + second.enumerated().map { QuranAlignedWord(id: $0.offset + 31, verse: "114:1", page: 604, aliases: [[QuranAlignedWord.normalize($0.element)]]) }
        var tracker = QuranRecitationTracker(expected: words)
        let heard = (first + second).enumerated().map { QuranHeardWord(text: $0.element,
            start: Double($0.offset), end: Double($0.offset) + 0.8, probability: 0.99) }
        let evidence = try tracker.consume(heard, takeID: UUID())
        XCTAssertEqual(evidence.map(\.nativeID), [1, 2, 3, 4, 31, 32, 33, 34])
        XCTAssertEqual(evidence.last?.verse, "114:1")
        XCTAssertFalse(tracker.revealedIDs.contains(20))
        var ambiguous = QuranRecitationTracker(expected: [
            .init(id: 1, verse: "112:1", page: 604, aliases: [["الله"]]),
            .init(id: 2, verse: "112:1", page: 604, aliases: [["الصمد"]]),
            .init(id: 3, verse: "112:2", page: 604, aliases: [["الله"]]),
            .init(id: 4, verse: "112:2", page: 604, aliases: [["الصمد"]])])
        XCTAssertTrue(try ambiguous.consume([
            .init(text: "الله", start: 0, end: 0.8, probability: 0.99),
            .init(text: "الصمد", start: 1, end: 1.8, probability: 0.99)], takeID: UUID()).isEmpty)
        // A shorter prefix cannot preempt a stronger overlapping anchor.
        // These isolated lexical fixtures are not rendered Quran content.
        let overlap = ["قال", "رب", "اني"].enumerated().map {
            QuranAlignedWord(id: $0.offset + 1, verse: "2:1", page: 2, aliases: [[$0.element]])
        } + ["رب", "اني", "اعوذ", "بك"].enumerated().map {
            QuranAlignedWord(id: $0.offset + 4, verse: "2:2", page: 2, aliases: [[$0.element]])
        }
        var overlapping = QuranRecitationTracker(expected: overlap)
        let actual = ["قال", "رب", "اني", "اعوذ", "بك"].enumerated().map {
            QuranHeardWord(text: $0.element, start: Double($0.offset), end: Double($0.offset) + 0.8, probability: 0.99)
        }
        XCTAssertEqual(try overlapping.consume(actual, takeID: UUID()).map(\.nativeID), [4, 5, 6, 7])
    }
    func testTextVisibilityChangesDuringCaptureWithoutLosingAssistanceOrSession() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let snapshot = try JSONDecoder().decode(QCFV2Snapshot.self,
            from: XCTUnwrap(QCFV2ContentCache.bundledSnapshot())).validated()
        let corpus = try XCTUnwrap(QuranResources.corpus)
        let controller = QuranRecitationController(requestPermission: { true }, archiveRoot: root,
            makeCapture: { writer, _ in ContinuousReferenceCapture(writer) }, setSessionActive: { _ in })
        await controller.start(keys: ["112:1"], page: 604, snapshot: snapshot, corpus: corpus, closedText: true)
        let id = try XCTUnwrap(controller.record?.id), takeID = try XCTUnwrap(controller.record?.takes.last?.id)
        XCTAssertEqual(controller.hiddenIDs.count, 4)
        XCTAssertTrue(controller.setPracticeTextHidden(false))
        XCTAssertTrue(controller.hiddenIDs.isEmpty)
        XCTAssertEqual(controller.record?.textExposureOccurred, true)
        XCTAssertEqual(controller.record?.takes.last?.textExposureOccurred, true)
        XCTAssertTrue(controller.setPracticeTextHidden(true))
        XCTAssertEqual(controller.hiddenIDs.count, 4)
        XCTAssertEqual(controller.record?.textExposureOccurred, true, "Hiding again cannot erase assistance")
        XCTAssertEqual(controller.state, .listening)
        XCTAssertEqual(controller.record?.id, id); XCTAssertEqual(controller.record?.takes.last?.id, takeID)
        XCTAssertTrue(controller.revealed.isEmpty); XCTAssertTrue(controller.record?.evidence.isEmpty == true)
        await controller.pause()
        XCTAssertTrue(controller.setPracticeTextHidden(false))
        let saved = try QuranRecitationJournal(root: root).load(id)
        XCTAssertEqual(saved.practiceTextHidden, false)
        let reopened = QuranRecitationController(archiveRoot: root)
        await reopened.restore(id: id, snapshot: snapshot, corpus: corpus)
        XCTAssertFalse(reopened.practiceTextHidden); XCTAssertTrue(reopened.hiddenIDs.isEmpty)
        await controller.finish()
    }

    func testVisibleTextTracksRecognizedWordsAcrossAyahsWithoutHidingOrReshapingThePage() async throws {
        // Original public PCM supplies capture/VAD. The timed observations are
        // injected explicitly: this verifies controller-to-native-canvas wiring,
        // not recognition accuracy, real microphone latency or human Tajweed.
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let snapshot = try JSONDecoder().decode(QCFV2Snapshot.self,
            from: XCTUnwrap(QCFV2ContentCache.bundledSnapshot())).validated()
        let corpus = try XCTUnwrap(QuranResources.corpus)
        let keys = corpus.flatMap { s in s.ayahs.map { "\(s.number):\($0.number)" } }
        let wordIndex = MushafStudyWordIndex(snapshot: snapshot, keys: keys)
        let firstIDs = try XCTUnwrap(wordIndex.words["112:1"])
        let secondIDs = try XCTUnwrap(wordIndex.words["112:2"])
        XCTAssertEqual(firstIDs.count, 4); XCTAssertEqual(secondIDs.count, 2)
        let reference = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "112001", withExtension: "mp3"))
        let samples = try AudioProcessor.loadAudioAsFloatArray(fromPath: reference.path)
        XCTAssertGreaterThanOrEqual(samples.count, 32_000)
        var input: ContinuousReferenceCapture?
        let controller = QuranRecitationController(requestPermission: { true }, archiveRoot: root,
            recognitionProvider: VisibleTrackingProvider(),
            makeCapture: { writer, _ in let feed = ContinuousReferenceCapture(writer); input = feed; return feed },
            setSessionActive: { _ in })
        await controller.start(keys: ["112:1", "112:2", "112:3"], page: 604,
            snapshot: snapshot, corpus: corpus, closedText: false)
        let session = try XCTUnwrap(controller.record?.id)
        XCTAssertEqual(controller.state, .listening); XCTAssertTrue(controller.hiddenIDs.isEmpty)
        XCTAssertNil(controller.activeWordID, "Showing the Quran cannot invent a heard word")

        try OriginalMushafCompanion.register()
        let fonts = MushafFonts(); await fonts.load("QCF2604"); XCTAssertNil(fonts.error)
        let page = OriginalPageData.page(604, snapshot: snapshot, rows: try OriginalMushafRows.load(), keys: keys)
        let canvas = OriginalMushafCanvas(frame: CGRect(origin: .zero, size: OriginalMushafCanvas.pageSize))
        canvas.configure(page: page, corpus: corpus)
        XCTAssertTrue(canvas.renderedSuccessfully)
        let geometry = canvas.regions.map(\.rect), ink = canvas.rowGeometry.map(\.ink), passes = canvas.shapingPasses

        for (expectedVerse, expectedID) in [("112:1", try XCTUnwrap(firstIDs.last)), ("112:2", try XCTUnwrap(secondIDs.last))] {
            input?.append(Array(samples.prefix(32_000)))
            let deadline = Date().addingTimeInterval(8)
            while controller.activeWordID != expectedID && Date() < deadline {
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            XCTAssertEqual(controller.currentVerse, expectedVerse)
            XCTAssertEqual(controller.activeWordID, expectedID)
            XCTAssertEqual(controller.record?.id, session); XCTAssertEqual(controller.state, .listening)
            XCTAssertTrue(controller.hiddenIDs.isEmpty, "Open-text recitation must leave every ayah visible")
            let location = wordIndex.listeningLocation(verse: controller.currentVerse,
                wordID: controller.activeWordID, allowedPages: 1...604)
            XCTAssertEqual(location, MushafStudyWordIndex.PlaybackLocation(verse: expectedVerse, page: 604))
            canvas.selected = controller.currentVerse; canvas.activeWordID = controller.activeWordID
            canvas.hiddenWordIDs = controller.hiddenIDs
            XCTAssertNotNil(canvas.selectionPath(for: expectedVerse))
            XCTAssertNotNil(canvas.activeWordPath(), "The exact recognized word needs a native highlight with text open")
            XCTAssertEqual(canvas.regions.map(\.rect), geometry); XCTAssertEqual(canvas.rowGeometry.map(\.ink), ink)
            XCTAssertEqual(canvas.shapingPasses, passes, "Tracking cannot refit or shrink the approved Mushaf")
        }
        XCTAssertTrue(controller.record?.retainedVisibleVerses?.contains("112:1") == true)
        XCTAssertTrue(controller.setPracticeTextHidden(true))
        XCTAssertTrue(Set(firstIDs).isDisjoint(with: controller.hiddenIDs), "The completed ayah stays visible")
        XCTAssertFalse(controller.hiddenIDs.isEmpty, "Unrecited text can still be concealed on request")
        XCTAssertTrue(controller.setPracticeTextHidden(false)); XCTAssertTrue(controller.hiddenIDs.isEmpty)
        XCTAssertEqual(controller.activeWordID, secondIDs.last, "Changing visibility cannot change recognized position")
        await controller.finish()
    }

    func testDelayedAnalysisCannotOverwriteVisibilityOrTextAssistance() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let journal = QuranRecitationJournal(root: root)
        var record = QuranRecitationRecord(keys: ["112:1"], originPage: 604)
        record.closedTextRequested = true; record.practiceTextHidden = true; record.textExposureOccurred = false
        try journal.create(record)
        var oldAnalysis = record
        record.practiceTextHidden = false; record.textExposureOccurred = true
        try journal.save(record)
        oldAnalysis.observedSpeech = []
        try journal.saveAnalysis(oldAnalysis)
        let saved = try journal.load(record.id)
        XCTAssertEqual(saved.practiceTextHidden, false); XCTAssertEqual(saved.textExposureOccurred, true)
        XCTAssertEqual(saved.observedSpeech, [])
        record.practiceTextHidden = true; record.textExposureOccurred = false
        try journal.save(record)
        oldAnalysis.textExposureOccurred = true; oldAnalysis.recognitionUnavailable = true
        try journal.saveAnalysis(oldAnalysis)
        XCTAssertEqual(try journal.load(record.id).textExposureOccurred, true,
                       "Recognizer failure that exposes text also survives the analysis merge")
    }

    func testAnalysisPersistsActualWindowFramesWithoutReopeningALaterClosedTake() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let journal = QuranRecitationJournal(root: root)
        var record = QuranRecitationRecord(keys: ["112:1"], originPage: 604)
        record.phase = .recording
        record.takes = [.init(startedAt: record.startedAt)]
        try journal.create(record)
        var analysis = record
        analysis.takes[0].frames = 16_000
        analysis.observedSpeech = [.init(takeID: record.takes[0].id, start: 0, end: 1,
            words: ["قل"], unresolved: true, backendID: "journal-regression")]
        try journal.saveAnalysis(analysis)
        var paused = try journal.load(record.id)
        XCTAssertEqual(paused.takes[0].frames, 16_000)
        XCTAssertEqual(paused.observedSpeech, analysis.observedSpeech)
        paused.takes[0].frames = 32_000; paused.takes[0].closed = true; paused.phase = .paused
        paused.practiceTextHidden = false; paused.textExposureOccurred = true
        try journal.save(paused)
        try journal.saveAnalysis(analysis)
        let saved = try journal.load(record.id)
        XCTAssertEqual(saved.phase, .paused); XCTAssertTrue(saved.takes[0].closed)
        XCTAssertEqual(saved.takes[0].frames, 32_000)
        XCTAssertEqual(saved.practiceTextHidden, false); XCTAssertEqual(saved.textExposureOccurred, true)
    }

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
            if number == 1 {
                canvas.hiddenWordIDs = Set(page.words.map(\.id))
                let elements = try XCTUnwrap(canvas.accessibilityElements as? [UIAccessibilityElement])
                XCTAssertTrue(elements.allSatisfy { $0.accessibilityLabel?.contains(canvas.hiddenTextAccessibilityHint) == true },
                              "VoiceOver must not read hidden Quran text")
                canvas.hiddenWordIDs = []
                XCTAssertEqual(canvas.shapingPasses, passes, "Visibility cannot reshape or shift Quran glyphs")
            }
            // Exercise actual Core Text drawing, not metadata validation alone.
            autoreleasepool {
                let format = UIGraphicsImageRendererFormat(); format.preferredRange = .standard
                let renderer = UIGraphicsImageRenderer(size: OriginalMushafCanvas.pageSize, format: format)
                let image = renderer.image { context in canvas.layer.render(in: context.cgContext) }
                if let pixels = image.cgImage?.dataProvider?.data, let bytes = CFDataGetBytePtr(pixels) {
                    XCTAssertTrue(stride(from: 4, to: CFDataGetLength(pixels) - 4, by: 4).contains { offset in
                        (0..<4).contains { bytes[offset + $0] != bytes[$0] }
                    }, "Uniform blank rendering on page \(number)")
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

    func testOriginalTajweedLayersRenderAll604PagesAndPreserveHiddenWordGeometry() async throws {
        executionTimeAllowance = 180
        try OriginalMushafCompanion.register()
        let snapshot = try JSONDecoder().decode(QCFV2Snapshot.self, from: XCTUnwrap(QCFV2ContentCache.bundledSnapshot())).validated()
        let rows = try OriginalMushafRows.load(), corpus = try XCTUnwrap(QuranResources.corpus)
        let keys = corpus.flatMap { s in s.ayahs.map { "\(s.number):\($0.number)" } }
        let canvas = OriginalMushafCanvas(frame: CGRect(origin: .zero, size: OriginalMushafCanvas.pageSize))
        canvas.tajweedEnabled = true
        let reference = OriginalMushafCanvas(frame: canvas.frame), fonts = MushafFonts()
        for number in 1...604 {
            await fonts.load(String(format: "QCF2%03d", number))
            XCTAssertNil(fonts.error)
            let page = OriginalPageData.page(number, snapshot: snapshot, rows: rows, keys: keys)
            reference.configure(page: page, corpus: corpus)
            XCTAssertTrue(reference.renderedSuccessfully)
            let referenceWidth = reference.rowGeometry.filter { $0.kind == "ayah" }.map(\.ink.width).max() ?? 0
            for style in [UIUserInterfaceStyle.light, .dark] {
                canvas.overrideUserInterfaceStyle = style
                canvas.configure(page: page, corpus: corpus)
                XCTAssertTrue(canvas.renderedSuccessfully, "Tajweed \(number)/\(style.rawValue): \(canvas.failureReason ?? "")")
                XCTAssertEqual(Set(canvas.regions.map(\.word)), Set(page.words.map(\.id)))
                XCTAssertTrue(canvas.regions.allSatisfy { canvas.bounds.contains($0.rect) })
                let coloredWidth = canvas.rowGeometry.filter { $0.kind == "ayah" }.map(\.ink.width).max() ?? 0
                XCTAssertGreaterThanOrEqual(coloredWidth, referenceWidth * 0.95,
                    "Colors must not shrink the reading extent: page \(number)")
                XCTAssertLessThanOrEqual(coloredWidth, referenceWidth + 0.1)
                try autoreleasepool {
                    let format = UIGraphicsImageRendererFormat(); format.preferredRange = .standard; format.scale = 1
                    let image = UIGraphicsImageRenderer(size: canvas.bounds.size, format: format).image { context in
                        (style == .dark ? UIColor.black : .white).setFill(); context.fill(canvas.bounds)
                        canvas.layer.render(in: context.cgContext)
                    }
                    let pixels = try XCTUnwrap(image.cgImage?.dataProvider?.data), bytes = try XCTUnwrap(CFDataGetBytePtr(pixels))
                    XCTAssertTrue(stride(from: 0, to: CFDataGetLength(pixels) - 4, by: 4).contains { i in
                        max(max(bytes[i], bytes[i + 1]), bytes[i + 2]) - min(min(bytes[i], bytes[i + 1]), bytes[i + 2]) > 35
                    }, "Original colored layers must actually draw, not a monochrome fallback")
                    if [1, 2, 17, 29, 151, 305, 560, 579, 604].contains(number) {
                        let proof = XCTAttachment(image: image); proof.name = "tajweed-\(number)-\(style.rawValue)"; proof.lifetime = .keepAlways; add(proof)
                    }
                }
            }
            let passes = canvas.shapingPasses, geometry = canvas.regions.map(\.rect)
            canvas.hiddenWordIDs = Set(page.words.map(\.id))
            XCTAssertTrue((canvas.accessibilityElements as? [UIAccessibilityElement] ?? []).allSatisfy { $0.accessibilityLabel?.contains(canvas.hiddenTextAccessibilityHint) == true })
            canvas.hiddenWordIDs = []
            XCTAssertEqual(canvas.shapingPasses, passes); XCTAssertEqual(canvas.regions.map(\.rect), geometry)
        }
        let page = OriginalPageData.page(1, snapshot: snapshot, rows: rows, keys: keys)
        await fonts.load("QCF2001")
        canvas.tajweedEnabled = false; canvas.configure(page: page, corpus: corpus)
        XCTAssertTrue(canvas.renderedSuccessfully, "Turning colors off restores the approved original V2 edition")
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
            if controller.currentVerse != expected, let record = controller.record {
                let diagnostic = try JSONEncoder().encode(record)
                let attachment = XCTAttachment(data: diagnostic, uniformTypeIdentifier: "public.json")
                attachment.name = "public-fixture-recognition-evidence-\(file)"; attachment.lifetime = .keepAlways; add(attachment)
                // Only this test's hash-pinned public fixture/injected capture;
                // never production recordings or user account data. Preserve
                // the actual unresolved words/clock before changing a gate.
                print("NOOR_PUBLIC_PCM_FAILURE_EVIDENCE file=\(file) \(String(decoding:diagnostic,as:UTF8.self))")
            }
            XCTAssertEqual(controller.state, .listening)
            XCTAssertEqual(controller.record?.id, id)
            XCTAssertTrue(controller.hiddenIDs.isEmpty)
            let proof = XCTAttachment(string: "Public fixture \(file); buffer-feed-to-location \(Date().timeIntervalSince(started)) seconds; actual model; injected PCM transport, not a device microphone")
            proof.lifetime = .keepAlways; add(proof)
            print("NOOR_ACTUAL_CONTINUOUS_ANCHOR file=\(file) expected=\(expected) seconds=\(Date().timeIntervalSince(started)) located=\(controller.currentVerse == expected)")
        }
        let position = controller.currentVerse
        await controller.finish()
        XCTAssertEqual(controller.state, .stopped)
        XCTAssertEqual(controller.currentVerse, position)
        XCTAssertEqual(controller.record?.id, id)
    }
}

private struct VisibleTrackingProvider: QuranSpeechRecognitionProvider {
    let capabilities = QuranRecognitionCapabilities(backendID: "visible-tracking-fixture",
        modelID: "injected-timed-observations-not-ASR", modelRevision: "1", configuredLanguage: "ar",
        delivery: .overlappingAudioWindows, processesLocally: true, wordTimestamps: true,
        wordConfidence: true, phonemeEvidence: false, calibratedWordingAssessment: false, validatedTajweedAssessment: false)
    func prepare() async throws {}
    func recognize(_ window: QuranAudioWindow) async throws -> QuranRecognitionWorker.Result {
        let tokens = window.endFrame <= 32_000 ? ["قل", "هو", "الله", "أحد"] : ["قل", "هو", "الله", "أحد", "الله", "الصمد"]
        return .init(runs: [tokens.enumerated().map {
            QuranHeardWord(text: $0.element, start: Double($0.offset) * 0.35,
                end: Double($0.offset + 1) * 0.35, probability: 0.99)
        }], hasUnresolvedSpeech: false)
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
