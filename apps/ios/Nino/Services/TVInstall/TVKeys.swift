// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import CryptoKit
import Foundation
import Security

// DER kodlama, RSA anahtarı, X.509 tarihleri ve TLS istemci kimliği (adb'nin kablosuz hata ayıklaması, Samsung
// sertifika istekleri ve imzası, LG'nin SSH anahtarı).

struct TVKeyError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

// MARK: - DER

/// ASN.1 DER: yazıcı ve basit okuyucu.
enum ASN1 {
    static func node(_ tag: UInt8, _ body: Bytes) -> Bytes {
        var out: Bytes = [tag]
        let n = body.count
        if n < 0x80 {
            out.append(UInt8(n))
        } else {
            var length = Bytes()
            var rest = n
            while rest > 0 {
                length.insert(UInt8(rest & 0xFF), at: 0)
                rest >>= 8
            }
            out.append(0x80 | UInt8(length.count))
            out += length
        }
        return out + body
    }

    static func seq(_ parts: Bytes...) -> Bytes { node(0x30, parts.flatMap { $0 }) }
    static func seq(of parts: [Bytes]) -> Bytes { node(0x30, parts.flatMap { $0 }) }
    static func set(_ parts: Bytes...) -> Bytes { node(0x31, parts.flatMap { $0 }) }
    static let null: Bytes = [0x05, 0x00]
    static func bool(_ v: Bool) -> Bytes { node(0x01, [v ? 0xFF : 0x00]) }
    static func small(_ v: UInt8) -> Bytes { node(0x02, [v]) }
    static func octets(_ body: Bytes) -> Bytes { node(0x04, body) }
    static func bits(_ body: Bytes) -> Bytes { node(0x03, [0] + body) }
    static func utf8(_ s: String) -> Bytes { node(0x0C, Bytes(s.utf8)) }
    static func ia5(_ s: String) -> Bytes { node(0x16, Bytes(s.utf8)) }

    /// İşaretsiz büyük-endian tam sayı.
    static func unsigned(_ magnitude: Bytes) -> Bytes {
        var v = Array(magnitude.drop(while: { $0 == 0 }))
        if v.isEmpty { v = [0] }
        if v[0] >= 0x80 { v.insert(0, at: 0) }
        return node(0x02, v)
    }

    static func oid(_ dotted: String) -> Bytes {
        let arcs = dotted.split(separator: ".").map { UInt64($0)! }
        var body: Bytes = [UInt8(arcs[0] * 40 + arcs[1])]
        for arc in arcs.dropFirst(2) {
            var groups: Bytes = [UInt8(arc & 0x7F)]
            var rest = arc >> 7
            while rest > 0 {
                groups.insert(UInt8(rest & 0x7F) | 0x80, at: 0)
                rest >>= 7
            }
            body += groups
        }
        return node(0x06, body)
    }

    static func utcTime(_ date: Date) -> Bytes {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyMMddHHmmss'Z'"
        return node(0x17, Bytes(f.string(from: date).utf8))
    }

    struct Item {
        let tag: UInt8
        let body: Bytes
        var items: [Item] { (try? ASN1.parse(body)) ?? [] }
    }

    static func parse(_ data: Bytes) throws -> [Item] {
        var out: [Item] = []
        var i = 0
        while i < data.count {
            guard i + 2 <= data.count else { throw TVKeyError("DER truncated") }
            let tag = data[i]
            var length = Int(data[i + 1])
            i += 2
            if length >= 0x80 {
                let count = length & 0x7F
                guard (1...4).contains(count), i + count <= data.count else { throw TVKeyError("DER length") }
                length = data[i..<i + count].reduce(0) { $0 << 8 | Int($1) }
                i += count
            }
            guard i + length <= data.count else { throw TVKeyError("DER truncated") }
            out.append(Item(tag: tag, body: Array(data[i..<i + length])))
            i += length
        }
        return out
    }

