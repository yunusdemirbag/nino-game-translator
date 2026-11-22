// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

// Güncelleme denetimi (guncelleme-admin.md §2) ve toplam indirme sayacı (§3).
// İndirip kurma (Sparkle) ayrı iş: burada yalnız `UpdateService` sözleşmesi ve GitHub denetimi var.

/// GitHub'daki son sürüm.
public struct ReleaseInfo: Equatable, Sendable {
    public var version: String
    public var notesURL: URL?
    public var downloadURL: URL?

    public init(version: String, notesURL: URL?, downloadURL: URL?) {
        self.version = version
        self.notesURL = notesURL
        self.downloadURL = downloadURL
    }
}

public enum UpdateCheckResult: Equatable, Sendable {
    case upToDate
    case available(ReleaseInfo)
    case failed
    /// Saatlik sınır yüzünden ağa çıkılmadı; önceki sonuç geçerli.
    case skipped
}

/// Güncellemenin işi. Uygulamada GitHub denetimi + (sonra) Sparkle; testte sahte.
@MainActor
public protocol UpdateService: AnyObject {
    /// `force`: Yenile/denetle düğmeleri saatlik sınırı atlar.
    func check(force: Bool) async -> UpdateCheckResult
    /// İndirilmiş güncellemeyi kurar ve yeniden açar (DMG sürümü); App Store'da tarayıcıyı açar.
    func install()
    /// Bilinen son sürüm.
    var latest: ReleaseInfo? { get }
}

public enum VersionCompare {
    /// Noktalı parçalar sayısal karşılaştırılır; eksik parça 0. Baştaki `v` atılır.
    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = parts(candidate), b = parts(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    static func parts(_ text: String) -> [Int] {
        var t = text.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("v") || t.hasPrefix("V") { t.removeFirst() }
        return t.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
    }
}

/// GitHub API'deki son sürüme bakar. Ağa en çok saatte bir çıkar (zorlanmadıkça).
@MainActor
public final class GitHubUpdateChecker: UpdateService {
    public static let latestReleaseAPI =
        URL(string: "https://api.github.com/repos/yunusdemirbag/nino-game-translator/releases/latest")!
    public static let releasesPage =
        URL(string: "https://github.com/yunusdemirbag/nino-game-translator/releases/latest")!
    public static let minimumInterval: TimeInterval = 3600
    /// İstek başlıkları (alan → değer).
    static let releaseHeaders = ["Accept": "application/vnd.github+json", "User-Agent": "Nino-Mac"]
    public static let assetName = "Nino-Mac.zip"

    private let network: NetworkClient
    private let currentVersion: String
    private let now: () -> Date
    private let installAction: (ReleaseInfo?) -> Void
    private var lastNetworkCheck: Date?
    public private(set) var latest: ReleaseInfo?

    public init(network: NetworkClient, currentVersion: String, now: @escaping () -> Date = Date.init,
                install: @escaping (ReleaseInfo?) -> Void) {
        self.network = network
        self.currentVersion = currentVersion
        self.now = now
        self.installAction = install
    }

    public func check(force: Bool) async -> UpdateCheckResult {
        let date = now()
        if !force, let last = lastNetworkCheck, date.timeIntervalSince(last) < Self.minimumInterval { return .skipped }
        lastNetworkCheck = date
        var request = URLRequest(url: Self.latestReleaseAPI, timeoutInterval: 15)
        // GitHub sürüm API'si: JSON biçimi ve uygulamanın kimliği.
        for (field, value) in Self.releaseHeaders { request.setValue(value, forHTTPHeaderField: field) }
        guard let (data, response) = try? await network.send(request), response.statusCode == 200,
              let release = Self.parse(data) else { return .failed }
        if VersionCompare.isNewer(release.version, than: currentVersion) {
            latest = release
            return .available(release)
        }
        latest = nil
        return .upToDate
    }

    public func install() { installAction(latest) }

    static func parse(_ data: Data) -> ReleaseInfo? {
        guard let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              var tag = o["tag_name"] as? String, !tag.isEmpty else { return nil }
        if tag.hasPrefix("v") || tag.hasPrefix("V") { tag.removeFirst() }
        let assets = o["assets"] as? [[String: Any]] ?? []
        let download = assets.first { $0["name"] as? String == assetName }?["browser_download_url"] as? String
        return ReleaseInfo(version: tag, notesURL: (o["html_url"] as? String).flatMap(URL.init(string:)),
                           downloadURL: download.flatMap(URL.init(string:)))
    }
}

/// Testlerde ve önizlemede: ağa çıkmaz.
@MainActor
public final class FakeUpdateService: UpdateService {
    public var result: UpdateCheckResult
    public private(set) var checks: [Bool] = []
    public private(set) var installs = 0
    public var latest: ReleaseInfo?

    public init(result: UpdateCheckResult = .upToDate) { self.result = result }

    public func check(force: Bool) async -> UpdateCheckResult {
        checks.append(force)
        if case .available(let info) = result { latest = info }
        return result
    }

    public func install() { installs += 1 }
}

/// `UpdateCheckResult` → ekranların okuduğu durum.
public extension UpdateStatus {
    static func from(_ result: UpdateCheckResult, previous: UpdateStatus) -> UpdateStatus {
        switch result {
        case .upToDate: return .upToDate
        case .available(let info): return .available(version: info.version)
        case .failed: return .failed(message: "")
        case .skipped: return previous == .checking ? .idle : previous
        }
    }
}

// MARK: - Toplam indirme sayacı

/// Canlı havuz sunucusundan `GET v1/config` → `downloads`. En çok 10 dakikada bir; son geçerli sayı saklanır.
@MainActor
public final class DownloadCounterService {
    public static let interval: TimeInterval = 600
    public static let defaultsKey = "ninoDownloadTotal"

    private let network: NetworkClient
    private let defaults: UserDefaults
    private let now: () -> Date
    private var lastAttempt: Date?

    public init(network: NetworkClient, defaults: UserDefaults, now: @escaping () -> Date = Date.init) {
        self.network = network
        self.defaults = defaults
        self.now = now
    }

    /// Saklanan son geçerli sayı; hiç alınamadıysa nil (sayaç görünmez).
    public var stored: Int? {
        let value = defaults.integer(forKey: Self.defaultsKey)
        return value > 0 ? value : nil
    }

    /// Sınır dolduysa ağa çıkmadan saklananı döner. Ağ yoksa saklanan gösterilmeye devam eder.
    public func refresh() async -> Int? {
        let date = now()
        if let last = lastAttempt, date.timeIntervalSince(last) < Self.interval { return stored }
        lastAttempt = date
        var request = URLRequest(url: PoolServer.endpoint(PoolServer.liveURL, "v1/config"),
                                 cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 10)
        request.httpMethod = "GET"
        guard let (data, response) = try? await network.send(request), response.statusCode == 200,
              let count = Self.parse(data) else { return stored }
        defaults.set(count, forKey: Self.defaultsKey)
        return count
    }

    static func parse(_ data: Data) -> Int? {
        guard let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let n = DataFiles.number(o["downloads"]) else { return nil }
        let value = Int(n)
        return value > 0 ? value : nil
    }
}
