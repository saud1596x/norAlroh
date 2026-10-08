import SwiftUI
import AVFoundation

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
    @State private var showingDeleted = false
    @State private var sessionTitle = ""
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !sessionTitle.isEmpty { Text(verbatim: sessionTitle).font(.title3.bold()).accessibilityIdentifier("study.recordings.range") }
                    if takes.isEmpty {
                        ContentUnavailableView(showingDeleted ? "لا توجد مقاطع محذوفة" : "لا يوجد صوت قابل للتشغيل", systemImage: "waveform",
                            description: Text(loadError ?? (showingDeleted ? "المقاطع المحذوفة قابلة للاستعادة هنا." : "لم يُحفظ تسجيل قابل للتشغيل لهذه الجلسة.")))
                    }
                    ForEach(Array(takes.enumerated()), id: \.element.id) { index, take in
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Image(systemName: "waveform").foregroundStyle(Theme.gold).accessibilityHidden(true)
                                Text("المقطع \(index + 1)").font(.headline)
                                Spacer()
                                ShareLink(item: take.url) {
                                    Image(systemName: "square.and.arrow.up").frame(width: 44, height: 44)
                                }.accessibilityLabel("مشاركة المقطع \(index + 1)")
                            }
                            Text(verbatim: MushafAudioTime.date(take.date)).font(.caption).foregroundStyle(.secondary)
                            if recorder.playing == take.id {
                                TimelineView(.periodic(from: .now, by: 0.25)) { context in
                                    VStack(spacing: 8) {
                                        Slider(value: Binding(get: { recorder.playbackPosition },
                                            set: { recorder.seekPlayback(to: $0) }),
                                            in: 0...max(0.01, recorder.playbackDuration))
                                            .frame(minHeight: 44)
                                            .accessibilityLabel("موضع تشغيل التسجيل")
                                            .accessibilityIdentifier("study.recording.seek")
                                        HStack {
                                            Text(MushafAudioTime.text(recorder.playbackPosition))
                                            Spacer()
                                            Text(MushafAudioTime.text(recorder.playbackDuration))
                                        }.font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                    }.environment(\.layoutDirection, .leftToRight)
                                        .onChange(of: context.date) { _, _ in recorder.refreshPlaybackPosition() }
                                }
                            } else {
                                Text(MushafAudioTime.text(take.duration)).font(.caption.monospacedDigit())
                                    .environment(\.layoutDirection, .leftToRight)
                            }
                            if showingDeleted {
                                Button { move(take, deleted: false) } label: {
                                    Label("استعادة المقطع", systemImage: "arrow.uturn.backward")
                                        .frame(maxWidth: .infinity, minHeight: 44)
                                }.buttonStyle(.borderedProminent).tint(Theme.gold)
                                    .accessibilityIdentifier("study.recording.restore.\(take.id.uuidString)")
                            } else { HStack(spacing: 16) {
                                Button {
                                    if recorder.playing != take.id { recorder.play(take) }
                                    else if recorder.playbackPaused { recorder.resumePlayback() }
                                    else { recorder.pausePlayback() }
                                } label: {
                                    Label(recorder.playing == take.id && !recorder.playbackPaused ? "إيقاف مؤقت" : "استماع",
                                        systemImage: recorder.playing == take.id && !recorder.playbackPaused ? "pause.fill" : "play.fill")
                                        .frame(maxWidth: .infinity, minHeight: 44)
                                }.buttonStyle(.borderedProminent).tint(Theme.gold)
                                    .accessibilityIdentifier("study.recording.play.\(take.id.uuidString)")
                                Button { recorder.play(take) } label: {
                                    Image(systemName: "arrow.counterclockwise").frame(width: 44, height: 44)
                                }.accessibilityLabel("إعادة المقطع من البداية")
                                    .accessibilityIdentifier("study.recording.replay.\(take.id.uuidString)")
                                Menu {
                                    Button("نقل إلى المحذوفات", systemImage: "trash") { move(take, deleted: true) }
                                } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                                    .accessibilityLabel("خيارات المقطع")
                                    .accessibilityIdentifier("study.recording.options.\(take.id.uuidString)")
                            } }
                        }
                        .padding(20).background(Theme.panel, in: RoundedRectangle(cornerRadius: 24))
                    }
                }.padding(20)
            }
            .navigationTitle("تسجيلات الجلسة")
            .toolbar { Button("إغلاق") { recorder.stop(); dismiss() }.accessibilityIdentifier("study.recordings.close") }
            .toolbar {
                ToolbarItem(placement: .bottomBar) {
                    Button(showingDeleted ? "عرض التسجيلات" : "المقاطع المحذوفة") {
                        recorder.stop(); showingDeleted.toggle(); reload()
                    }.frame(minHeight: 44).accessibilityIdentifier("study.recordings.deleted")
                }
            }
            .task {
                sessionTitle = (try? MushafRecordingArchive.metadata(session: session))?.title ?? ""
                reload()
            }
            .onDisappear { recorder.stop() }
            .onChange(of: scenePhase) { _, phase in if phase != .active { recorder.pausePlayback() } }
            .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { _ in recorder.pausePlayback() }
            .alert("تشغيل التسجيل", isPresented: Binding(get: { recorder.message != nil }, set: { if !$0 { recorder.message = nil } })) {
                Button("حسنًا") { recorder.message = nil }
            } message: { Text(recorder.message ?? "") }
        }
    }
    private func reload() {
        do {
            takes = try showingDeleted ? MushafRecordingArchive.deletedTakes(session: session) : MushafRecordingArchive.takes(session: session)
            loadError = nil
        } catch { loadError = "تعذّر قراءة قائمة التسجيلات. احتُفظ بالملفات الأصلية؛ أعد المحاولة بعد فتح قفل الجهاز." }
    }
    private func move(_ take: MushafRecordingTake, deleted: Bool) {
        if recorder.playing == take.id { recorder.stop() }
        do { try MushafRecordingArchive.moveAudio(take, toDeleted: deleted); reload() }
        catch { recorder.message = "تعذّر نقل المقطع. لم يُستبدل الصوت أو سجل الجلسة." }
    }
}

