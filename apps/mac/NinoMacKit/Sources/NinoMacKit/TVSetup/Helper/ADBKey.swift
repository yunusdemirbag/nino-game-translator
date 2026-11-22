// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation
import Security

/// ADB'nin RSA anahtarı (2048 bit, e = 65537).
///
/// Dosya `adb/adbkey`: PEM PKCS#8 (`BEGIN PRIVATE KEY`, standart adb ile aynı) ya da PKCS#1
/// (`BEGIN RSA PRIVATE KEY`) okunur; yeni anahtar PKCS#8 PEM olarak 0600 yazılır. Anahtarlığa hiç dokunulmaz
/// (anahtar kalıcı değil, yalnız bellekte).
public struct ADBKey: @unchecked Sendable {
    public let privateKey: SecKey
    /// PKCS#1 RSAPrivateKey DER.
    public let pkcs1: Data

    public enum KeyError: Error, Equatable {
        case unreadable(String)
        case generateFailed(String)
        case signFailed(String)
    }

    public static let fileName = "adbkey"

    // MARK: Yükleme / üretme

    public init(pkcs1 der: Data) throws {
        let attrs: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPrivate,
        ]
        var err: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(der as CFData, attrs as CFDictionary, &err) else {
            throw KeyError.unreadable(err.map { "\($0.takeRetainedValue())" } ?? "SecKeyCreateWithData")
        }
        privateKey = key
        pkcs1 = der
    }

    /// PEM ya da ham DER (PKCS#1 veya PKCS#8).
    public init(fileData: Data) throws {
        let text = String(decoding: fileData, as: UTF8.self)
        var der = fileData
        if text.contains("-----BEGIN") {
            let body = text.split(whereSeparator: \.isNewline)
                .filter { !$0.hasPrefix("-----") }
                .joined()
            guard let d = Data(base64Encoded: body, options: .ignoreUnknownCharacters) else {
                throw KeyError.unreadable("PEM")
            }
            der = d
        }
        if let inner = ASN1.pkcs8PrivateKey(der) { der = inner }
        try self.init(pkcs1: der)
    }

    public static func generate() throws -> ADBKey {
        let attrs: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits: 2048,
            kSecAttrIsPermanent: false,
        ]
        var err: Unmanaged<CFError>?
        guard let key = SecKeyCreateRandomKey(attrs as CFDictionary, &err),
              let der = SecKeyCopyExternalRepresentation(key, &err) as Data? else {
            throw KeyError.generateFailed(err.map { "\($0.takeRetainedValue())" } ?? "SecKeyCreateRandomKey")
        }
        return try ADBKey(pkcs1: der)
    }

    /// `dir/adbkey` varsa onu okur (TV onu "yetkili" hatırlıyor); yoksa ya da okunamazsa yenisini yazar.
    /// Okunamayan eski dosya silinmez, `adbkey.bad` adıyla kenara konur.
    public static func loadOrCreate(in dir: URL, log: (String) -> Void = { _ in }) throws -> ADBKey {
        let fm = FileManager.default
        let file = dir.appendingPathComponent(fileName)
        if let data = fm.contents(atPath: file.path) {
            do { return try ADBKey(fileData: data) } catch {
                log("ADB anahtarı okunamadı (\(error)); yenisi üretiliyor.")
                let bad = dir.appendingPathComponent(fileName + ".bad")
                try? fm.removeItem(at: bad)
                try? fm.moveItem(at: file, to: bad)
            }
        }
        let key = try generate()
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        fm.createFile(atPath: file.path, contents: Data(key.pem().utf8), attributes: [.posixPermissions: 0o600])
        let pub = dir.appendingPathComponent(fileName + ".pub")
        if let line = try? key.publicKeyLine() {
            fm.createFile(atPath: pub.path, contents: Data(line.utf8), attributes: [.posixPermissions: 0o644])
        }
        return key
    }

    /// PKCS#8 PEM (standart adb'nin yazdığı biçim).
    public func pem() -> String {
        let b64 = ASN1.wrapPKCS8(pkcs1).base64EncodedString(options: [.lineLength64Characters, .endLineWithLineFeed])
        return "-----BEGIN PRIVATE KEY-----\n\(b64)\n-----END PRIVATE KEY-----\n"
    }

    // MARK: İmza

    /// AUTH jetonunu imzalar: jeton hazır bir SHA-1 özeti sayılır (adbd RSA_verify(NID_sha1, token) ile denetler).
    public func sign(token: Data) throws -> Data {
        var err: Unmanaged<CFError>?
        guard let sig = SecKeyCreateSignature(privateKey, .rsaSignatureDigestPKCS1v15SHA1, token as CFData, &err) as Data? else {
            throw KeyError.signFailed(err.map { "\($0.takeRetainedValue())" } ?? "SecKeyCreateSignature")
        }
        return sig
    }

    // MARK: Açık anahtar (Android RSAPublicKey biçimi)

    /// Modül ve üs (büyük-sonlu baytlar).
    public func publicComponents() throws -> (modulus: Data, exponent: Data) {
        guard let pub = SecKeyCopyPublicKey(privateKey) else { throw KeyError.unreadable("public key") }
        var err: Unmanaged<CFError>?
        guard let der = SecKeyCopyExternalRepresentation(pub, &err) as Data?,
              let parts = ASN1.rsaPublicKey(der) else { throw KeyError.unreadable("public key DER") }
        return parts
    }

    /// AOSP `android_pubkey` yapısı: modül sözcük sayısı, n0inv (-1/n[0] mod 2^32), modül (küçük-sonlu),
    /// rr = R² mod n (R = 2^2048, küçük-sonlu), üs. Hepsi küçük-sonlu 32 bit sözcükler.
    public func androidPublicKey() throws -> Data {
        let (modulus, exponent) = try publicComponents()
        return try Self.androidPublicKey(modulus: modulus, exponent: exponent)
    }

    public static func androidPublicKey(modulus: Data, exponent: Data) throws -> Data {
        let size = 256
        var n = [UInt8](modulus.drop(while: { $0 == 0 }))
        guard n.count == size else { throw KeyError.unreadable("modulus must be 2048 bit") }
        n.reverse() // küçük-sonlu
        let words = (0..<(size / 4)).map { i in
            UInt32(n[i * 4]) | UInt32(n[i * 4 + 1]) << 8 | UInt32(n[i * 4 + 2]) << 16 | UInt32(n[i * 4 + 3]) << 24
        }
        // n0inv: n[0]'ın 2^32'ye göre tersi (Newton), eksi işaretlisi.
        var inv: UInt32 = 1
        for _ in 0..<5 { inv = inv &* (2 &- words[0] &* inv) }
        let n0inv = 0 &- inv
        let rr = BigWords.powerOfTwoMod(4096, words)
        var e: UInt32 = 0
        for b in exponent { e = e << 8 | UInt32(b) }

        var out = Data()
        out.appendLE(UInt32(size / 4))
        out.appendLE(n0inv)
        out.append(contentsOf: n)
        for w in rr { out.appendLE(w) }
        out.appendLE(e)
        return out
    }

    /// AUTH RSAPUBLICKEY verisi ve `.pub` dosyası: "<base64> <ad>" (+ NUL iletide).
    public func publicKeyLine(name: String = "nino@mac") throws -> String {
        try androidPublicKey().base64EncodedString() + " " + name
    }
}

