import SwiftUI

/// Evidence coverage is distinct from correctness. Unrecognized passages never
/// become confirmed errors or an invented success percentage.
struct QuranSessionResult: View {
    let record: QuranRecitationRecord
    let wordIDs: [String: [Int]]
    let onReview: (String) -> Void
    private let coverageCounts: [String: Int]
    init(record: QuranRecitationRecord, wordIDs: [String: [Int]], onReview: @escaping (String) -> Void) {
        self.record = record; self.wordIDs = wordIDs; self.onReview = onReview
        let evidence = Dictionary(grouping: record.evidence, by: \.verse).mapValues { Set($0.map(\.nativeID)) }
        coverageCounts = Dictionary(uniqueKeysWithValues: record.keys.map { key in
            (key, (evidence[key] ?? []).intersection(Set(wordIDs[key] ?? [])).count)
        })
    }
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AtharStore
    private func coverage(_ key: String) -> Int {
        coverageCounts[key] ?? 0
    }
    private func complete(_ key: String) -> Bool {
        let count = wordIDs[key]?.count ?? 0
        return count > 0 && coverage(key) == count
    }
    private var unresolved: [String] { record.keys.filter { !complete($0) } }
    private var trackedCount: Int { record.keys.reduce(0) { $0 + coverage($1) } }
    private func reference(_ key: String) -> String {
        let parts = key.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2, store.quran.indices.contains(parts[0] - 1) else { return key }
        return "\(store.quran[parts[0] - 1].name) · الآية \(parts[1])"
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "waveform.circle.fill").font(.system(size: 48)).foregroundStyle(Theme.gold).accessibilityHidden(true)
                        Text("حُفظت جلستك").font(.title2.bold()).accessibilityIdentifier("study.result.saved")
                        if let first = record.keys.first, let last = record.keys.last {
                            Text(first == last ? reference(first) : "\(reference(first)) — \(reference(last))").font(.subheadline)
                        }
                    }
                    HStack(spacing: 24) {
                        metric("مدة التسجيل", value: MushafAudioTime.text(record.duration))
                        metric("كلمات متتبّعة", value: String(trackedCount))
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    if let key = unresolved.first {
                        Button { onReview(key) } label: {
                            Label("راجع المقاطع غير المتتبّعة", systemImage: "book").frame(maxWidth: .infinity, minHeight: 44)
                        }.buttonStyle(.bordered).accessibilityIdentifier("study.result.review")
                    }
                    DisclosureGroup("تفاصيل التتبع") {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            Text("التتبع يحدد موضع التلاوة؛ لا يقيس صحة النطق أو التجويد. المقاطع غير المتتبّعة ليست أخطاء مؤكدة.").font(.footnote).foregroundStyle(.secondary)
                            if record.recognitionUnavailable { Text("تعذّر التحليل في جزء من الجلسة؛ التسجيل الصوتي محفوظ.").font(.footnote) }
                            ForEach(record.keys, id: \.self) { key in
                                Button { onReview(key) } label: {
                                    HStack {
                                        Text(reference(key))
                                        Spacer()
                                        Text(complete(key) ? "تتبع كامل" : coverage(key) > 0 ? "تتبع جزئي" : "غير محسوم").font(.caption).foregroundStyle(.secondary)
                                    }.frame(minHeight: 44)
                                }
                            }
                        }.padding(.top, 12)
                    }
                }.padding(24)
            }.background(Theme.panel)
                .navigationTitle("نتيجة التسميع").navigationBarTitleDisplayMode(.inline)
                .toolbar { Button("متابعة القراءة") { dismiss() }.accessibilityIdentifier("study.result.close") }
        }
    }
    private func metric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value).font(.title2.bold()).monospacedDigit()
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }
}
