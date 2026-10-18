import Foundation

/// Actual worker activity, not a decorative listening animation or progress.
/// Use a monotonic clock and a brief grace period to avoid a per-window flicker.
struct QuranTrackingFeedback: Sendable {
    enum Activity: Sendable { case preparingModel, recognizing, locatingPassage }
    let activity: Activity
    let startedAt: Double
    func message(now: Double) -> String? {
        guard startedAt.isFinite, now.isFinite, now >= startedAt, now - startedAt >= 0.7 else { return nil }
        switch activity {
        case .preparingModel: return "أستمع · تجهيز التتبع"
        case .recognizing: return "أستمع · معالجة التلاوة"
        case .locatingPassage: return "أستمع · تحديد موضع التلاوة"
        }
    }
}

enum QuranTrackingUncertainty: Sendable {
    case none, noSpeech, unreliableWords, passageUnclear
    var message: String? {
        switch self {
        case .none: return nil
        case .noSpeech: return "الميكروفون مفتوح · أنتظر التلاوة"
        case .unreliableWords: return "أستمع · لم يتضح الكلام بعد"
        case .passageUnclear: return "أستمع · أكمل التلاوة ليتضح الموضع"
        }
    }
}

/// Condition only the inference copy. The recorder retains the original PCM.
/// Bounded gain is not speech detection: silence, word timing, model confidence
/// and exact Quran anchoring still have to pass their independent checks.
enum QuranRecognitionAudio {
    /// Ceiling only; the RMS target and peak headroom usually select less gain.
    static let maximumInferenceGain: Double = 256
    static func conditioned(_ samples: [Float]) throws -> [Float] {
        guard !samples.isEmpty, samples.allSatisfy({ $0.isFinite && abs($0) <= 1 }) else {
            throw QuranCaptureFailure.invalidSamples
        }
        // Remove only a substantial measured DC offset. Its energy must not
        // consume gain headroom or turn a constant digital signal into speech.
        // There is no resampling, phase filter or change to archived samples.
        let mean = samples.reduce(0.0) { $0 + Double($1) } / Double(samples.count)
        let centered = abs(mean) >= 0.01 ? samples.map { $0 - Float(mean) } : samples
        let peak = centered.reduce(Float(0)) { max($0, abs($1)) }
        guard peak > 0 else { return centered }
        let rms = sqrt(centered.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(centered.count))
        // Allow up to 48 dB for very weak input. This cannot distinguish a voice
        // from background noise: preserve confidence/no-speech checks independently.
        // Never clip or attenuate an already usable input.
        let gain = max(1, min(maximumInferenceGain, min(0.06 / max(rms, 0.000001), 0.9 / Double(peak))))
        // Recentring can increase one-sided headroom above one. Attenuate only
        // that exceptional centered result; ordinary audible input is unchanged.
        let headroom = peak > 1 ? Double(0.99 / peak) : gain
        guard headroom != 1 else { return centered }
        return centered.map { $0 * Float(headroom) }
    }
}
