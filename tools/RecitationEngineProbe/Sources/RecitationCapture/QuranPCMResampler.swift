import AVFoundation
import Foundation

/// One converter per microphone take preserves its filter history and sample
/// clock. An input buffer is offered exactly once, never repeated to fill an
/// output request. Call finish after removing the microphone tap.
public final class QuranPCMResampler {
    private let converter: AVAudioConverter
    private var ended = false
    public init(input: AVAudioFormat) throws {
        guard input.sampleRate.isFinite, input.sampleRate > 0, input.channelCount > 0,
              let output = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000,
                  channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: input, to: output) else {
            throw QuranCaptureFailure.invalidSamples
        }
        self.converter = converter
    }
    public func convert(_ input: AVAudioPCMBuffer) throws -> [Float] {
        guard !ended, input.format == converter.inputFormat, input.frameLength > 0 else {
            throw QuranCaptureFailure.invalidSamples
        }
        var supplied = false
        return try drain { _, status in
            guard !supplied else { status.pointee = .noDataNow; return nil }
            supplied = true; status.pointee = .haveData; return input
        }
    }
    public func finish() throws -> [Float] {
        guard !ended else { return [] }
        ended = true
        return try drain { _, status in status.pointee = .endOfStream; return nil }
    }
    private func drain(_ input: @escaping AVAudioConverterInputBlock) throws -> [Float] {
        var result: [Float] = []
        // The live tap supplies 4096 frames. A hard bound rejects a broken
        // converter instead of hanging the audio callback or duplicating input.
        for _ in 0..<32 {
            guard let output = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: 4096) else {
                throw QuranCaptureFailure.invalidSamples
            }
            var error: NSError?
            let status = converter.convert(to: output, error: &error, withInputFrom: input)
            if let error { throw error }
            guard status != .error, let channel = output.floatChannelData?[0] else {
                throw QuranCaptureFailure.invalidSamples
            }
            result.append(contentsOf: UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
            if status == .inputRanDry || status == .endOfStream { return result }
            guard output.frameLength > 0 else { throw QuranCaptureFailure.invalidSamples }
        }
        throw QuranCaptureFailure.overloadedWriter
    }
}
