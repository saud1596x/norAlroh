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
}

struct MushafRecordingFileMetadata: Codable {
    let id: UUID
    let bytes: Int
}
struct MushafRecordingExport: Codable {
    let session: UUID
    let metadata: MushafRecordingSessionMetadata?
    let unreadableMetadata: Data?
    let files: [MushafRecordingFileMetadata]
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
    func valid() -> Bool {
        guard let corpus = QuranResources.corpus else { return false }
        return MushafStudySession(keys: keys, scope: scope, page: page, date: startedAt).valid(corpus: corpus)
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
        let root = try base ?? self.root()
        let directory = root.appendingPathComponent(session.uuidString, isDirectory: true)
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        let files = try FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: [.creationDateKey, .isRegularFileKey, .isSymbolicLinkKey])
        let decoded: [MushafRecordingTake] = try files.compactMap { file -> MushafRecordingTake? in
            guard file.pathExtension == "m4a", let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent) else { return nil }
            let values = try file.resourceValues(forKeys: [.creationDateKey, .isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true,
                let player = try? AVAudioPlayer(contentsOf: file), player.duration.isFinite, player.duration > 0 else { return nil }
            return MushafRecordingTake(id: id, session: session, url: file,
                date: values.creationDate ?? .distantPast, duration: player.duration)
        }
        return decoded.sorted { $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date < $1.date }
    }
    static func metadata(session: UUID, base: URL? = nil) throws -> MushafRecordingSessionMetadata? {
        let root = try base ?? self.root()
        let file = root.appendingPathComponent(session.uuidString).appendingPathComponent("session.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
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
            guard files.contains(where: { $0.pathExtension == "m4a" && UUID(uuidString: $0.deletingPathExtension().lastPathComponent) != nil
                && ((try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) > 0 }) else { continue }
            let header = try? metadata(session: id, base: base)
            rows.append(.init(id: id, date: header?.startedAt ?? values.creationDate ?? .distantPast, metadata: header))
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
                guard path.pathExtension == "m4a", let id = UUID(uuidString: path.deletingPathExtension().lastPathComponent) else { continue }
                let values = try path.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
                guard values.isRegularFile == true, values.isSymbolicLink != true else { continue }
                files.append(.init(id: id, bytes: values.fileSize ?? 0))
            }
            let unreadable = row.metadata == nil ? (try? Data(contentsOf: folder.appendingPathComponent("session.json"))) : nil
            return MushafRecordingExport(session: row.id, metadata: row.metadata, unreadableMetadata: unreadable,
                files: files.sorted { $0.id.uuidString < $1.id.uuidString })
        }
    }
    static func erase(base: URL? = nil) throws {
        let root = try base ?? self.root()
        guard FileManager.default.fileExists(atPath: root.path) else { return }
        // Root was created by this feature; no legacy recordings live here.
        try FileManager.default.removeItem(at: root)
    }
}

@MainActor final class MushafSessionRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate, AVAudioPlayerDelegate {
    @Published private(set) var recording = false
    @Published private(set) var requestingPermission = false
    @Published private(set) var permissionDenied = false
    @Published private(set) var playing: UUID?
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var level = 0.0
    @Published var message: String?
    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var revision = 0
    private let permission: () async -> Bool
    private let isActive: () -> Bool
    private let base: URL?
    init(base: URL? = nil, permission: @escaping () async -> Bool = {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
        }
    }, isActive: @escaping () -> Bool = { UIApplication.shared.applicationState == .active }) {
        self.base = base; self.permission = permission; self.isActive = isActive
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
            try sound.setActive(true)
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
    func meters() {
        guard recording, let recorder else { return }
        recorder.updateMeters(); elapsed = recorder.currentTime.isFinite ? max(0, recorder.currentTime) : 0
        level = min(1, max(0, pow(10, Double(recorder.averagePower(forChannel: 0)) / 20)))
    }
    func stop() {
        revision += 1
        let ownsSound = recorder != nil || player != nil
        recorder?.stop(); recorder = nil; player?.stop(); player = nil
        recording = false; playing = nil; level = 0
        if ownsSound { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
        // Never replace/delete a take here. Interrupted bytes remain recoverable;
        // the list exposes only files AVFoundation can actually decode.
    }
    func play(_ take: MushafRecordingTake) {
        stop()
        do {
            let sound = AVAudioSession.sharedInstance()
            try sound.setCategory(.playback); try sound.setActive(true)
            let playback = try AVAudioPlayer(contentsOf: take.url)
            playback.delegate = self; player = playback
            guard playback.play() else { throw CocoaError(.fileReadCorruptFile) }
            playing = take.id; message = nil
        } catch { stop(); message = "تعذّر تشغيل هذا التسجيل. احتُفظ بالملف الأصلي دون استبدال." }
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