enum MushafAudioTime {
    static func text(_ seconds: TimeInterval) -> String {
        let whole = seconds.isFinite ? Int(max(0, min(seconds, Double(Int.max / 2)))) : 0
        return "\(whole / 60):" + String(format: "%02d", whole % 60)
    }
    static func date(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "ar_SA")
        formatter.calendar = Calendar(identifier: .gregorian); formatter.timeZone = .current
        formatter.dateFormat = "d MMMM yyyy · HH:mm"
        return formatter.string(from: date).map { character in
            character.wholeNumberValue.map(String.init) ?? String(character)
        }.joined()
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
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                if sessions.isEmpty {
                    ContentUnavailableView("تسجيلاتك", systemImage: "waveform",
                        description: Text(error ?? "بعد جلسة التسميع، تجد صوتك محفوظًا هنا."))
                }
                ForEach(sessions) { session in
                Button {
                    selected = session.id; opened = true
                } label: {
                    HStack(spacing: 16) {
                        Image(systemName: "waveform").font(.title2).foregroundStyle(Theme.gold)
                            .frame(width: 48, height: 48).background(Theme.gold.opacity(0.08), in: Circle()).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 8) {
                            Text(verbatim: session.metadata?.title ?? "تسجيل محفوظ · معلومات الجلسة غير متاحة").font(.headline)
                            Text(verbatim: MushafAudioTime.date(session.date)).font(.caption).foregroundStyle(.secondary)
                            Text(verbatim: session.takeCount == 0
                                ? (session.recoverableDeleted ? "مقاطع محذوفة قابلة للاستعادة" : "لا يوجد صوت قابل للتشغيل")
                                : "\(session.takeCount) مقاطع · \(MushafAudioTime.text(session.duration))")
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.left").font(.caption).foregroundStyle(.secondary).accessibilityHidden(true)
                    }.padding(20).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 24)).contentShape(Rectangle())
                }.buttonStyle(NoorPressStyle()).accessibilityIdentifier("study.recording.session.\(session.id.uuidString)")
                }
            }.padding(20)
        }.background(Theme.background)
        .navigationTitle("تسجيلات التسميع")
        .task { reloadSessions() }
        .sheet(isPresented: $opened, onDismiss: reloadSessions) {
            if let selected { MushafRecordingList(session: selected, recorder: recorder) }
        }
        .onDisappear { recorder.stop() }
    }
    private func reloadSessions() {
        do { sessions = try MushafRecordingArchive.sessions(); error = nil }
        catch { self.error = "تعذّر قراءة التسجيلات الآن. احتُفظ بالملفات الأصلية؛ حاول بعد فتح قفل الجهاز." }
    }
}
