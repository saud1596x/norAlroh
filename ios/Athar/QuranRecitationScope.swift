import SwiftUI

/// Secondary setup. The main microphone still starts the visible page directly.
struct QuranRecitationScope: View {
    let page: Int
    let pageKeys: [String]
    let initialKey: String
    let onStart: ([String]) -> Void
    @EnvironmentObject private var store: AtharStore
    @Environment(\.dismiss) private var dismiss
    @State private var scope = MushafStudySession.Scope.page
    @State private var chapter: Int
    @State private var from: Int
    @State private var to: Int

    init(page: Int, pageKeys: [String], initialKey: String, onStart: @escaping ([String]) -> Void) {
        self.page = page; self.pageKeys = pageKeys; self.initialKey = initialKey; self.onStart = onStart
        let parts = initialKey.split(separator: ":").compactMap { Int($0) }
        _chapter = State(initialValue: parts.first ?? 1)
        _from = State(initialValue: parts.count == 2 ? parts[1] : 1)
        _to = State(initialValue: parts.count == 2 ? parts[1] : 1)
    }
    private var count: Int { store.quran.first { $0.number == chapter }?.ayahs.count ?? 0 }
    private var selectedKeys: [String] {
        switch scope {
        case .page: return pageKeys
        case .surah: return count > 0 ? (1...count).map { "\(chapter):\($0)" } : []
        case .range: return count > 0 && from <= to && to <= count ? (from...to).map { "\(chapter):\($0)" } : []
        }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("اختر مقطعك").font(.title2.bold())
                    Picker("مقطع التسميع", selection: $scope) {
                        Text("صفحة").tag(MushafStudySession.Scope.page)
                        Text("سورة").tag(MushafStudySession.Scope.surah)
                        Text("آيات").tag(MushafStudySession.Scope.range)
                    }.pickerStyle(.segmented).accessibilityIdentifier("recitation.scope.kind")
                    if scope != .page {
                        Picker("السورة", selection: $chapter) {
                            ForEach(store.quran) { surah in Text(surah.name).tag(surah.number) }
                        }.pickerStyle(.menu).frame(minHeight: 44).accessibilityIdentifier("recitation.scope.chapter")
                        if scope == .range {
                            Stepper("من الآية \(from)", value: $from, in: 1...max(1, count))
                                .frame(minHeight: 44).accessibilityIdentifier("recitation.scope.from")
                            Stepper("إلى الآية \(to)", value: $to, in: from...max(from, count))
                                .frame(minHeight: 44).accessibilityIdentifier("recitation.scope.to")
                        }
                    }
                    HStack {
                        Image(systemName: "book.pages").foregroundStyle(Theme.gold).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(scope == .page ? "الصفحة \(page)" : store.quran.first { $0.number == chapter }?.name ?? "")
                                .font(.headline)
                            Text("\(selectedKeys.count) آية").font(.subheadline).foregroundStyle(.secondary)
                                .accessibilityIdentifier("recitation.scope.count")
                        }
                    }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.gold.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                    Button {
                        onStart(selectedKeys); dismiss()
                    } label: {
                        Label("ابدأ التسميع", systemImage: "mic.fill").frame(maxWidth: .infinity, minHeight: 48)
                    }.buttonStyle(.borderedProminent).tint(Theme.gold).disabled(selectedKeys.isEmpty)
                        .accessibilityIdentifier("recitation.scope.start")
                }.padding(24)
            }.background(Theme.panel)
                .navigationTitle("مقطع التسميع").navigationBarTitleDisplayMode(.inline)
                .toolbar { Button { dismiss() } label: { Text("إغلاق").frame(minWidth: 44, minHeight: 44) }.accessibilityIdentifier("recitation.scope.close") }
                .onChange(of: chapter) { _, _ in from = 1; to = 1 }
                .onChange(of: from) { _, value in if to < value { to = value } }
        }
    }
}
