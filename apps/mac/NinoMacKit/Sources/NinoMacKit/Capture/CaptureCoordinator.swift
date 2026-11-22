// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import AVFoundation
import AppKit
import Foundation
import NinoCore
import Observation

/// Görüntü kaynaklarının dışarıya dokunan işleri (testlerde sahteleri verilir).
public struct CaptureEnvironment: Sendable {
    public var xboxProbe: XboxProbe
    public var greenlight: GreenlightInstaller
    /// Paket kimliğiyle uygulama kurulu mu.
    public var isAppInstalled: @Sendable (String) -> Bool
    /// Greenlight'ı açar ya da öne getirir.
    public var openGreenlight: @MainActor @Sendable () -> Void
    /// Geliştirici derlemesinde PS5 yolunda hedeflenen başka uygulama (adı ya da paket kimliğinin parçası).
    public var windowTargetOverride: String?

    public init(xboxProbe: XboxProbe, greenlight: GreenlightInstaller, isAppInstalled: @escaping @Sendable (String) -> Bool,
                openGreenlight: @escaping @MainActor @Sendable () -> Void, windowTargetOverride: String? = nil) {
        self.xboxProbe = xboxProbe
        self.greenlight = greenlight
        self.isAppInstalled = isAppInstalled
        self.openGreenlight = openGreenlight
        self.windowTargetOverride = windowTargetOverride
    }

    /// Geliştirici derlemesinde PS5 penceresi hedefini değiştiren ayar anahtarı.
    public static let windowTargetDefaultsKey = "ninoWindowTargetApp"

    public static func live(windowTargetOverride: String? = nil) -> CaptureEnvironment {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return CaptureEnvironment(
            xboxProbe: .live(home: home),
            greenlight: GreenlightInstaller(carrier: LiveGreenlightCarrier(),
                                            destinations: [URL(fileURLWithPath: "/Applications"),
                                                           home.appendingPathComponent("Applications")]),
            isAppInstalled: { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil },
            openGreenlight: {
                if let app = NSRunningApplication.runningApplications(withBundleIdentifier: GreenlightFacts.bundleID).first {
                    app.activate()
                    return
                }
                let url = GreenlightFacts.appLocations(home: home).first { FileManager.default.fileExists(atPath: $0.path) }
                    ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: GreenlightFacts.bundleID)
                guard let url else { return }
                let config = NSWorkspace.OpenConfiguration()
                config.activates = true
                NSWorkspace.shared.openApplication(at: url, configuration: config)
            },
            windowTargetOverride: windowTargetOverride)
    }
}

/// Oyun penceresi, yakalama kartı ve Xbox (Greenlight) işlerinin tek sahibi. `LiveEngine` tutar ve
/// kaynak isterken, kurulum/ayar eylemlerinde buna danışır.
@MainActor
public final class CaptureCoordinator {
    private let state: AppState
    private let settingsStore: SettingsStore
    private let env: CaptureEnvironment
    private let log: @Sendable (String) -> Void
    private let hub: CardPreviewHub

    private var previewCount = 0
    private var previewCard: CardCapture?
    private var activeCard: CardCapture?
    private var deviceObservers: [NSObjectProtocol] = []
    private lazy var gameWindow = CardGameWindow(state: state) { [weak self] in self?.state.stopTranslation() }

    private var xboxPollCount = 0
    private var xboxPoll: Task<Void, Never>?
    private var installTask: Task<Void, Never>?

    /// `stopTranslation` kart penceresi kapatılınca çağrılır (AppState üzerinden motor).
    public init(state: AppState, settingsStore: SettingsStore, environment: CaptureEnvironment,
                log: @escaping @Sendable (String) -> Void, hub: CardPreviewHub? = nil) {
        self.state = state
        self.settingsStore = settingsStore
        self.env = environment
        self.log = log
        self.hub = hub ?? .shared
        state.setup.captureCard.selectedDeviceID = settingsStore.captureCardID
        refreshRemotePlayApps()
        refreshXbox()
        watchState()
    }

    // MARK: Kaynaklar

