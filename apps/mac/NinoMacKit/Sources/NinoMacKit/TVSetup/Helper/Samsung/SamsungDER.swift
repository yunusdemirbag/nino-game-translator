// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// Samsung kurulumunun ASN.1 DER işleri (CSR, PKCS#12, X.509 okuma) için küçük yazıcı ve okuyucu.
enum DER {
    // MARK: Yazma

    static func length(_ n: Int) -> Data {
        if n < 0x80 { return Data([UInt8(n)]) }
        var bytes: [UInt8] = []
        var v = n
        while v > 0 { bytes.insert(UInt8(v & 0xff), at: 0); v >>= 8 }
        return Data([0x80 | UInt8(bytes.count)] + bytes)
    }

    static func tlv(_ tag: UInt8, _ content: Data) -> Data {
        var d = Data([tag])
        d.append(length(content.count))
        d.append(content)
        return d
    }

    static func sequence(_ items: Data...) -> Data { tlv(0x30, items.reduce(Data(), +)) }
    static func sequence(_ items: [Data]) -> Data { tlv(0x30, items.reduce(Data(), +)) }
    static func set(_ items: Data...) -> Data { tlv(0x31, items.reduce(Data(), +)) }
    static func octets(_ d: Data) -> Data { tlv(0x04, d) }
    static let null = Data([0x05, 0x00])
    static func utf8(_ s: String) -> Data { tlv(0x0c, Data(s.utf8)) }
    static func ia5(_ s: String) -> Data { tlv(0x16, Data(s.utf8)) }
    static func bmp(_ s: String) -> Data {
        var d = Data()
        for u in s.utf16 { d.append(UInt8(u >> 8)); d.append(UInt8(u & 0xff)) }
        return tlv(0x1e, d)
    }
    /// Bağlama özgü, yapılı ([n] EXPLICIT).
    static func explicit(_ n: UInt8, _ content: Data) -> Data { tlv(0xa0 | n, content) }
    static func bitString(_ d: Data) -> Data { tlv(0x03, Data([0]) + d) }

    static func integer(_ v: Int) -> Data {
        var bytes: [UInt8] = []
        var x = v
        repeat { bytes.insert(UInt8(x & 0xff), at: 0); x >>= 8 } while x > 0
        if bytes[0] & 0x80 != 0 { bytes.insert(0, at: 0) }
        return tlv(0x02, Data(bytes))
    }

    /// Noktalı OID metninden DER.
    static func oid(_ dotted: String) -> Data {
        let parts = dotted.split(separator: ".").compactMap { UInt64($0) }
        precondition(parts.count >= 2)
        var body = Data([UInt8(parts[0] * 40 + parts[1])])
        for p in parts.dropFirst(2) {
            var chunk: [UInt8] = [UInt8(p & 0x7f)]
            var v = p >> 7
            while v > 0 { chunk.insert(UInt8(v & 0x7f) | 0x80, at: 0); v >>= 7 }
            body.append(contentsOf: chunk)
        }
        return tlv(0x06, body)
    }

    static func algorithm(_ dotted: String, parameters: Data? = DER.null) -> Data {
        sequence(oid(dotted) + (parameters ?? Data()))
    }

    // MARK: Okuma

    struct Node {
        var tag: UInt8
        /// Bütün TLV (etiket + uzunluk + içerik).
        var raw: Data
        var content: Data

        var children: [Node] { DER.parseAll(content) }
        var isConstructed: Bool { tag & 0x20 != 0 }
        var oidText: String? { tag == 0x06 ? DER.oidText(content) : nil }
        var string: String? {
            switch tag {
            case 0x0c, 0x13, 0x16, 0x14, 0x12: return String(decoding: content, as: UTF8.self)
            case 0x1e:
                var u: [UInt16] = []
                let b = [UInt8](content)
                var i = 0
                while i + 1 < b.count { u.append(UInt16(b[i]) << 8 | UInt16(b[i + 1])); i += 2 }
                return String(decoding: u, as: UTF16.self)
            default: return nil
            }
        }
        var intValue: Int? {
            guard tag == 0x02, content.count <= 8 else { return nil }
            return content.reduce(0) { $0 << 8 | Int($1) }
        }
    }

    enum ParseError: Error { case truncated }

    static func parse(_ d: Data) throws -> Node {
        guard let (node, _) = parse(d, at: d.startIndex) else { throw ParseError.truncated }
        return node
    }

