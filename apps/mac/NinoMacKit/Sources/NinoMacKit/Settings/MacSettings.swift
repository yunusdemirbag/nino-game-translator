// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// Mac uygulamasının bütün ayarları. Diskte UserDefaults'taki `settings` anahtarında
/// tek bir JSON nesnesi olarak durur (docs/yeni/mac/veri-uyumu.md §1).
///
/// Okuma hoşgörülüdür: her alan ayrı okunur, tanınmayan değer yalnız o alanı
/// varsayılana düşürür. Tanınmayan alanlar kaybolmaz; yazarken olduğu gibi geri
/// konur, böylece eski sürüme dönen kullanıcı da ayarlarını bulur.
public struct MacSettings: Equatable, Sendable {
    public var region: Region = .bottomPreset
    public var areaPreset: AreaPreset? = nil
    public var extraAreas: [ExtraArea] = []
    public var style: SubtitleStyle = SubtitleStyle()
    public var sourceLanguage: String = "en"
    public var targetLanguage: String = "tr"
    public var onlineTranslation: Bool = false
    public var onlineEngine: OnlineEngine = .deepl
    public var geminiModel: String = ""
    public var openAIModel: String = ""
    public var claudeModel: String = ""
    public var localAIBaseURL: String = LocalServer.ollama.baseURL
    public var localAIModel: String = MacSettings.defaultLocalModel
    public var output: Output = .tv
    public var overlayClickThrough: Bool = false
    public var videoSource: VideoSource = .ps5
    public var gameConsole: GameConsole = .ps5
    public var gamePacks: Bool = true
    public var sharePool: Bool = true
    public var autoReport: Bool = true
    public var translateCorners: Bool = true
    public var askGame: Bool = true
    public var showSpeakerNames: Bool = true
    public var fastSubtitleDetection: Bool = false
    /// "Yalnız altyazıyı çevir": görev/ipucu/sekme satırları ana altyazıdan atılır (eski kayıtta yoksa kapalı).
    public var subtitlesOnly: Bool = false
    public var xboxAudioOnDevice: Bool = true
    public var appearance: Appearance = .system
    public var homeStyle: HomeStyle = .livingRoom
    public var frameSource: String = "ps5"
    public var remotePlayApp: RemotePlayApp = .automatic

    /// Bu sürümün tanımadığı alanlar (ör. kaldırılmış dublaj ayarı). Yazarken geri konur.
    public var unknownFields: [String: JSONValue] = [:]

    public static let defaultLocalModel = "translategemma:4b"
    static let retiredLocalModel = "qwen2.5:7b"
    public static let maxExtraAreas = 3

    public init() {}

    /// Çeviri dili seçenekleri. Filipince ayarda `tl` olarak tutulur.
    public static let targetLanguages = ["tr", "ar", "hi", "id", "th", "vi", "ur", "bn", "ms", "tl", "nl"]
    public static let rightToLeftLanguages: Set<String> = ["ar", "ur"]

    /// Hiç ayar yokken: sistem dili listedeyse o, değilse Türkçe.
    public static func fresh(preferredLanguages: [String] = Locale.preferredLanguages) -> MacSettings {
        var s = MacSettings()
        s.targetLanguage = initialTarget(preferredLanguages: preferredLanguages)
        return s
    }

    static func initialTarget(preferredLanguages: [String]) -> String {
        guard let first = preferredLanguages.first else { return "tr" }
        var code = String(first.prefix { $0 != "-" && $0 != "_" }).lowercased()
        if code == "fil" { code = "tl" }
        return targetLanguages.contains(code) ? code : "tr"
    }

    /// Okuduktan sonra uygulanan düzeltmeler. Bir şey değiştiyse `true` döner
    /// (çağıran ayarı hemen geri yazar).
    @discardableResult
    public mutating func normalize(models: ModelCatalog = .standard) -> Bool {
        let before = self
        if output == .both { output = .tv }
        if localAIModel == Self.retiredLocalModel { localAIModel = Self.defaultLocalModel }
        if !models.gemini.contains(geminiModel) { geminiModel = models.gemini.first ?? "" }
        if !models.openAI.contains(openAIModel) { openAIModel = models.openAI.first ?? "" }
        if !models.claude.contains(claudeModel) { claudeModel = models.claude.first ?? "" }
        if extraAreas.count > Self.maxExtraAreas { extraAreas = Array(extraAreas.prefix(Self.maxExtraAreas)) }
        if style.placement == .cover && style.background < 60 { style.background = 100 }
        if areaPreset == nil { areaPreset = AreaPreset.matching(region) }
        return self != before
    }

    public var isRightToLeft: Bool { Self.rightToLeftLanguages.contains(targetLanguage) }
}

// MARK: - Seçenekler

extension MacSettings {
    public enum OnlineEngine: String, CaseIterable, Sendable { case deepl, gemini, openai, claude, local }
    public enum Output: String, CaseIterable, Sendable { case tv, computer, both }
    public enum VideoSource: String, CaseIterable, Sendable { case ps5, window, card }
    public enum GameConsole: String, CaseIterable, Sendable { case ps5, xbox }
    public enum Appearance: String, CaseIterable, Sendable { case dark, light, system }
    public enum HomeStyle: String, CaseIterable, Sendable { case livingRoom, toggle }
    public enum RemotePlayApp: String, CaseIterable, Sendable { case automatic, sony, chiaki }

