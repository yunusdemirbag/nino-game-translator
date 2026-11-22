// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// Kurulumun gerektirdiği kadar işaretsiz büyük tam sayı: adb açık anahtar biçimi (R² mod n), SPAKE2 skalerleri
/// (mod l) ve SSH'nin eski Diffie-Hellman grupları (Montgomery üs alma). 32 bitlik sözcükler, en düşük önce.
struct BigNum: Equatable, Comparable {
    private(set) var words: [UInt32]

    init(_ value: UInt64 = 0) {
        words = [UInt32(truncatingIfNeeded: value), UInt32(truncatingIfNeeded: value >> 32)]
        trim()
    }

    init(words: [UInt32]) {
        self.words = words
        trim()
    }

    init(bigEndian bytes: Bytes) {
        var w = [UInt32](repeating: 0, count: (bytes.count + 3) / 4)
        for (i, b) in bytes.reversed().enumerated() { w[i / 4] |= UInt32(b) << UInt32(8 * (i % 4)) }
        self.init(words: w)
    }

    init(littleEndian bytes: Bytes) { self.init(bigEndian: bytes.reversed()) }

    private mutating func trim() {
        while words.last == 0 { words.removeLast() }
    }

    var isZero: Bool { words.isEmpty }

    var bitLength: Int {
        guard let top = words.last else { return 0 }
        return words.count * 32 - top.leadingZeroBitCount
    }

    func bit(_ i: Int) -> Bool {
        let w = i / 32
        return w < words.count && (words[w] >> UInt32(i % 32)) & 1 == 1
    }

    func littleEndian(count: Int) -> Bytes {
        (0..<count).map { i in
            let w = i / 4
            return w < words.count ? UInt8(truncatingIfNeeded: words[w] >> UInt32(8 * (i % 4))) : 0
        }
    }

    func bigEndian(count: Int) -> Bytes { littleEndian(count: count).reversed() }

    /// En kısa büyük-endian gösterim (sıfır için boş).
    var bigEndianMinimal: Bytes { Array(bigEndian(count: (bitLength + 7) / 8)) }

    static func < (a: BigNum, b: BigNum) -> Bool {
        if a.words.count != b.words.count { return a.words.count < b.words.count }
        for i in stride(from: a.words.count - 1, through: 0, by: -1) where a.words[i] != b.words[i] {
            return a.words[i] < b.words[i]
        }
        return false
    }

    static func + (a: BigNum, b: BigNum) -> BigNum {
        let n = max(a.words.count, b.words.count)
        var out = [UInt32](repeating: 0, count: n + 1)
        var carry: UInt64 = 0
        for i in 0..<n {
            let s = UInt64(i < a.words.count ? a.words[i] : 0) + UInt64(i < b.words.count ? b.words[i] : 0) + carry
            out[i] = UInt32(truncatingIfNeeded: s)
            carry = s >> 32
        }
        out[n] = UInt32(carry)
        return BigNum(words: out)
    }

    /// a − b; a ≥ b olmalıdır.
    static func - (a: BigNum, b: BigNum) -> BigNum {
        precondition(a >= b, "BigNum underflow")
        var out = a.words
        var borrow: UInt64 = 0
        for i in 0..<out.count {
            let sub = UInt64(i < b.words.count ? b.words[i] : 0) + borrow
            let cur = UInt64(out[i])
            if cur >= sub {
                out[i] = UInt32(cur - sub)
                borrow = 0
            } else {
                out[i] = UInt32(cur + (1 << 32) - sub)
                borrow = 1
            }
        }
        return BigNum(words: out)
    }

    static func * (a: BigNum, b: BigNum) -> BigNum {
        guard !a.isZero, !b.isZero else { return BigNum() }
        var out = [UInt32](repeating: 0, count: a.words.count + b.words.count)
        for i in 0..<a.words.count {
            var carry: UInt64 = 0
            let x = UInt64(a.words[i])
            for j in 0..<b.words.count {
                let t = x * UInt64(b.words[j]) + UInt64(out[i + j]) + carry
                out[i + j] = UInt32(truncatingIfNeeded: t)
                carry = t >> 32
            }
            out[i + b.words.count] = UInt32(carry)
        }
        return BigNum(words: out)
    }

