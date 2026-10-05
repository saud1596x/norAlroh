import SwiftUI
import UIKit
import CoreText
import CryptoKit

struct MushafWord: Codable { let code: String; let line: Int; let key: String; let kind: String }
struct MushafLayout: Codable { let type: String; let chapter: Int?; let code: String?; let font: String? }
struct MushafPage: Codable, Identifiable {
    let page: Int; let font: String; let juz: Int; let layout: [String: MushafLayout]; let words: [MushafWord]
    var id: Int { page }
}
struct MushafDatabase: Codable {
    let pages: [MushafPage]; let chapterPages: [String: Int]; let juzPages: [Int]
    static let shared: MushafDatabase? = {
        guard let bytes = QuranResources.data("mushaf"),
              let value = try? JSONDecoder().decode(Self.self, from: bytes),
              let corpus = QuranResources.corpus, value.isValid(corpus: corpus) else { return nil }
        return value
    }()
    static let headers: [Int] = {
        guard let bytes = QuranResources.data("mushaf-headers") else { return [] }
        return (try? JSONDecoder().decode([Int].self, from: bytes)) ?? []
    }()
    func isValid(corpus: [Surah]) -> Bool {
        let canonical = corpus.flatMap { chapter in chapter.ayahs.map { "\(chapter.number):\($0.number)" } }
        let ends = pages.flatMap { $0.words.filter { $0.kind == "end" }.map(\.key) }
        guard pages.map(\.page) == Array(1...604), ends == canonical,
              Set(chapterPages.keys) == Set((1...114).map { String($0) }),
              juzPages == [1,22,42,62,82,102,121,142,162,182,201,222,242,262,282,302,322,342,362,382,402,422,442,462,482,502,522,542,562,582] else { return false }
        let validKeys = Set(canonical)
        var headings: [Int] = []
        var firstPages: [String: Int] = [:]
        for page in pages {
            guard (1...47).contains(Int(page.font.suffix(2)) ?? 0),
                  page.font.hasPrefix("QCF4_Hafs_"), !page.words.isEmpty,
                  page.words.map(\.line) == page.words.map(\.line).sorted(),
                  page.juz == juzPages.filter({ page.page >= $0 }).count else { return false }
            let rows = page.page <= 2 ? 8 : 15
            for word in page.words {
                guard (1...rows).contains(word.line), validKeys.contains(word.key),
                      ["word", "end", "quarter"].contains(word.kind), !word.code.isEmpty,
                      word.code.unicodeScalars.allSatisfy({ (0xE000...0xF8FF).contains(Int($0.value)) }) else { return false }
                if firstPages[word.key] == nil { firstPages[word.key] = page.page }
            }
            for (line, layout) in page.layout.sorted(by: { (Int($0.key) ?? 0) < (Int($1.key) ?? 0) }) {
                guard let row = Int(line), (1...rows).contains(row),
                      !page.words.contains(where: { $0.line == row }) else { return false }
                if layout.type == "header", let chapter = layout.chapter { headings.append(chapter) }
                else if layout.type != "bismillah" || layout.code?.isEmpty != false { return false }
            }
        }
        return headings == Array(1...114) && corpus.allSatisfy { chapterPages[String($0.number)] == firstPages["\($0.number):1"] }
    }
}