    /// PEM metnini DER'e çevirir; PEM değilse veriyi olduğu gibi döner.
    static func unwrapPEM(_ data: Bytes) -> Bytes {
        guard let text = String(bytes: data, encoding: .utf8), text.contains("-----BEGIN") else { return data }
        let body = text.split(whereSeparator: \.isNewline).filter { !$0.hasPrefix("-----") && !$0.contains(":") }.joined()
        return Data(base64Encoded: body, options: .ignoreUnknownCharacters).map(Bytes.init) ?? data
    }

    static func pem(_ der: Bytes, label: String) -> Bytes {
        let b64 = Data(der).base64EncodedString(options: [.lineLength64Characters, .endLineWithLineFeed])
        return Bytes("-----BEGIN \(label)-----\n\(b64)\n-----END \(label)-----\n".utf8)
    }
}

// MARK: - RSA

/// 2048 bit RSA özel anahtarı. Dosyada PKCS#1 DER olarak saklanır.
struct RSAPrivateKey {
    let ref: SecKey

    static func generate(bits: Int = 2048) throws -> RSAPrivateKey {
        let attrs: [CFString: Any] = [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeySizeInBits: bits]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateRandomKey(attrs as CFDictionary, &error) else {
            throw TVKeyError("RSA key generation failed: \(error?.takeRetainedValue().localizedDescription ?? "?")")
        }
        return RSAPrivateKey(ref: key)
    }

    init(ref: SecKey) { self.ref = ref }

    /// PKCS#1 RSAPrivateKey DER'inden.
    init(pkcs1: Bytes) throws {
        let attrs: [CFString: Any] = [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeyClass: kSecAttrKeyClassPrivate]
        guard let key = SecKeyCreateWithData(Data(pkcs1) as CFData, attrs as CFDictionary, nil) else {
            throw TVKeyError("RSA key unreadable")
        }
        ref = key
    }

    /// PKCS#1 ya da PKCS#8 (parolasız) PEM/DER.
    init(pem: Bytes) throws {
        let der = ASN1.unwrapPEM(pem)
        if let key = try? RSAPrivateKey(pkcs1: der) {
            self = key
            return
        }
        // PKCS#8: SEQUENCE { version, algorithm, OCTET STRING { RSAPrivateKey } }
        guard let outer = try ASN1.parse(der).first, outer.items.count >= 3, outer.items[2].tag == 0x04 else {
            throw TVKeyError("unsupported private key format")
        }
        try self.init(pkcs1: outer.items[2].body)
    }

    /// Dosyadan okur; yoksa ya da bozuksa yenisini üretip yazar.
    static func stored(at file: URL) throws -> RSAPrivateKey {
        if let data = try? Data(contentsOf: file), let key = try? RSAPrivateKey(pkcs1: Bytes(data)) { return key }
        let key = try generate()
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(try key.pkcs1()).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return key
    }

    func pkcs1() throws -> Bytes {
        guard let data = SecKeyCopyExternalRepresentation(ref, nil) as Data? else { throw TVKeyError("key export failed") }
        return Bytes(data)
    }

    var publicRef: SecKey { SecKeyCopyPublicKey(ref)! }

    /// PKCS#1 RSAPublicKey: SEQUENCE { n, e }.
    var publicPKCS1: Bytes { (SecKeyCopyExternalRepresentation(publicRef, nil) as Data?).map(Bytes.init) ?? [] }

    /// SubjectPublicKeyInfo (X.509, CSR).
    var subjectPublicKeyInfo: Bytes {
        ASN1.seq(ASN1.seq(ASN1.oid("1.2.840.113549.1.1.1"), ASN1.null), ASN1.bits(publicPKCS1))
    }

    /// Modül ve üs, büyük-endian, baştaki sıfırlar atılmış.
    var modulus: Bytes { publicParts.0 }
    var exponent: Bytes { publicParts.1 }

