import XCTest
@testable import Athar

final class NoorReciterWordTimingTests: XCTestCase {
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
