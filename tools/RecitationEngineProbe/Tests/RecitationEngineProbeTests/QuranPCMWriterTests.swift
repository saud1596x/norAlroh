import XCTest
import AVFoundation
import WhisperKit
@testable import RecitationCapture

final class QuranPCMWriterTests: XCTestCase {
    func testActualReferenceAudioSurvivesWriterClosureWithExactSampleClock() async throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let fixture = root.appendingPathComponent("release/recitation-engine-probe/data/fixtures/112001.mp3")
        let samples = try AudioProcessor.loadAudioAsFloatArray(fromPath: fixture.path)
        XCTAssertGreaterThan(samples.count, 64_000)
        XCTAssertLessThan(samples.count, 32 * 16_000)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("take.caf")
        let done = expectation(description: "Recording file is closed after actual decoded PCM")
        var windows: [QuranAudioWindow] = []
        let writer = try QuranPCMWriter(url: url, onWindow: { windows.append($0) },
            onFailure: { XCTFail("Unexpected writer failure: \($0)") })
        // This short real fixture fits the bounded queue in 1-second batches.
        for start in stride(from: 0, to: samples.count, by: 16_000) {
            writer.append(Array(samples[start..<min(samples.count, start + 16_000)]))
        }
        writer.finish { result in
            XCTAssertEqual(try? result.get(), Int64(samples.count)); done.fulfill()
        }
        await fulfillment(of: [done], timeout: 10)
        let decoded = try AVAudioFile(forReading: url)
        XCTAssertEqual(decoded.length, Int64(samples.count))
        XCTAssertEqual(decoded.processingFormat.sampleRate, 16_000)
        XCTAssertEqual(try AudioProcessor.loadAudioAsFloatArray(fromPath: url.path), samples,
            "Closing/reopening must retain the actual recitation samples, not just a playable empty file")
        let player = try AVAudioPlayer(contentsOf: url)
        XCTAssertEqual(player.duration, Double(samples.count) / 16_000, accuracy: 0.01)
        XCTAssertTrue(player.prepareToPlay(), "Persisted bytes must remain decodable with a new player")
        XCTAssertEqual(windows.last?.endFrame, Int64(samples.count))
        XCTAssertTrue(windows.allSatisfy { $0.samples.count <= 128_000
            && $0.endFrame - $0.startFrame == Int64($0.samples.count) })
        XCTAssertThrowsError(try QuranPCMWriter(url: url, onWindow: { _ in }, onFailure: { _ in }),
            "Starting another take must never overwrite prior audio")
    }
    func testInvalidInputRetainsAlreadySavedAudioAndNeverFeedsRecognition() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".caf")
        defer { try? FileManager.default.removeItem(at: url) }
        let failed = expectation(description: "Invalid microphone buffer reports failure")
        let finished = expectation(description: "Failed writer still closes retained bytes")
        let writer = try QuranPCMWriter(url: url, onWindow: { _ in XCTFail("Invalid or too-short audio cannot produce a recognition window") },
            onFailure: { _ in failed.fulfill() })
        writer.append(Array(repeating: 0.1, count: 16_000))
        writer.append([.nan])
        writer.finish { result in
            if case .success = result { XCTFail("A recording write failure cannot report success") }
            finished.fulfill()
        }
        await fulfillment(of: [failed, finished], timeout: 5)
        XCTAssertEqual(try AVAudioFile(forReading: url).length, 16_000)
    }
}
