import Foundation

/// Read-only lexical correspondence. This never supplies display text or layout.
public struct QuranWordScript: Decodable {
    public struct Edition: Decodable {
        public let resource_group: String
        public let resource_id: Int
        public let resource_content_id: Int
    }
    public struct Group: Decodable {
        public let page: Int
        public let glyph: String
        public let imlaei: [String]
        public let canonical: [String]
        public init(from decoder: Decoder) throws {
            var container = try decoder.unkeyedContainer()
            page = try container.decode(Int.self)
            glyph = try container.decode(String.self)
            imlaei = try container.decode([String].self)
            canonical = try container.decode([String].self)
            guard container.isAtEnd else { throw QuranAlignmentFailure.invalidScript }
        }
    }
    public let schema_version: Int
    public let source_sha256: String
    public let edition: Edition
    public let groups: [String: [Group]]

    /// Bind only after the entire native edition has passed its own validator.
    /// Native IDs are supplied by that edition, never QUL's unrelated database.
    public func bind(native: [QuranNativeWord], verseKeys: [String]) throws -> [QuranAlignedWord] {
        guard schema_version == 2,
              source_sha256 == "60b5341ecf04b6dbcdd2c42cc9b377003d9185ac6a76ad104a109ed669b0cf3c",
              edition.resource_group == "mushafs", edition.resource_id == 1,
              edition.resource_content_id == 382,
              verseKeys.count == 6236, Set(verseKeys).count == 6236,
              Set(groups.keys) == Set(verseKeys), native.count == 77429,
              Set(native.map(\.id)).count == native.count else { throw QuranAlignmentFailure.invalidScript }
        let byVerse = Dictionary(grouping: native, by: \.verse)
        guard Set(byVerse.keys) == Set(verseKeys) else { throw QuranAlignmentFailure.invalidEdition }
        var result: [QuranAlignedWord] = []
        result.reserveCapacity(native.count)
        for key in verseKeys {
            let records = byVerse[key]!.sorted { $0.position < $1.position }
            let lexical = groups[key]!
            guard records.count == lexical.count,
                  records.map(\.position) == Array(1...records.count) else { throw QuranAlignmentFailure.invalidEdition }
            for (record, group) in zip(records, lexical) {
                guard record.page == group.page, record.glyph == group.glyph,
                      (1...604).contains(group.page) else { throw QuranAlignmentFailure.invalidEdition }
                let aliases = Set([QuranAlignedWord.tokens(group.imlaei),
                                   QuranAlignedWord.tokens(group.canonical),
                                   QuranAlignedWord.tokens(group.canonical, expandDaggerAlif: true)])
                guard aliases.allSatisfy({ !$0.isEmpty && $0.allSatisfy({ !$0.isEmpty }) }) else {
                    throw QuranAlignmentFailure.invalidScript
                }
                result.append(.init(id: record.id, verse: key, page: record.page, aliases: aliases))
            }
        }
        return result
    }
}

public enum QuranAlignmentFailure: Error { case invalidScript, invalidEdition, invalidEvidence }

public struct QuranNativeWord: Equatable, Sendable {
    public let id: Int
    public let verse: String
    public let position: Int
    public let page: Int
    public let glyph: String
    public init(id: Int, verse: String, position: Int, page: Int, glyph: String) {
        self.id = id; self.verse = verse; self.position = position; self.page = page; self.glyph = glyph
    }
}

public struct QuranAlignedWord: Sendable {
    public let id: Int
    public let verse: String
    public let page: Int
    public let aliases: Set<[String]>
    public init(id: Int, verse: String, page: Int, aliases: Set<[String]>) {
        self.id = id; self.verse = verse; self.page = page; self.aliases = aliases
    }
    /// Keep long vowels and consonants. No fuzzy distance or deletion of alif.
    public static func normalize(_ text: String, expandDaggerAlif: Bool = false) -> String {
        let expanded = (expandDaggerAlif ? text.replacingOccurrences(of: "\u{0670}", with: "ا") : text)
            .replacingOccurrences(of: "ٱ", with: "ا")
        let scalars = expanded.decomposedStringWithCompatibilityMapping.unicodeScalars.filter {
            CharacterSet.letters.contains($0) && !CharacterSet.nonBaseCharacters.contains($0)
                && $0.value != 0x0640
                && $0.value != 0x06E5 && $0.value != 0x06E6
        }
        return String(String.UnicodeScalarView(scalars))
    }
    public static func tokens(_ words: [String], expandDaggerAlif: Bool = false) -> [String] {
        words.flatMap { $0.split(whereSeparator: \.isWhitespace).map {
            normalize(String($0), expandDaggerAlif: expandDaggerAlif)
        } }
            .filter { !$0.isEmpty }
    }
}

/// Only evidence which already passed the word-local audio/timing gate belongs
/// here. This layer identifies a position; it cannot judge pronunciation.
public struct QuranHeardWord: Sendable {
    public let text: String
    public let start: Double
    public let end: Double
    public let probability: Double
    public init(text: String, start: Double, end: Double, probability: Double) {
        self.text = text; self.start = start; self.end = end; self.probability = probability
    }
}

