import SwiftUI
import AVFoundation

struct SpeechRecitationView: View {
    @EnvironmentObject private var store: AtharStore
    @EnvironmentObject private var memorization: MemorizationStore
    @EnvironmentObject private var speech: LocalSpeechRecitation
    @EnvironmentObject private var recorder: LocalRecitationRecorder
    @State private var downloadConsent = false
    @State private var hideVerses = true
    @State private var confirmedWords: Set<Int> = []
    private var chapter: Surah? { store.quran.first { $0.number == memorization.plan.chapter } }
    private var end: Int { min(memorization.plan.to, memorization.plan.from + 9) }
    private var words: [RecitationExpectedWord] { chapter.map { RecitationComparison.words(chapter: $0, from: memorization.plan.from, to: end) } ?? [] }
    private var currentAyah: Int {
        guard !words.isEmpty else { return memorization.plan.from }
        return words[min(words.count - 1, max(0, speech.anchor - 1))].ayah
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("تابع تسميعك").font(.largeTitle.bold())
                Text("\(chapter?.name ?? "الحفظ") · الآيات \(memorization.plan.from)–\(end)").font(.subheadline)
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
                    ForEach(chapter.ayahs.filter { (memorization.plan.from...end).contains($0.number) }) { ayah in
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
                Text("المتابعة مقارنة كلمات باستخدام تعرّف صوتي متعدد اللغات؛ قد يخطئ المحرك نفسه. لا تقيس التشكيل أو التجويد، ولا تغيّر نص القرآن أو تمنح حكمًا نهائيًا بصحة الحفظ. المقطع الصوتي مؤقت في الذاكرة ولا يُرسل لخادم ولا يُحفظ تلقائيًا. الجلسة حتى خمس دقائق وعشر آيات من خطتك.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(20)
        }.background(Theme.background).navigationTitle("المتابعة الصوتية")
            .confirmationDialog("تنزيل نموذج محلي متعدد اللغات بحجم يقارب ٦٢٦ ميغابايت، إضافة إلى ملفات التشغيل. يحتاج اتصالًا ومساحة كافية؛ بعد التجهيز تُعالج التلاوة على جهازك دون إرسال الصوت. قد يحمّل ملفات النموذج من Hugging Face.", isPresented: $downloadConsent, titleVisibility: .visible) {
                Button("تنزيل وتجهيز النموذج") { speech.prepare() }
                Button("إلغاء", role: .cancel) {}
            }
            .onDisappear { speech.stop(clear: true) }
            .onChange(of: speech.listening) { _, new in if new { confirmedWords = [] } }
            .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { _ in speech.stop() }
            .alert("المتابعة الصوتية", isPresented: Binding(get: { speech.message != nil }, set: { if !$0 { speech.message = nil } })) { Button("تم") { speech.message = nil } } message: { Text(speech.message ?? "") }
    }
    private func displayText(_ ayah: Ayah) -> String {
        guard hideVerses else { return QuranText.verse(chapter: memorization.plan.chapter, ayah: ayah) }
        let verseWords = words.filter { $0.ayah == ayah.number }
        let visible = verseWords.filter { $0.id < speech.anchor }.map(\.text).joined(separator: " ")
        return visible + (verseWords.last.map { $0.id >= speech.anchor } == true ? " …" : "")
    }
}
