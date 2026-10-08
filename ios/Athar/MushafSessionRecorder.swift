import Foundation
import AVFoundation
import UIKit
import Combine

struct MushafRecordingTake: Identifiable {
    let id: UUID
    let session: UUID
    let url: URL
    let date: Date
    let duration: TimeInterval
}

struct MushafRecordingSessionRow: Identifiable {
    let id: UUID
    let date: Date
    let metadata: MushafRecordingSessionMetadata?
    let duration: TimeInterval
    let takeCount: Int
    let recoverableDeleted: Bool
}

struct MushafRecordingFileMetadata: Codable {
    let id: UUID
    let bytes: Int
    var deleted: Bool? = nil
}
struct MushafRecordingExport: Codable {
    let session: UUID
    let metadata: MushafRecordingSessionMetadata?
    let unreadableMetadata: Data?
    let files: [MushafRecordingFileMetadata]
    let recognizedSession: Data?
}

struct MushafRecordingSessionMetadata: Codable, Equatable, Identifiable {
    let id: UUID
    let startedAt: Date
    let scope: MushafStudySession.Scope
    let keys: [String]
    let page: Int?
    init(_ session: MushafStudySession) {
        id = session.id; startedAt = session.startedAt; scope = session.scope; keys = session.keys; page = session.originPage
    }
    init(_ session: QuranRecitationRecord) {
        id = session.id; startedAt = session.startedAt; scope = .range; keys = session.keys; page = session.originPage
    }
    func valid() -> Bool {
        guard let corpus = QuranResources.corpus else { return false }
        return MushafStudySession(keys: keys, scope: scope, page: page, date: startedAt).valid(corpus: corpus)
    }
    var title: String {
        guard let first = keys.first, let last = keys.last, let corpus = QuranResources.corpus else { return "تسجيل تسميع" }
        func reference(_ key: String) -> (Int, Int)? {
            let parts = key.split(separator: ":").compactMap { Int($0) }
            guard parts.count == 2, corpus.indices.contains(parts[0] - 1),
                (1...corpus[parts[0] - 1].ayahs.count).contains(parts[1]) else { return nil }
            return (parts[0], parts[1])
        }
        guard let start = reference(first), let end = reference(last) else { return "تسجيل تسميع" }
        let name = corpus[start.0 - 1].name
        if start == end { return "\(name) · الآية \(start.1)" }
        if start.0 == end.0 { return "\(name) · الآيات \(start.1)–\(end.1)" }
        return "\(name) \(start.1) — \(corpus[end.0 - 1].name) \(end.1)"
    }
}

