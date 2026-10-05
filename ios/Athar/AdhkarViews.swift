import SwiftUI
import Foundation

struct DhikrEntry: Codable, Identifiable {
    let id: String; let title: String; let text: String; let target: Int; let reference: String; let sourceURL: URL
}
struct DhikrGroup: Codable, Identifiable {
    let id: String; let name: String; let note: String; let icon: String; let items: [String]
    var symbol: String {
        switch icon { case "sun": "sun.max"; case "moon": "moon.stars"; case "mosque": "building.2"; default: "sparkles" }
    }
}
struct AdhkarContent: Codable {
    let groups: [DhikrGroup]; let entries: [DhikrEntry]
    static let shared: AdhkarContent? = {
        guard let bytes = QuranResources.data("adhkar"),
              let value = try? JSONDecoder().decode(Self.self, from: bytes),
              value.groups.count == 132, value.entries.count == 267,
              Set(value.groups.map(\.id)).count == 132,
              value.entries.allSatisfy({ !$0.text.isEmpty && $0.target > 0 && !$0.reference.isEmpty && $0.sourceURL.scheme == "https" }) else { return nil }
        let ids = Set(value.entries.map(\.id))
        let assigned = value.groups.flatMap(\.items)
        guard ids.count == value.entries.count, Set(assigned) == ids, assigned.count == value.entries.count,
              value.groups.allSatisfy({ !$0.items.isEmpty }) else { return nil }
        return value
    }()
    static func load() -> AdhkarContent? { shared }
    func entries(in group: DhikrGroup) -> [DhikrEntry] {
        let lookup = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
        return group.items.compactMap { lookup[$0] }
    }
}

@MainActor final class DhikrCounterStore: ObservableObject {
    @Published private(set) var counts: [String: Int]
    @Published private(set) var favorites: Set<String>
    private let key = "noor.adhkar.counts.v1"
    private let favoriteKey = "noor.adhkar.favorites.v1"
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        counts = defaults.dictionary(forKey: key) as? [String: Int] ?? [:]
        favorites = Set(defaults.stringArray(forKey: favoriteKey) ?? [])
    }
    private func identifier(entry: DhikrEntry, group: DhikrGroup, city: City, date: Date) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian); formatter.timeZone = TimeZone(identifier: "Asia/Riyadh")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date) + ":" + group.id + ":" + entry.id
    }
    func count(entry: DhikrEntry, group: DhikrGroup, city: City, date: Date = Date()) -> Int {
        max(0, min(entry.target, counts[identifier(entry: entry, group: group, city: city, date: date)] ?? 0))
    }
    func update(_ value: Int, entry: DhikrEntry, group: DhikrGroup, city: City, date: Date = Date()) {
        counts[identifier(entry: entry, group: group, city: city, date: date)] = max(0, min(entry.target, value))
        // Retain only the current day, keeping daily counters bounded across all 132 chapters.
        let prefix = identifier(entry: entry, group: group, city: city, date: date).prefix(10)
        counts = counts.filter { $0.key.hasPrefix(prefix) }
        defaults.set(counts, forKey: key)
    }
    func toggleFavorite(_ id: String) {
        if favorites.contains(id) { favorites.remove(id) } else { favorites.insert(id) }
        defaults.set(Array(favorites).sorted(), forKey: favoriteKey)
    }
    func refreshDay(date: Date = Date()) {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian); formatter.timeZone = TimeZone(identifier: "Asia/Riyadh")
        formatter.dateFormat = "yyyy-MM-dd"
        let day = formatter.string(from: date) + ":"
        let current = counts.filter { $0.key.hasPrefix(day) }
        if current != counts { counts = current; defaults.set(counts, forKey: key) }
    }
    func erase() {
        counts = [:]; favorites = []
        defaults.removeObject(forKey: key); defaults.removeObject(forKey: favoriteKey)
    }
}

