// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// Eski 8787 SSE olayı (eski TV uygulamaları ve OBS sayfası için).
public struct LegacyEvent: Equatable, Sendable {
    public enum Name {
        public static let subtitle = "subtitle"
        public static let clear = "clear"
        public static let style = "style"
        public static let started = "started"
        public static let stopped = "stopped"
        public static let screen = "screen"
        public static let screenClear = "screen-clear"
        public static let region = "region"
        public static let regionClear = "region-clear"
        public static let ping = "ping"
    }

    public let name: String
    /// JSON gövdesi, anahtarlar sıralı.
    public let data: String

    public init(name: String, body: [String: Any]) {
        self.name = name
        self.data = String(decoding: LinkNumber.encode(body), as: UTF8.self)
    }

    /// "Altyazı olayı" mı? ("altyazı yalnız bilgisayarda" iken TV'lere gitmeyenler.)
    public var isSubtitleEvent: Bool {
        ![Name.started, Name.stopped, Name.ping].contains(name)
    }

    /// SSE çerçevesi: `event: <ad>\ndata: <JSON>\n\n`.
    public var frame: Data { Data("event: \(name)\ndata: \(data)\n\n".utf8) }

    /// 15 sn'de bir yollanan canlı tutma çerçevesi.
    public static let pingFrame = Data(": ping\nevent: ping\ndata: {}\n\n".utf8)
    /// Akışın ilk satırı.
    public static let retryFrame = Data("retry: 2000\n\n".utf8)
}

/// Protokol mesajlarını eski olaylara çevirir. Durum tutar (son altyazının kimliği).
public struct LegacyTranslator: Sendable {
    /// `durationMs: 0` ("clear gelene kadar") eski TV'de bu süreye çevrilir (eski varsayılan 15 sn).
    public var untilClearedDurationMs: Int
    public private(set) var lastSubtitleID: Int?

    public init(untilClearedDurationMs: Int = 15_000) {
        self.untilClearedDurationMs = untilClearedDurationMs
    }

    public mutating func subtitle(_ p: ShowPayload, now: Date = Date()) -> LegacyEvent {
        lastSubtitleID = p.id
        var o: [String: Any] = [
            // Eski TV'ler konuşan adını ayrı tanımaz: ad metne önek olarak katılır.
            "text": p.textWithSpeaker,
            "duration": p.durationMs > 0 ? p.durationMs : untilClearedDurationMs,
            "at": Int64((now.timeIntervalSince1970 * 1000).rounded()),
        ]
        o["box"] = p.box?.jsonObject
        if p.replace == true { o["replace"] = true }
        o["light"] = p.light.map { LinkNumber.unit($0, 2) }
        o["cover"] = p.cover
        return LegacyEvent(name: LegacyEvent.Name.subtitle, body: o)
    }

    /// Eski `clear`'ın kimliği yok: kimlik verilmişse yalnız son altyazı oysa yollanır.
    public mutating func clear(id: Int?) -> LegacyEvent? {
        if let id, let last = lastSubtitleID, id != last { return nil }
        if id != nil, lastSubtitleID == nil { return nil }
        lastSubtitleID = nil
        return LegacyEvent(name: LegacyEvent.Name.clear, body: [:])
    }

    public mutating func event(_ e: NinoEvent) -> LegacyEvent {
        switch e {
        case let .style(s):
            return LegacyEvent(name: LegacyEvent.Name.style, body: s.fields)
        case .started:
            return LegacyEvent(name: LegacyEvent.Name.started, body: [:])
        case .stopped:
            lastSubtitleID = nil
            return LegacyEvent(name: LegacyEvent.Name.stopped, body: [:])
        case let .screen(p):
            // Eski TV tuş simgesini bilmez: `⟦T1⟧` okunur metne döner (`[→]`), `icons` gitmez.
            var o: [String: Any] = ["duration": max(0, p.durationMs), "items": p.items.map(\.legacyJSONObject)]
            if p.overlay == true { o["overlay"] = true }
            return LegacyEvent(name: LegacyEvent.Name.screen, body: o)
        case .screenClear:
            return LegacyEvent(name: LegacyEvent.Name.screenClear, body: [:])
        case let .region(r):
            var o: [String: Any] = ["id": r.id, "text": IconPlaceholders.readable(r.text, icons: r.icons)]
            o["box"] = r.box?.jsonObject
            o["line"] = r.line.map { LinkNumber.round($0) }
            return LegacyEvent(name: LegacyEvent.Name.region, body: o)
        case .regionClear:
            return LegacyEvent(name: LegacyEvent.Name.regionClear, body: [:])
        }
    }
}
