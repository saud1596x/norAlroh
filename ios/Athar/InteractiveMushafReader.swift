import SwiftUI
import UIKit
import Combine

@MainActor final class MushafTafsir: ObservableObject {
    struct Envelope: Decodable { let result: Result }
    struct Result: Codable { let sura: String; let aya: String; let translation: String }
    struct Cached: Codable { let date: Date; let value: Result }
    @Published var text: String?
    @Published var error: String?
    private var request: UUID?
    func load(chapter: Int, ayah: Int) async {
        let token = UUID(); request = token; text = nil; error = nil
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("mushaf-tafsir", isDirectory: true)
        let file = directory.appendingPathComponent("\(chapter)-\(ayah).json")
        func valid(_ value: Result) -> Bool { Int(value.sura) == chapter && Int(value.aya) == ayah && !value.translation.isEmpty && value.translation.utf8.count < 100_000 }
        let saved = (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode(Cached.self, from: $0) }
        if let saved, valid(saved.value), Date().timeIntervalSince(saved.date) < 604800 { text = saved.value.translation; return }
        do {
            let url = URL(string: "https://quranenc.com/api/v1/translation/aya/arabic_moyassar/\(chapter)/\(ayah)")!
            let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 25))
            guard let http = response as? HTTPURLResponse, http.statusCode == 200, data.count < 200_000 else { throw URLError(.badServerResponse) }
            let value = try JSONDecoder().decode(Envelope.self, from: data).result
            guard valid(value) else { throw URLError(.cannotParseResponse) }
            guard request == token else { return }
            text = value.translation
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(Cached(date: Date(), value: value)).write(to: file, options: .atomic)
        } catch {
            guard request == token else { return }
            if let saved, valid(saved.value) { text = saved.value.translation }
            else { self.error = "تعذّر تنزيل التفسير. اتصل بالإنترنت وحاول مرة أخرى؛ يُحفظ التفسير بعد فتحه للقراءة دون اتصال." }
        }
    }
}

/// Consumes the original entry only when reading resources are ready. Failed
/// loads remain retryable; a dismissed reader must never start its old intent.
struct MushafInitialEntry {
    enum Action: Equatable { case scope, study }
    private(set) var consumed = false
    mutating func cancel() { consumed = true }
    mutating func consume(requestScope: Bool, startStudy: Bool, ready: Bool,
                          visible: Bool, cancelled: Bool) -> Action? {
        guard !consumed, ready, visible, !cancelled else { return nil }
        guard requestScope || startStudy else { return nil }
        consumed = true
        return requestScope ? .scope : .study
    }
}

enum MushafReaderInsets {
    /// Ordinary chrome visibility never changes the reading coordinate space.
    /// Only the explicit expanded-reading mode may reclaim the control lanes.
    static func reserved(_ measured: CGFloat?, minimum: CGFloat, visible: Bool = true,
                         fullScreen: Bool = false) -> CGFloat {
        guard !fullScreen else { return 0 }
        guard let measured, measured.isFinite, measured > 0 else { return minimum }
        return max(minimum, measured)
    }
}
struct MushafRenderIdentity {
    let page: Int
    let generation: UUID
    func isCurrent(page currentPage: Int, generation currentGeneration: UUID) -> Bool {
        page == currentPage && generation == currentGeneration
    }
}

/// A verified font may arrive after live following, selection or a newer turn.
/// A late manual request never owns that newer reading position, even if the
/// user has since returned to the same numbered page.
struct MushafPageTurnCoordinator {
    struct Request: Equatable {
        let id = UUID()
        let source: Int
        let destination: Int
    }
    private(set) var pending: Request?
    mutating func begin(from source: Int, to destination: Int) -> Request {
        let value = Request(source: source, destination: destination)
        pending = value
        return value
    }
    mutating func cancel() { pending = nil }
    mutating func consume(_ request: Request, currentPage: Int,
                          visible: Bool, playbackLocked: Bool) -> Int? {
        guard pending == request, currentPage == request.source,
              visible, !playbackLocked else { return nil }
        pending = nil
        return request.destination
    }
}

/// Equal side reservations keep the title on the page axis even when one side
/// contains both the reciter and Stop. Ordinary HStack spacers center it only
/// between the unequal buttons, which visibly shifts the title to one side.
struct MushafCenteredHeader: Layout {
    private func dimensions(_ proposal: ProposedViewSize, _ subviews: Subviews) -> (CGFloat, CGFloat, CGFloat) {
        let ideal = subviews.map { $0.sizeThatFits(.unspecified) }
        let idealWidth = ideal.reduce(CGFloat.zero) { $0 + $1.width }
        let width = proposal.width.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil } ?? idealWidth
        let side = min(max(ideal[0].width, ideal[2].width), max(0, (width - 44) / 2))
        let widths = [side, max(0, width - 2 * side), side]
        let height = subviews.indices.map {
            subviews[$0].sizeThatFits(ProposedViewSize(width: widths[$0], height: nil)).height
        }.max() ?? 44
        return (width, side, max(44, height))
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let (width, _, height) = dimensions(proposal, subviews)
        return CGSize(width: width, height: height)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let (_, side, _) = dimensions(ProposedViewSize(width: bounds.width, height: bounds.height), subviews)
        // SwiftUI mirrors custom layout coordinates for RTL. Compute the
        // logical left-to-right slots once rather than mirroring them twice.
        subviews[0].place(at: CGPoint(x: bounds.minX, y: bounds.midY), anchor: .leading,
                          proposal: ProposedViewSize(width: side, height: bounds.height))
        subviews[1].place(at: CGPoint(x: bounds.midX, y: bounds.midY), anchor: .center,
                          proposal: ProposedViewSize(width: max(0, bounds.width - 2 * side), height: bounds.height))
        subviews[2].place(at: CGPoint(x: bounds.maxX, y: bounds.midY), anchor: .trailing,
                          proposal: ProposedViewSize(width: side, height: bounds.height))
    }
}

