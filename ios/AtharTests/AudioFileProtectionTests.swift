import XCTest
import AVFoundation
@testable import Athar

/// Actual iOS filesystem attributes and identified audio, not a simulated lock
/// or microphone test. Device lock/interruption behavior needs a device run.
final class AudioFileProtectionTests: XCTestCase {
    private func protection(_ url: URL) throws -> FileProtectionType {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try XCTUnwrap(attributes[.protectionKey] as? FileProtectionType)
    }
    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
    func testActualPCMAndJournalAttributesPreserveReferenceAudio() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let journal = QuranRecitationJournal(root: root)
        let record = QuranRecitationRecord(keys: ["112:1"], originPage: 604)
        try journal.create(record)
        let folder = journal.folder(record.id)
        XCTAssertEqual(try protection(folder), .completeUntilFirstUserAuthentication)
        XCTAssertEqual(try protection(folder.appendingPathComponent("recognized-session.json")),
                       .completeUntilFirstUserAuthentication)
        XCTAssertEqual(try folder.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
        let reference = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "112001", withExtension: "mp3"))
        let input = try AVAudioFile(forReading: reference)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: input.processingFormat,
            frameCapacity: 4096))
        let converter = try QuranPCMResampler(input: input.processingFormat)
        var samples: [Float] = []
        var inputFrames: AVAudioFramePosition = 0
        // Exercise the converter at the real tap's 4096-frame size, preserving
        // filter history instead of offering a whole MP3 to a bounded drain.
        while input.framePosition < input.length {
            try input.read(into: buffer, frameCount: 4096)
            XCTAssertGreaterThan(buffer.frameLength, 0)
            guard buffer.frameLength > 0 else { break }
            inputFrames += AVAudioFramePosition(buffer.frameLength)
            samples += try converter.convert(buffer)
        }
        samples += try converter.finish()
        XCTAssertEqual(inputFrames, input.length)
        XCTAssertGreaterThan(samples.count, 0)
        let output = journal.audio(session: record.id, take: UUID())
        let writer = try QuranPCMWriter(url: output, onWindow: { _ in },
            onFailure: { _ in XCTFail("Reference PCM write failed") })
        XCTAssertEqual(try protection(output), .completeUntilFirstUserAuthentication)
        for start in stride(from: 0, to: samples.count, by: 16_000) {
            writer.append(Array(samples[start..<min(samples.count, start + 16_000)]))
        }
        let result: Result<Int64, Error> = await withCheckedContinuation { continuation in
            writer.finish { continuation.resume(returning: $0) }
        }
        XCTAssertEqual(try result.get(), Int64(samples.count))
        XCTAssertEqual(try AVAudioFile(forReading: output).length, Int64(samples.count))
        XCTAssertEqual(try protection(output), .completeUntilFirstUserAuthentication)
        XCTAssertEqual(try journal.load(record.id).id, record.id)
    }
    func testActualLegacyCaptureProtectionDoesNotWeakenCompletedArchive() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let reference = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "112001", withExtension: "mp3"))
        let capture = root.appendingPathComponent("capture.mp3")
        let saved = root.appendingPathComponent("completed.mp3")
        try FileManager.default.copyItem(at: reference, to: capture)
        let original = try Data(contentsOf: capture)
        try RecitationArchive.protectOpenCapture(capture)
        XCTAssertEqual(try protection(capture), .completeUntilFirstUserAuthentication)
        XCTAssertEqual(try Data(contentsOf: capture), original)
        try RecitationArchive.save(capture: capture, destination: saved)
        XCTAssertEqual(try protection(saved), .complete)
        XCTAssertEqual(try Data(contentsOf: saved), original)
        XCTAssertTrue(try AVAudioPlayer(contentsOf: saved).prepareToPlay())
    }
}
