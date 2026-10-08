import SwiftUI

struct MemorizationPlan: Codable { var chapter = 1; var from = 1; var to = 7; var daily = 3 }
struct MemorizationAnswer: Codable, Equatable { let ayah: Int; let assessment: String; let revealed: Bool; let hints: Int }
struct MemorizationResult: Codable, Identifiable, Equatable {
    var id = UUID(); var date = Date(); let chapter: Int; let answers: [MemorizationAnswer]
}
struct MemorizationSession: Codable {
    var chapter: Int
    var keys: [Int]
    var answers: [MemorizationAnswer] = []
    var hintWords = 0
    var hintCount = 0
    var revealed = false
}
struct MemorizationPracticeSession: Codable {
    var chapter: Int
    var from: Int
    var to: Int
    var ayah: Int
    var visibleWords = 0
    var hints = 0
    var revealAll = false
    var usedHelp = false
    func valid(corpus: [Surah]) -> Bool {
        corpus.indices.contains(chapter - 1) && from > 0 && to >= from
            && to <= corpus[chapter - 1].ayahs.count && (from...to).contains(ayah)
            && (0...1024).contains(visibleWords) && (0...100000).contains(hints)
            && (!revealAll || usedHelp) && (visibleWords == 0 || usedHelp)
    }
}

