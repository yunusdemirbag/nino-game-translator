// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import CryptoKit
import Foundation

/// Sunucudaki oyun paketlerini indirir; kullanıcının elle bıraktığı dosyaya dokunmaz.
public actor PackUpdater {
    public struct RemotePack: Codable, Equatable, Sendable {
        public var id: String
        public var title: String
        public var version: Int
        public var sha256: String

        public init(id: String, title: String, version: Int, sha256: String) {
            self.id = id
            self.title = title
            self.version = version
            self.sha256 = sha256
        }
    }

    public struct Status: Codable, Equatable, Sendable {
        public var checked: Double = 0
        public var packs: [RemotePack] = []
    }

    public enum Reason: Sendable { case launch, periodic, newGame }

    public struct Result: Equatable, Sendable {
        public var downloaded: [String] = []
        public var removed: [String] = []
        public var failed: [String] = []
        /// Kullanıcının dosyası olduğu için yazılmayanlar.
        public var userFiles: [String] = []
        public var listFailed = false
        /// Kütüphane yeniden okunmalı mı?
        public var changed: Bool { !downloaded.isEmpty || !removed.isEmpty }
    }

    public static let maxPackBytes = 64 << 20
    public static let dailyInterval: TimeInterval = 86_400
    public static let newGameInterval: TimeInterval = 600

    public let packsDirectory: URL
    /// Paket klasörünün dışında (`packs-remote.json`).
    public let statusFile: URL
    private let configuration: PoolConfiguration
    private let transport: PoolTransport
    private let environment: PoolEnvironment

    /// `configuration.baseURL`: paket sunucusunun adresi; yoksa özellik kapalı.
    public init(packsDirectory: URL, statusFile: URL, configuration: PoolConfiguration,
                transport: PoolTransport, environment: PoolEnvironment = PoolEnvironment()) {
        self.packsDirectory = packsDirectory
        self.statusFile = statusFile
        self.configuration = configuration
        self.transport = transport
        self.environment = environment
    }

    public func status() -> Status {
        (try? Data(contentsOf: statusFile)).flatMap { try? JSONDecoder().decode(Status.self, from: $0) } ?? Status()
    }

    /// Bakma zamanı geldi mi? Önceki seferde inemeyen varsa her zaman evet.
    public func isDue(_ reason: Reason) -> Bool {
        guard configuration.baseURL != nil else { return false }
        let s = status()
        if s.packs.contains(where: { $0.version == -1 }) { return true }
        let age = environment.now().timeIntervalSince1970 - s.checked
        return age >= (reason == .newGame ? Self.newGameInterval : Self.dailyInterval)
    }

    public func checkIfDue(_ reason: Reason) async -> Result? {
        isDue(reason) ? await check() : nil
    }

    public func check() async -> Result {
        var result = Result()
        guard let listRequest = configuration.request("/v1/packs", timeout: 30),
              let (data, http) = try? await transport.send(listRequest), http.statusCode == 200,
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let list = json["packs"] as? [[String: Any]] else {
            result.listFailed = true
            return result
        }
        let remote: [RemotePack] = list.compactMap { p in
            guard let id = p["id"] as? String, Self.isValidID(id),
                  let sha = (p["sha256"] as? String)?.lowercased(), Self.isSHA(sha) else { return nil }
            return RemotePack(id: id, title: p["title"] as? String ?? id,
                              version: (p["version"] as? NSNumber)?.intValue ?? 0, sha256: sha)
        }
        let old = status()
        let recorded = Dictionary(old.packs.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        try? FileManager.default.createDirectory(at: packsDirectory, withIntermediateDirectories: true)
        var next: [RemotePack] = []

        for pack in remote {
            let file = fileURL(pack.id)
            let disk = Self.sha256(of: file)
            let known = recorded[pack.id]
            if disk == pack.sha256 {
                next.append(pack) // diskteki dosya zaten bu sürüm
                continue
            }
            if let disk, disk != known?.sha256 {
                result.userFiles.append(pack.id) // kullanıcının dosyası
                continue
            }
            if await download(pack) {
                next.append(pack)
                result.downloaded.append(pack.id)
            } else {
                next.append(RemotePack(id: pack.id, title: pack.title, version: -1, sha256: known?.sha256 ?? ""))
                result.failed.append(pack.id)
            }
        }
        let remoteIDs = Set(remote.map(\.id))
        for pack in old.packs where !remoteIDs.contains(pack.id) {
            let file = fileURL(pack.id)
            if let disk = Self.sha256(of: file), disk == pack.sha256 {
                try? FileManager.default.removeItem(at: file)
                result.removed.append(pack.id)
            }
        }
        let status = Status(checked: result.failed.isEmpty ? environment.now().timeIntervalSince1970 : old.checked, packs: next)
        if let data = try? JSONEncoder.pool.encode(status) {
            try? FileManager.default.createDirectory(at: statusFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: statusFile, options: .atomic)
        }
        return result
    }

    /// "İndirilen paketleri sil": yalnız sunucudan inmiş ve değişmemiş dosyalar ve durum dosyası.
    @discardableResult
    public func removeDownloaded() -> [String] {
        var removed: [String] = []
        for pack in status().packs {
            let file = fileURL(pack.id)
            if let disk = Self.sha256(of: file), disk == pack.sha256 {
                try? FileManager.default.removeItem(at: file)
                removed.append(pack.id)
            }
        }
        try? FileManager.default.removeItem(at: statusFile)
        return removed
    }

    func fileURL(_ id: String) -> URL { packsDirectory.appendingPathComponent("\(id).json.gz") }

    private func download(_ pack: RemotePack) async -> Bool {
        guard let request = configuration.request("/v1/packs/\(pack.id)", timeout: 60),
              let (data, http) = try? await transport.send(request), http.statusCode == 200,
              data.count <= Self.maxPackBytes, Self.sha256(data) == pack.sha256 else { return false }
        let temp = packsDirectory.appendingPathComponent(".\(pack.id).download")
        let fm = FileManager.default
        do {
            try data.write(to: temp)
            let target = fileURL(pack.id)
            if fm.fileExists(atPath: target.path) {
                _ = try fm.replaceItemAt(target, withItemAt: temp)
            } else {
                try fm.moveItem(at: temp, to: target)
            }
            return true
        } catch {
            try? fm.removeItem(at: temp)
            return false
        }
    }

    static func isValidID(_ id: String) -> Bool {
        let bytes = Array(id.utf8)
        guard (1...64).contains(bytes.count) else { return false }
        func ok(_ b: UInt8, dash: Bool) -> Bool { (97...122).contains(b) || (48...57).contains(b) || (dash && b == 45) }
        return ok(bytes[0], dash: false) && bytes.dropFirst().allSatisfy { ok($0, dash: true) }
    }

    static func isSHA(_ s: String) -> Bool {
        s.utf8.count == 64 && s.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func sha256(of url: URL) -> String? {
        (try? Data(contentsOf: url)).map(sha256)
    }
}
