import SwiftUI
import AVFoundation

struct SpeechRecitationView: View {
    @EnvironmentObject private var store: AtharStore
    @EnvironmentObject private var memorization: MemorizationStore
    @EnvironmentObject private var speech: LocalSpeechRecitation
    @EnvironmentObject private var recorder: LocalRecitationRecorder
    @State private var chapterNumber = 1
    @State private var from = 1
    @State private var to = 7
    @State private var beginAyah = 1
    @State private var resumeIndex: Int?
    @State private var configured = false
    @State private var rangePicker = false
    @State private var draftChapter = 1
    @State private var draftFrom = 1
    @State private var draftTo = 7
    @State private var draftBegin = 1
    @State private var details = false
    @State private var downloadConsent = false
    @State private var hideVerses = true
    @State private var confirmedWords: Set<Int> = []
    @State private var usedReveal = false
    @State private var reviewing = false
    @State private var resultSaved = false
    private var chapter: Surah? { store.quran.first { $0.number == chapterNumber } }
    private var words: [RecitationExpectedWord] { chapter.map { RecitationComparison.words(chapter: $0, from: from, to: to) } ?? [] }
    private var currentAyah: Int {
        guard !words.isEmpty else { return beginAyah }
        let active = speech.listening || speech.settling
        let position = active ? speech.anchor : (resumeIndex ?? initialIndex)
        return words[min(words.count - 1, max(0, active && speech.comparison?.reliableAlignment == true && position > 0 ? position - 1 : position))].ayah
    }
    private var initialIndex: Int { words.firstIndex { $0.ayah == beginAyah } ?? 0 }
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Button("\(chapter?.name ?? "السورة") · \(ArabicSearch.digits(from))–\(ArabicSearch.digits(to))") { draftChapter = chapterNumber; draftFrom = from; draftTo = to; draftBegin = beginAyah; rangePicker = true }
                    .disabled(speech.listening || speech.settling).accessibilityIdentifier("speech.range")
                Spacer()
                Toggle("إخفاء", isOn: $hideVerses).fixedSize().accessibilityIdentifier("speech.hideVerses")
            }.font(.subheadline).padding(.horizontal, 16)
            Text(speech.status).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 16).accessibilityIdentifier("speech.status")
            if configured {
                MushafTrainingPage(chapter: chapterNumber, ayah: currentAyah, revealedWords: 0, revealAll: !hideVerses,
                    hiddenRange: from...to, onHint: { hideVerses = false; usedReveal = true; speech.markHelpUsed() })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
            if speech.preparing || speech.deleting || speech.settling { ProgressView().accessibilityLabel("تجهيز أو إنهاء المعالجة الصوتية") }
            if !speech.ready {
                Button("تجهيز النموذج الصوتي") { downloadConsent = true }.frame(minHeight: 44)
                    .disabled(speech.preparing || speech.deleting).accessibilityIdentifier("speech.prepare")
            } else {
                Button(speech.listening ? "توقف واحفظ موضعك" : resumeIndex == nil ? "ابدأ التسميع" : "استأنف من آخر موضع") {
                    if speech.listening { speech.stop() }
                    else { Task { await speech.start(expected: words, recorder: recorder, resumeAt: resumeIndex ?? initialIndex, helped: usedReveal || !hideVerses) } }
                }.frame(minHeight: 48).disabled(speech.requestingPermission || speech.deleting || speech.settling || words.isEmpty || words.count > 1500)
                    .accessibilityIdentifier("speech.listen")
            }
            HStack {
                Button("الملاحظات") { details = true }.accessibilityIdentifier("speech.notes")
                Spacer()
                Button(resultSaved ? "حُفظت المراجعة" : "راجع النتيجة") { reviewing = true }
                    .disabled(resultSaved || speech.listening || speech.settling || speech.transcript.isEmpty).accessibilityIdentifier("speech.reviewResult")
            }.frame(minHeight: 44).padding(.horizontal, 16)
            Text(words.count > 1500 ? "هذا النطاق كبير للمعالجة الحالية؛ اختر نطاقًا أقصر." : "المتابعة تقارن الكلمات وقد يخطئ التعرّف. لا تقيس التشكيل أو التجويد. الجلسة حتى خمس دقائق، ويمكن استئناف الموضع بعدها.")
                .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 16).padding(.bottom, 6)
        }.background(Theme.panel).navigationTitle("التسميع").navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("تنزيل نموذج محلي بحجم يقارب ٦٢٦ ميغابايت، إضافة إلى ملفات التشغيل. يحتاج اتصالًا ومساحة كافية. بعد التجهيز تُعالج التلاوة على جهازك؛ قد يحمّل النموذج من Hugging Face.", isPresented: $downloadConsent, titleVisibility: .visible) {
                Button("تنزيل وتجهيز النموذج") { speech.prepare() }; Button("إلغاء", role: .cancel) {}
            }
            .task {
                if !configured {
                    if let position = speech.savedPosition {
                        chapterNumber = position.chapter; from = position.from; to = position.to; beginAyah = position.from
                        resumeIndex = position.nextWord; usedReveal = position.usedHelp
                    } else {
                        chapterNumber = memorization.plan.chapter; from = memorization.plan.from; to = memorization.plan.to; beginAyah = from
                    }
                    configured = true
                }
                speech.prepareLocalIfAvailable()
            }
            .onDisappear { speech.stop(clear: true) }
            .onChange(of: speech.anchor) { _, value in if speech.listening || speech.settling { resumeIndex = value } }
            .onChange(of: speech.listening) { _, new in if new { confirmedWords = []; resultSaved = false; usedReveal = usedReveal || !hideVerses } }
            .onChange(of: hideVerses) { _, new in if !new { usedReveal = true; speech.markHelpUsed() } }
            .sheet(isPresented: $rangePicker) { rangeForm }
            .sheet(isPresented: $details) { observationSheet }
            .sheet(isPresented: $reviewing) {
                if let chapter { NavigationStack { SpeechSessionReviewView(chapter: chapter, from: from, to: to, revealed: usedReveal) { resultSaved = true } } }
            }
            .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { _ in speech.stop() }
            .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { notification in
                let raw = (notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? NSNumber)?.uintValue ?? 0
                let reason = AVAudioSession.RouteChangeReason(rawValue: raw)
                if speech.listening && (reason == .oldDeviceUnavailable || reason == .newDeviceAvailable) { speech.stop(); speech.message = "تغيّر مخرج الصوت. تحقق من السماعة ثم استأنف التسميع." }
            }
            .alert("التسميع", isPresented: Binding(get: { speech.message != nil }, set: { if !$0 { speech.message = nil } })) { Button("حسنًا") { speech.message = nil } } message: { Text(speech.message ?? "") }
    }
    private var rangeForm: some View {
        NavigationStack {
            Form {
                Picker("السورة", selection: $draftChapter) { ForEach(store.quran) { Text($0.name).tag($0.number) } }
                let maximum = store.quran.first { $0.number == draftChapter }?.ayahs.count ?? 7
                let lower = min(maximum, max(1, draftFrom))
                let upper = min(maximum, max(lower, draftTo))
                Stepper("من الآية \(ArabicSearch.digits(draftFrom))", value: $draftFrom, in: 1...maximum)
                Stepper("إلى الآية \(ArabicSearch.digits(draftTo))", value: $draftTo, in: lower...maximum)
                Stepper("ابدأ من الآية \(ArabicSearch.digits(draftBegin))", value: $draftBegin, in: lower...upper)
                Button("ابدأ من الموضع المختار") {
                    speech.stop(clear: true)
                    chapterNumber = draftChapter; from = lower; to = upper; beginAyah = max(lower, min(upper, draftBegin))
                    resumeIndex = nil; usedReveal = !hideVerses; resultSaved = false; confirmedWords = []; rangePicker = false
                }.accessibilityIdentifier("speech.applyRange")
                if speech.ready {
                    Button("حذف النموذج وتوفير المساحة", role: .destructive) { Task { _ = await speech.eraseModel() } }
                        .disabled(speech.preparing || speech.deleting || speech.listening)
                }
                Text("يُحفظ موضع الجلسة والمساعدة على جهازك. الصوت والتفريغ لا يُحفظان تلقائيًا ولا يُرفعان.").font(.caption).foregroundStyle(.secondary)
            }.navigationTitle("نطاق التسميع")
                .onChange(of: draftChapter) { _, value in draftFrom = 1; draftTo = min(7, store.quran.first { $0.number == value }?.ayahs.count ?? 7); draftBegin = 1 }
                .onChange(of: draftFrom) { _, value in draftTo = max(value, draftTo); draftBegin = max(value, min(draftBegin, draftTo)) }
                .onChange(of: draftTo) { _, value in draftBegin = max(draftFrom, min(value, draftBegin)) }
                .toolbar { Button("إغلاق") { rangePicker = false } }
        }
    }
    private var observationSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("فروق محتملة من مقاطع الجلسة؛ لم تُسجّل أخطاء حفظ تلقائيًا.").font(.headline)
                    if speech.observations.isEmpty { Text("لا توجد ملاحظات قابلة للمراجعة الآن.") }
                    TimelineView(.periodic(from: .now, by: 1)) { timeline in
                        ForEach(speech.observations.filter { !$0.dismissed }) { note in
                            VStack(alignment: .leading, spacing: 6) {
                                let word = words.indices.contains(note.wordIndex) ? words[note.wordIndex] : nil
                                if let word { Text("الآية \(ArabicSearch.digits(word.ayah))").font(.caption.bold()) }
                                Text("المتوقع: \(note.expected)")
                                Text("المتعرّف عليه: \(note.heard ?? "لم تظهر الكلمة")").foregroundStyle(.secondary)
                                if note.corrected { Text("تطابقت الكلمة عند إعادتها؛ لا تُضاف للمراجعة.").font(.caption) }
                                else {
                                    if !note.readyForReview(at: timeline.date) { Text("بانتظار فرصة للتصحيح الذاتي…").font(.caption) }
                                    if let word {
                                        Button(confirmedWords.contains(note.wordIndex) ? "أُضيف للمراجعة" : "أكد أن الموضع يحتاج تثبيتًا") {
                                            if memorization.confirmMistake(chapter: word.chapter, ayah: word.ayah, expected: word.text, heard: note.heard) { confirmedWords.insert(note.wordIndex) }
                                            else { speech.message = memorization.error ?? "تعذّر حفظ الموضع." }
                                        }.disabled(confirmedWords.contains(note.wordIndex) || speech.listening || speech.settling || !note.readyForReview(at: timeline.date))
                                    }
                                    Button("استبعدها: خطأ في التعرّف") { speech.dismissObservation(note.wordIndex) }
                                        .disabled(confirmedWords.contains(note.wordIndex))
                                }
                            }.padding(.vertical, 8)
                        }
                    }
                    if !speech.transcript.isEmpty { DisclosureGroup("ما تعرّف عليه المحرك") { Text(verbatim: speech.transcript).textSelection(.enabled) } }
                }.padding(20)
            }.navigationTitle("مراجعة الملاحظات").toolbar { Button("إغلاق") { details = false } }
        }
    }
}