    private var publicParts: (Bytes, Bytes) {
        guard let seq = try? ASN1.parse(publicPKCS1).first, seq.items.count >= 2 else { return ([], []) }
        return (Array(seq.items[0].body.drop(while: { $0 == 0 })), Array(seq.items[1].body.drop(while: { $0 == 0 })))
    }

    func sign(_ message: Bytes, _ algorithm: SecKeyAlgorithm) throws -> Bytes {
        var error: Unmanaged<CFError>?
        guard let sig = SecKeyCreateSignature(ref, algorithm, Data(message) as CFData, &error) as Data? else {
            throw TVKeyError("signing failed: \(error?.takeRetainedValue().localizedDescription ?? "?")")
        }
        return Bytes(sig)
    }
}

/// RSA açık anahtarıyla imza denetimi (testler ve SSH sunucu anahtarı).
enum RSAVerify {
    static func publicKey(pkcs1: Bytes) -> SecKey? {
        let attrs: [CFString: Any] = [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeyClass: kSecAttrKeyClassPublic]
        return SecKeyCreateWithData(Data(pkcs1) as CFData, attrs as CFDictionary, nil)
    }

    static func check(_ key: SecKey, _ algorithm: SecKeyAlgorithm, message: Bytes, signature: Bytes) -> Bool {
        SecKeyVerifySignature(key, algorithm, Data(message) as CFData, Data(signature) as CFData, nil)
    }
}

// MARK: - Sertifika

/// X.509 sertifikası ve Security'nin vermediği geçerlilik tarihleri.
struct TVCertificate {
    let der: Bytes
    let ref: SecCertificate
    let notBefore: Date
    let notAfter: Date

    init(_ data: Bytes) throws {
        let der = ASN1.unwrapPEM(data)
        guard let ref = SecCertificateCreateWithData(nil, Data(der) as CFData) else { throw TVKeyError("not a certificate") }
        guard let cert = try ASN1.parse(der).first, var tbs = cert.items.first?.items else {
            throw TVKeyError("certificate malformed")
        }
        if tbs.first?.tag == 0xA0 { tbs.removeFirst() }
        // serialNumber, signature, issuer, validity …
        guard tbs.count > 3 else { throw TVKeyError("certificate malformed") }
        let validity = tbs[3].items
        guard validity.count == 2, let start = Self.date(validity[0]), let end = Self.date(validity[1]) else {
            throw TVKeyError("certificate dates unreadable")
        }
        self.der = der
        self.ref = ref
        notBefore = start
        notAfter = end
    }

    private static func date(_ item: ASN1.Item) -> Date? {
        guard let text = String(bytes: item.body, encoding: .ascii) else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = item.tag == 0x17 ? "yyMMddHHmmss'Z'" : "yyyyMMddHHmmss'Z'"
        return f.date(from: text)
    }

    var issuerName: Data? { SecCertificateCopyNormalizedIssuerSequence(ref) as Data? }
    var subjectName: Data? { SecCertificateCopyNormalizedSubjectSequence(ref) as Data? }
    var summary: String { (SecCertificateCopySubjectSummary(ref) as String?) ?? "?" }

    /// Kendinden imzalı sertifika (adb'nin TLS kimliği için).
    static func selfSigned(_ key: RSAPrivateKey, name: String = "nino") throws -> Bytes {
        let subject = ASN1.seq(ASN1.set(ASN1.seq(ASN1.oid("2.5.4.3"), ASN1.utf8(name))))
        let sha256RSA = ASN1.seq(ASN1.oid("1.2.840.113549.1.1.11"), ASN1.null)
        let now = Date()
        let serial = Bytes.random(8).enumerated().map { $0.offset == 0 ? $0.element & 0x7F | 0x01 : $0.element }
        // Uzantılar: anahtar kullanımı (dijital imza, anahtar şifreleme, sertifika imzalama) ve temel kısıt.
        let keyUsage = ASN1.seq(ASN1.oid("2.5.29.15"), ASN1.bool(true), ASN1.octets(ASN1.node(0x03, [0x02, 0xA4])))
        let basic = ASN1.seq(ASN1.oid("2.5.29.19"), ASN1.bool(true), ASN1.octets(ASN1.seq(ASN1.bool(true))))
        let tbs = ASN1.seq(
            ASN1.node(0xA0, ASN1.small(2)),
            ASN1.unsigned(serial),
            sha256RSA,
            subject,
            ASN1.seq(ASN1.utcTime(now.addingTimeInterval(-2 * 86_400)), ASN1.utcTime(now.addingTimeInterval(20 * 365 * 86_400))),
            subject,
            key.subjectPublicKeyInfo,
            ASN1.node(0xA3, ASN1.seq(basic, keyUsage))
        )
        let signature = try key.sign(tbs, .rsaSignatureMessagePKCS1v15SHA256)
        return ASN1.seq(tbs, sha256RSA, ASN1.bits(signature))
    }
}