/// 32 bit sözcüklerle küçük çok-duyarlıklı aritmetik (yalnız R² mod n için).
enum BigWords {
    /// 2^exp mod n; n küçük-sonlu sözcükler. Kaydır ve gerekirse çıkar.
    static func powerOfTwoMod(_ exp: Int, _ n: [UInt32]) -> [UInt32] {
        let count = n.count
        var x = [UInt32](repeating: 0, count: count + 1)
        x[0] = 1
        let m = n + [0]
        for _ in 0..<exp {
            var carry: UInt32 = 0
            for i in 0...count {
                let v = x[i]
                x[i] = v << 1 | carry
                carry = v >> 31
            }
            if !less(x, m) { subtract(&x, m) }
        }
        return Array(x.prefix(count))
    }

    static func less(_ a: [UInt32], _ b: [UInt32]) -> Bool {
        for i in stride(from: a.count - 1, through: 0, by: -1) where a[i] != b[i] { return a[i] < b[i] }
        return false
    }

    static func subtract(_ a: inout [UInt32], _ b: [UInt32]) {
        var borrow: UInt64 = 0
        for i in 0..<a.count {
            let d = UInt64(a[i]) &- UInt64(b[i]) &- borrow
            a[i] = UInt32(truncatingIfNeeded: d)
            borrow = (d >> 63) & 1
        }
    }
}

