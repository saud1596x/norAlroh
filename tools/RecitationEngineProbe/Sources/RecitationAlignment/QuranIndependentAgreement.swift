import Foundation

/// Raw acoustic hypotheses, never scripture supplied by a reference prompt.
/// CTC posteriors are not calibrated probabilities of correct recitation.
public struct QuranIndependentWord: Codable, Equatable, Sendable {
    public let text: String
    public let start: Double
    public let end: Double
    public let meanPosterior: Double
    public init(text: String, start: Double, end: Double, meanPosterior: Double) {
        self.text = text; self.start = start; self.end = end; self.meanPosterior = meanPosterior
    }
}

/// A second recognizer may withhold a first recognizer's hypothesis. It cannot
/// create words, repair spelling, fill an omission, or change source timings.
public enum QuranIndependentAgreement {
    public struct Key: Hashable, Sendable {
        public let text: String
        public let start: Double
        public let end: Double
        public init(text: String, start: Double, end: Double) {
            self.text = text; self.start = start; self.end = end
        }
    }
    public struct Result: Sendable {
        public let runs: [[QuranHeardWord]]
        public let retained: Set<Key>
        public let disagreements: Int
        public let hasIndependentOnlyWords: Bool
    }
    private static func comparison(_ text: String) -> String {
        // Only the independent comparison shares the CTC model's orthography.
        // The authentic Quran binding still validates the primary spelling.
        QuranAlignedWord.normalize(text).replacingOccurrences(of: "أ", with: "ا")
            .replacingOccurrences(of: "إ", with: "ا").replacingOccurrences(of: "آ", with: "ا")
    }
    public static func evaluate(_ primary: [[QuranHeardWord]], independent: [QuranIndependentWord],
                                duration: Double) throws -> Result {
        guard duration.isFinite, duration > 0, duration <= 16,
              primary.reduce(0, { $0 + $1.count }) <= 1000, independent.count <= 1000,
              independent.allSatisfy({ !$0.text.isEmpty && $0.text.utf8.count <= 512
                  && $0.start.isFinite && $0.end.isFinite && $0.start >= 0 && $0.end > $0.start
                  && $0.end <= duration && $0.meanPosterior.isFinite && (0...1).contains($0.meanPosterior) }),
              zip(independent, independent.dropFirst()).allSatisfy({ $0.end <= $1.start }) else {
            throw QuranAlignmentFailure.invalidEvidence
        }
        let flat = primary.flatMap { $0 }
        guard flat.allSatisfy({ !$0.text.isEmpty && $0.start.isFinite && $0.end.isFinite
            && $0.start >= 0 && $0.end > $0.start && $0.end <= duration
            && $0.probability.isFinite && (0...1).contains($0.probability) }),
              zip(flat,flat.dropFirst()).allSatisfy({ $0.end <= $1.start }) else {
            throw QuranAlignmentFailure.invalidEvidence
        }
        // A repeated word must have one unique acoustic occurrence in each
        // model. A broad timestamp overlapping two repetitions is unresolved.
        let matches = flat.map { heard in independent.indices.filter { index in
            comparison(heard.text) == comparison(independent[index].text)
                && min(heard.end, independent[index].end) > max(heard.start, independent[index].start)
        } }
        var uses: [Int: Int] = [:]
        for match in matches where match.count == 1 { uses[match[0], default: 0] += 1 }
        var result: [[QuranHeardWord]] = [], retained = Set<Key>(), position = 0, disagreements = 0
        for run in primary {
            var current: [QuranHeardWord] = []
            var previousIndependent: Int?
            for word in run {
                let candidates = matches[position]; position += 1
                if candidates.count == 1, uses[candidates[0]] == 1 {
                    if let previousIndependent, candidates[0] != previousIndependent+1, !current.isEmpty {
                        result.append(current); current = []
                    }
                    current.append(word)
                    retained.insert(Key(text: word.text, start: word.start, end: word.end))
                    previousIndependent = candidates[0]
                } else {
                    disagreements += 1
                    if !current.isEmpty { result.append(current); current = [] }
                    previousIndependent = nil
                }
            }
            if !current.isEmpty { result.append(current) }
        }
        return Result(runs: result, retained: retained, disagreements: disagreements,
                      hasIndependentOnlyWords: independent.indices.contains { uses[$0] != 1 })
    }
}
