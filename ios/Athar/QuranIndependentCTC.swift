import Foundation
import CoreML
import CryptoKit

/// Bundled acoustic CTC only: no passage prompt, network, microphone ownership,
/// forced alignment, canonical replacement text or pronunciation verdict.
actor QuranIndependentCTC {
    static let shared = QuranIndependentCTC()
    private var model: MLModel?
    private var projection: [Int] = []
    private var characters: [String] = []
    static let revision = "b539d5fa66deb820c8e4762171ecb284ace4b52d"
    static let configuration = "coreml-ctc-float32/raw-20ms/no-prompt/paired1"
    private struct Descriptor: Decodable {
        let schema: Int
        let revision: String
        let precision: String
        let sourceWeightsSHA256: String
        let convertedWeightsSHA256: String
        let files: [String: String]
    }
    func prepare() throws {
        guard model == nil else { return }
        guard let folder = Bundle.main.url(forResource: "IndependentCTC", withExtension: nil) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let descriptor = try JSONDecoder().decode(Descriptor.self, from: Data(contentsOf: folder.appendingPathComponent("verified-model.json")))
        guard descriptor.schema == 1, descriptor.revision == Self.revision, descriptor.precision == "float32",
              descriptor.sourceWeightsSHA256 == "202cb1eefd7c399d117140014dc773da358e895e6e6b2312d999e7fda503febf",
              descriptor.convertedWeightsSHA256 == "bb4a2ffd5eb4082d8383c721887294886594ba77ec0d4611b38ea1796e231833",
              !descriptor.files.isEmpty, descriptor.files.count <= 128 else { throw CocoaError(.fileReadCorruptFile) }
        for (path, expected) in descriptor.files {
            guard !path.hasPrefix("/"), !path.split(separator: "/").contains(".."),
                  expected.count == 64 else { throw CocoaError(.fileReadCorruptFile) }
            let file = folder.appendingPathComponent(path)
            let handle = try FileHandle(forReadingFrom: file)
            defer { try? handle.close() }
            var digest = SHA256()
            while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty { digest.update(data: data) }
            guard digest.finalize().map({String(format:"%02x",$0)}).joined() == expected else {
                throw CocoaError(.fileReadCorruptFile)
            }
        }
        let vocabularyData = try Data(contentsOf: folder.appendingPathComponent("vocab.json"))
        guard SHA256.hash(data: vocabularyData).map({String(format:"%02x",$0)}).joined()
            == "60b9e6174798b6e1a92c92fb5935e32522aebaca4cdd1f481fd220346471644c" else { throw CocoaError(.fileReadCorruptFile) }
        let source = try JSONDecoder().decode([String:Int].self, from: vocabularyData)
        guard source.count == 56, Set(source.values) == Set(0..<56), source["<pad>"] == 0,
              source["|"] == 4 else { throw CocoaError(.fileReadCorruptFile) }
        func normalized(_ value: String) -> String {
            QuranAlignedWord.normalize(value).replacingOccurrences(of:"أ",with:"ا")
                .replacingOccurrences(of:"إ",with:"ا").replacingOccurrences(of:"آ",with:"ا")
        }
        let letters = Set(source.keys.filter { $0.unicodeScalars.count == 1 && $0 != "|" }
            .map(normalized).filter { !$0.isEmpty }).sorted()
        characters = ["", " "] + letters
        let indices = Dictionary(uniqueKeysWithValues: characters.enumerated().map {($0.element,$0.offset)})
        projection = Array(repeating:0,count:56)
        for (character, id) in source {
            projection[id] = character == "|" ? 1 : character.unicodeScalars.count == 1 ? indices[normalized(character)] ?? 0 : 0
        }
        let settings = MLModelConfiguration()
        // This route is measured separately on the Simulator; no phone/ANE
        // speed claim follows from the Mac conversion experiment.
        settings.computeUnits = .all
        model = try MLModel(contentsOf: folder.appendingPathComponent("quran-ctc.mlmodelc"), configuration: settings)
    }
    func recognize(_ window: QuranAudioWindow) throws -> QuranIndependentObservation {
        guard window.startFrame >= 0, window.endFrame >= window.startFrame,
              window.endFrame-window.startFrame == Int64(window.samples.count),
              (400...256_000).contains(window.samples.count), window.samples.allSatisfy({$0.isFinite && abs($0)<=1}) else {
            throw QuranAlignmentFailure.invalidEvidence
        }
        try Task.checkCancellation()
        try prepare()
        guard let model else { throw CocoaError(.fileReadCorruptFile) }
        let mean = window.samples.reduce(0.0) { $0 + Double($1) } / Double(window.samples.count)
        let variance = window.samples.reduce(0.0) { $0 + pow(Double($1)-mean,2) } / Double(window.samples.count)
        let divisor = sqrt(variance+1e-7)
        let input = try MLMultiArray(shape:[1, NSNumber(value:window.samples.count)],dataType:.float32)
        let pointer = input.dataPointer.assumingMemoryBound(to:Float.self)
        for index in window.samples.indices { pointer[index] = Float((Double(window.samples[index])-mean)/divisor) }
        let prediction = try model.prediction(from: MLDictionaryFeatureProvider(dictionary:["input_values":input]))
        try Task.checkCancellation()
        guard let logits = prediction.featureValue(for:"logits")?.multiArrayValue,
              logits.shape.map(\.intValue) == [1,(window.samples.count-400)/320+1,56] else {
            throw QuranAlignmentFailure.invalidEvidence
        }
        let frames = logits.shape[1].intValue
        var symbols: [(label:Int,first:Int,end:Int,posterior:Double,count:Int)] = []
        var previous = 0
        for frame in 0..<frames {
            var scores = [Double](repeating:0,count:56)
            for label in 0..<56 {
                let value = logits[[0,NSNumber(value:frame),NSNumber(value:label)]].doubleValue
                guard value.isFinite else { throw QuranAlignmentFailure.invalidEvidence }
                scores[label] = value
            }
            let peak = scores.max()!
            let exponentials = scores.map { exp($0-peak) }, total = exponentials.reduce(0,+)
            var projected = [Double](repeating:0,count:characters.count)
            for label in 0..<56 { projected[projection[label]] += exponentials[label]/total }
            let label = projected.indices.max(by:{ projected[$0] < projected[$1] })!
            if label != 0 {
                if label == previous, !symbols.isEmpty {
                    symbols[symbols.count-1].end = frame+1
                    symbols[symbols.count-1].posterior += projected[label]
                    symbols[symbols.count-1].count += 1
                } else { symbols.append((label,frame,frame+1,projected[label],1)) }
            }
            previous = label
        }
        var words: [QuranIndependentWord] = [], text = "", start = 0, end = 0, sum = 0.0, count = 0
        func finish() {
            guard !text.isEmpty, count > 0 else { return }
            words.append(.init(text:text,start:Double(start)*0.02,end:Double(end)*0.02,
                               meanPosterior:sum/Double(count)))
            text = ""; sum = 0; count = 0
        }
        for symbol in symbols {
            if symbol.label == 1 { finish(); continue }
            if text.isEmpty { start = symbol.first }
            text += characters[symbol.label]; end = symbol.end; sum += symbol.posterior; count += symbol.count
        }
        finish()
        let sourceSHA = window.samples.withUnsafeBufferPointer { buffer in
            SHA256.hash(data:Data(buffer:buffer)).map{String(format:"%02x",$0)}.joined()
        }
        return .init(modelRevision:Self.revision,configuration:Self.configuration,sourceSHA256:sourceSHA,
                     startFrame:window.startFrame,endFrame:window.endFrame,words:words)
    }
}
