// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import CoreGraphics
import Foundation
import NinoCore
import Observation

// Ayarlar penceresinin okuduğu, motorun yazdığı durum (docs/yeni/mac/ayarlar.md).
// Gizli bilgiler (anahtarlar, PS5 giriş şifresi) burada durmaz; yalnız "kayıtlı mı" bilgisi durur.

@MainActor
@Observable
public final class SettingsStatus {
    /// PS5 giriş şifresi Anahtar Zinciri'nde kayıtlı mı (§5).
    public var passcodeSaved: Bool = false
    /// Anahtarı Anahtar Zinciri'nde kayıtlı olan motorlar (DeepL, Gemini, OpenAI, Claude, yerel).
    public var savedKeys: Set<MacSettings.OnlineEngine> = []
    /// Son anahtar denemesinin sonucu, motor başına (§7.5–7.7).
    public var engineTests: [MacSettings.OnlineEngine: EngineTest] = [:]
    /// DeepL'in bu ayki kullanımı (§7.6).
    public var deepLUsage: DeepLUsage?
    /// Bu bilgisayarda Ollama çalışıyor mu (§7.7).
    public var ollama: OllamaStatus = .checking
    /// Ollama'da kurulu modeller.
    public var installedLocalModels: [String] = []
    /// Süren model indirmesi.
    public var localDownload: LocalModelDownload?
    /// Son indirme yarım kaldı mı.
    public var localDownloadFailed: Bool = false
    /// Altyazı sunucusunun kapısı (OBS adresi, §8).
    public var overlayServerPort: Int = 8787
    /// Bu Mac'in yerel ağ adresi; bulunamazsa nil.
    public var networkAddress: String?
    /// Kurulu oyun paketleri (§14.3).
    public var gamePacks: [GamePackInfo] = []
    /// İçe aktarılmayı bekleyen paket (önizleme sayfası).
    public var packImport: GamePackImport?
    /// İçe aktarma ya da kurma hatası.
    public var packError: GamePackError?
    /// Son PS5 karesi (Altyazı alanı önizlemesi); yoksa nil.
    public var lastFrame: CGImage?

    public init() {}
}

/// Bir çeviri motoru denemesinin sonucu.
public enum EngineTest: Equatable, Sendable {
    case testing
    /// Çalışıyor; örnek çeviri.
    case works(sample: String)
    case failed(EngineFailure)
}

/// Motor denemesinin hata türü (§7.8). Metinleri `SettingsEngineText` üretir.
public enum EngineFailure: Equatable, Sendable {
    case badKey
    /// Sınır doldu. Gemini'de günlük hakkın yenileneceği an (bilinmiyorsa kural ile hesaplanır).
    case quota
    case modelRejected
    case unreachable
    /// Yerel model sunucusu anahtarı kabul etmedi.
    case localBadKey
    case localBusy
    /// Yerel sunucuda bu model yok.
    case localModelMissing
    /// Yerel sunucuya ulaşılamadı ya da model zamanında yanıt vermedi.
    case localUnreachable
}

public enum DeepLUsage: Equatable, Sendable {
    case checking
    case used(characters: Int, limit: Int)
    case limitReached
    case badKey
    case unreachable
}

public enum OllamaStatus: Equatable, Sendable { case checking, running, notRunning }

public struct LocalModelDownload: Equatable, Sendable {
    public var model: String
    /// 0…1
    public var progress: Double
    public init(model: String, progress: Double) {
        self.model = model
        self.progress = progress
    }
}

public struct GamePackInfo: Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var lines: Int
    public init(id: String, name: String, lines: Int) {
        self.id = id
        self.name = name
        self.lines = lines
    }
}

/// İçe aktarma önizlemesi (§14.3).
public struct GamePackImport: Equatable, Sendable {
    public var fileURL: URL
    public var suggestedTitle: String
    public var usable: Int
    public var invalid: Int
    public var duplicates: Int
    public var conflicts: Int
    public init(fileURL: URL, suggestedTitle: String, usable: Int, invalid: Int, duplicates: Int, conflicts: Int) {
        self.fileURL = fileURL
        self.suggestedTitle = suggestedTitle
        self.usable = usable
        self.invalid = invalid
        self.duplicates = duplicates
        self.conflicts = conflicts
    }
}

public enum GamePackError: Equatable, Sendable {
    case unreadable
    case badFormat
    /// Bu kimlikte paket zaten var (değiştirme onayı istenir).
    case alreadyExists(title: String)
    case sameFile
    case installFailed
}

// MARK: - Kurallar (görünümden bağımsız, sınanabilir)