    /// Ayardaki kaynak pencere ya da kartsa onun kaynağı; PS5 için nil.
    public func makeSource(_ s: MacSettings, callbacks: SourceCallbacks) -> SessionSource? {
        switch s.videoSource {
        case .ps5:
            return nil
        case .window:
            let xbox = s.gameConsole == .xbox
            log("görüntü kaynağı: oyun penceresi (" + (xbox ? "Xbox: Greenlight / xbox.com/play" : "PS Remote Play / chiaki-ng") + ")")
            let target: WindowTarget = xbox ? .xbox : .playStation(s.remotePlayApp, customMatch: env.windowTargetOverride)
            let capture = WindowCapture(target: target, hooks: hooks(callbacks, xbox: xbox))
            return SessionSource(frames: capture, stop: { capture.stop() }, reconnect: { capture.reconnect() })
        case .card:
            let showsGame = state.subtitlesOnComputer
            log("görüntü kaynağı: yakalama kartı" + (showsGame ? ", oyun ekranı Mac'te de açık" : ""))
            closePreview()
            let store = settingsStore
            let capture = CardCapture(preferredID: { store.captureCardID }, playsAudio: showsGame,
                                      hooks: hooks(callbacks, xbox: false))
            capture.onSessionRebuilt = { [weak self] in
                Task { @MainActor in
                    self?.hub.rebuilt()
                    self?.gameWindow.reattach()
                }
            }
            activeCard = capture
            hub.attach(capture.session)
            if showsGame { gameWindow.show(session: capture.session) }
            return SessionSource(frames: capture, stop: { [weak self] in
                capture.stop()
                Task { @MainActor in self?.cardSessionEnded(capture) }
            }, reconnect: { capture.reconnect() })
        }
    }

    private func hooks(_ callbacks: SourceCallbacks, xbox: Bool) -> CaptureHooks {
        CaptureHooks(
            window: { [weak self] link in
                callbacks.status(.window(link))
                if xbox { Task { @MainActor in self?.refreshXbox() } }
            },
            card: { [weak self] link in
                callbacks.status(.card(link))
                Task { @MainActor in self?.state.setup.captureCard.status = CardRules.checkStatus(link) }
            },
            gameArea: { rect in callbacks.gameArea(rect) },
            log: log)
    }

    private func cardSessionEnded(_ capture: CardCapture) {
        guard activeCard === capture else { return }
        activeCard = nil
        gameWindow.close()
        hub.attach(nil)
        state.setup.captureCard.status = .searching
        // Denetim hâlâ görünüyorsa önizleme kendi oturumunu açar.
        if previewCount > 0 { openPreview() }
    }

    // MARK: Remote Play uygulaması

    public func refreshRemotePlayApps() {
        let installed = RemotePlayApps.installed(choice: state.settings.remotePlayApp, isInstalled: env.isAppInstalled)
        state.setup.remotePlayAppInstalled = installed
        applyIdleWindowStatus()
    }

    /// Çeviri durmuşken PS5 pencere yolunda uygulama kurulu değilse ana ekran bunu söyler.
    private func applyIdleWindowStatus() {
        guard state.translation == .off, state.settings.videoSource == .window, state.settings.gameConsole == .ps5 else { return }
        let missing = !state.setup.remotePlayAppInstalled
        switch state.source {
        case .window(.idle) where missing: state.source = .window(.appMissing)
        case .window(.appMissing) where !missing: state.source = .window(.idle)
        default: break
        }
    }

    // MARK: Yakalama kartı önizlemesi ve seçimi

    /// Kart denetimi görünür oldu/kayboldu (iç içe görünümler sayılır).
    public func setCardPreview(_ on: Bool) {
        previewCount = max(0, previewCount + (on ? 1 : -1))
        if previewCount > 0 {
            reloadCaptureDevices()
            observeDevices(true)
            if activeCard == nil, state.translation == .off { openPreview() }
        } else {
            observeDevices(false)
            closePreview()
        }
    }

    public func selectCaptureDevice(_ id: String?) {
        settingsStore.captureCardID = id
        state.setup.captureCard.selectedDeviceID = id
        previewCard?.reconnect()
        activeCard?.reconnect()
    }

    private func openPreview() {
        guard previewCard == nil else { return }
        let store = settingsStore
        let card = CardCapture(preferredID: { store.captureCardID }, playsAudio: false, hooks: CaptureHooks(
            card: { [weak self] link in Task { @MainActor in self?.state.setup.captureCard.status = CardRules.checkStatus(link) } }))
        card.onSessionRebuilt = { [weak self] in Task { @MainActor in self?.hub.rebuilt() } }
        previewCard = card
        state.setup.captureCard.status = .searching
        hub.attach(card.session)
        card.start()
    }