/// Own session files only. Existing NoorRecitation/latest-recitation.m4a is untouched.
enum MushafRecordingArchive {
    static func root() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true).appendingPathComponent("NoorMushafRecordings", isDirectory: true)
    }
    static func directory(session: UUID, base: URL? = nil) throws -> URL {
        let root = try base ?? self.root()
        let folder = root.appendingPathComponent(session.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUnlessOpen])
        var rootURL = root; var attributes = URLResourceValues(); attributes.isExcludedFromBackup = true
        try rootURL.setResourceValues(attributes)
        return folder
    }
    static func takes(session: UUID, base: URL? = nil) throws -> [MushafRecordingTake] {
        try audioFiles(session: session, deleted: false, base: base)
    }
    static func deletedTakes(session: UUID, base: URL? = nil) throws -> [MushafRecordingTake] {
        try audioFiles(session: session, deleted: true, base: base)
    }
    private static func audioFiles(session: UUID, deleted: Bool, base: URL?) throws -> [MushafRecordingTake] {
        let root = try base ?? self.root()
        let container = deleted ? root.appendingPathComponent("DeletedAudio", isDirectory: true) : root
        let directory = container.appendingPathComponent(session.uuidString, isDirectory: true)
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        let files = try FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: [.creationDateKey, .isRegularFileKey, .isSymbolicLinkKey])
        let decoded: [MushafRecordingTake] = try files.compactMap { file -> MushafRecordingTake? in
            guard ["m4a", "caf"].contains(file.pathExtension), let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent) else { return nil }
            let values = try file.resourceValues(forKeys: [.creationDateKey, .isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true,
                let player = try? AVAudioPlayer(contentsOf: file), player.duration.isFinite, player.duration > 0 else { return nil }
            return MushafRecordingTake(id: id, session: session, url: file,
                date: values.creationDate ?? .distantPast, duration: player.duration)
        }
        return decoded.sorted { $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date < $1.date }
    }
    /// Recoverable removal. Never edits the recognition journal or deletes audio
    /// bytes; the user can restore each take through the recording screen.
    static func moveAudio(_ take: MushafRecordingTake, toDeleted deleted: Bool, base: URL? = nil) throws {
        let root = try base ?? self.root()
        let live = root.appendingPathComponent(take.session.uuidString, isDirectory: true)
        let trash = root.appendingPathComponent("DeletedAudio", isDirectory: true)
            .appendingPathComponent(take.session.uuidString, isDirectory: true)
        let sourceFolder = deleted ? live : trash
        let destinationFolder = deleted ? trash : live
        guard ["caf", "m4a"].contains(take.url.pathExtension) else { throw CocoaError(.fileReadInvalidFileName) }
        let name = take.id.uuidString + "." + take.url.pathExtension
        let source = sourceFolder.appendingPathComponent(name)
        guard source.standardizedFileURL == take.url.standardizedFileURL else { throw CocoaError(.fileReadInvalidFileName) }
        let properties = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard properties.isRegularFile == true, properties.isSymbolicLink != true else { throw CocoaError(.fileReadInvalidFileName) }
        try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUnlessOpen])
        // moveItem refuses to overwrite an existing destination, including a
        // restored take created on another operation boundary.
        try FileManager.default.moveItem(at: source, to: destinationFolder.appendingPathComponent(name))
    }
    static func metadata(session: UUID, base: URL? = nil) throws -> MushafRecordingSessionMetadata? {
        let root = try base ?? self.root()
        let file = root.appendingPathComponent(session.uuidString).appendingPathComponent("session.json")
        guard FileManager.default.fileExists(atPath: file.path) else {
            let journal = QuranRecitationJournal(root: root)
            guard FileManager.default.fileExists(atPath: journal.folder(session).appendingPathComponent("recognized-session.json").path) else { return nil }
            let value = MushafRecordingSessionMetadata(try journal.load(session))
            guard value.valid() else { throw CocoaError(.fileReadCorruptFile) }
            return value
        }
        let value = try JSONDecoder().decode(MushafRecordingSessionMetadata.self, from: Data(contentsOf: file))
        guard value.id == session, value.valid() else { throw CocoaError(.fileReadCorruptFile) }
        return value
    }
    static func register(_ session: MushafStudySession, base: URL? = nil) throws -> URL {
        let value = MushafRecordingSessionMetadata(session)
        guard value.valid() else { throw CocoaError(.fileReadCorruptFile) }
        let folder = try directory(session: session.id, base: base)
        if let existing = try metadata(session: session.id, base: base) {
            guard existing == value else { throw CocoaError(.fileReadCorruptFile) }
        } else {
            try JSONEncoder().encode(value).write(to: folder.appendingPathComponent("session.json"),
                options: [.atomic, .completeFileProtectionUnlessOpen])
        }
        return folder
    }
    static func sessions(base: URL? = nil) throws -> [MushafRecordingSessionRow] {
        let root = try base ?? self.root()
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        let folders = try FileManager.default.contentsOfDirectory(at: root,
            includingPropertiesForKeys: [.creationDateKey, .isDirectoryKey, .isSymbolicLinkKey])
        var rows: [MushafRecordingSessionRow] = []
        for folder in folders {
            guard let id = UUID(uuidString: folder.lastPathComponent) else { continue }
            let values = try folder.resourceValues(forKeys: [.creationDateKey, .isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true, values.isSymbolicLink != true else { continue }
            let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey])
            let hasLiveAudio = files.contains(where: { ["m4a", "caf"].contains($0.pathExtension) && UUID(uuidString: $0.deletingPathExtension().lastPathComponent) != nil
                && ((try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) > 0 })
            if !hasLiveAudio, try deletedTakes(session: id, base: base).isEmpty { continue }
            let header = try? metadata(session: id, base: base)
            let available = try takes(session: id, base: base)
            let removed = try deletedTakes(session: id, base: base)
            rows.append(.init(id: id, date: header?.startedAt ?? values.creationDate ?? .distantPast,
                metadata: header, duration: available.reduce(0) { $0 + $1.duration }, takeCount: available.count,
                recoverableDeleted: !removed.isEmpty))
        }
        return rows.sorted { $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date > $1.date }
    }
    /// Export file names/sizes and scope, not a huge in-memory copy of all voice bytes.
    /// Individual audio files are saved through the real recording list's ShareLink.
    static func exportMetadata(base: URL? = nil) throws -> [MushafRecordingExport] {
        let root = try base ?? self.root()
        return try sessions(base: base).map { row in
            let folder = root.appendingPathComponent(row.id.uuidString)
            let paths = try FileManager.default.contentsOfDirectory(at: folder,
                includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
            var files: [MushafRecordingFileMetadata] = []
            for path in paths {
                guard ["m4a", "caf"].contains(path.pathExtension), let id = UUID(uuidString: path.deletingPathExtension().lastPathComponent) else { continue }
                let values = try path.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
                guard values.isRegularFile == true, values.isSymbolicLink != true else { continue }
                files.append(.init(id: id, bytes: values.fileSize ?? 0))
            }
            for take in try deletedTakes(session: row.id, base: base) {
                let size = try take.url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                files.append(.init(id: take.id, bytes: size, deleted: true))
            }
            let unreadable = row.metadata == nil ? (try? Data(contentsOf: folder.appendingPathComponent("session.json"))) : nil
            return MushafRecordingExport(session: row.id, metadata: row.metadata, unreadableMetadata: unreadable,
                files: files.sorted { $0.id.uuidString < $1.id.uuidString },
                recognizedSession: try? Data(contentsOf: folder.appendingPathComponent("recognized-session.json")))
        }
    }
    static func erase(base: URL? = nil) throws {
        let root = try base ?? self.root()
        // Root was created by this feature; no legacy recordings live here.
        if FileManager.default.fileExists(atPath: root.path) { try FileManager.default.removeItem(at: root) }
        if base == nil { UserDefaults.standard.removeObject(forKey: "noor.recitation.pending") }
    }
}

@MainActor final class MushafSessionRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate, AVAudioPlayerDelegate {
    @Published private(set) var recording = false
    @Published private(set) var requestingPermission = false
    @Published private(set) var permissionDenied = false
    @Published private(set) var playing: UUID?
    @Published private(set) var playbackPaused = false
    @Published private(set) var playbackPosition: TimeInterval = 0
    @Published private(set) var playbackDuration: TimeInterval = 0
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var level = 0.0
    @Published var message: String?
    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var revision = 0
    private var ownsAudioSession = false
    private let setSessionActive: (Bool) throws -> Void
    private let permission: () async -> Bool
    private let isActive: () -> Bool
    private let base: URL?
    init(base: URL? = nil, permission: @escaping () async -> Bool = {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
        }
    }, isActive: @escaping () -> Bool = { UIApplication.shared.applicationState == .active },
        setSessionActive: @escaping (Bool) throws -> Void = { active in
            try AVAudioSession.sharedInstance().setActive(active, options: active ? [] : .notifyOthersOnDeactivation)
        }) {
        self.base = base; self.permission = permission; self.isActive = isActive; self.setSessionActive = setSessionActive
        super.init()
    }
    func start(session: MushafStudySession) async {
        guard !recording, !requestingPermission else { return }
        stop(); let token = revision
        requestingPermission = true; permissionDenied = false
        defer { requestingPermission = false }
        let granted = await permission()
        guard token == revision else { return }
        guard granted else {
            permissionDenied = true
            message = "إذن الميكروفون غير متاح. يمكنك متابعة التسميع الذاتي دون تسجيل، أو السماح بالميكروفون من إعدادات iPhone."; return
        }
        guard isActive() else {
            message = "لم يبدأ التسجيل أثناء مغادرة التطبيق. عُد إلى الجلسة واضغط الميكروفون عندما تكون مستعدًا."; return
        }
        do {
            guard session.phase == .active, session.currentKey != nil else { return }
            let directory = try MushafRecordingArchive.register(session, base: base)
            let file = directory.appendingPathComponent(UUID().uuidString + ".m4a")
            let sound = AVAudioSession.sharedInstance()
            try MushafCaptureAudio.configure(sound)
            try activateSound()
            let capture = try AVAudioRecorder(url: file, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44100, AVNumberOfChannelsKey: 1, AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue])
            capture.delegate = self; capture.isMeteringEnabled = true; recorder = capture
            guard capture.prepareToRecord(), capture.record() else { throw CocoaError(.fileWriteUnknown) }
            // No time cap; pause/interruption creates another independent take.
            recording = true; elapsed = 0; level = 0; message = nil
        } catch {
            stop(); message = "تعذّر بدء التسجيل. تحقق من مساحة الجهاز والميكروفون. جلسة التسميع ونتائجها محفوظة بشكل مستقل عن الصوت."
        }
    }
    private func activateSound() throws {
        try setSessionActive(true)
        // Track activation before creating the encoder/player: their initializers
        // can throw while the app already owns an active system audio session.
        ownsAudioSession = true
    }
    func meters() {
        guard recording, let recorder else { return }
        recorder.updateMeters(); elapsed = recorder.currentTime.isFinite ? max(0, recorder.currentTime) : 0
        level = min(1, max(0, pow(10, Double(recorder.averagePower(forChannel: 0)) / 20)))
    }
    func stop() {
        revision += 1
        let ownsSound = ownsAudioSession
        recorder?.stop(); recorder = nil; player?.stop(); player = nil
        recording = false; playing = nil; level = 0
        playbackPaused = false; playbackPosition = 0; playbackDuration = 0
        if ownsSound {
            do { try setSessionActive(false); ownsAudioSession = false }
            catch { /* Retain ownership so the next explicit stop can retry. */ }
        }
        // Never replace/delete a take here. Interrupted bytes remain recoverable;
        // the list exposes only files AVFoundation can actually decode.
    }
    func play(_ take: MushafRecordingTake, at position: TimeInterval = 0) {
        stop()
        do {
            let sound = AVAudioSession.sharedInstance()
            try sound.setCategory(.playback); try activateSound()
            let playback = try AVAudioPlayer(contentsOf: take.url)
            playback.delegate = self; player = playback
            playback.currentTime = position.isFinite ? min(max(0, position), playback.duration) : 0
            guard playback.play() else { throw CocoaError(.fileReadCorruptFile) }
            playing = take.id; playbackDuration = playback.duration
            playbackPosition = playback.currentTime; playbackPaused = false; message = nil
        } catch { stop(); message = "تعذّر تشغيل هذا التسجيل. احتُفظ بالملف الأصلي دون استبدال." }
    }
    func refreshPlaybackPosition() {
        guard let player, playing != nil else { return }
        playbackPosition = min(playbackDuration, max(0, player.currentTime))
    }
    func pausePlayback() {
        guard let player, playing != nil, !playbackPaused else { return }
        player.pause(); refreshPlaybackPosition(); playbackPaused = true
        if ownsAudioSession {
            do { try setSessionActive(false); ownsAudioSession = false }
            catch { /* Retain ownership for the next explicit stop. */ }
        }
    }
    func resumePlayback() {
        guard let player, playing != nil, playbackPaused else { return }
        do {
            try activateSound()
            guard player.play() else { throw CocoaError(.fileReadUnknown) }
            playbackPaused = false; message = nil
        } catch {
            // Keep the paused player and its position for an explicit retry,
            // but do not retain system audio ownership after failed playback.
            if ownsAudioSession {
                do { try setSessionActive(false); ownsAudioSession = false }
                catch { /* A subsequent pause/stop can retry deactivation. */ }
            }
            message = "تعذّر استئناف الصوت. بقي التسجيل محفوظًا؛ أعد المحاولة."
        }
    }
    func seekPlayback(to position: TimeInterval) {
        guard position.isFinite, let player, playing != nil else { return }
        player.currentTime = min(max(0, position), playbackDuration)
        refreshPlaybackPosition()
    }
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self, self.recorder === recorder else { return }
            self.stop()
            if !flag { self.message = "توقف التسجيل قبل اكتماله. احتُفظ بالملف المتاح، ولم تُسجّل مشكلة الصوت كخطأ في تلاوتك." }
        }
    }
    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor [weak self] in
            guard let self, self.recorder === recorder else { return }
            self.stop(); self.message = "تعذّر إكمال حفظ الصوت. احتُفظ بالملف المتاح وبنتائج التسميع؛ لم يُقيّم النطق أو التجويد."
        }
    }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self, self.player === player else { return }; self.stop()
            if !flag { self.message = "انقطع تشغيل التسجيل. يمكنك إعادة المحاولة." }
        }
    }
}

/// Apple's category/mode table allows measurement with recording; spokenAudio
/// belongs to playback. Configure before activation, without requesting input.
enum MushafCaptureAudio {
    static func configure(_ session: AVAudioSession) throws {
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker])
    }
}
