import XCTest
@testable import Athar

final class NoorReciterWordTimingTests: XCTestCase {
    func testVisibleWordStartUsesItsOwnInclusiveBoundaryAcrossSplitAyahAndGaps() throws {
        let track = try XCTUnwrap(NoorSurahWordTimingTrack(surah: 2, ayahCount: 3, spans: [
            [1, 201, 1000, 1400], [1, 202, 1700, 2100], [2, 203, 2500, 2900]
        ]))
        // Starting the visible continuation of an ayah must not rewind to its
        // preceding word, including when that word belongs on another face.
        let seconds = try XCTUnwrap(track.startOffset(wordID: 202, verse: "2:1"))
        XCTAssertEqual(seconds, 1.7)
        XCTAssertEqual(track.position(at: seconds, duration: 4), .init(verse: "2:1", wordID: 202))
        XCTAssertNil(track.position(at: seconds - 0.001, duration: 4), "The source pause is not a word")
        XCTAssertNil(track.position(at: 2.1, duration: 4), "The source end is exclusive")
        XCTAssertEqual(track.startOffset(wordID: 203, verse: "2:2"), 2.5)
        XCTAssertNil(track.startOffset(wordID: 202, verse: "2:2"), "An ID cannot borrow another ayah's start")
        XCTAssertNil(track.startOffset(wordID: 999, verse: "2:1"))
        XCTAssertNil(track.startOffset(wordID: 202, verse: "1:1"))
    }

    func testRepeatedWordStartRetainsFirstActualSourceOccurrence() throws {
        let track = try XCTUnwrap(NoorSurahWordTimingTrack(surah: 1, ayahCount: 7, spans: [
            [1, 101, 300, 700], [1, 102, 900, 1300], [1, 101, 1500, 1900]
        ]))
        XCTAssertEqual(track.startOffset(wordID: 101, verse: "1:1"), 0.3)
        XCTAssertNil(track.startOffset(wordID: 101, verse: "01:1"), "Only the exact canonical verse can select a clock")
        XCTAssertNil(track.startOffset(wordID: 101, verse: "1:01"))
        XCTAssertNil(track.startOffset(wordID: 101, verse: "1:0"))
    }

    func testVoiceGroupingContainsOnlyCompleteRecordingsAndPreservesExactIdentities() throws {
        let groups = NoorReciterVoiceGroup.matching("")
        XCTAssertEqual(groups.count, 4)
        let expected: Set<String> = ["surah:74:74", "surah:1000001:1000001",
            "surah:1000002:1000002", "surah:1000003:1000003"]
        XCTAssertEqual(Set(groups.flatMap(\.recordings).map(\.id)), expected)
        XCTAssertEqual(groups.flatMap(\.recordings).count, 4)
        for choice in groups.flatMap(\.recordings) {
            let selected = try XCTUnwrap(NoorMushafReciter.selected(choice.id))
            XCTAssertEqual(selected.recordingIdentity, choice.recordingIdentity)
            XCTAssertTrue(selected.hasCompleteWordTracking)
            XCTAssertFalse(selected.supportsVersePlayback)
            XCTAssertEqual(selected.coverage?.timedWords, 77_429)
            XCTAssertEqual(selected.coverage?.timedVerses, 6_236)
        }
        XCTAssertTrue(NoorReciterVoiceGroup.matching("الشَّرِيم").isEmpty,
            "Missing Fatiha basmala makes the old Shuraim recording ineligible")
        XCTAssertEqual(NoorReciterVoiceGroup.matching("الحُذَيْفِي").count, 1)
        XCTAssertEqual(NoorReciterVoiceGroup.matching("  \n").count, 4)
        XCTAssertTrue(NoorReciterVoiceGroup.matching("قارئ غير موجود").isEmpty)
    }

