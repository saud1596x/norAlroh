import Foundation

/// Signal measurements only: silence is not a learner error and loud input is
/// not proof of speech. Measure pre-inference PCM without changing saved audio.
public struct QuranInputQuality {
    public enum Reading: Equatable { case noSignal, weak, clipping, present }
    private var count = 0
    private var squared: Double = 0
    private var clipped = 0
    private var maximum: Float = 0
    public init() {}
    public mutating func consume(_ samples: [Float]) -> [Reading] {
        var output: [Reading] = []
        for sample in samples {
            guard sample.isFinite else { continue }
            count += 1; squared += Double(sample) * Double(sample)
            maximum = max(maximum, abs(sample))
            if abs(sample) >= 0.995 { clipped += 1 }
            if count == 8_000 {
                let rms = sqrt(squared / Double(count))
                output.append(maximum == 0 ? .noSignal : Double(clipped) / Double(count) >= 0.01 ? .clipping
                    : rms < 0.0005 ? .weak : .present)
                count = 0; squared = 0; clipped = 0; maximum = 0
            }
        }
        return output
    }
}
