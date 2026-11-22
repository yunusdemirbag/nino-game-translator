// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// Ortak havuza satır gönderen kayıpsız kuyruk. Klasör düzeni eski uygulamayla aynı:
/// `pending.jsonl`, `outbox/`, `parked/`, `state.json`, `rejected.jsonl`.
public actor PoolQueue {
    public struct State: Codable, Equatable, Sendable {
        public var install: String
        public var frozenThrough: Int
        public var failures: Int
        public var nextAttempt: Double
        public var serverRetryAt: Double
        public var app: String
        public var dropped: Int

        init(install: String, app: String) {
            self.install = install
            frozenThrough = 0
            failures = 0
            nextAttempt = 0
            serverRetryAt = 0
            self.app = app
            dropped = 0
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            install = try c.decode(String.self, forKey: .install)
            frozenThrough = try c.decodeIfPresent(Int.self, forKey: .frozenThrough) ?? 0
            failures = try c.decodeIfPresent(Int.self, forKey: .failures) ?? 0
            nextAttempt = try c.decodeIfPresent(Double.self, forKey: .nextAttempt) ?? 0
            serverRetryAt = try c.decodeIfPresent(Double.self, forKey: .serverRetryAt) ?? 0
            app = try c.decodeIfPresent(String.self, forKey: .app) ?? ""
            dropped = try c.decodeIfPresent(Int.self, forKey: .dropped) ?? 0
        }
    }

    struct Pending: Codable, Equatable {
        var s: Int
        var t: String
        var g: String?
        var e: String?
        var a: Int
    }

    public struct Batch: Codable, Equatable, Sendable {
        public struct Line: Codable, Equatable, Sendable {
            public var text: String
            public var game: String?
            public var session: String?
            public var count: Int
            public var first: Int
            public var last: Int
        }

        public var v: Int
        public var batch: String
        public var install: String
        public var app: String
        public var platform: String
        public var lines: [Line]
        public var upTo: Int
    }

    /// Bir gönderme turunun sonucu.
    public struct RoundResult: Equatable, Sendable {
        public var sent = 0
        public var parked = 0
        public var split = 0
        public var failed = false
        public var serverBusy = false
    }

    public static let sendAtLines = 200
    public static let sendAtAge: TimeInterval = 120
    public static let batchLines = 200
    public static let maxOutbox = 2000
    public static let maxPendingBytes = 64 << 20
    public static let maxRejectedBytes = 1 << 20

    public let directory: URL
    public let session: String
    private let configuration: PoolConfiguration
    private let transport: PoolTransport
    private let environment: PoolEnvironment
    private let filter: PoolFilter
    public private(set) var state: State
    private var pending: [Pending]
    private var nextSequence: Int
    private var pendingBytes: Int

    var outboxDirectory: URL { directory.appendingPathComponent("outbox", isDirectory: true) }
    var parkedDirectory: URL { directory.appendingPathComponent("parked", isDirectory: true) }
    var pendingFile: URL { directory.appendingPathComponent("pending.jsonl") }
    var stateFile: URL { directory.appendingPathComponent("state.json") }
    var rejectedFile: URL { directory.appendingPathComponent("rejected.jsonl") }

    /// `directory`: `pool/` klasörü. `legacyQueueFile`: eski `pool.json` (varsa bir kez aktarılır).
    public init(directory: URL, configuration: PoolConfiguration, transport: PoolTransport,
                environment: PoolEnvironment = PoolEnvironment(), filter: PoolFilter = PoolFilter(),
                legacyQueueFile: URL? = nil) {
        self.directory = directory
        self.configuration = configuration
        self.transport = transport
        self.environment = environment
        self.filter = filter
        session = environment.uuid().uuidString.lowercased()
        let opened = Self.open(directory: directory, appVersion: configuration.appVersion,
                               environment: environment, legacyQueueFile: legacyQueueFile)
        state = opened.state
        pending = opened.pending
        pendingBytes = opened.bytes
        nextSequence = max(opened.state.frozenThrough, opened.pending.map(\.s).max() ?? 0) + 1
    }

    public var pendingCount: Int { pending.count }
    public var install: String { state.install }

    public func outboxFiles() -> [String] { Self.jsonFiles(in: outboxDirectory) }
    public func parkedFiles() -> [String] { Self.jsonFiles(in: parkedDirectory) }

    // MARK: Kayıt

    /// Görülen satırı kuyruğa ekler. Süzgeçten geçmezse ya da havuz kapalıysa `false`.
    @discardableResult
    public func record(_ text: String, game: String? = nil) -> Bool {
        guard configuration.enabled, let line = filter.prepare(text) else { return false }
        let item = Pending(s: nextSequence, t: line, g: game.flatMap(GameIDs.id), e: session,
                           a: Int(environment.now().timeIntervalSince1970))
        guard let data = try? JSONEncoder.pool.encode(item) else { return false }
        let row = data + Data("\n".utf8)
        guard pendingBytes + row.count <= Self.maxPendingBytes else {
            state.dropped += 1
            saveState()
            return false
        }
        guard Self.append(row, to: pendingFile) else { return false }
        pending.append(item)
        pendingBytes += row.count
        nextSequence += 1
        return true
    }

    /// Bekleyenler dondurulmalı mı (≥ 200 satır ya da en eskisi ≥ 120 sn)?
    public func freezeIsDue() -> Bool {
        guard let oldest = pending.map(\.a).min() else { return false }
        return pending.count >= Self.sendAtLines
            || environment.now().timeIntervalSince1970 - Double(oldest) >= Self.sendAtAge
    }

    // MARK: Dondurma

    /// Bekleyenleri ≤ 200 farklı satırlık parçalara böler ve `outbox/`'a yazar.
    public func freeze() {
        guard !pending.isEmpty else { return }
        let fm = FileManager.default
        try? fm.createDirectory(at: outboxDirectory, withIntermediateDirectories: true)
        var outboxCount = outboxFiles().count
        let sorted = pending.sorted { $0.s < $1.s }
        let ms = Int(environment.now().timeIntervalSince1970 * 1000)
        var chunkIndex = 0
        var lines: [Batch.Line] = []
        var positions: [String: Int] = [:]
        var upTo = 0

        func flush() -> Bool {
            guard !lines.isEmpty else { return true }
            guard outboxCount < Self.maxOutbox else { return false }
            let id = environment.uuid().uuidString.lowercased()
            let batch = Batch(v: 1, batch: id, install: state.install, app: configuration.appVersion,
                              platform: configuration.platform, lines: lines, upTo: upTo)
            let name = Self.pad(ms, 15) + "-" + Self.pad(chunkIndex % 10_000, 4) + "-\(id).json"
            guard let data = try? JSONEncoder.pool.encode(batch),
                  (try? data.write(to: outboxDirectory.appendingPathComponent(name), options: .atomic)) != nil else { return false }
            state.frozenThrough = max(state.frozenThrough, upTo)
            saveState()
            outboxCount += 1
            chunkIndex += 1
            lines = []
            positions = [:]
            return true
        }

        var stopped = false
        for item in sorted {
            // Eski sürümün kuyruğa yazdığı takma adlı kimlik de asıl kimlikle gider.
            let game = item.g.flatMap(GameIDs.id)
            let id = "\(game ?? "")\u{1F}\(item.e ?? "")\u{1F}\(item.t)"
            if let p = positions[id] {
                lines[p].count += 1
                lines[p].first = min(lines[p].first, item.a)
                lines[p].last = max(lines[p].last, item.a)
            } else {
                if lines.count == Self.batchLines, !flush() { stopped = true; break }
                positions[id] = lines.count
                lines.append(.init(text: item.t, game: game, session: item.e, count: 1, first: item.a, last: item.a))
            }
            upTo = item.s
        }
        if !stopped { _ = flush() }
        pending.removeAll { $0.s <= state.frozenThrough }
        rewritePending()
    }

    // MARK: Gönderme

    /// Zamanı geldiyse dondurur, sonra `outbox/`'taki parçaları sırayla bir kez dener.
    public func run() async -> RoundResult {
        if freezeIsDue() { freeze() }
        return await sendRound()
    }

    public func sendRound() async -> RoundResult {
        var result = RoundResult()
        guard configuration.enabled, configuration.baseURL != nil else { return result }
        for name in outboxFiles() {
            let now = environment.now().timeIntervalSince1970
            guard state.nextAttempt <= now, state.serverRetryAt <= now else { break }
            let url = outboxDirectory.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: url), let batch = try? JSONDecoder().decode(Batch.self, from: data) else {
                park(name)
                result.parked += 1
                continue
            }
            guard let request = configuration.request("/v1/batches", method: "POST", body: data, timeout: 30) else { break }
            let response: (Data, HTTPURLResponse)
            do { response = try await transport.send(request) } catch {
                fail()
                result.failed = true
                break
            }
            let (body, http) = response
            switch http.statusCode {
            case 200..<300:
                let reply = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
                guard reply?["ok"] as? Bool == true, reply?["batch"] as? String == batch.batch else {
                    fail()
                    result.failed = true
                    break
                }
                for r in (reply?["rejected"] as? [[String: Any]]) ?? [] {
                    guard let i = (r["i"] as? NSNumber)?.intValue, batch.lines.indices.contains(i) else { continue }
                    logRejected(text: batch.lines[i].text, reason: r["reason"] as? String ?? "")
                }
                try? FileManager.default.removeItem(at: url)
                state.failures = 0
                state.nextAttempt = 0
                result.sent += 1
            case 413:
                if batch.lines.count > 1 {
                    split(batch, name: name)
                    result.split += 1
                } else {
                    park(name)
                    result.parked += 1
                }
            case 429, 503:
                state.serverRetryAt = environment.now().timeIntervalSince1970
                    + Self.retryAfter(http.value(forHTTPHeaderField: "Retry-After"), now: environment.now())
                result.serverBusy = true
            case 400, 422:
                park(name)
                result.parked += 1
            default:
                fail()
                result.failed = true
            }
            if result.failed || result.serverBusy { break }
        }
        saveState()
        return result
    }

    /// Ağ geri geldi: artan bekleme sıfırlanır.
    public func networkRestored() {
        state.failures = 0
        state.nextAttempt = 0
        saveState()
    }

    /// Ortak havuz kapatıldı: bekleyen, gönderilecek ve kenara alınmış her şey silinir.
    public func clear() {
        let fm = FileManager.default
        for dir in [outboxDirectory, parkedDirectory] {
            for name in (try? fm.contentsOfDirectory(atPath: dir.path)) ?? [] {
                try? fm.removeItem(at: dir.appendingPathComponent(name))
            }
        }
        try? fm.removeItem(at: pendingFile)
        pending = []
        pendingBytes = 0
        state.failures = 0
        state.nextAttempt = 0
        saveState()
    }

    // MARK: İç işler

    private func fail() {
        state.failures += 1
        let base = min(3600, 30 * pow(2, Double(state.failures - 1)))
        state.nextAttempt = environment.now().timeIntervalSince1970 + base * (1 + environment.jitter())
    }

    private func park(_ name: String) {
        let fm = FileManager.default
        try? fm.createDirectory(at: parkedDirectory, withIntermediateDirectories: true)
        let target = parkedDirectory.appendingPathComponent(name)
        try? fm.removeItem(at: target)
        try? fm.moveItem(at: outboxDirectory.appendingPathComponent(name), to: target)
    }

    private func split(_ batch: Batch, name: String) {
        let parts = name.split(separator: "-", maxSplits: 2)
        let prefix = parts.count >= 2 ? "\(parts[0])-\(parts[1])" : "000000000000000-0000"
        let half = batch.lines.count / 2
        for lines in [Array(batch.lines[..<half]), Array(batch.lines[half...])] {
            var b = batch
            b.batch = environment.uuid().uuidString.lowercased()
            b.lines = lines
            if let data = try? JSONEncoder.pool.encode(b) {
                try? data.write(to: outboxDirectory.appendingPathComponent("\(prefix)-\(b.batch).json"), options: .atomic)
            }
        }
        try? FileManager.default.removeItem(at: outboxDirectory.appendingPathComponent(name))
    }

    private func logRejected(text: String, reason: String) {
        let size = (try? FileManager.default.attributesOfItem(atPath: rejectedFile.path)[.size] as? Int) ?? 0
        if size > Self.maxRejectedBytes { try? FileManager.default.removeItem(at: rejectedFile) }
        struct Row: Encodable { var reason: String; var text: String }
        if let data = try? JSONEncoder.pool.encode(Row(reason: reason, text: text)) {
            _ = Self.append(data + Data("\n".utf8), to: rejectedFile)
        }
    }

    private func saveState() {
        if let data = try? JSONEncoder.pool.encode(state) { try? data.write(to: stateFile, options: .atomic) }
    }

    private func rewritePending() {
        var data = Data()
        for p in pending { if let d = try? JSONEncoder.pool.encode(p) { data += d + Data("\n".utf8) } }
        try? data.write(to: pendingFile, options: .atomic)
        pendingBytes = data.count
    }

    static func append(_ data: Data, to url: URL) -> Bool {
        if !FileManager.default.fileExists(atPath: url.path) {
            return (try? data.write(to: url, options: .atomic)) != nil
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return false }
        defer { try? handle.close() }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            return true
        } catch { return false }
    }

    static func pad(_ n: Int, _ width: Int) -> String {
        let s = String(n)
        return String(repeating: "0", count: max(0, width - s.count)) + s
    }

    static func jsonFiles(in dir: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
            .filter { $0.hasSuffix(".json") && !$0.hasPrefix(".") }.sorted()
    }

    /// `Retry-After`: saniye ya da HTTP tarihi; yoksa 60 sn; 1 sn–1 gün.
    static func retryAfter(_ header: String?, now: Date) -> TimeInterval {
        guard let h = header?.trimmingCharacters(in: .whitespaces), !h.isEmpty else { return 60 }
        var seconds: TimeInterval?
        if let n = Double(h) {
            seconds = n
        } else {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone(identifier: "GMT")
            f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
            seconds = f.date(from: h).map { $0.timeIntervalSince(now) }
        }
        guard let s = seconds else { return 60 }
        return min(86_400, max(1, s))
    }

    // MARK: Açılış

    static func open(directory: URL, appVersion: String, environment: PoolEnvironment,
                     legacyQueueFile: URL?) -> (state: State, pending: [Pending], bytes: Int) {
        let fm = FileManager.default
        let outbox = directory.appendingPathComponent("outbox", isDirectory: true)
        let parked = directory.appendingPathComponent("parked", isDirectory: true)
        for d in [directory, outbox, parked] { try? fm.createDirectory(at: d, withIntermediateDirectories: true) }
        let stateFile = directory.appendingPathComponent("state.json")
        let pendingFile = directory.appendingPathComponent("pending.jsonl")
        let unix = Int(environment.now().timeIntervalSince1970)

        // Eski kuyruk dosyası
        var legacyInstall: String?
        var legacyLines: [(String, String?, Int)] = []
        if let legacyQueueFile, let data = try? Data(contentsOf: legacyQueueFile) {
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            legacyInstall = (object?["install"] as? String).flatMap { UUID(uuidString: $0) != nil ? $0.lowercased() : nil }
            for item in (object?["queue"] as? [[String: Any]]) ?? [] {
                let text = PoolFilter.clean(item["text"] as? String ?? "")
                guard !text.isEmpty else { continue }
                let game = ((item["game"] as? String) ?? (item["titleId"] as? String)).flatMap(GameIDs.id)
                var seen = (item["firstSeen"] as? NSNumber)?.doubleValue ?? Double(unix)
                if seen > 100_000_000_000 { seen /= 1000 }
                legacyLines.append((text, game, Int(seen)))
            }
        }

        var state: State
        if let data = try? Data(contentsOf: stateFile) {
            if let s = try? JSONDecoder().decode(State.self, from: data), UUID(uuidString: s.install) != nil {
                state = s
            } else {
                try? fm.moveItem(at: stateFile, to: directory.appendingPathComponent("state.broken-\(unix).json"))
                state = State(install: environment.uuid().uuidString.lowercased(), app: appVersion)
            }
        } else {
            state = State(install: legacyInstall ?? environment.uuid().uuidString.lowercased(), app: appVersion)
        }

        // Yarım kalmış son satır kesilir.
        var raw = (try? Data(contentsOf: pendingFile)) ?? Data()
        if let last = raw.last, last != UInt8(ascii: "\n") {
            if let cut = raw.lastIndex(of: UInt8(ascii: "\n")) { raw = raw[...cut] } else { raw = Data() }
            try? Data(raw).write(to: pendingFile, options: .atomic)
        }
        var pending: [Pending] = []
        for row in raw.split(separator: UInt8(ascii: "\n")) {
            if let p = try? JSONDecoder().decode(Pending.self, from: Data(row)) { pending.append(p) }
        }

        // Diskteki parçaların en büyük `upTo`'su.
        for dir in [outbox, parked] {
            for name in jsonFiles(in: dir) {
                if let data = try? Data(contentsOf: dir.appendingPathComponent(name)),
                   let upTo = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["upTo"] as? NSNumber {
                    state.frozenThrough = max(state.frozenThrough, upTo.intValue)
                }
            }
        }
        let before = pending.count
        pending.removeAll { $0.s <= state.frozenThrough }
        var changed = pending.count != before

        // Sürüm değiştiyse kenara alınanlar yeniden denenir.
        if state.app != appVersion {
            for name in jsonFiles(in: parked) {
                try? fm.moveItem(at: parked.appendingPathComponent(name), to: outbox.appendingPathComponent(name))
            }
            state.app = appVersion
        }
        state.failures = 0
        state.nextAttempt = 0

        if !legacyLines.isEmpty, let legacyQueueFile {
            var seq = max(state.frozenThrough, pending.map(\.s).max() ?? 0)
            for (text, game, seen) in legacyLines {
                seq += 1
                pending.append(Pending(s: seq, t: text, g: game, e: nil, a: seen))
            }
            changed = true
            let imported = legacyQueueFile.deletingLastPathComponent()
                .appendingPathComponent(legacyQueueFile.lastPathComponent + ".imported")
            try? fm.removeItem(at: imported)
            try? fm.moveItem(at: legacyQueueFile, to: imported)
        } else if let legacyQueueFile, fm.fileExists(atPath: legacyQueueFile.path) {
            let imported = legacyQueueFile.deletingLastPathComponent()
                .appendingPathComponent(legacyQueueFile.lastPathComponent + ".imported")
            if !fm.fileExists(atPath: imported.path) { try? fm.moveItem(at: legacyQueueFile, to: imported) }
        }

        var bytes = raw.count
        if changed {
            var data = Data()
            for p in pending { if let d = try? JSONEncoder.pool.encode(p) { data += d + Data("\n".utf8) } }
            try? data.write(to: pendingFile, options: .atomic)
            bytes = data.count
        }
        if let data = try? JSONEncoder.pool.encode(state) { try? data.write(to: stateFile, options: .atomic) }
        return (state, pending, bytes)
    }
}
