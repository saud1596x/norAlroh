import AVFoundation
import Foundation

/// Audio capture never waits for model loading, inference or UI updates.
/// The pipe serializes tap shutdown with conversion and drains the final PCM.
protocol QuranAudioCapture: AnyObject {
    func start() throws
    func stop() async -> Result<Int64, Error>
}

final class QuranMicrophoneCapture: QuranAudioCapture {
    private let engine: AVAudioEngine
    private let pipe: Pipe
    private let inputEvents: QuranAudioInputEvents
    private var installed = false
    init(writer: QuranPCMWriter, onFailure: @escaping (Error) -> Void) throws {
        let engine = AVAudioEngine()
        let input = engine.inputNode.outputFormat(forBus: 0)
        guard input.sampleRate > 0, input.channelCount > 0 else { throw QuranCaptureFailure.invalidSamples }
        self.engine = engine
        pipe = try Pipe(format: input, writer: writer, onFailure: onFailure)
        inputEvents = QuranAudioInputEvents(engine: engine, onFailure: onFailure)
    }
    func start() throws {
        let pipe = self.pipe
        let input = engine.inputNode
        input.installTap(onBus: 0, bufferSize: 4096, format: input.outputFormat(forBus: 0)) { buffer, _ in
            pipe.append(buffer)
        }
        installed = true; engine.prepare()
        inputEvents.arm()
        do { try engine.start() }
        catch { inputEvents.disarm(); engine.inputNode.removeTap(onBus: 0); installed = false; throw error }
    }
    func stop() async -> Result<Int64, Error> {
        inputEvents.disarm()
        engine.stop()
        if installed { engine.inputNode.removeTap(onBus: 0); installed = false }
        return await withCheckedContinuation { continuation in
            pipe.finish { continuation.resume(returning: $0) }
        }
    }
    deinit { inputEvents.disarm(); engine.stop(); if installed { engine.inputNode.removeTap(onBus: 0) } }
    private final class Pipe {
        private let lock = NSLock()
        private let resampler: QuranPCMResampler
        private let writer: QuranPCMWriter
        private let onFailure: (Error) -> Void
        private var stopped = false
        private var failure: Error?
        init(format: AVAudioFormat, writer: QuranPCMWriter, onFailure: @escaping (Error) -> Void) throws {
            resampler = try QuranPCMResampler(input: format); self.writer = writer; self.onFailure = onFailure
        }
        func append(_ buffer: AVAudioPCMBuffer) {
            lock.lock(); defer { lock.unlock() }
            guard !stopped else { return }
            do {
                let samples = try resampler.convert(buffer)
                if !samples.isEmpty { writer.append(samples) }
            } catch { stopped = true; failure = error; onFailure(error) }
        }
        func finish(_ completion: @escaping (Result<Int64, Error>) -> Void) {
            lock.lock()
            if !stopped {
                stopped = true
                do { let tail = try resampler.finish(); if !tail.isEmpty { writer.append(tail) } }
                catch { failure = error; onFailure(error) }
            }
            let failure = self.failure
            lock.unlock()
            writer.finish { result in completion(failure.map { .failure($0) } ?? result) }
        }
    }
}

enum QuranAudioInputFailure: Error {
    case configurationChanged, routeChanged, interrupted, mediaServicesUnavailable
}

/// A stopped hardware engine does not necessarily deliver another tap buffer or
/// conversion error. Report input loss once so the controller closes the take
/// and offers explicit resume; never claim an automatic restart succeeded.
final class QuranAudioInputEvents {
    private let center: NotificationCenter
    private let onFailure: (Error) -> Void
    private let lock = NSLock()
    private var armed = false
    private var observations: [NSObjectProtocol] = []
    init(engine: AnyObject, center: NotificationCenter = .default, onFailure: @escaping (Error) -> Void) {
        self.center = center; self.onFailure = onFailure
        observations.append(center.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil) { [weak self] _ in
            self?.fail(QuranAudioInputFailure.configurationChanged)
        })
        observations.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: nil) { [weak self] event in
            guard let reason = event.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  [AVAudioSession.RouteChangeReason.newDeviceAvailable.rawValue,
                   AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue,
                   AVAudioSession.RouteChangeReason.routeConfigurationChange.rawValue,
                   AVAudioSession.RouteChangeReason.noSuitableRouteForCategory.rawValue].contains(reason) else { return }
            self?.fail(QuranAudioInputFailure.routeChanged)
        })
        observations.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: nil) { [weak self] event in
            guard (event.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) == AVAudioSession.InterruptionType.began.rawValue else { return }
            self?.fail(QuranAudioInputFailure.interrupted)
        })
        for name in [AVAudioSession.mediaServicesWereLostNotification, AVAudioSession.mediaServicesWereResetNotification] {
            observations.append(center.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
                self?.fail(QuranAudioInputFailure.mediaServicesUnavailable)
            })
        }
    }
    func arm() { lock.lock(); armed = true; lock.unlock() }
    func disarm() { lock.lock(); armed = false; lock.unlock() }
    private func fail(_ error: Error) {
        lock.lock()
        guard armed else { lock.unlock(); return }
        armed = false; lock.unlock()
        // Apple's configuration callback can run on an internal engine queue.
        // Do not stop or deallocate AVAudioEngine synchronously from it. The
        // production failure callback dispatches controller.pause to MainActor.
        onFailure(error)
    }
    deinit { observations.forEach { center.removeObserver($0) } }
}

/// The latest completed audio window replaces older pending inference only.
/// All audio remains in the writer. Constant space even on a slow device.
final class QuranWindowMailbox {
    private let lock = NSLock()
    private var latest: QuranAudioWindow?
    func put(_ value: QuranAudioWindow) { lock.lock(); defer { lock.unlock() }; latest = value }
    func take() -> QuranAudioWindow? { lock.lock(); defer { lock.unlock() }; defer { latest = nil }; return latest }
}
