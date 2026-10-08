import SwiftUI
import AVFoundation
import UIKit
import Combine
import UniformTypeIdentifiers

enum RecitationArchive {
    /// Decode before replacing the saved take. An interrupted or empty capture must preserve it.
    static func save(capture: URL, destination: URL) throws {
        let check = try AVAudioPlayer(contentsOf: capture)
        guard check.duration.isFinite, check.duration > 0 else { throw CocoaError(.fileReadCorruptFile) }
        try Data(contentsOf: capture).write(to: destination, options: [.atomic, .completeFileProtection])
    }
}

@MainActor final class LocalRecitationRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate, AVAudioPlayerDelegate {
    @Published private(set) var recording = false
    @Published private(set) var playing = false
    @Published private(set) var hasRecording = false
    @Published var message: String?
    @Published private(set) var level = 0.0
    @Published private(set) var elapsed = 0.0
    @Published private(set) var duration = 0.0
    @Published private(set) var playbackTime = 0.0
    private var capture: URL?
    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var file: URL?
    @Published private(set) var requestingPermission = false
    private var startRevision = 0
    override init() {
        super.init()
        do {
            let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("NoorRecitation", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var folder = directory; var attributes = URLResourceValues(); attributes.isExcludedFromBackup = true
            try folder.setResourceValues(attributes)
            file = directory.appendingPathComponent("latest-recitation.m4a")
            hasRecording = file.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
        } catch { message = "تعذّر تجهيز مساحة التسجيل." }
    }
    func start() async {
        guard !recording, !requestingPermission else { return }
        requestingPermission = true
        let requestedRevision = startRevision
        defer { requestingPermission = false }
        let granted = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
        }
        guard requestedRevision == startRevision else { return }
        guard granted else { message = "اسمح باستخدام الميكروفون من إعدادات iPhone لتسجيل مراجعتك. يمكنك متابعة الحفظ دون تسجيل."; return }
        guard requestedRevision == startRevision, let file, UIApplication.shared.applicationState == .active else { return }
        do {
            stop()
            let session = AVAudioSession.sharedInstance()
            try MushafCaptureAudio.configure(session)
            try session.setActive(true)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            let temporary = file.deletingLastPathComponent().appendingPathComponent(".capture-" + UUID().uuidString + ".m4a")
            capture = temporary
            let audio = try AVAudioRecorder(url: temporary, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44100, AVNumberOfChannelsKey: 1, AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue])
            audio.delegate = self; audio.isMeteringEnabled = true; recorder = audio
            guard audio.prepareToRecord(), audio.record(forDuration: 300) else { throw CocoaError(.fileWriteUnknown) }
            message = nil; elapsed = 0; level = 0; recording = true
        } catch { stop(saveCapture: false); message = "تعذّر بدء التسجيل. تأكد من مساحة الجهاز والميكروفون." }
    }
    func updateMeters() {
        if recording, let recorder {
            recorder.updateMeters(); elapsed = recorder.currentTime
            level = min(1, max(0, pow(10, Double(recorder.averagePower(forChannel: 0)) / 20)))
        } else if playing, let player { playbackTime = player.currentTime }
    }
    func stop(saveCapture: Bool = true) {
        startRevision += 1
        let shouldSave = recording && saveCapture
        recorder?.stop(); recorder = nil; player?.stop(); player = nil
        recording = false; playing = false; level = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        if let capture, let file {
            if shouldSave {
                do {
                    try RecitationArchive.save(capture: capture, destination: file)
                } catch { message = "تعذّر حفظ التسجيل الجديد. التسجيل السابق لم يُستبدل. حاول مجددًا." }
            }
            do { if FileManager.default.fileExists(atPath: capture.path) { try FileManager.default.removeItem(at: capture) } }
            catch { message = "تعذّر حذف ملف التسجيل المؤقت. احذف التسجيلات من الإعدادات للمحاولة مجددًا." }
        }
        capture = nil
        hasRecording = file.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
    }
    func play() {
        guard !recording, let file, hasRecording else { return }
        do {
            let session = AVAudioSession.sharedInstance(); try session.setCategory(.playback, mode: .spokenAudio)
            try session.setActive(true)
            let audio = try AVAudioPlayer(contentsOf: file); audio.delegate = self; player = audio
            guard audio.play() else { throw CocoaError(.fileReadUnknown) }
            duration = audio.duration; playbackTime = 0; playing = true; message = nil
        } catch { message = "تعذّر تشغيل التسجيل."; stop() }
    }
    func seek(to time: Double) {
        guard time.isFinite, playing, let player else { return }
        player.currentTime = min(player.duration, max(0, time)); playbackTime = player.currentTime
    }
    @discardableResult func erase() -> Bool {
        stop()
        guard let file else { return true }
        do {
            let directory = file.deletingLastPathComponent()
            if FileManager.default.fileExists(atPath: directory.path) {
                let owned = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                    .filter { $0.lastPathComponent == file.lastPathComponent || $0.lastPathComponent.hasPrefix(".capture-") }
                for url in owned { try FileManager.default.removeItem(at: url) }
            }
            hasRecording = false; elapsed = 0; duration = 0; playbackTime = 0; return true
        } catch { message = "تعذّر حذف التسجيلات؛ حاول مجددًا."; return false }
    }
    func exportRecording() throws -> Data? {
        stop()
        guard hasRecording, let file else { return nil }
        return try Data(contentsOf: file)
    }
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self, self.recorder === recorder else { return }
            self.stop(saveCapture: flag); if !flag { self.message = "لم يكتمل التسجيل. التسجيل السابق لم يُستبدل." }
        }
    }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self, self.player === player else { return }; self.stop()
        }
    }
}

