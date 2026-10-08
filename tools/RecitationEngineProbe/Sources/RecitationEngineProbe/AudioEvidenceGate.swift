import Foundation

/// A necessary acoustic/timing gate, not a speech classifier or Quran grader.
/// Low-volume input stays unresolved; it must never become a reader error.
enum AudioEvidenceGate {
    struct Evidence {
        let start: Float
        let end: Float
        let probability: Float
    }
    enum Rejection: String, Codable {
        case invalidAudio, invalidTiming, lowConfidence, insufficientAudio
    }
    static let sampleRate = 16_000
    static let minimumRMS: Double = 0.02

    static func rejection(_ word: Evidence, samples: [Float]) -> Rejection? {
        guard !samples.isEmpty, samples.allSatisfy(\.isFinite) else { return .invalidAudio }
        let duration = Double(samples.count) / Double(sampleRate)
        guard word.start.isFinite, word.end.isFinite,
              word.start >= 0, word.end > word.start,
              Double(word.end) <= duration + 0.1 else { return .invalidTiming }
        guard word.probability.isFinite, (0...1).contains(word.probability),
              word.probability >= 0.75 else { return .lowConfidence }
        // This is only an evidence window. The original word timings are never
        // clamped or rewritten; partial silence tails of at most 100 ms are
        // tolerated, whereas the observed 28-second hallucinations are rejected.
        let first = Int(Double(word.start) * Double(sampleRate))
        let last = min(samples.count, Int(Double(word.end) * Double(sampleRate)))
        guard first < last else { return .invalidTiming }
        let signal = samples[first..<last]
        let squareMean = signal.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(signal.count)
        guard squareMean.squareRoot() >= minimumRMS else { return .insufficientAudio }
        return nil
    }
}
