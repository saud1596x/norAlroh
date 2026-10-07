import Foundation
import AVFoundation
import CryptoKit
import SwiftUI

struct NoorAudioFile: Codable, Identifiable {
    let key: String
    let bytes: Int
    let sha256: String
    var id: String { key }
}
/// The digest detects changes to an installed file. It is not a publisher
/// signature or an independent certification of the recitation's contents.
enum NoorAudioIntegrity {
    static let maximumBytes = 20_000_000
    static func availableCapacity(at directory: URL) throws -> Int64 {
        let values = try directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
        return values.volumeAvailableCapacityForImportantUsage ?? Int64(values.volumeAvailableCapacity ?? 0)
    }
    static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    static func valid(_ data: Data, metadata: NoorAudioFile) -> Bool {
        data.count > 0 && data.count <= maximumBytes && data.count == metadata.bytes && digest(data) == metadata.sha256
    }
    static func url(_ key: String) -> URL? {
        let parts = key.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2, let corpus = QuranResources.corpus,
              corpus.indices.contains(parts[0] - 1), (1...corpus[parts[0] - 1].ayahs.count).contains(parts[1]),
              key == "\(parts[0]):\(parts[1])" else { return nil }
        return URL(string: String(format: "https://everyayah.com/data/Abdul_Basit_Murattal_64kbps/%03d%03d.mp3", parts[0], parts[1]))
    }
}

private final class NoorAudioTransfer: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let progress: @Sendable (Int64, Int64) -> Void
    let finish: @Sendable (URL?, HTTPURLResponse?) -> Void
    let failure: @Sendable (NSError) -> Void
    init(progress: @escaping @Sendable (Int64, Int64) -> Void,
         finish: @escaping @Sendable (URL?, HTTPURLResponse?) -> Void,
         failure: @escaping @Sendable (NSError) -> Void) {
        self.progress = progress; self.finish = finish; self.failure = failure
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesWritten > Int64(NoorAudioIntegrity.maximumBytes) || totalBytesExpectedToWrite > Int64(NoorAudioIntegrity.maximumBytes) {
            downloadTask.cancel(); failure(NSError(domain: NSCocoaErrorDomain, code: CocoaError.fileReadTooLarge.rawValue)); return
        }
        progress(totalBytesWritten, totalBytesExpectedToWrite)
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // URLSession removes its temporary file when this delegate returns.
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent("noor-audio-" + UUID().uuidString + ".mp3")
        do { try FileManager.default.moveItem(at: location, to: copy); finish(copy, downloadTask.response as? HTTPURLResponse) }
        catch { failure(error as NSError) }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { failure(error as NSError) }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url?.scheme == "https" && request.url?.host == "everyayah.com" ? request : nil)
    }
}

