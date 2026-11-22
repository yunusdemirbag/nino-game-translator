// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation
import Observation

/// Ekranların okuduğu bütün durum ve çağırdığı bütün eylemler (docs/yeni/mac/ana-ekran.md §8).
///
/// Ekranlar yalnız bunu görür. İşi yapan taraf `AppEngine`'dir: eylemler ona gider,
/// o da sonuçları buraya yazar. Testlerde ve önizlemelerde `PreviewEngine` kullanılır.
@MainActor
@Observable
public final class AppState {
    // MARK: Ayarlar

    /// Değişince kaydedilir ve motora bildirilir (TV'ye stil gider vb.).
    public var settings: MacSettings {
        didSet {
            guard settings != oldValue else { return }
            engine?.settingsChanged(from: oldValue, to: settings)
        }
    }
    public internal(set) var adminMode: Bool = false
    /// Admin etiketleri görünür mü (yalnız geliştirici kimliği; `AdminModeRules.showsBadges`).
    public internal(set) var adminBadges: Bool = false

    // MARK: Kurulum

    public var setupStep: SetupStep = .welcome
    public var isSetupComplete: Bool { setupStep == .done }
    /// Ana ekrandan kurulumun belli bir adımına gidilince (konsol, TV) dönüş yeri.
    public var setupOpenedFromHome: Bool = false
    public var psnAccount: PSNAccountState = .signedOut
    public var pairing: PairingState = .idle
    public var pairedConsole: PairedConsole?
    public var pairedTV: PairedTV?
    public var tvInstall: TVInstallState = .idle
    /// Sihirbazın ayrıntılı durumu (SetupTypes.swift).
    public var setup = SetupDetail()

    // MARK: Çeviri

    public var translation: TranslationPhase = .off
    public var source: SourceStatus = .ps5(.idle)
    /// Bağlı TV uygulaması sayısı.
    public var connectedDisplays: Int = 0
    public var lastLine: LiveLine?
    public var game: RecognizedGame?
    public var translator: TranslatorReadiness = .ready
    public var onlineEngineProblem: OnlineEngineProblem?
    public var localNetworkBlocked: Bool = false
    public var textReadingFailure: TextReadingFailure?
    public var history: [HistoryEntry] = []

    // MARK: Pencereler

    public var overlayAdjusting: Bool = false
    public var cardFullScreen: Bool = false
    public var xboxStep: XboxStep = .notStarted
    public var activeSheet: Sheet?
    /// Yayın penceresi açık mı (Ayarlar › OBS açar, pencere kapanınca false).
    public var streamWindowOpen: Bool = false
    /// Yayın penceresinin zemini (ayrı küçük tercih: `streamBackground`).
    public var streamBackground: StreamBackground = .green
    /// Ek alan çevirileri (ekran dışı ve yayın penceresinin üstündeki kutular).
    public var extraAreaTexts: [ExtraAreaText] = []
    /// Oyun penceresinden okunurken oyun alanının ekrandaki yeri (AppKit ekran koordinatı); bilinmiyorsa nil.
    public var gameAreaFrame: CGRect?
    /// Admin modu: TV'nin gördüğünün bileşik karesi (PS5 + TV katmanı; 2 sn'de bir ve değişince). Normal kullanıcıda nil.
    public var adminTVPreview: AdminTVPreview?

    // MARK: Uygulama

    public var update: UpdateStatus = .idle
    public var downloadTotal: Int?
    /// Başlıktaki sürüm hapı ve Hakkında.
    public var version: AppVersionInfo = AppVersionInfo(short: "V4.1", full: "4.1.0")
    /// Kullanıcının oyun görselleri ("Covers" klasörü, `<oyun-kimliği>.png`); nil ise aranmaz.
    public var coversFolder: URL?
    public var health: HealthSnapshot = HealthSnapshot()
    /// Ayarlar penceresinin motordan gelen durumu (SettingsStatus.swift).
    public let settingsStatus = SettingsStatus()
    /// Sayfaların (Geçmiş, Sistem sağlığı, Sorun Bildir, Nino'ya Sor, oyun kartı) durumu (SheetsStatus.swift).
    public let sheetsStatus = SheetsStatus()
    /// Anahtar ve dil paketi önerilerinin kalıcı işaretleri (TranslationNudges.swift).
    public let nudges = TranslationNudges()

    public private(set) weak var engine: AppEngine?

    public init(settings: MacSettings = MacSettings()) {
        self.settings = settings
    }

    /// Motoru bağlar. Motor kendini burada tutmaz; sahibi uygulamadır.
    public func attach(_ engine: AppEngine) {
        self.engine = engine
    }

    // MARK: Türetilen kurallar (ana-ekran.md §8.1)

