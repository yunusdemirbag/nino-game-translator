// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

// Protokol uzantıları (sürüm 1, hepsi isteğe bağlı). Bkz. docs/tarif/protokol.md "Uzantılar".

extension NinoLink {
    /// `cover` taşımayan mesajlar için göndericinin uyduğu üst sınır.
    public static let compactMessageBytes = 16 * 1024
    /// `info` cevabındaki `role` değeri: cevap veren bir göndericidir.
    public static let senderRole = "sender"
    /// Yeni bağlanan TV'ye `started` yalnız çeviri bu kadar saniye önce başladıysa yeniden yollanır
    /// (TV her `started`'da "çeviri başladı" balonu gösterir).
    public static let startedReplayWindow: TimeInterval = 20

    public enum ExtensionType {
        public static let style = "style"
        public static let started = "started"
        public static let stopped = "stopped"
        public static let screen = "screen"
        public static let screenClear = "screen-clear"
        public static let region = "region"
        public static let regionClear = "region-clear"
    }
}

/// Uzantılarda ondalık yuvarlama ve kırpma.
enum LinkNumber {
    /// Yuvarlanmış sayı; JSON'da kısa yazılsın diye ondalık sayı olarak (0.95, 0.9499999… değil).
    static func round(_ v: Double, _ digits: Int = 4) -> NSDecimalNumber {
        guard v.isFinite else { return 0 }
        let f = pow(10, Double(digits))
        let r = (v * f).rounded() / f
        return NSDecimalNumber(string: "\(r == 0 ? 0 : r)", locale: Locale(identifier: "en_US_POSIX"))
    }

    static func unit(_ v: Double, _ digits: Int = 4) -> NSDecimalNumber { round(min(1, max(0, v)), digits) }

    static func double(_ any: Any?) -> Double? {
        guard let n = any as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
        return n.doubleValue
    }

    static func int(_ any: Any?) -> Int? {
        guard let n = any as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
        return n.intValue
    }

    static func bool(_ any: Any?) -> Bool? {
        guard let n = any as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() else { return nil }
        return n.boolValue
    }

    /// Sıralı anahtarlı JSON.
    static func encode(_ o: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: o, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data()
    }
}

/// Karenin oranı olarak bir kutu (0–1, üstten/soldan).
public struct NinoBox: Equatable, Hashable, Sendable {
    public var left: Double
    public var top: Double
    public var right: Double
    public var bottom: Double

    public init(left: Double, top: Double, right: Double, bottom: Double) {
        self.left = left
        self.top = top
        self.right = right
        self.bottom = bottom
    }

    /// 0–1 arasına kırpılmış, 4 basamağa yuvarlanmış JSON nesnesi.
    public var jsonObject: [String: Any] {
        ["left": LinkNumber.unit(left), "top": LinkNumber.unit(top),
         "right": LinkNumber.unit(right), "bottom": LinkNumber.unit(bottom)]
    }

    public init?(json: Any?) {
        guard let o = json as? [String: Any],
              let l = LinkNumber.double(o["left"]), let t = LinkNumber.double(o["top"]),
              let r = LinkNumber.double(o["right"]), let b = LinkNumber.double(o["bottom"]) else { return nil }
        self.init(left: l, top: t, right: r, bottom: b)
    }
}

/// `style` mesajı: TV'deki altyazı görünümü. Bütün alanlar isteğe bağlı; değerler
/// dizge olarak taşınır ki bilinmeyen yeni değerler de geçsin.
public struct NinoStyle: Equatable, Sendable {
    public var fontSize: Int?
    public var bottomPercent: Int?
    /// `cover`, `above`, `below`, `fixed`
    public var placement: String?
    /// 0–100 zemin koyuluğu.
    public var background: Int?
    /// `fit`, `band`
    public var backgroundShape: String?
    public var bold: Bool?
    /// `white`, `yellow`
    public var textColor: String?
    /// `inApp`, `overlay` (yalnız Android TV)
    public var displayMode: String?
    public var stackPrevious: Bool?
    /// `classic`, `cinema`, `minimal`, `glass`, `contrast`, `outline`
    public var theme: String?
    public var autoSize: Bool?
    /// `system`, `modern`, `condensed`, `rounded`
    public var font: String?
    /// TV'de sol alttaki Nino rozeti.
    public var watermark: Bool?

    public init(fontSize: Int? = nil, bottomPercent: Int? = nil, placement: String? = nil, background: Int? = nil,
                backgroundShape: String? = nil, bold: Bool? = nil, textColor: String? = nil, displayMode: String? = nil,
                stackPrevious: Bool? = nil, theme: String? = nil, autoSize: Bool? = nil, font: String? = nil,
                watermark: Bool? = nil) {
        self.fontSize = fontSize
        self.bottomPercent = bottomPercent
        self.placement = placement
        self.background = background
        self.backgroundShape = backgroundShape
        self.bold = bold
        self.textColor = textColor
        self.displayMode = displayMode
        self.stackPrevious = stackPrevious
        self.theme = theme
        self.autoSize = autoSize
        self.font = font
        self.watermark = watermark
    }

