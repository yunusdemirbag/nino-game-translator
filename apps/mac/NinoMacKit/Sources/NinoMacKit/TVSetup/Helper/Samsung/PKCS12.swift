// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import CommonCrypto
import CryptoKit
import Foundation
import Security

/// PKCS#12 (RFC 7292) yazıcı ve okuyucu. Anahtarlığa hiç dokunmaz (`SecPKCS12Import` macOS'ta öğeleri kullanıcının
/// anahtar zincirine koyabiliyor). Yazılan biçim (§9.7): anahtar ve sertifikalar pbeWithSHAAnd3-KeyTripleDES-CBC,
/// SHA-1, 2048 tur; HMAC-SHA1 MAC. Okurken 3DES (3 ve 2 anahtar), RC2-40/128, PBES2 (PBKDF2 + AES-CBC) ve
/// şifresiz güvenli içerik kabul edilir.
public enum PKCS12 {
    public struct Contents {
        /// PKCS#1 RSAPrivateKey DER.
        public var privateKey: Data
        /// Yaprak önce, sonra ötekiler (dosyadaki sırayla).
        public var certificates: [Data]
    }

    public enum Failure: Error, Equatable {
        case malformed(String)
        case badPassword
        case unsupported(String)
        case crypto(String)
    }

    static let iterations = 2048
    static let oidData = "1.2.840.113549.1.7.1"
    static let oidEncryptedData = "1.2.840.113549.1.7.6"
    static let oidShroudedKeyBag = "1.2.840.113549.1.12.10.1.2"
    static let oidKeyBag = "1.2.840.113549.1.12.10.1.1"
    static let oidCertBag = "1.2.840.113549.1.12.10.1.3"
    static let oidX509 = "1.2.840.113549.1.9.22.1"
    static let oidLocalKeyID = "1.2.840.113549.1.9.21"
    static let oidFriendlyName = "1.2.840.113549.1.9.20"
    static let oidSHA1 = "1.3.14.3.2.26"
    static let oidSHA256 = "2.16.840.1.101.3.4.2.1"
    static let pbe3DES = "1.2.840.113549.1.12.1.3"
    static let pbe2DES = "1.2.840.113549.1.12.1.4"
    static let pbeRC2_128 = "1.2.840.113549.1.12.1.5"
    static let pbeRC2_40 = "1.2.840.113549.1.12.1.6"
    static let pbes2 = "1.2.840.113549.1.5.13"
    static let pbkdf2 = "1.2.840.113549.1.5.12"

    // MARK: Yazma

    /// `certificates[0]` yaprak; anahtar PKCS#1 DER.
    public static func build(privateKeyPKCS1: Data, certificates: [Data], password: String,
                             friendlyName: String? = nil) throws -> Data {
        let keyID = Data(Insecure.SHA1.hash(data: certificates.first ?? Data()))
        var attrs = DER.sequence(DER.oid(oidLocalKeyID), DER.set(DER.octets(keyID)))
        if let friendlyName { attrs += DER.sequence(DER.oid(oidFriendlyName), DER.set(DER.bmp(friendlyName))) }
        let bagAttrs = DER.set(attrs)

        // Sertifikalar: şifreli içerik (encryptedData).
        var certBags: [Data] = []
        for (i, c) in certificates.enumerated() {
            let bag = DER.sequence(DER.oid(oidX509), DER.explicit(0, DER.octets(c)))
            var safeBag = DER.oid(oidCertBag) + DER.explicit(0, bag)
            if i == 0 { safeBag += bagAttrs }
            certBags.append(DER.sequence(safeBag))
        }
        let certSalt = random(8)
        let encryptedCerts = try pbe3DES(encrypt: true, DER.sequence(certBags), password: password, salt: certSalt,
                                         iterations: iterations)
        let certAlg = DER.sequence(DER.oid(pbe3DES), DER.sequence(DER.octets(certSalt), DER.integer(iterations)))
        let encryptedData = DER.sequence(DER.integer(0),
                                         DER.sequence(DER.oid(oidData), certAlg, DER.tlv(0x80, encryptedCerts)))
        let certInfo = DER.sequence(DER.oid(oidEncryptedData), DER.explicit(0, encryptedData))

        // Anahtar: düz içerikte pkcs8ShroudedKeyBag.
        let keySalt = random(8)
        let pkcs8 = ASN1.wrapPKCS8(privateKeyPKCS1)
        let encryptedKey = try pbe3DES(encrypt: true, pkcs8, password: password, salt: keySalt, iterations: iterations)
        let keyAlg = DER.sequence(DER.oid(pbe3DES), DER.sequence(DER.octets(keySalt), DER.integer(iterations)))
        let shrouded = DER.sequence(keyAlg, DER.octets(encryptedKey))
        let keyBag = DER.sequence(DER.oid(oidShroudedKeyBag) + DER.explicit(0, shrouded) + bagAttrs)
        let keyInfo = DER.sequence(DER.oid(oidData), DER.explicit(0, DER.octets(DER.sequence(keyBag))))

        let authSafe = DER.sequence(certInfo, keyInfo)
        let macSalt = random(8)
        let macKey = derive(password: password, salt: macSalt, id: 3, iterations: iterations, length: 20, hash: .sha1)
        let mac = Data(HMAC<Insecure.SHA1>.authenticationCode(for: authSafe, using: SymmetricKey(data: macKey)))
        let macData = DER.sequence(DER.sequence(DER.algorithm(oidSHA1), DER.octets(mac)), DER.octets(macSalt),
                                   DER.integer(iterations))
        return DER.sequence(DER.integer(3), DER.sequence(DER.oid(oidData), DER.explicit(0, DER.octets(authSafe))), macData)
    }