    /// Bu Mac'teki PS Remote Play penceresinden mi okunuyor (oyun bu bilgisayarda oynanıyor).
    public var readsPlayStationWindow: Bool {
        settings.videoSource == .window && settings.gameConsole == .ps5
    }

    public var subtitlesOnComputer: Bool {
        readsPlayStationWindow || settings.output == .computer || settings.output == .both
    }

    public var subtitlesOnTV: Bool {
        !readsPlayStationWindow && (settings.output == .tv || settings.output == .both)
    }

    public var tvReady: Bool { pairedTV?.hasKey == true }

    public var videoSourceReady: Bool {
        switch settings.videoSource {
        case .window: return true
        case .card: return true
        case .ps5: return pairedConsole != nil && psnAccount.isSignedIn
        }
    }

    public var canStart: Bool {
        if readsPlayStationWindow { return true }
        return videoSourceReady && (subtitlesOnComputer || tvReady)
    }

    public var isTranslating: Bool { translation == .on }

    // MARK: Eylemler

    public func startTranslation() { engine?.startTranslation() }
    public func stopTranslation() { engine?.stopTranslation() }
    public func toggleTranslation() { translation == .off ? startTranslation() : stopTranslation() }
    public func openSetup(at step: SetupStep) {
        setupOpenedFromHome = isSetupComplete
        setupStep = step
    }
    public func open(_ sheet: Sheet) { activeSheet = sheet }
    public func checkForUpdates() { engine?.checkForUpdates() }
    public func installUpdate() { engine?.installUpdate() }
    public func refreshDownloadTotal() { engine?.refreshDownloadTotal() }
}

/// İşi yapan taraf. Uygulamada `LiveEngine`, testlerde `PreviewEngine`.
@MainActor
public protocol AppEngine: AnyObject {
    func settingsChanged(from old: MacSettings, to new: MacSettings)
    func startTranslation()
    func stopTranslation()
    func checkForUpdates()
    func installUpdate()
    func refreshDownloadTotal()
    /// ⌥⌘T ekranı çevir ve iptali (AppSupport/ScreenTranslation.swift; varsayılanı hiçbir şey yapmaz).
    func translateScreen()
    func cancelScreenTranslation()

    // Kurulum (kurulum.md). Varsayılanları SetupTypes.swift'te: hiçbir şey yapmaz.
    func setupFinished()
    func beginPSNSignIn()
    func enterPSNAccountID(_ text: String) -> Bool
    func signOutPSN()
    var psnLoginController: PSNLoginController? { get }
    func searchConsoles()
    func pairConsole(address: String, code: String)
    func revealRemotePlayLog()
    func refreshRemotePlayApps()
    func searchTVs()
    func pairTV(_ tv: DiscoveredTV)
    func recheckTVApp()
    /// Kullanıcı istedi ("Tekrar Dene"): yakın zamanda doğrulanmış olsa da TV uygulaması yeniden denetlenir.
    func recheckTVAppNow()
    /// Eski TV uygulaması kuruluyken yenisini kur (eskisi yerinde kalır).
    func upgradeLegacyTVApp()
    func installTVApp(passphrase: String?)
    func samsungTryAnyway()
    func samsungTypeDeveloperCode()
    func reopenSamsungSignIn()
    func sendTestSubtitle()
    func saveGeminiKey(_ key: String)
    func installGreenlight()
    func openGreenlight()
    func setXboxPolling(_ on: Bool)
    func setCaptureCardPreview(_ on: Bool)
    func selectCaptureDevice(_ id: String?)

    // Ayarlar (ayarlar.md). Varsayılanları SettingsStatus.swift'te: hiçbir şey yapmaz.
    func savePS5Passcode(_ code: String)
    func removePS5Passcode()
    func saveTranslationKey(_ key: String, for engine: MacSettings.OnlineEngine)
    func testTranslationEngine(_ engine: MacSettings.OnlineEngine)
    func removeTranslationKey(for engine: MacSettings.OnlineEngine)
    func refreshDeepLUsage()
    func checkOllama()
    func downloadLocalModel(_ model: String)
    func forceCheckForUpdates()
    func openReleaseNotes()
    func resetFromTV()
    func resetEverything()
    func prepareGamePackImport(_ url: URL)
    func installGamePack(title: String, replacing: Bool)
    func cancelGamePackImport()

    // Sayfalar (gecmis-hakkinda-saglik.md, ninoya-sor.md). Varsayılanları SheetsStatus.swift'te: ağa çıkmaz.
    func clearHistory()
    func askAssistant(_ chat: [AssistantMessage]) async -> Result<AssistantReply, AssistantError>
    func sendProblemReport(_ report: ProblemReport) async -> Result<Void, ReportError>
    func saveLogsZip(details: String) async throws -> URL
}
