// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import CryptoKit
import XCTest
@testable import Nino

/// TV kurulumunun şifreleme parçaları: büyük sayı, edwards25519, SPAKE2, adb anahtar biçimi, eşleme şifresi.
final class TVCryptoTests: XCTestCase {
    static func fixture(_ name: String, _ ext: String) throws -> Data {
        let url = try XCTUnwrap(Bundle(for: TVCryptoTests.self).url(forResource: name, withExtension: ext))
        return try Data(contentsOf: url)
    }

    func testBigNumArithmetic() {
        let m = (BigNum(1) << 127) - BigNum(1)
        let e = (BigNum(1) << 100) + BigNum(7)
        // Python: pow(3, 2**100+7, 2**127-1)
        XCTAssertEqual(BigNum(3).power(e, modulus: m), BigNum(decimal: "35918501684820074657246006075159498392"))
        // 2048 bitlik tek modül (SSH'nin DH gruplarıyla aynı boy)
        let big = (BigNum(1) << 2048) - BigNum(1_942_289)
        let r = BigNum(5).power((BigNum(1) << 300) + BigNum(12_345), modulus: big)
        XCTAssertEqual(r.bigEndian(count: 256).hexString,
                       "b54879a2bd4f5a963bfd5663bab27d4a133604ce9bb45bf890563a8244da6200d08c81fdcbc2417e89ab76235d8995f4fe13802a5d902b293298f889509fe4ff83957d19dae47d1459ea0739dbb6965dd2d5bd38b1654417a7b93da8f633e4df1f4aa224da4f759a24ee415613550686cb11c67799893b9e5e61a1f6fd5d30bb564ae255e34a11ce8c0a28feaa71dde0b8954c98a13b44e573cbff02f59cf9135a827026e3bd053219fa3ad8d81e69380ccadec6bbcd0396eaf59571eb8b5e49076d9b51c8613e05f765f3c9645450f0126947dc31a18aab33980d6315e50ca76140bf9a00e94bc0b9099ecf7cc1abaa2128f2871fc034e849c12bf1e44ce3a2")
        XCTAssertEqual((BigNum(1_000_003) * BigNum(999_983)) % BigNum(1_000_003), BigNum())
    }

    func testEdwardsBasePointAndOrder() {
        XCTAssertEqual(EdwardsPoint.base.encoded.hexString,
                       "5866666666666666666666666666666666666666666666666666666666666666")
        XCTAssertTrue(EdwardsPoint.base.times(EdwardsPoint.order).isIdentity)
        // M ve N asal mertebeli alt grupta değil; mertebeleri 8·l'yi böler (parola skalerinin alt üç biti bu yüzden sıfır).
        XCTAssertFalse(Spake2.m.times(EdwardsPoint.order).isIdentity)
        XCTAssertTrue(Spake2.m.times(EdwardsPoint.order).times([8]).isIdentity)
        XCTAssertTrue(Spake2.n.times(EdwardsPoint.order).times([8]).isIdentity)
        // 2B = B + B
        XCTAssertEqual(EdwardsPoint.base.times([2]).encoded, EdwardsPoint.base.adding(.base).encoded)
        XCTAssertNil(EdwardsPoint(encoded: Bytes(repeating: 0xFF, count: 32)))
    }

    /// Önceki uygulamanın (gerçek TV'lerde çalışan) çıktısıyla aynı mesajlar ve anahtar.
    func testSpake2MatchesKnownVector() throws {
        let password = Bytes("123456".utf8) + Bytes(repeating: 0x11, count: 64)
        let alice = Spake2(role: .alice, password: password, seed: (0..<64).map { UInt8($0) })
        let bob = Spake2(role: .bob, password: password, seed: (64..<128).map { UInt8($0) })
        XCTAssertEqual(alice.message.hexString, "18110a8f686063bd892389f4121ef62798e6d2d84ae1e542f899448348c47daf")
        XCTAssertEqual(bob.message.hexString, "83c403369f97373154e8c286eafc09f94a959da8f5022cb03f439c61e254700a")
        let key = try XCTUnwrap(alice.finish(bob.message))
        XCTAssertEqual(key.hexString, "8cd235a3c5b751056c5a5116ace058476a8284444b50cba7973379c6fe577be23a788511f76b23ce9915cf4e82456f442f357667d10e922bc5d225ac02d0b329")
        XCTAssertEqual(bob.finish(alice.message), key)
    }

