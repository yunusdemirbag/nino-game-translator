// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// Dakikalık istek hakkı: model başına kayan 60 sn pencere. Uygulama genelinde
/// tek (`shared`); hat yeniden kurulsa da sıfırlanmaz.
public actor RequestBudget {
    public static let shared = RequestBudget()

    public let window: TimeInterval
    private let now: @Sendable () -> Date
    private var stamps: [String: [Date]] = [:]
    private var lowered: [String: Int] = [:]

    public init(window: TimeInterval = 60, now: @escaping @Sendable () -> Date = { Date() }) {
        self.window = window
        self.now = now
    }

    /// Hak varsa alır ve `true` döner. `limit` `nil` ise sınır yok.
    public func acquire(_ key: String, limit: Int?) -> Bool {
        guard let cap = effectiveLimit(key, limit) else { return true }
        let t = now()
        var list = (stamps[key] ?? []).filter { t.timeIntervalSince($0) < window }
        guard list.count < cap else { stamps[key] = list; return false }
        list.append(t)
        stamps[key] = list
        return true
    }

    /// Hak var mı (almadan)?
    public func available(_ key: String, limit: Int?) -> Bool {
        guard let cap = effectiveLimit(key, limit) else { return true }
        let t = now()
        return (stamps[key] ?? []).filter { t.timeIntervalSince($0) < window }.count < cap
    }

    /// Hizmetin bildirdiği sınır: yalnız düşürür, yükseltmez.
    public func lower(_ key: String, to value: Int) {
        guard value > 0 else { return }
        lowered[key] = min(lowered[key] ?? .max, value)
    }

    public func effectiveLimit(_ key: String, _ limit: Int?) -> Int? {
        switch (limit, lowered[key]) {
        case let (l?, d?): return min(l, d)
        case let (l?, nil): return l
        case let (nil, d?): return d
        default: return nil
        }
    }
}