struct RecitationRecordingControls: View {
    @EnvironmentObject var audio: LocalRecitationRecorder
    @EnvironmentObject var speech: LocalSpeechRecitation
    var recordingAllowed = true
    @State private var replaceConfirmation = false
    @State private var deleteConfirmation = false
    @State private var exporting = false
    @State private var document = ExportDocument(bytes: Data())
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("سجّل تسميعك", systemImage: "mic.fill").font(.headline)
            Text("سمّع من حفظك، ثم استمع وقارن بالنص.").font(.subheadline).foregroundStyle(.secondary)
            HStack {
                Button {
                    if audio.recording { audio.stop() }
                    else if audio.hasRecording { replaceConfirmation = true }
                    else { speech.stop(); Task { await audio.start() } }
                } label: {
                    Label(audio.recording ? "إيقاف وحفظ" : audio.requestingPermission ? "طلب إذن الميكروفون…" : "ابدأ التسميع", systemImage: audio.recording ? "stop.circle.fill" : "mic")
                }.frame(minHeight: 44).disabled(audio.requestingPermission || (!recordingAllowed && !audio.recording))
                    .accessibilityIdentifier("recitation.record")
                if audio.hasRecording && !audio.recording {
                    Button { if audio.playing { audio.stop() } else { audio.play() } } label: {
                        Label(audio.playing ? "إيقاف" : "استماع", systemImage: audio.playing ? "stop" : "play")
                    }.frame(minHeight: 44).accessibilityIdentifier("recitation.play")
                }
            }.font(.subheadline).buttonStyle(.bordered)
            if audio.hasRecording && !audio.recording {
                HStack {
                    Button("تصدير الصوت", systemImage: "square.and.arrow.up") {
                        do {
                            if let bytes = try audio.exportRecording() { document = ExportDocument(bytes: bytes); exporting = true }
                        } catch { audio.message = "تعذّر تجهيز ملف الصوت للتصدير." }
                    }.accessibilityIdentifier("recitation.export")
                    Spacer()
                    Button("حذف", role: .destructive) { deleteConfirmation = true }.accessibilityIdentifier("recitation.delete")
                }.font(.caption).frame(minHeight: 44)
            }
            if audio.recording {
                HStack {
                    Image(systemName: "waveform").foregroundStyle(Theme.gold)
                    NoorProgressBar(value: audio.level, label: "مستوى صوت الميكروفون", height: 6)
                    Text("\(Int(audio.elapsed)) / ٣٠٠ ث").font(.caption.monospacedDigit()).accessibilityIdentifier("recitation.elapsed")
                }.transition(.opacity)
            }
            if audio.playing && audio.duration > 0 {
                Slider(value: Binding(get: { audio.playbackTime }, set: { audio.seek(to: $0) }), in: 0...audio.duration)
                    .accessibilityLabel("موضع تشغيل التسميع").accessibilityIdentifier("recitation.position")
                HStack {
                    Text(audio.playbackTime, format: .number.precision(.fractionLength(0)))
                    Spacer()
                    Text("\(Int(audio.duration)) ثانية")
                }.font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Text("تسجيل محلي حتى ٥ دقائق. التسجيل الجديد يستبدل السابق بعد نجاح حفظه. لا إرسال إلى خادم ولا تصحيح آلي.")
                .font(.caption).foregroundStyle(.secondary)
        }.onDisappear { audio.stop() }
        .confirmationDialog("بدء تسجيل جديد؟ يبقى التسجيل السابق حتى ينجح حفظ الجديد.", isPresented: $replaceConfirmation, titleVisibility: .visible) {
            Button("بدء تسجيل جديد") { speech.stop(); Task { await audio.start() } }
            Button("إلغاء", role: .cancel) {}
        }
        .confirmationDialog("حذف تسميعك المحفوظ نهائيًا؟", isPresented: $deleteConfirmation, titleVisibility: .visible) {
            Button("حذف التسجيل", role: .destructive) { _ = audio.erase() }
            Button("إلغاء", role: .cancel) {}
        }
        .fileExporter(isPresented: $exporting, document: document, contentType: .mpeg4Audio, defaultFilename: "noor-alruh-recitation") { result in
            if case .failure = result { audio.message = "لم يُصدّر الصوت. اختر مكانًا متاحًا وحاول مجددًا." }
        }
        .onReceive(Timer.publish(every: 0.15, on: .main, in: .common).autoconnect()) { _ in audio.updateMeters() }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { _ in audio.stop() }
        .alert("التسجيل", isPresented: Binding(get: { audio.message != nil }, set: { if !$0 { audio.message = nil } })) {
            Button("تم") { audio.message = nil }
        } message: { Text(audio.message ?? "") }
    }
}
