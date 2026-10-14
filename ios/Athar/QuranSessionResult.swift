import SwiftUI

/// Evidence coverage is distinct from correctness. Unrecognized passages never
/// become confirmed errors or an invented success percentage.
struct QuranSessionResult: View {
    let record: QuranRecitationRecord
    let wordIDs: [String: [Int]]
    let onReview: (String) -> Void
    let onListenPractice: (([String]) -> Void)?
    private let coverageCounts: [String: Int]
    init(record: QuranRecitationRecord, wordIDs: [String: [Int]], onReview: @escaping (String) -> Void,
         onListenPractice: (([String]) -> Void)? = nil) {
        self.record = record; self.wordIDs = wordIDs; self.onReview = onReview
        self.onListenPractice = onListenPractice
        let evidence = Dictionary(grouping: record.evidence, by: \.verse).mapValues { Set($0.map(\.nativeID)) }
        coverageCounts = Dictionary(uniqueKeysWithValues: record.keys.map { key in
            (key, (evidence[key] ?? []).intersection(Set(wordIDs[key] ?? [])).count)
        })
    }
    @Environment(\.dismiss) private var dismiss
    /// An open-Quran session has no assigned unread passage. Only actual
    /// evidence and review locations belong in its summary, never all 6236 ayat.
    var summaryKeys: [String] {
        guard record.automaticScope == true else { return record.keys }
        let heard = Set(record.evidence.map(\.verse))
        let review = Set((record.wordingEvents ?? []).filter { $0.state == "provisional" }.flatMap(\.referenceIDs))
        return record.keys.filter { heard.contains($0) || !Set(wordIDs[$0] ?? []).isDisjoint(with: review) }
    }
    private var contextualPractice: [String] {
        let pendingIDs = Set((record.wordingEvents ?? []).filter {
            $0.state == "provisional" && $0.resolution == nil && $0.category != "repetition"
        }.flatMap(\.referenceIDs))
        let focus = summaryKeys.first { !Set(wordIDs[$0] ?? []).isDisjoint(with: pendingIDs) }
            ?? unresolved.first ?? summaryKeys.first
        guard let focus, let index = record.keys.firstIndex(of: focus) else { return [] }
        let chapter = focus.split(separator: ":").first
        return record.keys[max(0, index-1)...min(record.keys.count-1, index+1)].filter {
            $0.split(separator: ":").first == chapter
        }
    }
    @EnvironmentObject private var store: AtharStore
    @StateObject private var attemptAudio = MushafSessionRecorder()
    @State private var replayNotice: String?
    @State private var replayRevision = UUID()
    private func replay(_ span: QuranObservedSpeech, word: QuranObservedWord? = nil) {
        let token = UUID(); replayRevision = token
        Task {
            do {
                let sessionID = record.id
                let takes = try await Task.detached(priority: .userInitiated) {
                    try MushafRecordingArchive.takes(session: sessionID)
                }.value
                guard replayRevision == token else { return }
                guard let take = takes.first(where: { $0.id == span.takeID }) else {
                    replayNotice = "التسجيل غير متاح؛ قد يكون محذوفًا أو نُقل إلى المحذوفات."; return
                }
                attemptAudio.play(take, at: max(0, (word?.startInTakeSeconds ?? span.start) - 0.75))
                replayNotice = word?.startInTakeSeconds == nil ? "الاستماع من بداية المقطع؛ توقيت الكلمة غير متاح." : nil
            } catch { replayNotice = "تعذّر فتح التسجيل. حاول بعد فتح قفل الجهاز." }
        }
    }
    private func coverage(_ key: String) -> Int {
        coverageCounts[key] ?? 0
    }
    private func complete(_ key: String) -> Bool {
        let count = wordIDs[key]?.count ?? 0
        return count > 0 && coverage(key) == count
    }
    private var unresolved: [String] { summaryKeys.filter { !complete($0) } }
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
                        if let first = summaryKeys.first, let last = summaryKeys.last {
                            Text(first == last ? reference(first) : "\(reference(first)) — \(reference(last))").font(.subheadline)
                        }
                    }
                    HStack(spacing: 24) {
                        metric("مدة التسجيل", value: MushafAudioTime.text(record.duration))
                        metric("كلمات متتبّعة", value: String(trackedCount))
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    if record.textExposureOccurred == true || !(record.textHintIDs ?? []).isEmpty {
                        Text("استُخدمت تلميحات للقراءة؛ الكلمات المكشوفة لا تُحسب كتلاوة مسموعة.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if let key = unresolved.first {
                        Button { onReview(key) } label: {
                            Label("راجع المقاطع غير المتتبّعة", systemImage: "book").frame(maxWidth: .infinity, minHeight: 44)
                        }.buttonStyle(.bordered).accessibilityIdentifier("study.result.review")
                    }
                    if let onListenPractice, !contextualPractice.isEmpty {
                        Button { onListenPractice(contextualPractice) } label: {
                            Label("استمع للمقطع ثم أعد التسميع", systemImage: "ear.and.waveform")
                                .frame(maxWidth: .infinity, minHeight: 48)
                        }.buttonStyle(.bordered).accessibilityIdentifier("study.result.contextualPractice")
                    }
                    DisclosureGroup("تفاصيل التتبع") {
                        if let events = record.wordingEvents, !events.isEmpty {
                            Text("ملاحظات تحتاج مراجعة الصوت؛ ليست أخطاء مؤكدة ولا تؤثر في تقدم الحفظ.").font(.footnote).foregroundStyle(.secondary)
                            ForEach(events.filter { $0.state == "provisional" }, id: \.eventID) { event in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(event.resolution == nil ? "راجع هذا الموضع" : event.resolution == "later-assisted-evidence"
                                         ? "ظهرت قراءة مطابقة بمساعدة؛ ليست استرجاعًا مستقلًا" : "ظهرت قراءة مطابقة لاحقًا في التسجيل")
                                    HStack {
                                        Button("استمع لمحاولتك") {
                                            if let span = record.observedSpeech?.first(where: { $0.takeID == event.takeID && $0.start <= event.start && $0.end >= event.end }) {
                                                let word = span.wordObservations?.first { event.supportingObservationIDs.contains($0.observationID) }
                                                replay(span, word: word)
                                            }
                                        }.frame(minHeight: 44)
                                        if let ids = event.correctionObservationIDs,
                                           let span = record.observedSpeech?.first(where: { source in
                                               source.wordObservations?.contains(where: { ids.contains($0.observationID) }) == true
                                           }), let word = span.wordObservations?.first(where: { ids.contains($0.observationID) }) {
                                            Button("استمع للمحاولة اللاحقة") { replay(span, word: word) }.frame(minHeight: 44)
                                        }
                                        if let key = wordIDs.first(where: { !Set($0.value).isDisjoint(with: event.referenceIDs) })?.key {
                                            Button("راجع الآية") { onReview(key) }.frame(minHeight: 44)
                                        }
                                    }
                                }.padding(.vertical, 8)
                            }
                        }
                        if let spans = record.observedSpeech, !spans.isEmpty {
                            Text("الكلمات المسموعة ليست حكمًا بصحة الحفظ أو النطق. المقاطع المتداخلة قد تكرر الكلمات.").font(.footnote).foregroundStyle(.secondary)
                            LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(spans.indices, id: \.self) { index in
                                let span = spans[index]
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("\(MushafAudioTime.text(span.start)) – \(MushafAudioTime.text(span.end))").font(.caption.monospacedDigit())
                                    Text(span.words.isEmpty ? "لم يتضح كلام قابل للتتبع" : span.words.joined(separator: " "))
                                        .font(.body).textSelection(.enabled)
                                    if let words = span.wordObservations, !words.isEmpty {
                                        ForEach(words, id: \.observationID) { word in
                                            Button { replay(span, word: word) } label: {
                                                HStack {
                                                    Text(word.observedText)
                                                    Spacer()
                                                    Image(systemName: "play.circle")
                                                    if word.recognitionState != "accepted" { Text("غير محسوم").font(.caption) }
                                                }.frame(minHeight: 44)
                                            }.buttonStyle(.plain)
                                                .accessibilityLabel("استمع إلى \(word.observedText) في تسجيلك")
                                        }
                                    } else {
                                        Button("استمع إلى المقطع") { replay(span) }.frame(minHeight: 44)
                                    }
                                    if span.unresolved { Text("يوجد صوت غير محسوم في هذا المقطع").font(.caption).foregroundStyle(.secondary) }
                                }.padding(.vertical, 8)
                            }
                            }
                        }
                        if attemptAudio.playing != nil {
                            Button("إيقاف الاستماع") { replayRevision = UUID(); attemptAudio.stop() }.frame(minHeight: 44)
                        }
                        if let notice = replayNotice ?? attemptAudio.message { Text(notice).font(.footnote) }
                        LazyVStack(alignment: .leading, spacing: 12) {
                            Text("التتبع يحدد موضع التلاوة؛ لا يقيس صحة النطق أو التجويد. المقاطع غير المتتبّعة ليست أخطاء مؤكدة.").font(.footnote).foregroundStyle(.secondary)
                            if record.recognitionUnavailable { Text("تعذّر التحليل في جزء من الجلسة؛ التسجيل الصوتي محفوظ.").font(.footnote) }
                            ForEach(summaryKeys, id: \.self) { key in
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
                .onDisappear { replayRevision = UUID(); attemptAudio.stop() }
        }
    }
    private func metric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value).font(.title2.bold()).monospacedDigit()
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }
}
