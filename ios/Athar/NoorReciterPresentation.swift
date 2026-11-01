import Foundation
import CryptoKit
import SwiftUI

struct NoorReciterTimingCoverage: Decodable, Equatable {
    let timedWords: Int
    let totalWords: Int
    let timedVerses: Int
    let totalVerses: Int
    let onlyMissingFirstBasmala: Bool
    var isComplete: Bool { timedWords == totalWords && timedVerses == totalVerses }
    var label: String {
        if isComplete { return "توقيت الكلمات متاح لجميع الآيات" }
        if onlyMissingFirstBasmala { return "توقيت الكلمات متاح عدا بسملة الفاتحة" }
        return "توقيت الكلمات متاح بتغطية جزئية"
    }
    var valid: Bool {
        totalWords > 0 && totalWords < 120_000 && timedWords > 0 && timedWords <= totalWords &&
        totalVerses > 0 && totalVerses < 10_000 && timedVerses > 0 && timedVerses <= totalVerses &&
        (!onlyMissingFirstBasmala || (timedWords < totalWords && timedVerses + 1 == totalVerses))
    }
}

enum NoorReciterCoverageCatalog {
    // Generated from the actual pinned word-timing payloads and native IDs by
    // build-reciter-picker-coverage.py. No large JSON decode in a SwiftUI body.
    static let digest = "9d26b3076b28904878d6d01157b9246a8b740ab37960b7cd71ac8c821d56131a"
    private struct Document: Decodable {
        let schema: Int
        let scope: String
        let nativeSnapshotSHA256: String
        let sourceSHA256: [String: String]
        let recordings: [String: NoorReciterTimingCoverage]
    }
    static let recordings: [String: NoorReciterTimingCoverage] = {
        guard let url = Bundle.main.url(forResource: "reciter-picker-coverage", withExtension: "json"),
              let bytes = try? Data(contentsOf: url), bytes.count < 32_000,
              SHA256.hash(data: bytes).map({ String(format: "%02x", $0) }).joined() == digest,
              let document = try? JSONDecoder().decode(Document.self, from: bytes), document.schema == 1,
              document.scope == "PUBLISHED_TIMING_COVERAGE_NOT_AUDIBLE_APPROVAL",
              document.nativeSnapshotSHA256 == "37544d69f3615fa2040be516eb2ba57c62fa25741332e3ba67f31f2a6df292d1",
              document.sourceSHA256 == ["reciter-word-timings.json": NoorReciterWordTimings.digest,
                                         "surah-word-timings.json": NoorSurahWordTimings.digest,
                                         "additional-surah-word-timings.json": NoorAdditionalReciters.timingDigest],
              document.recordings.values.allSatisfy(\.valid) else { return [:] }
        return document.recordings
    }()
}

struct NoorReciterVoiceGroup: Identifiable {
    let id: String
    let name: String
    let recordings: [NoorMushafReciter]
    static func matching(_ search: String, recordings: [NoorMushafReciter] = NoorMushafReciter.all) -> [Self] {
        let query = ArabicSearch.normalize(search)
        var order: [String] = [], choices: [String: [NoorMushafReciter]] = [:]
        for recording in recordings {
            let key = ArabicSearch.normalize(recording.name)
            if choices[key] == nil { order.append(key) }
            choices[key, default: []].append(recording)
        }
        return order.compactMap { key in
            guard query.isEmpty || key.contains(query), let values = choices[key], let first = values.first else { return nil }
            return .init(id: key, name: first.name, recordings: values)
        }
    }
}

struct NoorReciterSearchField: View {
    @Binding var text: String
    let identifier: String
    @Environment(\.colorScheme) private var scheme
    @FocusState private var focused: Bool
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
            TextField("ابحث باسم القارئ", text: $text)
                .font(.body).textInputAutocapitalization(.never).autocorrectionDisabled()
                .submitLabel(.search).focused($focused).onSubmit { focused = false }
                .accessibilityIdentifier(identifier)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        .frame(minWidth: 44, minHeight: 44)
                }.buttonStyle(.plain).accessibilityLabel("مسح البحث")
                    .accessibilityIdentifier(identifier + ".clear")
            }
        }.padding(.horizontal, 16).frame(minHeight: 52)
            .background(NoorChromeTokens(scheme: scheme).surface, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct NoorReciterRecordingLabel: View {
    let reciter: NoorMushafReciter
    let selected: Bool
    @Environment(\.colorScheme) private var scheme
    private var tokens: NoorChromeTokens { .init(scheme: scheme) }
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(reciter.scopeLabel).font(.headline).foregroundStyle(tokens.primary)
                Text(reciter.coverage?.label ?? "توقيت الكلمات حسب التسجيل")
                    .font(.subheadline).foregroundStyle(tokens.secondary)
            }.fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if selected {
                Image(systemName: "checkmark.circle.fill").font(.title3)
                    .foregroundStyle(tokens.primary).accessibilityHidden(true)
            }
        }.padding(16).frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
            .background(tokens.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).stroke(tokens.primary.opacity(selected ? 0.45 : 0.1), lineWidth: selected ? 1.5 : 1) }
            .contentShape(RoundedRectangle(cornerRadius: 12))
    }
}
