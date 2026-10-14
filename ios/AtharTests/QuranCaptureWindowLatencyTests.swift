import XCTest
import AVFoundation
import WhisperKit
@testable import Athar

final class QuranCaptureWindowLatencyTests: XCTestCase {
    func testProductionLowLatencyStartsAtTwoSecondsWithoutChangingRecordedPCM() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".caf")
        defer { try? FileManager.default.removeItem(at: url) }
        let done = expectation(description: "Low-latency recording drains and closes")
        var windows: [QuranAudioWindow] = []
        let writer = try QuranPCMWriter(url: url, lowLatency: true, onWindow: { windows.append($0) },
            onFailure: { XCTFail("Unexpected writer failure: \($0)") })
        let samples = (0..<80_000).map { Float(sin(Double($0) / 23)) * 0.1 }
        for first in stride(from: 0, to: samples.count, by: 8_000) {
            writer.append(Array(samples[first..<first + 8_000]))
        }
        writer.finish { result in XCTAssertEqual(try? result.get(), 80_000); done.fulfill() }
        await fulfillment(of: [done], timeout: 10)
        XCTAssertEqual(windows.map(\.endFrame), [32_000, 48_000, 64_000, 80_000])
        XCTAssertEqual(windows.first?.startFrame, 0)
        XCTAssertEqual(try AudioProcessor.loadAudioAsFloatArray(fromPath: url.path), samples)
    }
}
