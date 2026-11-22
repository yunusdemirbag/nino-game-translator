// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// Çökme tespiti: "çalışıyor" işareti. Uygulama öndeyken `telemetry/running.json` durur; düzgün kapanınca ya da arka
/// plana geçince silinir. Bir sonraki açılışta işaret hâlâ duruyorsa önceki çalışma çökmüştür.
/// Yakalanmamış Objective-C istisnası olursa yalnız sınıf adı işarete yazılır (mesajı değil).
public struct CrashMarker: Sendable {
    public struct Record: Codable, Equatable, Sendable {
        public var version: String
        public var started: Int
        /// Son "hâlâ çalışıyorum" zamanı (çalışma süresini tahmin etmek için).
        public var alive: Int
        public var code: String?
        public var place: String?
    }

    public let url: URL

    public init(directory: URL) {
        url = directory.appendingPathComponent("running.json")
    }

    public func read() -> Record? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Record.self, from: data)
    }

    public func markRunning(version: String, now: Int) {
        write(Record(version: version, started: now, alive: now, code: nil, place: nil))
    }

    public func touch(now: Int) {
        guard var r = read() else { return }
        r.alive = now
        write(r)
    }

    public func clear() {
        try? FileManager.default.removeItem(at: url)
    }

    /// Önceki çalışmanın çökme olayı (varsa) ve işaretin silinmesi.
    public func takeCrash() -> TelemetryEvent? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        defer { clear() }
        guard let r = read() else { return .crash(code: nil, version: "", uptime: nil) }
        return .crash(code: r.code, where: r.place, version: r.version, uptime: max(0, r.alive - r.started))
    }

    private func write(_ record: Record) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(record) { try? data.write(to: url, options: .atomic) }
    }

    // MARK: - Yakalanmamış istisna

    nonisolated(unsafe) private static var exceptionMarker: CrashMarker?

    /// Yakalanmamış Objective-C istisnasının sınıf adını işarete yazar. Uygulama başlarken bir kez çağrılır.
    public static func installExceptionHandler(_ marker: CrashMarker) {
        exceptionMarker = marker
        NSSetUncaughtExceptionHandler { exception in
            guard let marker = CrashMarker.exceptionMarker, var r = marker.read() else { return }
            r.code = TelemetryCode.clean(exception.name.rawValue) ?? "objc_exception"
            marker.write(r)
        }
    }
}
