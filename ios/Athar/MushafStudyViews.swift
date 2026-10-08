import SwiftUI

struct MushafStudyButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.caption).lineLimit(2)
            .frame(maxWidth: .infinity).frame(minHeight: 44)
            .background(Color.primary.opacity(configuration.isPressed ? 0.15 : 0.06), in: RoundedRectangle(cornerRadius: 10))
            .opacity(enabled ? 1 : 0.45)
    }
}

struct MushafStudySetup: View {
    @EnvironmentObject private var store: AtharStore
    @EnvironmentObject private var memorization: MemorizationStore
    @Environment(\.dismiss) private var dismiss
    let page: Int
    let pageKeys: [String]
    let initialKey: String
    let onOpen: () -> Void
    @State private var scope = MushafStudySession.Scope.page
    @State private var chapter = 1
    @State private var from = 1
    @State private var to = 1
    init(page: Int, pageKeys: [String], initialKey: String, onOpen: @escaping () -> Void) {
        self.page = page; self.pageKeys = pageKeys; self.initialKey = initialKey; self.onOpen = onOpen
        let parts = initialKey.split(separator: ":").compactMap { Int($0) }
        _chapter = State(initialValue: parts.first ?? 1)
        _from = State(initialValue: parts.count == 2 ? parts[1] : 1)
        _to = State(initialValue: parts.count == 2 ? parts[1] : 1)
    }
    private var count: Int { store.quran.indices.contains(chapter - 1) ? store.quran[chapter - 1].ayahs.count : 0 }
    private var selectedKeys: [String] {
        switch scope {
        case .page: return pageKeys
        case .surah: return (1...max(1, count)).map { "\(chapter):\($0)" }
        case .range: return from <= to ? (from...to).map { "\(chapter):\($0)" } : []
        }
    }
    var body: some View {
        NavigationStack {
            Form {
                if let pending = memorization.mushafStudy.pending {
                    Section("جلسة محفوظة") {
                        Text("\(pending.answers.count) من \(pending.keys.count) آية · المساعدة والإجابات محفوظة على هذا الجهاز.")
                        Button(pending.phase == .finishing ? "استكمال حفظ النتيجة" : "متابعة الجلسة") {
                            onOpen(); dismiss()
                        }.accessibilityIdentifier("study.resume")
                        Text("يمكنك إنهاء الجلسة من المصحف قبل بدء جلسة أخرى؛ لن تُستبدل خطة الحفظ السابقة.").font(.footnote)
                    }
                } else if memorization.unreadableMushafStudy != nil {
                    Section { Text("تعذّر قراءة الجلسة المحفوظة. احتُفظ بالبيانات الأصلية، ويمكن تصديرها من الإعدادات؛ لن نستبدلها بجلسة جديدة.") }
                } else {
                    Section("اختر المقطع") {
                        Picker("نوع المقطع", selection: $scope) {
                            Text("صفحة").tag(MushafStudySession.Scope.page)
                            Text("سورة").tag(MushafStudySession.Scope.surah)
                            Text("نطاق آيات").tag(MushafStudySession.Scope.range)
                        }.pickerStyle(.menu).accessibilityIdentifier("study.scope")
                        if scope == .page {
                            Text("الصفحة \(page) · \(pageKeys.count) آية")
                            Text("تُسمّع كل آية كاملة، وتُحفظ نتيجتها على حدة، حتى عندما تضم الصفحة أكثر من سورة.").font(.footnote)
                        } else {
                            Picker("السورة", selection: $chapter) {
                                ForEach(store.quran) { surah in Text(surah.name).tag(surah.number) }
                            }.pickerStyle(.menu).accessibilityIdentifier("study.chapter")
                            if scope == .range {
                                Stepper("من الآية \(from)", value: $from, in: 1...max(1, count))
                                Stepper("إلى الآية \(to)", value: $to, in: from...max(from, count))
                            }
                        }
                    }
                    Section {
                        Button("ابدأ التسميع") {
                            if memorization.startMushafStudy(keys: selectedKeys, scope: scope, page: page) { onOpen(); dismiss() }
                        }.disabled(selectedKeys.isEmpty || count == 0).accessibilityIdentifier("study.start")
                        Text("تسميع ذاتي داخل المصحف: اخفِ النص، واكشف الكلمات عند الحاجة، ثم قيّم تذكّرك. تُسجّل كل مساعدة؛ لا يوجد تصحيح صوتي آلي أو تقييم للتجويد.").font(.footnote)
                    }
                    if memorization.mushafStudy.summary != nil {
                        Section("آخر جلسة") { MushafStudySummaryContent() }
                    }
                }
                if let error = memorization.error { Section { Text(error).foregroundStyle(.red) } }
            }
            .navigationTitle("الحفظ والتسميع")
            .toolbar { Button("إغلاق") { dismiss() }.accessibilityIdentifier("study.setup.close") }
            .onChange(of: chapter) { _, _ in from = 1; to = 1 }
            .onChange(of: from) { _, value in if to < value { to = value } }
        }
    }
}

