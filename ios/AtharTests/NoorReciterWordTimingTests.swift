import XCTest
@testable import Athar

final class NoorReciterWordTimingTests: XCTestCase {
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
