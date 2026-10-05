import Foundation

struct DhikrQuranReference {
    let chapter: Int
    let from: Int
    let to: Int
    let title: String
}

struct DhikrReadingBlock: Identifiable {
    enum Kind { case invocation, instruction, basmala, quran }
    let id: Int
    let kind: Kind
    let sourceText: String
    let quran: DhikrQuranReference?
}

/// Split source spans, never reconstruct or normalize the original Hisn text.
struct DhikrReadingContent {
    let source: DhikrEntry
    let blocks: [DhikrReadingBlock]
    var title: String {
        if let first = blocks.first(where: { $0.quran != nil })?.quran {
            return blocks.filter { $0.quran != nil }.count > 1 ? "الإخلاص والفلق والناس" : first.title
        }
        let names = ["hisn-27-79": "سيد الاستغفار", "hisn-27-83": "حسبي الله", "hisn-27-84": "العفو والعافية", "hisn-27-91": "سبحان الله وبحمده", "hisn-27-98": "الصلاة على النبي"]
        return names[source.id] ?? source.title
    }
    var counterEntry: DhikrEntry {
        let repeatedSeven = source.id == "hisn-27-83" && ArabicSearch.normalize(source.text).contains("سبع مرات")
        return DhikrEntry(id: source.id, title: source.title, text: source.text, target: repeatedSeven ? 7 : source.target,
                         reference: source.reference, sourceURL: source.sourceURL)
    }
    var usesCanonicalQuran: Bool { blocks.contains { $0.quran != nil } }
    var originalReassembled: String { blocks.map(\.sourceText).joined() }

    init(entry: DhikrEntry) {
        source = entry
        let kursi = [DhikrQuranReference(chapter: 2, from: 255, to: 255, title: "آية الكرسي")]
        let shortSurahs = [DhikrQuranReference(chapter: 112, from: 1, to: 4, title: "سورة الإخلاص"),
                           DhikrQuranReference(chapter: 113, from: 1, to: 5, title: "سورة الفلق"),
                           DhikrQuranReference(chapter: 114, from: 1, to: 6, title: "سورة الناس")]
        let known: [String: [DhikrQuranReference]] = ["hisn-27-75": kursi, "hisn-28-100": kursi, "hisn-25-71": kursi,
            "hisn-27-76": shortSurahs, "hisn-28-99": shortSurahs, "hisn-25-70": shortSurahs,
            "hisn-28-101": [.init(chapter: 2, from: 285, to: 286, title: "خواتيم سورة البقرة")]]
        let matcher = try! NSRegularExpression(pattern: #"\[[^\[\]]*\]|﴿[^﴿﴾]*﴾|بسم الله الرحمن الرحيم"#)
        let matches = matcher.matches(in: entry.text, range: NSRange(entry.text.startIndex..., in: entry.text))
        let quranCount = matches.filter { (entry.text as NSString).substring(with: $0.range).hasPrefix("﴿") }.count
        // A changed source structure must fall back to its original text, not the wrong verse.
        let references = known[entry.id].flatMap { $0.count == quranCount ? $0 : nil } ?? []
        var parts: [DhikrReadingBlock] = [], cursor = 0, quranIndex = 0
        let sourceString = entry.text as NSString
        func append(_ range: NSRange, _ kind: DhikrReadingBlock.Kind, _ reference: DhikrQuranReference? = nil) {
            guard range.length > 0 else { return }
            parts.append(.init(id: parts.count, kind: kind, sourceText: sourceString.substring(with: range), quran: reference))
        }
        for match in matches {
            append(NSRange(location: cursor, length: match.range.location - cursor), .invocation)
            let token = sourceString.substring(with: match.range)
            if token.hasPrefix("﴿") {
                append(match.range, .quran, references.indices.contains(quranIndex) ? references[quranIndex] : nil)
                quranIndex += 1
            } else { append(match.range, token.hasPrefix("[") ? .instruction : .basmala) }
            cursor = NSMaxRange(match.range)
        }
        append(NSRange(location: cursor, length: sourceString.length - cursor), .invocation)
        blocks = parts
    }
}