struct SpeechSessionReviewView: View {
    @EnvironmentObject private var memorization: MemorizationStore
    @Environment(\.dismiss) private var dismiss
    let chapter: Surah
    let from: Int
    let to: Int
    let revealed: Bool
    let saved: () -> Void
    @State private var grades: [Int: String] = [:]
    @State private var error: String?
    private var verses: [Ayah] { chapter.ayahs.filter { (from...to).contains($0.number) } }
    var body: some View {
        Form {
            Section {
                Text("قارن تسميعك بالنص ثم قيّم كل آية. لا يقرر المحرك صحة الحفظ، ولن نحتسب آية لم تختَر تقييمها.")
                if revealed { Text("استُخدم إظهار النص؛ يُحسب الورد ممارسةً، ولا يُحسب استرجاعًا مستقلًا.").font(.caption).foregroundStyle(.secondary) }
            }
            ForEach(verses) { ayah in
                Section("الآية \(ayah.number)") {
                    QuranVerseText(QuranText.verse(chapter: chapter.number, ayah: ayah))
                    Picker("تقييمك", selection: Binding(get: { grades[ayah.number] ?? "skip" }, set: { grades[ayah.number] = $0 })) {
                        Text("لم أراجعها").tag("skip")
                        Text("تذكّرتها").tag("remembered")
                        Text("تحتاج تثبيتًا").tag("review")
                    }
                }
            }
            Section {
                Button("حفظ نتيجة التسميع") {
                    let answers = verses.map { MemorizationAnswer(ayah: $0.number, assessment: grades[$0.number] ?? "skip", revealed: revealed, hints: 0) }
                    if memorization.finish(chapter: chapter.number, answers: answers) { saved(); dismiss() }
                    else { error = memorization.error ?? "تعذّر حفظ نتيجة التسميع." }
                }.disabled(!grades.values.contains { $0 != "skip" }).accessibilityIdentifier("speech.saveResult")
            }
        }.navigationTitle("مراجعة التسميع")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { dismiss() } } }
            .alert("نتيجة التسميع", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("تم") { error = nil } } message: { Text(error ?? "") }
    }
}
