// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation
import NinoCore

/// Anonim hata ve hız istatistikleri (tarif: NinoCore docs/tarif/olcum.md). Ayarlarda kapatma düğmesi yok; yalnız
/// sunucu durdurabilir. Metin, ad, adres ya da hata mesajı gitmez; yalnız kodlar ve süreler.
enum AppTelemetry {
    nonisolated(unsafe) private static var shared: Telemetry?

    static func start(folders: AppFolders) {
        guard shared == nil, let base = NinoServer.base else { return }
        #if DEBUG
        let channel = "dev"
        #else
        let channel = "release"
        #endif
        let options = Telemetry.Options(endpoint: base.appendingPathComponent("v1/events"),
                                        installID: NinoServer.installID(folders: folders),
                                        context: TelemetryContext.current(app: AppInfo.version, channel: channel),
                                        directory: folders.support.appendingPathComponent("telemetry", isDirectory: true),
                                        enabled: true)
        let t = Telemetry(options: options)
        shared = t
        AppDiagnosis.shared.start()
        Task {
            await t.appLaunched()
            await t.start()
        }
    }

    static func record(_ event: TelemetryEvent?) {
        guard let t = shared, let event else { return }
        Task { await t.record(event) }
    }

    static func error(_ code: String) {
        guard let t = shared else { return }
        Task { await t.recordError(code) }
    }

    /// Sunucunun otomatik teşhis ayarı (kapatılan kurallar, eşikler).
    static func diagConfig() async -> TelemetryRemoteConfig.DiagConfig? {
        guard let t = shared else { return nil }
        return await t.remoteConfig.diag
    }

    static func background() { if let t = shared { Task { await t.appDidEnterBackground() } } }
    static func foreground() { if let t = shared { Task { await t.appWillEnterForeground() } } }
}
