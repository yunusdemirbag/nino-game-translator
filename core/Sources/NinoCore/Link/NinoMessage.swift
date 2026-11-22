// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// Nino Bağlantı Protokolü sabitleri (bkz. docs/tarif/protokol.md).
public enum NinoLink {
    public static let version = 1
    public static let supportedVersions = [1]
    public static let defaultPort: UInt16 = 47800
    public static let serviceType = "_nino._tcp"
    /// Tek mesajın üst sınırı (buzlu zemin görseli `cover` için 512 KB; bkz. `compactMessageBytes`).
    public static let maxMessageBytes = 512 * 1024
    public static let handshakeTimeout: TimeInterval = 5
    public static let pingInterval: TimeInterval = 5
    public static let pongTimeout: TimeInterval = 15
    public static let displayIdleTimeout: TimeInterval = 20

    public enum Path {
        public static let info = "/nino/info"
        public static let webSocket = "/nino/ws"
        public static let show = "/nino/show"
        public static let clear = "/nino/clear"
    }

    public enum ErrorCode {
        public static let versionUnsupported = "version_unsupported"
        public static let badHandshake = "bad_handshake"
        public static let badMessage = "bad_message"
        public static let tooLarge = "too_large"
        public static let replaced = "replaced"
        /// Aynı TV kısa sürede yine bağlandı; sağlam eski bağlantı kalıyor, bu bağlantı geri çevrildi.
        public static let duplicate = "duplicate"
    }

    /// Karşı tarafın verdiği sürüm listesinden ortak en büyük sürüm.
    public static func bestCommonVersion(_ theirs: [Int], ours: [Int] = supportedVersions) -> Int? {
        Set(theirs).intersection(ours).max()
    }

    public struct BadAddress: Error, Equatable { public let host: String }

    /// Adres, bağlantı noktası ve yoldan URL kurar. IPv6 köşeli paranteze alınır,
    /// kapsam (`%en0`) `%25en0` olarak kodlanır.
    public static func url(scheme: String, host: String, port: UInt16, path: String) throws -> URL {
        var h = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if !h.contains(":"), let percent = h.firstIndex(of: "%") {
            h = String(h[..<percent]) // IPv4'te kapsam anlamsız.
        } else if h.contains(":") {
            h = "[" + h.replacingOccurrences(of: "%25", with: "%").replacingOccurrences(of: "%", with: "%25") + "]"
        }
        guard !h.isEmpty, let url = URL(string: "\(scheme)://\(h):\(port)\(path)") else { throw BadAddress(host: host) }
        return url
    }

    /// Yerel ağ adresi mi? (özel IPv4 aralıkları, yerel IPv6, geri döngü)
    public static func isLocalAddress(_ host: String) -> Bool {
        var h = host.lowercased()
        if let percent = h.firstIndex(of: "%") { h = String(h[..<percent]) }
        h = h.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if h.hasPrefix("::ffff:") { h = String(h.dropFirst(7)) }

        let parts = h.split(separator: ".", omittingEmptySubsequences: false).compactMap { UInt8($0) }
        if parts.count == 4, h.split(separator: ".", omittingEmptySubsequences: false).count == 4 {
            switch (parts[0], parts[1]) {
            case (10, _), (127, _), (192, 168), (169, 254): return true
            case (172, 16...31): return true
            default: return false
            }
        }
        if h.contains(":") {
            if h == "::1" { return true }
            if h.hasPrefix("fe8") || h.hasPrefix("fe9") || h.hasPrefix("fea") || h.hasPrefix("feb") { return true }
            if h.hasPrefix("fc") || h.hasPrefix("fd") { return true }
        }
        return false
    }
}

/// Altyazının ekrandaki yeri.
public enum SubtitlePosition: String, Codable, Sendable {
    case bottom, top
}

/// `show` mesajının içeriği.
public struct ShowPayload: Equatable, Sendable {
    public var id: Int
    public var text: String
    public var source: String?
    public var position: SubtitlePosition
    /// 0: `clear` gelene kadar kalır.
    public var durationMs: Int
    // Uzantılar (isteğe bağlı; bkz. NinoExtensions.swift).
    /// İngilizce altyazının ekrandaki yeri.
    public var box: NinoBox?
    /// Çok parçalı metin.
    public var paragraphs: Bool?
    /// Önceki satırın düzelmiş okuması: yığma, yerine koy.
    public var replace: Bool?
    /// Sahne aydınlığı 0–1.
    public var light: Double?
    /// base64 JPEG: altyazının arkasının bulanık hali.
    public var cover: String?
    /// Konuşan adı (kaynak satırdan ayrılmış, çevrilmez). Varsa `text` adsızdır; TV adı ayrı çizer.
    /// Eski 8787 yolunda `"Ad: text"` olarak tek metne katılır.
    public var speaker: String?
    /// `text` içindeki `⟦T1⟧` yer tutucularının tuş simgeleri (protokol.md "Tuş simgeleri"). Boşsa alan yazılmaz.
    public var icons: [LinkIcon]?