public struct QuranWordEvidence: Codable, Equatable, Sendable {
    public let nativeID: Int
    public let verse: String
    public let takeID: UUID
    public let start: Double
    public let end: Double
    public let minimumConfidence: Double
}

public struct QuranRecitationTracker: Sendable {
    public let expected: [QuranAlignedWord]
    public private(set) var cursor = 0
    public private(set) var evidence: [QuranWordEvidence] = []
    /// Work count, not a confidence or an accuracy measurement.
    public private(set) var candidateComparisons = 0
    private let starts: [String: Set<Int>]
    public var revealedIDs: Set<Int> { Set(evidence.map(\.nativeID)) }
    public init(expected: [QuranAlignedWord]) {
        self.expected = expected; self.starts = Self.index(expected)
    }
    private static func index(_ words: [QuranAlignedWord]) -> [String: Set<Int>] {
        var result: [String: Set<Int>] = [:]
        for (index, word) in words.enumerated() {
            for form in word.aliases {
                if let first = form.first { result[first, default: []].insert(index) }
            }
        }
        return result
    }

    /// Reopen only evidence tied to this exact native corpus and scope. No
    /// inferred words are added when restoring a paused or interrupted session.
    public init(expected: [QuranAlignedWord], restoring evidence: [QuranWordEvidence]) throws {
        self.expected = expected; self.starts = Self.index(expected)
        let ids = Set(expected.map(\.id))
        guard ids.count == expected.count else { throw QuranAlignmentFailure.invalidEdition }
        let known = Dictionary(uniqueKeysWithValues: expected.map { ($0.id, $0.verse) })
        guard evidence.allSatisfy({ known[$0.nativeID] == $0.verse && $0.start.isFinite
            && $0.end.isFinite && $0.start >= 0 && $0.end > $0.start
            && $0.minimumConfidence.isFinite && (0.75...1).contains($0.minimumConfidence) }) else {
            throw QuranAlignmentFailure.invalidEvidence
        }
        self.evidence = evidence
        if let last = evidence.last, let index = expected.firstIndex(where: { $0.id == last.nativeID }) {
            cursor = index + 1
        }
    }

    /// Exact, local, multi-group anchoring. Ambiguous phrases wait for context.
    /// Replace the covered interpretation of one audio window before consuming
    /// its new accepted runs. Older source transcripts stay in the journal, but
    /// a retracted interpretation must not permanently reveal Quran words.
    public mutating func reconsiderAudio(takeID: UUID, start: Double, end: Double) throws {
        guard start.isFinite, end.isFinite, start >= 0, end > start else {
            throw QuranAlignmentFailure.invalidEvidence
        }
        evidence.removeAll { $0.takeID == takeID && $0.start >= start && $0.end <= end }
        // A retracted interpretation cannot remain a short-anchor location
        // prior. Rebuild the cursor from surviving source evidence only.
        if let last = evidence.last, let index = expected.firstIndex(where: { $0.id == last.nativeID }) {
            cursor = index + 1
        } else { cursor = 0 }
    }