    /// Yalnız dolu alanlar (zarf alanları yok).
    public var fields: [String: Any] {
        var o: [String: Any] = [:]
        o["fontSize"] = fontSize
        o["bottomPercent"] = bottomPercent
        o["placement"] = placement
        o["background"] = background
        o["backgroundShape"] = backgroundShape
        o["bold"] = bold
        o["textColor"] = textColor
        o["displayMode"] = displayMode
        o["stackPrevious"] = stackPrevious
        o["theme"] = theme
        o["autoSize"] = autoSize
        o["font"] = font
        o["watermark"] = watermark
        return o
    }

    public init(fields o: [String: Any]) {
        self.init(fontSize: LinkNumber.int(o["fontSize"]), bottomPercent: LinkNumber.int(o["bottomPercent"]),
                  placement: o["placement"] as? String, background: LinkNumber.int(o["background"]),
                  backgroundShape: o["backgroundShape"] as? String, bold: LinkNumber.bool(o["bold"]),
                  textColor: o["textColor"] as? String, displayMode: o["displayMode"] as? String,
                  stackPrevious: LinkNumber.bool(o["stackPrevious"]), theme: o["theme"] as? String,
                  autoSize: LinkNumber.bool(o["autoSize"]), font: o["font"] as? String,
                  watermark: LinkNumber.bool(o["watermark"]))
    }
}

/// `screen` mesajındaki tek öğe (ekranı çevir, köşe yazıları, telefon, harita kartı...).
public struct ScreenItem: Equatable, Sendable {
    public var box: NinoBox
    public var text: String
    /// Satır yüksekliği (karenin oranı).
    public var line: Double?
    public var paragraphs: Bool?
    public var plain: Bool?
    public var italic: Bool?
    /// `#rrggbb`
    public var fill: String?
    /// `#rrggbb`
    public var ink: String?
    /// Derece, saat yönü artı.
    public var angle: Double?
    /// 0–1
    public var alpha: Double?
    public var side: Bool?
    public var frost: Bool?
    public var backdrop: Bool?
    public var card: Bool?
    /// `text` içindeki `⟦T1⟧` yer tutucularının tuş simgeleri. Boşsa alan yazılmaz.
    public var icons: [LinkIcon]?

    public init(box: NinoBox, text: String, line: Double? = nil, paragraphs: Bool? = nil, plain: Bool? = nil,
                italic: Bool? = nil, fill: String? = nil, ink: String? = nil, angle: Double? = nil, alpha: Double? = nil,
                side: Bool? = nil, frost: Bool? = nil, backdrop: Bool? = nil, card: Bool? = nil, icons: [LinkIcon]? = nil) {
        self.box = box
        self.text = text
        self.line = line
        self.paragraphs = paragraphs
        self.plain = plain
        self.italic = italic
        self.fill = fill
        self.ink = ink
        self.angle = angle
        self.alpha = alpha
        self.side = side
        self.frost = frost
        self.backdrop = backdrop
        self.card = card
        self.icons = icons
    }

    public var jsonObject: [String: Any] {
        var o: [String: Any] = ["box": box.jsonObject, "text": text]
        o["line"] = line.map { LinkNumber.round($0) }
        o["paragraphs"] = paragraphs
        o["plain"] = plain
        o["italic"] = italic
        o["fill"] = fill
        o["ink"] = ink
        if let angle, abs(angle) >= 0.3 { o["angle"] = LinkNumber.round(angle, 1) }
        o["alpha"] = alpha.map { LinkNumber.unit($0, 2) }
        o["side"] = side
        o["frost"] = frost
        o["backdrop"] = backdrop
        o["card"] = card
        o["icons"] = LinkIcon.encode(icons)
        return o
    }

    /// Eski 8787 göstericisi için: yer tutucular okunur metne döner (`[→]`), `icons` gitmez.
    public var legacyJSONObject: [String: Any] {
        var copy = self
        copy.text = IconPlaceholders.readable(text, icons: icons)
        copy.icons = nil
        return copy.jsonObject
    }

    public init?(json: Any?) {
        guard let o = json as? [String: Any], let box = NinoBox(json: o["box"]), let text = o["text"] as? String else { return nil }
        self.init(box: box, text: text, line: LinkNumber.double(o["line"]), paragraphs: LinkNumber.bool(o["paragraphs"]),
                  plain: LinkNumber.bool(o["plain"]), italic: LinkNumber.bool(o["italic"]), fill: o["fill"] as? String,
                  ink: o["ink"] as? String, angle: LinkNumber.double(o["angle"]), alpha: LinkNumber.double(o["alpha"]),
                  side: LinkNumber.bool(o["side"]), frost: LinkNumber.bool(o["frost"]),
                  backdrop: LinkNumber.bool(o["backdrop"]), card: LinkNumber.bool(o["card"]),
                  icons: LinkIcon.decode(o["icons"]))
    }
}

