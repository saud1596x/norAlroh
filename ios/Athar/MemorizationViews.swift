import SwiftUI

struct MemorizationPlan: Codable { var chapter = 1; var from = 1; var to = 7; var daily = 3 }
struct MemorizationAnswer: Codable { let ayah: Int; let assessment: String; let revealed: Bool; let hints: Int }
struct MemorizationResult: Codable, Identifiable {
    var id = UUID(); var date = Date(); let chapter: Int; let answers: [MemorizationAnswer]
}
@MainActor final class MemorizationStore: ObservableObject {
    @Published private(set) var plan = MemorizationPlan()
    @Published private(set) var history: [MemorizationResult] = []
    @Published var error: String?
    @Published private(set) var unreadableHistory: Data?
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
        do { let data = try JSONEncoder().encode(candidate); defaults.set(data, forKey: "noor.memorization.plan"); plan = candidate; return true }
        catch { self.error = "تعذر حفظ خطة المراجعة."; return false }
    }
    @discardableResult func finish(chapter: Int, answers: [MemorizationAnswer]) -> Bool {
        guard unreadableHistory == nil else { error = "لم تُحفظ النتيجة كي لا يُستبدل سجل سابق تعذّر فتحه. صدّر بياناتك من الإعدادات."; return false }
        let result = MemorizationResult(chapter: chapter, answers: answers)
        guard let corpus = QuranResources.corpus, Self.valid(result, corpus: corpus) else { error = "راجع آيات نتيجة المراجعة."; return false }
        let next = Array(([result] + history).prefix(100))
        do { let data = try JSONEncoder().encode(next); defaults.set(data, forKey: "noor.memorization.history"); history = next; return true }
        catch { self.error = "تعذر حفظ نتيجة المراجعة."; return false }
    }
    func erase() {
        defaults.removeObject(forKey: "noor.memorization.history"); defaults.removeObject(forKey: "noor.memorization.plan")
        history = []; plan = MemorizationPlan(); unreadableHistory = nil; error = nil
    }
}
struct MemorizationView: View {
    @EnvironmentObject var store: AtharStore
    @EnvironmentObject var memorization: MemorizationStore
    @Environment(\.accessibilityReduceMotion) private var systemReduce
    @State private var revealed = 0
    private var surah: Surah? { store.quran.first { $0.number == memorization.plan.chapter } }
    private var ayahs: [Ayah] {
        guard let surah else { return [] }
        return surah.ayahs.filter { (memorization.plan.from...memorization.plan.to).contains($0.number) }
    }
    private var total: Int { ayahs.reduce(0) { $0 + QuranText.verse(chapter: memorization.plan.chapter, ayah: $1).split(whereSeparator: \.isWhitespace).count } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Card {
                    Text(surah?.name ?? "اختر سورة").font(.title2.bold())
                    Text("الآيات \(memorization.plan.from)–\(memorization.plan.to) · \(revealed) من \(total) كلمة مكشوفة")
                        .font(.subheadline).foregroundStyle(.secondary)
                    NavigationLink("السورة وخطة الحفظ") { MemorizationPlanView() }.accessibilityIdentifier("hifz.plan")
                    NavigationLink("اختبار الاسترجاع") { MemorizationTestView() }.accessibilityIdentifier("hifz.test")
                    NavigationLink("التسميع والمتابعة الصوتية") { SpeechRecitationView() }.accessibilityIdentifier("hifz.speech")
                    NavigationLink("سجل المراجعة") { MemorizationHistoryView() }.accessibilityIdentifier("hifz.history")
                    NavigationLink("التشابه اللفظي") { LexicalSimilaritiesView() }.accessibilityIdentifier("hifz.similarities")
                }
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(ayahs.enumerated()), id: \.element.id) { index, ayah in
                        let offset = ayahs.prefix(index).reduce(0) { $0 + QuranText.verse(chapter: memorization.plan.chapter, ayah: $1).split(whereSeparator: \.isWhitespace).count }
                        let words = QuranText.verse(chapter: memorization.plan.chapter, ayah: ayah).split(whereSeparator: \.isWhitespace)
                        let visible = max(0, min(words.count, revealed - offset))
                        VStack(alignment: .leading, spacing: 2) {
                        QuranVerseText(words.enumerated().map { $0.offset < visible ? String($0.element) : "▰" }.joined(separator: " "))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityLabel("الآية \(ayah.number)، " + words.prefix(visible).joined(separator: " ") + ", بقية الكلمات مخفية")
                        Text("الآية \(ayah.number)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    }
                    HStack {
                        Button("إظهار كلمة") { withAnimation(systemReduce || store.data.lowMotion ? nil : .easeInOut(duration: 0.2)) { revealed = min(total, revealed + 1) } }
                            .disabled(revealed >= total).frame(minHeight: 44)
                        Spacer()
                        Button(revealed >= total ? "إخفاء الآيات" : "كشف الآيات") { revealed = revealed >= total ? 0 : total }.frame(minHeight: 44)
                    }
                    Text("الكشف والتقييم يدويان.").font(.caption).foregroundStyle(.secondary)
                }
                Card { RecitationRecordingControls() }
            }.padding(20)
        }.background(Theme.background).navigationTitle("مساحة الحفظ")
            .onChange(of: memorization.plan.chapter) { _, _ in revealed = 0 }
            .onChange(of: memorization.plan.from) { _, _ in revealed = 0 }
            .onChange(of: memorization.plan.to) { _, _ in revealed = 0 }
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
            Text("الاختبار الواحد يراجع حتى ١٠ آيات عشوائية من نطاقك.").font(.caption).foregroundStyle(.secondary)
            Button("حفظ الخطة") { if memorization.configure(draft, corpus: store.quran) { dismiss() } else { invalid = true } }.accessibilityIdentifier("hifz.savePlan")
        }.navigationTitle("خطة الحفظ").onAppear { draft = memorization.plan }
            .onChange(of: draft.chapter) { _, _ in draft.from = 1; draft.to = min(7, maxAyah) }
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
                    Button("مراجعة جديدة") { start() }.frame(minHeight: 44)
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
                            Button("كشف النص") { withAnimation(reduced || store.data.lowMotion ? nil : .easeInOut(duration: 0.2)) { revealed = true } }.disabled(paused).accessibilityIdentifier("hifz.reveal")
                            Button(paused ? "متابعة" : "استراحة") { paused.toggle(); if paused { audio.stop() } }.accessibilityIdentifier("hifz.pause")
                        }.buttonStyle(.bordered).font(.subheadline)
                    }
                    Card { RecitationRecordingControls(recordingAllowed: !paused) }
                    Text("قارن النص ثم قيّم استرجاعك بنفسك.").font(.subheadline).foregroundStyle(.secondary)
                    PrimaryButton(title: "تذكّرتها", icon: "checkmark") { assess("remembered") }.disabled(paused).accessibilityIdentifier("hifz.remembered")
                    Button("تحتاج مراجعة") { assess("review") }.buttonStyle(.bordered).disabled(paused).frame(minHeight: 44)
                    Button("تجاوز هذه الآية") { assess("skip") }.disabled(paused).frame(minHeight: 44)
                    Text("لا تصحيح صوتي آلي ولا تقييم للتجويد.").font(.caption).foregroundStyle(.secondary)
                } else {
                    ContentUnavailableView("تعذّر بدء المراجعة", systemImage: "book.closed", description: Text("تحقّق من موارد المصحف واختر خطة حفظ صحيحة."))
                    Button("إعادة المحاولة") { start() }
                }
            }.padding(20)
        }.background(Theme.background).navigationTitle("اختبار الاسترجاع")
            .onAppear { if keys.isEmpty { start() } }
            .onDisappear { audio.stop() }
            .onChange(of: phase) { _, new in if new != .active { paused = true; audio.stop() } }
    }
    private var wordCount: Int { ayah.map { QuranText.verse(chapter: chapter, ayah: $0).split(whereSeparator: \.isWhitespace).count } ?? 0 }
    private var cueWords: Int { min(2, max(0, wordCount - 1)) }
    private func giveHint() {
        guard !paused, !revealed, cueWords + hintWords < wordCount else { return }
        hintCount += 1
        withAnimation(reduced || store.data.lowMotion ? nil : .easeInOut(duration: 0.2)) { hintWords = min(wordCount - cueWords, hintWords + 2) }
    }
    private func start() {
        audio.stop()
        let p = memorization.plan; chapter = p.chapter
        let max = store.quran.first { $0.number == chapter }?.ayahs.count ?? 0
        guard max > 0 else { return }
        let from = min(max, maxInt(1, p.from)); let to = min(max, maxInt(from, p.to))
        keys = Array(Array(from...to).shuffled().prefix(min(10, p.daily)))
        index = 0; hintWords = 0; hintCount = 0; revealed = false; paused = false; answers = []; done = false; saved = false
    }
    private func maxInt(_ a: Int, _ b: Int) -> Int { Swift.max(a, b) }
    private func assess(_ value: String) {
        guard !paused, !done, ["remembered", "review", "skip"].contains(value), let ayah else { return }
        answers.append(.init(ayah: ayah.number, assessment: value, revealed: revealed || cueWords + hintWords >= wordCount, hints: hintCount))
        index += 1; revealed = false; hintWords = 0; hintCount = 0
        if index >= keys.count { audio.stop(); saved = memorization.finish(chapter: chapter, answers: answers); done = true }
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
