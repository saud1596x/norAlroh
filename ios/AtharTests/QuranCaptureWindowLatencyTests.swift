import XCTest
import AVFoundation
import WhisperKit
@testable import Athar

final class QuranCaptureWindowLatencyTests: XCTestCase {
    func testHourOfPCMRetainsEveryFrameWithBoundedRecognitionWindows() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".caf")
        defer { try? FileManager.default.removeItem(at: url) }
        let completedWindow = DispatchSemaphore(value: 0)
        let closed = expectation(description: "Hour-equivalent PCM is finalized")
        let chunk = (0..<32_000).map { Float(sin(Double($0) / 23)) * 0.1 }
        var count = 0, largest = 0
        var lastEnd: Int64 = 0
        let started = Date()
        let writer = try QuranPCMWriter(url: url, lowLatency: true, onWindow: { window in
            XCTAssertLessThanOrEqual(window.samples.count, 128_000)
            XCTAssertEqual(window.endFrame - window.startFrame, Int64(window.samples.count))
            XCTAssertGreaterThan(window.endFrame, lastEnd)
            lastEnd = window.endFrame; largest = max(largest, window.samples.count); count += 1
            completedWindow.signal()
        }, onFailure: { error in XCTFail("Long PCM writer failure: \(error)"); completedWindow.signal() })
        // Accelerated generated media, explicitly not physical microphone,
        // real-time ASR, thermal, route, or pronunciation acceptance evidence.
        for _ in 0..<1800 {
            writer.append(chunk)
            guard completedWindow.wait(timeout: .now() + 10) == .success else {
                XCTFail("The writer stalled before publishing its durable window")
                throw QuranCaptureFailure.overloadedWriter
            }
        }
        writer.finish { result in XCTAssertEqual(try? result.get(), 57_600_000); closed.fulfill() }
        await fulfillment(of: [closed], timeout: 10)
        XCTAssertEqual(count, 1800)
        XCTAssertEqual(largest, 128_000)
        let file = try AVAudioFile(forReading: url)
        XCTAssertEqual(file.length, 57_600_000)
        for offset in [Int64(0), file.length - 1024] {
            file.framePosition = offset
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 1024))
            try file.read(into: buffer)
            let samples = try XCTUnwrap(buffer.floatChannelData?[0])
            for index in 0..<1024 {
                XCTAssertEqual(samples[index], chunk[Int((offset + Int64(index)) % 32_000)])
            }
        }
        print("PCM_HOUR_COMPONENT: frames=57600000, maxWindowFrames=\(largest), wallSeconds=\(Date().timeIntervalSince(started)); accelerated simulator file pipeline, not a hardware soak")
    }
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