/// `screen` mesajı.
public struct ScreenPayload: Equatable, Sendable {
    public var items: [ScreenItem]
    public var durationMs: Int
    /// `true`: TV görünen altyazıyı silmez (sürekli örtüler).
    public var overlay: Bool?

    public init(items: [ScreenItem], durationMs: Int, overlay: Bool? = nil) {
        self.items = items
        self.durationMs = durationMs
        self.overlay = overlay
    }
}

/// `region` mesajı: kimlikli ek alan kutusu.
public struct RegionPayload: Equatable, Sendable {
    public var id: String
    /// Boşsa kutu kalkar.
    public var text: String
    public var box: NinoBox?
    public var line: Double?
    /// `text` içindeki `⟦T1⟧` yer tutucularının tuş simgeleri. Boşsa alan yazılmaz.
    public var icons: [LinkIcon]?

    public init(id: String, text: String, box: NinoBox? = nil, line: Double? = nil, icons: [LinkIcon]? = nil) {
        self.id = id
        self.text = text
        self.box = box
        self.line = line
        self.icons = icons
    }
}

/// Uzantı mesajları (`show`/`clear` dışındaki, göndericiden TV'ye giden ek türler).
public enum NinoEvent: Equatable, Sendable {
    case style(NinoStyle)
    case started
    case stopped
    case screen(ScreenPayload)
    case screenClear
    case region(RegionPayload)
    case regionClear

    public var type: String {
        switch self {
        case .style: return NinoLink.ExtensionType.style
        case .started: return NinoLink.ExtensionType.started
        case .stopped: return NinoLink.ExtensionType.stopped
        case .screen: return NinoLink.ExtensionType.screen
        case .screenClear: return NinoLink.ExtensionType.screenClear
        case .region: return NinoLink.ExtensionType.region
        case .regionClear: return NinoLink.ExtensionType.regionClear
        }
    }

    /// Altyazı olayı mı? ("altyazı yalnız bilgisayarda" iken TV'ye gitmeyenler.)
    public var isSubtitleEvent: Bool {
        switch self {
        case .started, .stopped: return false
        default: return true
        }
    }

    public func jsonObject() -> [String: Any] {
        var o: [String: Any] = ["app": "nino", "type": type]
        switch self {
        case let .style(s):
            o.merge(s.fields) { a, _ in a }
        case let .screen(p):
            o["items"] = p.items.map(\.jsonObject)
            o["durationMs"] = max(0, p.durationMs)
            o["overlay"] = p.overlay
        case let .region(r):
            o["id"] = r.id
            o["text"] = r.text
            o["box"] = r.box?.jsonObject
            o["line"] = r.line.map { LinkNumber.round($0) }
            o["icons"] = LinkIcon.encode(r.icons)
        case .started, .stopped, .screenClear, .regionClear:
            break
        }
        return o
    }

    public func encoded() -> Data { LinkNumber.encode(jsonObject()) }
    public var jsonString: String { String(decoding: encoded(), as: UTF8.self) }

    /// Uzantı türü değilse `nil`; zarf bozuksa hata.
    public init?(data: Data) throws {
        guard let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { throw NinoMessage.DecodeError.notJSON }
        guard (o["app"] as? String) == "nino" else { throw NinoMessage.DecodeError.notNino }
        guard let type = o["type"] as? String else { throw NinoMessage.DecodeError.missingField("type") }
        switch type {
        case NinoLink.ExtensionType.style:
            self = .style(NinoStyle(fields: o))
        case NinoLink.ExtensionType.started:
            self = .started
        case NinoLink.ExtensionType.stopped:
            self = .stopped
        case NinoLink.ExtensionType.screen:
            guard let raw = o["items"] as? [Any] else { throw NinoMessage.DecodeError.missingField("items") }
            self = .screen(ScreenPayload(items: raw.compactMap(ScreenItem.init(json:)),
                                         durationMs: max(0, LinkNumber.int(o["durationMs"]) ?? 0),
                                         overlay: LinkNumber.bool(o["overlay"])))
        case NinoLink.ExtensionType.screenClear:
            self = .screenClear
        case NinoLink.ExtensionType.region:
            let id: String
            if let s = o["id"] as? String { id = s } else if let n = LinkNumber.int(o["id"]) { id = String(n) } else {
                throw NinoMessage.DecodeError.missingField("id")
            }
            self = .region(RegionPayload(id: id, text: o["text"] as? String ?? "", box: NinoBox(json: o["box"]),
                                         line: LinkNumber.double(o["line"]), icons: LinkIcon.decode(o["icons"])))
        case NinoLink.ExtensionType.regionClear:
            self = .regionClear
        default:
            return nil
        }
    }

