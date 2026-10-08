import XCTest
import AVFoundation
import Combine
@testable import Athar

final class MushafRecordingTests: XCTestCase {
    private func folder() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("NoorRecordingTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
    private func session() -> MushafStudySession { .init(keys: ["112:1", "112:2"], scope: .range, page: 604) }
    @MainActor func testActualCaptureCategoryAndModeAreCompatibleWithoutActivatingMicrophone() throws {
        let sound = AVAudioSession.sharedInstance()
        let category = sound.category; let mode = sound.mode; let options = sound.categoryOptions
        defer { try? sound.setCategory(category, mode: mode, options: options) }
        try MushafCaptureAudio.configure(sound)
        XCTAssertEqual(sound.category, .playAndRecord)
        XCTAssertEqual(sound.mode, .measurement)
        XCTAssertTrue(sound.categoryOptions.contains(.defaultToSpeaker))
        // No setActive/record call: this verifies real OS configuration, not
        // microphone signal, permission consent or recitation accuracy.
    }
    @MainActor func testDeniedPermissionLeavesSelfSessionAndFilesUntouched() async throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        let value = session()
        let recorder = MushafSessionRecorder(base: root, permission: { false }, isActive: { true })
        await recorder.start(session: value)
        XCTAssertTrue(recorder.permissionDenied); XCTAssertNotNil(recorder.message)
        XCTAssertFalse(recorder.recording); XCTAssertFalse(recorder.requestingPermission)
        XCTAssertEqual(value.phase, .active); XCTAssertEqual(value.answers.count, 0)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }
    @MainActor func testGrantedPermissionCannotRecordAfterAppLeavesForeground() async throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        let recorder = MushafSessionRecorder(base: root, permission: { true }, isActive: { false })
        await recorder.start(session: session())
        XCTAssertFalse(recorder.recording); XCTAssertNotNil(recorder.message)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }
    @MainActor func testCancelWhilePermissionIsPendingCannotStartLateRecording() async throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        let waiting = expectation(description: "Real asynchronous permission boundary")
        var answer: CheckedContinuation<Bool, Never>?
        let recorder = MushafSessionRecorder(base: root, permission: {
            await withCheckedContinuation { answer = $0; waiting.fulfill() }
        }, isActive: { true })
        let capture = Task { await recorder.start(session: session()) }
        await fulfillment(of: [waiting], timeout: 3)
        XCTAssertTrue(recorder.requestingPermission)
        recorder.stop(); try XCTUnwrap(answer).resume(returning: true)
        await capture.value
        XCTAssertFalse(recorder.recording); XCTAssertFalse(recorder.requestingPermission)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }
    func testActualAACChunksReopenWithoutReplacingEarlierAudioAndLongFilesAreNotCapped() throws {
        // Generated silent AAC fixture, not microphone/recitation accuracy evidence.
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        let value = session(); let directory = try MushafRecordingArchive.register(value, base: root)
        let first = UUID(); let second = UUID()
        try audio(directory.appendingPathComponent(first.uuidString + ".m4a"), seconds: 1)
        let original = try Data(contentsOf: directory.appendingPathComponent(first.uuidString + ".m4a"))
        try audio(directory.appendingPathComponent(second.uuidString + ".m4a"), seconds: 301)
        let takes = try MushafRecordingArchive.takes(session: value.id, base: root)
        XCTAssertEqual(Set(takes.map(\.id)), [first, second])
        XCTAssertGreaterThan(try XCTUnwrap(takes.first { $0.id == second }).duration, 300)
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent(first.uuidString + ".m4a")), original)
        XCTAssertEqual(try MushafRecordingArchive.sessions(base: root).map(\.id), [value.id])
        XCTAssertEqual(try MushafRecordingArchive.metadata(session: value.id, base: root)?.keys, value.keys)
        let export = try XCTUnwrap(MushafRecordingArchive.exportMetadata(base: root).first)
        XCTAssertEqual(Set(export.files.map(\.id)), [first, second]); XCTAssertTrue(export.files.allSatisfy { $0.bytes > 0 })
        XCTAssertEqual(export.metadata?.id, value.id); XCTAssertNil(export.unreadableMetadata)
    }
    @MainActor func testActualLocalPlaybackCompletesAndPreservesOriginalAACFile() async throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        let value = session(); let directory = try MushafRecordingArchive.register(value, base: root)
        let url = directory.appendingPathComponent(UUID().uuidString + ".m4a")
        try audio(url, seconds: 1); let bytes = try Data(contentsOf: url)
        let take = try XCTUnwrap(MushafRecordingArchive.takes(session: value.id, base: root).first)
        let recorder = MushafSessionRecorder(base: root, permission: { false }, isActive: { true })
        recorder.play(take)
        XCTAssertEqual(recorder.playing, take.id); XCTAssertNil(recorder.message)
        let ended = expectation(description: "Actual AVAudioPlayer completion")
        let observation = recorder.$playing.dropFirst().filter { $0 == nil }.prefix(1).sink { _ in ended.fulfill() }
        await fulfillment(of: [ended], timeout: 6)
        withExtendedLifetime(observation) {}
        XCTAssertNil(recorder.playing); XCTAssertNil(recorder.message)
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }
    @MainActor func testActualPlaybackTransportSeeksPausesResumesAndReopensOriginalFile() throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        let value = session(); let directory = try MushafRecordingArchive.register(value, base: root)
        let url = directory.appendingPathComponent(UUID().uuidString + ".m4a")
        try audio(url, seconds: 12); let bytes = try Data(contentsOf: url)
        let take = try XCTUnwrap(MushafRecordingArchive.takes(session: value.id, base: root).first)
        let transport = MushafSessionRecorder(base: root)
        transport.play(take, at: 3)
        XCTAssertEqual(transport.playing, take.id); XCTAssertNil(transport.message)
        XCTAssertGreaterThan(transport.playbackDuration, 11)
        transport.pausePlayback()
        XCTAssertTrue(transport.playbackPaused)
        XCTAssertEqual(transport.playbackPosition, 3, accuracy: 0.5)
        transport.seekPlayback(to: 7)
        XCTAssertEqual(transport.playbackPosition, 7, accuracy: 0.1)
        XCTAssertTrue(transport.playbackPaused, "Seeking must not resume paused audio")
        transport.seekPlayback(to: .nan)
        XCTAssertEqual(transport.playbackPosition, 7, accuracy: 0.1)
        transport.resumePlayback(); XCTAssertFalse(transport.playbackPaused); XCTAssertNil(transport.message)
        transport.pausePlayback(); transport.seekPlayback(to: -5)
        XCTAssertEqual(transport.playbackPosition, 0, accuracy: 0.1)
        transport.stop(); XCTAssertNil(transport.playing); XCTAssertEqual(transport.playbackDuration, 0)
        // A new archive read and player reconstruct playback from persisted bytes.
        // This tests native transport, not an app UI relaunch or audible device output.
        let reopened = try XCTUnwrap(MushafRecordingArchive.takes(session: value.id, base: root).first)
        let fresh = MushafSessionRecorder(base: root)
        fresh.play(reopened, at: 5)
        XCTAssertEqual(fresh.playing, take.id); XCTAssertEqual(fresh.playbackPosition, 5, accuracy: 0.5)
        fresh.stop()
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }
    @MainActor func testFailedRealDecodeReleasesOnlyOwnedAudioSessionWithoutDeletingBytes() throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent(UUID().uuidString + ".m4a")
        let bytes = Data([0, 255, 1]); try bytes.write(to: url)
        var activations: [Bool] = []
        let recorder = MushafSessionRecorder(base: root, permission: { false }, isActive: { true },
            setSessionActive: { activations.append($0) })
        recorder.stop(); XCTAssertTrue(activations.isEmpty, "An idle recorder must not deactivate another audio owner")
        recorder.play(.init(id: UUID(), session: UUID(), url: url, date: Date(), duration: 1))
        XCTAssertEqual(activations, [true, false], "Release activation even when actual AVAudioPlayer initialization throws")
        XCTAssertNil(recorder.playing); XCTAssertFalse(recorder.recording); XCTAssertNotNil(recorder.message)
        recorder.stop(); XCTAssertEqual(activations, [true, false])
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }
    @MainActor func testFailedDeactivationCanRetryWithoutReactivatingOrReplacingAudio() throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent(UUID().uuidString + ".m4a")
        let bytes = Data([0, 255, 1]); try bytes.write(to: url)
        var activations: [Bool] = []; var rejectedOnce = false
        let recorder = MushafSessionRecorder(base: root, permission: { false }, isActive: { true }, setSessionActive: { active in
            activations.append(active)
            if !active && !rejectedOnce { rejectedOnce = true; throw CocoaError(.fileReadUnknown) }
        })
        recorder.play(.init(id: UUID(), session: UUID(), url: url, date: Date(), duration: 1))
        XCTAssertEqual(activations, [true, false])
        recorder.stop(); XCTAssertEqual(activations, [true, false, false])
        recorder.stop(); XCTAssertEqual(activations, [true, false, false])
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }
    func testUnreadableMetadataAndAudioArePreservedAndConflictingHeaderCannotReplaceSession() throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        let value = session(); let directory = try MushafRecordingArchive.register(value, base: root)
        var payload = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
        payload["keys"] = ["112:1"]
        let conflict = try JSONDecoder().decode(MushafStudySession.self, from: JSONSerialization.data(withJSONObject: payload))
        XCTAssertThrowsError(try MushafRecordingArchive.register(conflict, base: root))
        let damaged = Data([0, 255, 10, 20]); let metadata = directory.appendingPathComponent("session.json")
        try damaged.write(to: metadata)
        let audioURL = directory.appendingPathComponent(UUID().uuidString + ".m4a")
        try damaged.write(to: audioURL)
        XCTAssertThrowsError(try MushafRecordingArchive.register(value, base: root))
        XCTAssertTrue(try MushafRecordingArchive.takes(session: value.id, base: root).isEmpty)
        let exported = try XCTUnwrap(MushafRecordingArchive.exportMetadata(base: root).first)
        XCTAssertEqual(exported.unreadableMetadata, damaged)
        XCTAssertEqual(try Data(contentsOf: metadata), damaged); XCTAssertEqual(try Data(contentsOf: audioURL), damaged)
    }
    func testExplicitEraseTouchesOnlyNewRecordingRoot() throws {
        let container = try folder(); defer { try? FileManager.default.removeItem(at: container) }
        let legacy = container.appendingPathComponent("latest-recitation.m4a")
        let bytes = Data([1, 2, 3]); try bytes.write(to: legacy)
        let root = container.appendingPathComponent("NoorMushafRecordings")
        _ = try MushafRecordingArchive.register(session(), base: root)
        try MushafRecordingArchive.erase(base: root)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
        XCTAssertEqual(try Data(contentsOf: legacy), bytes)
    }
    func testDurationFormattingRejectsNonfiniteValuesAndKeepsEnglishDigits() {
        XCTAssertEqual(MushafAudioTime.text(301), "5:01")
        XCTAssertEqual(MushafAudioTime.text(.infinity), "0:00")
        XCTAssertEqual(MushafAudioTime.text(-1), "0:00")
    }
    private func audio(_ url: URL, seconds: Int) throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16000))
        buffer.frameLength = 16000
        memset(try XCTUnwrap(buffer.floatChannelData)[0], 0, Int(buffer.frameLength) * MemoryLayout<Float>.size)
        let file = try AVAudioFile(forWriting: url, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16000, AVNumberOfChannelsKey: 1])
        for _ in 0..<seconds { try file.write(from: buffer) }
        // AVAudioFile closes at return, before the archive attempts to decode.
    }
}
