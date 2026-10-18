import AVFoundation
import Foundation

/// Audio capture never waits for model loading, inference or UI updates.
/// The pipe serializes tap shutdown with conversion and drains the final PCM.
protocol QuranAudioCapture: AnyObject {
    func start() throws
    func stop() async -> Result<Int64, Error>
    func observeLevel(_ observer: @escaping @Sendable (Float) -> Void)
    func observeQuality(_ observer: @escaping @Sendable (QuranInputQuality.Reading) -> Void)
}
extension QuranAudioCapture {
    func observeLevel(_ observer: @escaping @Sendable (Float) -> Void) {}
    func observeQuality(_ observer: @escaping @Sendable (QuranInputQuality.Reading) -> Void) {}
}

final class QuranMicrophoneCapture: QuranAudioCapture {
    private let engine: AVAudioEngine
    private let inputNode: AVAudioInputNode
    private let inputFormat: AVAudioFormat
    private let pipe: Pipe
    private let inputEvents: QuranAudioInputEvents
    private var installed = false
    init(writer: QuranPCMWriter, onFailure: @escaping @Sendable (Error) -> Void) throws {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let input = inputNode.outputFormat(forBus: 0)
        guard input.sampleRate > 0, input.channelCount > 0 else { throw QuranCaptureFailure.invalidSamples }
        self.engine = engine
        self.inputNode = inputNode; inputFormat = input
        pipe = try Pipe(format: input, writer: writer, onFailure: onFailure)
        inputEvents = QuranAudioInputEvents(engine: engine, onFailure: onFailure)
    }
    func start() throws {
        guard !installed else { return }
        let pipe = self.pipe
        // Retain the node/format for this take. Shutdown must not ask the
        // engine to initialize or rediscover its input after route loss.
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { buffer, time in
            pipe.append(buffer, at: time)
        }
        installed = true; engine.prepare()
        inputEvents.arm()
        do { try engine.start() }
        catch { inputEvents.disarm(); inputNode.removeTap(onBus: 0); installed = false; throw error }
    }
    func observeLevel(_ observer: @escaping @Sendable (Float) -> Void) { pipe.observeLevel(observer) }
    func observeQuality(_ observer: @escaping @Sendable (QuranInputQuality.Reading) -> Void) { pipe.observeQuality(observer) }
    func stop() async -> Result<Int64, Error> {
        inputEvents.disarm()
        engine.stop()
        if installed { inputNode.removeTap(onBus: 0); installed = false }
        return await withCheckedContinuation { continuation in
            pipe.finish { continuation.resume(returning: $0) }
        }
    }
    deinit { inputEvents.disarm(); engine.stop(); if installed { inputNode.removeTap(onBus: 0) } }
    private final class Pipe {
        private let lock = NSLock()
        private let resampler: QuranPCMResampler
        private let writer: QuranPCMWriter
        private let onFailure: @Sendable (Error) -> Void
        private var stopped = false
        private var failure: Error?
        private var levelObserver: (@Sendable (Float) -> Void)?
        private var qualityObserver: (@Sendable (QuranInputQuality.Reading) -> Void)?
        private var quality = QuranInputQuality()
        private var clock = QuranCaptureClock()
        init(format: AVAudioFormat, writer: QuranPCMWriter, onFailure: @escaping @Sendable (Error) -> Void) throws {
            resampler = try QuranPCMResampler(input: format); self.writer = writer; self.onFailure = onFailure
        }
        func append(_ buffer: AVAudioPCMBuffer, at time: AVAudioTime) {
            lock.lock(); defer { lock.unlock() }
            guard !stopped else { return }
            do {
                // Tap delivery time is not the device's acoustic clock. Do not
                // concatenate a lost/repeated device interval into a fake
                // continuous take or fill it with generated silence.
                if buffer.frameLength > 0 {
                    try clock.consume(frames: Int64(buffer.frameLength), rate: buffer.format.sampleRate,
                        sampleTime: time.isSampleTimeValid ? time.sampleTime : nil,
                        sampleRate: time.isSampleTimeValid ? time.sampleRate : nil,
                        hostTime: time.isHostTimeValid ? time.hostTime : nil)
                }
                let samples = try resampler.convert(buffer)
                if !samples.isEmpty {
                    // Read the converted microphone samples, independently of
                    // model throughput. A decorative pulse is not input proof.
                    levelObserver?(samples.reduce(Float(0)) { max($0, abs($1)) })
                    for reading in quality.consume(samples) { qualityObserver?(reading) }
                    writer.append(samples)
                }
            } catch { stopped = true; failure = error; onFailure(error) }
        }
        func observeLevel(_ observer: @escaping @Sendable (Float) -> Void) {
            lock.lock(); levelObserver = observer; lock.unlock()
        }
        func observeQuality(_ observer: @escaping @Sendable (QuranInputQuality.Reading) -> Void) {
            lock.lock(); qualityObserver = observer; lock.unlock()
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
    case invalidDeviceClock, discontinuousDeviceClock
}

/// Per-take acoustic continuity before resampling. Sample positions are exact;
/// host-only stamps use elapsed device ticks, never callback arrival latency.
/// AVAudioTime may provide either representation (Apple AVAudioTime docs).
struct QuranCaptureClock {
    private enum Source { case samples(next: Int64), host(origin: UInt64, frames: Int64) }
    private var source: Source?
    private var rate: Double?
    mutating func consume(frames: Int64, rate: Double, sampleTime: Int64?,
                          sampleRate: Double?, hostTime: UInt64?) throws {
        guard frames > 0, rate.isFinite, rate > 0,
              self.rate == nil || self.rate == rate else { throw QuranAudioInputFailure.invalidDeviceClock }
        let next: Source
        if let source {
            switch source {
            case .samples(let expected):
                guard let sampleTime, sampleRate == rate else { throw QuranAudioInputFailure.invalidDeviceClock }
                guard sampleTime == expected else { throw QuranAudioInputFailure.discontinuousDeviceClock }
                let (end, overflow) = sampleTime.addingReportingOverflow(frames)
                guard !overflow else { throw QuranAudioInputFailure.invalidDeviceClock }
                next = .samples(next: end)
            case .host(let origin, let recorded):
                guard let hostTime, hostTime >= origin else { throw QuranAudioInputFailure.invalidDeviceClock }
                let elapsed = AVAudioTime.seconds(forHostTime: hostTime - origin)
                // One microsecond tolerates host-tick conversion, not a missing
                // PCM frame at the supported 8..192kHz device sampling rates.
                guard elapsed.isFinite, abs(elapsed - Double(recorded) / rate) <= min(0.000001, 0.1 / rate) else {
                    throw QuranAudioInputFailure.discontinuousDeviceClock
                }
                let (total, overflow) = recorded.addingReportingOverflow(frames)
                guard !overflow else { throw QuranAudioInputFailure.invalidDeviceClock }
                next = .host(origin: origin, frames: total)
            }
        } else if let sampleTime {
            guard sampleRate == rate else { throw QuranAudioInputFailure.invalidDeviceClock }
            let (end, overflow) = sampleTime.addingReportingOverflow(frames)
            guard !overflow else { throw QuranAudioInputFailure.invalidDeviceClock }
            next = .samples(next: end)
        } else if let hostTime { next = .host(origin: hostTime, frames: frames) }
        else { throw QuranAudioInputFailure.invalidDeviceClock }
        self.source = next; self.rate = rate
    }
}

/// A stopped hardware engine does not necessarily deliver another tap buffer or
/// conversion error. Report input loss once so the controller closes the take
/// and offers explicit resume; never claim an automatic restart succeeded.
final class QuranAudioInputEvents {
    private let center: NotificationCenter
    private let onFailure: @Sendable (Error) -> Void
    private let lock = NSLock()
    private var armed = false
    private var observations: [NSObjectProtocol] = []
    init(engine: AnyObject, center: NotificationCenter = .default, onFailure: @escaping @Sendable (Error) -> Void) {
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

/// Coalesce overlapping windows only when their predecessor still covers the
/// removed audio. A cold model must not silently skip the beginning of a take.
/// Eight eight-second windows bound memory to ~4 MB; overload is explicit and
/// affects tracking only. The independent writer retains the original audio.
final class QuranWindowMailbox {
    enum Failure: Error { case overloaded, discontinuousAudio }
    private let lock = NSLock()
    private let capacity: Int
    private var pending: [QuranAudioWindow] = []
    private var deliveredEnd: Int64 = 0
    private var receivedEnd: Int64 = 0
    private var failure: Failure?
    init(capacity: Int = 8) { self.capacity = max(1, capacity) }
    func put(_ value: QuranAudioWindow) {
        lock.lock(); defer { lock.unlock() }
        guard failure == nil else { return }
        guard value.startFrame >= 0, value.endFrame > receivedEnd,
              value.endFrame - value.startFrame == Int64(value.samples.count),
              !value.samples.isEmpty, value.samples.count <= 128_000,
              value.startFrame <= receivedEnd else {
            failure = .discontinuousAudio; pending.removeAll(); return
        }
        receivedEnd = value.endFrame
        if !pending.isEmpty {
            let predecessorEnd = pending.count > 1 ? pending[pending.count - 2].endFrame : deliveredEnd
            // Retain a second of overlap for words crossing a decode boundary.
            let replacementStart = max(0, predecessorEnd - 16_000)
            if value.startFrame <= replacementStart {
                pending[pending.count - 1] = value
                return
            }
        }
        guard pending.count < capacity else {
            failure = .overloaded; pending.removeAll(); return
        }
        pending.append(value)
    }
    func take() throws -> QuranAudioWindow? {
        lock.lock(); defer { lock.unlock() }
        if let failure { throw failure }
        guard !pending.isEmpty else { return nil }
        let next = pending.removeFirst()
        deliveredEnd = next.endFrame
        return next
    }
}
