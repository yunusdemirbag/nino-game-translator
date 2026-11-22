// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// Sunucunun uzak ayarı (`/v1/config`). Ulaşılamazsa ya da alan eksikse varsayılan kalır.
public struct PoolRemoteConfig: Equatable, Sendable {
    public var translateEnabled = true
    public var deadlineMs = 900
    public var syncSeconds = 180
    public var contextLines = 4
    public var maxLines = 12
    public var poolFirstGames = ["grand-theft-auto-vi", "gta-vi", "gta-6", "gta6"]
    public var poolFirstLanguages = ["tr"]
    public var poolFirstDeadlineMs = 1500

    public init() {}

    /// Kimlik havuz öncelikli listede mi? İki yan da asıl kimliğe çevrilir (listede yalnız takma ad olsa da eşleşir);
    /// eski davranış gibi kimliğin içinde geçmesi de sayılır.
    public func isPoolFirstGame(_ id: String) -> Bool {
        let game = GameIDs.canonical(id)
        guard !game.isEmpty else { return false }
        return poolFirstGames.contains { entry in
            let e = GameIDs.canonical(entry)
            return !e.isEmpty && (game.contains(e) || game.contains(entry.lowercased()))
        }
    }

    mutating func apply(_ json: [String: Any]) {
        if let t = json["translate"] as? [String: Any] {
            if let v = t["enabled"] as? Bool { translateEnabled = v }
            if let v = (t["deadlineMs"] as? NSNumber)?.intValue { deadlineMs = v }
            if let v = (t["syncSeconds"] as? NSNumber)?.intValue { syncSeconds = v }
            if let v = (t["contextLines"] as? NSNumber)?.intValue { contextLines = v }
            if let v = (t["maxLines"] as? NSNumber)?.intValue { maxLines = v }
        }
        if let p = json["poolFirst"] as? [String: Any] {
            if let v = p["games"] as? [String] { poolFirstGames = v }
            if let v = p["langs"] as? [String] { poolFirstLanguages = v }
            if let v = (p["deadlineMs"] as? NSNumber)?.intValue { poolFirstDeadlineMs = v }
        }
    }
}

/// Havuzdan inen çeviriler (dil başına bir dosya) ve oyun başına indirme imleçleri.
public actor PoolTranslations {
    public struct Cursor: Codable, Equatable, Sendable {
        public var since: Double = 0
        public var after: String = ""
        public var checked: Double = 0
    }

    public static let maxTexts = 400_000

    /// Veri klasörü; dosya `translations/translations-<dil>.json` (okurken `Translations/` da aranır).
    public let root: URL
    public private(set) var language: String
    private var texts: [UInt64: String] = [:]
    private(set) var cursors: [String: Cursor] = [:]
    private var dirty = false

    public init(root: URL, language: String) {
        self.root = root
        self.language = language
        let loaded = Self.load(root: root, language: language)
        texts = loaded.texts
        cursors = loaded.cursors
    }

    public var count: Int { texts.count }

    public func text(for key: UInt64) -> String? { texts[key] }

    public func lookup(_ sentence: String) -> String? { LineKey.key(sentence).flatMap { texts[$0] } }

    public func add(key: UInt64, text: String) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, texts[key] != clean else { return }
        texts[key] = clean
        dirty = true
    }

    public func cursor(for game: String?) -> Cursor { cursors[game ?? ""] ?? Cursor() }

    func setCursor(_ c: Cursor, for game: String?) {
        cursors[game ?? ""] = c
        dirty = true
    }

    /// Hedef dil değişti: eldeki yazılır, yeni dilin dosyası yüklenir.
    public func switchLanguage(_ newLanguage: String) {
        guard newLanguage != language else { return }
        save()
        language = newLanguage
        let loaded = Self.load(root: root, language: newLanguage)
        texts = loaded.texts
        cursors = loaded.cursors
        dirty = false
    }

    public var fileURL: URL { Self.file(root: root, folder: "translations", language: language) }

    /// Değişiklik varsa yazar (en çok 400 000 çeviri).
    public func save() {
        guard dirty else { return }
        var out: [String: String] = [:]
        for key in texts.keys.sorted().prefix(Self.maxTexts) { out[LineKey.hex(key)] = texts[key] }
        struct File: Encodable { var language: String; var texts: [String: String]; var cursors: [String: Cursor] }
        guard let data = try? JSONEncoder.pool.encode(File(language: language, texts: out, cursors: cursors)) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if (try? data.write(to: fileURL, options: .atomic)) != nil { dirty = false }
    }

    static func file(root: URL, folder: String, language: String) -> URL {
        root.appendingPathComponent(folder, isDirectory: true).appendingPathComponent("translations-\(language).json")
    }

    static func load(root: URL, language: String) -> (texts: [UInt64: String], cursors: [String: Cursor]) {
        for folder in ["translations", "Translations"] {
            guard let data = try? Data(contentsOf: file(root: root, folder: folder, language: language)),
                  let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { continue }
            var texts: [UInt64: String] = [:]
            for (hex, v) in (object["texts"] as? [String: Any]) ?? [:] {
                if let k = LineKey.parse(hex), let t = v as? String, !t.isEmpty { texts[k] = t }
            }
            var cursors: [String: Cursor] = [:]
            for (game, v) in (object["cursors"] as? [String: Any]) ?? [:] {
                guard let c = v as? [String: Any] else { continue }
                cursors[game] = Cursor(since: (c["since"] as? NSNumber)?.doubleValue ?? 0,
                                       after: c["after"] as? String ?? "",
                                       checked: (c["checked"] as? NSNumber)?.doubleValue ?? 0)
            }
            return (texts, cursors)
        }
        return ([:], [:])
    }
}

