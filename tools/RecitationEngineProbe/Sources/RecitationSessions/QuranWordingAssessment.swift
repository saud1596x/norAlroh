import Foundation
#if canImport(RecitationAlignment)
import RecitationAlignment
#endif

public struct QuranWordingEvent: Codable, Equatable, Sendable {
    public let eventID: UUID
    public let takeID: UUID
    public let referenceIDs: [Int]
    public let supportingObservationIDs: [UUID]
    public let start: Double
    public let end: Double
    public let category: String
    public var state: String = "provisional"
    public var revision: Int = 0
    public var resolution: String? = nil
    public var correctionObservationIDs: [UUID]? = nil
    public var assessmentPolicyVersion: String = "context-dp-development-1"
}

/// Edit costs rank sequence hypotheses; they are not correctness probabilities.
/// This policy has no calibrated acoustic confirmation and never issues a
/// confirmed learner mistake. Reference text cannot replace source observations.
public enum QuranWordingAssessment {
    /// Cross-take retries require a fresh microphone occurrence and a unique
    /// five-word context. Listening exposure remains assisted evidence.
    public static func linkLaterAttempts(_ events: [QuranWordingEvent], spans: [QuranObservedSpeech],
                                         takes: [QuranRecitationTake], expected: [QuranAlignedWord]) -> [QuranWordingEvent] {
        guard expected.count >= 5, expected.count <= 77_429,
              events.contains(where: { $0.state == "provisional" && $0.resolution == nil }) else { return events }
        let known = Dictionary(uniqueKeysWithValues: takes.map { ($0.id, $0) })
        let forms = expected.map { Set($0.aliases.filter { $0.count == 1 }.map { QuranAlignedWord.normalize($0[0]) }) }
        var starts: [String: [Int]] = [:]
        for start in 0..<(forms.count - 4) {
            for left in forms[start] { for right in forms[start + 1] {
                starts[left + " " + right, default: []].append(start)
            } }
        }
        var result = events
        for index in result.indices.suffix(256) where result[index].state == "provisional" && result[index].resolution == nil {
            guard let target = result[index].referenceIDs.first,
                  let position = expected.firstIndex(where: { $0.id == target }), position >= 2,
                  position + 2 < expected.count, let original = known[result[index].takeID] else { continue }
            for span in reconciledWindows(spans) where span.takeID != original.id {
                guard let later = known[span.takeID], later.startedAt > original.startedAt else { continue }
                for run in contiguousAcceptedSpans(span) {
                    let words = run.wordObservations ?? []
                    guard words.count >= 5 else { continue }
                    for offset in 0...(words.count - 5) {
                        let context = Array(words[offset..<(offset + 5)])
                        let tokens = context.map { QuranAlignedWord.normalize($0.observedText) }
                        let candidates = starts[tokens[0] + " " + tokens[1]] ?? []
                        guard candidates.count <= 16 else { continue }
                        let matches = Set(candidates.filter { start in
                            (0..<5).allSatisfy { forms[start + $0].contains(tokens[$0]) }
                        })
                        guard matches == Set([position - 2]) else { continue }
                        result[index].resolution = later.referenceExposure == nil ? "later-independent-evidence" : "later-assisted-evidence"
                        result[index].correctionObservationIDs = context.map(\.observationID)
                        break
                    }
                    if result[index].resolution != nil { break }
                }
                if result[index].resolution != nil { break }
            }
        }
        return result
    }
    /// A newer recognizer hypothesis can retract a provisional finding. Keep
    /// that prior interpretation auditable; it is not a learner correction.
    public static func reconcile(previous: [QuranWordingEvent], incoming: [QuranWordingEvent],
                                 reconsidered: [QuranObservedSpeech]) -> [QuranWordingEvent] {
        let beginnings = Dictionary(grouping: reconsidered, by: \.takeID).mapValues { $0.map(\.start).min()! }
        var updated = previous
        var replacements = incoming
        for index in updated.indices where updated[index].state == "provisional" {
            let old = updated[index]
            let replacementIndex = replacements.firstIndex(where: { $0.eventID == old.eventID })
            let affected = beginnings[old.takeID].map { old.end >= $0 } ?? false
            guard affected || replacementIndex != nil else { continue }
            if let replacement = replacementIndex {
                var compared = replacements[replacement]; compared.revision = old.revision
                if compared == old { replacements.remove(at: replacement); continue }
                replacements[replacement].revision = max(old.revision + 1, replacements[replacement].revision)
            }
            updated[index].state = "superseded"
        }
        for var event in replacements {
            guard !updated.contains(where: { $0.eventID == event.eventID && $0.state == "provisional" }) else { continue }
            if let prior = updated.filter({ $0.eventID == event.eventID }).map(\.revision).max() {
                event.revision = max(event.revision, prior + 1)
            }
            updated.append(event)
        }
        return updated
    }
    private struct Step { let kind: String; let reference: Int; let observed: Int }
    private struct Alignment { let steps: [Step]; let cost: Int }
    public static func evaluate(_ spans: [QuranObservedSpeech], expected: [QuranAlignedWord]) -> [QuranWordingEvent] {
        guard !expected.isEmpty, expected.count <= 77_429 else { return [] }
        let forms = expected.map { word in Set(word.aliases.map { $0.map { QuranAlignedWord.normalize($0) } }) }
        var anchors: [String: Set<Int>] = [:]
        if forms.count > 1 {
            for j in 0..<(forms.count - 1) {
                for left in forms[j] where left.count == 1 {
                    for right in forms[j + 1] where right.count == 1 {
                        anchors[left[0] + " " + right[0], default: []].insert(j)
                    }
                }
            }
        }
        var events: [QuranWordingEvent] = []
        for span in reconciledWindows(spans).flatMap({ contiguousAcceptedSpans($0) }) {
            guard let words = span.wordObservations, (4...160).contains(words.count),
                  words.allSatisfy({ $0.recognitionState == "accepted" && $0.startInTakeSeconds != nil && $0.endInTakeSeconds != nil }),
                  zip(words, words.dropFirst()).allSatisfy({ $0.startInTakeSeconds! <= $1.startInTakeSeconds! }) else { continue }
            let tokens = words.map { QuranAlignedWord.normalize($0.observedText) }
            // Unique consecutive two-word anchors bound the local DP. Ambiguous
            // competing passages abstain rather than receiving a forced error.
            var candidateStarts = Set<Int>()
            for i in 0..<(tokens.count - 1) {
                for j in anchors[tokens[i] + " " + tokens[i + 1]] ?? [] {
                    candidateStarts.insert(max(0, j - i - 4))
                }
            }
            guard candidateStarts.count <= 16 else { continue }
            var best: (Alignment, Int)?
            var ambiguous = false
            for start in candidateStarts.sorted() {
                let end = min(forms.count, start + 64)
                let aligned = align(tokens, forms: Array(forms[start..<end]))
                if best == nil || aligned.cost < best!.0.cost { best = (aligned, start); ambiguous = false }
                else if aligned.cost == best!.0.cost {
                    let old = best!.0.steps.filter { $0.kind == "match" }.map { $0.reference + best!.1 }
                    let new = aligned.steps.filter { $0.kind == "match" }.map { $0.reference + start }
                    if old != new { ambiguous = true }
                }
            }
            guard !ambiguous, let (alignment, base) = best else { continue }
            let steps = alignment.steps
            for index in steps.indices where steps[index].kind != "match" {
                let step = steps[index]
                // Both sides need consecutive stable context. Rejected audio,
                // recording ends and silence cannot establish an omitted word.
                guard index >= 2, index + 2 < steps.count,
                      steps[index - 1].kind == "match", steps[index - 2].kind == "match",
                      steps[index + 1].kind == "match", steps[index + 2].kind == "match" else { continue }
                let before = words[steps[index - 1].observed], after = words[steps[index + 1].observed]
                guard after.startInTakeSeconds! - before.endInTakeSeconds! <= 2 else { continue }
                let insertion = step.kind == "insertion"
                let reference = base + step.reference
                guard expected.indices.contains(reference) else { continue }
                let support = step.kind == "omission" ? [before, after] : [words[step.observed]]
                var category = step.kind
                if insertion && step.observed > 0 && tokens[step.observed] == tokens[step.observed - 1] { category = "repetition" }
                let event = QuranWordingEvent(eventID: support[0].observationID, takeID: span.takeID,
                    referenceIDs: insertion ? [] : [expected[reference].id],
                    supportingObservationIDs: support.map(\.observationID),
                    start: support[0].startInTakeSeconds!, end: support.last!.endInTakeSeconds!, category: category)
                if !events.contains(where: { $0.takeID == event.takeID && $0.referenceIDs == event.referenceIDs && $0.category == event.category
                    && max($0.start, event.start) < min($0.end, event.end) }) { events.append(event) }
            }
            // Only a later, complete, exact contextual occurrence in the same
            // microphone take can support independent correction. App playback
            // cannot occur while this take owns audio focus.
            if alignment.cost == 0 {
                for index in events.indices where events[index].takeID == span.takeID && events[index].end < words[0].startInTakeSeconds! {
                    let matching = steps.indices.filter { position in
                        position >= 2 && position + 2 < steps.count
                            && steps[(position - 2)...(position + 2)].allSatisfy { $0.kind == "match" }
                            && events[index].referenceIDs.contains(expected[base + steps[position].reference].id)
                    }.map { steps[$0] }
                    if !matching.isEmpty {
                        events[index].resolution = "later-independent-evidence"
                        events[index].correctionObservationIDs = matching.map { words[$0.observed].observationID }
                        events[index].revision += 1
                    }
                }
            }
        }
        return events
    }
    private static func reconciledWindows(_ spans: [QuranObservedSpeech]) -> [QuranObservedSpeech] {
        var used: [QuranObservedSpeech] = []
        // A newer interpretation of the same audio replaces an older hypothesis
        // for assessment, while every source window remains in the journal.
        for span in spans.suffix(16) {
            used.removeAll { $0.takeID == span.takeID && $0.start == span.start && $0.end == span.end }
            used.append(span)
        }
        var conflicting = Set<Int>()
        for left in used.indices {
            for right in used.indices where right > left && used[left].takeID == used[right].takeID
                && max(used[left].start, used[right].start) < min(used[left].end, used[right].end) {
                let conflict = (used[left].wordObservations ?? []).contains { a in
                    guard let start = a.startInTakeSeconds, let end = a.endInTakeSeconds else { return false }
                    return (used[right].wordObservations ?? []).contains { b in
                        guard let otherStart = b.startInTakeSeconds, let otherEnd = b.endInTakeSeconds else { return false }
                        let overlap = min(end, otherEnd) - max(start, otherStart)
                        return abs(start - otherStart) <= 0.25 && overlap > 0
                            && overlap >= min(end - start, otherEnd - otherStart) * 0.5
                            && QuranAlignedWord.normalize(a.observedText) != QuranAlignedWord.normalize(b.observedText)
                    }
                }
                if conflict { conflicting.insert(left); conflicting.insert(right) }
            }
        }
        return used.indices.filter { !conflicting.contains($0) }.map { used[$0] }
    }
    private static func contiguousAcceptedSpans(_ source: QuranObservedSpeech) -> [QuranObservedSpeech] {
        var result: [QuranObservedSpeech] = [], run: [QuranObservedWord] = []
        func flush() {
            if run.count >= 4 {
                var span = source; span.wordObservations = run
                result.append(span)
            }
            run = []
        }
        for word in source.wordObservations ?? [] {
            guard word.recognitionState == "accepted", let start = word.startInTakeSeconds,
                  let end = word.endInTakeSeconds, start.isFinite, end.isFinite, end > start else { flush(); continue }
            if let last = run.last, (last.runIndex != word.runIndex || start < last.startInTakeSeconds!
                || start - last.endInTakeSeconds! > 2) { flush() }
            run.append(word)
        }
        flush(); return result
    }
    private static func align(_ tokens: [String], forms: [Set<[String]>]) -> Alignment {
        let n = tokens.count, m = forms.count, width = m + 1
        var costs = [Int](repeating: 10_000, count: (n + 1) * width)
        var previous = [(Int, Int, String)](repeating: (0, 0, ""), count: costs.count)
        for j in 0...m { costs[j] = 0 }
        func update(_ i: Int, _ j: Int, from a: Int, _ b: Int, cost: Int, kind: String) {
            let value = costs[a * width + b] + cost, target = i * width + j
            if value < costs[target] { costs[target] = value; previous[target] = (a, b, kind) }
        }
        for i in 0...n {
            for j in 0...m {
                if i < n && j < m {
                    for form in forms[j] where !form.isEmpty && i + form.count <= n && Array(tokens[i..<(i + form.count)]) == form {
                        update(i + form.count, j + 1, from: i, j, cost: 0, kind: "match")
                    }
                    update(i + 1, j + 1, from: i, j, cost: 1, kind: "substitution")
                }
                if i < n { update(i + 1, j, from: i, j, cost: 1, kind: "insertion") }
                if j < m { update(i, j + 1, from: i, j, cost: 1, kind: "omission") }
            }
        }
        let end = (0...m).min { costs[n * width + $0] < costs[n * width + $1] } ?? 0
        var i = n, j = end, steps: [Step] = []
        while i > 0 {
            let (a, b, kind) = previous[i * width + j]
            guard a < i || b < j else { break }
            steps.append(.init(kind: kind, reference: b, observed: a))
            i = a; j = b
        }
        return Alignment(steps: Array(steps.reversed()), cost: costs[n * width + end])
    }
}