public enum SettingsRules {
    /// PS5 giriş şifresi: boşluklar atılır; tam 4 ASCII rakam değilse nil.
    public static func passcode(_ input: String) -> String? {
        let digits = input.filter { !$0.isWhitespace }
        guard digits.count == 4, digits.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return digits
    }

    /// Konsol değişince: Xbox'a geçerken kaynak PS5 ise pencere olur. Aynı konsol tekrar seçilirse değişmez.
    public static func choosing(console: MacSettings.GameConsole, in settings: MacSettings) -> MacSettings {
        var s = settings
        guard s.gameConsole != console else { return s }
        s.gameConsole = console
        if console == .xbox, s.videoSource == .ps5 { s.videoSource = .window }
        return s
    }

    /// Görüntü kaynağı değişince: PS5'e dönülünce altyazı yeri TV olur.
    public static func choosing(source: MacSettings.VideoSource, in settings: MacSettings) -> MacSettings {
        var s = settings
        s.videoSource = source
        if source == .ps5 { s.output = .tv }
        return s
    }

    /// Motor seçimi: Ücretsiz (nil) çevrimiçi çeviriyi kapatır, son çevrimiçi motor hatırlanır.
    public static func choosing(engine: MacSettings.OnlineEngine?, in settings: MacSettings) -> MacSettings {
        var s = settings
        if let engine {
            s.onlineTranslation = true
            s.onlineEngine = engine
        } else {
            s.onlineTranslation = false
        }
        return s
    }

    /// Seçili motor (Ücretsiz için nil).
    public static func selectedEngine(_ settings: MacSettings) -> MacSettings.OnlineEngine? {
        settings.onlineTranslation ? settings.onlineEngine : nil
    }

    /// Yerel sunucunun türü; adres geçersizse Ollama varsayılanı.
    public static func localServerKind(_ address: String) -> LocalModelServer.Kind {
        guard let url = LocalModelServer.normalize(address) else { return .ollama }
        return LocalModelServer.kind(url)
    }

    /// Gemini'nin günlük hakkının yenileneceği an: bir sonraki Pasifik saatiyle gece yarısı.
    public static func nextPacificMidnight(after date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .current
        let start = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: 1, to: start) ?? date.addingTimeInterval(86_400)
    }

    /// Yazı boyu kaydırıcısı ve önizleme: otomatik boy açıksa ölçülen boy (önizlemede 38, TV sayfası gibi %25
    /// büyütülmüş) × kullanıcının çarpanı (TV ile aynı kural: fontSize / 46, 0,5–2,5), kapalıysa seçili boy.
    public static let autoSizeBoost: CGFloat = 1.25
    public static func previewFontSize(_ style: SubtitleStyle, width: CGFloat) -> CGFloat {
        let base = style.autoSize ? 38 * autoSizeBoost * autoSizeScale(style.fontSize) : CGFloat(style.fontSize)
        return max(10, base / 1920 * width * 1.6)
    }

    /// Otomatik boyda kullanıcının yazı boyu çarpan olarak uygulanır (TV sayfasının `autoFont` kuralı).
    public static func autoSizeScale(_ fontSize: Int) -> CGFloat {
        guard fontSize > 0 else { return 1 }
        return min(2.5, max(0.5, CGFloat(fontSize) / 46))
    }

    /// Önerilen yerel modeller (§7.7). İlki varsayılandır.
    public static let suggestedLocalModels: [SuggestedLocalModel] = [
        SuggestedLocalModel(id: "translategemma:4b", name: "TranslateGemma 4B", detailKey: "settings.local.model.gemma4b",
                            sizeGB: 3.3, recommended: true),
        SuggestedLocalModel(id: "translategemma:12b", name: "TranslateGemma 12B", detailKey: "settings.local.model.gemma12b",
                            sizeGB: 8.1, recommended: false),
        SuggestedLocalModel(id: "milmmt:4b", name: "MiLMMT 4B", detailKey: "settings.local.model.milmmt",
                            sizeGB: 3.1, recommended: false),
    ]
}

public struct SuggestedLocalModel: Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var detailKey: String
    public var sizeGB: Double
    public var recommended: Bool
}

// MARK: - Ayarlar eylemleri

