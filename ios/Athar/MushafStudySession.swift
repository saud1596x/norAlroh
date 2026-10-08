import Foundation

/// Self-assessed Quran practice. These values are never an ASR or Tajweed grade.
struct MushafStudyAssistance: Codable, Equatable {
    var visibleWords = 0
    var revealAll = false
    var revealHints = 0
    var audioHints = 0
    var used: Bool { revealHints > 0 || audioHints > 0 }
    func valid() -> Bool {
        (0...100_000).contains(visibleWords) && (0...100_000).contains(revealHints)
            && (0...100_000).contains(audioHints)
            && (visibleWords == 0 || revealHints > 0) && (!revealAll || revealHints > 0)
    }
}

struct MushafStudyAnswer: Codable, Equatable {
    let key: String
    let assessment: String
    let assistance: MushafStudyAssistance
}

struct MushafStudySession: Codable, Equatable, Identifiable {
    enum Scope: String, Codable { case page, surah, range }
    enum Phase: String, Codable { case active, paused, finishing }
    let id: UUID
    let startedAt: Date
    let scope: Scope
    let keys: [String]
    let originPage: Int?
    // Assigned before any answer is saved. Retrying a finish after a crash uses
    // exactly the same result IDs, even when a page crosses surah boundaries.
    let resultIDs: [Int: UUID]
    var answers: [MushafStudyAnswer] = []
    var assistance = MushafStudyAssistance()
    var phase = Phase.active
    var finishedAt: Date?
    var currentKey: String? { answers.count < keys.count ? keys[answers.count] : nil }

    init(keys: [String], scope: Scope, page: Int? = nil, date: Date = Date()) {
        id = UUID(); startedAt = date; self.scope = scope; self.keys = keys; originPage = page
        let chapters = Set(keys.compactMap { Int($0.split(separator: ":").first ?? "") })
        resultIDs = Dictionary(uniqueKeysWithValues: chapters.map { ($0, UUID()) })
    }
    func valid(corpus: [Surah]) -> Bool {
        let canonical = corpus.flatMap { surah in surah.ayahs.map { "\(surah.number):\($0.number)" } }
        let positions = Dictionary(uniqueKeysWithValues: canonical.enumerated().map { ($0.element, $0.offset) })
        guard !keys.isEmpty, keys.count <= canonical.count, Set(keys).count == keys.count,
              startedAt.timeIntervalSince1970.isFinite, assistance.valid(),
              originPage.map({ (1...604).contains($0) }) ?? true,
              scope != .page || originPage != nil,
              answers.count <= keys.count else { return false }
        let indices = keys.compactMap { positions[$0] }
        guard indices.count == keys.count,
              zip(indices, indices.dropFirst()).allSatisfy({ $0.1 == $0.0 + 1 }) else { return false }
        let chapters = Set(keys.compactMap { Int($0.split(separator: ":").first ?? "") })
        guard Set(resultIDs.keys) == chapters, Set(resultIDs.values).count == resultIDs.count else { return false }
        guard answers.enumerated().allSatisfy({ index, answer in
            answer.key == keys[index] && ["remembered", "review", "skip"].contains(answer.assessment)
                && answer.assistance.valid()
        }) else { return false }
        if let finishedAt {
            guard phase == .finishing, finishedAt.timeIntervalSince1970.isFinite,
                  finishedAt >= startedAt else { return false }
        } else if phase == .finishing { return false }
        return true
    }
    mutating func reveal(wordCount: Int, all: Bool) -> Bool {
        guard phase == .active, currentKey != nil, wordCount > 0, wordCount <= 100_000,
              !assistance.revealAll, assistance.visibleWords < wordCount,
              assistance.revealHints < 100_000 else { return false }
        assistance.visibleWords = all ? wordCount : assistance.visibleWords + 1
        assistance.revealAll = all
        assistance.revealHints += 1
        return true
    }
    /// Call only after the player has actually begun the requested help verse.
    /// The caller consumes its playback request token before calling this method.
    mutating func recordAudioHelp(for key: String) -> Bool {
        guard phase == .active, currentKey == key, assistance.audioHints < 100_000 else { return false }
        assistance.audioHints += 1; return true
    }
    mutating func answer(_ assessment: String) -> Bool {
        guard phase == .active, let key = currentKey,
              ["remembered", "review", "skip"].contains(assessment) else { return false }
        answers.append(.init(key: key, assessment: assessment, assistance: assistance))
        assistance = .init(); return true
    }
    func results() -> [MemorizationResult]? {
        guard let date = finishedAt, phase == .finishing else { return nil }
        let grouped = Dictionary(grouping: answers) { Int($0.key.split(separator: ":")[0])! }
        return grouped.keys.sorted().compactMap { chapter in
            guard let id = resultIDs[chapter] else { return nil }
            let values = grouped[chapter]!.map { value in
                MemorizationAnswer(ayah: Int(value.key.split(separator: ":")[1])!,
                    assessment: value.assessment, revealed: value.assistance.revealHints > 0,
                    hints: value.assistance.revealHints + value.assistance.audioHints)
            }
            return MemorizationResult(id: id, date: date, chapter: chapter, answers: values)
        }
    }
}

struct MushafStudySummary: Codable, Equatable {
    let session: MushafStudySession
    var answered: Int { session.answers.filter { $0.assessment != "skip" }.count }
    var skipped: Int { session.answers.filter { $0.assessment == "skip" }.count }
    var helped: Int { session.answers.filter { $0.assistance.used }.count }
    var remembered: Int { session.answers.filter { $0.assessment == "remembered" }.count }
    var reviewKeys: [String] {
        session.answers.filter { $0.assessment != "skip" && ($0.assessment == "review" || $0.assistance.used) }.map(\.key)
    }
}

struct MushafRepeatPreferences: Codable, Equatable {
    var count = 3
    var delaySeconds = 0
    var valid: Bool { (1...20).contains(count) && (0...30).contains(delaySeconds) }
}

struct MushafStudyArchive: Codable, Equatable {
    var version = 1
    var pending: MushafStudySession?
    var summary: MushafStudySummary?
    var repetition: MushafRepeatPreferences?
    func valid(corpus: [Surah]) -> Bool {
        version == 1 && (repetition?.valid ?? true) && (pending?.valid(corpus: corpus) ?? true)
            && (summary.map { $0.session.phase == .finishing && $0.session.valid(corpus: corpus) } ?? true)
    }
}

/// Word masks use the validated edition's IDs and ordering, never text guesses.
struct MushafStudyWordIndex {
    let words: [String: [Int]]
    let pages: [String: [Int]]
    init(snapshot: QCFV2Snapshot, keys: [String]) {
        let records = snapshot.records.filter { $0.record_type == "mushaf_word" }
        let grouped = Dictionary(grouping: records) { keys[$0.verse_id! - 1] }
        words = grouped.mapValues { values in
            values.filter { $0.char_type_name == "word" }
                .sorted { $0.position_in_verse! < $1.position_in_verse! }.map(\.id)
        }
        pages = grouped.mapValues { Array(Set($0.compactMap(\.page_number))).sorted() }
    }
    func hiddenIDs(session: MushafStudySession) -> Set<Int> {
        var result = Set<Int>()
        for key in session.keys.dropFirst(session.answers.count) {
            let ids = words[key] ?? []
            let visible = key == session.currentKey ? session.assistance.visibleWords : 0
            result.formUnion(ids.dropFirst(visible))
        }
        return result
    }
}