struct InteractiveMushafReader: View {
    @EnvironmentObject private var store: AtharStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduced
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @StateObject private var fonts = MushafFonts()
    @StateObject private var audio: MushafVerseAudio = {
        #if DEBUG || NOOR_ACCEPTANCE_TESTING
        if ProcessInfo.processInfo.arguments.contains("-NoorAcceptanceUnavailableVerseAudio") {
            // Exercise real AVPlayer failure, never a staged successful result.
            let unavailable = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp3")
            return MushafVerseAudio(source: { _ in unavailable })
        }
        #endif
        return MushafVerseAudio()
    }()
    let chapter: Int; let ayah: Int; let initialPage: Int?
    let readingScope: KhatmahReadingScope?
    private var readingOnly: Bool { readingScope != nil }
    // Manual navigation is locked throughout this reader's playback sequence,
    // including buffering, pauses and repeat gaps. Canonical playback callbacks
    // can still advance the page; Stop releases the lock immediately.
    private var playbackLocksPage: Bool {
        reciterPreparation != nil || audio.playing != nil || audio.loadingKey != nil || audio.waitingKey != nil
    }
    @ObservedObject private var readingJourney = KhatmahStore.shared
    @State private var wardComplete = false
    private var allowedPages: ClosedRange<Int> { readingScope?.pages ?? 1...604 }
    init(chapter: Int, ayah: Int, initialPage: Int?, readingScope: KhatmahReadingScope? = nil) {
        self.chapter = chapter; self.ayah = ayah; self.initialPage = initialPage
        self.readingScope = readingScope
    }
    @State private var snapshot: QCFV2Snapshot?
    @State private var rows: OriginalMushafRows?
    @State private var pageIndex: [Int: OriginalPageData] = [:]
    @State private var number = 1
    @State private var pageTurns = MushafPageTurnCoordinator()
    @State private var pageTurnTask: Task<Void, Never>?
    @State private var reciterPreparation: Task<Void, Never>?
    @State private var reciterRequest = UUID()
    private struct ReciterPlaybackStart {
        let identity: String
        let seconds: Double
    }
    @State private var reciterPlaybackStart: ReciterPlaybackStart?
    @State private var selected: String?
    @State private var manualSelection: VerseSelection?
    @State private var sheetVerse: VerseSelection?
    @State private var sheetAction = VerseToolAction.details
    @State private var tools = true
    @State private var fullScreenReading = false
    @ScaledMetric(relativeTo: .caption) private var readerCaptionLineHeight: CGFloat = 16
    private var readerDockHeight: CGFloat { max(86, 22 + 8 + 2 * readerCaptionLineHeight + 16) }
    @State private var readerActionsOpen = false
    private enum ReaderAction { case khatmah, fullScreen }
    @State private var pendingReaderAction: ReaderAction?
    @State private var recitersOpen = false
    @ObservedObject private var audioFocus = NoorAudioFocus.shared
    @AppStorage("noor.mushaf.reciter") private var preferredReciter = "surah:74:74"
    @State private var controlHeights: [String: CGFloat] = ["header": 44, "footer": 86]
    @State private var khatmah = false
    @State private var khatmahStopMessage: String?
    @State private var picker = false
    @FocusState private var pageInputFocused: Bool
    @State private var needsFirstDownload = false
    @State private var input = ""
    @State private var error: String?
    @State private var renderingFailed = false
    @State private var renderGeneration = UUID()
    @State private var studyIndex: MushafStudyWordIndex?
    @State private var readerVisible = false
    @State private var retryingReader = false
    #if DEBUG || NOOR_ACCEPTANCE_TESTING
    @State private var acceptanceRenderFailureRecovered = false
    #endif
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("noor.mushaf.lastPage") private var lastPage = 1
    @AppStorage("noor.mushaf.followAudio") private var followAudio = true
    private var keys: [String] { store.quran.flatMap { s in s.ayahs.map { "\(s.number):\($0.number)" } } }
    private var page: OriginalPageData? {
        pageIndex[number]
    }
    // The visible selection owns both the toolbar and canvas. A playback
    // callback must never silently replace the verse whose tools are open.
    private var visibleSelection: String? {
        let key = manualSelection?.key ?? selected
        return page?.words.contains(where: { $0.verse == key }) == true ? key : nil
    }
    var body: some View {
        presentedReader
        .onChange(of: audio.error) { _, value in
            if value != nil { reciterPlaybackStart = nil }
        }
        .onChange(of: audio.playing) { _, value in
            if value != nil { followPlayback() }
        }
        .onChange(of: audio.activeWordID) { _, word in
            // Silence between timed words must not send a split ayah back
            // to its first page. The next real word supplies its own page.
            if word != nil { followPlayback() }
        }
        .onChange(of: audio.activeVerseKey) { _, _ in followPlayback() }
        .onChange(of: playbackLocksPage) { _, locked in
            if locked { cancelPageTurn(); picker = false; pageInputFocused = false; followAudio = true; followPlayback() }
        }
        .alert("التلاوة", isPresented: Binding(
            get: { audio.error != nil },
            set: { if !$0 { audio.error = nil } })) {
            Button("حسنًا", role: .cancel) { audio.error = nil }
        } message: { Text(audio.error ?? "") }
    }
    private var initializedReader: some View {
        readerSurface
        .statusBarHidden(true)
        .toolbar(.hidden, for: .navigationBar, .tabBar)
        .onPreferenceChange(ReaderControlHeight.self) { heights in
            for (key, height) in heights where height.isFinite && height > 0 {
                if abs((controlHeights[key] ?? 0) - height) > 0.5 { controlHeights[key] = height }
            }
        }
        .transaction { transaction in
            if reduced || store.data.lowMotion { transaction.disablesAnimations = true }
        }
        .task {
            await load()
            injectAcceptanceRenderFailureIfNeeded()
        }
        .onAppear {
            readerVisible = true
            if let reciter = NoorMushafReciter.selected(preferredReciter) ?? NoorMushafReciter.all.first {
                if preferredReciter != reciter.id { preferredReciter = reciter.id }
                audio.selectReciter(reciter)
            }
        }
    }
    private var activeReader: some View {
        initializedReader
        .sheet(isPresented: $recitersOpen) {
            NoorMushafReciterPicker(selectedID: preferredReciter) { reciter in
                chooseAndPlayReciter(reciter)
            }
        }
        .task(id: number) {
            let requestedPage = number
            renderingFailed = false
            await fonts.load(String(format: "QCF2%03d", requestedPage))
            guard !Task.isCancelled, requestedPage == number else { return }
            injectAcceptanceRenderFailureIfNeeded()
            await fonts.prepareNeighbors(of: requestedPage)
        }
        .onDisappear { rememberWardPosition(); readerVisible = false; cancelPageTurn(); cancelReciterPreparation(); audio.stop(); audio.onVerse = nil }
        .onChange(of: scenePhase) { _, value in
            if value != .active { cancelReciterPreparation() }
            if value == .background { rememberWardPosition() }
        }
        .onChange(of: number) { _, value in
            cancelPageTurn()
            cancelReciterPreparation()
            guard allowedPages.contains(value) else { number = min(allowedPages.upperBound, max(allowedPages.lowerBound, value)); return }
            renderGeneration = UUID(); lastPage = value; rememberWardPosition()
        }
        .alert("أتممت ورد اليوم", isPresented: $wardComplete) {
            Button("العودة للرئيسية") { dismiss() }
        } message: { Text(readingJourney.active?.finished != nil ? "حُفظت قراءتك وأتممت الختمة." : "حُفظ تقدمك. ستكمل غدًا من الصفحة التالية حسب مقدار وردك.") }
    }
    private var verseToolsReader: some View {
        activeReader
        .sheet(item: $sheetVerse, onDismiss: { clearManualSelection(); followPlayback() }) { selection in
            VerseTools(selection: selection, audio: audio, selected: $selected, initialAction: sheetAction, readingOnly: readingOnly)
                .presentationDragIndicator(.visible)
        }
        .alert("موضع الختمة", isPresented: Binding(get: { khatmahStopMessage != nil }, set: { if !$0 { khatmahStopMessage = nil } })) {
            Button("تم") { khatmahStopMessage = nil }
            if KhatmahStore.shared.active == nil {
                Button("ابدأ ختمة") { khatmahStopMessage = nil; khatmah = true }
            }
        } message: { Text(khatmahStopMessage ?? "") }
        .sheet(isPresented: $khatmah) {
            NavigationStack {
                if KhatmahStore.shared.active == nil {
                    KhatmahSetupView(existing: nil, currentPage: number)
                } else {
                    KhatmahJourneyView(currentPage: number)
                }
            }
        }
    }
    private var presentedReader: some View {
        verseToolsReader
        .sheet(isPresented: $picker, onDismiss: { pageInputFocused = false }) {
            NavigationStack { Form {
                TextField("\(allowedPages.lowerBound) إلى \(allowedPages.upperBound)", text: $input).keyboardType(.numberPad)
                    .focused($pageInputFocused).accessibilityIdentifier("reader.pageNumber")
                Button("انتقل") {
                    let requested = ArabicSearch.integer(input)
                    #if NOOR_ACCEPTANCE_TESTING
                    // Test-only numeric metadata distinguishes a missed action
                    // from rejected input without logging text or user audio.
                    NSLog("NOOR_PAGE_SUBMIT entered length=%ld parsed=%ld lower=%ld upper=%ld focused=%d visible=%d",
                          input.count, requested ?? -1, allowedPages.lowerBound, allowedPages.upperBound,
                          pageInputFocused ? 1 : 0, picker ? 1 : 0)
                    #endif
                    if let value = requested, allowedPages.contains(value) {
                        pageInputFocused = false; turn(value - number); picker = false
                    }
                    #if NOOR_ACCEPTANCE_TESTING
                    NSLog("NOOR_PAGE_SUBMIT settled focused=%d visible=%d",
                          pageInputFocused ? 1 : 0, picker ? 1 : 0)
                    #endif
                }
            }.navigationTitle("الانتقال في المصحف").toolbar {
                Button("إغلاق") { pageInputFocused = false; picker = false }
            } }
        }
    }
    private var readerSurface: some View {
        ZStack {
            Theme.panel.ignoresSafeArea()
            readerPage
            // Explicit full screen releases its control lanes altogether. The
            // options sheet's anchor can otherwise remain in accessibility
            // despite the enclosing lane's opacity and accessibility hiding.
            // This mode starts in the options sheet's onDismiss, after its
            // presentation closes; a canvas tap restores the same controls.
            if !fullScreenReading {
            // Keep the ordinary lanes measured while hidden or recording. A
            // status change must not resize the production Quran viewport.
            VStack {
                MushafCenteredHeader {
                    HStack(spacing: 0) {
                    if manualSelection != nil {
                        Button { clearManualSelection() } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                            .accessibilityLabel("إلغاء تحديد الآية").accessibilityIdentifier("verse.tools.close")
                    } else {
                        Button { dismiss() } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }.accessibilityLabel("إغلاق المصحف")
                    }
                    }
                    readerHeaderTitle
                    readerHeaderSideLayout {
                    if manualSelection == nil && !readingOnly {
                        Button { recitersOpen = true } label: {
                            Label("القارئ", systemImage: "headphones")
                                .labelStyle(.iconOnly).font(.system(size: 22, weight: .medium))
                                .frame(width: 44, height: 44)
                        }.accessibilityLabel("اختر القارئ").accessibilityIdentifier("reader.reciters")
                            .accessibilityValue(audio.selectedCatalogReciter?.name ?? audio.displayName)
                    }
                    if let selection = manualSelection {
                        Button { openTools(selection, action: .details) } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                            .accessibilityLabel("المزيد من أدوات الآية").accessibilityIdentifier("verse.more")
                    } else if reciterPreparation != nil {
                        Button { cancelReciterPreparation() } label: { ProgressView().frame(width: 44, height: 44) }
                            .accessibilityLabel("إلغاء تجهيز التلاوة").accessibilityIdentifier("reader.audio.preparing")
                    } else if audioFocus.activePlayer != nil || audio.playing != nil || audio.waitingKey != nil { Button { cancelReciterPreparation(); audio.stop(); audioFocus.activePlayer?.stop() } label: { Image(systemName: "stop.fill").frame(width: 44, height: 44) }.accessibilityLabel(audio.waitingKey == nil ? "إيقاف التلاوة" : "إيقاف التكرار أثناء المهلة").accessibilityIdentifier("reader.audio.stop") }
                    else if audio.loadingKey != nil {
                        Button { cancelReciterPreparation(); audio.stop() } label: { ProgressView().frame(width: 44, height: 44) }.accessibilityLabel("إلغاء تحميل التلاوة")
                    } else if readingOnly {
                        Button { khatmah = true } label: { Image(systemName: "book.closed").frame(width: 44, height: 44) }
                            .accessibilityLabel("رحلة الختمة وتأكيد القراءة").accessibilityIdentifier("reader.khatmah")
                    }
                    }
                }
                // Two 44-point side actions need 96 points when stacked at
                // accessibility sizes. Reserve it even without Stop/selection,
                // so those state changes never refit the Quran underneath.
                .frame(minHeight: dynamicTypeSize.isAccessibilitySize ? 96 : 44)
                .background { readerControlMeasurement("header") }
                Spacer()
                VStack(spacing: 0) {
                    VStack(spacing: 0) {
                        pageNavigationControls
                    }
                    .frame(minHeight: readerDockHeight)
                    .opacity(manualSelection == nil ? 1 : 0)
                    .allowsHitTesting(manualSelection == nil)
                    .accessibilityHidden(manualSelection != nil)
                    .overlay(alignment: .bottom) {
                        if let selection = manualSelection { verseActions(selection) }
                    }
                    wardControls
                }.background { readerControlMeasurement("footer") }
            }.padding(.horizontal, 10)
                .opacity(tools ? 1 : 0)
                .allowsHitTesting(tools)
                .accessibilityHidden(!tools)
            }
        }
    }
    private var readerHeaderSideLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 8))
            : AnyLayout(HStackLayout(spacing: 8))
    }
    private var readerHeaderTitle: some View {
        ZStack {
            Button { input = ""; picker = true } label: {
                VStack(spacing: 0) {
                    Text(audio.waitingKey == nil ? title : "مهلة التكرار · \(title)")
                        .font(.headline).lineLimit(1).accessibilityIdentifier("reader.title")
                    Text("\(ArabicSearch.digits(number)) / ٦٠٤").font(.caption).monospacedDigit().lineLimit(1)
                }.frame(minHeight: 44).contentShape(Rectangle())
            }.buttonStyle(.plain)
                .accessibilityIdentifier("reader.jump")
                .accessibilityLabel("الصفحة \(ArabicSearch.digits(number)) من ٦٠٤")
                .disabled(playbackLocksPage || manualSelection != nil)
                .opacity(manualSelection == nil ? 1 : 0)
                .accessibilityHidden(manualSelection != nil)
            if let selection = manualSelection {
                Text("\(title) · الآية \(ArabicSearch.digits(selection.ayah))")
                    .font(.headline).lineLimit(1)
                    .accessibilityIdentifier("verse.tools.title")
                    .accessibilityValue(selection.key)
            }
        }
    }
    private var readerPage: some View {
            GeometryReader { geometry in
                if let page, fonts.names[String(format: "QCF2%03d", number)] != nil, !renderingFailed {
                    let renderedIdentity = MushafRenderIdentity(page: page.number, generation: renderGeneration)
                    OriginalMushafDrawing(page: page, corpus: store.quran, selected: visibleSelection, reduceMotion: reduced || store.data.lowMotion,
                        hiddenWordIDs: [],
                        reviewWordIDs: [],
                        activeWordID: audio.activeWordID,
                        tajweedEnabled: false,
                        pageRange: allowedPages,
                        allowsManualPageTurns: !playbackLocksPage,
                        allowsVerseSelection: true,
                        // Fit the complete page instead of automatically zooming
                        // past its edges. The larger-text preference uses a little
                        // less side padding while preserving the authored layout.
                        readingMagnification: 1,
                        onVerse: { key in
                            cancelPageTurn()
                            if let key {
                                audio.stop()
                                fullScreenReading = false
                                selected = key; manualSelection = VerseSelection(key: key)
                                withAnimation(reduced || store.data.lowMotion ? nil : .easeInOut(duration: 0.18)) { tools = true }
                            }
                        }, onFailure: { DispatchQueue.main.async {
                            guard renderedIdentity.isCurrent(page: number, generation: renderGeneration) else { return }
                            renderingFailed = true
                        } }, onTurn: { turn($0) },
                        onToggleTools: {
                            if manualSelection != nil { clearManualSelection() }
                            else if fullScreenReading { fullScreenReading = false; tools = true }
                            else { withAnimation(reduced || store.data.lowMotion ? nil : .easeInOut(duration: 0.18)) { tools.toggle() } }
                        })
                        // The authored canvas already contains its side margins.
                        // Do not shrink it again with a second horizontal inset.
                        .padding(.top, reservedReaderInset("header", minimum: 44))
                        .padding(.bottom, reservedReaderInset("footer", minimum: 60))
                        .accessibilityAction(named: tools ? "إخفاء أدوات المصحف" : "إظهار أدوات المصحف") {
                            if fullScreenReading { fullScreenReading = false; tools = true }
                            else { tools.toggle() }
                        }
                        .frame(width: geometry.size.width, height: geometry.size.height)
                } else if let message = error ?? fonts.error {
                    VStack(spacing: 18) { Text(message).accessibilityIdentifier("reader.load.error"); Button("إعادة المحاولة") { Task { await retryReader() } }.disabled(retryingReader).accessibilityIdentifier("reader.load.retry") }.padding().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if renderingFailed {
                    ContentUnavailableView {
                        Label("تعذّر فتح الصفحة", systemImage: "book.closed")
                    } description: {
                        Text("أعد فتح الصفحة. إذا استمرت المشكلة، تواصل مع الدعم مع ذكر رقم الصفحة.")
                    } actions: {
                        Button("إعادة المحاولة") { Task { await retryReader() } }
                            .disabled(retryingReader).accessibilityIdentifier("reader.render.retry")
                    }
                } else { ProgressView(needsFirstDownload ? "تنزيل بيانات المصحف لأول مرة…" : "فتح المصحف…")
                    .accessibilityIdentifier(needsFirstDownload ? "reader.downloading" : "reader.preparing")
                    .frame(maxWidth: .infinity, maxHeight: .infinity) }
            }
    }
    @ViewBuilder private var wardControls: some View {
                    if let scope = readingScope {
                        VStack(spacing: 4) {
                            Text("وردك · الصفحات \(ArabicSearch.digits(scope.first))–\(ArabicSearch.digits(scope.last))")
                                .font(.caption).accessibilityIdentifier("reader.ward.range")
                            Button(number == scope.last ? "أتممت ورد اليوم" : "أتممت القراءة حتى هذه الصفحة") {
                                if readingJourney.confirmReading(scope, through: number) {
                                    if number == scope.last { wardComplete = true }
                                    else { turn(1) }
                                }
                            }.frame(minHeight: 44).accessibilityIdentifier("reader.ward.confirm")
                                .disabled(page == nil || renderingFailed || fonts.names[String(format: "QCF2%03d", number)] == nil || readingJourney.active?.id != scope.planID || number < (readingJourney.active?.nextPage ?? 605))
                            if let message = readingJourney.error { Text(message).font(.caption).foregroundStyle(.red) }
                        }
                    }
    }
    private func retryReader() async {
        guard readerVisible, !retryingReader else { return }
        retryingReader = true; defer { retryingReader = false }
        #if DEBUG || NOOR_ACCEPTANCE_TESTING
        acceptanceRenderFailureRecovered = true
        #endif
        renderingFailed = false; tools = true
        await load()
    }
    private func injectAcceptanceRenderFailureIfNeeded() {
        #if DEBUG || NOOR_ACCEPTANCE_TESTING
        // This deliberately creates a negative UI state after loading real
        // resources. It tests access to recovery controls, not successful ink
        // rendering or the cause of a user's rendering/recognition failure.
        if ProcessInfo.processInfo.arguments.contains("-NoorAcceptanceReaderRenderFailure"),
           !acceptanceRenderFailureRecovered, snapshot != nil, error == nil,
           fonts.names[String(format: "QCF2%03d", number)] != nil {
            tools = false; renderingFailed = true
        }
        #endif
    }
    private func cancelReciterPreparation() {
        reciterRequest = UUID(); reciterPreparation?.cancel(); reciterPreparation = nil
        reciterPlaybackStart = nil
    }
    private func chooseAndPlayReciter(_ reciter: NoorMushafReciter) {
        cancelReciterPreparation(); cancelPageTurn()
        guard !readingOnly, readerVisible, scenePhase == .active, reciter.hasCompleteWordTracking,
              let recording = reciter.recording, let page, let studyIndex else { return }
        let chosenVerse = visibleSelection
        guard let word = page.words.first(where: { word in
            (chosenVerse == nil || chosenVerse == word.verse) && studyIndex.words[word.verse]?.contains(word.id) == true
        }) else { return }
        let verse = VerseSelection(key: word.verse)
        guard let surah = store.quran.first(where: { $0.number == verse.chapter }) else { return }
        preferredReciter = reciter.id
        audio.selectReciter(reciter)
        let request = reciterRequest, requestedPage = number
        reciterPreparation = Task {
            defer { if reciterRequest == request { reciterPreparation = nil } }
            let track = await NoorSurahWordTimings.shared.track(reciter: recording,
                surah: verse.chapter, ayahCount: surah.ayahs.count)
            guard !Task.isCancelled, readerVisible, scenePhase == .active,
                  reciterRequest == request, number == requestedPage,
                  preferredReciter == reciter.id, audio.selectedCatalogReciter?.id == reciter.id else { return }
            guard let seconds = track?.startOffset(wordID: word.id, verse: word.verse) else {
                audio.error = "تعذّر تجهيز التلاوة لهذا الموضع. أعد اختيار القارئ."; return
            }
            clearManualSelection(); tools = true; followAudio = true
            reciterPlaybackStart = .init(identity: reciter.recordingIdentity, seconds: seconds)
            audio.play([word.verse], seconds: seconds)
        }
    }
    private var readerOptionsButton: some View {
        Button { readerActionsOpen = true } label: {
            NoorReaderUtilityLabel(title: "المزيد", symbol: "ellipsis")
        }.buttonStyle(NoorReaderControlPressStyle()).accessibilityIdentifier("reader.more")
            .sheet(isPresented: $readerActionsOpen, onDismiss: {
                let action = pendingReaderAction; pendingReaderAction = nil
                switch action {
                case .khatmah: khatmah = true
                case .fullScreen: fullScreenReading = true; tools = false
                case nil: break
                }
            }) {
                NavigationStack {
                    List {
                        readerActionRow("الختمة وموضع التوقف", icon: "bookmark", action: .khatmah)
                        readerActionRow("قراءة بملء الشاشة", icon: "arrow.up.left.and.arrow.down.right", action: .fullScreen)
                    }
                    .navigationTitle("خيارات المصحف").navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("إغلاق") { readerActionsOpen = false }
                                .accessibilityIdentifier("reader.options.close")
                        }
                    }
                }.presentationDetents([.medium, .large])
            }
    }
    private func readerActionRow(_ title: String, icon: String, action: ReaderAction) -> some View {
        Button {
            pendingReaderAction = action; readerActionsOpen = false
        } label: {
            Label(title, systemImage: icon).frame(minHeight: 44)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private var pageNavigationControls: some View {
        HStack(spacing: 12) {
            pageTurnButton(1)
            if playbackLocksPage {
                Label("مع التلاوة · \(ArabicSearch.digits(number))", systemImage: "lock.fill")
                    .font(.caption).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("reader.playbackPageLock")
                    .accessibilityHint("أوقف التلاوة لتنتقل إلى صفحة أخرى")
            } else { readerOptionsButton.frame(maxWidth: .infinity) }
            pageTurnButton(-1)
        }.frame(maxWidth: .infinity)
    }
    private func pageTurnButton(_ amount: Int) -> some View {
        Button { turn(amount) } label: {
            Image(systemName: amount > 0 ? "chevron.right" : "chevron.left")
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(playbackLocksPage || !allowedPages.contains(number + amount))
        .accessibilityLabel(amount > 0 ? "الصفحة التالية" : "الصفحة السابقة")
        .accessibilityIdentifier(amount > 0 ? "reader.next" : "reader.previous")
        .accessibilityHint(playbackLocksPage ? "أوقف التلاوة لتنتقل إلى صفحة أخرى" : "")
    }
    private func reservedReaderInset(_ key: String, minimum: CGFloat) -> CGFloat {
        // Starting capture replaces the controls, not the authored Quran
        // viewport. Keep the ordinary controls' measured reservation; smaller
        // live controls and changing input hints cannot stretch/refit the page.
        let floor = key == "footer" ? max(minimum, readerDockHeight) : minimum
        return MushafReaderInsets.reserved(controlHeights[key], minimum: floor,
                                          visible: tools, fullScreen: fullScreenReading)
    }
    private func readerControlMeasurement(_ key: String) -> some View {
        GeometryReader { geometry in
            Color.clear.preference(key: ReaderControlHeight.self, value: [key: geometry.size.height])
        }
    }
    private var pageJumpControl: some View {
        Button { input = ""; picker = true } label: {
            Text("\(ArabicSearch.digits(number)) / ٦٠٤").font(.caption)
                .frame(minWidth: 70, minHeight: 44).contentShape(Rectangle())
        }.buttonStyle(.plain).foregroundStyle(Theme.gold)
            .disabled(playbackLocksPage)
            .accessibilityLabel("الصفحة \(ArabicSearch.digits(number)) من ٦٠٤")
            .accessibilityIdentifier("reader.jump")
    }
    private func clearManualSelection() {
        manualSelection = nil
        selected = audio.playing.flatMap { key in
            page?.words.contains(where: { $0.verse == key }) == true ? key : nil
        }
    }
    private func openTools(_ selection: VerseSelection, action: VerseToolAction) {
        sheetAction = action; sheetVerse = selection
    }
    private func verseActions(_ selection: VerseSelection) -> some View {
        // One scrollable control lane replaces the microphone lane. Six large
        // tiles must not expand over the Quran or refit it on selection.
        ScrollView(.horizontal) {
        HStack(spacing: 6) {
            verseAction("توقّف هنا للختمة", symbol: "bookmark.circle", identifier: "verse.khatmah.stop") {
                let journey = KhatmahStore.shared
                if journey.stop(page: number, chapter: selection.chapter, ayah: selection.ayah) {
                    khatmahStopMessage = "حُفظ موضعك عند الآية \(ArabicSearch.digits(selection.ayah)). حفظ الموضع لا يؤكد إتمام صفحات الورد."
                } else { khatmahStopMessage = journey.error }
            }
            verseAction("تفسير الآية", symbol: "book", identifier: "verse.tafsir") { openTools(selection, action: .tafsir) }
            if !readingOnly { verseAction(audio.selectedCatalogReciter?.supportsVersePlayback == false ? "استماع السورة" : "استماع من الآية", symbol: "play.fill", identifier: "verse.play") {
                let count = store.quran[selection.chapter - 1].ayahs.count
                manualSelection = nil; followAudio = true
                audio.play((selection.ayah...count).map { "\(selection.chapter):\($0)" })
            }
            verseAction(audio.selectedCatalogReciter?.supportsVersePlayback == false ? "تكرار السورة" : "تكرار الآية", symbol: "repeat", identifier: "verse.repeat") { openTools(selection, action: .repeatRange) }
            }
            let bookmarked = store.data.bookmarks.contains(selection.key)
            verseAction(bookmarked ? "إزالة العلامة" : "حفظ موضع الآية", symbol: bookmarked ? "bookmark.fill" : "bookmark", identifier: "verse.bookmark") {
                store.toggleBookmark(surah: selection.chapter, ayah: selection.ayah)
            }.accessibilityLabel(bookmarked ? "إزالة العلامة المرجعية" : "إضافة علامة مرجعية")
        }.scrollTargetLayout().padding(.horizontal, 8)
        }
            .scrollIndicators(.hidden)
            // At accessibility text sizes a tile nearly fills the lane. Settle
            // on its edge instead of leaving every action partly clipped
            // between tiles after an inertial horizontal swipe.
            .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
            .frame(height: readerDockHeight)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.gold.opacity(0.3), lineWidth: 1))
            .accessibilityIdentifier("verse.actions.panel")
            .accessibilityHint("اسحب أفقيًا لإظهار بقية خيارات الآية")
    }
    private func verseAction(_ label: String, symbol: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 22, weight: .semibold))
                Text(label).font(.caption.weight(.semibold)).lineLimit(2)
            }
                .multilineTextAlignment(.center)
                .frame(width: max(104, 104 * readerCaptionLineHeight / 16), height: readerDockHeight - 16)
                .foregroundStyle(.primary)
                .background(Theme.gold.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.gold.opacity(0.55), lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: 12))
        }.accessibilityLabel(label).accessibilityIdentifier(identifier)
    }
    private var title: String {
        guard let key = visibleSelection ?? page?.words.first?.verse, let n = Int(key.split(separator: ":")[0]), store.quran.indices.contains(n - 1) else { return "المصحف" }
        return store.quran[n - 1].name
    }
    private func turn(_ amount: Int) {
        guard !playbackLocksPage, allowedPages.contains(number + amount) else { return }
        followAudio = false
        let destination = number + amount
        cancelPageTurn()
        let request = pageTurns.begin(from: number, to: destination)
        let family = String(format: "QCF2%03d", destination)
        if fonts.names[family] != nil { commitPageTurn(destination, request: request); return }
        // Keep the current UIKit viewport mounted until its replacement font
        // is verified. Publishing number first used to replace it with a
        // spinner and destroy the gesture, shaped-page cache and slide state.
        pageTurnTask = Task {
            await fonts.load(family)
            guard !Task.isCancelled, fonts.names[family] != nil else { return }
            commitPageTurn(destination, request: request)
        }
    }
    private func cancelPageTurn() {
        pageTurns.cancel(); pageTurnTask?.cancel(); pageTurnTask = nil
    }
    private func commitPageTurn(_ destination: Int, request: MushafPageTurnCoordinator.Request) {
        guard pageTurns.consume(request, currentPage: number, visible: readerVisible,
                                playbackLocked: playbackLocksPage) == destination else { return }
        pageTurnTask = nil
        lastPage = destination
        number = destination; selected = nil; manualSelection = nil
    }
    private func rememberWardPosition() {
        guard let scope = readingScope, readingJourney.active?.id == scope.planID,
              allowedPages.contains(number), let page else { return }
        let oldStop = readingJourney.active?.stoppedAt
        let savedKey = oldStop.flatMap { $0.page == number ? "\($0.chapter):\($0.ayah)" : nil }
        let candidate = visibleSelection ?? savedKey
        guard let key = candidate.flatMap({ key in page.words.contains(where: { $0.verse == key }) ? key : nil }) ?? page.words.first?.verse else { return }
        let verse = VerseSelection(key: key)
        _ = readingJourney.stop(page: number, chapter: verse.chapter, ayah: verse.ayah)
    }
    private func followCurrentAudio() {
        if audio.playing != nil { clearManualSelection(); followPlayback(); return }
        guard let key = audio.playing,
              let destination = studyIndex?.pages[key]?.first, allowedPages.contains(destination) else { return }
        cancelPageTurn()
        followAudio = true; manualSelection = nil; selected = key
        lastPage = destination; number = destination
    }
    private func followPlayback() {
        // Playback follows the clock for the selected recording.
        guard readerVisible,
              manualSelection == nil, sheetVerse == nil,
              let mediaKey = audio.playing else { return }
        if let start = reciterPlaybackStart {
            // A whole-surah file's key denotes ayah1, not this requested word.
            // Do not navigate until the actual selected recording's clock has
            // reached the offset and supplied its own word/ayah location.
            guard audio.currentRecordingIdentity == start.identity,
                  audio.currentSeconds >= start.seconds - 0.002,
                  audio.activeWordID != nil, audio.activeVerseKey != nil else { return }
            reciterPlaybackStart = nil
        }
        let wholeSurah = NoorAudioIntegrity.reciterRecording(mediaKey) != nil
        // A gap or an unavailable timing track must not jump back to ayah1
        // after playback has advanced. Only the known start can navigate there.
        if wholeSurah, audio.activeVerseKey == nil, audio.currentSeconds > 0.1 {
            selected = nil; return
        }
        let key = audio.activeVerseKey ?? mediaKey
        guard let location = studyIndex?.playbackLocation(key: key, wordID: audio.activeWordID,
                  currentPage: number, allowedPages: allowedPages) else { return }
        cancelPageTurn()
        followAudio = true
        // Navigating to a surah's known beginning is not evidence that its
        // first ayah is still being read many seconds later.
        selected = !wholeSurah || audio.activeVerseKey != nil ? location.verse : nil
        if number != location.page { lastPage = location.page; number = location.page }
    }
    private func load() async {
        cancelPageTurn()
        renderGeneration = UUID(); error = nil; needsFirstDownload = false
        do {
            try OriginalMushafCompanion.register()
            let cache = try MushafReadingResources.cache()
            let entry = try await cache.readingEntry(onDownload: { needsFirstDownload = true })
            needsFirstDownload = false
            let referenceKeys = keys
            let content = try await MushafReadingPreparation.shared.prepare(entry.snapshot, keys: referenceKeys)
            try Task.checkCancellation()
            let data = content.snapshot
            let versePages = content.versePages
            let first = snapshot == nil; snapshot = data; rows = content.rows
            studyIndex = content.studyIndex; pageIndex = content.pageIndex
            if first {
                number = initialPage.flatMap { (1...604).contains($0) ? $0 : nil }
                    ?? versePages["\(chapter):\(ayah)"] ?? 1
                number = min(allowedPages.upperBound, max(allowedPages.lowerBound, number))
                // Explicit surah/bookmark/library entries can share one face
                // with other surahs. Preserve their target without opening
                // manual tools; page-only resume must not select a foreign key.
                if versePages["\(chapter):\(ayah)"] == number { selected = "\(chapter):\(ayah)" }
                lastPage = number
            }
            // Reconcile observable player state after resources load too:
            // a one-shot start callback can arrive while an ayah sheet closes.
            followPlayback()
            await fonts.load(String(format: "QCF2%03d", number))
        } catch {
            guard !Task.isCancelled else { return }
            self.error = "تعذّر التحقق من موارد المصحف المضمّنة. أعد المحاولة أو أعد تثبيت نسخة موثوقة من التطبيق." }
    }
}
private struct ReaderControlHeight: PreferenceKey {
    static var defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
struct VerseSelection: Identifiable { let key: String; var id: String { key }; var chapter: Int { Int(key.split(separator: ":")[0])! }; var ayah: Int { Int(key.split(separator: ":")[1])! } }

private enum VerseToolAction: Equatable { case details, tafsir, repeatRange }
private struct VerseTools: View {
    let selection: VerseSelection
    @ObservedObject var audio: MushafVerseAudio
    @Binding var selected: String?
    @EnvironmentObject private var store: AtharStore
    @EnvironmentObject private var memorization: MemorizationStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var tafsir = MushafTafsir()
    @State private var showTafsir = false
    @State private var repeatCount = 3
    @State private var repeatEnd = 1
    @State private var repeatDelay = 0
    @State private var notice: String?
    @State private var tafsirHeight: CGFloat = 220
    let initialAction: VerseToolAction
    let readingOnly: Bool
    init(selection: VerseSelection, audio: MushafVerseAudio, selected: Binding<String?>, initialAction: VerseToolAction = .details, readingOnly: Bool = false) {
        self.selection = selection; self.audio = audio; self._selected = selected
        self.initialAction = initialAction; self.readingOnly = readingOnly
        self._repeatEnd = State(initialValue: selection.ayah)
    }
    private var surah: Surah { store.quran[selection.chapter - 1] }
    private var verse: Ayah { surah.ayahs[selection.ayah - 1] }
    private var copyText: String { "\(QuranText.verse(chapter: selection.chapter, ayah: verse))\n[\(surah.name): \(selection.ayah)]" }
    var body: some View {
        NavigationStack {
            Group {
                if initialAction == .tafsir { tafsirContent }
                else { List {
                if initialAction == .details {
                Section {
                    if !readingOnly { Button(audio.selectedCatalogReciter?.supportsVersePlayback == false ? "الاستماع للسورة من بدايتها" : "الاستماع من هذه الآية", systemImage: "play.fill") {
                        audio.play((selection.ayah...surah.ayahs.count).map { "\(selection.chapter):\($0)" }); dismiss()
                    }.accessibilityIdentifier("verse.sheet.play") }
                    Button("التفسير", systemImage: "book") { showTafsir = true }.accessibilityIdentifier("verse.sheet.tafsir")
                    Button(store.data.bookmarks.contains(selection.key) ? "إزالة العلامة المرجعية" : "إضافة علامة مرجعية", systemImage: "bookmark") { store.toggleBookmark(surah: selection.chapter, ayah: selection.ayah) }.accessibilityIdentifier("verse.sheet.bookmark")
                }
                }
                if !readingOnly { Section("التكرار") {
                    Stepper("عدد التكرارات: \(repeatCount)", value: $repeatCount, in: 1...20).accessibilityIdentifier("verse.repeat.count")
                    if audio.selectedCatalogReciter?.supportsVersePlayback != false { Stepper("إلى الآية: \(repeatEnd)", value: $repeatEnd, in: selection.ayah...surah.ayahs.count) }
                    Stepper("مهلة بين التلاوات: \(repeatDelay) ثانية", value: $repeatDelay, in: 0...30).accessibilityIdentifier("verse.repeat.delay")
                    Text(audio.selectedCatalogReciter?.supportsVersePlayback == false ? "يتكرر تسجيل السورة كاملًا من بدايته. تبدأ المهلة بعد انتهاء التلاوة." : "يتكرر نطاق الآيات كاملًا بالترتيب. تبدأ المهلة بعد انتهاء كل تلاوة، ويمكن إيقافها من شريط المصحف.").font(.footnote)
                    Button("تشغيل التكرار") {
                        var next = memorization.mushafStudy
                        next.repetition = MushafRepeatPreferences(count: repeatCount, delaySeconds: repeatDelay)
                        guard memorization.saveMushafStudy(next) else { notice = "تعذّر حفظ خيارات التكرار. بياناتك السابقة محفوظة؛ صدّرها من الإعدادات."; return }
                        audio.play((selection.ayah...repeatEnd).map { "\(selection.chapter):\($0)" }, repetitions: repeatCount, delaySeconds: repeatDelay)
                        dismiss()
                    }.accessibilityIdentifier("verse.repeat.start")
                } }
                if initialAction == .details {
                Section("الحفظ والمشاركة") {
                    Button("نسخ نص الآية", systemImage: "doc.on.doc") { UIPasteboard.general.string = copyText; notice = "نُسخ نص الآية مع اسم السورة ورقمها." }.accessibilityIdentifier("verse.copy")
                    ShareLink(item: copyText) { Label("مشاركة الآية", systemImage: "square.and.arrow.up") }
                }
                }
                } }
            }
            .navigationTitle("\(surah.name) · الآية \(selection.ayah)")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                // List rows below the viewport are created lazily. A result
                // placed after ShareLink can remain invisible on smaller phones
                // even after Copy has succeeded. Keep action feedback outside
                // the scrolling list so it is visible and accessible immediately.
                if let notice {
                    Text(notice)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.regularMaterial)
                        .accessibilityIdentifier(initialAction == .repeatRange ? "verse.repeat.error" : "verse.notice")
                }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("\(surah.name) · الآية \(selection.ayah)").font(.headline)
                        .accessibilityIdentifier("verse.sheet.title")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("إغلاق") { dismiss() }.accessibilityIdentifier(initialAction == .tafsir ? "verse.tafsir.close" : "verse.sheet.close")
                }
            }
            .onAppear {
                repeatEnd = selection.ayah
                let saved = memorization.mushafStudy.repetition ?? MushafRepeatPreferences()
                repeatCount = saved.count; repeatDelay = saved.delaySeconds
            }
            .sheet(isPresented: $showTafsir) {
                NavigationStack {
                    tafsirContent
                    .navigationTitle("التفسير · \(surah.name) \(selection.ayah)")
                    .toolbar { Button("إغلاق") { showTafsir = false }.accessibilityIdentifier("verse.tafsir.close") }
                }
                .presentationDetents([.height(tafsirHeight), .large])
                .presentationDragIndicator(.visible)
            }

        }
        .presentationDetents(initialAction == .tafsir ? [.height(tafsirHeight), .large] : [.medium, .large])
    }
    private var tafsirContent: some View {
        ScrollView { VStack(alignment: .leading, spacing: 18) {
            Text(QuranText.verse(chapter: selection.chapter, ayah: verse))
                .font(.body).foregroundStyle(.secondary)
                .accessibilityIdentifier("verse.tafsir.ayah")
            Divider()
            if let text = tafsir.text { Text(text).font(.body).lineSpacing(6).accessibilityIdentifier("verse.tafsir.text") }
            else if let error = tafsir.error { Text(error); Button("إعادة المحاولة") { Task { await tafsir.load(chapter: selection.chapter, ayah: selection.ayah) } } }
            else { ProgressView("تحميل التفسير الميسر…") }
        }.padding().frame(maxWidth: .infinity, alignment: .leading)
            .background { GeometryReader { proxy in
                Color.clear.preference(key: TafsirContentHeight.self, value: proxy.size.height)
            } }
        }
            .onPreferenceChange(TafsirContentHeight.self) { height in
                guard height.isFinite, height > 0 else { return }
                // Includes the actual text and a navigation/drag-handle lane.
                // Long explanations scroll; the reader can expand to full height.
                tafsirHeight = min(480, max(220, height + 80))
            }
            .task { await tafsir.load(chapter: selection.chapter, ayah: selection.ayah) }
    }
}
private struct TafsirContentHeight: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
