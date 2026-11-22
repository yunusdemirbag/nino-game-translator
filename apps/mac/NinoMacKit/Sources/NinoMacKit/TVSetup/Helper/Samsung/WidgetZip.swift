// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Compression
import Foundation

/// `.wgt` (zip) okuma ve yeniden yazma. Var olan girdiler sıkıştırılmış hâlleriyle olduğu gibi taşınır; yeni girdiler
/// (imza dosyaları) deflate ile yazılır. Zip64 desteklenmez (TV paketi küçük).
struct WidgetZip {
    struct Entry {
        var name: String
        var method: UInt16
        var flags: UInt16
        var crc: UInt32
        var compressed: Data
        var uncompressedSize: UInt32
        var modTime: UInt16
        var modDate: UInt16
        var isDirectory: Bool { name.hasSuffix("/") }
    }

    enum Failure: Error, Equatable, CustomStringConvertible {
        case malformed(String)
        case unsupported(String)
        var description: String {
            switch self {
            case let .malformed(m): return "zip: \(m)"
            case let .unsupported(m): return "zip: \(m) desteklenmiyor"
            }
        }
    }

    var entries: [Entry]

    init(entries: [Entry]) { self.entries = entries }

    init(data: Data) throws {
        let b = [UInt8](data)
        func u16(_ i: Int) -> UInt16 { UInt16(b[i]) | UInt16(b[i + 1]) << 8 }
        func u32(_ i: Int) -> UInt32 { UInt32(u16(i)) | UInt32(u16(i + 2)) << 16 }
        // Merkezi dizin sonu kaydı.
        guard b.count >= 22 else { throw Failure.malformed("çok kısa") }
        var eocd = -1
        var i = b.count - 22
        let lowest = max(0, b.count - 22 - 65535)
        while i >= lowest {
            if u32(i) == 0x0605_4b50 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { throw Failure.malformed("merkezi dizin yok") }
        let count = Int(u16(eocd + 10))
        var p = Int(u32(eocd + 16))
        if count == 0xffff || p == 0xffff_ffff { throw Failure.unsupported("zip64") }
        var out: [Entry] = []
        for _ in 0..<count {
            guard p + 46 <= b.count, u32(p) == 0x0201_4b50 else { throw Failure.malformed("merkezi dizin") }
            let flags = u16(p + 8), method = u16(p + 10)
            let time = u16(p + 12), date = u16(p + 14)
            let crc = u32(p + 16), csize = Int(u32(p + 20)), usize = u32(p + 24)
            let nlen = Int(u16(p + 28)), xlen = Int(u16(p + 30)), clen = Int(u16(p + 32))
            let local = Int(u32(p + 42))
            guard p + 46 + nlen <= b.count else { throw Failure.malformed("ad") }
            let name = String(decoding: b[(p + 46)..<(p + 46 + nlen)], as: UTF8.self)
            if flags & 1 != 0 { throw Failure.unsupported("şifreli girdi") }
            guard local + 30 <= b.count, u32(local) == 0x0403_4b50 else { throw Failure.malformed("yerel başlık") }
            let start = local + 30 + Int(u16(local + 26)) + Int(u16(local + 28))
            guard start + csize <= b.count else { throw Failure.malformed("veri") }
            out.append(Entry(name: name, method: method, flags: flags & 0x0800, crc: crc,
                             compressed: Data(b[start..<(start + csize)]), uncompressedSize: usize,
                             modTime: time, modDate: date))
            p += 46 + nlen + xlen + clen
        }
        entries = out
    }

    /// Girdinin açılmış baytları.
    static func contents(_ e: Entry) throws -> Data {
        switch e.method {
        case 0: return e.compressed
        case 8:
            let out = try inflate(e.compressed, expected: Int(e.uncompressedSize))
            guard crc32(out) == e.crc else { throw Failure.malformed("CRC \(e.name)") }
            return out
        default: throw Failure.unsupported("sıkıştırma \(e.method)")
        }
    }

    static func entry(name: String, contents: Data, date: Date = Date()) -> Entry {
        let deflated = (try? deflate(contents)) ?? contents
        let useDeflate = deflated.count < contents.count
        let (t, d) = dosTime(date)
        return Entry(name: name, method: useDeflate ? 8 : 0, flags: 0x0800, crc: crc32(contents),
                     compressed: useDeflate ? deflated : contents, uncompressedSize: UInt32(contents.count),
                     modTime: t, modDate: d)
    }

    func encoded() -> Data {
        var out = Data()
        var central = Data()
        func le16(_ v: UInt16, _ d: inout Data) { d.append(UInt8(v & 0xff)); d.append(UInt8(v >> 8)) }
        func le32(_ v: UInt32, _ d: inout Data) { d.appendLE(v) }
        for e in entries {
            let name = Data(e.name.utf8)
            let offset = UInt32(out.count)
            let version: UInt16 = e.method == 8 ? 20 : 10
            le32(0x0403_4b50, &out); le16(version, &out); le16(e.flags, &out); le16(e.method, &out)
            le16(e.modTime, &out); le16(e.modDate, &out); le32(e.crc, &out)
            le32(UInt32(e.compressed.count), &out); le32(e.uncompressedSize, &out)
            le16(UInt16(name.count), &out); le16(0, &out)
            out.append(name); out.append(e.compressed)

            le32(0x0201_4b50, &central); le16(0x031e, &central); le16(version, &central); le16(e.flags, &central)
            le16(e.method, &central); le16(e.modTime, &central); le16(e.modDate, &central); le32(e.crc, &central)
            le32(UInt32(e.compressed.count), &central); le32(e.uncompressedSize, &central)
            le16(UInt16(name.count), &central); le16(0, &central); le16(0, &central); le16(0, &central)
            le16(0, &central)
            le32(e.isDirectory ? 0o40755 << 16 | 0x10 : 0o100644 << 16, &central)
            le32(offset, &central)
            central.append(name)
        }
        let cdOffset = UInt32(out.count)
        out.append(central)
        le32(0x0605_4b50, &out); le16(0, &out); le16(0, &out)
        le16(UInt16(entries.count), &out); le16(UInt16(entries.count), &out)
        le32(UInt32(central.count), &out); le32(cdOffset, &out); le16(0, &out)
        return out
    }

    // MARK: Yardımcılar

    static func dosTime(_ date: Date) -> (UInt16, UInt16) {
        let c = Calendar(identifier: .gregorian).dateComponents(in: TimeZone.current, from: date)
        let t = UInt16((c.hour ?? 0) << 11 | (c.minute ?? 0) << 5 | (c.second ?? 0) / 2)
        let d = UInt16(max(0, (c.year ?? 1980) - 1980) << 9 | (c.month ?? 1) << 5 | (c.day ?? 1))
        return (t, d)
    }

    static let crcTable: [UInt32] = (0..<256).map { n -> UInt32 in
        var c = UInt32(n)
        for _ in 0..<8 { c = c & 1 != 0 ? 0xedb8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    static func crc32(_ d: Data) -> UInt32 {
        var c: UInt32 = 0xffff_ffff
        for b in d { c = crcTable[Int((c ^ UInt32(b)) & 0xff)] ^ (c >> 8) }
        return c ^ 0xffff_ffff
    }

    /// Ham deflate (RFC 1951); Compression'ın ZLIB'i başlıksızdır.
    static func inflate(_ d: Data, expected: Int) throws -> Data {
        if expected == 0 { return Data() }
        return try process(d, operation: COMPRESSION_STREAM_DECODE, capacityHint: expected)
    }

    static func deflate(_ d: Data) throws -> Data {
        try process(d, operation: COMPRESSION_STREAM_ENCODE, capacityHint: max(64, d.count))
    }

    static func process(_ input: Data, operation: compression_stream_operation, capacityHint: Int) throws -> Data {
        let streamPtr = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
        defer { streamPtr.deallocate() }
        guard compression_stream_init(streamPtr, operation, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else {
            throw Failure.malformed("deflate init")
        }
        defer { compression_stream_destroy(streamPtr) }
        let chunk = 64 * 1024
        let dst = UnsafeMutablePointer<UInt8>.allocate(capacity: chunk)
        defer { dst.deallocate() }
        var out = Data(capacity: capacityHint)
        return try input.withUnsafeBytes { (src: UnsafeRawBufferPointer) -> Data in
            streamPtr.pointee.src_ptr = src.bindMemory(to: UInt8.self).baseAddress ?? UnsafePointer(dst)
            streamPtr.pointee.src_size = input.count
            while true {
                streamPtr.pointee.dst_ptr = dst
                streamPtr.pointee.dst_size = chunk
                let status = compression_stream_process(streamPtr, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                out.append(dst, count: chunk - streamPtr.pointee.dst_size)
                switch status {
                case COMPRESSION_STATUS_OK: continue
                case COMPRESSION_STATUS_END: return out
                default: throw Failure.malformed("deflate")
                }
            }
        }
    }
}