// MARK: - TLS istemci kimliği

/// iOS'ta anahtar ve sertifikadan `SecIdentity` ancak Anahtar Zinciri üzerinden kurulur: ikisi de eklenir, kimlik
/// sertifikanın baytlarıyla bulunur.
enum TLSClientIdentity {
    static func make(key: RSAPrivateKey, certificateFile: URL) throws -> SecIdentity {
        var der: Bytes
        if let saved = try? Data(contentsOf: certificateFile), SecCertificateCreateWithData(nil, saved as CFData) != nil {
            der = Bytes(saved)
        } else {
            der = try TVCertificate.selfSigned(key)
            try? Data(der).write(to: certificateFile, options: .atomic)
        }
        // Kayıtlı sertifika başka bir anahtarın olabilir (anahtar dosyası yenilendiyse): açık anahtarlar karşılaştırılır.
        if let cert = SecCertificateCreateWithData(nil, Data(der) as CFData), let pub = SecCertificateCopyKey(cert),
           (SecKeyCopyExternalRepresentation(pub, nil) as Data?).map(Bytes.init) != key.publicPKCS1 {
            der = try TVCertificate.selfSigned(key)
            try? Data(der).write(to: certificateFile, options: .atomic)
        }
        guard let certificate = SecCertificateCreateWithData(nil, Data(der) as CFData) else {
            throw TVKeyError("certificate could not be created")
        }
        let tag = Data("com.ninotranslator.tvinstall.\(certificateFile.deletingPathExtension().lastPathComponent)".utf8)
        let addKey: [CFString: Any] = [
            kSecClass: kSecClassKey, kSecValueRef: key.ref, kSecAttrApplicationTag: tag,
            kSecAttrLabel: "Nino TV install", kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let keyStatus = SecItemAdd(addKey as CFDictionary, nil)
        guard keyStatus == errSecSuccess || keyStatus == errSecDuplicateItem else {
            throw TVKeyError("keychain refused the key (\(keyStatus))")
        }
        let addCert: [CFString: Any] = [kSecClass: kSecClassCertificate, kSecValueRef: certificate,
                                        kSecAttrLabel: "Nino TV install"]
        let certStatus = SecItemAdd(addCert as CFDictionary, nil)
        guard certStatus == errSecSuccess || certStatus == errSecDuplicateItem else {
            throw TVKeyError("keychain refused the certificate (\(certStatus))")
        }
        let find: [CFString: Any] = [kSecClass: kSecClassIdentity, kSecReturnRef: true, kSecMatchLimit: kSecMatchLimitAll]
        var found: CFTypeRef?
        guard SecItemCopyMatching(find as CFDictionary, &found) == errSecSuccess, let all = found as? [SecIdentity] else {
            throw TVKeyError("TLS identity not found")
        }
        for identity in all {
            var cert: SecCertificate?
            if SecIdentityCopyCertificate(identity, &cert) == errSecSuccess, let cert,
               Bytes(SecCertificateCopyData(cert) as Data) == der {
                return identity
            }
        }
        throw TVKeyError("TLS identity not found")
    }
}
