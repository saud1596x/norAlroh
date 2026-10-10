import XCTest
import AVFoundation
@testable import Athar

final class AudioDownloadTests: XCTestCase {
    actor CommitGate {
        private var released = false
        private var continuation: CheckedContinuation<Void, Never>?
        func wait() async {
            if released { return }
            await withCheckedContinuation { continuation = $0 }
        }
        func release() { released = true; continuation?.resume(); continuation = nil }
    }
    private func writeTone(to url: URL, frequency: Double) throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let pcm = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8_000)); pcm.frameLength = 8_000
        let channel = try XCTUnwrap(pcm.floatChannelData?[0])
        for i in 0..<8_000 { channel[i] = Float(sin(Double(i) * 2 * .pi * frequency / 16_000)) * 0.1 }
        // Generated media tests file handling, never Quran recognition accuracy.
        let audio = try AVAudioFile(forWriting: url, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16_000, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 32_000])
        try audio.write(from: pcm)
    }
    func testIndexWriteFailureRollsBackNewAudioAndPreservesPreviousVerifiedAudio() async throws {
        for replaceExisting in [false, true] {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: folder); try? FileManager.default.removeItem(at: temporary) }
            let destination = folder.appendingPathComponent("1-1.mp3")
            let index = folder.appendingPathComponent("index.json")
            var previousFiles: [NoorAudioFile] = []
            var previousBytes: Data?
            var previousIndex: Data?
            if replaceExisting {
                let priorTone = folder.appendingPathComponent("previous-fixture.m4a")
                try writeTone(to: priorTone, frequency: 440)
                try FileManager.default.moveItem(at: priorTone, to: destination)
                let bytes = try Data(contentsOf: destination)
                previousBytes = bytes
                previousFiles = [NoorAudioFile(key: "1:1", bytes: bytes.count, sha256: NoorAudioIntegrity.digest(bytes))]
                let encoded = try JSONEncoder().encode(previousFiles); try encoded.write(to: index); previousIndex = encoded
            }
            try writeTone(to: temporary, frequency: 880)
            let bytes = try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            let url = try XCTUnwrap(URL(string: "https://everyayah.com/data/fixture.m4a"))
            let response = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Length": String(bytes)]))
            let attempted = expectation(description: "Index commit fails after verified audio write")
            let worker = NoorAudioDiskStore(directory: folder, writeIndex: { _, _ in
                attempted.fulfill(); throw CocoaError(.fileWriteOutOfSpace)
            })
            do {
                _ = try await worker.install(temporary, response: response, key: "1:1", files: previousFiles, epoch: 1)
                XCTFail("Index failure must propagate and no successful installation can be returned")
            } catch { XCTAssertEqual((error as NSError).code, CocoaError.fileWriteOutOfSpace.rawValue) }
            await fulfillment(of: [attempted], timeout: 5)
            if replaceExisting {
                XCTAssertEqual(try Data(contentsOf: destination), previousBytes, "The prior verified audio must survive replacement failure")
                XCTAssertEqual(try Data(contentsOf: index), previousIndex, "The prior index must remain intact")
                let playable = await worker.localURL(try XCTUnwrap(previousFiles.first), epoch: 1)
                XCTAssertEqual(playable, destination, "Rollback must preserve the checksum-valid existing file")
            } else {
                XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path), "An unindexed new audio file must not remain orphaned")
                XCTAssertFalse(FileManager.default.fileExists(atPath: index.path))
            }
            let remaining = try FileManager.default.contentsOfDirectory(atPath: folder.path)
            XCTAssertFalse(remaining.contains(where: { $0.hasPrefix(".audio-replacement-") }), "Successful rollback must clean its private backup")
            XCTAssertFalse(FileManager.default.fileExists(atPath: temporary.path))
        }
    }
    func testErasingDuringVerifiedMediaInstallCannotRecreateAudioOrIndex() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
        defer { try? FileManager.default.removeItem(at: folder); try? FileManager.default.removeItem(at: temporary) }
        try writeTone(to: temporary, frequency: 440)
        let bytes = try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        let url = try XCTUnwrap(URL(string: "https://everyayah.com/data/fixture.m4a"))
        let response = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Length": String(bytes)]))
        let gate = CommitGate(); let validated = expectation(description: "Actual asset is validated before installation")
        let worker = NoorAudioDiskStore(directory: folder, beforeCommit: { validated.fulfill(); await gate.wait() })
        let installation = Task { try await worker.install(temporary, response: response, key: "1:1", files: [], epoch: 1) }
        await fulfillment(of: [validated], timeout: 10)
        try await worker.erase(epoch: 2)
        await gate.release()
        let result = try await installation.value
        XCTAssertNil(result, "The old result cannot be published after erase")
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("1-1.mp3").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("index.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: temporary.path), "Abandoned download bytes must be removed")
    }
    @MainActor func testBackgroundPlaybackLookupRechecksSameSizedChangedBytesAndRejectsOldEpoch() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let original = Data("Labelled integrity fixture, not Quran audio".utf8)
        let metadata = NoorAudioFile(key: "1:1", bytes: original.count, sha256: NoorAudioIntegrity.digest(original))
        let file = folder.appendingPathComponent("1-1.mp3"); try original.write(to: file)
        let worker = NoorAudioDiskStore(directory: folder)
        let valid = await worker.localURL(metadata, epoch: 1)
        XCTAssertEqual(valid, file)
        try Data(repeating: 0, count: original.count).write(to: file)
        let changed = await worker.localURL(metadata, epoch: 1)
        XCTAssertNil(changed, "Equal length must never replace checksum verification")
        try original.write(to: file)
        await worker.invalidate(2)
        let stale = await worker.localURL(metadata, epoch: 1)
        XCTAssertNil(stale, "A queued pre-stop lookup must not return a playable URL")
    }
    @MainActor func testStoppingWhileDiskSourceResolvesCannotStartLatePlayback() async throws {
        let gate = CommitGate(); let entered = expectation(description: "Source lookup starts")
        let audio = MushafVerseAudio(resolveSource: { _ in
            entered.fulfill(); await gate.wait()
            return URL(fileURLWithPath: "/labelled-test-source.m4a")
        })
        var started = 0; audio.onVerse = { _ in started += 1 }
        audio.play(["1:1"])
        await fulfillment(of: [entered], timeout: 5)
        XCTAssertEqual(audio.loadingKey, "1:1")
        audio.stop()
        await gate.release()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertNil(audio.loadingKey); XCTAssertNil(audio.playing)
        XCTAssertEqual(started, 0, "A late disk URL must never revive a stopped range")
        XCTAssertEqual(audio.playbackDiagnostic, "", "No AVPlayer should be constructed after stop")
    }
    func testResponseLengthRejectsPlayablePrefixesAndAcceptsAssembledResume() throws {
        let url = try XCTUnwrap(URL(string: "https://everyayah.com/data/example.mp3"))
        func response(_ status: Int, _ headers: [String: String]) -> HTTPURLResponse? {
            HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)
        }
        XCTAssertTrue(NoorAudioIntegrity.completeResponse(response(200, ["Content-Length": "1000"]), bytes: 1000))
        XCTAssertFalse(NoorAudioIntegrity.completeResponse(response(200, ["Content-Length": "1000"]), bytes: 800))
        XCTAssertTrue(NoorAudioIntegrity.completeResponse(response(206,
            ["Content-Range": "bytes 800-999/1000", "Content-Length": "200"]), bytes: 1000))
        XCTAssertFalse(NoorAudioIntegrity.completeResponse(response(206,
            ["Content-Range": "bytes 800-999/1000", "Content-Length": "200"]), bytes: 200))
        for range in ["bytes 0-799/1000", "bytes 0-999/*", "bytes -1-999/1000", "invalid", "bytes 0-1000/1000"] {
            XCTAssertFalse(NoorAudioIntegrity.completeResponse(response(206, ["Content-Range": range]), bytes: 1000), range)
        }
        XCTAssertFalse(NoorAudioIntegrity.completeResponse(response(404, [:]), bytes: 1000))
        XCTAssertFalse(NoorAudioIntegrity.completeResponse(response(200, ["Content-Encoding": "gzip"]), bytes: 1000))
    }
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
    @MainActor func testOfflineIndexSurvivesRestartAndDeletionDoesNotTouchMemorization() async throws {
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
        let installed = await cache.localURL("1:1")
        XCTAssertEqual(installed, file)
        XCTAssertEqual(NoorAudioDownloads(directory: folder, defaults: defaults).totalBytes, original.count)
        try Data("corrupted".utf8).write(to: file)
        let corrupted = await cache.localURL("1:1")
        XCTAssertNil(corrupted, "Corrupt files must never be supplied to the player")
        await cache.remove("1:1")
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertTrue(NoorAudioDownloads(directory: folder, defaults: defaults).files.isEmpty)
        XCTAssertEqual(defaults.data(forKey: "noor.memorization.archive"), archive)
    }
    @MainActor func testPendingRetrySurvivesRestartAndExplicitEraseRemovesOnlyAudioState() async throws {
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
        await cache.remove("1:1")
        XCTAssertEqual(cache.pending, ["114:6"], "Deleting one item must preserve other pending downloads")
        XCTAssertTrue(try NoorAudioIntegrity.availableCapacity(at: folder) > 0)
        let erased = await cache.erase()
        XCTAssertTrue(erased)
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
        let checkedFirst = await cache.localURL("1:1")
        let first = try XCTUnwrap(checkedFirst, cache.message ?? "No verified first verse")
        XCTAssertGreaterThan(try first.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0, 0)
        let reopened = NoorAudioDownloads(directory: folder, defaults: defaults)
        let reopenedFirst = await reopened.localURL("1:1")
        XCTAssertNotNil(reopenedFirst)
        let reopenedSecond = await reopened.localURL("1:2")
        XCTAssertNotNil(reopenedSecond)
        await reopened.remove("1:1")
        let removedFirst = await reopened.localURL("1:1")
        XCTAssertNil(removedFirst)
        let preservedSecond = await reopened.localURL("1:2")
        XCTAssertNotNil(preservedSecond, "Deleting one verse must preserve the other")
        let erased = await reopened.erase()
        XCTAssertTrue(erased)
    }

}
