// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import CryptoKit
import Foundation

// Android'in kablosuz hata ayıklama eşlemesindeki SPAKE2 (BoringSSL'in edwards25519 üzerindeki SPAKE2'si ile aynı
// mesaj ve anahtar). Hız gerekmez: eşleme başına birkaç skaler çarpım.

/// 2^255 − 19 cismi: 16 adet 16 bitlik parça (Int64; toplama ve çıkarmada taşma geçici olarak serbest).
struct Field25519: Equatable {
    var limb: [Int64]

    init(_ limbs: [Int64]) { limb = limbs }
    init(small v: Int64) {
        limb = [Int64](repeating: 0, count: 16)
        limb[0] = v
    }

    static let zero = Field25519(small: 0)
    static let one = Field25519(small: 1)

    /// Küçük-endian 32 bayttan (üst bit yok sayılır).
    init(bytes: Bytes) {
        limb = (0..<16).map { Int64(bytes[2 * $0]) | Int64(bytes[2 * $0 + 1]) << 8 }
        limb[15] &= 0x7FFF
    }

    private static func carry(_ o: inout [Int64]) {
        for i in 0..<16 {
            let c = o[i] >> 16
            o[i] -= c << 16
            if i < 15 { o[i + 1] += c } else { o[0] += 38 * c }
        }
    }

    static func + (a: Field25519, b: Field25519) -> Field25519 { Field25519((0..<16).map { a.limb[$0] + b.limb[$0] }) }
    static func - (a: Field25519, b: Field25519) -> Field25519 { Field25519((0..<16).map { a.limb[$0] - b.limb[$0] }) }

    static func * (a: Field25519, b: Field25519) -> Field25519 {
        var t = [Int64](repeating: 0, count: 31)
        for i in 0..<16 {
            let x = a.limb[i]
            for j in 0..<16 { t[i + j] += x * b.limb[j] }
        }
        // 2^256 ≡ 38 (mod p)
        for i in 0..<15 { t[i] += 38 * t[i + 16] }
        var o = Array(t[0..<16])
        carry(&o)
        carry(&o)
        return Field25519(o)
    }

    var squared: Field25519 { self * self }

    /// self ^ e (e küçük-endian bayt).
    func power(_ exponent: Bytes) -> Field25519 {
        var result = Field25519.one
        for i in stride(from: exponent.count * 8 - 1, through: 0, by: -1) {
            result = result.squared
            if (exponent[i / 8] >> UInt8(i % 8)) & 1 == 1 { result = result * self }
        }
        return result
    }

    var inverse: Field25519 { power(Field25519.pMinus2) }

    /// Kanonik 32 bayt (küçük-endian).
    var bytes: Bytes {
        var t = limb
        Field25519.carry(&t)
        Field25519.carry(&t)
        Field25519.carry(&t)
        for _ in 0..<2 {
            var m = [Int64](repeating: 0, count: 16)
            m[0] = t[0] - 0xFFED
            for i in 1..<15 {
                m[i] = t[i] - 0xFFFF - ((m[i - 1] >> 16) & 1)
                m[i - 1] &= 0xFFFF
            }
            m[15] = t[15] - 0x7FFF - ((m[14] >> 16) & 1)
            let borrow = (m[15] >> 16) & 1
            m[14] &= 0xFFFF
            if borrow == 0 { t = m }
        }
        var out = Bytes(repeating: 0, count: 32)
        for i in 0..<16 {
            out[2 * i] = UInt8(truncatingIfNeeded: t[i])
            out[2 * i + 1] = UInt8(truncatingIfNeeded: t[i] >> 8)
        }
        return out
    }

    var isNegative: Bool { bytes[0] & 1 == 1 }
    var isZero: Bool { bytes.allSatisfy { $0 == 0 } }
    static func == (a: Field25519, b: Field25519) -> Bool { a.bytes == b.bytes }

    // Sabit üsler (küçük-endian): p − 2, (p + 3) / 8, (p − 1) / 4.
    static let pMinus2: Bytes = [0xEB] + Bytes(repeating: 0xFF, count: 30) + [0x7F]
    static let pPlus3Over8: Bytes = [0xFE] + Bytes(repeating: 0xFF, count: 30) + [0x0F]
    static let pMinus1Over4: Bytes = [0xFB] + Bytes(repeating: 0xFF, count: 30) + [0x1F]
}

/// edwards25519 noktası, genişletilmiş koordinatlar (X:Y:Z:T), x = X/Z, y = Y/Z, xy = T/Z.
struct EdwardsPoint {
    typealias F = Field25519
    var x: F, y: F, z: F, t: F

    static let d: F = (F.zero - F(small: 121_665)) * F(small: 121_666).inverse
    static let d2: F = d + d
    static let sqrtMinusOne: F = F(small: 2).power(F.pMinus1Over4)
    static let identity = EdwardsPoint(x: .zero, y: .one, z: .one, t: .zero)

    /// Taban noktası (y = 4/5, x çift).
    static let base: EdwardsPoint = {
        let y = F(small: 4) * F(small: 5).inverse
        var encoded = y.bytes
        encoded[31] &= 0x7F
        return EdwardsPoint(encoded: encoded)!
    }()

    /// Grup mertebesi l = 2^252 + 27742317777372353535851937790883648493 (küçük-endian).
    static let order: Bytes = Bytes(hex: "edd3f55c1a631258d69cf7a2def9de1400000000000000000000000000000010")!

