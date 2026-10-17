import Foundation
import SwiftUI

/// A persisted recording identity, not a row index or a temporary audio player.
/// Whole-surah recordings never acquire invented ayah/word timestamps.
struct NoorMushafReciter: Identifiable {
    let id: String
    let name: String
    let verseDirectory: String?
    let recording: NoorReciter?
    var supportsVersePlayback: Bool { verseDirectory != nil }
    var scopeLabel: String { supportsVersePlayback ? "من الآية المحددة" : "السورة كاملة من بدايتها" }
    static var all: [Self] {
        NoorVerseReciter.all.map { .init(id: $0.id, name: $0.name, verseDirectory: $0.id, recording: nil) }
        + NoorReciterCatalog.reciters.map {
            .init(id: "surah:\($0.id):\($0.recordingID)", name: $0.name, verseDirectory: nil, recording: $0)
        }
    }
    static func selected(_ id: String) -> Self? {
        if let current = all.first(where: { $0.id == id }) { return current }
        // Restore the exact older recording, not another bitrate with a
        // similar voice name or somebody else's cached/timed media.
        guard let legacy = NoorVerseReciter.legacyRecordings.first(where: { $0.id == id }) else { return nil }
        return .init(id: legacy.id, name: legacy.name, verseDirectory: legacy.id, recording: nil)
    }
    func playbackKeys(_ verses: [String]) -> [String] {
        guard let recording else { return verses }
        var seen = Set<Int>()
        return verses.compactMap { key in
            if let (source, surah) = NoorAudioIntegrity.reciterRecording(key) {
                guard source == recording, seen.insert(surah).inserted else { return nil }
                return key
            }
            let parts = key.split(separator: ":").compactMap { Int($0) }
            guard parts.count == 2, seen.insert(parts[0]).inserted else { return nil }
            return NoorAudioIntegrity.reciterKey(recording, surah: parts[0])
        }
    }
}

struct NoorMushafReciterPicker: View {
    let selectedID: String
    let onSelect: (NoorMushafReciter) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    private var matches: [NoorMushafReciter] {
        let query = ArabicSearch.normalize(search)
        var choices = NoorMushafReciter.all
        if let saved = NoorMushafReciter.selected(selectedID), !choices.contains(where: { $0.id == saved.id }) {
            choices.insert(saved, at: 0)
        }
        return choices.filter { query.isEmpty || ArabicSearch.normalize($0.name).contains(query) }
    }
    var body: some View {
        NavigationStack {
            List {
                ForEach(matches) { reciter in
                    Button {
                        onSelect(reciter); dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(reciter.name).foregroundStyle(.primary)
                                Text(reciter.scopeLabel).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if selectedID == reciter.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.gold) }
                        }.frame(minHeight: 48)
                    }.accessibilityIdentifier("reader.reciter.\(reciter.id)")
                        .accessibilityValue(selectedID == reciter.id ? "محدد" : "")
                }
                if matches.isEmpty { Text("لا يوجد قارئ مطابق") }
            }
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "ابحث باسم القارئ")
            .navigationTitle("اختر القارئ")
            .toolbar { Button("إغلاق") { dismiss() } }
        }
    }
}