    // MARK: Okuma

    public static func parse(_ data: Data, password: String) throws -> Contents {
        guard let pfx = try? DER.parse(data), pfx.tag == 0x30 else { throw Failure.malformed("PFX") }
        let top = pfx.children
        guard top.count >= 2, let authInfo = top[1].children.first?.oidText, authInfo == oidData,
              let wrapped = top[1].children.dropFirst().first, let inner = wrapped.children.first else {
            throw Failure.malformed("authSafe")
        }
        let authSafe = octetContent(inner)
        if top.count >= 3 { try verifyMAC(top[2], authSafe: authSafe, password: password) }

        guard let safes = try? DER.parse(authSafe) else { throw Failure.malformed("AuthenticatedSafe") }
        var key: Data?
        var certs: [(Data, Data?)] = []
        var keyID: Data?
        for ci in safes.children {
            let parts = ci.children
            guard let type = parts.first?.oidText, parts.count >= 2, let body = parts[1].children.first else { continue }
            let bagsDER: Data
            if type == oidData {
                bagsDER = octetContent(body)
            } else if type == oidEncryptedData {
                let ed = body.children
                guard ed.count >= 2 else { throw Failure.malformed("EncryptedData") }
                let eci = ed[1].children
                guard eci.count >= 3 else { throw Failure.malformed("EncryptedContentInfo") }
                let cipher = eci[2].tag == 0xa0 ? octetContent(eci[2]) : eci[2].content
                bagsDER = try decrypt(algorithm: eci[1], cipher, password: password)
            } else { continue }
            guard let bags = try? DER.parse(bagsDER) else { throw Failure.badPassword }
            for bag in bags.children {
                let f = bag.children
                guard let bagType = f.first?.oidText, f.count >= 2, let value = f[1].children.first else { continue }
                let localID = f.count >= 3 ? localKeyID(f[2]) : nil
                switch bagType {
                case oidShroudedKeyBag:
                    let p = value.children
                    guard p.count == 2 else { throw Failure.malformed("ShroudedKeyBag") }
                    let plain = try decrypt(algorithm: p[0], p[1].content, password: password)
                    guard let k = ASN1.pkcs8PrivateKey(plain) else { throw Failure.badPassword }
                    key = k; keyID = localID
                case oidKeyBag:
                    if let k = ASN1.pkcs8PrivateKey(value.raw) { key = k; keyID = localID }
                case oidCertBag:
                    let cb = value.children
                    guard cb.count == 2, cb[0].oidText == oidX509, let oct = cb[1].children.first else { continue }
                    certs.append((oct.content, localID))
                default: continue
                }
            }
        }
        guard let key else { throw Failure.malformed("no private key") }
        guard !certs.isEmpty else { throw Failure.malformed("no certificate") }
        // Yaprak: anahtar kimliği eşleşen; yoksa açık anahtarı özel anahtarınkiyle aynı olan sertifika.
        var ordered = certs.map(\.0)
        let leafIndex = keyID.flatMap { id in certs.firstIndex { $0.1 == id } }
            ?? ordered.firstIndex { matches(certificate: $0, privateKey: key) }
        if let i = leafIndex {
            let leaf = ordered.remove(at: i)
            ordered.insert(leaf, at: 0)
        }
        return Contents(privateKey: key, certificates: ordered)
    }

    /// Sertifikanın RSA modülü özel anahtarınkiyle aynı mı.
    static func matches(certificate: Data, privateKey pkcs1: Data) -> Bool {
        guard let cert = SecCertificateCreateWithData(nil, certificate as CFData), let pub = SecCertificateCopyKey(cert),
              let der = SecKeyCopyExternalRepresentation(pub, nil) as Data?,
              let (modulus, _) = ASN1.rsaPublicKey(der),
              let key = try? DER.parse(pkcs1), key.children.count > 2 else { return false }
        let strip: (Data) -> Data = { Data($0.drop { $0 == 0 }) }
        return strip(key.children[1].content) == strip(modulus)
    }