    private func closePreview() {
        guard let card = previewCard else { return }
        previewCard = nil
        card.stop()
        if activeCard == nil { hub.attach(nil) }
    }

    private func reloadCaptureDevices() {
        state.setup.captureCard.devices = CardCapture.deviceList()
    }

    private func observeDevices(_ on: Bool) {
        let center = NotificationCenter.default
        if !on {
            for o in deviceObservers { center.removeObserver(o) }
            deviceObservers = []
            return
        }
        guard deviceObservers.isEmpty else { return }
        for name in [AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification] {
            deviceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.reloadCaptureDevices()
                }
            })
        }
    }

    // MARK: Xbox

    /// Bağlantı listesi görünürken saniyede bir yoklanır (iç içe görünümler sayılır).
    public func setXboxPolling(_ on: Bool) {
        xboxPollCount = max(0, xboxPollCount + (on ? 1 : -1))
        if xboxPollCount > 0, xboxPoll == nil {
            refreshXbox()
            xboxPoll = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    self?.refreshXbox()
                }
            }
        } else if xboxPollCount == 0 {
            xboxPoll?.cancel()
            xboxPoll = nil
        }
    }

    public func refreshXbox() {
        let link = env.xboxProbe.read(keeping: state.setup.xbox)
        if link != state.setup.xbox { state.setup.xbox = link }
        let step = GreenlightFacts.xboxStep(link)
        if step != state.xboxStep { state.xboxStep = step }
    }

    public func installGreenlight() {
        guard installTask == nil else { return }
        state.setup.xbox.installError = nil
        state.setup.xbox.installProgress = 0
        refreshXbox()
        let installer = env.greenlight
        installTask = Task { [weak self] in
            do {
                let app = try await installer.install { p in
                    guard let p else { return }
                    Task { @MainActor in
                        guard let self, self.installTask != nil else { return }
                        self.state.setup.xbox.installProgress = max(self.state.setup.xbox.installProgress ?? 0, p)
                        self.state.xboxStep = GreenlightFacts.xboxStep(self.state.setup.xbox)
                    }
                }
                self?.log("Greenlight kuruldu: \(app.path)")
                self?.installFinished(error: nil)
                self?.openGreenlight()
            } catch {
                let message = (error as? GreenlightInstallError ?? .downloadFailed).message
                self?.log("Greenlight kurulamadı: \(error)")
                self?.installFinished(error: message)
            }
        }
    }

    /// Kurulum sürüyor mu (testler bekler).
    public var greenlightInstall: Task<Void, Never>? { installTask }

    private func installFinished(error: String?) {
        installTask = nil
        state.setup.xbox.installProgress = nil
        state.setup.xbox.installError = error
        refreshXbox()
    }

    public func openGreenlight() { env.openGreenlight() }

    // MARK: Durum izleme

    /// Ayar ve durum değişimlerini izler: Remote Play seçimi, boşta pencere durumu, kart tam ekranı.
    private func watchState() {
        withObservationTracking {
            _ = state.settings.remotePlayApp
            _ = state.settings.videoSource
            _ = state.settings.gameConsole
            _ = state.source
            _ = state.translation
            _ = state.cardFullScreen
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.stateChanged()
                self.watchState()
            }
        }
    }

    private var lastRemotePlayChoice: MacSettings.RemotePlayApp?
    private var lastCardFullScreen = false

    private func stateChanged() {
        if lastRemotePlayChoice != state.settings.remotePlayApp {
            lastRemotePlayChoice = state.settings.remotePlayApp
            refreshRemotePlayApps()
        } else {
            applyIdleWindowStatus()
        }
        // Yalnız tam ekran isteği değişince (pencerenin kendi geçişi de bunu yazar; aynı değerde dokunulmaz).
        if state.cardFullScreen != lastCardFullScreen {
            lastCardFullScreen = state.cardFullScreen
            if gameWindow.isOpen { gameWindow.setFullScreen(state.cardFullScreen) }
        }
        // Çeviri başka kaynakla başladıysa kartın önizlemesi bırakılır; durunca denetim görünürse geri açılır.
        if state.translation != .off, activeCard == nil { closePreview() }
        if state.translation == .off, activeCard == nil, previewCount > 0 { openPreview() }
    }
}
