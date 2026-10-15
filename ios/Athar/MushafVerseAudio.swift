import AVFoundation
import Combine
import Foundation
import MediaPlayer

/// Cursor stores a range once. Only a real item-end event starts the next
/// delay, and stop/replacement invalidates both that delay and stale callbacks.
@MainActor final class MushafVerseAudio: ObservableObject {
    // Native CI can distinguish an OS audio RPC stall from sequence logic.
    // Phase markers contain no media URL, Quran text or user recording data.
    private func traceAudio(_ phase: String) {
        #if DEBUG || NOOR_ACCEPTANCE_TESTING
        NSLog("NOOR_AUDIO_STAGE %@", phase)
        #endif
    }
    @Published private(set) var playing: String?
    @Published var error: String?
    @Published private(set) var loadingKey: String?
    @Published private(set) var waitingKey: String?
    @Published private(set) var isPaused = false
    @Published private(set) var completedRepetitions = 0
    @Published private(set) var playbackRate: Float = 1
    @Published private(set) var sleepStatus: String?
    private var sleepTask: Task<Void, Never>?
    private var stopAtBoundary = false
    private var bookmarkSeconds: Double?
    private let recordingIdentity: String?
    let displayName: String
    private let keepAlive: Bool
    private var remoteTargets: [(MPRemoteCommand, Any)] = []
    var currentSeconds: Double {
        let value = player?.currentTime().seconds ?? 0
        return value.isFinite ? max(0, value) : 0
    }
    var durationSeconds: Double {
        // AVPlayer can report a playing time-control state before its item is
        // ready. Do not synchronously request unloaded media timing from UI.
        guard let item = player?.currentItem, item.status == .readyToPlay else { return 0 }
        let value = item.duration.seconds
        return value.isFinite ? max(0, value) : 0
    }
    var repetitionCount: Int { count }
    var currentCanonicalKey: String? { index < keys.count ? keys[index] : nil }
    private var bookmarkKey: String { "noor.audio.bookmark." + (recordingIdentity ?? "everyayah:" + reciterDirectory) }
    private var playbackObservation: NSKeyValueObservation?
    private var observation: NSKeyValueObservation?
    private var player: AVPlayer?
    private var end: NSObjectProtocol?
    private var failure: NSObjectProtocol?
    private var delay: Task<Void, Never>?
    private var loadDeadline: Task<Void, Never>?
    private let loadTimeout: UInt64
    private var revision = UUID()
    private let focusID = UUID()
    private var keys: [String] = []
    private var index = 0
    private var pass = 0
    private var count = 1
    private var gap = 0
    private var reportedStart = false
    // Native CI needs to distinguish corrupt media, buffering and simulator
    // audio-route failure without exposing URLs or a user's recording content.
    private(set) var lastPlaybackDiagnostic = ""
    var playbackDiagnostic: String {
        guard let player else { return lastPlaybackDiagnostic }
        let item = player.currentItem
        return "player=\(player.status.rawValue), item=\(item?.status.rawValue ?? -1), timeControl=\(player.timeControlStatus.rawValue), waiting=\(player.reasonForWaitingToPlay?.rawValue ?? "none"), seconds=\(player.currentTime().seconds), duration=\(item?.duration.seconds ?? .nan), itemError=\((item?.error as NSError?)?.code ?? 0), outputs=\(AVAudioSession.sharedInstance().currentRoute.outputs.map { $0.portType.rawValue }.joined(separator: ","))"
    }
    private let cacheKey: ((String) -> String?)?
    private let cachedSource: (String) async -> URL?
    private let source: ((String) -> URL?)?
    private let resolveSource: (String) async -> URL?
    private var resolvingSource: Task<Void, Never>?
    var onVerse: ((String) -> Void)?
    private var onSequenceFinished: (() -> Void)?
    private var onSequenceInterrupted: (() -> Void)?
    var reciterDirectory = "Abdul_Basit_Murattal_64kbps" {
        willSet { if newValue != reciterDirectory { stop() } }
    }
    init(source: ((String) -> URL?)? = nil, cacheKey: ((String) -> String?)? = nil,
         cachedSource: ((String) async -> URL?)? = nil, loadTimeoutSeconds: Double = 15,
         resolveSource: ((String) async -> URL?)? = nil, recordingIdentity: String? = nil,
         displayName: String = "تلاوة القرآن", keepAlive: Bool = false) {
        self.source = source; self.cacheKey = cacheKey
        self.cachedSource = cachedSource ?? { await NoorAudioDownloads.shared.localURL($0) }
        self.recordingIdentity = recordingIdentity
        self.displayName = displayName; self.keepAlive = keepAlive
        self.resolveSource = resolveSource ?? Self.recitationURL
        loadTimeout = UInt64(max(0.05, min(60, loadTimeoutSeconds.isFinite ? loadTimeoutSeconds : 15)) * 1_000_000_000)
        let storedRate = UserDefaults.standard.float(forKey: bookmarkKey + ".rate")
        if storedRate.isFinite, (0.75...1.25).contains(storedRate) { playbackRate = storedRate }
        NoorAudioFocus.shared.register(focusID) { [weak self] in self?.stop() }
    }
    static func recitationURL(_ key: String) async -> URL? {
        let parts = key.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2, let corpus = QuranResources.corpus,
              corpus.indices.contains(parts[0] - 1), corpus[parts[0] - 1].ayahs.indices.contains(parts[1] - 1),
              key == "\(parts[0]):\(parts[1])" else { return nil }
        return await NoorAudioDownloads.shared.localURL(key) ?? URL(string: String(format:
            "https://everyayah.com/data/Abdul_Basit_Murattal_64kbps/%03d%03d.mp3", parts[0], parts[1]))
    }
    func play(_ keys: [String], repetitions: Int = 1, delaySeconds: Int = 0,
              startingAt: Int = 0, seconds: Double = 0, completedPass: Int = 0,
              onFinished: (() -> Void)? = nil, onInterrupted: (() -> Void)? = nil) {
        stop(); error = nil; lastPlaybackDiagnostic = ""
        guard NoorAudioFocus.shared.preparePlayback(focusID) else {
            error = "أوقف التسميع أولًا للاستماع إلى التلاوة."; return
        }
        guard !keys.isEmpty, (1...20).contains(repetitions), (0...30).contains(delaySeconds),
              keys.indices.contains(startingAt), (0..<repetitions).contains(completedPass), seconds.isFinite, seconds >= 0,
              keys.allSatisfy({ key in source.map { $0(key) != nil } ?? (NoorAudioIntegrity.url(key) != nil) }) else {
            error = "تعذّر تشغيل نطاق التلاوة أو خيارات التكرار."; return
        }
        self.keys = keys; count = repetitions; gap = delaySeconds
        onSequenceFinished = onFinished; onSequenceInterrupted = onInterrupted
        index = startingAt; pass = completedPass; completedRepetitions = completedPass
        bookmarkSeconds = seconds > 0 ? seconds : nil
        if keepAlive { NoorAudioFocus.shared.holdPlayback(self, id: focusID) }
        traceAudio("remote-controls.begin")
        installRemoteControls()
        traceAudio("remote-controls.end")
        advance()
    }
    func pausePlayback() {
        if waitingKey != nil { delay?.cancel(); delay = nil; isPaused = true; updateNowPlaying(); return }
        guard player != nil, playing != nil else { return }
        saveBookmark(); isPaused = true; player?.pause(); updateNowPlaying()
    }
    func resumePlayback() {
        if isPaused, waitingKey != nil, NoorAudioFocus.shared.preparePlayback(focusID) {
            waitingKey = nil; isPaused = false; advance(); return
        }
        guard isPaused, let player, NoorAudioFocus.shared.preparePlayback(focusID) else { return }
        isPaused = false; player.playImmediately(atRate: playbackRate); updateNowPlaying()
    }
    func seek(to seconds: Double) {
        guard seconds.isFinite, let player, durationSeconds > 0, seconds >= 0, seconds <= durationSeconds else { return }
        let token = revision
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in guard let self, self.revision == token else { return }; self.updateNowPlaying() }
        }
    }
    @discardableResult func setPlaybackRate(_ rate: Float) -> Bool {
        guard rate.isFinite, (0.75...1.25).contains(rate) else { return false }
        playbackRate = rate
        UserDefaults.standard.set(rate, forKey: bookmarkKey + ".rate")
        if !isPaused, playing != nil { player?.rate = rate }
        updateNowPlaying()
        return true
    }
    @discardableResult func switchReciter(to directory: String) -> Bool {
        let permitted = ["Abdul_Basit_Murattal_64kbps", "Abdurrahmaan_As-Sudais_64kbps", "Hudhaify_64kbps", "Maher_AlMuaiqly_64kbps", "Saood_ash-Shuraym_64kbps"]
        guard source == nil, permitted.contains(directory), index < keys.count else { return false }
        let range = keys, position = index, repetitions = count, completed = pass, pause = gap
        reciterDirectory = directory
        // No recording-specific word timing is available here. Start the same
        // canonical ayah from its own beginning, never copy elapsed seconds.
        play(range, repetitions: repetitions, delaySeconds: pause, startingAt: position, completedPass: completed)
        return error == nil
    }
    @discardableResult func setSleepTimer(minutes: Int, atBoundary: Bool = true) -> Bool {
        guard (1...120).contains(minutes) else { return false }
        sleepTask?.cancel(); stopAtBoundary = false
        sleepStatus = "إيقاف بعد \(minutes) دقيقة"
        sleepTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: UInt64(minutes) * 60 * 1_000_000_000) } catch { return }
            guard let self, !Task.isCancelled else { return }
            if atBoundary, self.playing != nil { self.stopAtBoundary = true; self.sleepStatus = "سينتهي الاستماع عند نهاية المقطع" }
            else { self.stop() }
        }
        return true
    }
    func saveBookmark() {
        guard index < keys.count, player != nil, currentSeconds >= 0 else { return }
        UserDefaults.standard.set(["key": keys[index], "keys": keys, "index": index, "seconds": currentSeconds,
                                   "repetitions": count, "completedPass": pass, "gap": gap], forKey: bookmarkKey)
    }
    @discardableResult func restoreBookmark() -> Bool {
        guard let value = UserDefaults.standard.dictionary(forKey: bookmarkKey),
              let key = value["key"] as? String, let seconds = value["seconds"] as? Double,
              seconds.isFinite, seconds >= 0 else { return false }
        let range = value["keys"] as? [String] ?? [key]
        let position = value["index"] as? Int ?? 0
        guard range.indices.contains(position), range[position] == key else { return false }
        play(range, repetitions: value["repetitions"] as? Int ?? 1, delaySeconds: value["gap"] as? Int ?? 0,
             startingAt: position, seconds: seconds, completedPass: value["completedPass"] as? Int ?? 0)
        return error == nil && (loadingKey != nil || playing != nil)
    }
    private func releasePlayer() {
        traceAudio("player.release.begin")
        resolvingSource?.cancel(); resolvingSource = nil
        loadDeadline?.cancel(); loadDeadline = nil
        if player != nil { lastPlaybackDiagnostic = playbackDiagnostic }
        player?.pause(); player = nil; observation = nil; playbackObservation = nil
        if let end { NotificationCenter.default.removeObserver(end) }; end = nil
        if let failure { NotificationCenter.default.removeObserver(failure) }; failure = nil
        playing = nil; loadingKey = nil; reportedStart = false
        isPaused = false
        traceAudio("player.release.end")
    }
    private func completed(_ item: AVPlayerItem, revision token: UUID) {
        guard revision == token, player?.currentItem === item else { return }
        traceAudio("item.actual-end")
        saveBookmark()
        if stopAtBoundary { stop(); return }
        releasePlayer(); index += 1
        if index == keys.count { index = 0; pass += 1 }
        completedRepetitions = pass
        guard pass < count else {
            let completed = onSequenceFinished
            // A natural end is distinct from replacement, route loss, failure
            // or an explicit stop. Callbacks belong to this one sequence only.
            onSequenceFinished = nil; onSequenceInterrupted = nil
            stop(); completed?(); return
        }
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
        guard index < keys.count else { stop(); return }
        releasePlayer()
        let key = keys[index]; let token = revision
        loadingKey = key
        startLoadDeadline(key: key, token: token)
        if let source {
            guard let url = source(key) else { error = "تعذّر العثور على تلاوة هذا المقطع."; stop(); return }
            if let cacheKey = cacheKey?(key) {
                resolvingSource = Task { [weak self] in
                    guard let self else { return }
                    let local = await self.cachedSource(cacheKey)
                    guard !Task.isCancelled, self.revision == token, self.loadingKey == key else { return }
                    self.resolvingSource = nil
                    self.startPlayer(url: local ?? url, key: key, token: token)
                }
            } else { startPlayer(url: url, key: key, token: token) }
        } else {
            resolvingSource = Task { [weak self] in
                guard let self else { return }
                let url: URL?
                if self.reciterDirectory == "Abdul_Basit_Murattal_64kbps" {
                    url = await self.resolveSource(key)
                } else {
                    let parts = key.split(separator: ":").compactMap { Int($0) }
                    let permitted = ["Abdurrahmaan_As-Sudais_64kbps", "Hudhaify_64kbps", "Maher_AlMuaiqly_64kbps", "Saood_ash-Shuraym_64kbps"]
                    url = parts.count == 2 && permitted.contains(self.reciterDirectory)
                        ? URL(string: String(format: "https://everyayah.com/data/%@/%03d%03d.mp3", self.reciterDirectory, parts[0], parts[1])) : nil
                }
                guard !Task.isCancelled, self.revision == token, self.loadingKey == key else { return }
                self.resolvingSource = nil
                guard let url else { self.error = "تعذّر العثور على تلاوة هذا المقطع."; self.stop(); return }
                self.startPlayer(url: url, key: key, token: token)
            }
        }
    }
    private func startPlayer(url: URL, key: String, token: UUID) {
        do {
            traceAudio("session.category.begin")
            try AVAudioSession.sharedInstance().setCategory(.playback)
            traceAudio("session.category.end")
            traceAudio("session.activate.begin")
            try AVAudioSession.sharedInstance().setActive(true)
            traceAudio("session.activate.end")
        } catch { self.error = "تعذّر تشغيل الصوت على الجهاز."; stop(); return }
        traceAudio("item.create.begin")
        let item = AVPlayerItem(url: url)
        traceAudio("item.create.end")
        traceAudio("player.create.begin")
        let playback = AVPlayer(playerItem: item); player = playback
        traceAudio("player.create.end")
        item.audioTimePitchAlgorithm = .spectral
        loadingKey = key
        playbackObservation = playback.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            Task { @MainActor in
                self?.refreshPlaybackState(player, key: key, token: token)
            }
        }
        observation = item.observe(\.status, options: [.new, .initial]) { [weak self, weak playback] item, _ in
            Task { @MainActor in
                guard let self, let playback, self.revision == token,
                      self.player === playback, playback.currentItem === item else { return }
                if item.status == .failed {
                    self.error = "تعذّر تشغيل الآية. أعد تنزيلها أو تحقق من الاتصال."; self.stop()
                } else {
                    // Readiness and time-control notifications can arrive in
                    // either order. Both must converge on the same state.
                    self.refreshPlaybackState(playback, key: key, token: token)
                }
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
        traceAudio("player.play.begin")
        playback.playImmediately(atRate: playbackRate)
        traceAudio("player.play.end")
    }
    private func refreshPlaybackState(_ playback: AVPlayer, key: String, token: UUID) {
        guard revision == token, player === playback else { return }
        if playback.timeControlStatus == .playing,
           playback.currentItem?.status == .readyToPlay {
            traceAudio("ready-state.begin")
            loadDeadline?.cancel(); loadDeadline = nil
            playing = key; loadingKey = nil
            if let seconds = bookmarkSeconds, durationSeconds > 0 {
                bookmarkSeconds = nil
                seek(to: min(seconds, max(0, durationSeconds - 0.05)))
            }
            if !reportedStart { reportedStart = true; onVerse?(key) }
            updateNowPlaying()
            traceAudio("ready-state.end")
        } else if !isPaused {
            playing = nil; loadingKey = key
            startLoadDeadline(key: key, token: token)
        }
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
        let interrupted = onSequenceInterrupted
        onSequenceInterrupted = nil; onSequenceFinished = nil
        saveBookmark(); bookmarkSeconds = nil
        sleepTask?.cancel(); sleepTask = nil; stopAtBoundary = false; sleepStatus = nil
        revision = UUID(); delay?.cancel(); delay = nil; waitingKey = nil
        releasePlayer(); keys = []; index = 0; pass = 0
        NoorAudioFocus.shared.releasePlayback(focusID)
        if !remoteTargets.isEmpty { MPNowPlayingInfoCenter.default().nowPlayingInfo = nil }
        for (command, target) in remoteTargets { command.removeTarget(target) }
        remoteTargets = []
        interrupted?()
    }
    private func updateNowPlaying() {
        // Unknown/loading items must retain their load deadline and must not
        // cause synchronous metadata queries on the main actor.
        guard !remoteTargets.isEmpty,
              player?.currentItem?.status == .readyToPlay else { return }
        traceAudio("now-playing.begin")
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [MPMediaItemPropertyTitle: displayName,
            MPMediaItemPropertyPlaybackDuration: durationSeconds, MPNowPlayingInfoPropertyElapsedPlaybackTime: currentSeconds,
            MPNowPlayingInfoPropertyPlaybackRate: isPaused ? Float(0) : playbackRate]
        traceAudio("now-playing.end")
    }
    private func installRemoteControls() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.isEnabled = true; center.pauseCommand.isEnabled = true
        center.stopCommand.isEnabled = true; center.togglePlayPauseCommand.isEnabled = true
        center.changePlaybackPositionCommand.isEnabled = true
        remoteTargets.append((center.pauseCommand, center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pausePlayback() }; return .success
        }))
        remoteTargets.append((center.playCommand, center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.resumePlayback() }; return .success
        }))
        remoteTargets.append((center.togglePlayPauseCommand, center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in guard let self else { return }; if self.isPaused { self.resumePlayback() } else { self.pausePlayback() } }; return .success
        }))
        remoteTargets.append((center.stopCommand, center.stopCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.stop() }; return .success
        }))
        remoteTargets.append((center.changePlaybackPositionCommand, center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let position = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let seconds = position.positionTime
            Task { @MainActor in self?.seek(to: seconds) }; return .success
        }))
    }
    deinit {
        let id = focusID
        Task { @MainActor in NoorAudioFocus.shared.unregister(id) }
        resolvingSource?.cancel()
        delay?.cancel()
        loadDeadline?.cancel()
        sleepTask?.cancel()
        for (command, target) in remoteTargets { command.removeTarget(target) }
        if let end { NotificationCenter.default.removeObserver(end) }
        if let failure { NotificationCenter.default.removeObserver(failure) }
    }
}