    static func octetContent(_ n: DER.Node) -> Data {
        // Belirsiz uzunluklu (BER) yapılı OCTET STRING desteklenmez; DER bekleriz.
        if n.tag == 0x24 { return n.children.map(\.content).reduce(Data(), +) }
        return n.content
    }

    static func localKeyID(_ attrs: DER.Node) -> Data? {
        for a in attrs.children {
            let c = a.children
            if c.count == 2, c[0].oidText == oidLocalKeyID { return c[1].children.first?.content }
        }
        return nil
    }

    static func verifyMAC(_ macData: DER.Node, authSafe: Data, password: String) throws {
        let m = macData.children
        guard m.count >= 2, let digestInfo = m.first?.children, digestInfo.count == 2,
              let alg = digestInfo[0].children.first?.oidText else { throw Failure.malformed("MacData") }
        let expected = digestInfo[1].content
        let salt = m[1].content
        let iter = m.count >= 3 ? (m[2].intValue ?? 1) : 1
        let actual: Data
        switch alg {
        case oidSHA1:
            let k = derive(password: password, salt: salt, id: 3, iterations: iter, length: 20, hash: .sha1)
            actual = Data(HMAC<Insecure.SHA1>.authenticationCode(for: authSafe, using: SymmetricKey(data: k)))
        case oidSHA256:
            let k = derive(password: password, salt: salt, id: 3, iterations: iter, length: 32, hash: .sha256)
            actual = Data(HMAC<SHA256>.authenticationCode(for: authSafe, using: SymmetricKey(data: k)))
        default:
            throw Failure.unsupported("MAC \(alg)")
        }
        guard actual == expected else { throw Failure.badPassword }
    }

    static func decrypt(algorithm: DER.Node, _ cipher: Data, password: String) throws -> Data {
        let a = algorithm.children
        guard let oid = a.first?.oidText else { throw Failure.malformed("AlgorithmIdentifier") }
        if oid == pbes2 { return try decryptPBES2(a.count > 1 ? a[1] : nil, cipher, password: password) }
        guard a.count == 2 else { throw Failure.malformed("PBE params") }
        let params = a[1].children
        guard params.count == 2, let iter = params[1].intValue else { throw Failure.malformed("PBE params") }
        let salt = params[0].content
        switch oid {
        case pbe3DES: return try pbe3DES(encrypt: false, cipher, password: password, salt: salt, iterations: iter)
        case pbe2DES:
            let k = derive(password: password, salt: salt, id: 1, iterations: iter, length: 16, hash: .sha1)
            let iv = derive(password: password, salt: salt, id: 2, iterations: iter, length: 8, hash: .sha1)
            return try cbc(CCAlgorithm(kCCAlgorithm3DES), false, cipher, key: k + k.prefix(8), iv: iv)
        case pbeRC2_40, pbeRC2_128:
            let len = oid == pbeRC2_40 ? 5 : 16
            let k = derive(password: password, salt: salt, id: 1, iterations: iter, length: len, hash: .sha1)
            let iv = derive(password: password, salt: salt, id: 2, iterations: iter, length: 8, hash: .sha1)
            return try cbc(CCAlgorithm(kCCAlgorithmRC2), false, cipher, key: k, iv: iv)
        default:
            throw Failure.unsupported(oid)
        }
    }

