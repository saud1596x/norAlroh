import Foundation
import CNoorVAD

/// WebRTC's binary speech decision is not a Quran confidence or an error grade.
/// Scan the audio without rewriting its timeline. Keep breath/pauses in saved PCM.
enum QuranVoiceActivity {
    struct Interval: Equatable, Sendable { let start: Double; let end: Double }
    struct Scan: Sendable {
        let intervals: [Interval]
        let analyzedFrames: Int
        var hasSpeech: Bool { !intervals.isEmpty }
    }
    static func scan(_ samples: [Float]) throws -> Scan {
        guard !samples.isEmpty, samples.count <= 480_000, samples.allSatisfy(\.isFinite),
              let vad = fvad_new() else { throw QuranCaptureFailure.invalidSamples }
        defer { fvad_free(vad) }
        // Least aggressive mode favors retaining quiet/elongated recitation.
        guard fvad_set_sample_rate(vad, 16_000) == 0, fvad_set_mode(vad, 0) == 0 else {
            throw QuranCaptureFailure.invalidSamples
        }
        let frameCount = 320 // Exactly 20ms at 16kHz.
        var frame = [Int16](repeating: 0, count: frameCount)
        var intervals: [Interval] = []
        var analyzed = 0
        for offset in stride(from: 0, to: samples.count, by: frameCount) {
            let available = min(frameCount, samples.count - offset)
            for index in 0..<frameCount {
                let value = index < available ? samples[offset + index] : 0
                frame[index] = Int16(max(-32_768, min(32_767, Double(value) * 32_767)))
            }
            let result = frame.withUnsafeBufferPointer { fvad_process(vad, $0.baseAddress!, frameCount) }
            guard result >= 0 else { throw QuranCaptureFailure.invalidSamples }
            analyzed += 1
            if result == 1 {
                let start = Double(offset) / 16_000, end = Double(offset + available) / 16_000
                if let last = intervals.last, abs(last.end - start) < 0.000_001 {
                    intervals[intervals.count - 1] = Interval(start: last.start, end: end)
                } else { intervals.append(Interval(start: start, end: end)) }
            }
        }
        return Scan(intervals: intervals, analyzedFrames: analyzed)
    }
}
