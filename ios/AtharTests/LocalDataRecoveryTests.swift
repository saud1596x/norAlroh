import XCTest
@testable import Athar

final class LocalDataRecoveryTests: XCTestCase {
    @MainActor func testUnreadableDeviceFileIsExportableAndCannotBeOverwrittenUntilErase() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let directory = folder.appendingPathComponent("Athar")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let original = Data("{invalid-but-preserved".utf8)
        let file = directory.appendingPathComponent("device-data.json")
        try original.write(to: file)
        let store = AtharStore(directory: folder)
        XCTAssertEqual(store.unreadableDeviceData, original)
        XCTAssertFalse(store.update { $0.lowMotion = true })
        XCTAssertEqual(try Data(contentsOf: file), original)
        XCTAssertTrue(store.erase())
        XCTAssertNil(store.unreadableDeviceData)
        XCTAssertTrue(store.update { $0.lowMotion = true })
        XCTAssertTrue(AtharStore(directory: folder).data.lowMotion)
    }
    @MainActor func testMalformedMemorizationHistoryIsNotReplacedByNewResults() throws {
        let suite = "NoorHistoryRecovery." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let original = Data("unreadable-history".utf8)
        defaults.set(original, forKey: "noor.memorization.history")
        let store = MemorizationStore(defaults: defaults)
        XCTAssertEqual(store.unreadableHistory, original)
        let answer = MemorizationAnswer(ayah: 1, assessment: "remembered", revealed: false, hints: 0)
        XCTAssertFalse(store.finish(chapter: 1, answers: [answer]))
        XCTAssertEqual(defaults.data(forKey: "noor.memorization.history"), original)
        store.erase()
        XCTAssertTrue(store.finish(chapter: 1, answers: [answer]))
        XCTAssertFalse(store.finish(chapter: 1, answers: [answer, answer]))
        XCTAssertFalse(store.finish(chapter: 1, answers: [.init(ayah: 1, assessment: "unsupported", revealed: false, hints: 0)]))
    }
    func testArabicPersianAndAsciiPageNumbers() {
        XCTAssertEqual(ArabicSearch.integer("٦٠٤"), 604)
        XCTAssertEqual(ArabicSearch.integer("۱۲۳"), 123)
        XCTAssertEqual(ArabicSearch.integer(" 42 "), 42)
        XCTAssertNil(ArabicSearch.integer("١-٢"))
        XCTAssertNil(ArabicSearch.integer(""))
        XCTAssertNil(ArabicSearch.integer("999999999999999999999"))
        XCTAssertEqual(ArabicSearch.normalize("الإِخۡلَاصِ"), ArabicSearch.normalize("الاخلاص"))
        XCTAssertEqual(ArabicSearch.normalize("النَّاسِ"), ArabicSearch.normalize("الناس"))
        XCTAssertEqual(ArabicSearch.normalize("المَدِينَة"), ArabicSearch.normalize("المدينة"))
    }
}
