import XCTest
import AVFoundation
@testable import RecitationCapture

final class QuranPCMResamplerTests: XCTestCase {
    func testContinuousMicrophoneRatesPreserveDurationAndDoNotRepeatBuffers() throws {
        for rate in [44_100.0, 48_000.0] {
            let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1))
            let converter = try QuranPCMResampler(input: format)
            var output: [Float] = []
            let length = Int(rate * 2)
            for start in stride(from: 0, to: length, by: 4096) {
                let count = min(4096, length - start)
                let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)))
                buffer.frameLength = AVAudioFrameCount(count)
                let channel = try XCTUnwrap(buffer.floatChannelData?[0])
                for index in 0..<count {
                    let frame = start + index
                    // Different levels before/after one second expose duplicated
                    // input or per-buffer resets that a silence test would miss.
                    let amplitude = frame < Int(rate) ? 0.1 : 0.6
                    channel[index] = Float(amplitude * sin(2 * .pi * 400 * Double(frame) / rate))
                }
                output += try converter.convert(buffer)
            }
            output += try converter.finish()
            XCTAssertEqual(Double(output.count) / 16_000, 2, accuracy: 0.002)
            XCTAssertTrue(output.allSatisfy(\.isFinite))
            func rms(_ samples: ArraySlice<Float>) -> Double {
                (samples.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(samples.count)).squareRoot()
            }
            guard output.count >= 30_000 else { XCTFail("Converted audio truncated"); continue }
            XCTAssertEqual(rms(output[2_000..<14_000]), 0.1 / sqrt(2), accuracy: 0.008)
            XCTAssertEqual(rms(output[18_000..<30_000]), 0.6 / sqrt(2), accuracy: 0.008)
            XCTAssertTrue(try converter.finish().isEmpty)
        }
    }
}