struct AdhkarView: View {
    @EnvironmentObject private var counters: DhikrCounterStore
    @EnvironmentObject private var store: AtharStore
    @Environment(\.accessibilityReduceMotion) private var reduced
    @State private var search = ""
    @State private var favoritesOnly = false
    private let content = AdhkarContent.shared
    private var groups: [DhikrGroup] {
        guard let content else { return [] }
        let query = ArabicSearch.normalize(search)
        let matchingEntries = Set(content.entries.filter { ArabicSearch.normalize($0.text).contains(query) }.map(\.id))
        return content.groups.filter { group in
            (!favoritesOnly || counters.favorites.contains(group.id)) &&
                (query.isEmpty || ArabicSearch.normalize(group.name).contains(query) || group.items.contains(where: matchingEntries.contains))
        }
    }
    var body: some View {
        Group {
            if let content {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("ذكرٌ، وسكينة").font(.largeTitle.bold())
                            Text("حصن المسلم · ١٣٢ بابًا و٢٦٧ نصًا").font(.subheadline)
                            HStack {
                                Label("محفوظ على جهازك", systemImage: "checkmark.circle")
                                Spacer()
                                Text("دون اتصال")
                            }.font(.caption)
                        }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
                            .foregroundStyle(Theme.buttonInk).background(Theme.gold, in: RoundedRectangle(cornerRadius: 26))
                            .overlay(alignment: .topLeading) { NoorAmbientOrnament(ink: Theme.buttonInk).frame(width: 95, height: 95).padding(12) }
                            .noorEntrance()
                        Picker("عرض الأذكار", selection: $favoritesOnly) {
                            Text("جميع الأبواب").tag(false); Text("المفضلة").tag(true)
                        }.pickerStyle(.segmented)
                        ForEach(groups) { group in
                            HStack(spacing: 8) {
                                NavigationLink { DhikrListView(group: group, entries: content.entries(in: group)) } label: {
                                    HStack(spacing: 14) {
                                        Image(systemName: group.symbol).font(.title2).foregroundStyle(Theme.gold)
                                            .frame(width: 46, height: 46).background(Theme.gold.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text(group.name).font(.headline).foregroundStyle(.primary)
                                            Text(group.note).font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer(); Image(systemName: "chevron.left").font(.caption).foregroundStyle(.secondary)
                                    }.frame(minHeight: 58)
                                }.buttonStyle(NoorPressStyle())
                                Button { counters.toggleFavorite(group.id) } label: {
                                    Image(systemName: counters.favorites.contains(group.id) ? "star.fill" : "star")
                                        .foregroundStyle(Theme.gold).frame(width: 44, height: 44)
                                        .symbolEffect(.bounce, value: !reduced && !store.data.lowMotion && counters.favorites.contains(group.id))
                                }.buttonStyle(NoorPressStyle()).accessibilityLabel("مفضلة: \(group.name)")
                            }.padding(14).background(Theme.panel, in: RoundedRectangle(cornerRadius: 20)).noorEntrance()
                        }
                        if groups.isEmpty { ContentUnavailableView("لا توجد نتائج", systemImage: "magnifyingglass", description: Text("ابحث باسم الباب أو كلمة من الذكر، أو أضف بابًا إلى المفضلة.")) }
                        Text("النص والعدد كما وردا في مصدر حصن المسلم. رقم المصدر لا يمثل درجة صحة الحديث.")
                            .font(.caption).foregroundStyle(.secondary).padding(.vertical, 10)
                    }.padding(20)
                }
            } else { ContentUnavailableView("تعذر تحميل الأذكار", systemImage: "book.closed") }
        }.background(Theme.background).navigationTitle("الأذكار")
            .searchable(text: $search, prompt: "ابحث في الأبواب والنصوص")
            .tint(Theme.gold)
    }
}

struct DhikrListView: View {
    @EnvironmentObject private var store: AtharStore
    @EnvironmentObject private var counters: DhikrCounterStore
    let group: DhikrGroup; let entries: [DhikrEntry]
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                NavigationLink { DhikrReadingSession(group: group, entries: entries, start: 0) } label: {
                    Label("ابدأ جلسة الذكر", systemImage: "play.fill").font(.headline).frame(maxWidth: .infinity, minHeight: 54)
                        .foregroundStyle(Theme.buttonInk).background(Theme.gold, in: RoundedRectangle(cornerRadius: 18))
                }.buttonStyle(NoorPressStyle()).noorEntrance()
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    let reading = DhikrReadingContent(entry: entry)
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(reading.title).font(.headline)
                                    Text("الذكر \(index + 1) من \(entries.count)").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(counters.count(entry: reading.counterEntry, group: group, city: store.data.city)) / \(reading.counterEntry.target)").font(.caption.monospacedDigit()).foregroundStyle(Theme.gold)
                            }
                            DhikrReadingText(content: reading)
                            NavigationLink { DhikrReadingSession(group: group, entries: entries, start: index) } label: {
                                Label("اقرأ هذا الذكر مع العداد", systemImage: "hand.tap").font(.subheadline.bold()).frame(minHeight: 44)
                            }.accessibilityIdentifier("dhikr.open.\(entry.id)")
                            Label(entry.reference, systemImage: "book.closed").font(.caption).foregroundStyle(.secondary)
                        }.foregroundStyle(.primary).padding(20).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 22))
                            .accessibilityIdentifier("dhikr.card.\(entry.id)").noorEntrance()
                }
            }.padding(20)
        }.background(Theme.background).navigationTitle(group.name).navigationBarTitleDisplayMode(.inline)
    }
}

