// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Compression
import Foundation

/// gzip (RFC 1952) açıcı. Gövde sistemin Compression çerçevesiyle açılır.
public enum Gzip {
    public enum Failure: Error, Equatable {
        case badHeader
        case badBody
        case sizeMismatch
    }

    /// İlk iki bayt `1f 8b` ve boy ≥ 18 mi?
    public static func isGzip(_ data: Data) -> Bool {
        data.count >= 18 && data[data.startIndex] == 0x1f && data[data.startIndex + 1] == 0x8b
    }

    public static func decompress(_ data: Data) throws -> Data {
        let bytes = [UInt8](data)
        guard bytes.count >= 18, bytes[0] == 0x1f, bytes[1] == 0x8b, bytes[2] == 8 else { throw Failure.badHeader }
        let flags = bytes[3]
        var pos = 10
        let end = bytes.count - 8
        if flags & 0x04 != 0 { // FEXTRA
            guard pos + 2 <= end else { throw Failure.badHeader }
            pos += 2 + (Int(bytes[pos]) | Int(bytes[pos + 1]) << 8)
        }
        for flag: UInt8 in [0x08, 0x10] where flags & flag != 0 { // FNAME, FCOMMENT
            while pos < end, bytes[pos] != 0 { pos += 1 }
            pos += 1
        }
        if flags & 0x02 != 0 { pos += 2 } // FHCRC
        guard pos <= end else { throw Failure.badHeader }

        let expected = UInt32(bytes[end + 4]) | UInt32(bytes[end + 5]) << 8
            | UInt32(bytes[end + 6]) << 16 | UInt32(bytes[end + 7]) << 24
        let out = try inflate(Array(bytes[pos..<end]), sizeHint: Int(expected))
        guard UInt32(truncatingIfNeeded: out.count) == expected else { throw Failure.sizeMismatch }
        return out
    }

    /// Ham deflate akışını açar.
    static func inflate(_ input: [UInt8], sizeHint: Int) throws -> Data {
        let streamPointer = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
        defer { streamPointer.deallocate() }
        guard compression_stream_init(streamPointer, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else {
            throw Failure.badBody
        }
        defer { compression_stream_destroy(streamPointer) }

        let chunk = 1 << 20
        var output = Data()
        output.reserveCapacity(min(max(sizeHint, chunk), 1 << 30))
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: chunk)
        defer { buffer.deallocate() }

        return try input.withUnsafeBufferPointer { inBuf -> Data in
            streamPointer.pointee.src_ptr = inBuf.baseAddress ?? UnsafePointer(buffer)
            streamPointer.pointee.src_size = inBuf.count
            while true {
                streamPointer.pointee.dst_ptr = buffer
                streamPointer.pointee.dst_size = chunk
                let status = compression_stream_process(streamPointer, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                output.append(buffer, count: chunk - streamPointer.pointee.dst_size)
                switch status {
                case COMPRESSION_STATUS_OK:
                    if streamPointer.pointee.src_size == 0, streamPointer.pointee.dst_size == chunk { throw Failure.badBody }
                case COMPRESSION_STATUS_END:
                    return output
                default:
                    throw Failure.badBody
                }
            }
        }
    }
}
