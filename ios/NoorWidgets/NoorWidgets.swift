import SwiftUI
import WidgetKit

struct NoorEntry: TimelineEntry {
    let date: Date
    let snapshot: NoorWidgetSnapshot?
    var dua: NoorDua? = nil
}
struct NoorProvider: TimelineProvider {
    var kind: NoorWidgetKind = .nextPrayer
    private func family(_ family: WidgetFamily) -> NoorDuaFamily {
        switch family {
        case .systemSmall: return .small
        case .accessoryInline: return .lockInline
        case .accessoryRectangular: return .lockRectangular
        default: return .home
        }
    }
    private func entry(date: Date, snapshot: NoorWidgetSnapshot?, family: WidgetFamily) -> NoorEntry {
        .init(date: date, snapshot: snapshot, dua: NoorDuaTimeline.selection(at: date, family: self.family(family), timeZone: .current))
    }
    func placeholder(in context: Context) -> NoorEntry { entry(date: Date(), snapshot: nil, family: context.family) }
    func getSnapshot(in context: Context, completion: @escaping (NoorEntry) -> Void) {
        completion(entry(date: Date(), snapshot: NoorWidgetSnapshot.load(), family: context.family))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<NoorEntry>) -> Void) {
        let now = Date(), snapshot = NoorWidgetSnapshot.load()
        if kind == .dua || kind == .shortDhikr {
            let entries = NoorDuaTimeline.entries(now: now, family: family(context.family), timeZone: .current)
                .map { NoorEntry(date: $0.date, snapshot: nil, dua: $0.dua) }
            completion(Timeline(entries: entries, policy: .atEnd))
            return
        }
        var dates = [now]
        if let snapshot {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: snapshot.prayer.city.timeZone) ?? .current
            for offset in 0...2 {
                guard let day = calendar.date(byAdding: .day, value: offset, to: now) else { continue }
                if snapshot.canDisplayPrayerTimes { dates += PrayerCalculator.rows(data: snapshot.prayer, date: day).map(\.date).filter { $0 > now } }
                let midnight = calendar.startOfDay(for: day)
                if midnight > now { dates.append(midnight) }
            }
            // Memorization day uses the device calendar, independently of city time.
            if let midnight = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now)) { dates.append(midnight) }
            for zone in [snapshot.khatmah?.timeZone, snapshot.salawatTimeZone].compactMap({ $0 }) {
                var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: zone) ?? .current
                for offset in 1...2 {
                    if let midnight = c.date(byAdding: .day, value: offset, to: c.startOfDay(for: now)) { dates.append(midnight) }
                }
            }
        }
        let entries = Set(dates).sorted().map { NoorEntry(date: $0, snapshot: snapshot) }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(6 * 3600))))
    }
}