    init(x: F, y: F, z: F, t: F) {
        self.x = x
        self.y = y
        self.z = z
        self.t = t
    }

    /// RFC 8032 5.1.3 çözme; eğri üstünde değilse nil.
    init?(encoded: Bytes) {
        guard encoded.count == 32 else { return nil }
        let sign = encoded[31] >> 7 == 1
        let y = F(bytes: encoded)
        // Kanonik olmayan y (≥ p) reddedilir.
        var masked = encoded
        masked[31] &= 0x7F
        guard y.bytes == masked else { return nil }
        let yy = y.squared
        let u = yy - .one
        let v = EdwardsPoint.d * yy + .one
        let x2 = u * v.inverse
        var x = x2.power(F.pPlus3Over8)
        if !(x.squared == x2) { x = x * EdwardsPoint.sqrtMinusOne }
        guard x.squared == x2 else { return nil }
        if x.isZero && sign { return nil }
        if x.isNegative != sign { x = F.zero - x }
        self.init(x: x, y: y, z: .one, t: x * y)
    }

    func adding(_ q: EdwardsPoint) -> EdwardsPoint {
        let a = (y - x) * (q.y - q.x)
        let b = (y + x) * (q.y + q.x)
        let c = t * EdwardsPoint.d2 * q.t
        let dd = (z + z) * q.z
        let e = b - a, f = dd - c, g = dd + c, h = b + a
        return EdwardsPoint(x: e * f, y: g * h, z: f * g, t: e * h)
    }

    var negated: EdwardsPoint { EdwardsPoint(x: F.zero - x, y: y, z: z, t: F.zero - t) }

    /// Skaler (küçük-endian bayt) ile çarpım.
    func times(_ scalar: Bytes) -> EdwardsPoint {
        var r = EdwardsPoint.identity
        for i in stride(from: scalar.count * 8 - 1, through: 0, by: -1) {
            r = r.adding(r)
            if (scalar[i / 8] >> UInt8(i % 8)) & 1 == 1 { r = r.adding(self) }
        }
        return r
    }

    var encoded: Bytes {
        let zi = z.inverse
        var out = (y * zi).bytes
        if (x * zi).isNegative { out[31] |= 0x80 }
        return out
    }

    var isIdentity: Bool { encoded == EdwardsPoint.identity.encoded }
}

/// BoringSSL uyumlu SPAKE2 (adb eşlemesinde telefon "alice", TV "bob").
struct Spake2 {
    enum Role { case alice, bob }

    static let aliceName = Bytes("adb pair client\u{0}".utf8)
    static let bobName = Bytes("adb pair server\u{0}".utf8)
    // BoringSSL'in M ve N noktaları (sıkıştırılmış).
    static let m = EdwardsPoint(encoded: Bytes(hex: "5ada7e4bf6ddd9adb6626d32131c6b5c51a1e347a3478f53cfcf441b88eed12e")!)!
    static let n = EdwardsPoint(encoded: Bytes(hex: "10e3df0ae37d8e7a99b5fe74b44672103dbddcbd06af680d71329a11693bc778")!)!

    let role: Role
    let message: Bytes
    private let secret: Bytes
    private let passwordScalar: Bytes
    private let passwordHash: Bytes

    /// - Parameter seed: 64 rastgele bayt (testlerde sabit verilir).
    init(role: Role, password: Bytes, seed: Bytes = .random(64)) {
        self.role = role
        passwordHash = Bytes(SHA512.hash(data: password))
        // Özel skaler: tohum mod l, sonra 8 ile çarpılır (kofaktör).
        let reduced = BigNum(littleEndian: seed) % BigNum(littleEndian: EdwardsPoint.order)
        secret = (reduced << 3).littleEndian(count: 32)
        // Parola skaleri: alt üç biti sıfır olacak biçimde l, 2l, 4l eklenir (BoringSSL'deki gibi, sırayla).
        let l = BigNum(littleEndian: EdwardsPoint.order)
        var w = BigNum(littleEndian: passwordHash) % l
        if w.bit(0) { w = w + l }
        if w.bit(1) { w = w + (l << 1) }
        if w.bit(2) { w = w + (l << 2) }
        passwordScalar = w.littleEndian(count: 32)
        let mask = (role == .alice ? Spake2.m : Spake2.n).times(passwordScalar)
        message = EdwardsPoint.base.times(secret).adding(mask).encoded
    }

    /// Karşı tarafın mesajından 64 baytlık anahtar; mesaj geçersizse nil.
    func finish(_ theirs: Bytes) -> Bytes? {
        guard let point = EdwardsPoint(encoded: theirs) else { return nil }
        let theirMask = (role == .alice ? Spake2.n : Spake2.m).times(passwordScalar)
        let shared = point.adding(theirMask.negated).times(secret).encoded
        var hash = SHA512()
        func add(_ part: Bytes) {
            hash.update(data: le64(part.count))
            hash.update(data: part)
        }
        if role == .alice {
            add(Spake2.aliceName); add(Spake2.bobName); add(message); add(theirs)
        } else {
            add(Spake2.aliceName); add(Spake2.bobName); add(theirs); add(message)
        }
        add(shared)
        add(passwordHash)
        return Bytes(hash.finalize())
    }

    private func le64(_ v: Int) -> Bytes { (0..<8).map { UInt8(truncatingIfNeeded: UInt64(v) >> UInt64(8 * $0)) } }
}
