import Foundation
import SwiftUI

/// A persisted recording identity, not a row index or a temporary audio player.
/// Whole-surah recordings never acquire invented ayah/word timestamps.
struct NoorMushafReciter: Identifiable {
    let id: String
    let name: String
    let verseDirectory: String?
    let recording: NoorReciter?
    var recordingIdentity: String { verseDirectory.map { "everyayah:" + $0 } ?? id }
    var supportsVersePlayback: Bool { verseDirectory != nil }
    var supportsWordTracking: Bool {
        if let verseDirectory {
            return recording == nil && id == verseDirectory
                && NoorReciterWordTimings.timedDirectories.contains(verseDirectory)
        }
        guard let recording, id == "surah:\(recording.id):\(recording.recordingID)" else { return false }
        return NoorSurahWordTimings.supports(recording)
    }
    var scopeLabel: String { supportsVersePlayback ? "من الآية المحددة" : "السورة كاملة من بدايتها" }
    var trackingLabel: String {
        scopeLabel + (supportsWordTracking ? " · تتبّع الكلمات، بتغطية جزئية" : " · التتبّع غير متاح")
    }
    static var all: [Self] {
        (NoorVerseReciter.all.map { Self(id: $0.id, name: $0.name, verseDirectory: $0.id, recording: nil) }
        + NoorReciterCatalog.reciters.map {
            Self(id: "surah:\($0.id):\($0.recordingID)", name: $0.name, verseDirectory: nil, recording: $0)
        }).filter(\.supportsWordTracking)
    }
    static func selected(_ id: String) -> Self? {
        // Old untimed preferences cannot reinsert an unsupported choice.
        // Cached media retains its exact identity and is never relabelled.
        all.first(where: { $0.id == id })
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
        return NoorMushafReciter.all.filter { query.isEmpty || ArabicSearch.normalize($0.name).contains(query) }
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
                                Text(reciter.trackingLabel).font(.caption).foregroundStyle(.secondary)
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