    func testCoverageLabelsDistinguishFullNativeMapMissingBasmalaAndPartialVerseSources() throws {
        let full = try XCTUnwrap(NoorMushafReciter.selected("surah:74:74")?.coverage)
        XCTAssertEqual(full.timedWords, 77429); XCTAssertEqual(full.totalWords, 77429)
        XCTAssertEqual(full.timedVerses, 6236); XCTAssertTrue(full.isComplete)
        XCTAssertEqual(full.label, "توقيت الكلمات متاح لجميع الآيات")
        let shuraim = try XCTUnwrap(NoorReciterCoverageCatalog.recordings["surah:31:31"])
        XCTAssertEqual(shuraim.timedWords, 77425); XCTAssertFalse(shuraim.isComplete)
        XCTAssertTrue(shuraim.onlyMissingFirstBasmala)
        XCTAssertEqual(shuraim.label, "توقيت الكلمات متاح عدا بسملة الفاتحة")
        for id in ["Abdul_Basit_Murattal_64kbps", "Abdurrahmaan_As-Sudais_192kbps", "Saood_ash-Shuraym_128kbps"] {
            let partial = try XCTUnwrap(NoorReciterCoverageCatalog.recordings[id])
            XCTAssertFalse(partial.isComplete); XCTAssertFalse(partial.onlyMissingFirstBasmala)
            XCTAssertLessThan(partial.timedWords, partial.totalWords)
            XCTAssertEqual(partial.label, "توقيت الكلمات متاح بتغطية جزئية")
        }
        let actual = try XCTUnwrap(NoorReciterCatalog.reciters.first { $0.id == 74 })
        let changed = NoorReciter(id: actual.id, name: actual.name, recordingID: actual.recordingID,
            server: "https://cdn.mp3quran.net/audio/ali-hudhaifi/r2/", surahs: actual.surahs)
        XCTAssertNil(NoorMushafReciter(id: "surah:74:74", name: changed.name, verseDirectory: nil, recording: changed).coverage)
    }