struct VerseReviewState: Codable {
    var stage = 0
    var attempts = 0
    var lapses = 0
    var lastPracticed = Date.distantPast
    var nextReview = Date.distantPast
    var needsHelp = true
    mutating func record(_ answer: MemorizationAnswer, at date: Date, calendar: Calendar = .current) {
        guard answer.assessment != "skip" else { return }
        let independent = answer.assessment == "remembered" && !answer.revealed && answer.hints == 0
        if independent {
            if !calendar.isDate(lastPracticed, inSameDayAs: date) { stage = min(6, stage + 1) }
        } else {
            stage = 0; lapses += 1
        }
        attempts += 1; needsHelp = !independent; lastPracticed = date
        let days = [1, 1, 3, 7, 14, 30, 60][stage]
        nextReview = calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: date)) ?? date
    }
}
struct MemorizationProgress: Codable {
    var version = 1
    var verses: [String: VerseReviewState] = [:]
    var practiceDays: [String: Set<String>] = [:]
    var confirmedMistakes: [ConfirmedRecitationMistake] = []
    // Durable exclusions prevent stale backups/devices from restoring ASR notes.
    var excludedMistakeIDs = Set<UUID>()
    private enum CodingKeys: String, CodingKey { case version, verses, practiceDays, confirmedMistakes, excludedMistakeIDs }
    init() {}
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decode(Int.self, forKey: .version)
        verses = try values.decode([String: VerseReviewState].self, forKey: .verses)
        practiceDays = try values.decode([String: Set<String>].self, forKey: .practiceDays)
        confirmedMistakes = try values.decode([ConfirmedRecitationMistake].self, forKey: .confirmedMistakes)
        excludedMistakeIDs = try values.decodeIfPresent(Set<UUID>.self, forKey: .excludedMistakeIDs) ?? []
    }
    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(version, forKey: .version)
        try values.encode(verses, forKey: .verses)
        try values.encode(practiceDays.mapValues { $0.sorted() }, forKey: .practiceDays)
        try values.encode(confirmedMistakes, forKey: .confirmedMistakes)
        if !excludedMistakeIDs.isEmpty {
            try values.encode(excludedMistakeIDs.sorted { $0.uuidString < $1.uuidString }, forKey: .excludedMistakeIDs)
        }
    }
    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }
    mutating func record(_ result: MemorizationResult, calendar: Calendar = .current) {
        let day = Self.dayKey(result.date, calendar: calendar)
        for answer in result.answers where answer.assessment != "skip" {
            let key = "\(result.chapter):\(answer.ayah)"
            var state = verses[key] ?? VerseReviewState()
            state.record(answer, at: result.date, calendar: calendar); verses[key] = state
            practiceDays[day, default: []].insert(key)
        }
    }
    func valid(corpus: [Surah]) -> Bool {
        func validKey(_ key: String) -> Bool {
            let parts = key.split(separator: ":").compactMap { Int($0) }
            return parts.count == 2 && corpus.indices.contains(parts[0] - 1) && (1...corpus[parts[0] - 1].ayahs.count).contains(parts[1]) && key == "\(parts[0]):\(parts[1])"
        }
        return version == 1 && verses.allSatisfy { key, value in
            validKey(key) && (0...6).contains(value.stage) && value.attempts >= 0 && value.lapses >= 0
                && value.lastPracticed.timeIntervalSince1970.isFinite && value.nextReview.timeIntervalSince1970.isFinite
        } && practiceDays.values.allSatisfy { $0.allSatisfy(validKey) }
            && confirmedMistakes.allSatisfy { !excludedMistakeIDs.contains($0.id) && validKey("\($0.chapter):\($0.ayah)") && !$0.expected.isEmpty && $0.date.timeIntervalSince1970.isFinite }
    }
}
struct ConfirmedRecitationMistake: Codable, Identifiable {
    var id = UUID()
    var date = Date()
    let chapter: Int
    let ayah: Int
    let expected: String
    let heard: String?
}
struct MemorizationArchive: Codable {
    let version: Int
    let history: [MemorizationResult]
    let progress: MemorizationProgress
    var plan: MemorizationPlan? = nil
}
@MainActor final class MemorizationStore: ObservableObject {
    @Published private(set) var plan = MemorizationPlan()
    @Published private(set) var history: [MemorizationResult] = []
    @Published private(set) var session: MemorizationSession?
    @Published private(set) var practice: MemorizationPracticeSession?
    private(set) var unreadablePractice: Data?
    @Published var error: String?
    @Published private(set) var unreadableHistory: Data?
    @Published private(set) var progress = MemorizationProgress()
    @Published private(set) var mushafStudy = MushafStudyArchive()
    private(set) var unreadableMushafStudy: Data?
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Preserve exact pre-upgrade bytes before any archive rewrite. Never
        // rotate this snapshot implicitly; explicit erasure removes it too.
        if defaults.object(forKey: "noor.memorization.preRetentionFix") == nil {
            var original: [String: Data] = [:]
            for key in ["history", "archive", "plan", "session"] {
                if let bytes = defaults.data(forKey: "noor.memorization." + key) { original[key] = bytes }
            }
            defaults.set(original, forKey: "noor.memorization.preRetentionFix")
        }
        if let data = defaults.data(forKey: "noor.memorization.plan"), let value = try? JSONDecoder().decode(MemorizationPlan.self, from: data),
            (1...114).contains(value.chapter), value.from > 0, value.to >= value.from,
            let corpus = QuranResources.corpus, value.to <= corpus[value.chapter - 1].ayahs.count,
            (1...50).contains(value.daily) { plan = value }
        if let data = defaults.data(forKey: "noor.memorization.history") {
            if let value = try? JSONDecoder().decode([MemorizationResult].self, from: data),
               let corpus = QuranResources.corpus, value.allSatisfy({ Self.valid($0, corpus: corpus) }),
               Set(value.map(\.id)).count == value.count { history = value }
            else { unreadableHistory = data; error = "تعذّر قراءة سجل الحفظ السابق. صدّر بياناتك لإنقاذ نسخة أو احذفها من الإعدادات قبل تسجيل نتائج جديدة." }
        }
        if let data = defaults.data(forKey: "noor.memorization.archive") {
            if let value = try? JSONDecoder().decode(MemorizationArchive.self, from: data), value.version == 1,
               let corpus = QuranResources.corpus, value.progress.valid(corpus: corpus),
               value.history.allSatisfy({ Self.valid($0, corpus: corpus) }), Set(value.history.map(\.id)).count == value.history.count {
                history = value.history; progress = value.progress; unreadableHistory = nil; error = nil
                if let restoredPlan = value.plan, Self.validPlan(restoredPlan, corpus: corpus) { plan = restoredPlan }
            } else {
                unreadableHistory = data; error = "تعذّر فتح سجل الإتقان. بياناتك محفوظة؛ صدّرها قبل بدء جلسات جديدة."
            }
        } else {
            for result in history.sorted(by: { $0.date < $1.date }) { progress.record(result) }
        }
        if let data = defaults.data(forKey: "noor.memorization.session"),
           let value = try? JSONDecoder().decode(MemorizationSession.self, from: data),
           let corpus = QuranResources.corpus, validSession(value, corpus: corpus) { session = value }
        if let data = defaults.data(forKey: "noor.memorization.practice") {
            if let value = try? JSONDecoder().decode(MemorizationPracticeSession.self, from: data),
               let corpus = QuranResources.corpus, value.valid(corpus: corpus) { practice = value }
            else { unreadablePractice = data }
        }
        if let data = defaults.data(forKey: "noor.mushaf.study") {
            if let value = try? JSONDecoder().decode(MushafStudyArchive.self, from: data),
               let corpus = QuranResources.corpus, value.valid(corpus: corpus) { mushafStudy = value }
            else { unreadableMushafStudy = data }
        }
    }
    @discardableResult func savePractice(_ value: MemorizationPracticeSession) -> Bool {
        guard unreadablePractice == nil, let corpus = QuranResources.corpus, value.valid(corpus: corpus) else {
            error = "تعذّر حفظ التدريب. احتُفظ ببيانات الجلسة السابقة؛ يمكنك تصدير بياناتك من الإعدادات."; return false
        }
        do {
            defaults.set(try JSONEncoder().encode(value), forKey: "noor.memorization.practice")
            practice = value; return true
        } catch { self.error = "تعذّر حفظ موضع التدريب."; return false }
    }
    private func validSession(_ value: MemorizationSession, corpus: [Surah]) -> Bool {
        guard corpus.indices.contains(value.chapter - 1), !value.keys.isEmpty, value.keys.count <= 50,
              Set(value.keys).count == value.keys.count, value.answers.count < value.keys.count,
              value.hintWords >= 0, value.hintCount >= 0 else { return false }
        let count = corpus[value.chapter - 1].ayahs.count
        guard value.keys.allSatisfy({ (1...count).contains($0) }),
              value.answers.map(\.ayah) == Array(value.keys.prefix(value.answers.count)) else { return false }
        return value.answers.isEmpty || Self.valid(.init(chapter: value.chapter, answers: value.answers), corpus: corpus)
    }
    @discardableResult func saveSession(_ value: MemorizationSession) -> Bool {
        guard let corpus = QuranResources.corpus, validSession(value, corpus: corpus) else { return false }
        do {
            defaults.set(try JSONEncoder().encode(value), forKey: "noor.memorization.session")
            session = value; return true
        } catch { self.error = "تعذّر حفظ الجلسة. حاول مجددًا."; return false }
    }
    func clearSession() {
        defaults.removeObject(forKey: "noor.memorization.session"); session = nil
    }
    func reviewKeys(corpus: [Surah]) -> [Int] {
        guard corpus.indices.contains(plan.chapter - 1) else { return [] }
        let upper = min(plan.to, corpus[plan.chapter - 1].ayahs.count)
        guard plan.from > 0, plan.from <= upper else { return [] }
        // Weak verses first, then overdue recall, unseen verses and future reviews.
        var latest: [Int: MemorizationAnswer] = [:]
        for result in history where result.chapter == plan.chapter {
            for answer in result.answers where latest[answer.ayah] == nil { latest[answer.ayah] = answer }
        }
        let states = progress.verses
        let chapter = plan.chapter
        let today = Calendar.current.startOfDay(for: Date())
        let keys = Array(plan.from...upper).shuffled().sorted { a, b in
            func priority(_ key: Int) -> Int {
                if states["\(chapter):\(key)"]?.needsHelp == true { return 0 }
                if let answer = latest[key], answer.assessment != "remembered" || answer.revealed || answer.hints > 0 { return 0 }
                guard let state = states["\(chapter):\(key)"] else { return 2 }
                return state.nextReview <= today ? 1 : 3
            }
            return priority(a) < priority(b)
        }
        return Array(keys.prefix(plan.daily))
    }
    var dailyTarget: Int { min(plan.daily, max(0, plan.to - plan.from + 1)) }
    func completedToday(at date: Date = Date(), calendar: Calendar = .current) -> Int {
        let keys = progress.practiceDays[MemorizationProgress.dayKey(date, calendar: calendar)] ?? []
        return keys.filter { key in
            let parts = key.split(separator: ":").compactMap { Int($0) }
            return parts.count == 2 && parts[0] == plan.chapter && (plan.from...plan.to).contains(parts[1])
        }.count
    }
    func wardComplete(at date: Date = Date()) -> Bool { dailyTarget > 0 && completedToday(at: date) >= dailyTarget }
    var masteredCount: Int { progress.verses.values.filter { $0.stage >= 3 && !$0.needsHelp }.count }
    @discardableResult func confirmMistake(chapter: Int, ayah: Int, expected: String, heard: String?) -> Bool {
        guard unreadableHistory == nil, let corpus = QuranResources.corpus, corpus.indices.contains(chapter - 1),
              (1...corpus[chapter - 1].ayahs.count).contains(ayah),
              corpus[chapter - 1].ayahs[ayah - 1].text.split(whereSeparator: \.isWhitespace).contains(Substring(expected)) else { return false }
        var next = progress
        next.confirmedMistakes.insert(.init(chapter: chapter, ayah: ayah, expected: expected, heard: heard), at: 0)
        let key = "\(chapter):\(ayah)"
        var state = next.verses[key] ?? VerseReviewState()
        state.needsHelp = true; state.stage = 0; state.nextReview = Calendar.current.startOfDay(for: Date()); next.verses[key] = state
        do {
            let data = try JSONEncoder().encode(MemorizationArchive(version: 1, history: history, progress: next, plan: plan))
            defaults.set(data, forKey: "noor.memorization.archive"); progress = next; return true
        } catch { self.error = "تعذّر حفظ موضع المراجعة."; return false }
    }
    @discardableResult func excludeMistake(_ id: UUID) -> Bool {
        guard unreadableHistory == nil, progress.confirmedMistakes.contains(where: { $0.id == id }) else { return false }
        var next = progress
        next.confirmedMistakes.removeAll { $0.id == id }; next.excludedMistakeIDs.insert(id)
        do {
            let archive = try JSONEncoder().encode(MemorizationArchive(version: 1, history: history, progress: next, plan: plan))
            defaults.set(archive, forKey: "noor.memorization.archive"); progress = next; return true
        } catch { self.error = "تعذر استبعاد الملاحظة. أعد المحاولة."; return false }
    }
    func dueKeys(at date: Date = Date()) -> [Int] {
        (plan.from...plan.to).filter { (progress.verses["\(plan.chapter):\($0)"]?.nextReview ?? .distantFuture) <= Calendar.current.startOfDay(for: date) }
    }
    func streak(at date: Date = Date(), calendar: Calendar = .current) -> Int {
        var day = calendar.startOfDay(for: date)
        if progress.practiceDays[MemorizationProgress.dayKey(day, calendar: calendar)]?.isEmpty != false {
            day = calendar.date(byAdding: .day, value: -1, to: day) ?? day
        }
        var count = 0
        while progress.practiceDays[MemorizationProgress.dayKey(day, calendar: calendar)]?.isEmpty == false && count < 36500 {
            count += 1; guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }; day = previous
        }
        return count
    }
    private static func valid(_ result: MemorizationResult, corpus: [Surah]) -> Bool {
        guard corpus.indices.contains(result.chapter - 1), !result.answers.isEmpty,
              result.date.timeIntervalSince1970.isFinite,
              Set(result.answers.map(\.ayah)).count == result.answers.count else { return false }
        return result.answers.allSatisfy { (1...corpus[result.chapter - 1].ayahs.count).contains($0.ayah)
            && ["remembered", "review", "skip"].contains($0.assessment) && $0.hints >= 0 }
    }
    func configure(_ candidate: MemorizationPlan, corpus: [Surah]) -> Bool {
        guard corpus.indices.contains(candidate.chapter - 1), candidate.from > 0, candidate.to >= candidate.from,
              candidate.to <= corpus[candidate.chapter - 1].ayahs.count, (1...50).contains(candidate.daily) else { return false }
        do {
            let data = try JSONEncoder().encode(candidate)
            let archive = try JSONEncoder().encode(MemorizationArchive(version: 1, history: history, progress: progress, plan: candidate))
            defaults.set(data, forKey: "noor.memorization.plan")
            if unreadableHistory == nil { defaults.set(archive, forKey: "noor.memorization.archive") }
            plan = candidate; clearSession(); return true
        }
        catch { self.error = "تعذر حفظ خطة المراجعة."; return false }
    }
    private static func validPlan(_ plan: MemorizationPlan, corpus: [Surah]) -> Bool {
        corpus.indices.contains(plan.chapter - 1) && plan.from > 0 && plan.to >= plan.from
            && plan.to <= corpus[plan.chapter - 1].ayahs.count && (1...50).contains(plan.daily)
    }
    @discardableResult func restore(_ backup: MemorizationCloudBackup) -> Bool {
        guard unreadableHistory == nil, backup.version == 1, backup.archive.version == 1,
              let corpus = QuranResources.corpus, Self.validPlan(backup.plan, corpus: corpus),
              backup.archive.progress.verses.count <= 6236,
              backup.archive.progress.valid(corpus: corpus),
              backup.archive.history.allSatisfy({ Self.valid($0, corpus: corpus) }),
              Set(backup.archive.history.map(\.id)).count == backup.archive.history.count else {
            error = "لا يمكن استبدال تقدمك بنسخة غير صالحة. صدّر بياناتك المحلية إن تعذّر فتحها."; return false
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        do {
            let local = MemorizationCloudBackup(version: 1, plan: plan,
                archive: MemorizationArchive(version: 1, history: history, progress: progress, plan: plan))
            let merged = try MemorizationCloudMerge.merge(local: local, remote: backup, corpus: corpus)
            let combined = merged.archive.history
            var restored = merged.archive.progress
            // Importing remote progress does not complete today's ward. Preserve
            // practice actually completed here, rather than clearing it on restore.
            let today = MemorizationProgress.dayKey(Date())
            restored.practiceDays[today] = progress.practiceDays[today]
            let selectedPlan = history.isEmpty && session == nil && practice == nil && mushafStudy.pending == nil && unreadableMushafStudy == nil ? backup.plan : plan
            guard restored.valid(corpus: corpus) else { throw CocoaError(.fileReadCorruptFile) }
            let archive = try encoder.encode(MemorizationArchive(version: 1, history: combined, progress: restored, plan: selectedPlan))
            let savedPlan = try encoder.encode(selectedPlan)
            // One durable pre-merge snapshot, also included in user data export.
            if defaults.object(forKey: "noor.memorization.preCloudMerge") == nil {
                var original: [String: Data] = [:]
                for key in ["archive", "history", "plan", "session", "practice"] {
                    if let bytes = defaults.data(forKey: "noor.memorization." + key) { original[key] = bytes }
                }
                defaults.set(original, forKey: "noor.memorization.preCloudMerge")
            }
            defaults.set(archive, forKey: "noor.memorization.archive")
            defaults.set(savedPlan, forKey: "noor.memorization.plan")
            if plan.chapter != selectedPlan.chapter || plan.from != selectedPlan.from || plan.to != selectedPlan.to || plan.daily != selectedPlan.daily {
                plan = selectedPlan
            }
            history = combined; progress = restored; error = nil
            NoorFocusController.shared.sync(progress: progress)
            return true
        } catch { self.error = "تعذّرت استعادة نسخة الحفظ؛ بقيت بياناتك المحلية محفوظة."; return false }
    }
    var preCloudMerge: [String: Data]? { defaults.dictionary(forKey: "noor.memorization.preCloudMerge") as? [String: Data] }
    @discardableResult func finish(chapter: Int, answers: [MemorizationAnswer]) -> Bool {
        guard unreadableHistory == nil else { error = "لم تُحفظ النتيجة كي لا يُستبدل سجل سابق تعذّر فتحه. صدّر بياناتك من الإعدادات."; return false }
        let result = MemorizationResult(chapter: chapter, answers: answers)
        guard let corpus = QuranResources.corpus, Self.valid(result, corpus: corpus) else { error = "راجع آيات نتيجة المراجعة."; return false }
        let next = [result] + history
        var nextProgress = progress; nextProgress.record(result)
        do {
            let data = try JSONEncoder().encode(MemorizationArchive(version: 1, history: next, progress: nextProgress, plan: plan))
            defaults.set(data, forKey: "noor.memorization.archive")
            history = next; progress = nextProgress; clearSession()
            NoorFocusController.shared.sync(progress: progress); return true
        }
        catch { self.error = "تعذر حفظ نتيجة المراجعة."; return false }
    }
    @discardableResult func saveMushafStudy(_ value: MushafStudyArchive) -> Bool {
        guard unreadableMushafStudy == nil, let corpus = QuranResources.corpus,
              value.valid(corpus: corpus) else {
            error = "تعذّر حفظ جلسة المصحف. بيانات الجلسة السابقة محفوظة؛ صدّرها من الإعدادات."; return false
        }
        do {
            defaults.set(try JSONEncoder().encode(value), forKey: "noor.mushaf.study")
            mushafStudy = value; return true
        } catch { self.error = "تعذّر حفظ جلسة التسميع."; return false }
    }
    @discardableResult func startMushafStudy(keys: [String], scope: MushafStudySession.Scope, page: Int? = nil) -> Bool {
        guard mushafStudy.pending == nil, unreadableHistory == nil else { return false }
        var next = mushafStudy; next.pending = MushafStudySession(keys: keys, scope: scope, page: page)
        return saveMushafStudy(next)
    }
    @discardableResult func updateMushafStudy(_ change: (inout MushafStudySession) -> Bool) -> Bool {
        guard var pending = mushafStudy.pending, change(&pending) else { return false }
        var next = mushafStudy; next.pending = pending; return saveMushafStudy(next)
    }
    @discardableResult func finishMushafStudy(at date: Date = Date()) -> Bool {
        guard unreadableHistory == nil, let corpus = QuranResources.corpus,
              var pending = mushafStudy.pending, pending.valid(corpus: corpus) else { return false }
        if pending.finishedAt == nil {
            pending.finishedAt = max(date, pending.startedAt); pending.phase = .finishing
            var next = mushafStudy; next.pending = pending
            guard saveMushafStudy(next) else { return false }
        }
        guard let results = pending.results(), results.allSatisfy({ Self.valid($0, corpus: corpus) }) else { return false }
        var nextHistory = history; var nextProgress = progress
        for result in results {
            if let prior = nextHistory.first(where: { $0.id == result.id }) {
                guard prior == result else {
                    error = "تعذّر إنهاء الجلسة بسبب تعارض في سجل سابق. بياناتك محفوظة."; return false
                }
            } else { nextHistory.insert(result, at: 0); nextProgress.record(result) }
        }
        do {
            // One archive write publishes all surah results and progress together.
            // If interrupted before clearing the session, identical IDs make the
            // next finish a retry, not another practice attempt.
            let archive = MemorizationArchive(version: 1, history: nextHistory, progress: nextProgress, plan: plan)
            defaults.set(try JSONEncoder().encode(archive), forKey: "noor.memorization.archive")
            history = nextHistory; progress = nextProgress
            var next = mushafStudy; next.pending = nil; next.summary = .init(session: pending)
            guard saveMushafStudy(next) else { return false }
            NoorFocusController.shared.sync(progress: progress); return true
        } catch { self.error = "تعذّر حفظ نتيجة جلسة المصحف. يمكنك إعادة محاولة إنهائها."; return false }
    }
    @discardableResult func applySyncedPlan(_ candidate: MemorizationPlan) -> Bool {
        guard session == nil, practice == nil, mushafStudy.pending == nil, unreadableMushafStudy == nil, unreadableHistory == nil, let corpus = QuranResources.corpus,
              Self.validPlan(candidate, corpus: corpus) else { return false }
        if plan.chapter == candidate.chapter && plan.from == candidate.from && plan.to == candidate.to && plan.daily == candidate.daily { return true }
        do {
            let archive = try JSONEncoder().encode(MemorizationArchive(version: 1, history: history, progress: progress, plan: candidate))
            let bytes = try JSONEncoder().encode(candidate)
            defaults.set(archive, forKey: "noor.memorization.archive")
            defaults.set(bytes, forKey: "noor.memorization.plan")
            plan = candidate; return true
        } catch { self.error = "تعذر حفظ الخطة المتزامنة. بقيت خطتك المحلية."; return false }
    }
    func erase() {
        NoorFocusController.shared.disable()
        defaults.removeObject(forKey: "noor.memorization.history"); defaults.removeObject(forKey: "noor.memorization.plan")
        defaults.removeObject(forKey: "noor.memorization.archive")
        defaults.removeObject(forKey: "noor.memorization.preRetentionFix")
        defaults.removeObject(forKey: "noor.memorization.preCloudMerge")
        defaults.removeObject(forKey: "noor.memorization.practice")
        defaults.removeObject(forKey: "noor.mushaf.study")
        mushafStudy = .init(); unreadableMushafStudy = nil
        practice = nil; unreadablePractice = nil
        clearSession(); history = []; progress = MemorizationProgress(); plan = MemorizationPlan(); unreadableHistory = nil; error = nil
    }
}
struct MemorizationView: View {
    @EnvironmentObject private var store: AtharStore
    @EnvironmentObject private var memorization: MemorizationStore
    private var surah: Surah? { store.quran.first { $0.number == memorization.plan.chapter } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(surah?.name ?? "خطة الحفظ").font(.largeTitle.bold())
                        Text("الآيات \(memorization.plan.from)–\(memorization.plan.to)").foregroundStyle(.secondary)
                    }
                    Spacer()
                    NavigationLink { MemorizationPlanView() } label: { Label("تعديل الخطة", systemImage: "slider.horizontal.3").font(.caption).frame(minHeight: 44) }
                        .accessibilityIdentifier("hifz.plan")
                }
                NoorDailyWardCard()
                Text("اختر خطوتك").font(.title3.bold())
                NavigationLink { MemorizationPracticeView() } label: {
                    action("احفظ آية جديدة", detail: "اقرأ الآية، أخفها، ثم اكشف كلماتها بالتدرج", icon: "book.closed", number: "١")
                }.accessibilityIdentifier("hifz.practice")
                NavigationLink { SpeechRecitationView() } label: {
                    action("سمّع داخل المصحف", detail: "اختر مقطعك، وأخفِ الآيات وسجّل صوتك اختياريًا", icon: "mic", number: "٢")
                }.accessibilityIdentifier("hifz.speech")
                NavigationLink { MemorizationTestView() } label: {
                    action(memorization.session == nil ? "راجع ورد اليوم" : "أكمل جلستك", detail: "تثبيت الآيات الضعيفة والمراجعات المستحقة", icon: "brain.head.profile", number: "٣")
                }.accessibilityIdentifier("hifz.test")
                Card {
                    HStack {
                        stat(memorization.masteredCount, "آيات متقنة")
                        Spacer()
                        stat(memorization.dueKeys().count, "مستحقة للمراجعة")
                        Spacer()
                        stat(memorization.streak(), "أيام متتابعة")
                    }
                    NavigationLink("خريطة الإتقان") { MemorizationInsightsView() }.accessibilityIdentifier("hifz.insights")
                    NavigationLink("سجل المراجعة") { MemorizationHistoryView() }.accessibilityIdentifier("hifz.history")
                    NavigationLink("الآيات المتشابهة") { LexicalSimilaritiesView() }.accessibilityIdentifier("hifz.similarities")
                    NavigationLink("حماية وقت الورد") { NoorFocusView() }.accessibilityIdentifier("hifz.focus")
                }
            }.padding(20)
        }.background(Theme.background).navigationTitle("الحفظ")
    }
    private func stat(_ count: Int, _ title: String) -> some View {
        VStack(alignment: .leading, spacing: 5) { Text("\(count)").font(.title2.bold()); Text(title).font(.caption).foregroundStyle(.secondary) }
    }
    private func action(_ title: String, detail: String, icon: String, number: String) -> some View {
        HStack(spacing: 15) {
            Image(systemName: icon).font(.title2).frame(width: 48, height: 54).foregroundStyle(Theme.gold)
            VStack(alignment: .leading, spacing: 7) { Text(title).font(.headline); Text(detail).font(.caption).foregroundStyle(.secondary) }
            Spacer(minLength: 0)
            Text(number).font(.title3.bold()).foregroundStyle(Theme.gold)
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading).foregroundStyle(.primary)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 22))
    }
}
struct MemorizationPracticeView: View {
    @EnvironmentObject private var store: AtharStore
    @EnvironmentObject private var memorization: MemorizationStore
    @StateObject private var audio = MushafVerseAudio()
    @State private var current: MemorizationPracticeSession?
    @State private var wordCount = 0
    @State private var saved = false
    private var chapter: Surah? { store.quran.first { $0.number == memorization.plan.chapter } }
    var body: some View {
        VStack(spacing: 8) {
            if let current {
                HStack {
                    Button("السابقة") { move(-1) }.disabled(current.ayah <= current.from)
                    Spacer()
                    Text("الآية \(ArabicSearch.digits(current.ayah))").font(.headline)
                    Spacer()
                    Button("التالية") { move(1) }.disabled(current.ayah >= current.to)
                }.frame(minHeight: 44).padding(.horizontal, 16)
                MushafTrainingPage(chapter: current.chapter, ayah: current.ayah,
                    revealedWords: current.visibleWords, revealAll: current.revealAll,
                    onHint: revealNext, onWordCount: { wordCount = $0 })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                HStack {
                    Button("كشف جزء") { revealNext() }.disabled(current.revealAll || current.visibleWords >= wordCount || wordCount == 0)
                        .accessibilityIdentifier("hifz.revealPart")
                    Spacer()
                    Button(current.revealAll ? "إخفاء النص" : "كشف الآية") {
                        change { value in
                            value.revealAll.toggle(); value.visibleWords = 0
                            if value.revealAll { value.usedHelp = true; value.hints += 1 }
                        }
                    }.accessibilityIdentifier("hifz.revealAll")
                    Spacer()
                    Button(audio.playing != nil || audio.loadingKey != nil ? "إيقاف" : "استمع") {
                        if audio.playing != nil || audio.loadingKey != nil { audio.stop() }
                        else { change { $0.usedHelp = true; $0.hints += 1 }; audio.play(["\(current.chapter):\(current.ayah)"]) }
                    }.accessibilityIdentifier("hifz.listen")
                }.frame(minHeight: 44).padding(.horizontal, 16)
                HStack {
                    Button(saved ? "حُفظ تقييمك" : "تذكّرتها") { record("remembered") }.disabled(saved)
                    Spacer()
                    Button("تحتاج تثبيتًا") { record("review") }.disabled(saved)
                }.frame(minHeight: 44).padding(.horizontal, 16)
                Text(current.usedHelp ? "استُخدمت مساعدة؛ يُسجّل التدريب كمراجعة مع مساعدة." : "قيّم استرجاعك بعد المقارنة. فتح الصفحة وحده لا يُكمل الورد.")
                    .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 16).padding(.bottom, 6)
            } else { ProgressView("استعادة موضع التدريب…") }
        }.background(Theme.panel).navigationTitle("تثبيت الآيات")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                let plan = memorization.plan
                if let saved = memorization.practice, saved.chapter == plan.chapter, saved.from == plan.from, saved.to == plan.to { current = saved }
                else {
                    let value = MemorizationPracticeSession(chapter: plan.chapter, from: plan.from, to: plan.to, ayah: plan.from)
                    current = value; _ = memorization.savePractice(value)
                }
            }
            .onDisappear { audio.stop() }
            .alert("التدريب", isPresented: Binding(get: { audio.error != nil || memorization.error != nil }, set: { if !$0 { audio.error = nil; memorization.error = nil } })) {
                Button("حسنًا") { audio.error = nil; memorization.error = nil }
            } message: { Text(audio.error ?? memorization.error ?? "") }
    }
    private func change(_ edit: (inout MemorizationPracticeSession) -> Void) {
        guard var value = current else { return }
        edit(&value)
        if memorization.savePractice(value) { current = value }
    }
    private func revealNext() {
        guard let current, !current.revealAll, current.visibleWords < wordCount else { return }
        change { $0.visibleWords += 1; $0.hints += 1; $0.usedHelp = true }
    }
    private func move(_ delta: Int) {
        guard let current, (current.from...current.to).contains(current.ayah + delta) else { return }
        audio.stop(); saved = false; wordCount = 0
        change { $0.ayah += delta; $0.visibleWords = 0; $0.hints = 0; $0.revealAll = false; $0.usedHelp = false }
    }
    private func record(_ assessment: String) {
        guard let current else { return }
        if memorization.finish(chapter: current.chapter, answers: [.init(ayah: current.ayah, assessment: assessment, revealed: current.usedHelp, hints: current.hints)]) { saved = true }
    }
}
struct NoorDailyWardCard: View {
    @EnvironmentObject private var memorization: MemorizationStore
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let completed = memorization.completedToday(at: context.date)
            let target = memorization.dailyTarget
            Card {
                HStack {
                    Label("وردك اليوم", systemImage: "sun.max").font(.headline)
                    Spacer()
                    Text("\(min(completed, target)) / \(target)").font(.headline.monospacedDigit())
                }
                NoorProgressBar(value: Double(completed) / Double(max(1, target)), label: "إنجاز ورد اليوم")
                Text(completed >= target && target > 0 ? "أتممت ورد اليوم. يمكنك مراجعة المزيد." : "\(max(0, target - completed)) آيات متبقية من خطتك.")
                    .font(.subheadline).accessibilityIdentifier("hifz.dailyStatus")
                Text("نحسب الآيات المختلفة التي راجعتها في جلسة محفوظة. التكرار والتجاوز لا يزيدان إنجاز اليوم؛ الإتقان يحتاج استرجاعًا مستقلًا في أيام مختلفة.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct MemorizationInsightsView: View {
    @State private var visibleMistakes = 50
    @EnvironmentObject private var memorization: MemorizationStore
    @EnvironmentObject private var store: AtharStore
    private var range: [Int] { Array(memorization.plan.from...memorization.plan.to) }
    private var chapter: Surah? { store.quran.first { $0.number == memorization.plan.chapter } }
    var body: some View {
        List {
            Section {
                Text(chapter?.name ?? "خطة الحفظ").font(.title2.bold())
                Text("نراجع الاسترجاع الناجح بعد يوم، ثم ٣ و٧ و١٤ و٣٠ و٦٠ يومًا. أي مساعدة تعيد الآية إلى المراجعة القريبة.")
                Text("الإتقان هنا مبني على تقييمك الذاتي؛ لا يُعد شهادة في صحة التلاوة أو التجويد.").font(.caption).foregroundStyle(.secondary)
            }
            Section("مواضع أكدت أنها تحتاج مراجعة") {
                let mistakes = memorization.progress.confirmedMistakes.filter { $0.chapter == memorization.plan.chapter }
                if mistakes.isEmpty { Text("يمكنك إضافة موضع من المقارنة الصوتية بعد التأكد منه بنفسك.").foregroundStyle(.secondary) }
                ForEach(Array(mistakes.prefix(visibleMistakes))) { mistake in
                    NavigationLink { MushafReader(chapter: mistake.chapter, ayah: mistake.ayah) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("الآية \(mistake.ayah)").font(.caption)
                            QuranVerseText(mistake.expected, size: 24)
                            Text("المتعرّف عليه: \(mistake.heard ?? "لم تظهر الكلمة")").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions { Button("استبعاد الملاحظة", role: .destructive) { _ = memorization.excludeMistake(mistake.id) } }
                    .accessibilityAction(named: Text("استبعاد الملاحظة")) { _ = memorization.excludeMistake(mistake.id) }
                }
                if mistakes.count > visibleMistakes { Button("عرض المزيد من المواضع") { visibleMistakes += 50 } }
                if !mistakes.isEmpty { Text("اسحب الملاحظة لاستبعاد نتيجة تعرف غير صحيحة. الاستبعاد لا يغيّر تقييمات المراجعات السابقة أو يضيف إنجازًا للورد.").font(.caption).foregroundStyle(.secondary) }
            }
            Section("آيات نطاقك") {
                ForEach(range, id: \.self) { number in
                    let state = memorization.progress.verses["\(memorization.plan.chapter):\(number)"]
                    NavigationLink { MushafReader(chapter: memorization.plan.chapter, ayah: number) } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("الآية \(number)").font(.headline)
                                Spacer()
                                Text(state == nil ? "جديدة" : state!.needsHelp ? "تحتاج تثبيتًا" : state!.stage >= 3 ? "استرجاع متكرر" : "قيد التثبيت").font(.caption)
                            }
                            if let state {
                                HStack {
                                    Text("\(state.attempts) مراجعات · \(state.lapses) مرات بمساعدة").font(.caption).foregroundStyle(.secondary)
                                    Spacer()
                                    Text(state.nextReview, style: .date).font(.caption)
                                }
                            }
                        }.padding(.vertical, 4)
                    }
                }
            }
        }.navigationTitle("خريطة الإتقان")
    }
}

