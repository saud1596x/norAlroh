import XCTest
import AVFoundation
@testable import Athar

/// Real reference-audio persistence on every platform; actual Data Protection
/// attributes require a device when Simulator's host filesystem omits them.
/// File attributes alone do not prove physical lock/interruption behavior.
final class AudioFileProtectionTests: XCTestCase {
    private func assertProtection(_ url: URL, _ expected: FileProtectionType,
                                  file: StaticString = #filePath, line: UInt = #line) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        // Apple's NSFileProtectionKey contract returns NSString, not a boxed
        // Swift FileProtectionType. Accept either bridge without inventing data.
        let value = (attributes[.protectionKey] as? FileProtectionType)
            ?? (attributes[.protectionKey] as? String).map { FileProtectionType(rawValue: $0) }
        if value == nil {
            // Only existence and runtime type; no path or private file content.
            let raw = attributes[.protectionKey]
            print("NOOR_PROTECTION_ATTRIBUTE_DIAGNOSTIC: present=\(raw != nil) type=\(raw.map { String(describing: type(of: $0)) } ?? "absent")")
            #if targetEnvironment(simulator)
            if raw == nil {
                // Actual run74 on both sizes established the missing key. Do
                // not substitute the requested value or skip audio assertions.
                print("NOOR_DEVICE_PROTECTION_ATTRIBUTE_NOT_PROVEN: simulator attribute absent")
                return
            }
            #endif
        }
        let actual = try XCTUnwrap(value, "File must expose its requested protection attribute", file: file, line: line)
        XCTAssertEqual(actual, expected, file: file, line: line)
    }
    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
    func testActualPCMAndJournalAttributesPreserveReferenceAudio() async throws {
        try await verifyActualPCMAndJournal()
    }
    private func verifyActualPCMAndJournal() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let journal = QuranRecitationJournal(root: root)
        let record = QuranRecitationRecord(keys: ["112:1"], originPage: 604)
        try journal.create(record)
        let folder = journal.folder(record.id)
        try assertProtection(folder, .completeUntilFirstUserAuthentication)
        try assertProtection(folder.appendingPathComponent("recognized-session.json"),
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
        try assertProtection(output, .completeUntilFirstUserAuthentication)
        for start in stride(from: 0, to: samples.count, by: 16_000) {
            writer.append(Array(samples[start..<min(samples.count, start + 16_000)]))
        }
        let result: Result<Int64, Error> = await withCheckedContinuation { continuation in
            writer.finish { continuation.resume(returning: $0) }
        }
        XCTAssertEqual(try result.get(), Int64(samples.count))
        XCTAssertEqual(try AVAudioFile(forReading: output).length, Int64(samples.count))
        try assertProtection(output, .completeUntilFirstUserAuthentication)
        XCTAssertEqual(try journal.load(record.id).id, record.id)
    }
    func testActualLegacyCaptureProtectionDoesNotWeakenCompletedArchive() throws {
        try verifyActualLegacyCapture()
    }
    private func verifyActualLegacyCapture() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let reference = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "112001", withExtension: "mp3"))
        let capture = root.appendingPathComponent("capture.mp3")
        let saved = root.appendingPathComponent("completed.mp3")
        try FileManager.default.copyItem(at: reference, to: capture)
        let original = try Data(contentsOf: capture)
        try RecitationArchive.protectOpenCapture(capture)
        try assertProtection(capture, .completeUntilFirstUserAuthentication)
        XCTAssertEqual(try Data(contentsOf: capture), original)
        try RecitationArchive.save(capture: capture, destination: saved)
        try assertProtection(saved, .complete)
        XCTAssertEqual(try Data(contentsOf: saved), original)
        XCTAssertTrue(try AVAudioPlayer(contentsOf: saved).prepareToPlay())
    }
    func testPhysicalDeviceProtectionAttributesForActualAudioAndMetadata() async throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Physical-device Data Protection attributes are not proven by Simulator; reference PCM and persistence tests still run separately.")
        #else
        // On a device assertProtection remains strict: no absent-key fallback.
        try await verifyActualPCMAndJournal()
        try verifyActualLegacyCapture()
        #endif
    }
}