    public init(id: Int, text: String, source: String? = nil, position: SubtitlePosition = .bottom, durationMs: Int = 0,
                box: NinoBox? = nil, paragraphs: Bool? = nil, replace: Bool? = nil, light: Double? = nil,
                cover: String? = nil, speaker: String? = nil, icons: [LinkIcon]? = nil) {
        self.id = id
        self.text = text
        self.source = source
        self.position = position
        self.durationMs = durationMs
        self.box = box
        self.paragraphs = paragraphs
        self.replace = replace
        self.light = light
        self.cover = cover
        self.speaker = speaker
        self.icons = icons
    }
}

/// Protokoldeki tüm mesajlar.
public enum NinoMessage: Equatable, Sendable {
    case hello(version: Int, device: String?, client: String?)
    case welcome(version: Int, name: String?)
    case info(version: Int, versions: [Int], name: String, id: String)
    case show(ShowPayload)
    case clear(id: Int?)
    case ping(t: Int64)
    case pong(t: Int64)
    case error(code: String, message: String?, versions: [Int]?)
    case ok
    /// Tanınmayan tür; yok sayılır.
    case unknown(type: String)

    public enum DecodeError: Error, Equatable {
        case notJSON
        case notNino
        case missingField(String)
    }

    public var type: String {
        switch self {
        case .hello: return "hello"
        case .welcome: return "welcome"
        case .info: return "info"
        case .show: return "show"
        case .clear: return "clear"
        case .ping: return "ping"
        case .pong: return "pong"
        case .error: return "error"
        case .ok: return "ok"
        case let .unknown(type): return type
        }
    }

    // MARK: JSON

    public func jsonObject() -> [String: Any] {
        var o: [String: Any] = ["app": "nino", "type": type]
        switch self {
        case let .hello(version, device, client):
            o["version"] = version
            o["device"] = device
            o["client"] = client
        case let .welcome(version, name):
            o["version"] = version
            o["name"] = name
        case let .info(version, versions, name, id):
            o["version"] = version
            o["versions"] = versions
            o["name"] = name
            o["id"] = id
        case let .show(p):
            o["id"] = p.id
            o["text"] = p.text
            o["source"] = p.source
            o["position"] = p.position.rawValue
            o["durationMs"] = p.durationMs
            p.appendExtensions(to: &o)
        case let .clear(id):
            o["id"] = id
        case let .ping(t), let .pong(t):
            o["t"] = t
        case let .error(code, message, versions):
            o["code"] = code
            o["message"] = message
            o["versions"] = versions
        case .ok, .unknown:
            break
        }
        return o
    }

    public func encoded() -> Data {
        // Anahtar sırası sabit olsun diye sıralı.
        (try? JSONSerialization.data(withJSONObject: jsonObject(), options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data()
    }

    public var jsonString: String { String(decoding: encoded(), as: UTF8.self) }

    public init(data: Data) throws {
        guard let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { throw DecodeError.notJSON }
        guard (o["app"] as? String) == "nino" else { throw DecodeError.notNino }
        guard let type = o["type"] as? String else { throw DecodeError.missingField("type") }

        func int(_ k: String) -> Int? { (o[k] as? NSNumber).flatMap { CFGetTypeID($0) == CFBooleanGetTypeID() ? nil : $0.intValue } }
        func need<T>(_ v: T?, _ k: String) throws -> T {
            guard let v else { throw DecodeError.missingField(k) }
            return v
        }
        let ints: (String) -> [Int]? = { k in (o[k] as? [Any])?.compactMap { ($0 as? NSNumber)?.intValue } }

        switch type {
        case "hello":
            self = .hello(version: try need(int("version"), "version"), device: o["device"] as? String, client: o["client"] as? String)
        case "welcome":
            self = .welcome(version: try need(int("version"), "version"), name: o["name"] as? String)
        case "info":
            self = .info(version: try need(int("version"), "version"), versions: ints("versions") ?? [],
                         name: o["name"] as? String ?? "", id: o["id"] as? String ?? "")
        case "show":
            let position = (o["position"] as? String).flatMap(SubtitlePosition.init(rawValue:)) ?? .bottom
            var p = ShowPayload(id: try need(int("id"), "id"), text: try need(o["text"] as? String, "text"),
                                source: o["source"] as? String, position: position,
                                durationMs: max(0, int("durationMs") ?? 0))
            p.readExtensions(from: o)
            self = .show(p)
        case "clear":
            self = .clear(id: int("id"))
        case "ping":
            self = .ping(t: Int64(try need(int("t"), "t")))
        case "pong":
            self = .pong(t: Int64(try need(int("t"), "t")))
        case "error":
            self = .error(code: try need(o["code"] as? String, "code"), message: o["message"] as? String, versions: ints("versions"))
        case "ok":
            self = .ok
        default:
            self = .unknown(type: type)
        }
    }

    public init(string: String) throws {
        try self.init(data: Data(string.utf8))
    }
}