public extension AppState {
    func savePS5Passcode(_ code: String) { engine?.savePS5Passcode(code) }
    func removePS5Passcode() { engine?.removePS5Passcode() }
    func saveTranslationKey(_ key: String, for engine: MacSettings.OnlineEngine) {
        self.engine?.saveTranslationKey(key, for: engine)
    }
    func testTranslationEngine(_ engine: MacSettings.OnlineEngine) { self.engine?.testTranslationEngine(engine) }
    func removeTranslationKey(for engine: MacSettings.OnlineEngine) { self.engine?.removeTranslationKey(for: engine) }
    func refreshDeepLUsage() { engine?.refreshDeepLUsage() }
    func checkOllama() { engine?.checkOllama() }
    func downloadLocalModel(_ model: String) { engine?.downloadLocalModel(model) }
    func forceCheckForUpdates() { engine?.forceCheckForUpdates() }
    func openReleaseNotes() { engine?.openReleaseNotes() }
    func resetFromTV() { engine?.resetFromTV() }
    func resetEverything() { engine?.resetEverything() }
    func prepareGamePackImport(_ url: URL) { engine?.prepareGamePackImport(url) }
    func installGamePack(title: String, replacing: Bool) { engine?.installGamePack(title: title, replacing: replacing) }
    func cancelGamePackImport() {
        settingsStatus.packImport = nil
        engine?.cancelGamePackImport()
    }
}

// MARK: - Motorun ayarlar yöntemleri (varsayılanları: hiçbir şey yapmaz)

public extension AppEngine {
    func savePS5Passcode(_ code: String) {}
    func removePS5Passcode() {}
    func saveTranslationKey(_ key: String, for engine: MacSettings.OnlineEngine) {}
    func testTranslationEngine(_ engine: MacSettings.OnlineEngine) {}
    func removeTranslationKey(for engine: MacSettings.OnlineEngine) {}
    func refreshDeepLUsage() {}
    func checkOllama() {}
    func downloadLocalModel(_ model: String) {}
    func forceCheckForUpdates() { checkForUpdates() }
    func openReleaseNotes() {}
    func resetFromTV() {}
    func resetEverything() {}
    func prepareGamePackImport(_ url: URL) {}
    func installGamePack(title: String, replacing: Bool) {}
    func cancelGamePackImport() {}
}

// MARK: - Sahte motorun ayarlar karşılıkları

public extension PreviewEngine {
    func savePS5Passcode(_ code: String) {
        guard SettingsRules.passcode(code) != nil else { return }
        state?.settingsStatus.passcodeSaved = true
    }

    func removePS5Passcode() { state?.settingsStatus.passcodeSaved = false }

    func saveTranslationKey(_ key: String, for engine: MacSettings.OnlineEngine) {
        guard let state, !key.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        state.settingsStatus.savedKeys.insert(engine)
        testTranslationEngine(engine)
    }

    func testTranslationEngine(_ engine: MacSettings.OnlineEngine) {
        guard let status = state?.settingsStatus else { return }
        if engine == .deepl {
            status.deepLUsage = .used(characters: 12_480, limit: 500_000)
        } else {
            status.engineTests[engine] = .works(sample: "BATMAN: Ben Batman'im.")
        }
    }

    func removeTranslationKey(for engine: MacSettings.OnlineEngine) {
        guard let status = state?.settingsStatus else { return }
        status.savedKeys.remove(engine)
        status.engineTests[engine] = nil
        if engine == .deepl { status.deepLUsage = nil }
    }

    func refreshDeepLUsage() {
        guard let status = state?.settingsStatus, status.savedKeys.contains(.deepl) else { return }
        status.deepLUsage = .used(characters: 12_480, limit: 500_000)
    }

    func checkOllama() { state?.settingsStatus.ollama = .running }

    func downloadLocalModel(_ model: String) {
        guard let state else { return }
        state.settings.localAIModel = model
        if !state.settingsStatus.installedLocalModels.contains(model) {
            state.settingsStatus.installedLocalModels.append(model)
        }
    }

    func resetFromTV() {
        guard let state else { return }
        state.stopTranslation()
        state.pairedTV = nil
        state.activeSheet = nil
        state.setupOpenedFromHome = false
        state.setupStep = .tv
    }

    func resetEverything() {
        guard let state else { return }
        state.stopTranslation()
        state.pairedTV = nil
        state.pairedConsole = nil
        state.psnAccount = .signedOut
        state.settingsStatus.passcodeSaved = false
        state.activeSheet = nil
        state.setupOpenedFromHome = false
        state.setupStep = .welcome
    }

    func installGamePack(title: String, replacing: Bool) {
        guard let state, let pending = state.settingsStatus.packImport else { return }
        state.settingsStatus.gamePacks.append(GamePackInfo(id: UUID().uuidString, name: title, lines: pending.usable))
        state.settingsStatus.packImport = nil
    }
}