/// Ortak havuzun çeviri tarafı: uzak ayar, havuz önceliği, toplu indirme, anında soru, "buradayım".
public actor PoolClient {
    nonisolated public let configuration: PoolConfiguration
    nonisolated public let translations: PoolTranslations
    nonisolated public let install: String
    private let transport: PoolTransport
    private let environment: PoolEnvironment
    private let filter: PoolFilter
    public private(set) var remote = PoolRemoteConfig()
    private var configCheckedAt: Date?
    private var serverGame: (id: String, at: Date)?
    private var inFlight: [String: Task<String?, Never>] = [:]
    private var context: [(text: String, at: Date)] = []

    public static let configInterval: TimeInterval = 600
    public static let serverGameMemory: TimeInterval = 600
    public static let maxPages = 50
    /// Sunucu (`TRANSLATE_LIMITS.maxText`) daha uzun satırı çevirmez (`text: null`); hiç sorulmaz.
    public static let maxAskCharacters = 300

    public init(configuration: PoolConfiguration, transport: PoolTransport, translations: PoolTranslations,
                install: String, environment: PoolEnvironment = PoolEnvironment(), filter: PoolFilter = PoolFilter()) {
        self.configuration = configuration
        self.transport = transport
        self.translations = translations
        self.install = install
        self.environment = environment
        self.filter = filter
    }

    // MARK: Uzak ayar

    /// En çok 10 dk'da bir `/v1/config` okur. Ulaşılamazsa eldeki ayar kalır.
    public func refreshConfig(force: Bool = false) async {
        let now = environment.now()
        if !force, let at = configCheckedAt, now.timeIntervalSince(at) < Self.configInterval { return }
        guard let request = configuration.request("/v1/config", timeout: 30) else { return }
        configCheckedAt = now
        guard let (data, http) = try? await transport.send(request), http.statusCode == 200,
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              json["ok"] as? Bool == true else { return }
        remote.apply(json)
    }

    /// Bu oyun havuz öncelikli mi (GTA 6 gibi)?
    public func isPoolFirst(game: String?, language: String) -> Bool {
        guard remote.translateEnabled, configuration.baseURL != nil else { return false }
        let lang = Self.baseLanguage(language)
        guard remote.poolFirstLanguages.contains(where: { $0 == "*" || Self.baseLanguage($0) == lang }) else { return false }
        if let id = game.flatMap(GameIDs.id), remote.isPoolFirstGame(id) {
            return true
        }
        if let s = serverGame, environment.now().timeIntervalSince(s.at) <= Self.serverGameMemory, remote.isPoolFirstGame(s.id) {
            return true
        }
        return false
    }

    /// Adaylardan oyun: listede olan ilk aday, yoksa ilk aday.
    public func chooseGame(_ candidates: [String]) -> String? {
        let ids = candidates.compactMap(GameIDs.id)
        return ids.first { remote.isPoolFirstGame($0) } ?? ids.first
    }

    static func baseLanguage(_ code: String) -> String {
        String(code.lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" }).first ?? "")
    }

    // MARK: Toplu indirme

    /// Oyunun havuz çevirilerini indirir. Oyun başına en erken `max(30, syncSeconds)` sn'de bir.
    /// Dönen: eklenen çeviri sayısı.
    @discardableResult
    public func sync(game: String?, force: Bool = false) async -> Int {
        guard configuration.enabled, configuration.baseURL != nil else { return 0 }
        let gameID = game.flatMap(GameIDs.id)
        let language = await translations.language
        var cursor = await translations.cursor(for: gameID)
        let now = environment.now().timeIntervalSince1970
        if !force, now - cursor.checked < Double(max(30, remote.syncSeconds)) { return 0 }

        var added = 0
        var maxUpdated = cursor.since
        var finished = false
        for _ in 0..<Self.maxPages {
            var query = [("lang", language), ("since", Self.number(cursor.since))]
            if let gameID { query.append(("game", gameID)) }
            if !cursor.after.isEmpty { query.append(("after", cursor.after)) }
            guard let request = configuration.request("/v1/translations", query: query, timeout: 30),
                  let (data, http) = try? await transport.send(request), http.statusCode == 200,
                  let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  json["ok"] as? Bool == true else { break }
            // Dil bu arada değiştiyse cevap atılır.
            guard await translations.language == language else { return added }
            for case let row as [Any] in (json["items"] as? [Any]) ?? [] {
                guard row.count >= 3, let hex = row[0] as? String, let key = LineKey.parse(hex),
                      let text = row[1] as? String, let updated = (row[2] as? NSNumber)?.doubleValue else { continue }
                if await translations.text(for: key) != text.trimmingCharacters(in: .whitespacesAndNewlines) {
                    await translations.add(key: key, text: text)
                    added += 1
                }
                maxUpdated = max(maxUpdated, updated)
            }
            if let next = json["next"] as? [String: Any] {
                cursor.since = (next["since"] as? NSNumber)?.doubleValue ?? cursor.since
                cursor.after = next["after"] as? String ?? ""
            } else {
                cursor.since = maxUpdated
                cursor.after = ""
                finished = true
                break
            }
        }
        if finished { cursor.checked = now }
        await translations.setCursor(cursor, for: gameID)
        if added > 0 || finished { await translations.save() }
        return added
    }

    /// Dakikada bir "buradayım"; cevap okunmaz.
    public func ping(game: String?) async {
        guard configuration.enabled else { return }
        let language = await translations.language
        let query = [("install", install), ("platform", configuration.platform), ("app", configuration.appVersion),
                     ("game", game.flatMap(GameIDs.id) ?? ""), ("lang", language)]
        guard let request = configuration.request("/v1/ping", query: query, timeout: 15) else { return }
        _ = try? await transport.send(request)
    }

    // MARK: Anında soru

    /// Ekranda görülen satırı bağlam listesine ekler (en çok 4, aynı metin yinelenmez).
    public func noteSeen(_ line: String) {
        let text = PoolFilter.clean(line)
        guard !text.isEmpty else { return }
        context.removeAll { $0.text == text }
        context.append((text, environment.now()))
        if context.count > 4 { context.removeFirst(context.count - 4) }
    }

    /// Satırı sunucuya sorar. `deadline` verilirse süre dolunca `nil` döner ama istek sürer,
    /// geç gelen cevap depoya yine yazılır. `poolFirst`: havuz kapalıyken de sorulur.
    public func ask(_ line: String, game: String?, poolFirst: Bool = false, deadline: Duration? = nil) async -> String? {
        guard configuration.enabled || poolFirst, remote.translateEnabled, configuration.baseURL != nil,
              let text = filter.prepare(line), text.unicodeScalars.count <= Self.maxAskCharacters,
              let key = LineKey.key(text) else { return nil }
        if let known = await translations.text(for: key) { return known }
        let language = await translations.language
        let flightKey = "\(language)\u{1F}\(key)"
        let task: Task<String?, Never>
        if let existing = inFlight[flightKey] {
            task = existing
        } else {
            let body = makeBody(text, game: game, language: language)
            task = Task { await self.performAsk(body: body, key: key, flightKey: flightKey) }
            inFlight[flightKey] = task
        }
        guard let deadline else { return await task.value }
        // Süre dolunca beklemeyi bırak; istek arka planda sürer.
        return await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            let once = ResumeOnce(continuation)
            Task { once.resume(await task.value) }
            Task {
                try? await Task.sleep(for: deadline)
                once.resume(nil)
            }
        }
    }

    /// Havuz öncelikli oyun için süre: `poolFirst.deadlineMs` 100–10 000 arasına sıkıştırılır.
    public var poolFirstDeadline: Duration { .milliseconds(min(10_000, max(100, remote.poolFirstDeadlineMs))) }

    private func makeBody(_ text: String, game: String?, language: String) -> Data? {
        let cutoff = environment.now().addingTimeInterval(-30)
        let ctx = context.filter { $0.at >= cutoff && $0.text != text }.suffix(max(0, remote.contextLines)).map(\.text)
        struct Body: Encodable {
            var v = 1
            var install, app, platform, lang, game: String
            var lines: [String]
            var context: [String]
        }
        return try? JSONEncoder.pool.encode(Body(install: install, app: configuration.appVersion, platform: configuration.platform,
                                                 lang: language, game: game.flatMap(GameIDs.id) ?? "", lines: [text], context: ctx))
    }

    private func performAsk(body: Data?, key: UInt64, flightKey: String) async -> String? {
        defer { inFlight[flightKey] = nil }
        guard let body, let request = configuration.request("/v1/translate", method: "POST", body: body, timeout: 20),
              let (data, http) = try? await transport.send(request), http.statusCode == 200,
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              json["ok"] as? Bool == true else { return nil }
        if let g = json["game"] as? String, let id = GameIDs.id(g) { serverGame = (id, environment.now()) }
        guard let first = (json["translations"] as? [Any])?.first as? [String: Any],
              let text = (first["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        await translations.add(key: key, text: text)
        return text
    }

    static func number(_ d: Double) -> String {
        d == d.rounded() && abs(d) < 1e18 ? String(Int64(d)) : String(d)
    }
}

/// Bir devamı yalnız bir kez sürdürür.
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String?, Never>?

    init(_ c: CheckedContinuation<String?, Never>) { continuation = c }

    func resume(_ value: String?) {
        let c = lock.withLock { () -> CheckedContinuation<String?, Never>? in
            defer { continuation = nil }
            return continuation
        }
        c?.resume(returning: value)
    }
}
