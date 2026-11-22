// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import AppKit
import SwiftUI
import Foundation
import NinoCore

// Uygulamanın motor dışındaki yardımcıları: güncelleme (Sparkle bağlantısı), genel kısayollar, ekranı çevir,
// admin modu, debug kareleri, yedek OCR ve takılınca yeniden açılma (guncelleme-admin.md, okuma-hatti.md §4.6).

/// Admin modunun saf kuralları (guncelleme-admin.md §6).
public enum AdminModeRules {
    /// Rozet ve debug kareleri: deneme yapısında her zaman, yayında yalnız `ninoAdminMode` ile.
    /// Dağıtılan deneme yapılarında (Info.plist `NinoAdminDisabled` = YES) admin kipi hiçbir koşulda açılmaz:
    /// kendiliğinden çeviri, hata ayıklama kaydı, debug kareleri ve TV uyandırma yok.
    public static var disabledByBundle: Bool { Bundle.main.object(forInfoDictionaryKey: "NinoAdminDisabled") as? Bool == true }

    public static func isOn(flavor: AppIdentity.Flavor, flag: Bool, disabled: Bool = disabledByBundle) -> Bool {
        if disabled { return false }
        switch flavor {
        case .development: return true
        case .release: return flag
        case .testing: return false
        }
    }

    /// Görünür admin etiketleri ("Admin modu açık (debug)" hapı, TV önizlemesindeki "TV (admin)"): yalnız geliştirici
    /// kimliğinde (deneme/Debug yapısı). Yayın kimliğinde admin modu açık olsa da hiç görünmez; admin modunun kendisi
    /// (kendiliğinden çeviri, kayıt, bileşik TV karesi) bundan etkilenmez.
    public static func showsBadges(flavor: AppIdentity.Flavor, adminOn: Bool) -> Bool {
        adminOn && flavor == .development
    }

    /// Açılışta kendiliğinden çeviri: YALNIZ yayın kimliğinde, bayrakla ve kurulum bitmişse. Deneme kimliğinde asla.
    public static func autoStarts(flavor: AppIdentity.Flavor, flag: Bool, setupComplete: Bool,
                                  translation: TranslationPhase, disabled: Bool = disabledByBundle) -> Bool {
        !disabled && flavor == .release && flag && setupComplete && translation == .off
    }

    /// Başlatılabilir olmayı en çok bu kadar bekler.
    public static let startWait: TimeInterval = 10
    /// TV uygulamasını uyandırmadan önce bu süre boyunca hiç TV bağlantısı görülmemiş olmalı.
    /// (TV'de Nino'yu öne getirmek kullanıcıyı HDMI/PS5 ekranından çıkarır; yalnız TV hiç bağlanmıyorsa yapılır.)
    public static let tvWakeDelay: TimeInterval = 60
    /// İki uyandırma arasında en az bu kadar geçer (uygulama yeniden açılsa da; UserDefaults'ta tutulur).
    public static let tvWakeMinInterval: TimeInterval = 600
    static let lastTVWakeKey = "ninoAdminLastTVWake"

    /// `everConnected`: bekleme süresi boyunca herhangi bir TV bağlantısı (giden, 47800, 8787) görüldü mü.
    public static func shouldWakeTV(subtitlesOnTV: Bool, tvPaired: Bool, connectedDisplays: Int, translation: TranslationPhase,
                                    everConnected: Bool = false, lastWake: Date? = nil, now: Date = Date()) -> Bool {
        guard translation == .on, subtitlesOnTV, tvPaired, connectedDisplays == 0, !everConnected else { return false }
        if let lastWake, now.timeIntervalSince(lastWake) < tvWakeMinInterval { return false }
        return true
    }
}

/// TV katmanını değiştiren mesajlar (bileşik kare hemen yenilenir).
public enum TVLayerRules {
    public static let layerTypes: Set<String> = ["show", "clear", "screen", "screen-clear", "region", "region-clear", "style", "stopped"]

