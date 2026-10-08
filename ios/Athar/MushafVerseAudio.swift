import AVFoundation
import Combine
import Foundation

/// Cursor stores a range once. Only a real item-end event starts the next
/// delay, and stop/replacement invalidates both that delay and stale callbacks.
@MainActor final class MushafVerseAudio: ObservableObject {
    @Published private(set) var playing: String?
    @Published var error: String?
    @Published private(set) var loadingKey: String?
    @Published private(set) var waitingKey: String?
    private var playbackObservation: NSKeyValueObservation?
    private var observation: NSKeyValueObservation?
    private var player: AVPlayer?
    private var end: NSObjectProtocol?
    private var failure: NSObjectProtocol?
    private var delay: Task<Void, Never>?
    private var loadDeadline: Task<Void, Never>?
    private let loadTimeout: UInt64
    private var revision = UUID()
    private var keys: [String] = []
    private var index = 0
    private var pass = 0
    private var count = 1
    private var gap = 0
    private var reportedStart = false
    private let source: (String) -> URL?
    var onVerse: ((String) -> Void)?
    init(source: ((String) -> URL?)? = nil, loadTimeoutSeconds: Double = 15) {
        self.source = source ?? Self.recitationURL
        loadTimeout = UInt64(max(0.05, min(60, loadTimeoutSeconds.isFinite ? loadTimeoutSeconds : 15)) * 1_000_000_000)
    }
    static func recitationURL(_ key: String) -> URL? {
        let parts = key.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2, let corpus = QuranResources.corpus,
              corpus.indices.contains(parts[0] - 1), corpus[parts[0] - 1].ayahs.indices.contains(parts[1] - 1),
              key == "\(parts[0]):\(parts[1])" else { return nil }
        return NoorAudioDownloads.shared.localURL(key) ?? URL(string: String(format:
            "https://everyayah.com/data/Abdul_Basit_Murattal_64kbps/%03d%03d.mp3", parts[0], parts[1]))
    }
    func play(_ keys: [String], repetitions: Int = 1, delaySeconds: Int = 0) {
        stop(); error = nil
        guard !keys.isEmpty, (1...20).contains(repetitions), (0...30).contains(delaySeconds),
              keys.allSatisfy({ source($0) != nil }) else {
            error = "تعذّر تشغيل نطاق التلاوة أو خيارات التكرار."; return
        }
        self.keys = keys; count = repetitions; gap = delaySeconds
        advance()
    }
    private func releasePlayer() {
        loadDeadline?.cancel(); loadDeadline = nil
        player?.pause(); player = nil; observation = nil; playbackObservation = nil
        if let end { NotificationCenter.default.removeObserver(end) }; end = nil
        if let failure { NotificationCenter.default.removeObserver(failure) }; failure = nil
        playing = nil; loadingKey = nil; reportedStart = false
    }
    private func completed(_ item: AVPlayerItem, revision token: UUID) {
        guard revision == token, player?.currentItem === item else { return }
        releasePlayer(); index += 1
        if index == keys.count { index = 0; pass += 1 }
        guard pass < count else { stop(); return }
        guard gap > 0 else { advance(); return }
        waitingKey = keys[index]
        let seconds = gap
        delay = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000) }
            catch { return }
            guard let self, !Task.isCancelled, self.revision == token else { return }
            self.waitingKey = nil; self.delay = nil; self.advance()
        }
    }
    private func advance() {
        guard index < keys.count, let url = source(keys[index]) else { stop(); return }
        releasePlayer()
        let key = keys[index]; let token = revision
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch { self.error = "تعذّر تشغيل الصوت على الجهاز."; stop(); return }
        let item = AVPlayerItem(url: url); let playback = AVPlayer(playerItem: item); player = playback
        loadingKey = key
        playbackObservation = playback.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            let started = player.timeControlStatus == .playing
            Task { @MainActor in
                guard let self, self.revision == token, self.player === player else { return }
                if started {
                    self.loadDeadline?.cancel(); self.loadDeadline = nil
                    self.playing = key; self.loadingKey = nil
                    if !self.reportedStart { self.reportedStart = true; self.onVerse?(key) }
                } else if player.timeControlStatus == .waitingToPlayAtSpecifiedRate {
                    self.playing = nil; self.loadingKey = key
                    self.startLoadDeadline(key: key, token: token)
                }
            }
        }
        observation = item.observe(\.status, options: [.new, .initial]) { [weak self] item, _ in
            let failed = item.status == .failed
            Task { @MainActor in
                guard failed, let self, self.revision == token, self.player?.currentItem === item else { return }
                self.error = "تعذّر تشغيل الآية. أعد تنزيلها أو تحقق من الاتصال."; self.stop()
            }
        }
        end = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.completed(item, revision: token) }
        }
        failure = NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.revision == token, self.player?.currentItem === item else { return }
                self.error = "انقطع تحميل التلاوة. تحقق من الاتصال وأعد المحاولة."; self.stop()
            }
        }
        startLoadDeadline(key: key, token: token)
        playback.play()
    }
    private func startLoadDeadline(key: String, token: UUID) {
        guard loadDeadline == nil else { return }
        let timeout = loadTimeout
        loadDeadline = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: timeout) } catch { return }
            guard let self, !Task.isCancelled, self.revision == token,
                  self.loadingKey == key else { return }
            self.error = "استغرق تحميل التلاوة وقتًا طويلًا. تحقق من الاتصال وأعد المحاولة، أو نزّل السورة للاستماع دون اتصال."
            self.stop()
        }
    }
    func stop() {
        revision = UUID(); delay?.cancel(); delay = nil; waitingKey = nil
        releasePlayer(); keys = []; index = 0; pass = 0
    }
    deinit {
        delay?.cancel()
        loadDeadline?.cancel()
        if let end { NotificationCenter.default.removeObserver(end) }
        if let failure { NotificationCenter.default.removeObserver(failure) }
    }
}
