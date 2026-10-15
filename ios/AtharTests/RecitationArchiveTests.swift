import XCTest
import AVFoundation
@testable import Athar

final class RecitationArchiveTests: XCTestCase {
    func testFailedFinalizationPreservesActualCaptureForRetry() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let reference = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "112001", withExtension: "mp3"))
        let capture = folder.appendingPathComponent(".capture-retry.mp3")
        try FileManager.default.copyItem(at: reference, to: capture)
        let original = try Data(contentsOf: capture)
        // A directory cannot be atomically replaced with the completed audio.
        let blocked = folder.appendingPathComponent("blocked", isDirectory: true)
        try FileManager.default.createDirectory(at: blocked, withIntermediateDirectories: true)
        let sentinel = blocked.appendingPathComponent("keep.txt")
        try Data("existing archive".utf8).write(to: sentinel)
        XCTAssertThrowsError(try RecitationArchive.finalize(capture: capture, destination: blocked, saveCapture: true))
        XCTAssertEqual(try Data(contentsOf: capture), original)
        XCTAssertEqual(try Data(contentsOf: sentinel), Data("existing archive".utf8))
        let saved = folder.appendingPathComponent("saved.mp3")
        try RecitationArchive.finalize(capture: capture, destination: saved, saveCapture: true)
        XCTAssertEqual(try Data(contentsOf: saved), original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: capture.path))
    }
    func testDamagedCaptureDoesNotReplaceSavedVoice() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let capture = folder.appendingPathComponent("broken.m4a")
        let saved = folder.appendingPathComponent("saved.m4a")
        let original = Data("existing private voice take".utf8)
        try original.write(to: saved); try Data("truncated capture".utf8).write(to: capture)
        XCTAssertThrowsError(try RecitationArchive.save(capture: capture, destination: saved))
        XCTAssertEqual(try Data(contentsOf: saved), original)
    }

    func testDecodableCaptureIsSavedAndReopens() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let capture = folder.appendingPathComponent("test-tone.wav")
        let saved = folder.appendingPathComponent("saved.wav")
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4410))
        buffer.frameLength = 4410
        let samples = try XCTUnwrap(buffer.floatChannelData)[0]
        for i in 0..<4410 { samples[i] = Float(sin(Double(i) * 2 * .pi * 440 / 44100)) * 0.1 }
        // A labelled test tone tests file handling; it is never injected into user recordings.
        do { let writer = try AVAudioFile(forWriting: capture, settings: format.settings); try writer.write(from: buffer) }
        try RecitationArchive.save(capture: capture, destination: saved)
        XCTAssertEqual(try Data(contentsOf: saved), try Data(contentsOf: capture))
        XCTAssertGreaterThan(try AVAudioPlayer(contentsOf: saved).duration, 0.09)
    }
}