// QCF V2 page fonts are bundled in every build and verified against the pinned manifest.
@MainActor final class MushafFonts: ObservableObject {
    @Published private(set) var names: [String: String] = [:]
    @Published var error: String?
    private var pending: [String: Task<String, Error>] = [:]
    func load(_ family: String) async {
        guard names[family] == nil else { return }
        let task = pending[family] ?? Task { try await Self.register(family) }
        pending[family] = task
        defer { pending[family] = nil }
        do {
            names[family] = try await task.value
        } catch {
            self.error = "تعذّر عرض صفحة المصحف. حاول مرة أخرى، أو أعد تثبيت نسخة موثوقة."
        }
    }
    private static func register(_ family: String) async throws -> String {
        guard family.hasPrefix("QCF2"), let page = Int(family.dropFirst(4)), (1...604).contains(page),
              let manifestURL = Bundle.main.url(forResource: "qcf-v2-manifest", withExtension: "json"),
              let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any],
              let entries = manifest["fonts"] as? [[String: Any]], entries.count == 604,
              let entry = entries.first(where: { $0["page"] as? Int == page }),
              entry["postScriptName"] as? String == family,
              let digest = entry["sha256"] as? String else { throw CocoaError(.fileReadCorruptFile) }
        let resource = "p\(page)"
        let fontData: Data
        if let url = Bundle.main.url(forResource: resource, withExtension: "ttf") {
            fontData = try Data(contentsOf: url)
        } else { throw CocoaError(.fileNoSuchFile) }
        guard fontData.count == entry["bytes"] as? Int,
              SHA256.hash(data: fontData).map({ String(format: "%02x", $0) }).joined() == digest,
              let provider = CGDataProvider(data: fontData as CFData), let font = CGFont(provider),
              let postScriptName = font.postScriptName, postScriptName as String == family else {
            throw CocoaError(.fileReadCorruptFile)
        }
        CTFontManagerRegisterGraphicsFont(font, nil)
        guard UIFont(name: family, size: 24) != nil else { throw CocoaError(.fileReadCorruptFile) }
        return family
    }
    func load(page: MushafPage) async { error = nil; await load(page.font) }
    func ready(page: MushafPage) -> Bool { names[page.font] != nil }

}