struct MushafStudySummaryContent: View {
    @EnvironmentObject private var memorization: MemorizationStore
    var body: some View {
        if let summary = memorization.mushafStudy.summary {
            VStack(alignment: .leading, spacing: 12) {
                Text("تم حفظ الجلسة").font(.headline).accessibilityIdentifier("study.result.saved")
                Text("أجبت عن \(summary.answered) من \(summary.session.keys.count) آية.")
                    .accessibilityIdentifier("study.result.answered")
                if summary.skipped > 0 {
                    Text("تجاوزت \(summary.skipped) آية دون تقييمها.").accessibilityIdentifier("study.result.skipped")
                }
                Text("تذكّرتها بتقييمك: \(summary.remembered) · استعنت بمساعدة: \(summary.helped)")
                    .accessibilityIdentifier("study.result.helped")
                Text(summary.reviewKeys.isEmpty ? "واصل المراجعة وفق خطتك؛ النتيجة تقييم ذاتي." : "الخطوة التالية: راجع \(summary.reviewKeys.count) آية احتاجت إلى مساعدة أو تثبيت. أُضيفت إلى سجل المراجعة.")
                Text("لم تُسجّل الآيات غير المُجاب عنها كأخطاء، ولم يُقيّم التجويد أو النطق آليًا.").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

struct MushafStudyResultView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView { MushafStudySummaryContent().padding().frame(maxWidth: .infinity, alignment: .leading) }
                .navigationTitle("نتيجة التسميع")
                .toolbar { Button("متابعة القراءة") { dismiss() }.accessibilityIdentifier("study.result.close") }
        }
    }
}

struct MushafRecordingList: View {
    let session: UUID
    @ObservedObject var recorder: MushafSessionRecorder
    @Environment(\.dismiss) private var dismiss
    @State private var takes: [MushafRecordingTake] = []
    @State private var loadError: String?
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("التسجيلات محفوظة على هذا الجهاز. استمع إلى المقاطع أو احفظ نسخة منها.").font(.footnote)
                    if takes.isEmpty { Text(loadError ?? "لا يوجد تسجيل قابل للتشغيل لهذه الجلسة.") }
                }
                ForEach(takes) { take in
                    Section {
                        Text(take.date, style: .date).font(.headline)
                        Text("المدة: \(MushafAudioTime.text(take.duration))").environment(\.layoutDirection, .leftToRight)
                        Button {
                            if recorder.playing == take.id { recorder.stop() } else { recorder.play(take) }
                        } label: {
                            Label(recorder.playing == take.id ? "إيقاف المقطع" : "استماع إلى المقطع", systemImage: recorder.playing == take.id ? "stop.fill" : "play.fill")
                                .frame(minHeight: 44).contentShape(Rectangle())
                        }.accessibilityIdentifier("study.recording.play.\(take.id.uuidString)")
                        ShareLink(item: take.url) {
                            Label("حفظ أو مشاركة ملف الصوت", systemImage: "square.and.arrow.up").frame(minHeight: 44)
                        }
                    }
                }
                Section {
                    Text("المقاطع التي انقطعت قبل اكتمالها تبقى محفوظة على الجهاز. تعرض هذه القائمة الملفات التي يمكن تشغيلها فقط.").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("تسجيلات الجلسة")
            .toolbar { Button("العودة للمصحف") { recorder.stop(); dismiss() }.accessibilityIdentifier("study.recordings.close") }
            .task {
                do { takes = try MushafRecordingArchive.takes(session: session) }
                catch { loadError = "تعذّر قراءة قائمة التسجيلات. احتُفظ بالملفات الأصلية؛ أعد المحاولة بعد فتح قفل الجهاز." }
            }
            .onDisappear { recorder.stop() }
            .alert("تشغيل التسجيل", isPresented: Binding(get: { recorder.message != nil }, set: { if !$0 { recorder.message = nil } })) {
                Button("حسنًا") { recorder.message = nil }
            } message: { Text(recorder.message ?? "") }
        }
    }
}

enum MushafAudioTime {
    static func text(_ seconds: TimeInterval) -> String {
        let whole = seconds.isFinite ? Int(max(0, min(seconds, Double(Int.max / 2)))) : 0
        return "\(whole / 60):" + String(format: "%02d", whole % 60)
    }
}

/// Durable access to finished sessions, independent of the latest summary.
struct MushafRecordingBrowser: View {
    @StateObject private var recorder = MushafSessionRecorder()
    @State private var sessions: [MushafRecordingSessionRow] = []
    @State private var selected: UUID?
    @State private var opened = false
    @State private var error: String?
    var body: some View {
        List {
            Section {
                Text("تسجيلات التسميع المحلية؛ لا تُرفع للحساب ولا تُستخدم لتقييم النطق أو التجويد.").font(.footnote)
                if sessions.isEmpty { Text(error ?? "لم تُحفظ تسجيلات تسميع بعد.") }
            }
            ForEach(sessions) { session in
                Button {
                    selected = session.id; opened = true
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(session.date, style: .date)
                        if let metadata = session.metadata {
                            Text("من \(metadata.keys.first ?? "") إلى \(metadata.keys.last ?? "") · \(metadata.keys.count) آية")
                                .font(.footnote).foregroundStyle(.secondary)
                        } else { Text("تسجيل محفوظ · تعذّر قراءة معلومات الجلسة").font(.footnote) }
                    }.frame(minHeight: 44).contentShape(Rectangle())
                }.accessibilityIdentifier("study.recording.session.\(session.id.uuidString)")
            }
        }
        .navigationTitle("تسجيلات التسميع")
        .task {
            do { sessions = try MushafRecordingArchive.sessions() }
            catch { self.error = "تعذّر قراءة التسجيلات الآن. احتُفظ بالملفات الأصلية؛ حاول بعد فتح قفل الجهاز." }
        }
        .sheet(isPresented: $opened) {
            if let selected { MushafRecordingList(session: selected, recorder: recorder) }
        }
        .onDisappear { recorder.stop() }
    }
}
