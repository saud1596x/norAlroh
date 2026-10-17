import XCTest
@testable import Athar

final class NoorReciterWordTimingTests: XCTestCase {
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