enum NoorWidgetKind: String, CaseIterable {
    case nextPrayer, prayerDay, dua, reading, ward, review, khatmah, salawat, shortDhikr
    var title: String {
        switch self {
        case .nextPrayer: "الصلاة القادمة"
        case .prayerDay: "مواقيت اليوم"
        case .dua: "دعاء"
        case .shortDhikr: "ذكر قصير"
        case .reading: "أكمل القراءة"
        case .ward: "وردي"
        case .review: "المراجعة المستحقة"
        case .khatmah: "رحلة الختمة"
        case .salawat: "الصلاة على النبي ﷺ"
        }
    }
    var symbol: String {
        switch self {
        case .nextPrayer: "sun.horizon"
        case .prayerDay: "clock"
        case .dua: "hands.sparkles"
        case .shortDhikr: "sparkle"
        case .reading: "book"
        case .ward: "checkmark.circle"
        case .review: "arrow.clockwise"
        case .khatmah: "book.closed"
        case .salawat: "plus.circle"
        }
    }
    var families: [WidgetFamily] {
        switch self {
        case .prayerDay: [.systemMedium, .systemLarge]
        case .dua: [.systemSmall, .systemMedium, .systemLarge]
        case .shortDhikr: [.accessoryRectangular, .accessoryInline]
        case .nextPrayer, .ward: [.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline, .accessoryCircular]
        default: [.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline]
        }
    }
    func url(page: Int) -> URL? {
        let route: String
        switch self {
        case .nextPrayer, .prayerDay: route = "prayers"
        case .dua, .shortDhikr: route = "dua"
        case .reading: route = "reading/\(page)"
        case .ward: route = "ward"
        case .review: route = "review"
        case .khatmah: route = "khatmah"
        case .salawat: route = "salawat"
        }
        return URL(string: "nooralruh://" + route)
    }
}
struct NoorWidgetView: View {
    let entry: NoorEntry
    let kind: NoorWidgetKind
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var scheme
    @Environment(\.widgetRenderingMode) private var renderingMode
    private var inline: Bool { family == .accessoryInline }
    private var lockScreen: Bool { inline || family == .accessoryRectangular || family == .accessoryCircular }
    private var url: URL? {
        if kind == .dua || kind == .shortDhikr, let dua = entry.dua { return NoorWidgetLink.dua(dua) }
        if kind == .ward, let plan = entry.snapshot?.khatmah {
            return plan.wardURL(at: entry.date) ?? URL(string: "nooralruh://khatmah")
        }
        if kind == .ward, let id = entry.snapshot?.wardID { return NoorWidgetLink.ward(id: id, page: entry.snapshot?.wardPage) }
        return kind.url(page: entry.snapshot?.page ?? 1)
    }
    var body: some View {
        Group {
            if let dua = entry.dua, kind == .dua || kind == .shortDhikr {
                if kind == .shortDhikr {
                    Text(dua.text).font(inline ? .caption : .body).lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                } else { NoorDuaWidgetComposition(dua: dua, family: family) }
            } else if let snapshot = entry.snapshot {
                if (kind == .nextPrayer || kind == .prayerDay), !snapshot.canDisplayPrayerTimes {
                    Label("حدد موقع الصلاة في التطبيق", systemImage: "location")
                        .font(lockScreen ? .caption : .headline)
                } else if inline { Label(summary(snapshot), systemImage: kind.symbol) }
                else if family == .accessoryCircular { circular(snapshot) }
                else {
                    VStack(alignment: .leading, spacing: lockScreen ? 3 : 9) {
                        Label(kind.title, systemImage: kind.symbol).font(.caption).foregroundStyle(.secondary)
                        content(snapshot)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                }
            } else {
                Label("افتح نور الروح لإعداد الأداة", systemImage: kind.symbol).font(.subheadline)
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .environment(\.locale, Locale(identifier: "ar_SA"))
        .containerBackground(for: .widget) {
            if !lockScreen, renderingMode == .fullColor { scheme == .dark ? NoorWidgetPalette.ink : NoorWidgetPalette.ivory }
        }
        .widgetURL(url)
        .privacySensitive(kind == .reading || kind == .ward || kind == .khatmah || kind == .review)
    }
    @ViewBuilder private func circular(_ snapshot: NoorWidgetSnapshot) -> some View {
        if kind == .ward {
            if let plan = snapshot.khatmah {
                if !plan.paused, plan.finished != true, plan.nextPage <= 604,
                   let target = plan.target(at: entry.date), let count = plan.completedToday(at: entry.date) {
                    Gauge(value: Double(min(count, target)), in: 0...Double(max(1, target))) {
                        Image(systemName: "book")
                    } currentValueLabel: { Text("\(count)") }
                        .gaugeStyle(.accessoryCircular).accessibilityLabel(summary(snapshot))
                } else { Image(systemName: "book").accessibilityLabel(summary(snapshot)) }
            } else {
                Gauge(value: Double(min(snapshot.completed(at: entry.date), snapshot.dailyTarget)), in: 0...Double(max(1, snapshot.dailyTarget))) {
                    Image(systemName: "book")
                } currentValueLabel: { Text("\(snapshot.completed(at: entry.date))") }
                    .gaugeStyle(.accessoryCircular)
                    .accessibilityLabel(summary(snapshot))
            }
        } else if let next = PrayerCalculator.next(data: snapshot.prayer, now: entry.date) {
            VStack(spacing: 0) {
                Image(systemName: kind.symbol).font(.caption2)
                Text(next.name).font(.caption2)
                Text(PrayerCalculator.time(next.date, city: snapshot.prayer.city)).font(.caption2).monospacedDigit()
                    .environment(\.layoutDirection, .leftToRight)
            }.accessibilityLabel(summary(snapshot))
        } else { Image(systemName: kind.symbol).accessibilityLabel("افتح التطبيق لإعداد المواقيت") }
    }
    private func summary(_ snapshot: NoorWidgetSnapshot) -> String {
        switch kind {
        case .nextPrayer, .prayerDay:
            guard snapshot.canDisplayPrayerTimes else { return "حدد موقع الصلاة في التطبيق" }
            guard let next = PrayerCalculator.next(data: snapshot.prayer, now: entry.date) else { return "افتح التطبيق لتحديث المواقيت" }
            return "\(next.name) \(PrayerDisplay.isolatedClock(next.date, city: snapshot.prayer.city))"
        case .reading: return snapshot.hasReadingPosition == false ? "ابدأ القراءة" : "الصفحة \(snapshot.page.formatted(.number.locale(Locale(identifier: "ar_SA"))))"
        case .ward:
            if let plan = snapshot.khatmah {
                guard let ward = plan.ward(at: entry.date) else { return plan.wardTitle(at: entry.date) }
                return "\(plan.wardTitle(at: entry.date)) · \(ward.first)–\(ward.last)"
            }
            return "\(snapshot.completed(at: entry.date)) من \(snapshot.dailyTarget) آيات"
        case .review: return "\(snapshot.due(at: entry.date)) آيات للمراجعة"
        case .dua, .shortDhikr: return entry.dua?.text ?? "دعاء"
        case .khatmah:
            guard let plan = snapshot.khatmah else { return "ابدأ رحلة الختمة" }
            guard let ward = plan.ward(at: entry.date) else { return plan.wardTitle(at: entry.date) }
            return "\(plan.wardTitle(at: entry.date)) · \(ward.first)–\(ward.last)"
        case .salawat:
            let zone = snapshot.salawatTimeZone.flatMap(TimeZone.init(identifier:)) ?? .current
            return "عدد اليوم: \(snapshot.salawat?.count(at: entry.date, timeZone: zone) ?? 0)"
        }
    }
    @ViewBuilder private func content(_ snapshot: NoorWidgetSnapshot) -> some View {
        switch kind {
        case .nextPrayer:
            if snapshot.canDisplayPrayerTimes, let next = PrayerCalculator.next(data: snapshot.prayer, now: entry.date) {
                Text(summary(snapshot)).font(lockScreen ? .headline : .title2.bold())
                Text(timerInterval: entry.date...next.date, countsDown: true).font(.caption).monospacedDigit()
                    .environment(\.locale, Locale(identifier: "en_US_POSIX"))
                    .environment(\.layoutDirection, .leftToRight)
                if !lockScreen {
                    HStack {
                        Text(snapshot.prayer.city.name)
                        Spacer()
                        Text(PrayerDisplay.date(next.date, city: snapshot.prayer.city, format: "d MMMM"))
                    }.font(.caption).foregroundStyle(.secondary)
                }
            } else { Text("افتح التطبيق لتحديث المواقيت") }
        case .prayerDay:
            Text(snapshot.prayer.city.name).font(.headline)
            Text(PrayerDisplay.gregorian(entry.date, city: snapshot.prayer.city)).font(.caption).foregroundStyle(.secondary)
            if family == .systemLarge {
                Text(PrayerDisplay.hijri(entry.date, city: snapshot.prayer.city)).font(.caption).foregroundStyle(.secondary)
            }
            let rows = PrayerCalculator.rows(data: snapshot.prayer, date: entry.date)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: family == .systemLarge ? 2 : 3), spacing: 7) {
                ForEach(rows) { row in
                    VStack(spacing: 2) {
                        Text(row.name).font(.caption)
                        Text(PrayerCalculator.time(row.date, city: snapshot.prayer.city)).font(.subheadline.bold()).monospacedDigit()
                            .environment(\.layoutDirection, .leftToRight)
                    }
                }
            }
        case .dua, .shortDhikr:
            if let dua = entry.dua { Text(dua.text).fixedSize(horizontal: false, vertical: true) }
        case .reading:
            if snapshot.hasReadingPosition != false, let name = snapshot.readingChapterName { Text(name).font(.headline) }
            Text(summary(snapshot)).font(lockScreen ? .headline : .title2.bold())
            Text(snapshot.hasReadingPosition == false ? "افتح المصحف" : "أكمل من حيث توقفت").font(.caption).foregroundStyle(.secondary)
        case .ward:
            Text(summary(snapshot)).font(.headline)
            if let plan = snapshot.khatmah {
                if !plan.paused, plan.finished != true, plan.nextPage <= 604,
                   let target = plan.target(at: entry.date), let count = plan.completedToday(at: entry.date) {
                    ProgressView(value: Double(min(count, target)), total: Double(max(1, target)))
                    Text("\(count) من \(target) صفحة").font(.caption).foregroundStyle(.secondary)
                }
                if !lockScreen, plan.ward(at: entry.date) != nil { Text("أكمل وردك").font(.caption).foregroundStyle(.secondary) }
            } else {
                ProgressView(value: Double(min(snapshot.completed(at: entry.date), snapshot.dailyTarget)), total: Double(max(1, snapshot.dailyTarget)))
                if !lockScreen {
                    Text(entry.date, style: .date).font(.caption).foregroundStyle(.secondary)
                    Text("أكمل وردك").font(.caption).foregroundStyle(.secondary)
                }
            }
        case .review:
            Text(summary(snapshot)).font(.headline)
            Text(snapshot.updated, style: .date).font(.caption).foregroundStyle(.secondary)
        case .khatmah:
            Text(summary(snapshot)).font(.headline)
            if let plan = snapshot.khatmah {
                Text("\(plan.completed) من \(605 - plan.firstPage) صفحة").font(.caption)
                if !lockScreen {
                    ProgressView(value: Double(plan.completed), total: Double(605 - plan.firstPage))
                    Text("القراءة المؤكدة في التطبيق").font(.caption).foregroundStyle(.secondary)
                }
            }
        case .salawat:
            Text(summary(snapshot)).font(lockScreen ? .headline : .title2.bold())
            if let goal = snapshot.salawat?.goal {
                Text("هدفك الشخصي: \(goal)").font(.caption).foregroundStyle(.secondary)
            } else if !lockScreen { Text("افتح العداد لمتابعة الذكر").font(.caption).foregroundStyle(.secondary) }
        }
    }
}
struct NoorWidget: Widget {
    let type: NoorWidgetKind
    init() { type = .nextPrayer }
    init(type: NoorWidgetKind) { self.type = type }
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "noor." + type.rawValue, provider: NoorProvider(kind: type)) { entry in NoorWidgetView(entry: entry, kind: type) }
            .configurationDisplayName(type.title)
            .description("تابع القراءة والعبادة من شاشتك.")
            .supportedFamilies(type.families)
    }
}
@main struct NoorWidgets: WidgetBundle {
    var body: some Widget {
        NoorWidget(type: .nextPrayer)
        NoorWidget(type: .prayerDay)
        NoorWidget(type: .dua)
        NoorWidget(type: .reading)
        NoorWidget(type: .ward)
        NoorWidget(type: .review)
        NoorWidget(type: .khatmah)
        NoorWidget(type: .salawat)
        NoorWidget(type: .shortDhikr)
    }
}