struct DhikrReadingSession: View {
    @EnvironmentObject private var store: AtharStore
    @Environment(\.accessibilityReduceMotion) private var reduced
    let group: DhikrGroup; let entries: [DhikrEntry]
    @State private var index: Int
    init(group: DhikrGroup, entries: [DhikrEntry], start: Int) {
        self.group = group; self.entries = entries
        _index = State(initialValue: max(0, min(start, entries.count - 1)))
    }
    var body: some View {
        Group {
            if entries.indices.contains(index) {
                DhikrSessionView(entry: entries[index], group: group)
                    .id(entries[index].id)
                    .transition(.opacity)
                    .safeAreaInset(edge: .bottom) {
                        HStack {
                            Button("السابق", systemImage: "chevron.right") { move(-1) }.disabled(index == 0)
                            Spacer(); Text("\(index + 1) / \(entries.count)").font(.caption.monospacedDigit()); Spacer()
                            Button("التالي", systemImage: "chevron.left") { move(1) }.disabled(index == entries.count - 1)
                        }.buttonStyle(NoorPressStyle()).frame(minHeight: 48).padding(.horizontal, 20).background(Theme.panel)
                    }
            } else { ContentUnavailableView("لا يوجد ذكر", systemImage: "book.closed") }
        }.navigationTitle(group.name).navigationBarTitleDisplayMode(.inline)
    }
    private func move(_ step: Int) {
        guard entries.indices.contains(index + step) else { return }
        withAnimation(reduced || store.data.lowMotion ? nil : .easeInOut(duration: 0.22)) { index += step }
    }
}

struct DhikrSessionView: View {
    @EnvironmentObject private var store: AtharStore
    @EnvironmentObject private var counters: DhikrCounterStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title2) private var size = 26.0
    let entry: DhikrEntry; let group: DhikrGroup
    private var reading: DhikrReadingContent { DhikrReadingContent(entry: entry) }
    private var counterEntry: DhikrEntry { reading.counterEntry }
    private var count: Int { counters.count(entry: counterEntry, group: group, city: store.data.city) }
    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                VStack(alignment: .leading, spacing: 18) {
                    Text(reading.title).font(.title2.bold())
                    DhikrReadingText(content: reading)
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.panel, in: RoundedRectangle(cornerRadius: 24))
                if reading.usesCanonicalQuran {
                    Text("الآيات من النص القرآني المدقّق · Tanzil. ترتيب الذكر وتعليماته من حصن المسلم.").font(.caption).foregroundStyle(.secondary)
                }
                DisclosureGroup("النص الأصلي كما ورد في المصدر") { Text(verbatim: entry.text).font(.body).lineSpacing(5).textSelection(.enabled) }
                Link(entry.reference, destination: entry.sourceURL).font(.caption).tint(Theme.gold)
                Button { change(count + 1) } label: {
                    ZStack {
                        Circle().fill(Theme.gold)
                        Circle().stroke(Theme.buttonInk.opacity(0.18), lineWidth: 5).padding(14)
                        Circle().trim(from: 0, to: Double(count) / Double(counterEntry.target))
                            .stroke(Theme.buttonInk, style: StrokeStyle(lineWidth: 5, lineCap: .round)).rotationEffect(.degrees(-90)).padding(14)
                        VStack(spacing: 8) {
                            Text(count, format: .number).font(.system(size: 54, weight: .medium)).monospacedDigit().contentTransition(.numericText())
                            Text(count == counterEntry.target ? "اكتمل الذكر" : "المس للعدّ").font(.headline)
                            Text("من \(counterEntry.target)").font(.caption)
                        }.foregroundStyle(Theme.buttonInk)
                    }.frame(width: 224, height: 224)
                }.buttonStyle(NoorPressStyle()).disabled(count >= counterEntry.target)
                    .accessibilityLabel("زيادة عداد الذكر").accessibilityValue("\(count) من \(counterEntry.target)")
                    .sensoryFeedback(.selection, trigger: count)
                if count >= counterEntry.target {
                    HStack { Image(systemName: "checkmark.circle.fill"); Text("أتممت هذا الذكر") }
                        .font(.headline).foregroundStyle(Theme.gold)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
                HStack(spacing: 24) {
                    Button("تراجع", systemImage: "arrow.uturn.backward") { change(count - 1) }.disabled(count == 0)
                    Button("إعادة العدّ", systemImage: "arrow.counterclockwise") { change(0) }.disabled(count == 0)
                }.buttonStyle(NoorPressStyle()).frame(minHeight: 44).font(.subheadline)
                Text("عدد القراءة من نص المصدر، وعداد اليوم محفوظ على جهازك بتوقيت المملكة.").font(.caption).foregroundStyle(.secondary)
                if reading.blocks.filter({ $0.quran != nil }).count > 1 {
                    Text("العداد لهذه المجموعة كاملة؛ اقرأ السور المعروضة ثم سجّل جولة واحدة.").font(.caption).foregroundStyle(.secondary)
                }
            }.padding(20)
        }.background(Theme.background).noorEntrance()
            .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { counters.refreshDay(date: $0) }
    }
    private func change(_ value: Int) {
        withAnimation(reduceMotion || store.data.lowMotion ? nil : .spring(duration: 0.35, bounce: 0.08)) {
            counters.update(value, entry: counterEntry, group: group, city: store.data.city)
        }
    }
}
