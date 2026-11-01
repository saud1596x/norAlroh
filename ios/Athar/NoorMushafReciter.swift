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
    var scopeLabel: String { supportsVersePlayback ? "من الآية المحددة" : "السورة كاملة" }
    var coverage: NoorReciterTimingCoverage? {
        guard supportsWordTracking else { return nil }
        return NoorReciterCoverageCatalog.recordings[id]
    }
    var hasCompleteWordTracking: Bool { supportsWordTracking && coverage?.isComplete == true }
    var trackingLabel: String {
        scopeLabel + " · " + (coverage?.label ?? (supportsWordTracking ? "توقيت الكلمات حسب التسجيل" : "التتبّع غير متاح"))
    }
    static var all: [Self] {
        (NoorVerseReciter.all.map { Self(id: $0.id, name: $0.name, verseDirectory: $0.id, recording: nil) }
        + NoorReciterCatalog.reciters.map {
            Self(id: "surah:\($0.id):\($0.recordingID)", name: $0.name, verseDirectory: nil, recording: $0)
        }).filter(\.hasCompleteWordTracking)
    }
    static var completeSurahReciters: [NoorReciter] { all.compactMap(\.recording) }
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
    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject private var store: AtharStore
    @State private var search = ""
    private var groups: [NoorReciterVoiceGroup] { NoorReciterVoiceGroup.matching(search) }
    private var tokens: NoorChromeTokens { .init(scheme: scheme) }
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 16) {
                    Text("اختر القارئ").font(.title2.bold()).foregroundStyle(tokens.primary)
                    Spacer(minLength: 8)
                    Button("إغلاق", systemImage: "xmark") { dismiss() }
                        .labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
                        .accessibilityIdentifier("reader.reciters.close")
                }
                NoorReciterSearchField(text: $search, identifier: "reader.reciters.search")
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(groups) { group in
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(group.recordings) { reciter in
                                    Button {
                                        onSelect(reciter); dismiss()
                                    } label: {
                                        NoorReciterRecordingLabel(reciter: reciter, selected: selectedID == reciter.id)
                                    }.buttonStyle(NoorChromePressStyle(lowMotion: store.data.lowMotion))
                                        .accessibilityIdentifier("reader.reciter.\(reciter.id)")
                                        .accessibilityLabel(group.name)
                                        .accessibilityValue(selectedID == reciter.id ? "محدد" : "")
                                        .accessibilityAddTraits(selectedID == reciter.id ? .isSelected : [])
                                }
                            }.accessibilityElement(children: .contain)
                                .accessibilityIdentifier("reader.voice.\(group.id)")
                        }
                        if groups.isEmpty {
                            ContentUnavailableView("لا يوجد قارئ مطابق", systemImage: "magnifyingglass",
                                description: Text("جرّب اسمًا آخر أو امسح البحث."))
                                .accessibilityIdentifier("reader.reciters.empty")
                        }
                    }.padding(.vertical, 8)
                }
                .scrollDismissesKeyboard(.interactively)
            }.padding(20).background(tokens.background)
                .toolbar(.hidden, for: .navigationBar)
                .environment(\.layoutDirection, .rightToLeft)
        }
    }
}