    static func << (a: BigNum, n: Int) -> BigNum {
        guard !a.isZero, n > 0 else { return a }
        let shiftWords = n / 32, shiftBits = UInt32(n % 32)
        var out = [UInt32](repeating: 0, count: a.words.count + shiftWords + 1)
        for (i, w) in a.words.enumerated() {
            out[i + shiftWords] |= w << shiftBits
            if shiftBits > 0 { out[i + shiftWords + 1] |= w >> (32 - shiftBits) }
        }
        return BigNum(words: out)
    }

    /// Kalan: baştan sona bit bit (en çok birkaç bin bitlik sayılar için yeterince hızlı).
    static func % (a: BigNum, m: BigNum) -> BigNum {
        precondition(!m.isZero)
        if a < m { return a }
        var r = BigNum()
        for i in stride(from: a.bitLength - 1, through: 0, by: -1) {
            r = r << 1
            if a.bit(i) { r = r + BigNum(1) }
            if r >= m { r = r - m }
        }
        return r
    }

    /// −m⁻¹ mod 2³² (Montgomery ve adb'nin n0inv'i); m tek olmalıdır.
    static func negInverse32(_ low: UInt32) -> UInt32 {
        var inv: UInt32 = 1
        for _ in 0..<5 { inv = inv &* (2 &- low &* inv) }
        return 0 &- inv
    }

    /// (self ^ e) mod m; m tek olmalıdır (Montgomery çarpımı).
    func power(_ e: BigNum, modulus m: BigNum) -> BigNum {
        let n = m.words.count
        let mw = m.words
        let k = BigNum.negInverse32(mw[0])

        func pad(_ x: BigNum) -> [UInt32] { x.words + [UInt32](repeating: 0, count: n - x.words.count) }

        // a·b·R⁻¹ mod m (CIOS)
        func mont(_ a: [UInt32], _ b: [UInt32]) -> [UInt32] {
            var t = [UInt32](repeating: 0, count: n + 2)
            for i in 0..<n {
                var carry: UInt64 = 0
                let ai = UInt64(a[i])
                for j in 0..<n {
                    let s = UInt64(t[j]) + ai * UInt64(b[j]) + carry
                    t[j] = UInt32(truncatingIfNeeded: s)
                    carry = s >> 32
                }
                var s = UInt64(t[n]) + carry
                t[n] = UInt32(truncatingIfNeeded: s)
                t[n + 1] = UInt32(s >> 32)
                let q = UInt64(t[0] &* k)
                s = UInt64(t[0]) + q * UInt64(mw[0])
                carry = s >> 32
                for j in 1..<n {
                    let u = UInt64(t[j]) + q * UInt64(mw[j]) + carry
                    t[j - 1] = UInt32(truncatingIfNeeded: u)
                    carry = u >> 32
                }
                s = UInt64(t[n]) + carry
                t[n - 1] = UInt32(truncatingIfNeeded: s)
                t[n] = t[n + 1] + UInt32(s >> 32)
            }
            var result = Array(t[0..<n])
            let top = t[n]
            if top != 0 || !(BigNum(words: result) < m) {
                var borrow: Int64 = 0
                for j in 0..<n {
                    var d = Int64(result[j]) - Int64(mw[j]) - borrow
                    borrow = d < 0 ? 1 : 0
                    if d < 0 { d += 1 << 32 }
                    result[j] = UInt32(d)
                }
            }
            return result
        }

        let r = (BigNum(1) << (32 * n)) % m
        let rr = (r * r) % m
        var acc = pad(r)
        let base = mont(pad(self % m), pad(rr))
        for i in stride(from: e.bitLength - 1, through: 0, by: -1) {
            acc = mont(acc, acc)
            if e.bit(i) { acc = mont(acc, base) }
        }
        var one = [UInt32](repeating: 0, count: n)
        one[0] = 1
        return BigNum(words: mont(acc, one))
    }
}