@MainActor final class NoorAudioDownloads: ObservableObject {
    static let shared = NoorAudioDownloads()
    @Published private(set) var files: [NoorAudioFile] = []
    @Published private(set) var active: String?
    @Published private(set) var received: Int64 = 0
    @Published private(set) var expected: Int64 = 0
    @Published private(set) var remaining = 0
    @Published private(set) var checking = false
    @Published private(set) var cancelling = false
    @Published var message: String?
    private var task: URLSessionDownloadTask?
    private var session: URLSession?
    private var generation = UUID()
    private var queue: [String] = []
    private var paused = false
    private let directory: URL
    private let defaults: UserDefaults
    private let pendingKey = "noor.audioDownloads.pending.v1"
    init(directory: URL? = nil, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("NoorRecitations", isDirectory: true)
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
        var folder = self.directory; var value = URLResourceValues(); value.isExcludedFromBackup = true; try? folder.setResourceValues(value)
        var seen = Set<String>()
        files = ((try? Data(contentsOf: self.directory.appendingPathComponent("index.json"))).flatMap { try? JSONDecoder().decode([NoorAudioFile].self, from: $0) } ?? [])
            .filter { NoorAudioIntegrity.url($0.key) != nil && $0.bytes > 0 && $0.bytes <= NoorAudioIntegrity.maximumBytes && seen.insert($0.key).inserted }
        remaining = pending.count
    }
    var pending: [String] { (defaults.stringArray(forKey: pendingKey) ?? []).filter { NoorAudioIntegrity.url($0) != nil } }
    var totalBytes: Int { files.reduce(0) { $0 + $1.bytes } }
    private func file(_ key: String) -> URL { directory.appendingPathComponent(key.replacingOccurrences(of: ":", with: "-") + ".mp3") }
    private func resumeFile(_ key: String) -> URL { directory.appendingPathComponent(key.replacingOccurrences(of: ":", with: "-") + ".resume") }
    func localURL(_ key: String) -> URL? {
        guard let metadata = files.first(where: { $0.key == key }),
              let size = try? file(key).resourceValues(forKeys: [.fileSizeKey]).fileSize, size == metadata.bytes,
              let data = try? Data(contentsOf: file(key), options: .mappedIfSafe),
              NoorAudioIntegrity.valid(data, metadata: metadata) else { return nil }
        return file(key)
    }
    func download(_ keys: [String]) {
        guard active == nil, !cancelling else { return }
        let valid = keys.filter { NoorAudioIntegrity.url($0) != nil }
        guard !valid.isEmpty, valid.count <= 300 else { message = "اختر نطاقًا لا يزيد على ٣٠٠ آية للتنزيل."; return }
        var seen = Set<String>()
        let combined = (pending + valid).filter { seen.insert($0).inserted && localURL($0) == nil }
        guard combined.count <= 300 else { message = "استكمل التنزيلات المعلّقة قبل إضافة هذا النطاق."; return }
        queue = combined
        paused = false; persistPending(); next()
    }
    func retry() { download(pending) }
    private func persistPending() {
        defaults.set((active.map { [$0] } ?? []) + queue, forKey: pendingKey)
        remaining = queue.count + (active == nil ? 0 : 1)
    }
    private func next() {
        guard !paused, active == nil, !queue.isEmpty else {
            if !paused && active == nil && queue.isEmpty { persistPending(); message = "التلاوات المحفوظة جاهزة دون اتصال." }
            return
        }
        let key = queue.removeFirst()
        guard let url = NoorAudioIntegrity.url(key) else { next(); return }
        do {
            let free = try NoorAudioIntegrity.availableCapacity(at: directory)
            guard free >= 50_000_000 else { throw CocoaError(.fileWriteOutOfSpace) }
            active = key; received = 0; expected = 0; checking = false; message = nil; generation = UUID(); let token = generation
            persistPending()
            let delegate = NoorAudioTransfer(progress: { [weak self] bytes, total in Task { @MainActor in
                guard let self, token == self.generation else { return }; self.received = bytes; self.expected = total
            } }, finish: { [weak self] temporary, response in Task { @MainActor in
                guard let self else { if let temporary { try? FileManager.default.removeItem(at: temporary) }; return }
                await self.install(temporary, response: response, key: key, token: token)
            } }, failure: { [weak self] error in Task { @MainActor in
                guard let self, token == self.generation else { return }
                if let bytes = error.userInfo[NSURLSessionDownloadTaskResumeData] as? Data { try? bytes.write(to: self.resumeFile(key), options: .atomic) }
                else { try? FileManager.default.removeItem(at: self.resumeFile(key)) }
                self.fail("توقف التنزيل. تحقق من الاتصال والمساحة، ثم اختر إعادة المحاولة.")
            } })
            let config = URLSessionConfiguration.ephemeral; config.timeoutIntervalForRequest = 45; config.timeoutIntervalForResource = 600
            let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil); self.session = session
            if let resume = try? Data(contentsOf: resumeFile(key)) { task = session.downloadTask(withResumeData: resume) }
            else { task = session.downloadTask(with: url) }
            task?.resume()
        } catch { queue.insert(key, at: 0); paused = true; persistPending(); message = "المساحة غير كافية. احذف تلاوات محفوظة أو حرّر مساحة ثم أعد المحاولة." }
    }
    private func install(_ temporary: URL?, response: HTTPURLResponse?, key: String, token: UUID) async {
        guard let temporary else { return }; defer { try? FileManager.default.removeItem(at: temporary) }
        guard token == generation else { return }
        checking = true
        do {
            guard response?.statusCode == 200 || response?.statusCode == 206,
                  response?.url?.host == "everyayah.com", response?.url?.scheme == "https" else { throw CocoaError(.fileReadCorruptFile) }
            let size = try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size > 0, size <= NoorAudioIntegrity.maximumBytes else { throw CocoaError(.fileReadCorruptFile) }
            let data = try Data(contentsOf: temporary, options: .mappedIfSafe)
            guard !data.isEmpty, data.count <= NoorAudioIntegrity.maximumBytes else { throw CocoaError(.fileReadCorruptFile) }
            let asset = AVURLAsset(url: temporary)
            let duration = try await asset.load(.duration)
            let tracks = try await asset.loadTracks(withMediaType: .audio)
            guard token == generation else { return }
            guard duration.seconds.isFinite, duration.seconds > 0, !tracks.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
            let metadata = NoorAudioFile(key: key, bytes: data.count, sha256: NoorAudioIntegrity.digest(data))
            let updated = files.filter { $0.key != key } + [metadata]
            let index = try JSONEncoder().encode(updated)
            try data.write(to: file(key), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            try index.write(to: directory.appendingPathComponent("index.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            files = updated; try? FileManager.default.removeItem(at: resumeFile(key))
            session?.finishTasksAndInvalidate(); session = nil; task = nil; active = nil; checking = false
            persistPending(); next()
        } catch { guard token == generation else { return }; try? FileManager.default.removeItem(at: resumeFile(key)); fail("لم ينجح التحقق من ملف التلاوة. أعد تنزيله؛ لا يستخدم التطبيق الملف الناقص.") }
    }
    private func fail(_ text: String) {
        if let key = active { queue.insert(key, at: 0) }
        generation = UUID(); active = nil; checking = false; task = nil; session?.invalidateAndCancel(); session = nil
        paused = true; persistPending(); message = text
    }
    func cancel() {
        guard let key = active, !cancelling, let stopped = task else { return }
        generation = UUID(); let token = generation; cancelling = true
        stopped.cancel(byProducingResumeData: { [weak self] bytes in Task { @MainActor in
            guard let self, self.generation == token else { return }
            if let bytes { try? bytes.write(to: self.resumeFile(key), options: .atomic) }
            self.cancelling = false
            self.fail("أُوقف التنزيل. يمكنك استئنافه؛ يبدأ من جديد إذا لم يدعم الخادم الاستئناف.")
        } })
    }
    @discardableResult func erase() -> Bool {
        generation = UUID(); session?.invalidateAndCancel(); session = nil; task = nil
        active = nil; queue = []; paused = true; cancelling = false; checking = false
        defaults.removeObject(forKey: pendingKey); remaining = 0
        do { try FileManager.default.removeItem(at: directory); try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true); files = []; return true }
        catch { message = "تعذّر حذف بعض ملفات التلاوة. أعد المحاولة."; return false }
    }
    func remove(_ key: String) {
        guard active != key else { message = "أوقف تنزيل الآية أولًا."; return }
        do {
            let updated = files.filter { $0.key != key }; let index = try JSONEncoder().encode(updated)
            // Delete the bytes first: a failed deletion stays visible and retryable.
            // A crash before the index update is safe: localURL rejects missing files.
            if FileManager.default.fileExists(atPath: file(key).path) { try FileManager.default.removeItem(at: file(key)) }
            try index.write(to: directory.appendingPathComponent("index.json"), options: .atomic)
            files = updated
            if active == nil { queue = pending }
            queue.removeAll { $0 == key }; persistPending()
            try? FileManager.default.removeItem(at: resumeFile(key))
        } catch { message = "تعذّر حذف ملف التلاوة. أعد المحاولة." }
    }
}

struct NoorAudioDownloadsView: View {
    @ObservedObject private var downloads = NoorAudioDownloads.shared
    @State private var chapter = 1
    @State private var from = 1
    @State private var to = 7
    @State private var confirm = false
    private var count: Int { QuranResources.corpus?[chapter - 1].ayahs.count ?? 1 }
    var body: some View {
        List {
            Section("تنزيل التلاوات") {
                Text("عبد الباسط عبد الصمد — مرتّل").font(.headline)
                Picker("السورة", selection: $chapter) {
                    ForEach(QuranResources.corpus ?? [], id: \.number) { Text($0.name).tag($0.number) }
                }.disabled(downloads.active != nil)
                Stepper("من الآية \(from)", value: $from, in: 1...count).disabled(downloads.active != nil)
                Stepper("إلى الآية \(to)", value: $to, in: from...max(from, count)).disabled(downloads.active != nil)
                Button("تنزيل النطاق") { confirm = true }.disabled(downloads.active != nil).accessibilityIdentifier("downloads.range")
                Text("يعمل التنزيل أثناء فتح التطبيق. تُحفظ الملفات المكتملة؛ الاستئناف يعتمد على دعم الخادم. لا تتغير بيانات الحفظ عند حذف التلاوات.").font(.caption)
            }
            if let key = downloads.active {
                Section("جاري تنزيل الآية \(key)") {
                    if downloads.expected > 0 { ProgressView(value: Double(downloads.received), total: Double(max(downloads.received, downloads.expected))) }
                    else { ProgressView() }
                    Text(ByteCountFormatter.string(fromByteCount: downloads.received, countStyle: .file))
                    Text(downloads.checking ? "التحقق من ملف الصوت…" : "متبقي \(downloads.remaining) آية")
                    Button("إيقاف التنزيل") { downloads.cancel() }.disabled(downloads.cancelling).accessibilityIdentifier("downloads.cancel")
                }
            } else if !downloads.pending.isEmpty {
                Section { Button("إعادة المحاولة والاستئناف") { downloads.retry() }.accessibilityIdentifier("downloads.retry") }
            }
            if let message = downloads.message { Section { Text(message) } }
            Section("المحفوظ على الجهاز · " + ByteCountFormatter.string(fromByteCount: Int64(downloads.totalBytes), countStyle: .file)) {
                if downloads.files.isEmpty { Text("لا توجد تلاوات منزّلة بعد.").foregroundStyle(.secondary) }
                ForEach(downloads.files) { recording in
                    HStack { Text("الآية \(recording.key)"); Spacer(); Text(ByteCountFormatter.string(fromByteCount: Int64(recording.bytes), countStyle: .file)).font(.caption) }
                    .swipeActions { Button("حذف", role: .destructive) { downloads.remove(recording.key) } }
                }
            }
        }.navigationTitle("التنزيلات")
        .onChange(of: chapter) { _, _ in from = 1; to = min(7, count) }
        .onChange(of: from) { _, value in to = max(to, value) }
        .confirmationDialog("تنزيل النطاق من الإنترنت؟ قد يستخدم بيانات الجوال.", isPresented: $confirm, titleVisibility: .visible) {
            Button("تنزيل") { downloads.download((from...to).map { "\(chapter):\($0)" }) }
        }
    }
}
