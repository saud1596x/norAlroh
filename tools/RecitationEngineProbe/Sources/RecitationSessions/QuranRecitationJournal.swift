import Foundation
#if canImport(RecitationAlignment)
import RecitationAlignment
#endif

public struct QuranRecitationTake: Codable, Equatable, Identifiable {
    public let id: UUID
    public let startedAt: Date
    public var frames: Int64
    public var closed: Bool
    public var referenceExposure: String? = nil
    public var textHintIDs: [Int]? = nil
    public var textExposureOccurred: Bool? = nil
    public var duration: Double { Double(frames) / 16_000 }
    public init(id: UUID = UUID(), startedAt: Date = Date(), frames: Int64 = 0, closed: Bool = false) {
        self.id = id; self.startedAt = startedAt; self.frames = frames; self.closed = closed
    }
}

public struct QuranObservedWord: Codable, Equatable, Sendable {
    public let observationID: UUID
    public let occurrenceIndex: Int
    public let runIndex: Int
    public let observedText: String
    // Canonical timeline: seconds from the beginning of the associated take.
    public let startInTakeSeconds: Double?
    public let endInTakeSeconds: Double?
    public let backendConfidence: Double?
    public let recognitionState: String
    public let timingSource: String
    public init(observationID: UUID = UUID(), occurrenceIndex: Int, runIndex: Int, observedText: String,
                startInTakeSeconds: Double?, endInTakeSeconds: Double?, backendConfidence: Double?,
                recognitionState: String, timingSource: String) {
        self.observationID = observationID; self.occurrenceIndex = occurrenceIndex; self.runIndex = runIndex
        self.observedText = observedText; self.startInTakeSeconds = startInTakeSeconds
        self.endInTakeSeconds = endInTakeSeconds; self.backendConfidence = backendConfidence
        self.recognitionState = recognitionState; self.timingSource = timingSource
    }
}
public struct QuranObservedSpeech: Codable, Equatable, Sendable {
    public let takeID: UUID
    public let start: Double
    public let end: Double
    public let words: [String]
    public let unresolved: Bool
    public let backendID: String
    public let modelID: String?
    public let modelRevision: String?
    public var evidenceVersion: Int? = nil
    public var recognitionWindowID: UUID? = nil
    public var recognitionRevision: Int? = nil
    public var wordObservations: [QuranObservedWord]? = nil
    public var processingConfiguration: String? = nil
    public init(takeID: UUID, start: Double, end: Double, words: [String], unresolved: Bool, backendID: String,
                modelID: String? = nil, modelRevision: String? = nil) {
        self.takeID = takeID; self.start = start; self.end = end; self.words = words
        self.unresolved = unresolved; self.backendID = backendID
        self.modelID = modelID; self.modelRevision = modelRevision
    }
}
public struct QuranRecitationRecord: Codable, Identifiable {
    public enum Phase: String, Codable { case recording, paused, interrupted, finished }
    public let version: Int
    public let id: UUID
    public let startedAt: Date
    public let keys: [String]
    public let originPage: Int
    public var phase: Phase
    public var takes: [QuranRecitationTake]
    public var evidence: [QuranWordEvidence]
    public var recognitionUnavailable: Bool
    public var finishedAt: Date?
    public var observedSpeech: [QuranObservedSpeech]? = nil
    public var wordingEvents: [QuranWordingEvent]? = nil
    public var closedTextRequested: Bool? = nil
    public var automaticScope: Bool? = nil
    public var textExposureOccurred: Bool? = nil
    public var referenceExposure: String? = nil
    public var textHintIDs: [Int]? = nil
    public var duration: Double { takes.reduce(0) { $0 + $1.duration } }
    public init(keys: [String], originPage: Int, date: Date = Date()) {
        version = 1; id = UUID(); startedAt = date; self.keys = keys; self.originPage = originPage
        phase = .paused; takes = []; evidence = []; recognitionUnavailable = false
    }
    public func validate() throws {
        guard version == 1, !keys.isEmpty, keys.count <= 6236,
              keys.count == Set(keys).count, (1...604).contains(originPage),
              startedAt.timeIntervalSince1970.isFinite, takes.count <= 10_000,
              Set(takes.map(\.id)).count == takes.count, evidence.count <= 1_000_000,
              keys.allSatisfy({ key in
                  let parts = key.split(separator: ":").compactMap { Int($0) }
                  return parts.count == 2 && (1...114).contains(parts[0]) && (1...286).contains(parts[1])
                      && key == "\(parts[0]):\(parts[1])"
              }), takes.allSatisfy({ $0.frames >= 0 && $0.frames <= 16_000 * 86_400
                  && $0.startedAt >= startedAt && $0.startedAt.timeIntervalSince1970.isFinite }) else {
            throw QuranJournalFailure.invalidRecord
        }
        guard (textHintIDs?.count ?? 0) <= 77_429, (textHintIDs ?? []).allSatisfy({ $0 > 0 }),
              takes.allSatisfy({ ($0.textHintIDs?.count ?? 0) <= 77_429 && ($0.textHintIDs ?? []).allSatisfy { $0 > 0 } }) else {
            throw QuranJournalFailure.invalidRecord
        }
        let knownTakes = Dictionary(uniqueKeysWithValues: takes.map { ($0.id, $0) })
        guard (observedSpeech?.count ?? 0) <= 100_000,
              (observedSpeech ?? []).allSatisfy({ span in
                  guard let take = knownTakes[span.takeID] else { return false }
                  return span.start.isFinite && span.end.isFinite && span.start >= 0 && span.end > span.start
                      && span.end <= take.duration + 0.1 && span.words.count <= 1000
                      && span.words.allSatisfy { !$0.isEmpty && $0.utf8.count <= 1024 }
                      && !span.backendID.isEmpty && span.backendID.utf8.count <= 256
                      && (span.modelID.map { !$0.isEmpty && $0.utf8.count <= 256 } ?? true)
                      && (span.modelRevision.map { !$0.isEmpty && $0.utf8.count <= 256 } ?? true)
                      && (span.evidenceVersion == nil || span.evidenceVersion == 1)
                      && (span.wordObservations == nil || (span.evidenceVersion == 1
                          && span.recognitionWindowID != nil && (span.recognitionRevision ?? -1) >= 0))
                      && (span.wordObservations.map { words in
                          words.count <= 1000 && Set(words.map(\.observationID)).count == words.count
                          && words.allSatisfy { word in
                              guard word.occurrenceIndex >= 0, word.runIndex >= 0,
                                    !word.observedText.isEmpty, word.observedText.utf8.count <= 1024,
                                    word.backendConfidence.map({ $0.isFinite && (0...1).contains($0) }) ?? true else { return false }
                              if let start = word.startInTakeSeconds, let end = word.endInTakeSeconds {
                                  return start.isFinite && end.isFinite && start >= span.start && end > start
                                      && end <= span.end + 0.001 && end <= take.duration + 0.1
                                      && word.timingSource == "backend-word"
                              }
                              return word.startInTakeSeconds == nil && word.endInTakeSeconds == nil
                                  && word.timingSource == "unavailable"
                          }
                      } ?? true)
              }) else { throw QuranJournalFailure.invalidRecord }
        let scope = Set(keys)
        let observedWords = Dictionary(grouping: (observedSpeech ?? []).flatMap { span in
            (span.wordObservations ?? []).map { (span.takeID, $0) }
        }, by: { $0.1.observationID })
        guard (wordingEvents?.count ?? 0) <= 100_000,
              (wordingEvents ?? []).allSatisfy({ event in
                  guard let take = knownTakes[event.takeID] else { return false }
                  return event.start.isFinite && event.end.isFinite && event.start >= 0 && event.end > event.start
                      && event.end <= take.duration + 0.1 && ["provisional", "superseded"].contains(event.state)
                      && event.revision >= 0
                      && ["substitution", "omission", "insertion", "repetition", "transposition", "skipped-passage"].contains(event.category)
                      && event.referenceIDs.count <= 128
                      && !event.supportingObservationIDs.isEmpty && event.supportingObservationIDs.count <= 160
                      && event.supportingObservationIDs.allSatisfy { id in
                          observedWords[id]?.contains(where: { observed in
                              observed.0 == event.takeID && observed.1.startInTakeSeconds.map { $0 >= event.start } == true
                                  && observed.1.endInTakeSeconds.map { $0 <= event.end + 0.001 } == true
                          }) == true
                      }
                      && (event.resolution == nil || ["later-independent-evidence", "later-assisted-evidence"].contains(event.resolution!))
                      && (event.resolution == nil) == (event.correctionObservationIDs == nil)
                      && (event.correctionObservationIDs.map { ids in
                          !ids.isEmpty && ids.count <= 160 && ids.allSatisfy { observedWords[$0] != nil }
                      } ?? true)
                      && event.referenceIDs.allSatisfy { $0 > 0 }
              }) else { throw QuranJournalFailure.invalidRecord }
        guard evidence.allSatisfy({ word in
            guard let take = knownTakes[word.takeID] else { return false }
            return word.nativeID > 0 && scope.contains(word.verse)
                && word.start.isFinite && word.end.isFinite && word.start >= 0 && word.end > word.start
                && word.end <= take.duration + 0.1 && word.minimumConfidence.isFinite
                && (0.75...1).contains(word.minimumConfidence)
        }), finishedAt.map({ $0 >= startedAt && $0.timeIntervalSince1970.isFinite }) ?? true,
              (phase == .finished) == (finishedAt != nil),
              phase == .recording || takes.allSatisfy(\.closed) else { throw QuranJournalFailure.invalidRecord }
    }
}

