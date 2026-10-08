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
                            if pending.phase == .finishing { _ = memorization.finishMushafStudy() }
                            else { onOpen(); dismiss() }
                        }.accessibilityIdentifier("study.resume")
                        Text("يمكنك إنهاء الجلسة من المصحف قبل بدء جلسة أخرى؛ لن تُستبدل خطة الحفظ السابقة.").font(.footnote)
                    }
                } else if memorization.unreadableMushafStudyData != nil {
                    Section { Text("تعذّر قراءة الجلسة المحفوظة. احتُفظ بالبيانات الأصلية، ويمكن تصديرها من الإعدادات؛ لن نستبدلها بجلسة جديدة.") }
                } else {
                    Section("اختر المقطع") {
                        Picker("نوع المقطع", selection: $scope) {
                            Text("صفحة").tag(MushafStudySession.Scope.page)
                            Text("سورة").tag(MushafStudySession.Scope.surah)
                            Text("نطاق آيات").tag(MushafStudySession.Scope.range)
                        }.accessibilityIdentifier("study.scope")
                        if scope == .page {
                            Text("الصفحة \(page) · \(pageKeys.count) آية")
                            Text("تشمل الآيات كاملة، بما فيها الآية التي تبدأ أو تنتهي في الصفحة المجاورة.").font(.footnote)
                        } else {
                            Picker("السورة", selection: $chapter) {
                                ForEach(store.quran) { surah in Text(surah.name).tag(surah.number) }
                            }.accessibilityIdentifier("study.chapter")
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