    public init?(string: String) throws { try self.init(data: Data(string.utf8)) }
}

// MARK: show ek alanları

extension ShowPayload {
    /// Ek alanları JSON'a ekler (boş olanlar eklenmez; eski mesajlar aynı kalır).
    func appendExtensions(to o: inout [String: Any]) {
        o["box"] = box?.jsonObject
        o["paragraphs"] = paragraphs
        o["replace"] = replace
        o["light"] = light.map { LinkNumber.unit($0, 2) }
        o["cover"] = cover
        o["speaker"] = speaker.flatMap(Self.cleanSpeaker)
        o["icons"] = LinkIcon.encode(icons)
    }

    /// Konuşan adının en uzun boyu (karakter); uzunu kırpılır.
    public static let speakerMaxLength = 60

    static func cleanSpeaker(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : String(t.prefix(speakerMaxLength))
    }

    /// Adı bilmeyen gösterici için tek metin: `"Ad: text"` (metin zaten adla başlıyorsa olduğu gibi).
    public var textWithSpeaker: String {
        let text = readableText
        guard let name = speaker.flatMap(Self.cleanSpeaker) else { return text }
        if text.hasPrefix(name + ":") || text.hasPrefix(name + "：") { return text }
        return "\(name): \(text)"
    }

    /// Simgeyi bilmeyen gösterici için metin: `⟦T1⟧` yer tutucuları okunur metne döner (`[→]`).
    public var readableText: String { IconPlaceholders.readable(text, icons: icons) }

    mutating func readExtensions(from o: [String: Any]) {
        box = NinoBox(json: o["box"])
        paragraphs = LinkNumber.bool(o["paragraphs"])
        replace = LinkNumber.bool(o["replace"])
        light = LinkNumber.double(o["light"])
        cover = (o["cover"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        speaker = (o["speaker"] as? String).flatMap(Self.cleanSpeaker)
        icons = LinkIcon.decode(o["icons"])
    }

    /// `cover` görselinin baytları (base64 çözülmüş).
    public var coverData: Data? { cover.flatMap { Data(base64Encoded: $0) } }

    /// Mesaj sınırını aşacaksa `cover`'ı atılmış hali; sığıyorsa kendisi.
    public func fittingLimit(_ limit: Int = NinoLink.maxMessageBytes) -> ShowPayload {
        guard cover != nil, NinoMessage.show(self).encoded().count > limit else { return self }
        var p = self
        p.cover = nil
        return p
    }
}

// MARK: info

/// `info` cevabı, uzantı alanlarıyla (`model`, `appVersion`, `role`).
/// `NinoMessage.info` aynı JSON'un uzantısız halidir.
public struct NinoInfo: Equatable, Sendable {
    public var version: Int
    public var versions: [Int]
    public var name: String
    public var id: String
    /// TV markası ve modeli.
    public var model: String?
    /// Karşı tarafın uygulama sürümü. (`app` zarf alanı olduğu için bu ad.)
    public var appVersion: String?
    /// `"sender"`: cevap veren bir göndericidir (TV değil).
    public var role: String?

    public init(version: Int = NinoLink.version, versions: [Int] = NinoLink.supportedVersions, name: String, id: String,
                model: String? = nil, appVersion: String? = nil, role: String? = nil) {
        self.version = version
        self.versions = versions
        self.name = name
        self.id = id
        self.model = model
        self.appVersion = appVersion
        self.role = role
    }

    public var isSender: Bool { role == NinoLink.senderRole }

    public var message: NinoMessage { .info(version: version, versions: versions, name: name, id: id) }

    public func jsonObject() -> [String: Any] {
        var o = message.jsonObject()
        o["model"] = model
        o["appVersion"] = appVersion
        o["role"] = role
        return o
    }

    public func encoded() -> Data { LinkNumber.encode(jsonObject()) }

    public init(data: Data) throws {
        guard case let .info(v, vs, name, id) = try NinoMessage(data: data) else { throw NinoMessage.DecodeError.missingField("type") }
        let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        self.init(version: v, versions: vs, name: name, id: id, model: o["model"] as? String,
                  appVersion: o["appVersion"] as? String, role: o["role"] as? String)
    }

    /// `GET /nino/info` ile ek alanlarıyla birlikte okur.
    public static func fetch(host: String, port: UInt16 = NinoLink.defaultPort, session: URLSession = .shared) async throws -> NinoInfo {
        let url = try NinoLink.url(scheme: "http", host: host, port: port, path: NinoLink.Path.info)
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw NinoHTTPClient.ClientError.status(http.statusCode)
        }
        return try NinoInfo(data: data)
    }
}
