import Foundation

struct NoorVerseReciter: Identifiable {
    let id: String
    let name: String
    static let all: [Self] = [
        .init(id: "Abdul_Basit_Murattal_64kbps", name: "عبد الباسط عبد الصمد"),
        .init(id: "Abdurrahmaan_As-Sudais_192kbps", name: "عبد الرحمن السديس"),
        .init(id: "Hudhaify_64kbps", name: "علي الحذيفي"),
        .init(id: "Maher_AlMuaiqly_64kbps", name: "ماهر المعيقلي"),
        .init(id: "Saood_ash-Shuraym_128kbps", name: "سعود الشريم")
    ]
    // Keep older bookmarks and verified cache files readable. Timings never
    // transfer between bitrates; only the exact published recording is used.
    static let legacyRecordings: [Self] = [
        .init(id: "Abdurrahmaan_As-Sudais_64kbps", name: "عبد الرحمن السديس"),
        .init(id: "Saood_ash-Shuraym_64kbps", name: "سعود الشريم")
    ]
    static let directories = Set((all + legacyRecordings).map(\.id))
    static func cacheKey(directory: String, verse: String) -> String? {
        guard directories.contains(directory),
              NoorAudioIntegrity.url(verse) != nil, !verse.hasPrefix("v:"), !verse.hasPrefix("r:") else { return nil }
        return directory == all[0].id ? verse : "v:\(directory):\(verse)"
    }
}

struct NoorReciter: Codable, Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
    let recordingID: Int
    let server: String
    let surahs: [Int]

    // A whole-surah recording has no fabricated verse boundaries.
    func audioURL(surah: Int) -> URL? {
        guard (1...114).contains(surah), surahs.contains(surah),
              let base = URL(string: server), base.scheme == "https",
              base.host == "cdn.mp3quran.net", base.user == nil, base.password == nil,
              base.port == nil, base.query == nil, base.fragment == nil,
              base.path.hasPrefix("/audio/"), base.hasDirectoryPath else { return nil }
        return base.appendingPathComponent(String(format: "%03d.mp3", surah))
    }
}

enum NoorReciterCatalog {
    private struct Document: Decodable {
        let schema: Int
        let reciters: [NoorReciter]
    }
    static let source = URL(string: "https://www.mp3quran.net/ar/api")!
    static let reciters: [NoorReciter] = {
        guard let url = Bundle.main.url(forResource: "haramain-reciters", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let document = try? JSONDecoder().decode(Document.self, from: data),
              document.schema == 1,
              Set(document.reciters.map(\.id)).count == document.reciters.count,
              document.reciters.allSatisfy({ reciter in
                  !reciter.name.isEmpty && reciter.surahs.count == 114 &&
                  Set(reciter.surahs) == Set(1...114) &&
                  reciter.surahs.allSatisfy { reciter.audioURL(surah: $0) != nil }
              }) else { return [] }
        return document.reciters
    }()
}
