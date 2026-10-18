import XCTest
@testable import Athar

final class NoorReaderCoreRegressionTests: XCTestCase {
    func testShortSharedOpeningDoesNotJumpFromIkhlasToFalaqBeforeDistinctiveWord() throws {
        let snapshot = try JSONDecoder().decode(QCFV2Snapshot.self,
            from: XCTUnwrap(QCFV2ContentCache.bundledSnapshot())).validated()
        let corpus = try XCTUnwrap(QuranResources.corpus)
        let keys = corpus.flatMap { s in s.ayahs.map { "\(s.number):\($0.number)" } }
        let native = snapshot.records.filter { $0.record_type == "mushaf_word" && $0.char_type_name == "word" }.map {
            QuranNativeWord(id:$0.id, verse:keys[$0.verse_id! - 1], position:$0.position_in_verse!,
                page:$0.page_number!, glyph:$0.text!)
        }
        let script = try JSONDecoder().decode(QuranWordScript.self, from: Data(contentsOf:
            XCTUnwrap(Bundle.main.url(forResource:"recitation-word-script", withExtension:"json"))))
        var tracker = QuranRecitationTracker(expected:try script.bind(native:native, verseKeys:keys))
        let take = UUID()
        func heard(_ text:[String], at offset:Double) -> [QuranHeardWord] {
            text.enumerated().map { .init(text:$0.element, start:offset+Double($0.offset)*0.4,
                end:offset+Double($0.offset)*0.4+0.3, probability:0.99) }
        }
        XCTAssertFalse(try tracker.consume(heard(["قل","هو","الله","أحد"], at:0), takeID:take).isEmpty)
        XCTAssertTrue(try tracker.consume(heard(["قل","أعوذ"], at:2), takeID:take).isEmpty,
                      "A shared partial is not a reliable nearby surah transition")
        let resolved = try tracker.consume(heard(["قل","أعوذ","برب","الناس"], at:3), takeID:take)
        XCTAssertEqual(Set(resolved.map(\.verse)), ["114:1"])
        XCTAssertFalse(tracker.evidence.contains { $0.verse == "113:1" })
    }
    func testTimedPlaybackFollowsRealPageBoundaryAndDoesNotInventWholeSurahOffsets() throws {
        let snapshot = try JSONDecoder().decode(QCFV2Snapshot.self,
            from: XCTUnwrap(QCFV2ContentCache.bundledSnapshot())).validated()
        let corpus = try XCTUnwrap(QuranResources.corpus)
        let keys = corpus.flatMap { s in s.ayahs.map { "\(s.number):\($0.number)" } }
        let index = MushafStudyWordIndex(snapshot: snapshot, keys: keys)
        let nextVerse = try XCTUnwrap(keys.first { index.pages[$0]?.first == 4 })
        let finalWord = try XCTUnwrap(index.words[nextVerse]?.last)
        XCTAssertEqual(index.playbackLocation(key: nextVerse, wordID: finalWord, currentPage: 3,
            allowedPages: 1...604)?.page, 4)
        XCTAssertEqual(index.playbackLocation(key: nextVerse, wordID: nil, currentPage: 4,
            allowedPages: 1...604)?.page, 4, "A pause between words must not jump back")
        XCTAssertNil(index.playbackLocation(key: nextVerse, wordID: finalWord, currentPage: 3,
            allowedPages: 3...3), "Playback cannot leave a reading-only daily range")
        let unrelatedWord = try XCTUnwrap(index.words["1:1"]?.first)
        XCTAssertEqual(index.playbackLocation(key: nextVerse, wordID: unrelatedWord, currentPage: 3,
            allowedPages: 1...604)?.page, 4, "Another ayah cannot provide a word cursor")
        let reciter = try XCTUnwrap(NoorReciterCatalog.reciters.first)
        let recording = try XCTUnwrap(NoorAudioIntegrity.reciterKey(reciter, surah: 2))
        XCTAssertEqual(index.playbackLocation(key: recording, wordID: finalWord, currentPage: 50,
            allowedPages: 1...604)?.verse, "2:1", "An untimed surah has only its known starting position")
    }
    @MainActor func testExistingReaderPreferencesRestoreTheSameLegacyRecordingAndCacheKey() throws {
        for directory in ["Abdurrahmaan_As-Sudais_64kbps", "Saood_ash-Shuraym_64kbps"] {
            let saved = try XCTUnwrap(NoorMushafReciter.selected(directory))
            XCTAssertEqual(saved.verseDirectory, directory); XCTAssertNil(saved.recording)
            let audio = MushafVerseAudio(); audio.selectReciter(saved)
            XCTAssertEqual(audio.reciterDirectory, directory)
            XCTAssertEqual(audio.currentRecordingIdentity, "everyayah:" + directory)
            XCTAssertNil(audio.playing, "Restoring a preference never starts playback")
            let rateKey = "noor.audio.bookmark.everyayah:\(directory).rate"
            let oldRate = UserDefaults.standard.object(forKey: rateKey)
            defer {
                if let oldRate { UserDefaults.standard.set(oldRate, forKey: rateKey) }
                else { UserDefaults.standard.removeObject(forKey: rateKey) }
            }
            XCTAssertTrue(audio.setPlaybackRate(1.1))
            XCTAssertEqual(UserDefaults.standard.float(forKey: rateKey), 1.1,
                           "Existing EveryAyah bookmarks retain the same namespace through the unified picker")
            let cache = try XCTUnwrap(NoorVerseReciter.cacheKey(directory: directory, verse: "112:1"))
            XCTAssertEqual(NoorAudioIntegrity.url(cache)?.absoluteString,
                           "https://everyayah.com/data/\(directory)/112001.mp3")
            audio.stop()
        }
        XCTAssertNil(NoorMushafReciter.selected("unknown-recording"))
    }
    func testActualDecodedRollingWindowKeepsBothSurahsDespiteCrossBoundaryBridge() throws {
        let script = try JSONDecoder().decode(QuranWordScript.self, from: Data(contentsOf:
            XCTUnwrap(Bundle.main.url(forResource: "recitation-word-script", withExtension: "json"))))
        let data = try XCTUnwrap(QCFV2ContentCache.bundledSnapshot())
        let snapshot = try JSONDecoder().decode(QCFV2Snapshot.self, from: data).validated()
        let corpus = try XCTUnwrap(QuranResources.corpus)
        let keys = corpus.flatMap { s in s.ayahs.map { "\(s.number):\($0.number)" } }
        let native = snapshot.records.filter { $0.record_type == "mushaf_word" && $0.char_type_name == "word" }.map {
            QuranNativeWord(id: $0.id, verse: keys[$0.verse_id! - 1], position: $0.position_in_verse!,
                           page: $0.page_number!, glyph: $0.text!)
        }
        var tracker = QuranRecitationTracker(expected: try script.bind(native: native, verseKeys: keys))
        // Verbatim accepted word/timing output captured from public PCM in the
        // failed22cff73 native run. This replays ALIGNMENT, not acoustic inference.
        let text = ["قُلْ", " هُوَ", " اللَّهُ", " أَحَدٌ", " قُلْ", " أَعُوذُ", " بِرَبِّ", " النَّاسِ"]
        let times = [0.1346875, 0.6146874892711639, 1.1146875190734864, 1.894687490463257,
                     2.6546874809265137, 3.894687490463257, 4.654687480926514, 5.514687614440918, 8.1346875]
        let heard = text.indices.map { QuranHeardWord(text: text[$0], start: times[$0], end: times[$0 + 1], probability: 1) }
        let take = UUID()
        let firstTimes = [0.0, 0.6200000047683716, 1.1200000047683716, 1.899999976158142, 3.0]
        let firstWindow = (0..<4).map { QuranHeardWord(text: text[$0], start: firstTimes[$0], end: firstTimes[$0 + 1], probability: 1) }
        XCTAssertEqual(try tracker.consume(firstWindow, takeID: take).count, 4)
        try tracker.reconsiderAudio(takeID: take, start: times[0], end: times[8])
        _ = try tracker.consume(heard, takeID: take)
        let evidence = tracker.evidence
        XCTAssertEqual(evidence.map(\.verse), Array(repeating: "112:1", count: 4) + Array(repeating: "114:1", count: 4))
        XCTAssertEqual(evidence.count, 8)
        XCTAssertEqual(evidence.last?.end, times.last)
        XCTAssertFalse(evidence.contains { $0.verse == "113:1" }, "A cross-boundary three-word prefix cannot displace two complete anchors")
    }

