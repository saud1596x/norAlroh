import Foundation

struct NoorReciter: Codable, Identifiable, Hashable {
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
              base.path.hasPrefix("/audio/"), base.path.hasSuffix("/") else { return nil }
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
