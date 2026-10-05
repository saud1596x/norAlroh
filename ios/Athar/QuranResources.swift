import Foundation
import CryptoKit

// A hash detects changed assets; it does not replace scholarly review of the source.
enum QuranResources {
    private static let manifest: [String: String] = {
        guard let url = Bundle.main.url(forResource: "quran-resource-hashes", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }()

    static func verified(_ data: Data, resource: String) -> Bool {
        guard let expected = manifest[resource] else { return false }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() == expected
    }

    static func data(_ name: String, extension ext: String = "json") -> Data? {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext),
              let data = try? Data(contentsOf: url), verified(data, resource: "\(name).\(ext)") else { return nil }
        return data
    }

    static let corpus: [Surah]? = {
        guard let data = data("quran"), let chapters = try? JSONDecoder().decode([Surah].self, from: data),
              chapters.map(\.number) == Array(1...114), chapters.reduce(0, { $0 + $1.ayahs.count }) == 6236,
              chapters.allSatisfy({ chapter in
                  !chapter.ayahs.isEmpty && chapter.ayahs.map(\.number) == Array(1...chapter.ayahs.count)
                      && chapter.ayahs.allSatisfy { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
              }) else { return nil }
        return chapters
    }()
}
