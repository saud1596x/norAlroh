import Foundation
import Compression

/// Decode before touching local progress. The output limit is enforced during
/// inflation, not after an unbounded NSData allocation has already happened.
enum NoorCloudPayload {
    static let compressedLimit = 750_000
    static let decodedLimit = 10_000_000

    static func decode(_ compressed: Data, limit: Int = decodedLimit) throws -> Data {
        guard !compressed.isEmpty, compressed.count <= compressedLimit,
              limit > 0, limit <= decodedLimit else { throw CocoaError(.fileReadCorruptFile) }
        return try compressed.withUnsafeBytes { raw in
            guard let source = raw.bindMemory(to: UInt8.self).baseAddress else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let chunkSize = 32_768
            let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: chunkSize)
            defer { destination.deallocate() }
            var stream = compression_stream(dst_ptr: destination, dst_size: chunkSize,
                                            src_ptr: source, src_size: compressed.count)
            guard compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else {
                throw CocoaError(.fileReadCorruptFile)
            }
            defer { compression_stream_destroy(&stream) }
            stream.src_ptr = source; stream.src_size = compressed.count
            var output = Data()
            while true {
                stream.dst_ptr = destination; stream.dst_size = chunkSize
                let previousInput = stream.src_size
                let status = compression_stream_process(&stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                let produced = chunkSize - stream.dst_size
                guard status != COMPRESSION_STATUS_ERROR, produced <= limit - output.count else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                output.append(destination, count: produced)
                if status == COMPRESSION_STATUS_END {
                    guard stream.src_size == 0, !output.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
                    return output
                }
                // Missing stream terminators cannot spin forever or return a
                // partially decoded archive as a successful restore.
                guard produced > 0 || stream.src_size < previousInput else {
                    throw CocoaError(.fileReadCorruptFile)
                }
            }
        }
    }
}
