import Foundation

/// Signal measurements only: silence is not a learner error and loud input is
/// not proof of speech. Measure pre-inference PCM without changing saved audio.
public struct QuranInputQuality: Sendable {
    public enum Reading: Equatable, Sendable {
        case noSignal, weak, clipping, present
        case invalidSignal, dcOffset, frozenInput
    }
    private var count = 0
    private var squared: Double = 0
    private var clipped = 0
    private var maximum: Float = 0
    private var sum: Double = 0
    private var invalid = 0
    private var previous: Float?
    private var constantRun = 0, longestConstantRun = 0
    public init() {}
    public mutating func consume(_ samples: [Float]) -> [Reading] {
        var output: [Reading] = []
        for sample in samples {
            // Count the actual input clock even for malformed samples. Skipping
            // them can conceal repeated corruption indefinitely.
            count += 1
            if !sample.isFinite || abs(sample) > 1 {
                invalid += 1; previous = nil; constantRun = 0
            } else {
                squared += Double(sample) * Double(sample); sum += Double(sample)
                maximum = max(maximum, abs(sample))
                if abs(sample) >= 0.995 { clipped += 1 }
                constantRun = sample != 0 && previous == sample ? constantRun + 1 : 1
                longestConstantRun = max(longestConstantRun, constantRun)
                previous = sample
            }
            if count == 8_000 {
                let rms = sqrt(squared / Double(count))
                let mean = sum / Double(count)
                let varyingRMS = sqrt(max(0, squared / Double(count) - mean * mean))
                let reading: Reading
                if invalid > 0 { reading = .invalidSignal }
                else if maximum == 0 { reading = .noSignal }
                else if Double(clipped) / Double(count) >= 0.01 { reading = .clipping }
                else if rms < 0.0005 { reading = .weak }
                else if longestConstantRun >= 3_200 { reading = .frozenInput }
                else if abs(mean) >= 0.03 && varyingRMS < abs(mean) * 0.5 { reading = .dcOffset }
                else { reading = .present }
                output.append(reading)
                count = 0; squared = 0; clipped = 0; maximum = 0
                sum = 0; invalid = 0; longestConstantRun = 0
            }
        }
        return output
    }
}

/// One inline action, measured in capture blocks, never overlapping decoder
/// windows. A short healthy burst must not erase persistent input advice.
public struct QuranInputGuidance: Sendable {
    public private(set) var message: String?
    private var issue: QuranInputQuality.Reading?
    private var issueBlocks = 0, healthyBlocks = 0
    public init() {}
    public mutating func consume(_ reading: QuranInputQuality.Reading) {
        if reading == .present {
            healthyBlocks += 1; issueBlocks = 0; issue = nil
            if healthyBlocks >= 3 { message = nil }
            return
        }
        healthyBlocks = 0
        let bucket: QuranInputQuality.Reading = reading == .noSignal ? .weak : reading
        if issue == bucket { issueBlocks += 1 }
        else { issue = bucket; issueBlocks = 1 }
        switch reading {
        case .invalidSignal:
            message = "إشارة الميكروفون غير سليمة؛ أوقف التسميع ثم أعد تشغيله."
        case .frozenInput where issueBlocks >= 2:
            message = "إشارة الميكروفون ثابتة؛ جرّب إعادة توصيله أو تشغيل التسميع."
        case .dcOffset where issueBlocks >= 2:
            message = "إشارة الميكروفون مشوّشة؛ جرّب ميكروفون الجهاز."
        case .clipping where issueBlocks >= 2:
            message = "الصوت مرتفع ومشوّش؛ أبعد الميكروفون قليلًا."
        case .weak, .noSignal:
            if issueBlocks >= 6 { message = "الصوت منخفض أو أنك متوقف؛ قرّب الميكروفون عند القراءة." }
        default: break
        }
    }
}