/// Anahtar dosyaları için en küçük DER okuyucu/yazıcı.
enum ASN1 {
    struct Element {
        var tag: UInt8
        var content: Data
        var next: Int
    }

    static func read(_ d: Data, at offset: Int) -> Element? {
        let b = [UInt8](d)
        var i = offset
        guard i + 2 <= b.count else { return nil }
        let tag = b[i]; i += 1
        var len = Int(b[i]); i += 1
        if len & 0x80 != 0 {
            let n = len & 0x7f
            guard n >= 1, n <= 4, i + n <= b.count else { return nil }
            len = 0
            for _ in 0..<n { len = len << 8 | Int(b[i]); i += 1 }
        }
        guard i + len <= b.count else { return nil }
        return Element(tag: tag, content: Data(b[i..<(i + len)]), next: i + len)
    }

    static func children(_ d: Data) -> [Element] {
        var out: [Element] = []
        var i = 0
        while i < d.count, let e = read(d, at: i) { out.append(e); i = e.next }
        return out
    }

    static let rsaEncryptionOID = Data([0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01])

    /// PKCS#8 PrivateKeyInfo ise içindeki PKCS#1 anahtarı; değilse nil.
    static func pkcs8PrivateKey(_ der: Data) -> Data? {
        guard let top = read(der, at: 0), top.tag == 0x30 else { return nil }
        let items = children(top.content)
        guard items.count >= 3, items[0].tag == 0x02, items[1].tag == 0x30, items[2].tag == 0x04,
              let oid = children(items[1].content).first, oid.tag == 0x06, oid.content == rsaEncryptionOID
        else { return nil }
        return items[2].content
    }

    /// RSAPublicKey (PKCS#1) ya da SubjectPublicKeyInfo'dan modül ve üs.
    static func rsaPublicKey(_ der: Data) -> (modulus: Data, exponent: Data)? {
        guard let top = read(der, at: 0), top.tag == 0x30 else { return nil }
        let items = children(top.content)
        if items.count == 2, items[0].tag == 0x02, items[1].tag == 0x02 {
            return (items[0].content, items[1].content)
        }
        if items.count == 2, items[0].tag == 0x30, items[1].tag == 0x03, items[1].content.count > 1 {
            return rsaPublicKey(items[1].content.dropFirst())
        }
        return nil
    }

    static func encodeLength(_ n: Int) -> Data {
        if n < 0x80 { return Data([UInt8(n)]) }
        var bytes: [UInt8] = []
        var v = n
        while v > 0 { bytes.insert(UInt8(v & 0xff), at: 0); v >>= 8 }
        return Data([0x80 | UInt8(bytes.count)] + bytes)
    }

    static func tlv(_ tag: UInt8, _ content: Data) -> Data {
        var d = Data([tag])
        d.append(encodeLength(content.count))
        d.append(content)
        return d
    }

    static func wrapPKCS8(_ pkcs1: Data) -> Data {
        let version = tlv(0x02, Data([0]))
        let algorithm = tlv(0x30, tlv(0x06, rsaEncryptionOID) + Data([0x05, 0x00]))
        return tlv(0x30, version + algorithm + tlv(0x04, pkcs1))
    }
}