    func testWholeSurahBundleCoversNativeWordsWithoutBorrowingTheMissingBasmala() async throws {
        let snapshot = try JSONDecoder().decode(QCFV2Snapshot.self,
            from: XCTUnwrap(QCFV2ContentCache.bundledSnapshot())).validated()
        let corpus = try XCTUnwrap(QuranResources.corpus)
        let keys = corpus.flatMap { surah in surah.ayahs.map { "\(surah.number):\($0.number)" } }
        let words = snapshot.records.filter { $0.record_type == "mushaf_word" && $0.char_type_name == "word" }
        let expected = Dictionary(uniqueKeysWithValues: try words.map { word in
            guard let verse = word.verse_id, (1...keys.count).contains(verse) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            return (word.id, keys[verse - 1])
        })
        let basmala = Set(words.filter { $0.verse_id == 1 }.map(\.id))
        for id in [74, 31] {
            let reciter = try XCTUnwrap(NoorReciterCatalog.reciters.first { $0.id == id })
            var seen = Set<Int>()
            for surah in corpus {
                let loaded = await NoorSurahWordTimings.shared.track(reciter: reciter,
                    surah: surah.number, ayahCount: surah.ayahs.count)
                let track = try XCTUnwrap(loaded, "Missing actual bundled chapter \(id):\(surah.number)")
                let last = try XCTUnwrap(track.spans.last)
                let duration = Double(last[3]) / 1000 + 1
                for span in track.spans {
                    let midpoint = Double(span[2] + span[3]) / 2000
                    let position = track.position(at: midpoint, duration: duration)
                    XCTAssertEqual(position?.wordID, span[1])
                    XCTAssertEqual(position?.verse, expected[span[1]], "A native ID must keep its authored ayah")
                    seen.insert(span[1])
                }
            }
            XCTAssertTrue(seen.isSubset(of: Set(expected.keys)))
            XCTAssertEqual(Set(expected.keys).subtracting(seen), id == 74 ? [] : basmala,
                "Only Shuraim's genuinely absent first basmala remains untimed; no inferred clocks")
        }
    }
    func testWholeRecordingWordClockTracksActualRepeatsAndGapsWithoutInterpolating() throws {
        let track = try XCTUnwrap(NoorSurahWordTimingTrack(surah: 112, ayahCount: 4,
            spans: [[1, 10, 100, 300], [1, 11, 450, 800], [1, 10, 1000, 1200], [2, 12, 1500, 1800]]))
        XCTAssertEqual(track.position(at: 0.1, duration: 2), NoorSurahWordTimingTrack.Position(verse: "112:1", wordID: 10))
        XCTAssertNil(track.position(at: 0.3, duration: 2))
        XCTAssertEqual(track.position(at: 0.45, duration: 2), NoorSurahWordTimingTrack.Position(verse: "112:1", wordID: 11))
        XCTAssertEqual(track.position(at: 1, duration: 2), NoorSurahWordTimingTrack.Position(verse: "112:1", wordID: 10),
                       "An explicitly timed repeat follows the reciter back to the prior word")
        XCTAssertEqual(track.position(at: 1.5, duration: 2), NoorSurahWordTimingTrack.Position(verse: "112:2", wordID: 12))
        XCTAssertNil(track.position(at: 0.1, duration: 1), "A truncated/different recording cannot use this clock")
        XCTAssertNil(track.position(at: .nan, duration: 2))
        XCTAssertNil(NoorSurahWordTimingTrack(surah: 112, ayahCount: 4, spans: [[5, 10, 0, 100]]))
        XCTAssertNil(NoorSurahWordTimingTrack(surah: 112, ayahCount: 4, spans: [[1, 10, 0, 200], [1, 11, 100, 300]]))
        XCTAssertNil(NoorSurahWordTimingTrack(surah: 112, ayahCount: 4, spans: [[1, 10, 0, 100], [2, 10, 100, 200]]),
                     "The same native ID cannot be reassigned to another ayah")
    }
    func testPublishedWholeSurahWordsUseTheExactRecordingAndNoGuessedBasmala() async throws {
        let hudhaify = try XCTUnwrap(NoorReciterCatalog.reciters.first { $0.id == 74 })
        let shuraim = try XCTUnwrap(NoorReciterCatalog.reciters.first { $0.id == 31 })
        let snapshot = try JSONDecoder().decode(QCFV2Snapshot.self,
            from: XCTUnwrap(QCFV2ContentCache.bundledSnapshot())).validated()
        func firstWord(_ verse: Int) throws -> Int {
            try XCTUnwrap(snapshot.records.first { $0.record_type == "mushaf_word" && $0.char_type_name == "word"
                && $0.verse_id == verse && $0.position_in_verse == 1 }).id
        }
        let h = await NoorSurahWordTimings.shared.track(reciter: hudhaify, surah: 1, ayahCount: 7)
        let s = await NoorSurahWordTimings.shared.track(reciter: shuraim, surah: 1, ayahCount: 7)
        XCTAssertEqual(try XCTUnwrap(h).position(at: 8.3, duration: 65),
                       NoorSurahWordTimingTrack.Position(verse: "1:1", wordID: try firstWord(1)))
        XCTAssertEqual(try XCTUnwrap(s).position(at: 5.5, duration: 40),
                       NoorSurahWordTimingTrack.Position(verse: "1:2", wordID: try firstWord(2)))
        XCTAssertNil(try XCTUnwrap(s).position(at: 2.5, duration: 40), "The publisher has no word timing for this basmala")
        let changed = NoorReciter(id: hudhaify.id, name: hudhaify.name, recordingID: hudhaify.recordingID + 1,
            server: hudhaify.server, surahs: hudhaify.surahs)
        let wrong = await NoorSurahWordTimings.shared.track(reciter: changed, surah: 1, ayahCount: 7)
        XCTAssertNil(wrong)
        XCTAssertFalse(NoorSurahWordTimings.supports(changed))
        let changedURL = NoorReciter(id: hudhaify.id, name: hudhaify.name, recordingID: hudhaify.recordingID,
            server: "https://cdn.mp3quran.net/audio/ali-hudhaifi/r2/", surahs: hudhaify.surahs)
        XCTAssertFalse(NoorSurahWordTimings.supports(changedURL), "A same-named voice cannot reuse another source's timing")
        XCTAssertTrue(NoorSurahWordTimings.supports(hudhaify))
        XCTAssertTrue(NoorSurahWordTimings.supports(shuraim))
        let other = try XCTUnwrap(NoorReciterCatalog.reciters.first { $0.id == 54 })
        let untimed = await NoorSurahWordTimings.shared.track(reciter: other, surah: 1, ayahCount: 7)
        XCTAssertNil(untimed, "Timings cannot transfer to another imam with the same ayah count")
        XCTAssertFalse(NoorSurahWordTimings.supports(other))
    }
    func testSurahTimingKeepsPublishedAyahBoundariesAndRejectsNumberingShifts() throws {
        let track = try XCTUnwrap(NoorSurahAyahTimingTrack(surah: 112, ayahCount: 4,
            spans: [[1, 100, 500], [2, 600, 1000], [3, 1000, 1400], [4, 1500, 1900]]))
        XCTAssertNil(track.verse(at: 0.05, duration: 2))
        XCTAssertEqual(track.verse(at: 0.1, duration: 2), "112:1")
        XCTAssertNil(track.verse(at: 0.5, duration: 2))
        XCTAssertEqual(track.verse(at: 1, duration: 2), "112:3")
        XCTAssertNil(track.verse(at: 1, duration: 1.5), "Another/truncated recording cannot use the timeline")
        XCTAssertNil(NoorSurahAyahTimingTrack(surah: 1, ayahCount: 2, spans: [[0, 0, 100], [1, 100, 200]]),
                     "Never shift a zero-indexed publisher document into canonical ayah numbers")
        XCTAssertNil(NoorSurahAyahTimingTrack(surah: 1, ayahCount: 2, spans: [[1, 0, 200], [2, 100, 300]]))
    }
    func testPublishedSurahTimingBindsExactRecordingAndExcludedTracksStayUnavailable() async throws {
        let reciter = try XCTUnwrap(NoorReciterCatalog.reciters.first { $0.id == 54 })
        let track = await NoorSurahAyahTimings.shared.track(reciter: reciter, surah: 2, ayahCount: 286)
        XCTAssertEqual(try XCTUnwrap(track).verse(at: 5, duration: 5625), "2:1")
        XCTAssertEqual(try XCTUnwrap(track).verse(at: 10, duration: 5625), "2:2")
        let changed = NoorReciter(id: reciter.id, name: reciter.name, recordingID: reciter.recordingID + 1,
            server: reciter.server, surahs: reciter.surahs)
        let wrongRecording = await NoorSurahAyahTimings.shared.track(reciter: changed, surah: 2, ayahCount: 286)
        XCTAssertNil(wrongRecording)
        let hudhaify = try XCTUnwrap(NoorReciterCatalog.reciters.first { $0.id == 74 })
        let excluded = await NoorSurahAyahTimings.shared.track(reciter: hudhaify, surah: 2, ayahCount: 286)
        XCTAssertNil(excluded, "Incomplete/misnumbered publisher timelines are not repaired by guessing")
        XCTAssertTrue(NoorSurahAyahTimings.supports(reciter))
        XCTAssertFalse(NoorSurahAyahTimings.supports(changed))
    }
    func testTimingUsesActualIntervalsAndClearsDuringGapsOrInvalidDuration() throws {
        // Boundary policy fixture, not acoustic evidence or generated timings
        // shipped to users. Real bundled data is tested separately below.
        let track = try XCTUnwrap(NoorReciterTimingTrack([[10, 100, 300], [11, 450, 800]]))
        XCTAssertNil(track.word(at: 0.099, duration: 1))
        XCTAssertEqual(track.word(at: 0.1, duration: 1), 10)
        XCTAssertNil(track.word(at: 0.3, duration: 1))
        XCTAssertEqual(track.word(at: 0.45, duration: 1), 11)
        XCTAssertNil(track.word(at: 0.8, duration: 1))
        XCTAssertNil(track.word(at: .nan, duration: 1))
        XCTAssertNil(track.word(at: 0.2, duration: 0.5), "A shorter/different recording must not use these times")
        XCTAssertNil(NoorReciterTimingTrack([[10, 300, 100]]))
        XCTAssertNil(NoorReciterTimingTrack([[10, 100, 400], [11, 300, 500]]))
    }
    func testPublishedDefaultTimingUsesNativeEditionIDsAndNeverAnotherBitrate() async throws {
        let snapshot = try JSONDecoder().decode(QCFV2Snapshot.self,
            from: XCTUnwrap(QCFV2ContentCache.bundledSnapshot())).validated()
        let expected = try XCTUnwrap(snapshot.records.first {
            $0.record_type == "mushaf_word" && $0.char_type_name == "word" && $0.verse_id == 1 && $0.position_in_verse == 1
        })
        let track = await NoorReciterWordTimings.shared.track(directory: "Abdul_Basit_Murattal_64kbps", verse: "1:1")
        XCTAssertEqual(try XCTUnwrap(track).word(at: 0.7, duration: 5), expected.id)
        let wrongBitrate = await NoorReciterWordTimings.shared.track(directory: "Abdurrahmaan_As-Sudais_64kbps", verse: "1:1")
        XCTAssertNil(wrongBitrate)
        let unsupported = await NoorReciterWordTimings.shared.track(directory: "Hudhaify_64kbps", verse: "1:1")
        XCTAssertNil(unsupported, "No fabricated positions for an untimed recording")
    }
}
