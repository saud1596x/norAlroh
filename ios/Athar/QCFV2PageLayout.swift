import Foundation

/// Builds page metadata from the licensed runtime snapshot, never from bundled
/// Content API data. Quran verse keys come from the verified Tanzil corpus.
enum QCFV2PageLayout {
    static func database(snapshot: QCFV2Snapshot, corpus: [Surah]) throws -> MushafDatabase {
        _ = try snapshot.validated()
        let keys = corpus.flatMap { chapter in chapter.ayahs.map { "\(chapter.number):\($0.number)" } }
        guard keys.count == 6236, corpus.map(\.number) == Array(1...114) else {
            throw QCFV2Snapshot.Invalid.verse
        }
        let juzPages = [1,22,42,62,82,102,121,142,162,182,201,222,242,262,282,302,322,342,362,382,402,422,442,462,482,502,522,542,562,582]
        let positioned = Dictionary(grouping: snapshot.records.filter { $0.record_type == "mushaf_word" }, by: { $0.page_number! })
        var layouts: [Int: [String: MushafLayout]] = [:]
        var chapterPages: [String: Int] = [:]
        var firstVerse = 1
        for chapter in corpus {
            guard let first = snapshot.records.first(where: {
                $0.record_type == "mushaf_word" && $0.verse_id == firstVerse && $0.position_in_verse == 1
            }), let page = first.page_number, let sourceLine = first.line_number else {
                throw QCFV2Snapshot.Invalid.verse
            }
            let line = sourceLine - (page <= 2 ? 7 : 0)
            chapterPages[String(chapter.number)] = page
            let headerOffset = chapter.number == 1 || chapter.number == 9 ? 1 : 2
            // A surah title may occupy line 15 of the preceding page. Its
            // basmala then starts line 1 of the next page; do not overlap ayahs.
            var headerPage = page
            var headerLine = line - headerOffset
            if headerLine < 1 { headerPage -= 1; headerLine += 15 }
            guard headerPage > 0, (1...15).contains(headerLine),
                  layouts[headerPage]?[String(headerLine)] == nil else { throw QCFV2Snapshot.Invalid.page }
            layouts[headerPage, default: [:]][String(headerLine)] = MushafLayout(type: "header", chapter: chapter.number, code: nil, font: "Amiri-Regular")
            if headerOffset == 2 {
                guard let basmala = QuranText.separateBasmalas[String(chapter.number)], !basmala.isEmpty else {
                    throw QCFV2Snapshot.Invalid.verse
                }
                layouts[page, default: [:]][String(line - 1)] = MushafLayout(type: "bismillah", chapter: chapter.number, code: basmala, font: "Amiri-Regular")
            }
            firstVerse += chapter.ayahs.count
        }
        var pages: [MushafPage] = []
        for number in 1...604 {
            let words = (positioned[number] ?? []).sorted { $0.position_in_page! < $1.position_in_page! }.map {
                MushafWord(code: $0.text!, line: $0.line_number! - (number <= 2 ? 7 : 0),
                           key: keys[$0.verse_id! - 1], kind: $0.char_type_name!)
            }
            let rows = number <= 2 ? 8 : 15
            guard !words.isEmpty, words.allSatisfy({ (1...rows).contains($0.line) }),
                  (layouts[number] ?? [:]).keys.allSatisfy({ row in
                      guard let line = Int(row), (1...rows).contains(line) else { return false }
                      return !words.contains { $0.line == line }
                  }) else { throw QCFV2Snapshot.Invalid.page }
            pages.append(MushafPage(page: number, font: String(format: "QCF2%03d", number),
                                    juz: juzPages.filter { number >= $0 }.count,
                                    layout: layouts[number] ?? [:], words: words))
        }
        guard pages.flatMap({ $0.words.filter { $0.kind == "end" }.map(\.key) }) == keys else {
            throw QCFV2Snapshot.Invalid.verse
        }
        return MushafDatabase(pages: pages, chapterPages: chapterPages, juzPages: juzPages)
    }
}
