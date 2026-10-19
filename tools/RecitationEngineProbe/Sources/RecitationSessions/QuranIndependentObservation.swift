import Foundation
#if canImport(RecitationAlignment)
import RecitationAlignment
#endif

/// Local evidence of what the independent decoder actually emitted, including
/// disagreement. Never replace it with the canonical passage or primary text.
public struct QuranIndependentObservation: Codable, Equatable, Sendable {
    public let modelRevision: String
    public let configuration: String
    public let sourceSHA256: String
    public let startFrame: Int64
    public let endFrame: Int64
    public let words: [QuranIndependentWord]
    public init(modelRevision: String, configuration: String, sourceSHA256: String,
                startFrame: Int64, endFrame: Int64, words: [QuranIndependentWord]) {
        self.modelRevision = modelRevision; self.configuration = configuration
        self.sourceSHA256 = sourceSHA256; self.startFrame = startFrame; self.endFrame = endFrame
        self.words = words
    }
    public func valid(start: Double, end: Double) -> Bool {
        let difference = endFrame.subtractingReportingOverflow(startFrame)
        guard !difference.overflow else { return false }
        let count = difference.partialValue
        return startFrame >= 0 && (400...256_000).contains(count)
            && start == Double(startFrame)/16_000 && end == Double(endFrame)/16_000
            && modelRevision == "b539d5fa66deb820c8e4762171ecb284ace4b52d"
            && configuration == "coreml-ctc-float32/cpu-only/raw-20ms/no-prompt/paired1"
            && sourceSHA256.utf8.count == 64 && sourceSHA256.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
            && words.count <= 1000 && words.allSatisfy { !$0.text.isEmpty && $0.text.utf8.count <= 512
                && $0.start.isFinite && $0.end.isFinite && $0.start >= 0 && $0.end > $0.start
                && $0.end <= Double(count)/16_000 && $0.meanPosterior.isFinite && (0...1).contains($0.meanPosterior) }
            && zip(words, words.dropFirst()).allSatisfy { $0.end <= $1.start }
    }
}
