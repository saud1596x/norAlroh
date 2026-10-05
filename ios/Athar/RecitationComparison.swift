import Foundation

struct RecitationExpectedWord: Identifiable {
    let id: Int
    let chapter: Int
    let ayah: Int
    let text: String
    let normalized: String
    let alternateNormalized: String
    func matches(_ heard: String) -> Bool { normalized == heard || alternateNormalized == heard }
}
struct RecitationDifference: Identifiable {
    let id: Int
    let wordIndex: Int?
    let expected: String?
    let heard: String?
}
struct RecitationComparison {
    let matchedIndices: [Int]
    let possibleDifferences: [RecitationDifference]
    let endIndex: Int
    let reliableAlignment: Bool
    static func words(chapter: Surah, from: Int, to: Int) -> [RecitationExpectedWord] {
        var result: [RecitationExpectedWord] = []
        for ayah in chapter.ayahs where (from...to).contains(ayah.number) {
            for text in ayah.text.split(whereSeparator: \.isWhitespace) {
                let normalized = normalize(String(text))
                if !normalized.isEmpty {
                    // ASR generally writes ordinary Arabic. Accept the pronounced alif
                    // represented by dagger alif, while preserving exact displayed text.
                    let alternate = normalize(String(text).replacingOccurrences(of: "\u{0670}", with: "ا"))
                    result.append(.init(id: result.count, chapter: chapter.number, ayah: ayah.number, text: String(text), normalized: normalized, alternateNormalized: alternate))
                }
            }
        }
        return result
    }
    static func normalize(_ word: String) -> String {
        String(String.UnicodeScalarView(ArabicSearch.normalize(word).unicodeScalars.filter {
            CharacterSet.letters.contains($0) && $0.value != 0x06E5 && $0.value != 0x06E6
        }))
    }
    /// Semi-global word alignment. Unspoken suffixes aren't omissions. Previously followed prefixes may be skipped.
    static func align(expected: [RecitationExpectedWord], heard: String, anchor: Int = 0) -> RecitationComparison {
        let tokens = heard.split(whereSeparator: \.isWhitespace).map { (raw: String($0), normalized: normalize(String($0))) }.filter { !$0.normalized.isEmpty }
        let empty = RecitationComparison(matchedIndices: [], possibleDifferences: [], endIndex: max(0, min(anchor, expected.count)), reliableAlignment: false)
        guard !expected.isEmpty, expected.count <= 1500, tokens.count >= 3, tokens.count <= 160 else { return empty }
        let n = expected.count, m = tokens.count, safeAnchor = max(0, min(anchor, n))
        var costs = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in 0...n { costs[i][0] = max(0, i - safeAnchor) }
        for j in 0...m { costs[0][j] = j }
        for i in 1...n { for j in 1...m {
            costs[i][j] = min(costs[i - 1][j - 1] + (expected[i - 1].matches(tokens[j - 1].normalized) ? 0 : 1),
                              min(costs[i - 1][j] + 1, costs[i][j - 1] + 1))
        } }
        let likelyEnd = min(n, safeAnchor + m)
        let end = (1...n).min { a, b in
            costs[a][m] == costs[b][m] ? abs(a - likelyEnd) < abs(b - likelyEnd) : costs[a][m] < costs[b][m]
        }!
        var i = end, j = m, matches: [Int] = [], differences: [RecitationDifference] = []
        while j > 0 {
            if i > 0 {
                let same = expected[i - 1].matches(tokens[j - 1].normalized)
                if costs[i][j] == costs[i - 1][j - 1] + (same ? 0 : 1) {
                    if same { matches.append(i - 1) }
                    else { differences.append(.init(id: differences.count, wordIndex: i - 1, expected: expected[i - 1].text, heard: tokens[j - 1].raw)) }
                    i -= 1; j -= 1; continue
                }
                if costs[i][j] == costs[i - 1][j] + 1 {
                    differences.append(.init(id: differences.count, wordIndex: i - 1, expected: expected[i - 1].text, heard: nil)); i -= 1; continue
                }
            }
            differences.append(.init(id: differences.count, wordIndex: nil, expected: nil, heard: tokens[j - 1].raw)); j -= 1
        }
        while i > safeAnchor {
            differences.append(.init(id: differences.count, wordIndex: i - 1, expected: expected[i - 1].text, heard: nil)); i -= 1
        }
        let reliable = matches.count >= 3 && Double(costs[end][m]) / Double(m) <= 0.35
        return .init(matchedIndices: reliable ? Array(matches.reversed()) : [], possibleDifferences: reliable ? Array(differences.reversed()) : [],
                     endIndex: reliable ? end : safeAnchor, reliableAlignment: reliable)
    }
}

/// Callback order is preserved, and inference receives an immutable bounded snapshot.
final class RecitationAudioBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [Float] = []
    private var accepting = true
    private let limit = 30 * 16000
    func append(_ values: [Float]) {
        lock.lock(); defer { lock.unlock() }
        guard accepting else { return }
        samples.append(contentsOf: values)
        if samples.count > limit { samples.removeFirst(samples.count - limit) }
    }
    func snapshot() -> [Float] { lock.lock(); defer { lock.unlock() }; return samples }
    func erase() { lock.lock(); defer { lock.unlock() }; accepting = false; samples.removeAll(keepingCapacity: false) }
}
