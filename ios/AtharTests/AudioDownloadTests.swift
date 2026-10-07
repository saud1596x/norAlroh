import XCTest
@testable import Athar

final class AudioDownloadTests: XCTestCase {
    func testInstalledDigestRejectsTruncationReplacementAndInvalidVerseKeys() {
        let original = Data("labelled file integrity fixture; not Quran audio".utf8)
        let metadata = NoorAudioFile(key: "1:1", bytes: original.count, sha256: NoorAudioIntegrity.digest(original))
        XCTAssertTrue(NoorAudioIntegrity.valid(original, metadata: metadata))
        XCTAssertFalse(NoorAudioIntegrity.valid(Data(original.dropLast()), metadata: metadata))
        XCTAssertFalse(NoorAudioIntegrity.valid(Data(repeating: 0, count: original.count), metadata: metadata))
        for key in ["0:1", "115:1", "1:8", "1:01", "../1:1", "1:1:2", "1:1?url=evil"] {
            XCTAssertNil(NoorAudioIntegrity.url(key), key)
        }
        XCTAssertEqual(NoorAudioIntegrity.url("114:6")?.lastPathComponent, "114006.mp3")
    }
    @MainActor func testOfflineIndexSurvivesRestartAndDeletionDoesNotTouchMemorization() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let suite = "Noor.AudioCache." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)); defer { defaults.removePersistentDomain(forName: suite) }
        let original = Data("labelled checksum fixture; not a playable recording".utf8)
        let metadata = NoorAudioFile(key: "1:1", bytes: original.count, sha256: NoorAudioIntegrity.digest(original))
        let file = folder.appendingPathComponent("1-1.mp3")
        try original.write(to: file)
        try JSONEncoder().encode([metadata]).write(to: folder.appendingPathComponent("index.json"))
        let archive = Data("preserved memorization bytes".utf8)
        defaults.set(archive, forKey: "noor.memorization.archive")
        let cache = NoorAudioDownloads(directory: folder, defaults: defaults)
        XCTAssertEqual(cache.localURL("1:1"), file)
        XCTAssertEqual(NoorAudioDownloads(directory: folder, defaults: defaults).totalBytes, original.count)
        try Data("corrupted".utf8).write(to: file)
        XCTAssertNil(cache.localURL("1:1"), "Corrupt files must never be supplied to the player")
        cache.remove("1:1")
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertTrue(NoorAudioDownloads(directory: folder, defaults: defaults).files.isEmpty)
        XCTAssertEqual(defaults.data(forKey: "noor.memorization.archive"), archive)
    }
    @MainActor func testPendingRetrySurvivesRestartAndExplicitEraseRemovesOnlyAudioState() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "Noor.PendingAudio." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: folder) }
        defaults.set(["1:1", "114:6", "../escape"], forKey: "noor.audioDownloads.pending.v1")
        defaults.set(Data("local session must survive".utf8), forKey: "noor.memorization.session")
        let cache = NoorAudioDownloads(directory: folder, defaults: defaults)
        XCTAssertEqual(cache.pending, ["1:1", "114:6"])
        XCTAssertEqual(cache.remaining, 2)
        XCTAssertEqual(NoorAudioDownloads(directory: folder, defaults: defaults).pending, cache.pending)
        cache.remove("1:1")
        XCTAssertEqual(cache.pending, ["114:6"], "Deleting one item must preserve other pending downloads")
        XCTAssertTrue(try NoorAudioIntegrity.availableCapacity(at: folder) > 0)
        XCTAssertTrue(cache.erase())
        XCTAssertTrue(cache.pending.isEmpty)
        XCTAssertEqual(cache.remaining, 0)
        XCTAssertNotNil(defaults.data(forKey: "noor.memorization.session"))
    }

    // Integration test against the actual configured audio host, not synthetic audio.
    // A host/network failure is reported as a failure, never as an offline pass.
    @MainActor func testLiveServerCancellationRetryPlayableFilesAndOfflineRestart() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "Noor.LiveAudio." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: folder) }
        let cache = NoorAudioDownloads(directory: folder, defaults: defaults)
        cache.download(["1:1", "1:2"])
        XCTAssertNotNil(cache.active)
        cache.cancel()
        for _ in 0..<100 {
            if cache.active == nil { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertNil(cache.active, "Cancellation must settle before retry")
        XCTAssertEqual(cache.pending, ["1:1", "1:2"])
        cache.retry()
        for _ in 0..<900 {
            if cache.active == nil { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        if cache.active != nil { cache.cancel(); XCTFail("Audio download did not finish within 90 seconds"); return }
        XCTAssertEqual(cache.files.count, 2, cache.message ?? "Missing verified audio files")
        XCTAssertTrue(cache.pending.isEmpty)
        let first = try XCTUnwrap(cache.localURL("1:1"), cache.message ?? "No verified first verse")
        XCTAssertGreaterThan(try first.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0, 0)
        let reopened = NoorAudioDownloads(directory: folder, defaults: defaults)
        XCTAssertNotNil(reopened.localURL("1:1"))
        XCTAssertNotNil(reopened.localURL("1:2"))
        reopened.remove("1:1")
        XCTAssertNil(reopened.localURL("1:1"))
        XCTAssertNotNil(reopened.localURL("1:2"), "Deleting one verse must preserve the other")
        XCTAssertTrue(reopened.erase())
    }

}
