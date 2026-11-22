// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation
import NinoMacKit
import Sparkle

/// Sparkle 2 (MIT) ile `AutoUpdater`: saatte bir denetim, yeni sürüm sorulmadan arka planda iner;
/// kurma zamanına `UpdateCoordinator` karar verir (guncelleme-admin.md §2).
///
/// Ayarlar bilgi dosyasında (project.yml): `SUFeedURL`, `SUPublicEDKey`, `SUEnableAutomaticChecks`,
/// `SUAutomaticallyUpdate`, `SUAllowsAutomaticUpdates`, `SUScheduledCheckInterval` = 3600.
@MainActor
final class SparkleAutoUpdater: NSObject, AutoUpdater, SPUUpdaterDelegate {
    var onEvent: ((AutoUpdaterEvent) -> Void)?
    private var controller: SPUStandardUpdaterController!
    /// Sparkle'ın "hemen kur ve yeniden aç" bloğu (güncelleme indikten sonra).
    private var immediateInstall: (() -> Void)?

    override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
    }

    func start() {
        controller.startUpdater()
    }

    func checkInBackground() {
        guard controller.updater.sessionInProgress == false else { return }
        controller.updater.checkForUpdatesInBackground()
    }

    func showUpdateWindow() {
        controller.checkForUpdates(nil)
    }

    func installReadyUpdate() -> Bool {
        guard let install = immediateInstall else { return false }
        immediateInstall = nil
        install()
        return true
    }

    // MARK: SPUUpdaterDelegate (Sparkle ana iş parçacığında çağırır)

    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let version = item.displayVersionString
        MainActor.assumeIsolated { onEvent?(.found(version: version)) }
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        MainActor.assumeIsolated { onEvent?(.noUpdate) }
    }

    nonisolated func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
                             immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        let version = item.displayVersionString
        MainActor.assumeIsolated {
            immediateInstall = immediateInstallHandler
            onEvent?(.downloaded(version: version))
        }
        return true
    }

    nonisolated func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        MainActor.assumeIsolated { onEvent?(.failed) }
    }
}
