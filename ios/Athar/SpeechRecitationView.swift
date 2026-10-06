import SwiftUI
import AVFoundation

struct SpeechRecitationView: View {
    @EnvironmentObject private var store: AtharStore
    @EnvironmentObject private var memorization: MemorizationStore
    @EnvironmentObject private var speech: LocalSpeechRecitation
    @EnvironmentObject private var recorder: LocalRecitationRecorder
    @State private var verseOffset = 0
    @State private var downloadConsent = false
    @State private var hideVerses = true
    @State private var confirmedWords: Set<Int> = []
    @State private var usedReveal = false
    @State private var reviewing = false
    @State private var resultSaved = false
    private var chapter: Surah? { store.quran.first { $0.number == memorization.plan.chapter } }
    private var start: Int { min(memorization.plan.to, memorization.plan.from + verseOffset) }
    private var end: Int { start }
    private var words: [RecitationExpectedWord] { chapter.map { RecitationComparison.words(chapter: $0, from: start, to: end) } ?? [] }
    private var currentAyah: Int {
        guard !words.isEmpty else { return memorization.plan.from }
        return words[min(words.count - 1, max(0, speech.anchor - 1))].ayah
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("سمّع آية بخطوة").font(.largeTitle.bold())
                Text("\(chapter?.name ?? "الحفظ") · الآية \(start) من نطاقك").font(.subheadline)
                HStack {
                    Button("الآية السابقة") { move(-1) }.disabled(verseOffset == 0 || speech.listening || speech.settling)
                    Spacer()
                    Button("الآية التالية") { move(1) }.disabled(start >= memorization.plan.to || speech.listening || speech.settling)
                }.frame(minHeight: 44)
                Toggle("إخفاء الآيات أثناء التسميع", isOn: $hideVerses).accessibilityIdentifier("speech.hideVerses")
                Card {
                    Label(speech.ready ? "نموذج محلي جاهز" : "معالجة الصوت على جهازك", systemImage: "waveform").font(.headline)
                    Text(speech.status).font(.subheadline).accessibilityIdentifier("speech.status")
                    if speech.preparing || speech.deleting || speech.settling { ProgressView().accessibilityLabel("تجهيز أو إنهاء المعالجة الصوتية") }
                    if !speech.ready {
                        Button("تجهيز النموذج الصوتي") { downloadConsent = true }.frame(minHeight: 44)
                            .disabled(speech.preparing || speech.deleting).accessibilityIdentifier("speech.prepare")
                    } else {
                        Button(speech.listening ? "إيقاف المتابعة" : "ابدأ التسميع والمتابعة") {
                            if speech.listening { speech.stop() }
                            else { Task { await speech.start(expected: words, recorder: recorder) } }
                        }.frame(minHeight: 48).disabled(speech.requestingPermission || speech.deleting || speech.settling || words.isEmpty)
                            .accessibilityIdentifier("speech.listen")
                        Button("حذف النموذج وتوفير المساحة", role: .destructive) { Task { _ = await speech.eraseModel() } }
                            .frame(minHeight: 44).disabled(speech.preparing || speech.deleting || speech.listening)
                    }
                }
                if let chapter {
                    ForEach(chapter.ayahs.filter { (start...end).contains($0.number) }) { ayah in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("الآية \(ayah.number)").font(.caption)
                                if ayah.number == currentAyah && speech.anchor > 0 { Label("موضع المتابعة", systemImage: "waveform").font(.caption).foregroundStyle(Theme.gold) }
                            }
                            if hideVerses && speech.anchor == 0 {
                                Text("الآية مخفية؛ ابدأ التسميع أو أوقف الإخفاء للمراجعة.").foregroundStyle(.secondary)
                            } else { QuranVerseText(displayText(ayah), size: 28) }
                        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 20))
                            .overlay { RoundedRectangle(cornerRadius: 20).stroke(ayah.number == currentAyah && speech.anchor > 0 ? Theme.gold : .clear, lineWidth: 2) }
                    }
                }
                if let comparison = speech.comparison, comparison.reliableAlignment {
                    Card {
                        Text("مقارنة كلمات المقطع").font(.headline)
                        Text("\(comparison.matchedIndices.count) كلمة متطابقة في المقطع الحالي").font(.subheadline)
                        ForEach(comparison.possibleDifferences.prefix(12)) { difference in
                            VStack(alignment: .leading, spacing: 6) {
                                Text("فرق محتمل — يحتاج مراجعتك").font(.caption.bold()).foregroundStyle(Theme.gold)
                                if let expected = difference.expected { Text("المتوقع: \(expected)") }
                                Text("المتعرّف عليه: \(difference.heard ?? "لم تظهر الكلمة في التعرّف")").foregroundStyle(.secondary)
                                if let position = difference.wordIndex, words.indices.contains(position) {
                                    let word = words[position]
                                    Button(confirmedWords.contains(position) ? "أُضيف إلى سجل المراجعة" : "أكد أن هذا الموضع يحتاج مراجعة") {
                                        if memorization.confirmMistake(chapter: word.chapter, ayah: word.ayah, expected: word.text, heard: difference.heard) { confirmedWords.insert(position) }
                                        else { speech.message = memorization.error ?? "تعذّر حفظ موضع المراجعة." }
                                    }.disabled(confirmedWords.contains(position))
                                }
                            }
                        }
                    }
                }
                if !speech.transcript.isEmpty {
                    DisclosureGroup("ما تعرّف عليه المحرك") { Text(verbatim: speech.transcript).font(.body).textSelection(.enabled) }
                }
                if !speech.transcript.isEmpty && !speech.listening && !speech.settling && chapter != nil {
                    Button(resultSaved ? "حُفظت مراجعة هذا التسميع" : "راجع النتيجة واحفظ إنجاز الورد") { reviewing = true }
                        .disabled(resultSaved).frame(minHeight: 44).accessibilityIdentifier("speech.reviewResult")
                }
                Text("المتابعة مقارنة كلمات باستخدام تعرّف صوتي متعدد اللغات؛ قد يخطئ المحرك نفسه. لا تقيس التشكيل أو التجويد، ولا تغيّر نص القرآن أو تمنح حكمًا نهائيًا بصحة الحفظ. المقطع الصوتي مؤقت في الذاكرة ولا يُرسل لخادم ولا يُحفظ تلقائيًا. سمّع آية واحدة في كل خطوة، ثم راجع النتيجة قبل الانتقال. الجلسة حتى خمس دقائق.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(20)
        }.background(Theme.background).navigationTitle("المتابعة الصوتية")
            .confirmationDialog("تنزيل نموذج محلي متعدد اللغات بحجم يقارب ٦٢٦ ميغابايت، إضافة إلى ملفات التشغيل. يحتاج اتصالًا ومساحة كافية؛ بعد التجهيز تُعالج التلاوة على جهازك دون إرسال الصوت. قد يحمّل ملفات النموذج من Hugging Face.", isPresented: $downloadConsent, titleVisibility: .visible) {
                Button("تنزيل وتجهيز النموذج") { speech.prepare() }
                Button("إلغاء", role: .cancel) {}
            }
            .task { speech.prepareLocalIfAvailable() }
            .onDisappear { speech.stop(clear: true) }
            .onChange(of: speech.listening) { _, new in if new { confirmedWords = []; usedReveal = !hideVerses; resultSaved = false } }
            .onChange(of: hideVerses) { _, new in if !new { usedReveal = true } }
            .onChange(of: speech.comparison?.possibleDifferences.count) { _, new in if (new ?? 0) > 0 { usedReveal = true } }
            .sheet(isPresented: $reviewing) {
                if let chapter {
                    NavigationStack {
                        SpeechSessionReviewView(chapter: chapter, from: start, to: end, revealed: usedReveal) { resultSaved = true }
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { _ in speech.stop() }
            .alert("المتابعة الصوتية", isPresented: Binding(get: { speech.message != nil }, set: { if !$0 { speech.message = nil } })) { Button("تم") { speech.message = nil } } message: { Text(speech.message ?? "") }
    }
    private func move(_ delta: Int) {
        speech.stop(clear: true); verseOffset = max(0, min(memorization.plan.to - memorization.plan.from, verseOffset + delta)); confirmedWords = []; resultSaved = false; usedReveal = !hideVerses
    }
    private func displayText(_ ayah: Ayah) -> String {
        guard hideVerses else { return QuranText.verse(chapter: memorization.plan.chapter, ayah: ayah) }
        let verseWords = words.filter { $0.ayah == ayah.number }
        let visible = verseWords.filter { $0.id < speech.anchor }.map(\.text).joined(separator: " ")
        return visible + (verseWords.last.map { $0.id >= speech.anchor } == true ? " …" : "")
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