public enum QuranJournalFailure: Error { case invalidRecord, existingSession, identityChanged }

/// Atomic per-session metadata, alongside independent audio files. Loading a
/// corrupt file throws; it never silently replaces user history with empty data.
public struct QuranRecitationJournal {
    public let root: URL
    public init(root: URL) { self.root = root }
    public func folder(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString, isDirectory: true) }
    public func audio(session: UUID, take: UUID) -> URL {
        folder(session).appendingPathComponent(take.uuidString + ".caf")
    }
    private func metadata(_ id: UUID) -> URL { folder(id).appendingPathComponent("recognized-session.json") }
    public func create(_ record: QuranRecitationRecord) throws {
        try record.validate()
        guard !FileManager.default.fileExists(atPath: metadata(record.id).path) else {
            throw QuranJournalFailure.existingSession
        }
        try FileManager.default.createDirectory(at: folder(record.id), withIntermediateDirectories: true)
        #if os(iOS)
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: folder(record.id).path)
        #endif
        try write(record)
    }
    public func load(_ id: UUID) throws -> QuranRecitationRecord {
        let url = metadata(id)
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= 64_000_000 else { throw QuranJournalFailure.invalidRecord }
        let record = try JSONDecoder().decode(QuranRecitationRecord.self, from: Data(contentsOf: url))
        guard record.id == id else { throw QuranJournalFailure.identityChanged }
        try record.validate(); return record
    }
    public func save(_ record: QuranRecitationRecord) throws {
        try record.validate()
        let original = try load(record.id)
        guard original.id == record.id, original.startedAt == record.startedAt,
              original.keys == record.keys, original.originPage == record.originPage else {
            throw QuranJournalFailure.identityChanged
        }
        try write(record)
    }
    private func write(_ record: QuranRecitationRecord) throws {
        let bytes = try JSONEncoder().encode(record)
        #if os(iOS)
        try bytes.write(to: metadata(record.id), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try bytes.write(to: metadata(record.id), options: .atomic)
        #endif
        var directory = folder(record.id)
        var attributes = URLResourceValues(); attributes.isExcludedFromBackup = true
        try directory.setResourceValues(attributes)
    }
}
