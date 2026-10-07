import XCTest
@testable import Athar

final class CloudPayloadTests: XCTestCase {
    private func compress(_ data: Data) throws -> Data {
        try (data as NSData).compressed(using: .zlib) as Data
    }

    func testExistingFoundationBackupRemainsReadable() throws {
        let original = Data(String(repeating: "سجل الحفظ والعلامات ١٢٣٤٥٦٧٨٩٠\n", count: 1200).utf8)
        XCTAssertEqual(try NoorCloudPayload.decode(compress(original)), original)
    }

    func testLimitIsEnforcedWhileInflatingHighlyCompressedPayload() throws {
        let original = Data(repeating: 65, count: 500_000)
        let packed = try compress(original)
        XCTAssertLessThan(packed.count, 32_768)
        XCTAssertThrowsError(try NoorCloudPayload.decode(packed, limit: 32_768))
    }

    func testExactLimitSucceedsAndOneMoreByteFails() throws {
        let original = Data(repeating: 66, count: 32_768)
        XCTAssertEqual(try NoorCloudPayload.decode(compress(original), limit: original.count), original)
        XCTAssertThrowsError(try NoorCloudPayload.decode(compress(original), limit: original.count - 1))
    }

    func testTruncatedOrAppendedStreamsCannotBecomeSuccessfulRestores() throws {
        let packed = try compress(Data(String(repeating: "test archive", count: 300).utf8))
        XCTAssertThrowsError(try NoorCloudPayload.decode(Data(packed.prefix(packed.count / 2))))
        XCTAssertThrowsError(try NoorCloudPayload.decode(packed + Data([0, 1, 2])))
        XCTAssertThrowsError(try NoorCloudPayload.decode(packed + Data([0])))
        XCTAssertThrowsError(try NoorCloudPayload.decode(packed + packed))
        XCTAssertThrowsError(try NoorCloudPayload.decode(Data(packed.dropLast())))
    }

    func testInvalidCompressedInputsAndInvalidLimitsAreRejected() {
        XCTAssertThrowsError(try NoorCloudPayload.decode(Data()))
        XCTAssertThrowsError(try NoorCloudPayload.decode(Data(repeating: 0, count: 750_001)))
        XCTAssertThrowsError(try NoorCloudPayload.decode(Data([255, 255, 255])))
        XCTAssertThrowsError(try NoorCloudPayload.decode(Data([0]), limit: 0))
        XCTAssertThrowsError(try NoorCloudPayload.decode(Data([0]), limit: 10_000_001))
    }
}
