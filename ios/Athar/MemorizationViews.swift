import SwiftUI

struct MemorizationPlan: Codable { var chapter = 1; var from = 1; var to = 7; var daily = 3 }
struct MemorizationAnswer: Codable { let ayah: Int; let assessment: String; let revealed: Bool; let hints: Int }
struct MemorizationResult: Codable, Identifiable {
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
            && confirmedMistakes.allSatisfy { validKey("\($0.chapter):\($0.ayah)") && !$0.expected.isEmpty && $0.date.timeIntervalSince1970.isFinite }
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
}
@MainActor final class MemorizationStore: ObservableObject {
    @Published private(set) var plan = MemorizationPlan()
    @Published private(set) var history: [MemorizationResult] = []
    @Published private(set) var session: MemorizationSession?
    @Published var error: String?
    @Published private(set) var unreadableHistory: Data?
    @Published private(set) var progress = MemorizationProgress()
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: "noor.memorization.plan"), let value = try? JSONDecoder().decode(MemorizationPlan.self, from: data),
            (1...114).contains(value.chapter), value.from > 0, value.to >= value.from,
            let corpus = QuranResources.corpus, value.to <= corpus[value.chapter - 1].ayahs.count,
            (1...50).contains(value.daily) { plan = value }
        if let data = defaults.data(forKey: "noor.memorization.history") {
            if let value = try? JSONDecoder().decode([MemorizationResult].self, from: data),
               let corpus = QuranResources.corpus, value.allSatisfy({ Self.valid($0, corpus: corpus) }),
               Set(value.map(\.id)).count == value.count { history = Array(value.prefix(100)) }
            else { unreadableHistory = data; error = "تعذّر قراءة سجل الحفظ السابق. صدّر بياناتك لإنقاذ نسخة أو احذفها من الإعدادات قبل تسجيل نتائج جديدة." }
        }
        if let data = defaults.data(forKey: "noor.memorization.archive") {
            if let value = try? JSONDecoder().decode(MemorizationArchive.self, from: data), value.version == 1,
               let corpus = QuranResources.corpus, value.progress.valid(corpus: corpus),
               value.history.allSatisfy({ Self.valid($0, corpus: corpus) }), Set(value.history.map(\.id)).count == value.history.count {
                history = Array(value.history.prefix(100)); progress = value.progress; unreadableHistory = nil; error = nil
            } else {
                unreadableHistory = data; error = "تعذّر فتح سجل الإتقان. بياناتك محفوظة؛ صدّرها قبل بدء جلسات جديدة."
            }
        } else {
            for result in history.sorted(by: { $0.date < $1.date }) { progress.record(result) }
        }
        if let data = defaults.data(forKey: "noor.memorization.session"),
           let value = try? JSONDecoder().decode(MemorizationSession.self, from: data),
           let corpus = QuranResources.corpus, validSession(value, corpus: corpus) { session = value }
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
        let keys = Array(plan.from...upper).shuffled().sorted { a, b in
            func priority(_ key: Int) -> Int {
                if progress.verses["\(plan.chapter):\(key)"]?.needsHelp == true { return 0 }
                if let answer = latest[key], answer.assessment != "remembered" || answer.revealed || answer.hints > 0 { return 0 }
                guard let state = progress.verses["\(plan.chapter):\(key)"] else { return 2 }
                return state.nextReview <= Calendar.current.startOfDay(for: Date()) ? 1 : 3
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
        next.confirmedMistakes = Array(next.confirmedMistakes.prefix(500))
        let key = "\(chapter):\(ayah)"
        var state = next.verses[key] ?? VerseReviewState()
        state.needsHelp = true; state.stage = 0; state.nextReview = Calendar.current.startOfDay(for: Date()); next.verses[key] = state
        do {
            let data = try JSONEncoder().encode(MemorizationArchive(version: 1, history: history, progress: next))
            defaults.set(data, forKey: "noor.memorization.archive"); progress = next; return true
        } catch { self.error = "تعذّر حفظ موضع المراجعة."; return false }
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
        do { let data = try JSONEncoder().encode(candidate); defaults.set(data, forKey: "noor.memorization.plan"); plan = candidate; clearSession(); return true }
        catch { self.error = "تعذر حفظ خطة المراجعة."; return false }
    }
    @discardableResult func finish(chapter: Int, answers: [MemorizationAnswer]) -> Bool {
        guard unreadableHistory == nil else { error = "لم تُحفظ النتيجة كي لا يُستبدل سجل سابق تعذّر فتحه. صدّر بياناتك من الإعدادات."; return false }
        let result = MemorizationResult(chapter: chapter, answers: answers)
        guard let corpus = QuranResources.corpus, Self.valid(result, corpus: corpus) else { error = "راجع آيات نتيجة المراجعة."; return false }
        let next = Array(([result] + history).prefix(100))
        var nextProgress = progress; nextProgress.record(result)
        do {
            let data = try JSONEncoder().encode(MemorizationArchive(version: 1, history: next, progress: nextProgress))
            defaults.set(data, forKey: "noor.memorization.archive")
            history = next; progress = nextProgress; clearSession()
            NoorFocusController.shared.sync(progress: progress); return true
        }
        catch { self.error = "تعذر حفظ نتيجة المراجعة."; return false }
    }
    func erase() {
        NoorFocusController.shared.disable()
        defaults.removeObject(forKey: "noor.memorization.history"); defaults.removeObject(forKey: "noor.memorization.plan")
        defaults.removeObject(forKey: "noor.memorization.archive")
        clearSession(); history = []; progress = MemorizationProgress(); plan = MemorizationPlan(); unreadableHistory = nil; error = nil
    }
}
struct MemorizationView: View {
    @EnvironmentObject var store: AtharStore
    @EnvironmentObject var memorization: MemorizationStore
    @Environment(\.accessibilityReduceMotion) private var systemReduce
    @State private var revealed = 0
    @State private var practiceIndex = 0
    private var surah: Surah? { store.quran.first { $0.number == memorization.plan.chapter } }
    private var ayahs: [Ayah] {
        guard let surah else { return [] }
        return surah.ayahs.filter { (memorization.plan.from...memorization.plan.to).contains($0.number) }
    }
    private var practiceAyah: Ayah? { ayahs.indices.contains(practiceIndex) ? ayahs[practiceIndex] : ayahs.first }
    private var total: Int { practiceAyah.map { QuranText.verse(chapter: memorization.plan.chapter, ayah: $0).split(whereSeparator: \.isWhitespace).count } ?? 0 }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                NoorDailyWardCard()
                Card {
                    HStack {
                        VStack(alignment: .leading) { Text("\(memorization.masteredCount)").font(.title2.bold()); Text("آيات بإتقان متكرر").font(.caption) }
                        Spacer()
                        VStack(alignment: .leading) { Text("\(memorization.dueKeys().count)").font(.title2.bold()); Text("مراجعات مستحقة").font(.caption) }
                        Spacer()
                        VStack(alignment: .leading) { Text("\(memorization.streak())").font(.title2.bold()); Text("أيام ممارسة متتابعة").font(.caption) }
                    }
                    NavigationLink("خريطة الإتقان والآيات الضعيفة") { MemorizationInsightsView() }.accessibilityIdentifier("hifz.insights")
                    NavigationLink("حماية وقت الورد") { NoorFocusView() }.accessibilityIdentifier("hifz.focus")
                }
                Card {
                    Text(surah?.name ?? "اختر سورة").font(.title2.bold())
                    Text("الآيات \(memorization.plan.from)–\(memorization.plan.to) · \(revealed) من \(total) كلمة مكشوفة")
                        .font(.subheadline).foregroundStyle(.secondary)
                    NavigationLink("السورة وخطة الحفظ") { MemorizationPlanView() }.accessibilityIdentifier("hifz.plan")
                    NavigationLink(memorization.session == nil ? "ابدأ مراجعة اليوم" : "أكمل جلستك السابقة") { MemorizationTestView() }.accessibilityIdentifier("hifz.test")
                    NavigationLink("التسميع والمتابعة الصوتية") { SpeechRecitationView() }.accessibilityIdentifier("hifz.speech")
                    NavigationLink("سجل المراجعة") { MemorizationHistoryView() }.accessibilityIdentifier("hifz.history")
                    NavigationLink("التشابه اللفظي") { LexicalSimilaritiesView() }.accessibilityIdentifier("hifz.similarities")
                }
                Card {
                    HStack {
                        Text("تدريب آية بخطوة").font(.headline)
                        Spacer()
                        Text("\(min(practiceIndex + 1, ayahs.count)) / \(ayahs.count)").font(.caption.monospacedDigit())
                    }
                    if let ayah = practiceAyah {
                        let words = QuranText.verse(chapter: memorization.plan.chapter, ayah: ayah).split(whereSeparator: \.isWhitespace)
                        Text("الآية \(ayah.number)").font(.caption).foregroundStyle(.secondary)
                        if revealed > 0 {
                            QuranVerseText(words.prefix(revealed).joined(separator: " "))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            Label("استرجع الآية، ثم اكشف كلمة أو النص كاملًا", systemImage: "brain.head.profile")
                                .foregroundStyle(.secondary).padding(.vertical, 20)
                        }
                        if revealed > 0 && revealed < total { Text("بقية الآية مخفية").font(.caption).foregroundStyle(.secondary) }
                    }
                    HStack {
                        Button("الآية السابقة") { practiceIndex = max(0, practiceIndex - 1); revealed = 0 }
                            .disabled(practiceIndex == 0).frame(minHeight: 44)
                        Spacer()
                        Button("الآية التالية") { practiceIndex = min(ayahs.count - 1, practiceIndex + 1); revealed = 0 }
                            .disabled(practiceIndex + 1 >= ayahs.count).frame(minHeight: 44)
                    }
                    HStack {
                        Button("إظهار كلمة") { withAnimation(systemReduce || store.data.lowMotion ? nil : .easeInOut(duration: 0.2)) { revealed = min(total, revealed + 1) } }
                            .disabled(revealed >= total).frame(minHeight: 44)
                        Spacer()
                        Button(revealed >= total ? "إخفاء الآيات" : "كشف الآيات") { revealed = revealed >= total ? 0 : total }.frame(minHeight: 44)
                    }
                    Text("استرجع الآيات، ثم اكشف النص للمقارنة. يمكنك المتابعة من حيث توقفت.").font(.caption).foregroundStyle(.secondary)
                }
                Card { RecitationRecordingControls() }
            }.padding(20)
        }.background(Theme.background).navigationTitle("مساحة الحفظ")
            .alert("الحفظ والمراجعة", isPresented: Binding(get: { memorization.error != nil }, set: { if !$0 { memorization.error = nil } })) {
                Button("تم") { memorization.error = nil }
            } message: { Text(memorization.error ?? "") }
            .onChange(of: memorization.plan.chapter) { _, _ in revealed = 0; practiceIndex = 0 }
            .onChange(of: memorization.plan.from) { _, _ in revealed = 0; practiceIndex = 0 }
            .onChange(of: memorization.plan.to) { _, _ in revealed = 0; practiceIndex = 0 }
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
                ForEach(Array(mistakes.prefix(50))) { mistake in
                    NavigationLink { MushafReader(chapter: mistake.chapter, ayah: mistake.ayah) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("الآية \(mistake.ayah)").font(.caption)
                            QuranVerseText(mistake.expected, size: 24)
                            Text("المتعرّف عليه: \(mistake.heard ?? "لم تظهر الكلمة")").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
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
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if done {
                    NoorCompletionMark()
                    Text("أكملت المراجعة").font(.largeTitle.bold()).accessibilityIdentifier("hifz.complete")
                    Card { RecitationRecordingControls() }
                    if !saved {
                        Text("لم تُحفظ النتيجة. سجلّك السابق محفوظ دون استبدال.").font(.subheadline).foregroundStyle(.secondary)
                        Button("حاول حفظ النتيجة") { saved = memorization.finish(chapter: chapter, answers: answers) }.frame(minHeight: 44)
                    }
                    Text("تذكّرت \(answers.filter { $0.assessment == "remembered" }.count) من \(answers.count) آيات بتقييمك الذاتي.")
                    NavigationLink("سجل المراجعة") { MemorizationHistoryView() }.accessibilityIdentifier("hifz.resultHistory")
                    Button("مراجعة جديدة") { start(forceNew: true) }.frame(minHeight: 44)
                } else if !QuranTypography.available {
                    ContentUnavailableView("الخط القرآني غير متاح", systemImage: "textformat", description: Text("أعد تثبيت نسخة موثوقة قبل اختبار الآيات."))
                } else if let ayah {
                    Text("السؤال \(index + 1) من \(keys.count) · الآية \(ayah.number)").font(.subheadline).foregroundStyle(.secondary)
                    NoorProgressBar(value: Double(index) / Double(max(1, keys.count)), label: "تقدم اختبار الحفظ")
                    Text(paused ? "خذ وقتك" : "أكمل الآية").font(.largeTitle.bold())
                    Card {
                        if paused { Text("الجلسة متوقفة").font(.headline) }
                        else {
                            QuranVerseText(revealed ? QuranText.verse(chapter: chapter, ayah: ayah) : QuranText.verse(chapter: chapter, ayah: ayah).split(whereSeparator: \.isWhitespace).prefix(cueWords + hintWords).joined(separator: " ") + " …")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        HStack {
                            Button("تلميح") { giveHint() }.disabled(paused || revealed || cueWords + hintWords >= wordCount)
                            Button("كشف النص") { withAnimation(reduced || store.data.lowMotion ? nil : .easeInOut(duration: 0.2)) { revealed = true }; persistSession() }.disabled(paused).accessibilityIdentifier("hifz.reveal")
                            Button(paused ? "متابعة" : "استراحة") { paused.toggle(); if paused { audio.stop() } }.accessibilityIdentifier("hifz.pause")
                        }.buttonStyle(.bordered).font(.subheadline)
                    }
                    Card { RecitationRecordingControls(recordingAllowed: !paused) }
                    Text("قارن النص ثم قيّم استرجاعك بنفسك.").font(.subheadline).foregroundStyle(.secondary)
                    PrimaryButton(title: "تذكّرتها", icon: "checkmark") { assess("remembered") }.disabled(paused).accessibilityIdentifier("hifz.remembered")
                    Button("تحتاج مراجعة") { assess("review") }.buttonStyle(.bordered).disabled(paused).frame(minHeight: 44)
                    Button("تجاوز هذه الآية") { assess("skip") }.disabled(paused).frame(minHeight: 44)
                    Text("هذا تقييم ذاتي لاسترجاع الآيات. المتابعة الصوتية متاحة من مساحة الحفظ.").font(.caption).foregroundStyle(.secondary)
                } else {
                    ContentUnavailableView("تعذّر بدء المراجعة", systemImage: "book.closed", description: Text("تحقّق من موارد المصحف واختر خطة حفظ صحيحة."))
                    Button("إعادة المحاولة") { start() }
                }
            }.padding(20)
        }.background(Theme.background).navigationTitle("اختبار الاسترجاع")
            .onAppear { if keys.isEmpty { start() } }
            .onDisappear { persistSession(); audio.stop() }
            .onChange(of: phase) { _, new in if new != .active { persistSession(); paused = true; audio.stop() } }
    }
    private var wordCount: Int { ayah.map { QuranText.verse(chapter: chapter, ayah: $0).split(whereSeparator: \.isWhitespace).count } ?? 0 }
    private var cueWords: Int { min(2, max(0, wordCount - 1)) }
    private func giveHint() {
        guard !paused, !revealed, cueWords + hintWords < wordCount else { return }
        hintCount += 1
        withAnimation(reduced || store.data.lowMotion ? nil : .easeInOut(duration: 0.2)) { hintWords = min(wordCount - cueWords, hintWords + 2) }
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
        answers.append(.init(ayah: ayah.number, assessment: value, revealed: revealed || cueWords + hintWords >= wordCount, hints: hintCount))
        index += 1; revealed = false; hintWords = 0; hintCount = 0
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
