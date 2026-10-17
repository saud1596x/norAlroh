import Foundation

/// Presentation variants from the explicit morning/evening instructions in
/// bundled Hisn chapter 27. The audited original file is never rewritten.
enum DhikrDayPeriod: String, CaseIterable, Identifiable {
    case morning, evening
    var id: String { rawValue }
    var title: String { self == .morning ? "أذكار الصباح" : "أذكار المساء" }
    var symbol: String { self == .morning ? "sun.max.fill" : "moon.stars.fill" }
    func group(in content: AdhkarContent) -> DhikrGroup {
        .init(id: "hisn-27-" + rawValue, name: title, note: "", icon: self == .morning ? "sun" : "moon",
              items: entries(in: content).map(\.id))
    }
    func entries(in content: AdhkarContent) -> [DhikrEntry] {
        guard let original = content.groups.first(where: { $0.id == "hisn-27" }) else { return [] }
        return content.entries(in: original).filter {
            self == .morning ? $0.id != "hisn-27-97" : !["hisn-27-93", "hisn-27-94", "hisn-27-95"].contains($0.id)
        }.enumerated().map { offset, entry in
            var text = entry.text
            let notes = try! NSRegularExpression(pattern: #"\[[^\[\]]*\]"#)
            let ns = text as NSString
            let spans = notes.matches(in: text, range: NSRange(location: 0, length: ns.length))
            if self == .evening {
                // Complete evening formulations are explicitly provided by the source.
                if ["hisn-27-78", "hisn-27-89"].contains(entry.id), let span = spans.first {
                    let note = ns.substring(with: span.range)
                    if let colon = note.firstIndex(of: ":") {
                        text = String(note[note.index(after: colon)..<note.index(before: note.endIndex)])
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                } else {
                    text = notes.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: ns.length), withTemplate: "")
                    switch entry.id {
                    case "hisn-27-77":
                        text = text.replacingOccurrences(of: "أَصْبَحْنَا وَأَصْبَحَ", with: "أَمْسَيْنَا وَأَمْسَى")
                            .replacingOccurrences(of: "هَذَا الْيَوْمِ", with: "هَذِهِ اللَّيْلَةِ")
                            .replacingOccurrences(of: "بَعْدَهُ", with: "بَعْدَهَا")
                    case "hisn-27-80": text = text.replacingOccurrences(of: "أَصْبَحْتُ", with: "أَمْسَيْتُ")
                    case "hisn-27-81": text = text.replacingOccurrences(of: "أَصْبَحَ", with: "أَمْسَى")
                    case "hisn-27-90": text = text.replacingOccurrences(of: "أَصْبَحْنا", with: "أَمْسَيْنَا")
                    default: break
                    }
                }
            } else {
                text = notes.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: ns.length), withTemplate: "")
            }
            return .init(id: entry.id, title: "\(title) · \(offset + 1)", text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                         target: entry.target, reference: entry.reference, sourceURL: entry.sourceURL)
        }
    }
}
