// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import SwiftUI
import UIKit
import UserNotifications

/// Nino Game Translator: tamamen ücretsiz; hesap istemez, ölçüm ve izleme yapmaz.
@main
struct NinoApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var wasInBackground = false

    init() {
        let testing = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        let folders = AppFolders.prepare()
        let model: AppModel
        if testing {
            model = AppModel(store: MemoryStore(), defaults: UserDefaults(suiteName: "nino-tests") ?? .standard,
                             folders: folders, ephemeral: true)
        } else if let demo = Self.screenshotModel(folders: folders) {
            model = demo
        } else {
            model = AppModel(store: KeychainStore(), folders: folders)
            AppTelemetry.start(folders: folders)
            model.keepScreenAwake = { ScreenAwake.set($0, for: .translation) }
            model.onConnectionLost = { ConnectionAlert.post() }
        }
        _model = StateObject(wrappedValue: model)
    }

    /// Hata ayıklama: NINO_SCREENSHOT=home ile kurulum bitmiş gibi açılır (ekran karşılaştırması için; ağa,
    /// Anahtar Zinciri'ne ve gerçek ayarlara dokunmaz).
    private static func screenshotModel(folders: AppFolders) -> AppModel? {
        #if DEBUG
        guard let mode = ProcessInfo.processInfo.environment["NINO_SCREENSHOT"] else { return nil }
        let store = MemoryStore()
        let suite = "nino-screenshot"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        if mode != "welcome" { defaults.set(true, forKey: Keys.welcomeSeen) }
        if mode == "psn" || mode == "pair" { defaults.set("playstation", forKey: Keys.platform) }
        if mode == "xbox" { defaults.set("xbox", forKey: Keys.platform) }
        if mode == "pair" { store.save(Data([1, 2, 3, 4, 5, 6, 7, 8]), for: Keys.accountID) }
        if mode == "target" { defaults.set(true, forKey: Keys.setupSkipped) }
        if let lang = ProcessInfo.processInfo.environment["NINO_SCREENSHOT_LANG"] {
            var s = AppSettings.load(from: defaults)
            s.targetLanguage = lang
            s.save(to: defaults)
        }
        if mode == "home" || mode == "tour" {
            store.save(Data([1, 2, 3, 4, 5, 6, 7, 8]), for: Keys.accountID)
            store.save(PairedConsole(host: "192.168.1.103", name: "PS5-002", registKey: Data(count: 16), morning: Data(count: 16)),
                       for: Keys.console)
            store.save(true, for: Keys.setupComplete)
            defaults.set(mode == "home", forKey: Keys.coachTourDone)
            var s = AppSettings.load(from: defaults)
            s.output = .computer
            s.save(to: defaults)
        }
        if ProcessInfo.processInfo.environment["NINO_SCREENSHOT_TVUPDATE"] != nil {
            store.save(PairedTV(name: "Salon", host: "192.168.1.50", brand: .androidTV), for: Keys.tv)
        }
        let model = AppModel(store: store, defaults: defaults, folders: folders, ephemeral: true)
        // NINO_SCREENSHOT_TVUPDATE=1: TV'de eski Nino varmış gibi güncelleme kartı görünür.
        if ProcessInfo.processInfo.environment["NINO_SCREENSHOT_TVUPDATE"] != nil {
            model.tvPackageVersions = [.androidTV: "4.5.0"]
            model.tvAppSeenVersion = "0.1.0-beta.37"
        }
        return model
        #else
        return nil
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                ScreenAwake.reapply()
                Task { await model.renewLGSessionIfDue() }
                let returning = wasInBackground
                wasInBackground = false
                if returning {
                    AppTelemetry.foreground()
                    AppDiagnosis.shared.note("app.foreground")
                }
                model.becameActive(afterBackground: returning)
            case .background:
                AppTelemetry.background()
                AppDiagnosis.shared.note("app.background")
                model.enteredBackground()
                wasInBackground = true
            default:
                break
            }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    /// Ekranın izin verilen yönleri (tam ekran altyazıda yatay istenir).
    static var orientations: UIInterfaceOrientationMask = DS.isPad ? .all : .portrait

    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        Self.orientations
    }
}

/// Ekran yönü isteği (iPad'de hiçbir şey yapmaz).
@MainActor
enum Orientation {
    static func request(_ mask: UIInterfaceOrientationMask) {
        guard !DS.isPad else { return }
        AppDelegate.orientations = mask
        for scene in UIApplication.shared.connectedScenes {
            guard let scene = scene as? UIWindowScene else { continue }
            scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask))
        }
    }
}

/// PS5 bağlantısı kendiliğinden koptuğunda gösterilen yerel bildirim. Uygulama öndeyken durum ekranda göründüğü için
/// gönderilmez; hep aynı kimlikle gönderildiği için art arda kopmalarda yalnız sonuncusu kalır.
@MainActor
enum ConnectionAlert {
    private static let center = UNUserNotificationCenter.current()

    static func requestPermission() {
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func post() {
        if UIApplication.shared.applicationState == .active { return }
        let note = UNMutableNotificationContent()
        note.title = L("notify.ps5.lost")
        note.body = L("notify.stopped")
        note.sound = .default
        center.add(UNNotificationRequest(identifier: "connection-lost", content: note, trigger: nil))
    }
}

/// Çeviri ve TV kurulumu sürerken ekran kararmasın (iOS uygulamayı askıya alıp bağlantıları keser).
@MainActor
enum ScreenAwake {
    enum Reason: Hashable { case translation, tvInstall }
    private static var reasons: Set<Reason> = []
    private static var timer: Timer?

    static func set(_ on: Bool, for reason: Reason) {
        if on { reasons.insert(reason) } else { reasons.remove(reason) }
        reapply()
        timer?.invalidate()
        timer = nil
        if !reasons.isEmpty {
            timer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { _ in
                Task { @MainActor in reapply() }
            }
        }
    }

    static func reapply() {
        let on = !reasons.isEmpty
        if on { UIApplication.shared.isIdleTimerDisabled = false }
        UIApplication.shared.isIdleTimerDisabled = on
    }
}