    /// Exact, local, multi-group anchoring. Ambiguous phrases wait for context.
    /// A skipped/uncertain word is never inferred from a later match or elapsed
    /// time. A compound is revealed only when its complete spoken form matches.
    @discardableResult public mutating func consume(_ heard: [QuranHeardWord], takeID: UUID,
                                                   offset: Double = 0) throws -> [QuranWordEvidence] {
        guard !heard.isEmpty, heard.count <= 160, expected.count <= 77429,
              offset.isFinite, offset >= 0,
              heard.allSatisfy({ $0.start.isFinite && $0.end.isFinite && $0.start >= 0
                  && $0.end > $0.start && $0.probability.isFinite && (0.75...1).contains($0.probability)
                  && QuranAlignedWord.tokens([$0.text]).count == 1 }),
              zip(heard, heard.dropFirst()).allSatisfy({ $0.start <= $1.start }) else {
            throw QuranAlignmentFailure.invalidEvidence
        }
        guard !expected.isEmpty else { return [] }
        let tokens = heard.map { QuranAlignedWord.normalize($0.text) }
        struct Match { let first: Int; let bounds: [(Int, Int, Int)] }
        var candidates: [Match] = []
        let lower = max(0, cursor - 12), upper = min(expected.count, cursor + 13)
        let neighboringVerses = Set([cursor - 1, cursor].compactMap {
            expected.indices.contains($0) ? expected[$0].verse : nil
        })
        // A slow device or an intentional return can move outside the local
        // window. Reacquire only with a longer unique exact anchor; never reveal
        // the skipped interval or convert it into a confirmed reader mistake.
        candidateComparisons = 0
        // Index each actual starting token. The previous union then Cartesian
        // product compared every corpus occurrence against every heard offset,
        // even when their first tokens differed. Keep exactly the same matching
        // and ambiguity policy while avoiding that quadratic cross-product.
        for heardStart in tokens.indices {
            for first in (starts[tokens[heardStart]] ?? []).sorted() {
                candidateComparisons += 1
                var word = first, token = heardStart, bounds: [(Int, Int, Int)] = []
                while word < expected.count && token < tokens.count {
                    if token > heardStart && heard[token].start - heard[token - 1].end > 2 { break }
                    let forms = expected[word].aliases.filter { form in
                        token + form.count <= tokens.count
                            && Array(tokens[token..<(token + form.count)]) == form
                    }
                    // Two distinct boundaries that both fit need more context;
                    // do not choose one by an arbitrary iteration order.
                    guard forms.count == 1, let form = forms.first else { break }
                    let end = token + form.count
                    guard heard[end - 1].end - heard[token].start <= 12,
                          end - token == 1 || zip(heard[token..<end], heard[(token + 1)..<end])
                            .allSatisfy({ $1.start - $0.end <= 2 }) else { break }
                    bounds.append((word, token, end)); word += 1; token = end
                }
                // A complete one-group scope cannot supply a two-group anchor.
                // Require the entire authentic spoken form and stronger token
                // confidence; ordinary/multi-group scopes keep their anchors.
                let singleScope = expected.count == 1 && bounds.count == 1
                    && heard[bounds[0].1..<bounds[0].2].allSatisfy { $0.probability >= 0.95 }
                // A nearby different passage is not evidence of continuation.
                // After112:1, a partial "قل أعوذ" must not select113:1 merely
                // because it lies within12 words while114:1 is farther away.
                // Two-group context is allowed only inside the current verse
                // or the actual next pending verse; other locations still need
                // the full independent3-group/ambiguity-safe anchor.
                let nearbyContinuation = (lower..<upper).contains(first)
                    && neighboringVerses.contains(expected[first].verse)
                let minimumAnchor = singleScope ? 1 : nearbyContinuation ? 2 : 3
                if bounds.count >= minimumAnchor { candidates.append(.init(first: first, bounds: bounds)) }
            }
        }
        // Select non-overlapping exact anchors. Squared HEARD-token length
        // favors a stronger continuous phrase over several weaker fragments.
        // A shorter bridge (e.g. "أحد قل أعوذ برب" across112/113) must not
        // join two independent passages into one giant ambiguity component.
        // Retain only bindings shared by EVERY optimal interpretation. Never
        // break an equal-coverage ambiguity by corpus position or iteration order.
        let byStart = Dictionary(grouping: candidates) { $0.bounds[0].1 }
        func weight(_ match: Match) -> Int {
            let length = match.bounds.last!.2 - match.bounds[0].1
            return length * length
        }
        var prefix = Array(repeating: 0, count: heard.count + 1)
        var suffix = prefix
        for position in heard.indices {
            prefix[position + 1] = max(prefix[position + 1], prefix[position])
            for candidate in byStart[position] ?? [] {
                let end = candidate.bounds.last!.2
                prefix[end] = max(prefix[end], prefix[position] + weight(candidate))
            }
        }
        for position in heard.indices.reversed() {
            suffix[position] = suffix[position + 1]
            for candidate in byStart[position] ?? [] {
                let end = candidate.bounds.last!.2
                suffix[position] = max(suffix[position], weight(candidate) + suffix[end])
            }
        }
        struct Binding: Hashable { let index: Int; let first: Int; let end: Int }
        let score = suffix[0]
        var alternatives = Array(repeating: Set<Binding>(), count: heard.count)
        var canBeUnmatched = Array(repeating: false, count: heard.count)
        for position in heard.indices {
            canBeUnmatched[position] = prefix[position] + suffix[position + 1] == score
        }
        let optimal = candidates.filter {
            let first = $0.bounds[0].1, end = $0.bounds.last!.2
            return prefix[first] + weight($0) + suffix[end] == score
        }
        for candidate in optimal {
            for (index, first, end) in candidate.bounds {
                let binding = Binding(index: index, first: first, end: end)
                for position in first..<end { alternatives[position].insert(binding) }
            }
        }
        var certain = Set<Binding>()
        for candidate in optimal {
            let bindings = candidate.bounds.map { Binding(index: $0.0, first: $0.1, end: $0.2) }
            guard bindings.allSatisfy({ binding in
                (binding.first..<binding.end).allSatisfy {
                    !canBeUnmatched[$0] && alternatives[$0] == Set([binding])
                }
            }) else { continue }
            certain.formUnion(bindings)
        }
        var added: [QuranWordEvidence] = []
        for binding in certain.sorted(by: { $0.first < $1.first }) {
                let index = binding.index, first = binding.first, end = binding.end
                let record = QuranWordEvidence(nativeID: expected[index].id, verse: expected[index].verse,
                    takeID: takeID, start: offset + heard[first].start, end: offset + heard[end - 1].end,
                    minimumConfidence: heard[first..<end].map(\.probability).min()!)
                // Deduplicate only the same audio interval of the same take/word.
                // A later spoken repetition remains a separate recording event.
                let duplicate = evidence.contains { previous in
                    previous.nativeID == record.nativeID && previous.takeID == takeID
                        && min(previous.end, record.end) > max(previous.start, record.start)
                }
                if !duplicate { evidence.append(record); added.append(record) }
                cursor = index + 1
        }
        return added
    }
}
