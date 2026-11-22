// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation
import Security

// TV kurulum protokollerinin (adb, sdb, SSH, zip, DER) ortak bayt yardımcıları.

typealias Bytes = [UInt8]

extension Array where Element == UInt8 {
    mutating func putLE16(_ value: Int) {
        append(UInt8(truncatingIfNeeded: value))
        append(UInt8(truncatingIfNeeded: value >> 8))
    }

    mutating func putLE32(_ value: UInt32) {
        for shift in stride(from: 0, to: 32, by: 8) { append(UInt8(truncatingIfNeeded: value >> UInt32(shift))) }
    }

    mutating func putBE32(_ value: UInt32) {
        for shift in stride(from: 24, through: 0, by: -8) { append(UInt8(truncatingIfNeeded: value >> UInt32(shift))) }
    }

    func le16(at offset: Int) -> Int { Int(self[offset]) | Int(self[offset + 1]) << 8 }

    func le32(at offset: Int) -> UInt32 {
        (0..<4).reduce(UInt32(0)) { $0 | UInt32(self[offset + $1]) << UInt32(8 * $1) }
    }

    func be32(at offset: Int) -> UInt32 {
        (0..<4).reduce(UInt32(0)) { $0 << 8 | UInt32(self[offset + $1]) }
    }

    var hexString: String { map { String(format: "%02x", $0) }.joined() }

    /// Onaltılık metinden; geçersiz karakterlerde nil.
    init?(hex: String) {
        let chars = [Character](hex.filter { !$0.isWhitespace })
        guard chars.count % 2 == 0 else { return nil }
        var out: [UInt8] = []
        out.reserveCapacity(chars.count / 2)
        var i = 0
        while i < chars.count {
            guard let hi = chars[i].hexDigitValue, let lo = chars[i + 1].hexDigitValue else { return nil }
            out.append(UInt8(hi << 4 | lo))
            i += 2
        }
        self = out
    }

    static func random(_ count: Int) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: count)
        if SecRandomCopyBytes(kSecRandomDefault, count, &out) != errSecSuccess {
            for i in out.indices { out[i] = UInt8.random(in: 0...255) }
        }
        return out
    }
}

func le32Bytes(_ value: UInt32) -> Bytes {
    var out = Bytes()
    out.putLE32(value)
    return out
}

func be32Bytes(_ value: UInt32) -> Bytes {
    var out = Bytes()
    out.putBE32(value)
    return out
}

/// Sürüm karşılaştırması: sayı sayı ("0.10.0" > "0.9.9"); sayı olmayan parça 0 sayılır.
enum VersionOrder {
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = numbers(candidate), b = numbers(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    private static func numbers(_ text: String) -> [Int] {
        text.split(whereSeparator: { !$0.isNumber }).map { Int($0) ?? 0 }
    }
}
