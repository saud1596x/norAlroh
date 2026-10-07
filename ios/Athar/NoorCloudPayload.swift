import Foundation
import zlib

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
            // Foundation's .zlib archives use raw DEFLATE, not an RFC 1950
            // wrapper. zlib exposes exact unused input; Compression can read
            // ahead past the terminator and silently consume appended bytes.
            var stream = z_stream()
            guard inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION,
                                Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
                throw CocoaError(.fileReadCorruptFile)
            }
            defer { inflateEnd(&stream) }
            stream.next_in = UnsafeMutablePointer(mutating: source)
            stream.avail_in = UInt32(compressed.count)
            var output = Data()
            while true {
                stream.next_out = destination; stream.avail_out = UInt32(chunkSize)
                let previousInput = stream.avail_in
                let status = inflate(&stream, Z_NO_FLUSH)
                let produced = chunkSize - Int(stream.avail_out)
                guard (status == Z_OK || status == Z_STREAM_END), produced <= limit - output.count else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                output.append(destination, count: produced)
                if status == Z_STREAM_END {
                    guard stream.avail_in == 0, Int(stream.total_in) == compressed.count,
                          !output.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
                    return output
                }
                // Missing stream terminators cannot spin forever or return a
                // partially decoded archive as a successful restore.
                guard produced > 0 || stream.avail_in < previousInput else {
                    throw CocoaError(.fileReadCorruptFile)
                }
            }
        }
    }
}