    func testEqualOptimalInterpretationsRemainUnresolved() throws {
        let words = ["قل", "اعوذ", "برب", "فاصل", "قل", "اعوذ", "برب"].enumerated().map {
            QuranAlignedWord(id: $0.offset + 1, verse: "112:1", page: 604, aliases: [[$0.element]])
        }
        var tracker = QuranRecitationTracker(expected: words)
        let heard = ["قل", "اعوذ", "برب"].enumerated().map {
            QuranHeardWord(text: $0.element, start: Double($0.offset), end: Double($0.offset) + 0.8, probability: 0.99)
        }
        XCTAssertTrue(try tracker.consume(heard, takeID: UUID()).isEmpty)
    }

    func testVisibilityAndAnalysisPreserveEvidenceInBothDiskWriteOrders() throws {
        for visibilityFirst in [true, false] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let journal = QuranRecitationJournal(root: root)
            var initial = QuranRecitationRecord(keys: ["112:1"], originPage: 604)
            initial.phase = .recording; initial.closedTextRequested = true; initial.practiceTextHidden = true
            initial.takes = [.init(startedAt: initial.startedAt)]
            try journal.create(initial)
            var analysis = initial, visibility = initial
            analysis.takes[0].frames = 32_000
            analysis.evidence = [.init(nativeID: 1, verse: "112:1", takeID: initial.takes[0].id,
                start: 0.1, end: 0.8, minimumConfidence: 0.99)]
            analysis.observedSpeech = [.init(takeID: initial.takes[0].id, start: 0, end: 2,
                words: ["قل"], unresolved: false, backendID: "journal-regression")]
            analysis.retainedVisibleVerses = ["112:1"]
            analysis.takes[0].textHintIDs = [1]
            visibility.practiceTextHidden = false; visibility.textExposureOccurred = true
            visibility.takes[0].textExposureOccurred = true
            if visibilityFirst {
                try journal.savePracticeTextVisibility(visibility); try journal.saveAnalysis(analysis)
            } else {
                try journal.saveAnalysis(analysis); try journal.savePracticeTextVisibility(visibility)
            }
            let saved = try journal.load(initial.id)
            XCTAssertEqual(saved.evidence, analysis.evidence)
            XCTAssertEqual(saved.observedSpeech, analysis.observedSpeech)
            XCTAssertEqual(saved.takes[0].frames, 32_000)
            XCTAssertEqual(saved.practiceTextHidden, false)
            XCTAssertEqual(saved.textExposureOccurred, true)
            XCTAssertEqual(saved.takes[0].textExposureOccurred, true)
            visibility.practiceTextHidden = true; visibility.textExposureOccurred = false
            visibility.takes[0].textExposureOccurred = false
            try journal.savePracticeTextVisibility(visibility)
            let hidden = try journal.load(initial.id)
            XCTAssertEqual(hidden.evidence, analysis.evidence)
            XCTAssertEqual(hidden.textExposureOccurred, true, "Hiding again cannot erase recorded assistance")
            var revised = analysis
            revised.evidence = []; revised.retainedVisibleVerses = nil; revised.takes[0].textHintIDs = nil
            try journal.saveAnalysis(revised)
            let retracted = try journal.load(initial.id)
            XCTAssertTrue(retracted.evidence.isEmpty)
            XCTAssertEqual(retracted.retainedVisibleVerses,["112:1"])
            XCTAssertEqual(retracted.takes[0].textHintIDs,[1])
            var invalid = retracted
            invalid.retainedVisibleVerses = ["112:1","112:1"]
            XCTAssertThrowsError(try invalid.validate())
            invalid.retainedVisibleVerses = ["1:2"]
            XCTAssertThrowsError(try invalid.validate())
        }
    }
}
