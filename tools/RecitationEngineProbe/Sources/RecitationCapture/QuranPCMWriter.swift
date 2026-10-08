import Foundation
import AVFoundation

public struct QuranAudioWindow {
    public let samples: [Float]
    public let startFrame: Int64
    public let endFrame: Int64
    public var offset: Double { Double(startFrame) / 16_000 }
}

public enum QuranCaptureFailure: Error { case existingFile, invalidSamples, overloadedWriter, closed }

/// Recording owns its own serial writer. Recognition receives bounded copies
/// only after audio was written; inference failure cannot erase the recording.
/// A saturated writer stops visibly rather than dropping input silently.
public final class QuranPCMWriter {
    public let url: URL
    private let queue = DispatchQueue(label: "Noor.QuranPCMWriter", qos: .userInitiated)
    private let lock = NSLock()
    private var pending = 0
    private var accepting = true
    private var file: AVAudioFile?
    private let format: AVAudioFormat
    private var frames: Int64 = 0
    private var ring: [Float] = []
    private var lastWindowEnd: Int64 = 0
    private var failed: Error?
    private let onWindow: (QuranAudioWindow) -> Void
    private let onFailure: (Error) -> Void
    public init(url: URL, onWindow: @escaping (QuranAudioWindow) -> Void,
                onFailure: @escaping (Error) -> Void) throws {
        guard !FileManager.default.fileExists(atPath: url.path) else { throw QuranCaptureFailure.existingFile }
        self.url = url; self.onWindow = onWindow; self.onFailure = onFailure
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000,
                                        channels: 1, interleaved: false) else { throw QuranCaptureFailure.invalidSamples }
        self.format = format
        file = try AVAudioFile(forWriting: url, settings: format.settings)
        ring.reserveCapacity(128_000)
    }
    public func append(_ samples: [Float]) {
        lock.lock()
        guard accepting else { lock.unlock(); return }
        if pending >= 32 {
            accepting = false; lock.unlock()
            queue.async { [self] in fail(QuranCaptureFailure.overloadedWriter) }
            return
        }
        pending += 1; lock.unlock()
        queue.async { [self] in
            defer { lock.lock(); pending -= 1; lock.unlock() }
            guard failed == nil else { return }
            do {
                guard !samples.isEmpty, samples.count <= 32_000, samples.allSatisfy(\.isFinite),
                      let file, let buffer = AVAudioPCMBuffer(pcmFormat: format,
                          frameCapacity: AVAudioFrameCount(samples.count)), let data = buffer.floatChannelData else {
                    throw QuranCaptureFailure.invalidSamples
                }
                buffer.frameLength = AVAudioFrameCount(samples.count)
                samples.withUnsafeBufferPointer { input in data[0].update(from: input.baseAddress!, count: samples.count) }
                try file.write(from: buffer)
                frames += Int64(samples.count)
                ring.append(contentsOf: samples)
                if ring.count > 128_000 { ring.removeFirst(ring.count - 128_000) }
                if frames >= 64_000 && frames - lastWindowEnd >= 32_000 { emitWindow() }
            } catch { fail(error) }
        }
    }
    private func emitWindow() {
        guard !ring.isEmpty else { return }
        lastWindowEnd = frames
        onWindow(.init(samples: ring, startFrame: frames - Int64(ring.count), endFrame: frames))
    }
    private func fail(_ error: Error) {
        guard failed == nil else { return }
        failed = error
        lock.lock(); accepting = false; lock.unlock()
        file = nil // Finalize the bytes already saved. Never delete or replace.
        onFailure(error)
    }
    /// Stop capture before calling this. Completion runs after every accepted
    /// buffer and closes the file, so relaunch playback can use the real bytes.
    public func finish(_ completion: @escaping (Result<Int64, Error>) -> Void) {
        lock.lock(); accepting = false; lock.unlock()
        queue.async { [self] in
            if failed == nil && frames != lastWindowEnd { emitWindow() }
            file = nil
            if let failed { completion(.failure(failed)) }
            else { completion(.success(frames)) }
        }
    }
}
