import Foundation
import CryptoKit

/// A resumable word position only. No recording or recognized transcript is saved.
struct SpeechSessionPosition: Codable {
    var version = 1
    let chapter: Int
    let from: Int
    let to: Int
    let wordCount: Int
    let textDigest: String
    var nextWord: Int
    var usedHelp: Bool
    static func digest(_ words: [RecitationExpectedWord]) -> String {
        let canonical = words.map { "\($0.chapter):\($0.ayah):\($0.id):\($0.text)" }.joined(separator: "\n")
        return SHA256.hash(data: Data(canonical.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    static func make(words: [RecitationExpectedWord], nextWord: Int, usedHelp: Bool) -> Self? {
        guard let first = words.first, let last = words.last, words.allSatisfy({ $0.chapter == first.chapter }),
              (0...words.count).contains(nextWord) else { return nil }
        return Self(chapter: first.chapter, from: first.ayah, to: last.ayah, wordCount: words.count,
            textDigest: digest(words), nextWord: nextWord, usedHelp: usedHelp)
    }
    func matches(_ words: [RecitationExpectedWord]) -> Bool {
        version == 1 && chapter == words.first?.chapter && from == words.first?.ayah && to == words.last?.ayah
            && wordCount == words.count && (0...wordCount).contains(nextWord) && textDigest == Self.digest(words)
    }
    func valid(corpus: [Surah]) -> Bool {
        guard corpus.indices.contains(chapter - 1), from > 0, to >= from, to <= corpus[chapter - 1].ayahs.count else { return false }
        return matches(RecitationComparison.words(chapter: corpus[chapter - 1], from: from, to: to))
    }
}

final class SpeechPositionStore {
    private let defaults: UserDefaults
    private let key = "noor.speech.position.v1"
    private(set) var value: SpeechSessionPosition?
    private(set) var unreadable: Data?
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key) {
            if let position = try? JSONDecoder().decode(SpeechSessionPosition.self, from: data),
               let corpus = QuranResources.corpus, position.valid(corpus: corpus) { value = position }
            else { unreadable = data }
        }
    }
    @discardableResult func save(_ position: SpeechSessionPosition) -> Bool {
        guard unreadable == nil, let corpus = QuranResources.corpus, position.valid(corpus: corpus),
              let bytes = try? JSONEncoder().encode(position) else { return false }
        // Keep the previous range available for recovery when starting a new range.
        if let value, value.chapter != position.chapter || value.from != position.from || value.to != position.to,
           let previous = defaults.data(forKey: key) { defaults.set(previous, forKey: "noor.speech.previousPosition.v1") }
        defaults.set(bytes, forKey: key); value = position; return true
    }
    func erase() {
        defaults.removeObject(forKey: key); defaults.removeObject(forKey: "noor.speech.previousPosition.v1")
        value = nil; unreadable = nil
    }
}