    static func parse(_ d: Data, at start: Int) -> (Node, Int)? {
        var i = start
        guard i + 2 <= d.endIndex else { return nil }
        let tag = d[i]; i += 1
        var len = Int(d[i]); i += 1
        if len & 0x80 != 0 {
            let n = len & 0x7f
            guard n >= 1, n <= 4, i + n <= d.endIndex else { return nil }
            len = 0
            for _ in 0..<n { len = len << 8 | Int(d[i]); i += 1 }
        }
        guard len >= 0, i + len <= d.endIndex else { return nil }
        let content = Data(d[i..<(i + len)])
        return (Node(tag: tag, raw: Data(d[start..<(i + len)]), content: content), i + len)
    }

    static func parseAll(_ d: Data) -> [Node] {
        var out: [Node] = []
        var i = d.startIndex
        while i < d.endIndex, let (n, next) = parse(d, at: i) { out.append(n); i = next }
        return out
    }

    static func oidText(_ content: Data) -> String {
        let b = [UInt8](content)
        guard let first = b.first else { return "" }
        var parts = [UInt64(first / 40), UInt64(first % 40)]
        var v: UInt64 = 0
        for byte in b.dropFirst() {
            v = v << 7 | UInt64(byte & 0x7f)
            if byte & 0x80 == 0 { parts.append(v); v = 0 }
        }
        return parts.map(String.init).joined(separator: ".")
    }

    /// UTCTime ya da GeneralizedTime (UTC, "Z").
    static func time(_ n: Node) -> Date? {
        let s = String(decoding: n.content, as: UTF8.self)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        switch n.tag {
        case 0x17: f.dateFormat = s.count >= 13 ? "yyMMddHHmmss'Z'" : "yyMMddHHmm'Z'"
        case 0x18: f.dateFormat = "yyyyMMddHHmmss'Z'"
        default: return nil
        }
        // UTCTime: 50 ve üstü 19xx (RFC 5280).
        if n.tag == 0x17, let d = f.date(from: s) {
            let year = Calendar(identifier: .gregorian).dateComponents(in: TimeZone(identifier: "UTC")!, from: d).year ?? 0
            if year >= 2050 { return Calendar(identifier: .gregorian).date(byAdding: .year, value: -100, to: d) }
            return d
        }
        return f.date(from: s)
    }
}

/// X.509 sertifikasının gereken alanları (konu, veren, geçerlilik) için küçük okuyucu.
struct X509Info: Equatable {
    var der: Data
    var issuerDER: Data
    var subjectDER: Data
    var notBefore: Date
    var notAfter: Date

    init?(der: Data) {
        guard let top = try? DER.parse(der), top.tag == 0x30,
              let tbs = top.children.first, tbs.tag == 0x30 else { return nil }
        var fields = tbs.children
        if fields.first?.tag == 0xa0 { fields.removeFirst() } // sürüm
        // seri, imza algoritması, veren, geçerlilik, konu
        guard fields.count >= 5, fields[2].tag == 0x30, fields[3].tag == 0x30, fields[4].tag == 0x30 else { return nil }
        let validity = fields[3].children
        guard validity.count == 2, let nb = DER.time(validity[0]), let na = DER.time(validity[1]) else { return nil }
        self.der = der
        issuerDER = fields[2].raw
        subjectDER = fields[4].raw
        notBefore = nb
        notAfter = na
    }

    var isSelfIssued: Bool { issuerDER == subjectDER }

    /// Adın ilk CN değeri (günlük için).
    static func commonName(_ nameDER: Data) -> String? {
        guard let name = try? DER.parse(nameDER) else { return nil }
        for rdn in name.children {
            for atv in rdn.children {
                let c = atv.children
                if c.count == 2, c[0].oidText == "2.5.4.3" { return c[1].string }
            }
        }
        return nil
    }

    var issuerCN: String { Self.commonName(issuerDER) ?? "?" }
    var subjectCN: String { Self.commonName(subjectDER) ?? "?" }

    /// PEM ya da DER metninden sertifikalar.
    static func certificates(fromPEMOrDER data: Data) -> [Data] {
        let text = String(decoding: data, as: UTF8.self)
        guard text.contains("-----BEGIN CERTIFICATE-----") else {
            return X509Info(der: data) != nil ? [data] : []
        }
        var out: [Data] = []
        var rest = Substring(text)
        while let b = rest.range(of: "-----BEGIN CERTIFICATE-----"),
              let e = rest.range(of: "-----END CERTIFICATE-----", range: b.upperBound..<rest.endIndex) {
            let body = rest[b.upperBound..<e.lowerBound].filter { !$0.isWhitespace }
            if let d = Data(base64Encoded: String(body)), X509Info(der: d) != nil { out.append(d) }
            rest = rest[e.upperBound...]
        }
        return out
    }
}
