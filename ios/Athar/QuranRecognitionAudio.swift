import Foundation

/// Condition only the inference copy. The recorder retains the original PCM.
/// Bounded gain is not speech detection: silence, word timing, model confidence
/// and exact Quran anchoring still have to pass their independent checks.
enum QuranRecognitionAudio {
    static func conditioned(_ samples: [Float]) throws -> [Float] {
        guard !samples.isEmpty, samples.allSatisfy(\.isFinite) else {
            throw QuranCaptureFailure.invalidSamples
        }
        let peak = samples.reduce(Float(0)) { max($0, abs($1)) }
        guard peak > 0 else { return samples }
        let rms = sqrt(samples.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(samples.count))
        // At most 18 dB; never clip or attenuate an already usable input.
        let gain = max(1, min(8, min(0.06 / max(rms, 0.000001), 0.9 / Double(peak))))
        guard gain > 1 else { return samples }
        return samples.map { $0 * Float(gain) }
    }
}
