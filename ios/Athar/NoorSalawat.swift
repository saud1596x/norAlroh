import SwiftUI

@MainActor final class NoorSalawatStore: ObservableObject {
    @Published private(set) var counts = NoorSalawatCounts()
    @Published var error: String?
    private let file: URL
    private var unreadable = false
    var exportBytes: Data? { try? Data(contentsOf: file) }
    init(file: URL? = nil) {
        self.file = file ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("noor-salawat-v1.json")
        guard FileManager.default.fileExists(atPath: self.file.path) else { return }
        do {
            let value = try JSONDecoder().decode(NoorSalawatCounts.self, from: Data(contentsOf: self.file))
            guard value.valid else { throw CocoaError(.fileReadCorruptFile) }
            counts = value
        } catch { unreadable = true; self.error = "تعذر فتح سجل العداد؛ بقي محفوظًا دون تغيير. صدّر بياناتك من الإعدادات." }
    }
    @discardableResult func increment(at date: Date = .now, timeZone: TimeZone = .current) -> Bool {
        let current = counts.count(at: date, timeZone: timeZone)
        guard current < Int.max else { return false }
        return setCount(current + 1, at: date, timeZone: timeZone)
    }
    @discardableResult func setCount(_ count: Int, at date: Date = .now, timeZone: TimeZone = .current) -> Bool {
        guard count >= 0 else { return false }
        var next = counts; next.days[NoorSalawatCounts.dayKey(date, timeZone: timeZone)] = count
        return save(next)
    }
    @discardableResult func setGoal(_ goal: Int?) -> Bool {
        guard goal.map({ $0 > 0 }) ?? true else { return false }
        var next = counts; next.goal = goal; return save(next)
    }
    private func save(_ value: NoorSalawatCounts) -> Bool {
        guard !unreadable else { error = "السجل يحتاج إصلاحًا؛ صدّر بياناتك قبل تغييره. بقي العدد السابق محفوظًا."; return false }
        guard value.valid else { return false }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(value).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            counts = value; error = nil; return true
        } catch { self.error = "تعذر حفظ العداد. بقي العدد السابق؛ حاول مجددًا بعد فتح قفل الجهاز."; return false }
    }
    @discardableResult func erase() -> Bool {
        do {
            if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
            counts = .init(); unreadable = false; error = nil; return true
        } catch { self.error = "تعذر حذف سجل العداد؛ بقي محفوظًا."; return false }
    }
}

struct NoorSalawatView: View {
    @EnvironmentObject private var counter: NoorSalawatStore
    @State private var reset = false
    @State private var goal = ""
    private var entry: DhikrEntry? { AdhkarContent.shared?.entries.first { $0.id == "hisn-107-219" } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("الصلاة على النبي ﷺ").font(.largeTitle.bold()).foregroundStyle(Theme.gold)
                if let entry {
                    Card { Text(entry.text).font(.title3).fixedSize(horizontal: false, vertical: true); Text(entry.reference).font(.caption).foregroundStyle(.secondary) }
                }
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    let count = counter.counts.count(at: context.date)
                    Card {
                        Text("عدد اليوم").font(.headline)
                        Text(verbatim: String(count)).font(.largeTitle.bold().monospacedDigit())
                            .accessibilityIdentifier("salawat.count").accessibilityValue(String(count))
                        PrimaryButton(title: "صلّيت على النبي ﷺ", icon: "plus") { _ = counter.increment() }
                            .accessibilityIdentifier("salawat.increment")
                        HStack {
                            Button("تراجع عن آخر ضغطة") { _ = counter.setCount(max(0, counter.counts.count(at: .now) - 1)) }.disabled(count == 0).frame(minHeight: 44)
                                .accessibilityIdentifier("salawat.undo")
                            Spacer()
                            Button("تصفير اليوم") { reset = true }.frame(minHeight: 44)
                        }
                        if let target = counter.counts.goal {
                            Text("هدفك الشخصي: \(count) من \(target)")
                            ProgressView(value: Double(min(count, target)), total: Double(target))
                        }
                        Text("العدد يتجدد عند منتصف الليل حسب وقت جهازك. يبقى سجل الأيام السابقة محفوظًا، ويمكنك المتابعة بعد بلوغ هدفك.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Card {
                    Text("هدف شخصي اختياري").font(.headline)
                    Text("اختر عددًا يناسبك؛ العداد لا يفرض عددًا تعبديًا.").font(.caption).foregroundStyle(.secondary)
                    TextField("عدد الهدف", text: $goal).keyboardType(.numberPad).textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("salawat.goal")
                    Button("حفظ الهدف") { if let number = Int(goal), counter.setGoal(number) { goal = String(number) } }
                        .disabled(Int(goal).map { $0 > 0 } != true).frame(minHeight: 44)
                    Button("المتابعة دون هدف") { if counter.setGoal(nil) { goal = "" } }.frame(minHeight: 44)
                    NavigationLink("إعداد تذكير الصلاة على النبي") { PrayerNotificationSettings() }.frame(minHeight: 44)
                }
            }.padding(20)
        }.background(Theme.background).navigationTitle("عداد الصلاة على النبي")
            .onAppear { goal = counter.counts.goal.map(String.init) ?? "" }
            .confirmationDialog("تصفير عداد اليوم؟", isPresented: $reset, titleVisibility: .visible) {
                Button("تصفير اليوم", role: .destructive) { _ = counter.setCount(0) }
                Button("إلغاء", role: .cancel) {}
            }
            .alert("العداد", isPresented: Binding(get: { counter.error != nil }, set: { if !$0 { counter.error = nil } })) {
                Button("حسنًا") { counter.error = nil }
            } message: { Text(counter.error ?? "") }
    }
}