    public static func changesLayer(_ json: String) -> Bool {
        guard let o = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any],
              let type = o["type"] as? String else { return false }
        return layerTypes.contains(type)
    }
}

/// OCR kalıcı takılınca son çare (okuma-hatti.md §4.6): süreç örneği alınır, çeviri sürüyorsa "sürdür" işareti
/// yazılır, oturum düzgün kapatılır ve uygulama yeniden açılır.
public enum StuckRecoveryRules {
    /// Bu süre içinde ikinci kez yeniden açılmaz (döngü olmasın).
    public static let minimumGap: TimeInterval = 600
    public static let lastRelaunchKey = "ninoOCRRelaunchAt"

    public static func mayRelaunch(lastRelaunch: TimeInterval?, now: TimeInterval) -> Bool {
        guard let lastRelaunch else { return true }
        return now - lastRelaunch >= minimumGap
    }
}

@MainActor
public final class NinoAppSupport {
    public private(set) static var shared: NinoAppSupport?

    public let screen: ScreenTranslator
    public private(set) var hotKeys: HotKeyController?
    public private(set) var updates: UpdateCoordinator?
    public private(set) var frames: DebugFrameRecorder?
    /// Sürekli hata ayıklama kaydı (`debug-kayit/`, nino-debug); yalnız admin modunda.
    public private(set) var recording: DebugRecording?
    /// Gizli TV sayfası (admin bileşik karesi).
    public private(set) var tvPage: TVPageRenderer?
    public let adminMode: Bool
    private weak var engine: LiveEngine?
    private var adminTask: Task<Void, Never>?
    private var relaunching = false

    /// Uygulama açılışı (`NinoMain.init`). `--ocr-helper` ile açıldıysa yardımcı süreç olur ve hiç dönmez.
    /// `makeAutoUpdater` yalnız yayın kimliğinde çağrılır (deneme yapısında Sparkle hiç kurulmaz).
    public static func launch(makeAutoUpdater: (@MainActor () -> AutoUpdater)?) {
        if OCRHelperServer.isRequested() { OCRHelperServer.run() }
        guard shared == nil, let engine = NinoAppModel.live.engine as? LiveEngine else { return }
        let auto = engine.env.identity.flavor == .release ? makeAutoUpdater?() : nil
        shared = NinoAppSupport(engine: engine, autoUpdater: auto)
        // Pencere hiç açılmadıysa açılış gösterisi bitmemiştir: ekran dışı çizimde ana ekran görünsün diye ayrı UI durumu
        // (ortak durum değişmez; pencere sonra açılınca gösteri yine oynar).
        let model = NinoAppModel.live
        let quiet = HomeUIState()
        quiet.splashFinished = true
        shared?.recording?.offscreenContent = {
            AnyView(MainWindowView(state: model.state, ui: model.ui.splashFinished ? model.ui : quiet))
        }
    }

    public init(engine: LiveEngine, autoUpdater: AutoUpdater?, globalHotKeys: Bool = true) {
        self.engine = engine
        self.screen = ScreenTranslator(engine: engine)
        let flavor = engine.env.identity.flavor
        adminMode = AdminModeRules.isOn(flavor: flavor, flag: engine.env.settingsStore.adminMode)
        engine.support = self
        engine.state.adminMode = adminMode
        engine.state.adminBadges = AdminModeRules.showsBadges(flavor: flavor, adminOn: adminMode)

        if let network = engine.env.network {
            let checker = GitHubUpdateChecker(network: network, currentVersion: engine.env.appVersion, install: { info in
                if let url = info?.downloadURL ?? info?.notesURL ?? Optional(GitHubUpdateChecker.releasesPage) {
                    NSWorkspace.shared.open(url)
                }
            })
            let coordinator = UpdateCoordinator(checker: checker, auto: autoUpdater, state: engine.state,
                                                stopTranslation: { [weak engine] in
                                                    engine?.stopTranslation()
                                                    await engine?.lastStop?.value
                                                }, markResume: { [weak engine] in
                                                    engine?.env.settingsStore.defaults.set(Date().timeIntervalSince1970,
                                                                                          forKey: DefaultsKey.resumeAfterRelaunch)
                                                })
            engine.updater = coordinator
            updates = coordinator
            if flavor == .release { coordinator.start() }
        }

        if globalHotKeys {
            hotKeys = HotKeyController(state: engine.state, onTranslateScreenReleased: { [weak self] in self?.screen.cancel() })
        }
        if adminMode { frames = Self.makeFrames(engine) }
        recording = DebugRecording.makeIfEnabled(engine: engine, adminMode: adminMode)
        if adminMode, let frames { connectTVLayer(frames, engine: engine) }
        OCRFallback.setGiveUpHandler { Task { @MainActor in NinoAppSupport.shared?.ocrGaveUp() } }
        startAdminMode()
    }