struct MushafReader: View {
    @EnvironmentObject var store: AtharStore
    @Environment(\.accessibilityReduceMotion) private var systemReduced
    @StateObject private var fonts = MushafFonts()
    let startingChapter: Int
    let startingAyah: Int
    let startingPage: Int?
    @AppStorage("noor.mushaf.lastPage") private var lastPage = 1
    @State private var number = 1
    @State private var selected: String?
    @State private var focused: String?
    @State private var picker = false
    @State private var input = "1"
    @State private var renderingFailed = false
    @State private var database: MushafDatabase?
    @State private var contentError: String?
    private var page: MushafPage? { database?.pages.first { $0.page == number } }
    private var reduce: Bool { systemReduced || store.data.lowMotion }
    init(chapter: Int, ayah: Int = 1, page: Int? = nil) { startingChapter = chapter; startingAyah = ayah; startingPage = page }
    var body: some View {
        VStack(spacing: 0) {
            if let page {
                if renderingFailed {
                    ContentUnavailableView("تعذّر رسم الصفحة بدقة", systemImage: "textformat", description: Text("لم يُعرض خط بديل للآيات. استخدم القراءة المرنة وأعد تثبيت نسخة موثوقة."))
                } else if fonts.ready(page: page) {
                    GeometryReader { geometry in
                        let opening = number <= 2
                        let rows = opening ? 8 : 15
                        let width = min(geometry.size.width, 640)
                        // Landscape scrolls vertically instead of compressing fifteen lines.
                        let height = width * CGFloat(rows) * (opening ? 0.145 : 0.112)
                        ScrollView(.vertical) {
                            VStack(spacing: 0) {
                                ForEach(1...rows, id: \.self) { line in
                                    MushafLineRepresentable(page: page, line: line, names: fonts.names,
                                        headers: MushafDatabase.headers, selected: focused, quran: store.quran,
                                        onSelect: { selected = $0; focused = $0 }, onFailure: { if number == page.page { renderingFailed = true } })
                                        .frame(height: height / CGFloat(rows))
                                }
                            }
                            .frame(width: width, height: height)
                            .frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: opening ? .center : .top)
                        }
                        .scrollIndicators(.hidden)
                    }.padding(.horizontal, 12).padding(.vertical, 8)
                    .id(number)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("صفحة المصحف \(number)")
                    .accessibilityIdentifier("reader.page.ready")
                    .transition(reduce ? .identity : .opacity)
                    .gesture(DragGesture(minimumDistance: 55).onEnded { value in
                        if abs(value.translation.width) > abs(value.translation.height) {
                            turn(value.translation.width > 0 ? 1 : -1)
                        }
                    })
                } else if let error = fonts.error {
                    ContentUnavailableView("خط المصحف غير متاح", systemImage: "textformat", description: Text(error))
                    Button("إعادة المحاولة") { Task { await fonts.load(page: page) } }.padding()
                } else { ProgressView("تحميل خط الصفحة…").frame(maxWidth: .infinity, maxHeight: .infinity) }
                HStack {
                    Button { turn(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                        .disabled(number == 604).accessibilityLabel("الصفحة التالية")
                    Spacer()
                    Button("\(number) / 604 · الجزء \(page.juz)") { input = String(number); picker = true }
                        .font(.subheadline).frame(minHeight: 44).accessibilityIdentifier("reader.jump")
                    Spacer()
                    Button { turn(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                        .disabled(number == 1).accessibilityLabel("الصفحة السابقة")
                }.padding(.horizontal, 12).background(Theme.panel)
            } else if let contentError {
                ContentUnavailableView("تعذّر تنزيل المصحف", systemImage: "wifi.exclamationmark", description: Text(contentError))
                Button("إعادة المحاولة") { Task { await loadContent() } }.padding()
            } else { ProgressView("تنزيل المصحف لأول مرة…").frame(maxWidth: .infinity, maxHeight: .infinity) }
        }
        .background(Theme.panel)
        .navigationTitle(pageTitle).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let chapter = store.quran.first(where: { $0.name == pageTitle }) {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { QuranReader(surah: chapter) } label: {
                        Image(systemName: "textformat.size").frame(width: 44, height: 44)
                    }.accessibilityLabel("قراءة مرنة وتكبير خط السورة")
                        .accessibilityIdentifier("reader.flexible")
                }
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .task {
            await loadContent()
            if let db = database {
                number = startingPage.flatMap { (1...604).contains($0) ? $0 : nil } ?? db.pages.first { $0.words.contains { $0.key == "\(startingChapter):\(startingAyah)" } }?.page
                    ?? db.chapterPages[String(startingChapter)] ?? 1
                lastPage = number
                let key = "\(startingChapter):\(startingAyah)"
                if startingPage == nil, page?.words.contains(where: { $0.key == key }) == true { focused = key }
                if let page { await fonts.load(page: page) }
            }
        }
        .onChange(of: number) { _, value in lastPage = value }
        .task(id: number) { if let page { await fonts.load(page: page) } }
        .sheet(isPresented: $picker) {
            NavigationStack {
                Form {
                    Section("رقم الصفحة") {
                        TextField("١ إلى ٦٠٤", text: $input).keyboardType(.numberPad).accessibilityIdentifier("reader.pageNumber")
                        Button("انتقل") { if let n = ArabicSearch.integer(input), (1...604).contains(n) { go(to: n); picker = false } }
                            .disabled(!(ArabicSearch.integer(input).map { (1...604).contains($0) } ?? false))
                    }
                    Section("الأجزاء") {
                        if let db = database { ForEach(Array(db.juzPages.enumerated()), id: \.offset) { index, n in
                            Button("الجزء \(index + 1) · صفحة \(n)") { go(to: n); picker = false }
                        } }
                    }
                }.navigationTitle("الانتقال في المصحف")
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("إغلاق") { picker = false } } }
            }
        }
        .confirmationDialog("خيارات الآية", isPresented: Binding(get: { selected != nil }, set: { if !$0 { selected = nil } })) {
            if let key = selected, let pair = verse(key) {
                Button(store.data.bookmarks.contains(key) ? "إزالة العلامة" : "حفظ علامة") {
                    store.toggleBookmark(surah: pair.0, ayah: pair.1); selected = nil
                }
                Button("نسخ الآية") {
                    UIPasteboard.general.string = QuranText.verse(chapter: pair.0, ayah: store.quran[pair.0 - 1].ayahs[pair.1 - 1])
                    selected = nil
                }
                Button("إلغاء", role: .cancel) { selected = nil }
            }
        }
    }
    private func loadContent() async {
        contentError = nil
        do {
            guard let corpus = QuranResources.corpus else { throw QCFV2Snapshot.Invalid.verse }
            let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let cache = QCFV2ContentCache(file: directory.appendingPathComponent("qcf-v2-cache.json"),
                                        endpoint: URL(string: "https://noor-quran-sync.onrender.com/v1/mushaf/snapshot")!)
            let entry: QCFV2ContentCache.Entry
            do { entry = try await cache.refresh() }
            catch { guard let offline = await cache.cached() else { throw error }; entry = offline }
            database = try await Task.detached {
                let snapshot = try JSONDecoder().decode(QCFV2Snapshot.self, from: entry.snapshot)
                return try QCFV2PageLayout.database(snapshot: snapshot, corpus: corpus)
            }.value
            if let page { await fonts.load(page: page) }
        } catch { contentError = "اتصل بالإنترنت لإتمام التنزيل الأول. بعده تُحفظ نسخة موثوقة للقراءة دون اتصال، ولا يُستبدل محتواها عند فشل التحديث." }
    }
    private var pageTitle: String {
        let key = focused.flatMap { key in page?.words.contains(where: { $0.key == key }) == true ? key : nil } ?? page?.words.first?.key
        guard let key, let pair = verse(key), store.quran.indices.contains(pair.0 - 1) else { return store.quran.first(where: { $0.number == startingChapter })?.name ?? "المصحف" }
        return store.quran[pair.0 - 1].name
    }
    private func verse(_ key: String) -> (Int, Int)? {
        let n = key.split(separator: ":").compactMap { Int($0) }
        guard n.count == 2, store.quran.indices.contains(n[0] - 1), store.quran[n[0] - 1].ayahs.indices.contains(n[1] - 1) else { return nil }
        return (n[0], n[1])
    }
    private func turn(_ amount: Int) {
        go(to: number + amount)
    }
    private func go(to destination: Int) {
        guard (1...604).contains(destination) else { return }
        withAnimation(reduce ? nil : .easeInOut(duration: 0.25)) { number = destination; lastPage = destination; selected = nil; focused = nil; renderingFailed = false }
    }
}

private struct MushafLineRepresentable: UIViewRepresentable {
    let page: MushafPage; let line: Int; let names: [String: String]; let headers: [Int]
    let selected: String?; let quran: [Surah]; let onSelect: (String) -> Void; let onFailure: () -> Void
    func makeUIView(context: Context) -> MushafLineCanvas { MushafLineCanvas() }
    func updateUIView(_ view: MushafLineCanvas, context: Context) {
        view.words = page.words.filter { $0.line == line }
        view.layout = page.layout[String(line)]
        view.bodyName = names[page.font] ?? ""
        view.headerName = QuranTypography.postScriptName
        view.basmalaName = QuranTypography.postScriptName
        view.headers = headers; view.quran = quran; view.centered = page.page <= 2
        view.onSelect = onSelect; view.onFailure = onFailure; view.selected = selected; view.setNeedsDisplay()
    }
}

private final class MushafLineCanvas: UIView {
    var words: [MushafWord] = []; var layout: MushafLayout?
    var bodyName = ""; var headerName = ""; var basmalaName = ""
    var headers: [Int] = []; var quran: [Surah] = []; var centered = false
    var onSelect: ((String) -> Void)?
    var onFailure: (() -> Void)?
    var selected: String?
    private var drawnLine: CTLine?; private var origin = CGPoint.zero
    private var wordRanges: [(NSRange, String)] = []
    private var verseRects: [(key: String, rect: CGRect)] = []
    override init(frame: CGRect) {
        super.init(frame: frame); backgroundColor = .clear
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped(_:))))
    }
    required init?(coder: NSCoder) { fatalError("Programmatic view") }
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) { super.traitCollectionDidChange(previousTraitCollection); setNeedsDisplay() }
    override func draw(_ rect: CGRect) {
        guard bounds.width > 12, bounds.height > 8, let context = UIGraphicsGetCurrentContext() else { return }
        drawnLine = nil; verseRects = []; accessibilityElements = nil
        var text = ""; var fontName = bodyName; var size: CGFloat = bounds.width * 0.115
        var justify = !centered; wordRanges = []
        if let layout, layout.type == "header", let chapter = layout.chapter, quran.indices.contains(chapter - 1) {
            text = quran[chapter - 1].name; fontName = headerName; size = bounds.width * 0.07; justify = false
            isAccessibilityElement = true
            accessibilityLabel = quran.indices.contains(chapter - 1) ? quran[chapter - 1].name : "عنوان السورة"
        } else if let layout, layout.type == "bismillah" {
            text = layout.code ?? ""; fontName = basmalaName; size = 21; justify = false
            isAccessibilityElement = true; accessibilityLabel = quran.first?.ayahs.first?.text
        } else {
            for word in words {
                if !text.isEmpty { text += " " }
                let location = (text as NSString).length
                text += word.code
                wordRanges.append((NSRange(location: location, length: (word.code as NSString).length), word.key))
            }
            isAccessibilityElement = false
        }
        guard !text.isEmpty else { return }
        guard let result = MushafTypesetter.make(text: text, fontName: fontName, size: size,
                                                bounds: bounds, justify: justify) else {
            DispatchQueue.main.async { [weak self] in self?.onFailure?() }
            return
        }
        let line = result.line
        origin = result.origin; drawnLine = line
        // Aggregate all words of a verse, including spaces, for VoiceOver and hit testing.
        for (range, key) in wordRanges {
            let a = CGFloat(CTLineGetOffsetForStringIndex(line, range.location, nil))
            let b = CGFloat(CTLineGetOffsetForStringIndex(line, range.location + range.length, nil))
            let rect = CGRect(x: origin.x + min(a, b) - 1, y: 0, width: max(3, abs(a - b) + 2), height: bounds.height)
                .intersection(bounds)
            if let i = verseRects.firstIndex(where: { $0.key == key }) { verseRects[i].rect = verseRects[i].rect.union(rect) }
            else { verseRects.append((key: key, rect: rect)) }
        }
        if let target = verseRects.first(where: { $0.key == selected }) {
            context.setFillColor(UIColor.systemYellow.withAlphaComponent(0.20).cgColor)
            context.fill(target.rect.insetBy(dx: 0, dy: 2))
        }
        context.saveGState(); context.textMatrix = .identity
        context.translateBy(x: 0, y: bounds.height); context.scaleBy(x: 1, y: -1)
        context.textPosition = origin; CTLineDraw(line, context); context.restoreGState()
        if layout == nil {
            var elements: [UIAccessibilityElement] = []
            for target in verseRects {
                let key = target.key
                let parts = key.split(separator: ":").compactMap { Int($0) }
                guard parts.count == 2, quran.indices.contains(parts[0] - 1), quran[parts[0] - 1].ayahs.indices.contains(parts[1] - 1) else { continue }
                let e = MushafAccessibilityElement(accessibilityContainer: self)
                e.accessibilityLabel = QuranText.verse(chapter: parts[0], ayah: quran[parts[0] - 1].ayahs[parts[1] - 1])
                e.accessibilityHint = "خيارات الآية \(parts[1])"; e.accessibilityTraits = .button
                e.accessibilityFrameInContainerSpace = target.rect
                e.activate = { [weak self] in self?.onSelect?(key) }; elements.append(e)
            }
            accessibilityElements = elements
        }
    }
    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        guard drawnLine != nil else { return }
        let x = gesture.location(in: self).x
        guard x >= 0, x <= bounds.width else { return }
        let point = gesture.location(in: self)
        if let target = verseRects.first(where: { $0.rect.contains(point) }) { onSelect?(target.key) }
    }
}
private final class MushafAccessibilityElement: UIAccessibilityElement {
    var activate: (() -> Void)?
    override func accessibilityActivate() -> Bool { activate?(); return true }
}
