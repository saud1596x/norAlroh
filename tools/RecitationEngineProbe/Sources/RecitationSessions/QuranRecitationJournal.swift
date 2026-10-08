import Foundation
#if canImport(RecitationAlignment)
import RecitationAlignment
#endif

public struct QuranRecitationTake: Codable, Equatable, Identifiable {
    public let id: UUID
    public let startedAt: Date
    public var frames: Int64
    public var closed: Bool
    public var duration: Double { Double(frames) / 16_000 }
    public init(id: UUID = UUID(), startedAt: Date = Date(), frames: Int64 = 0, closed: Bool = false) {
        self.id = id; self.startedAt = startedAt; self.frames = frames; self.closed = closed
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
        let knownTakes = Dictionary(uniqueKeysWithValues: takes.map { ($0.id, $0) })
        let scope = Set(keys)
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
