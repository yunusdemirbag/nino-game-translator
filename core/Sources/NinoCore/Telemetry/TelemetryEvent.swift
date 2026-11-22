// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// Ölçüm olaylarındaki değerler (JSON). Tarif: docs/tarif/olcum.md.
public enum TelemetryValue: Codable, Equatable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([TelemetryValue])
    case object([String: TelemetryValue])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Int.self) { self = .int(v) }
        else if let v = try? c.decode(Double.self) { self = .double(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([TelemetryValue].self) { self = .array(v) }
        else { self = .object(try c.decode([String: TelemetryValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .int(let v): try c.encode(v)
        case .double(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }

    public var intValue: Int? { if case .int(let v) = self { return v } else { return nil } }
    public var stringValue: String? { if case .string(let v) = self { return v } else { return nil } }
}

/// Bir ölçüm olayı: `{"k": tür, "t": zaman, ...alanlar}`. Hazır kurucular tarifteki alanları doldurur.
public struct TelemetryEvent: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case launch, session, crash, error, diag
        case ps5Connect = "ps5_connect", ps5Drop = "ps5_drop", tvConnect = "tv_connect", tvDrop = "tv_drop"
    }

    public var kind: Kind
    /// Unix saniye; 0 ise `Telemetry` kaydederken o anı yazar.
    public var time: Int
    public var fields: [String: TelemetryValue]

    public init(kind: Kind, time: Int = 0, fields: [String: TelemetryValue] = [:]) {
        self.kind = kind
        self.time = time
        self.fields = fields
    }

    private struct Key: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(_ s: String) { stringValue = s }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        kind = try c.decode(Kind.self, forKey: Key("k"))
        time = try c.decode(Int.self, forKey: Key("t"))
        var f: [String: TelemetryValue] = [:]
        for key in c.allKeys where key.stringValue != "k" && key.stringValue != "t" {
            f[key.stringValue] = try c.decode(TelemetryValue.self, forKey: key)
        }
        fields = f
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        try c.encode(kind, forKey: Key("k"))
        try c.encode(time, forKey: Key("t"))
        for (k, v) in fields where k != "k" && k != "t" { try c.encode(v, forKey: Key(k)) }
    }
}

// MARK: - Hazır kurucular

// Uygulamaların kendi `TVBrand` gibi türleriyle çakışmasın diye TelemetryEvent'in içinde.
extension TelemetryEvent {
    public enum PS5Route: String, Sendable { case lan, remote, xbox }
    public enum TVBrand: String, Sendable { case androidtv, samsung, lg }
    public enum TVProtocol: String, Sendable { case nino, legacy }
    public enum SessionSource: String, Sendable { case remoteplay, capture, xbox, screen }
    public enum DiagSeverity: String, Sendable { case info, warn, error }
    /// İz adımı: tetikten kaç saniye önce (≤ 0), kod, isteğe bağlı sayı.
    public struct DiagStep: Equatable, Sendable {
        public var seconds: Int
        public var code: String
        public var value: Int?
        public init(_ seconds: Int, _ code: String, _ value: Int? = nil) {
            self.seconds = seconds
            self.code = code
            self.value = value
        }
    }
}

extension TelemetryEvent {
    /// Uygulama açıldı. `ms`: soğuk açılış süresi (biliniyorsa).
    public static func launch(ms: Int? = nil) -> TelemetryEvent {
        TelemetryEvent(kind: .launch, fields: ms.map { ["ms": .int(max(0, $0))] } ?? [:])
    }

    /// Önceki çalışma çöktü (bir sonraki açılışta). `code` geçersizse `unclean_exit`, `where` geçersizse atılır.
    public static func crash(code: String?, where place: String? = nil, version: String, uptime: Int? = nil) -> TelemetryEvent {
        var f: [String: TelemetryValue] = ["code": .string(TelemetryCode.clean(code) ?? "unclean_exit"), "ver": .string(version)]
        if let w = TelemetryCode.cleanWhere(place) { f["where"] = .string(w) }
        if let up = uptime, up >= 0 { f["up"] = .int(up) }
        return TelemetryEvent(kind: .crash, fields: f)
    }

    /// Yakalanan hata. Kod geçersizse (boşluk, yol, mesaj) `nil` döner: serbest yazı gönderilmez.
    public static func error(_ code: String, http: Int? = nil, count: Int = 1) -> TelemetryEvent? {
        guard let code = TelemetryCode.clean(code) else { return nil }
        var f: [String: TelemetryValue] = ["code": .string(code)]
        if let http, (100...599).contains(http) { f["http"] = .int(http) }
        if count > 1 { f["n"] = .int(count) }
        return TelemetryEvent(kind: .error, fields: f)
    }

    /// PS5 bağlantı denemesi bitti. `result`: "ok" ya da hata kodu.
    public static func ps5Connect(result: String, ms: Int, via: PS5Route) -> TelemetryEvent {
        TelemetryEvent(kind: .ps5Connect, fields: [
            "r": .string(result == "ok" ? "ok" : TelemetryCode.clean(result) ?? TelemetryCode.ps5Other),
            "ms": .int(max(0, ms)), "via": .string(via.rawValue),
        ])
    }

    /// Bağlıyken PS5 koptu. `after`: kaç saniyedir bağlıydı.
    public static func ps5Drop(_ reason: String, after: Int) -> TelemetryEvent {
        TelemetryEvent(kind: .ps5Drop, fields: [
            "code": .string(TelemetryCode.clean(reason) ?? "other"), "after": .int(max(0, after)),
        ])
    }

    /// `model`: TV'nin modeli (ad değil), `tvApp`: TV'deki Nino sürümü; biliniyorsa.
    public static func tvConnect(result: String, ms: Int, brand: TVBrand?, proto: TVProtocol,
                                 model: String? = nil, tvApp: String? = nil) -> TelemetryEvent {
        var f: [String: TelemetryValue] = [
            "r": .string(result == "ok" ? "ok" : TelemetryCode.clean(result) ?? TelemetryCode.tvOther),
            "ms": .int(max(0, ms)), "brand": .string(brand?.rawValue ?? ""), "proto": .string(proto.rawValue),
        ]
        addTV(&f, model: model, tvApp: tvApp)
        return TelemetryEvent(kind: .tvConnect, fields: f)
    }

    /// `reason`: `TelemetryCode.Drop` (timeout, write_error, closed, resume, network_change, network_lost, other).
    public static func tvDrop(_ reason: String, brand: TVBrand?, after: Int,
                              model: String? = nil, tvApp: String? = nil) -> TelemetryEvent {
        var f: [String: TelemetryValue] = [
            "code": .string(TelemetryCode.clean(reason) ?? "other"), "brand": .string(brand?.rawValue ?? ""),
            "after": .int(max(0, after)),
        ]
        addTV(&f, model: model, tvApp: tvApp)
        return TelemetryEvent(kind: .tvDrop, fields: f)
    }

    /// Model ve sürüm yalnız kurala uyarsa (sunucuyla aynı); kullanıcının verdiği TV adı gibi şeyler gitmez.
    private static func addTV(_ f: inout [String: TelemetryValue], model: String?, tvApp: String?) {
        if let model, model.range(of: #"^[A-Za-z0-9][A-Za-z0-9 ,._()+-]{0,59}$"#, options: .regularExpression) != nil {
            f["model"] = .string(model)
        }
        if let tvApp, tvApp.range(of: #"^[0-9A-Za-z.+-]{1,24}$"#, options: .regularExpression) != nil {
            f["tvApp"] = .string(tvApp)
        }
    }

    /// Otomatik teşhis (docs/tarif/otomatik-teshis.md): bekçinin bir kuralı tetiklendi. Serbest metin yok:
    /// `state` sayı/doğru-yanlış/kod, `trail` [kaç sn önce (≤ 0), kod, sayı?]. Kurala uymayan alanlar atılır.
    public static func diag(rule: String, cause: String, severity: DiagSeverity = .warn,
                            state: [String: TelemetryValue] = [:], trail: [DiagStep] = [],
                            tv: (brand: TVBrand?, model: String?, app: String?)? = nil, game: String? = nil,
                            versions: [String: String] = [:]) -> TelemetryEvent? {
        guard rule.range(of: #"^[a-z0-9_.]{1,40}$"#, options: .regularExpression) != nil else { return nil }
        let short = #"^[A-Za-z0-9_.$-]{1,40}$"#
        let key = #"^[A-Za-z0-9_]{1,24}$"#
        var f: [String: TelemetryValue] = [
            "rule": .string(rule),
            "cause": .string(cause.range(of: short, options: .regularExpression) != nil ? cause : "unknown"),
            "sev": .string(severity.rawValue),
        ]
        var s: [String: TelemetryValue] = [:]
        for (k, v) in state.sorted(by: { $0.key < $1.key }) where s.count < 30 && k.range(of: key, options: .regularExpression) != nil {
            switch v {
            case .int, .bool: s[k] = v
            case .double(let d) where d.isFinite: s[k] = v
            case .string(let str) where str.range(of: short, options: .regularExpression) != nil: s[k] = v
            default: continue
            }
        }
        if !s.isEmpty { f["state"] = .object(s) }
        let steps = trail.suffix(40).compactMap { step -> TelemetryValue? in
            guard (-3600...0).contains(step.seconds), let code = TelemetryCode.clean(step.code) else { return nil }
            var a: [TelemetryValue] = [.int(step.seconds), .string(code)]
            if let n = step.value { a.append(.int(n)) }
            return .array(a)
        }
        if !steps.isEmpty { f["trail"] = .array(steps) }
        if let tv {
            var t: [String: TelemetryValue] = [:]
            if let b = tv.brand { t["brand"] = .string(b.rawValue) }
            var probe: [String: TelemetryValue] = [:]
            addTV(&probe, model: tv.model, tvApp: tv.app)
            if let m = probe["model"] { t["model"] = m }
            if let a = probe["tvApp"] { t["app"] = a }
            if !t.isEmpty { f["tv"] = .object(t) }
        }
        if let game, game.range(of: #"^[a-z0-9][a-z0-9._-]{0,63}$"#, options: .regularExpression) != nil, let id = GameIDs.id(game) {
            f["game"] = .string(id) // asıl kimlik (takma ad değil)
        }
        let ver = versions.filter {
            $0.key.range(of: key, options: .regularExpression) != nil && $0.value.range(of: #"^[0-9A-Za-z.+-]{1,24}$"#, options: .regularExpression) != nil
        }.prefix(6)
        if !ver.isEmpty { f["ver"] = .object(Dictionary(uniqueKeysWithValues: ver.map { ($0.key, TelemetryValue.string($0.value)) })) }
        return TelemetryEvent(kind: .diag, fields: f)
    }

    /// Çeviri oturumu bitti. `timings` oturum boyunca toplanan süre histogramları.
    public static func session(duration: Int, game: String?, source: SessionSource, lines: Int,
                               timings: SessionTimings = SessionTimings()) -> TelemetryEvent {
        var f: [String: TelemetryValue] = [
            "dur": .int(max(0, duration)), "src": .string(source.rawValue), "lines": .int(max(0, lines)),
        ]
        if let game, game.range(of: #"^[a-z0-9][a-z0-9._-]{0,63}$"#, options: .regularExpression) != nil, let id = GameIDs.id(game) {
            f["game"] = .string(id) // asıl kimlik (takma ad değil)
        }
        let h = timings.jsonValue
        if case .object(let o) = h, !o.isEmpty { f["h"] = h }
        return TelemetryEvent(kind: .session, fields: f)
    }
}