    func testSpake2WrongPasswordDisagrees() throws {
        let alice = Spake2(role: .alice, password: Bytes("111111".utf8))
        let bob = Spake2(role: .bob, password: Bytes("222222".utf8))
        XCTAssertNotEqual(try XCTUnwrap(alice.finish(bob.message)), try XCTUnwrap(bob.finish(alice.message)))
        XCTAssertNil(alice.finish(Bytes(repeating: 0xFF, count: 32)))
    }

    /// adb'nin kendi `adb keygen` çıktısıyla aynı açık anahtar.
    func testAndroidPublicKeyMatchesAdbKeygen() throws {
        let key = try RSAPrivateKey(pem: Bytes(try Self.fixture("adbkey", "pem")))
        let identity = AdbIdentity(key: key, certificateFile: TVTestFiles.scratch().appendingPathComponent("c.cer"))
        let expected = String(decoding: try Self.fixture("adbkey.pub", "b64"), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(Data(identity.androidPublicKey).base64EncodedString(), expected)
        XCTAssertTrue(identity.publicKeyLine.hasSuffix(" nino@iphone"))
    }

    func testAdbTokenSignatureVerifies() throws {
        let identity = AdbIdentity(key: try RSAPrivateKey.generate(), certificateFile: TVTestFiles.scratch().appendingPathComponent("c.cer"))
        let token = Bytes.random(20)
        let pub = try XCTUnwrap(RSAVerify.publicKey(pkcs1: identity.key.publicPKCS1))
        XCTAssertTrue(RSAVerify.check(pub, .rsaSignatureDigestPKCS1v15SHA1, message: token, signature: try identity.signAdbToken(token)))
        XCTAssertTrue(RSAVerify.check(pub, .rsaSignatureMessagePKCS1v15SHA1, message: token, signature: try identity.signSdbToken(token)))
    }

    func testPairingCipherRoundTripAndCounters() throws {
        let material = Bytes(repeating: 7, count: 64)
        var phone = AdbPairing.PairingCipher(keyMaterial: material)
        var tv = AdbPairing.PairingCipher(keyMaterial: material)
        let first = try phone.seal(AdbPairing.peerInfoBlock("abc nino@iphone"))
        let second = try phone.seal([1, 2, 3])
        XCTAssertEqual(first.count, 8192 + 16)
        XCTAssertEqual(tv.open(first)?.prefix(4), [0] + Bytes("abc".utf8))
        XCTAssertEqual(tv.open(second), [1, 2, 3])
        // Sıra bozulursa açılmaz (nonce sayacı).
        var other = AdbPairing.PairingCipher(keyMaterial: material)
        XCTAssertNil(other.open(second))
        XCTAssertEqual(AdbPairing.frame(1, [9, 9]), [1, 1, 0, 0, 0, 2, 9, 9])
    }

    func testDERRoundTripAndSelfSignedCertificate() throws {
        let key = try RSAPrivateKey.generate()
        let der = try TVCertificate.selfSigned(key)
        let cert = try TVCertificate(der)
        XCTAssertLessThan(cert.notBefore, Date())
        XCTAssertGreaterThan(cert.notAfter, Date().addingTimeInterval(365 * 86_400))
        XCTAssertEqual(ASN1.oid("1.2.840.113549.1.1.11"), [0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x0B])
        let long = ASN1.octets(Bytes(repeating: 1, count: 300))
        XCTAssertEqual(Array(long.prefix(4)), [0x04, 0x82, 0x01, 0x2C])
        XCTAssertEqual(try ASN1.parse(long).first?.body.count, 300)
        let pemKey = try RSAPrivateKey(pem: ASN1.pem(try key.pkcs1(), label: "RSA PRIVATE KEY"))
        XCTAssertEqual(pemKey.publicPKCS1, key.publicPKCS1)
    }

    func testVersionOrder() {
        XCTAssertTrue(VersionOrder.isNewer("0.10.0", than: "0.9.9"))
        XCTAssertTrue(VersionOrder.isNewer("4.0.4", than: "4.0.3"))
        XCTAssertFalse(VersionOrder.isNewer("4.0.3", than: "4.0.3"))
        XCTAssertFalse(VersionOrder.isNewer("4.0", than: "4.0.0"))
    }
}

extension BigNum {
    init(decimal: String) {
        var v = BigNum()
        for c in decimal { v = v * BigNum(10) + BigNum(UInt64(c.wholeNumberValue ?? 0)) }
        self = v
    }
}
