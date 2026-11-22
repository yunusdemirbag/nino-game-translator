// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// TV uygulaması denetiminin (Samsung yükleyicisi, LG kurulum denetimi) gereksiz tekrarını önler.
///
/// Denetim şu durumlarda çalışır: ilk eşleşme, TV adresi ya da markası değişince, kurulu sürüm bilinmiyorken, paketteki
/// TV uygulamasının sürümü değişince ve kullanıcı elle isteyince. Başarılı bir sonuçtan ("kuruldu" ya da "kurulum
/// gerekmedi") sonra aynı TV için `quietPeriod` boyunca kendiliğinden yeniden çalışmaz. Bellekte durur: Nino yeniden
/// açılınca sıfırlanır.
struct TVAppCheckGate {
    static let quietPeriod: TimeInterval = 6 * 3600

    struct Key: Hashable, Sendable {
        var brand: PairedTV.Brand
        var host: String
        /// Nino'nun içindeki TV uygulamasının sürümü.
        var bundled: String
    }

    private var confirmed: [Key: (version: String, at: Date)] = [:]

    /// Yakın zamanda doğrulanmış kurulu sürüm (denetim atlanabilir); yoksa nil.
    /// `recorded`: kayıtlı kurulu sürüm. `requireRecorded` iken kayıt yoksa ya da doğrulanandan farklıysa denetim çalışır.
    func freshVersion(_ key: Key, recorded: String?, requireRecorded: Bool, now: Date) -> String? {
        guard let c = confirmed[key], now >= c.at, now.timeIntervalSince(c.at) < Self.quietPeriod else { return nil }
        if requireRecorded, recorded != c.version { return nil }
        return c.version
    }

    mutating func confirm(_ key: Key, version: String, now: Date) {
        confirmed[key] = (version, now)
    }

    mutating func forget(_ key: Key) { confirmed[key] = nil }
}