    public enum LocalServer: CaseIterable, Sendable {
        case ollama, lmStudio
        public var baseURL: String {
            switch self {
            case .ollama: return "http://localhost:11434/v1"
            case .lmStudio: return "http://localhost:1234/v1"
            }
        }
    }

    /// Kendi anahtarıyla kullanılan yapay zekâ modelleri; ilki varsayılandır.
    public struct ModelCatalog: Sendable {
        public var gemini: [String]
        public var openAI: [String]
        public var claude: [String]
        public init(gemini: [String], openAI: [String], claude: [String]) {
            self.gemini = gemini
            self.openAI = openAI
            self.claude = claude
        }
        public static let standard = ModelCatalog(
            gemini: ["gemini-3.5-flash-lite", "gemini-3.6-flash"],
            openAI: ["gpt-6-luna", "gpt-6.1-terra"],
            claude: ["claude-haiku-5-5", "claude-sonnet-5-5"])
    }
}

// MARK: - Bölge

/// Karenin üstünden ve solundan 0–1 oranlarla bir dikdörtgen.
public struct Region: Equatable, Sendable, Codable {
    public var top: Double
    public var bottom: Double
    public var left: Double
    public var right: Double

    public init(top: Double, bottom: Double, left: Double, right: Double) {
        self.top = top
        self.bottom = bottom
        self.left = left
        self.right = right
    }

    public static let minimumSize = 0.05
    public static let bottomPreset = Region(top: 0.62, bottom: 0.97, left: 0.14, right: 0.86)
    public static let topPreset = Region(top: 0.03, bottom: 0.38, left: 0.14, right: 0.86)
    public static let fullPreset = Region(top: 0, bottom: 1, left: 0, right: 1)

    public var width: Double { right - left }
    public var height: Double { bottom - top }

    func isClose(to other: Region, tolerance: Double = 0.001) -> Bool {
        let gaps = [top - other.top, bottom - other.bottom, left - other.left, right - other.right]
        return gaps.allSatisfy { abs($0) <= tolerance }
    }
}

public enum AreaPreset: String, CaseIterable, Sendable {
    case bottom, top, full, custom

    public var region: Region? {
        switch self {
        case .bottom: return .bottomPreset
        case .top: return .topPreset
        case .full: return .fullPreset
        case .custom: return nil
        }
    }

    static func matching(_ region: Region) -> AreaPreset {
        for preset in [AreaPreset.bottom, .top, .full] where preset.region!.isClose(to: region) { return preset }
        return .custom
    }
}

/// Sürekli okunan ek alan (görev, bildirim, telefon).
public struct ExtraArea: Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var region: Region
    public var enabled: Bool

    public init(id: String = UUID().uuidString, name: String = "", region: Region = ExtraArea.questPreset, enabled: Bool = true) {
        self.id = id
        self.name = name
        self.region = region
        self.enabled = enabled
    }

    public static let questPreset = Region(top: 0.03, bottom: 0.30, left: 0.66, right: 0.98)
    public static let notificationPreset = Region(top: 0.58, bottom: 0.88, left: 0.02, right: 0.30)
    public static let phonePreset = Region(top: 0.50, bottom: 0.95, left: 0.72, right: 0.98)
}

// MARK: - Altyazı stili

public struct SubtitleStyle: Equatable, Sendable {
    public enum Placement: String, CaseIterable, Sendable { case cover, above, below, fixed }
    public enum Shape: String, CaseIterable, Sendable { case fit, band }
    public enum TextColor: String, CaseIterable, Sendable { case white, yellow }
    public enum DisplayMode: String, CaseIterable, Sendable { case inApp, overlay }
    public enum Theme: String, CaseIterable, Sendable { case classic, cinema, minimal, glass, contrast, outline }
    public enum Font: String, CaseIterable, Sendable { case system, modern, condensed, rounded }

    public var fontSize: Int = 46
    public var bottomPercent: Int = 7
    public var placement: Placement = .cover
    public var background: Int = 100
    // Aşağıdaki altısı (backgroundShape, bold, textColor, theme, font, watermark) artık ayarlanmıyor ve
    // kaydedilmiyor: hep bu varsayılanlarla çizilir ve TV'ye gider (kayıttaki eski değerler `unknownFields`'ta).
    public var backgroundShape: Shape = .fit
    public var bold: Bool = false
    public var textColor: TextColor = .white
    public var displayMode: DisplayMode = .inApp
    public var stackPrevious: Bool = true
    public var theme: Theme = .classic
    public var autoSize: Bool = true
    public var font: Font = .condensed
    public var watermark: Bool = true

    /// Stil içindeki tanınmayan alanlar.
    public var unknownFields: [String: JSONValue] = [:]

    public static let sizeChoices = [36, 46, 58, 72]

    public init() {}

    /// Temanın renk, kalınlık ve zemin karşılığı (ekran görüntüsü testleri için; ayarlarda tema seçimi yok).
    public mutating func apply(theme: Theme) {
        self.theme = theme
        switch theme {
        case .classic: (textColor, bold, background) = (.white, false, 100)
        case .cinema: (textColor, bold, background) = (.yellow, true, 0)
        case .minimal: (textColor, bold, background) = (.white, false, 0)
        case .glass: (textColor, bold, background) = (.white, false, 62)
        case .contrast: (textColor, bold, background) = (.white, true, 100)
        case .outline: (textColor, bold, background) = (.white, true, 0)
        }
    }
}
