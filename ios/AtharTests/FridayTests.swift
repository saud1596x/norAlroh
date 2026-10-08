import XCTest
@testable import Athar

final class FridayTests: XCTestCase {
    @MainActor func testCloudRestoreValidatesBeforeWritingAndDoesNotCompleteTodaysWard() throws {
        let suite = "NoorCloudRestore." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)); defer { defaults.removePersistentDomain(forName: suite) }
        let source = MemorizationStore(defaults: defaults)
        XCTAssertTrue(source.finish(chapter: 1, answers: [.init(ayah: 1, assessment: "remembered", revealed: false, hints: 0)]))
        let backup = MemorizationCloudBackup(version: 1, plan: source.plan, archive: .init(version: 1, history: source.history, progress: source.progress))
        XCTAssertTrue(source.restore(backup))
        XCTAssertEqual(source.completedToday(), 1, "Restoring keeps practice actually completed locally")
        XCTAssertEqual(source.progress.verses["1:1"]?.attempts, 1)
        let before = defaults.data(forKey: "noor.memorization.archive")
        let invalid = MemorizationCloudBackup(version: 1, plan: .init(chapter: 115, from: 1, to: 7, daily: 3), archive: backup.archive)
        XCTAssertFalse(source.restore(invalid))
        XCTAssertEqual(defaults.data(forKey: "noor.memorization.archive"), before)
    }
}