    // MARK: Admin modu

    private func startAdminMode() {
        guard let engine else { return }
        let s = engine.state
        guard AdminModeRules.autoStarts(flavor: engine.env.identity.flavor, flag: engine.env.settingsStore.adminMode,
                                        setupComplete: s.isSetupComplete, translation: s.translation) else { return }
        adminTask = Task { [weak self] in
            let deadline = Date().addingTimeInterval(AdminModeRules.startWait)
            while Date() < deadline, let e = self?.engine, !e.state.canStart {
                try? await Task.sleep(for: .milliseconds(500))
            }
            guard let e = self?.engine, e.state.translation == .off, e.state.canStart else { return }
            e.subtitleLog.write("admin modu: çeviri otomatik açılıyor")
            e.startTranslation()
            // TV bağlıyken (ya da bekleme süresinde bir kez bile bağlandıysa) hiç dokunma.
            var everConnected = false
            let waitUntil = Date().addingTimeInterval(AdminModeRules.tvWakeDelay)
            while Date() < waitUntil {
                guard let e = self?.engine else { return }
                if e.state.connectedDisplays > 0 { everConnected = true; break }
                try? await Task.sleep(for: .seconds(2))
            }
            guard let e = self?.engine else { return }
            let defaults = e.env.settingsStore.defaults
            let last = defaults.object(forKey: AdminModeRules.lastTVWakeKey) as? Date
            if AdminModeRules.shouldWakeTV(subtitlesOnTV: e.state.subtitlesOnTV, tvPaired: e.state.pairedTV != nil,
                                           connectedDisplays: e.state.connectedDisplays, translation: e.state.translation,
                                           everConnected: everConnected, lastWake: last) {
                defaults.set(Date(), forKey: AdminModeRules.lastTVWakeKey)
                e.subtitleLog.write("admin modu: TV'de Nino 60 sn boyunca hiç bağlanmadı, TV uygulaması başlatılıyor")
                // LG/Samsung: açık tutma turu uygulamayı yeniden açar. TODO: Android TV'de bu bilgisayarın adresiyle yenileme.
                e.tvSetup?.systemDidWake()
            }
        }
    }

    // MARK: Debug kareleri