    /// PBES2: PBKDF2 (HMAC-SHA1/SHA-256) + AES-CBC. Parola UTF-8 (BMP değil).
    static func decryptPBES2(_ params: DER.Node?, _ cipher: Data, password: String) throws -> Data {
        guard let p = params?.children, p.count == 2 else { throw Failure.malformed("PBES2") }
        let kdf = p[0].children, enc = p[1].children
        guard kdf.first?.oidText == pbkdf2, kdf.count == 2, enc.count == 2, let encOID = enc[0].oidText else {
            throw Failure.unsupported("PBES2 kdf")
        }
        let kp = kdf[1].children
        guard kp.count >= 2, let iter = kp[1].intValue else { throw Failure.malformed("PBKDF2") }
        let salt = kp[0].content
        var prf = CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1)
        if let last = kp.last, last.tag == 0x30, let prfOID = last.children.first?.oidText {
            switch prfOID {
            case "1.2.840.113549.2.9": prf = CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256)
            case "1.2.840.113549.2.7": prf = CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1)
            default: throw Failure.unsupported("PRF \(prfOID)")
            }
        }
        let keyLength: Int
        switch encOID {
        case "2.16.840.1.101.3.4.1.2": keyLength = 16
        case "2.16.840.1.101.3.4.1.22": keyLength = 24
        case "2.16.840.1.101.3.4.1.42": keyLength = 32
        default: throw Failure.unsupported("cipher \(encOID)")
        }
        let iv = enc[1].content
        var key = Data(count: keyLength)
        let pw = Array(password.utf8)
        let status = key.withUnsafeMutableBytes { k in
            salt.withUnsafeBytes { s in
                CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), pw.map { Int8(bitPattern: $0) }, pw.count,
                                     s.bindMemory(to: UInt8.self).baseAddress, salt.count, prf, UInt32(iter),
                                     k.bindMemory(to: UInt8.self).baseAddress, keyLength)
            }
        }
        guard status == kCCSuccess else { throw Failure.crypto("PBKDF2 \(status)") }
        return try cbc(CCAlgorithm(kCCAlgorithmAES), false, cipher, key: key, iv: iv)
    }

    static func pbe3DES(encrypt: Bool, _ data: Data, password: String, salt: Data, iterations: Int) throws -> Data {
        let key = derive(password: password, salt: salt, id: 1, iterations: iterations, length: 24, hash: .sha1)
        let iv = derive(password: password, salt: salt, id: 2, iterations: iterations, length: 8, hash: .sha1)
        return try cbc(CCAlgorithm(kCCAlgorithm3DES), encrypt, data, key: key, iv: iv)
    }

    static func cbc(_ alg: CCAlgorithm, _ encrypt: Bool, _ data: Data, key: Data, iv: Data) throws -> Data {
        var out = Data(count: data.count + 32)
        var moved = 0
        let outCount = out.count
        let status = out.withUnsafeMutableBytes { o in
            data.withUnsafeBytes { d in
                key.withUnsafeBytes { k in
                    iv.withUnsafeBytes { v in
                        CCCrypt(CCOperation(encrypt ? kCCEncrypt : kCCDecrypt), alg, CCOptions(kCCOptionPKCS7Padding),
                                k.baseAddress, key.count, v.baseAddress, d.baseAddress, data.count,
                                o.baseAddress, outCount, &moved)
                    }
                }
            }
        }
        guard status == kCCSuccess else {
            if !encrypt, status == kCCDecodeError || status == kCCAlignmentError { throw Failure.badPassword }
            throw Failure.crypto("CCCrypt \(status)")
        }
        return out.prefix(moved)
    }

    // MARK: PKCS#12 anahtar türetme (RFC 7292 Ek B)

    enum KDFHash { case sha1, sha256 }

    static func bmpPassword(_ password: String) -> Data {
        var d = Data()
        for u in password.utf16 { d.append(UInt8(u >> 8)); d.append(UInt8(u & 0xff)) }
        d.append(contentsOf: [0, 0])
        return d
    }

    static func derive(password: String, salt: Data, id: UInt8, iterations: Int, length: Int, hash: KDFHash) -> Data {
        let u = hash == .sha1 ? 20 : 32
        let v = 64
        let pw = bmpPassword(password)
        func fill(_ s: Data) -> Data {
            guard !s.isEmpty else { return Data() }
            let n = v * ((s.count + v - 1) / v)
            var out = Data(capacity: n)
            while out.count < n { out.append(s.prefix(n - out.count)) }
            return out
        }
        let d = Data(repeating: id, count: v)
        var i = fill(salt) + fill(pw)
        var result = Data()
        func h(_ x: Data) -> Data {
            hash == .sha1 ? Data(Insecure.SHA1.hash(data: x)) : Data(SHA256.hash(data: x))
        }
        while result.count < length {
            var a = h(d + i)
            for _ in 1..<max(1, iterations) { a = h(a) }
            result.append(a)
            guard result.count < length else { break }
            // B = A'nın v bayta tekrarı; I'nın her v'lik bloğuna B + 1 eklenir.
            let b = fill(a)
            var newI = Data(capacity: i.count)
            var offset = 0
            while offset < i.count {
                var block = [UInt8](i[(i.startIndex + offset)..<(i.startIndex + offset + v)])
                var carry: UInt16 = 1
                for j in stride(from: v - 1, through: 0, by: -1) {
                    let sum = UInt16(block[j]) + UInt16(b[b.startIndex + j]) + carry
                    block[j] = UInt8(sum & 0xff)
                    carry = sum >> 8
                }
                newI.append(contentsOf: block)
                offset += v
            }
            i = newI
        }
        _ = u
        return result.prefix(length)
    }

    static func random(_ n: Int) -> Data {
        var d = Data(count: n)
        _ = d.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, n, $0.baseAddress!) }
        return d
    }
}