struct MemorizationPlanView: View {
    @EnvironmentObject var store: AtharStore
    @EnvironmentObject var memorization: MemorizationStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft = MemorizationPlan()
    @State private var invalid = false
    private var maxAyah: Int { store.quran.first { $0.number == draft.chapter }?.ayahs.count ?? 7 }
    var body: some View {
        Form {
            Picker("السورة", selection: $draft.chapter) { ForEach(store.quran) { Text($0.name).tag($0.number) } }
            Stepper("من الآية \(draft.from)", value: $draft.from, in: 1...maxAyah)
            Stepper("إلى الآية \(draft.to)", value: $draft.to, in: 1...maxAyah)
            Stepper("هدف المراجعة اليومي \(draft.daily) آيات", value: $draft.daily, in: 1...50)
            Text("تبدأ المراجعة بالآيات التي احتجت فيها مساعدة، ثم المستحقة والجديدة. هدف اليوم لا يتجاوز عدد آيات نطاقك.").font(.caption).foregroundStyle(.secondary)
            Button("حفظ الخطة") { if memorization.configure(draft, corpus: store.quran) { dismiss() } else { invalid = true } }.accessibilityIdentifier("hifz.savePlan")
        }.navigationTitle("خطة الحفظ").onAppear { draft = memorization.plan }
            .onChange(of: draft.chapter) { _, _ in draft.from = 1; draft.to = min(7, maxAyah) }
            .onChange(of: draft.from) { _, value in if draft.to < value { draft.to = value } }
            .onChange(of: draft.to) { _, value in if draft.from > value { draft.from = value } }
            .alert("راجع نطاق الآيات", isPresented: $invalid) { Button("تم") {} } message: { Text("يجب أن تكون آية النهاية أكبر من أو مساوية لآية البداية.") }
    }
}
struct MemorizationTestView: View {
    @EnvironmentObject var store: AtharStore
    @EnvironmentObject var memorization: MemorizationStore
    @EnvironmentObject var audio: LocalRecitationRecorder
    @Environment(\.scenePhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var reduced
    @State private var keys: [Int] = []
    @State private var chapter = 1
    @State private var index = 0
    @State private var hintWords = 0
    @State private var revealed = false
    @State private var paused = false
    @State private var answers: [MemorizationAnswer] = []
    @State private var done = false
    @State private var saved = false
    @State private var hintCount = 0
    private var surah: Surah? { store.quran.first { $0.number == chapter } }
    private var ayah: Ayah? { guard index < keys.count else { return nil }; return surah?.ayahs.first { $0.number == keys[index] } }
    @State private var wordCount = 0
    @State private var recording = false
    var body: some View {
        VStack(spacing: 8) {
            if done {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        NoorCompletionMark()
                        Text("أكملت المراجعة").font(.largeTitle.bold()).accessibilityIdentifier("hifz.complete")
                        if !saved {
                            Text("لم تُحفظ النتيجة. سجلّك السابق محفوظ دون استبدال.")
                            Button("حاول حفظ النتيجة") { saved = memorization.finish(chapter: chapter, answers: answers) }
                        }
                        Text("تذكّرت \(answers.filter { $0.assessment == "remembered" }.count) من \(answers.count) آيات بتقييمك الذاتي.")
                        NavigationLink("سجل المراجعة") { MemorizationHistoryView() }.accessibilityIdentifier("hifz.resultHistory")
                        Button("مراجعة جديدة") { start(forceNew: true) }.frame(minHeight: 44)
                    }.padding(20)
                }
            } else if let ayah {
                Text("السؤال \(ArabicSearch.digits(index + 1)) من \(ArabicSearch.digits(keys.count)) · الآية \(ArabicSearch.digits(ayah.number))")
                    .font(.subheadline).foregroundStyle(.secondary)
                NoorProgressBar(value: Double(index) / Double(max(1, keys.count)), label: "تقدم اختبار الحفظ").padding(.horizontal, 16)
                ZStack {
                    MushafTrainingPage(chapter: chapter, ayah: ayah.number, revealedWords: hintWords, revealAll: revealed,
                        onHint: giveHint, onWordCount: { wordCount = $0 })
                        .opacity(paused ? 0 : 1).allowsHitTesting(!paused).accessibilityHidden(paused)
                    if paused { Label("الجلسة متوقفة؛ موضعك محفوظ", systemImage: "pause.circle").font(.headline) }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                HStack {
                    Button("تلميح") { giveHint() }.disabled(paused || revealed || hintWords >= wordCount || wordCount == 0)
                    Spacer()
                    Button("كشف النص") { revealed = true; persistSession() }.disabled(paused).accessibilityIdentifier("hifz.reveal")
                    Spacer()
                    Button(paused ? "متابعة" : "استراحة") { paused.toggle(); if paused { audio.stop() }; persistSession() }.accessibilityIdentifier("hifz.pause")
                }.frame(minHeight: 44).padding(.horizontal, 16)
                HStack {
                    Button("تذكّرتها") { assess("remembered") }.disabled(paused || wordCount == 0).accessibilityIdentifier("hifz.remembered")
                    Spacer()
                    Button("تحتاج مراجعة") { assess("review") }.disabled(paused || wordCount == 0)
                    Spacer()
                    Button("تجاوز") { assess("skip") }.disabled(paused)
                }.frame(minHeight: 44).padding(.horizontal, 16)
                Text("قارن النص ثم قيّم استرجاعك. التلميح والكشف يُسجّلان كمساعدة.")
                    .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 16).padding(.bottom, 6)
            } else {
                ContentUnavailableView("تعذّر بدء المراجعة", systemImage: "book.closed", description: Text("اختر خطة حفظ صحيحة ثم أعد المحاولة."))
                Button("إعادة المحاولة") { start() }
            }
        }.background(Theme.panel).navigationTitle("اختبار الاسترجاع").navigationBarTitleDisplayMode(.inline)
            .toolbar { Button { recording = true } label: { Image(systemName: "mic") }.accessibilityLabel("تسجيل تسميع للمراجعة").accessibilityIdentifier("hifz.recording") }
            .sheet(isPresented: $recording) {
                NavigationStack { ScrollView { RecitationRecordingControls(recordingAllowed: !paused).padding(20) }
                    .navigationTitle("تسجيل التسميع").toolbar { Button("إغلاق") { recording = false }.accessibilityIdentifier("hifz.recording.close") } }
            }
            .onAppear { if keys.isEmpty { start() } }
            .onDisappear { persistSession(); audio.stop() }
            .onChange(of: phase) { _, new in if new != .active { persistSession(); paused = true; audio.stop() } }
    }
    private func giveHint() {
        guard !paused, !revealed, hintWords < wordCount else { return }
        hintCount += 1
        withAnimation(reduced || store.data.lowMotion ? nil : .easeInOut(duration: 0.2)) { hintWords = min(wordCount, hintWords + 2) }
        persistSession()
    }
    private func persistSession() {
        guard !done, !keys.isEmpty, answers.count < keys.count else { return }
        memorization.saveSession(.init(chapter: chapter, keys: keys, answers: answers,
            hintWords: hintWords, hintCount: hintCount, revealed: revealed))
    }
    private func start(forceNew: Bool = false) {
        audio.stop()
        let previous = forceNew ? nil : memorization.session
        chapter = previous?.chapter ?? memorization.plan.chapter
        keys = previous?.keys ?? memorization.reviewKeys(corpus: store.quran)
        answers = previous?.answers ?? []; index = answers.count
        hintWords = previous?.hintWords ?? 0; hintCount = previous?.hintCount ?? 0
        revealed = previous?.revealed ?? false; paused = false; done = false; saved = false
        persistSession()
    }
    private func assess(_ value: String) {
        guard !paused, !done, ["remembered", "review", "skip"].contains(value), let ayah else { return }
        answers.append(.init(ayah: ayah.number, assessment: value, revealed: revealed || (wordCount > 0 && hintWords >= wordCount), hints: hintCount))
        index += 1; revealed = false; hintWords = 0; hintCount = 0; wordCount = 0
        if index >= keys.count { audio.stop(); saved = memorization.finish(chapter: chapter, answers: answers); done = true } else { persistSession() }
    }
}
struct MemorizationHistoryView: View {
    @EnvironmentObject var store: AtharStore
    @EnvironmentObject var memorization: MemorizationStore
    var body: some View {
        List {
            if memorization.history.isEmpty { ContentUnavailableView("لا جلسات بعد", systemImage: "chart.bar", description: Text("أكمل اختبارًا ليظهر في سجلك.")) }
            ForEach(memorization.history) { result in
                Section {
                    Text(store.quran.first { $0.number == result.chapter }?.name ?? "المراجعة").font(.headline)
                    Text(result.date, style: .date).font(.caption).foregroundStyle(.secondary)
                    ForEach(Array(result.answers.enumerated()), id: \.offset) { _, answer in
                        HStack {
                            Text("الآية \(answer.ayah)")
                            Spacer()
                            Text(answer.assessment == "remembered" ? "تذكّرتها" : answer.assessment == "review" ? "تحتاج مراجعة" : "تجاوزتها")
                                .foregroundStyle(.secondary)
                        }
                        if answer.revealed || answer.hints > 0 { Text("كشف النص: \(answer.revealed ? "نعم" : "لا") · التلميحات: \(answer.hints)").font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
        }.navigationTitle("سجل المراجعة")
    }
}
struct LexicalSimilaritiesView: View {
    @EnvironmentObject var store: AtharStore
    @State private var chapter = 1
    @State private var number = 1
    private var surah: Surah? { store.quran.first { $0.number == chapter } }
    private func normalized(_ text: String) -> String {
        text.replacingOccurrences(of: "[\\u064B-\\u065F\\u0670\\u06D6-\\u06ED\\u0640]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "[أإآٱ]", with: "ا", options: .regularExpression)
            .replacingOccurrences(of: "[^\\u0621-\\u064A\\s]", with: "", options: .regularExpression)
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
    private var matches: [(surah: Surah, ayah: Ayah)] {
        guard let original = surah?.ayahs.first(where: { $0.number == number }) else { return [] }
        let tokens = normalized(QuranText.verse(chapter: chapter, ayah: original)).split(separator: " ").prefix(4)
        guard tokens.count >= 3 else { return [] }
        let phrase = tokens.joined(separator: " ")
        return store.quran.flatMap { s in s.ayahs.filter { !(s.number == chapter && $0.number == number) && normalized(QuranText.verse(chapter: s.number, ayah: $0)).contains(phrase) }.map { (s, $0) } }
    }
    var body: some View {
        List {
            Section {
                Picker("السورة", selection: $chapter) { ForEach(store.quran) { Text($0.name).tag($0.number) } }
                Stepper("الآية \(number)", value: $number, in: 1...(surah?.ayahs.count ?? 1))
                if let ayah = surah?.ayahs.first(where: { $0.number == number }) { QuranVerseText(QuranText.verse(chapter: chapter, ayah: ayah)) }
            }
            Section("\(matches.count) نتائج تشابه لفظي") {
                ForEach(Array(matches.prefix(30).enumerated()), id: \.offset) { _, match in
                    NavigationLink { MushafReader(chapter: match.surah.number, ayah: match.ayah.number) } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("\(match.surah.name) · \(match.ayah.number)").font(.caption).foregroundStyle(.secondary)
                            QuranVerseText(QuranText.verse(chapter: match.surah.number, ayah: match.ayah), size: 24)
                        }
                    }
                }
                if matches.isEmpty { Text("لم نجد العبارة الافتتاحية نفسها في آية أخرى.") }
            }
            Text("مطابقة أول أربع كلمات بعد إزالة التشكيل. لا تصنيف تفسيري ولا قائمة شاملة للمتشابهات.").font(.caption).foregroundStyle(.secondary)
        }.navigationTitle("التشابه اللفظي").onChange(of: chapter) { _, _ in number = 1 }
    }
}