    static func makeFrames(_ engine: LiveEngine) -> DebugFrameRecorder {
        let folder = engine.env.identity.logsFolder.appendingPathComponent("frames", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let memory = LastLineMemory()
        let ref = WeakEngine(engine)
        return DebugFrameRecorder(folder: folder) {
            let snapshot = await MainActor.run { () -> (SubtitleSession?, LiveLine?) in
                (ref.engine?.session, ref.engine?.state.lastLine)
            }
            let (session, line) = snapshot
            if let line { memory.set(line.source, line.translated) }
            let area = await session?.reader.readingArea
            let box = await session?.reader.currentSubtitle?.box
            let (read, translated) = memory.get()
            return DebugFrameContext(readingArea: area, textBox: box, read: read, translation: translated)
        }
    }

    /// Bileşik kare (admin): TV'lere giden mesajlar gizli TV sayfasına da gider; sayfanın görüntüsü f-/latest.jpg'de
    /// PS5 karesinin üstüne konur ve ana ekrandaki TV'de gösterilir.
    private func connectTVLayer(_ frames: DebugFrameRecorder, engine: LiveEngine) {
        let renderer = TVPageRenderer()
        tvPage = renderer
        recording?.tap.onMessage = { [weak frames] json in
            Task { @MainActor in renderer.receive(json) }
            if TVLayerRules.changesLayer(json) { frames?.requestSoon() }
        }
        frames.overlay = { [weak renderer] in await renderer?.snapshot() }
        let state = engine.state
        frames.onComposite = { image in
            Task { @MainActor in state.adminTVPreview = AdminTVPreview(image: image, at: Date()) }
        }
    }

    /// Kaynaktan gelen kareler debug kayıtçılarına da uğrar (admin modunda).
    func tap(_ stream: AsyncStream<Frame>) -> AsyncStream<Frame> {
        let recorder = recording?.recorder
        guard frames != nil || recorder != nil else { return stream }
        let frames = self.frames
        return AsyncStream(bufferingPolicy: .bufferingNewest(2)) { continuation in
            let task = Task.detached {
                for await f in stream {
                    frames?.offer(f.image)
                    recorder?.offerPS5(f.image)
                    continuation.yield(f)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private final class WeakEngine: @unchecked Sendable {
        weak var engine: LiveEngine?
        init(_ e: LiveEngine) { engine = e }
    }

    private final class LastLineMemory: @unchecked Sendable {
        private let lock = NSLock()
        private var read = "", translated = ""
        func set(_ r: String, _ t: String) { lock.withLock { read = r; translated = t } }
        func get() -> (String, String) { lock.withLock { (read, translated) } }
    }

    // MARK: OCR takılması: son çare

    func ocrGaveUp() {
        guard let engine, !relaunching else { return }
        let defaults = engine.env.settingsStore.defaults
        let now = Date().timeIntervalSince1970
        let last = defaults.object(forKey: StuckRecoveryRules.lastRelaunchKey) as? Double
        engine.subtitleLog.write("OCR: yedek okuyucu da üç kez düştü")
        guard StuckRecoveryRules.mayRelaunch(lastRelaunch: last, now: now) else {
            engine.subtitleLog.write("OCR: son yeniden açılış çok yakın; yeniden açılmıyor")
            return
        }
        relaunching = true
        defaults.set(now, forKey: StuckRecoveryRules.lastRelaunchKey)
        let logs = engine.env.identity.logsFolder
        let translating = engine.state.translation != .off
        Task { [engine] in
            await Self.sampleSelf(into: logs)
            if translating {
                defaults.set(Date().timeIntervalSince1970, forKey: DefaultsKey.resumeAfterRelaunch)
                engine.stopTranslation()
                await engine.lastStop?.value
            }
            engine.subtitleLog.write("OCR: uygulama yeniden açılıyor")
            engine.subtitleLog.flush()
            Self.relaunch()
        }
    }

    /// `sample` ile 3 sn'lik süreç örneği (`ocr-takilma-<zaman>.txt`).
    static func sampleSelf(into folder: URL) async {
        let file = folder.appendingPathComponent("ocr-takilma-\(DebugFrameRules.stamp(Date())).txt")
        let pid = ProcessInfo.processInfo.processIdentifier
        await Task.detached {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/sample")
            p.arguments = ["\(pid)", "3", "-file", file.path]
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            guard (try? p.run()) != nil else { return }
            p.waitUntilExit()
        }.value
    }

    static func relaunch() {
        let path = Bundle.main.bundlePath
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 1; /usr/bin/open -n \"$0\"", path]
        try? p.run()
        NSApp.terminate(nil)
    }
}
