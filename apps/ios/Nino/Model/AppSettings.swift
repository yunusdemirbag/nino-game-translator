// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// Oyun karesinde oransal bölge (0–1; üst/alt yüksekliğe, sol/sağ genişliğe göre).
struct CropRegion: Codable, Equatable, Hashable {
    var top: Double
    var bottom: Double
    var left: Double
    var right: Double

    static let bottomArea = CropRegion(top: 0.62, bottom: 0.97, left: 0.14, right: 0.86)
    static let topArea = CropRegion(top: 0.03, bottom: 0.38, left: 0.14, right: 0.86)
    static let full = CropRegion(top: 0, bottom: 1, left: 0, right: 1)
    static let quest = CropRegion(top: 0.03, bottom: 0.30, left: 0.66, right: 0.98)
    static let notification = CropRegion(top: 0.58, bottom: 0.88, left: 0.02, right: 0.30)
    static let phone = CropRegion(top: 0.50, bottom: 0.95, left: 0.72, right: 0.98)

    func isClose(to other: CropRegion, tolerance: Double = 0.001) -> Bool {
        abs(top - other.top) <= tolerance && abs(bottom - other.bottom) <= tolerance
            && abs(left - other.left) <= tolerance && abs(right - other.right) <= tolerance
    }

    /// En küçük boyutu ve 0–1 sınırını korur.
    func clamped(minSize: Double = 0.05) -> CropRegion {
        var r = self
        r.left = min(max(0, r.left), 1 - minSize)
        r.top = min(max(0, r.top), 1 - minSize)
        r.right = min(max(r.left + minSize, r.right), 1)
        r.bottom = min(max(r.top + minSize, r.bottom), 1)
        return r
    }
}

enum AreaPreset: String, Codable, CaseIterable {
    case bottom, top, full, custom

    var region: CropRegion? {
        switch self {
        case .bottom: .bottomArea
        case .top: .topArea
        case .full: .full
        case .custom: nil
        }
    }

    static func matching(_ region: CropRegion) -> AreaPreset {
        for p in [AreaPreset.bottom, .top, .full] where p.region!.isClose(to: region) { return p }
        return .custom
    }
}

/// Altyazının yanında sürekli okunan ek alan (görev, bildirim, telefon).
struct ExtraArea: Codable, Equatable, Identifiable {
    static let maxCount = 3
    var id: String
    var name: String
    var region: CropRegion
    var enabled: Bool

    init(id: String = UUID().uuidString, name: String, region: CropRegion, enabled: Bool = true) {
        self.id = id
        self.name = name
        self.region = region
        self.enabled = enabled
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        region = try c.decodeIfPresent(CropRegion.self, forKey: .region) ?? .quest
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    }
}

/// Altyazının görünümü (TV ve telefon).
struct SubtitleStyle: Codable, Equatable {
    var fontSize = 46
    var bottomPercent = 7
    var placement = "cover"
    var background = 100
    var backgroundShape = "fit"
    var bold = false
    var textColor = "white"
    var displayMode = "inApp"
    var stackPrevious = true
    var theme = "classic"
    var autoSize = true
    var font: SubtitleTypeface = .action
    var watermark = true

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = SubtitleStyle()
        fontSize = try c.decodeIfPresent(Int.self, forKey: .fontSize) ?? d.fontSize
        bottomPercent = try c.decodeIfPresent(Int.self, forKey: .bottomPercent) ?? d.bottomPercent
        placement = Self.oneOf((try? c.decodeIfPresent(String.self, forKey: .placement)) ?? nil,
                               ["cover", "above", "below", "fixed"], d.placement)
        background = try c.decodeIfPresent(Int.self, forKey: .background) ?? d.background
        backgroundShape = Self.oneOf((try? c.decodeIfPresent(String.self, forKey: .backgroundShape)) ?? nil,
                                     ["fit", "band"], d.backgroundShape)
        bold = try c.decodeIfPresent(Bool.self, forKey: .bold) ?? d.bold
        textColor = Self.oneOf((try? c.decodeIfPresent(String.self, forKey: .textColor)) ?? nil, ["white", "yellow"], d.textColor)
        displayMode = Self.oneOf((try? c.decodeIfPresent(String.self, forKey: .displayMode)) ?? nil, ["inApp", "overlay"], d.displayMode)
        stackPrevious = try c.decodeIfPresent(Bool.self, forKey: .stackPrevious) ?? d.stackPrevious
        theme = Self.oneOf((try? c.decodeIfPresent(String.self, forKey: .theme)) ?? nil,
                           ["classic", "cinema", "minimal", "glass", "contrast", "outline"], d.theme)
        autoSize = ((try? c.decodeIfPresent(Bool.self, forKey: .autoSize)) ?? nil) ?? d.autoSize
        font = ((try? c.decodeIfPresent(SubtitleTypeface.self, forKey: .font)) ?? nil) ?? d.font
        watermark = ((try? c.decodeIfPresent(Bool.self, forKey: .watermark)) ?? nil) ?? d.watermark
        if placement == "cover", background < 60 { background = 100 }
    }

    private static func oneOf(_ value: String?, _ allowed: [String], _ fallback: String) -> String {
        guard let value, allowed.contains(value) else { return fallback }
        return value
    }

    var isYellow: Bool { textColor == "yellow" }
    /// Kullanıcının boyutu, varsayılana (46) oranla; %80–%160 arası.
    var scale: Double { min(1.6, max(0.8, Double(fontSize) / 46)) }
}

enum TranslationEngine: String, Codable, CaseIterable {
    case deepL = "deepl", gemini, openAI = "openai", claude, local
}

/// Altyazının gösterildiği yer. `computer`: "TV'm yok", altyazı bu telefonda.
enum SubtitleOutputTarget: String, Codable {
    case tv, computer

    var showsOnPhone: Bool { self == .computer }
}

/// Kullanıcı ayarları. UserDefaults `settings` anahtarında önceki sürümle aynı JSON olarak durur. Bu sürümün
/// kullanmadığı alanlar (Mac'e özgü olanlar) kayıttan silinmez; yazarken korunur.
struct AppSettings: Equatable {
    var region = CropRegion.bottomArea
    var areaPreset = AreaPreset.bottom
    var extraAreas: [ExtraArea] = []
    var style = SubtitleStyle()
    var sourceLanguage = "en"
    var targetLanguage = "tr"
    var onlineTranslation = false
    var onlineEngine = TranslationEngine.deepL
    var geminiModel = "gemini-3.5-flash-lite"
    var openAIModel = "gpt-6-luna"
    var claudeModel = "claude-haiku-5-5"
    var localAIBaseURL = "http://localhost:11434/v1"
    var localAIModel = "translategemma:4b"
    var output = SubtitleOutputTarget.tv
    var gamePacks = true
    var sharePool = true
    var autoReport = true
    var translateCorners = true
    var askGame = true
    var showSpeakerNames = true
    var fastSubtitleDetection = false
    var xboxAudioOnDevice = true
    /// Xbox görüntüsü 720p (zayıf Wi-Fi'de daha az kopma; okuma için yeterli).
    var xboxLowResolution = false
    var homeStyle = "livingRoom"

    /// Kayıtta olup bu sürümün bilmediği alanlar.
    fileprivate var unknown: [String: Any] = [:]

    static func == (a: AppSettings, b: AppSettings) -> Bool {
        a.region == b.region && a.areaPreset == b.areaPreset && a.extraAreas == b.extraAreas && a.style == b.style
            && a.sourceLanguage == b.sourceLanguage && a.targetLanguage == b.targetLanguage
            && a.onlineTranslation == b.onlineTranslation && a.onlineEngine == b.onlineEngine
            && a.geminiModel == b.geminiModel && a.openAIModel == b.openAIModel && a.claudeModel == b.claudeModel
            && a.localAIBaseURL == b.localAIBaseURL && a.localAIModel == b.localAIModel && a.output == b.output
            && a.gamePacks == b.gamePacks && a.sharePool == b.sharePool && a.autoReport == b.autoReport
            && a.translateCorners == b.translateCorners && a.askGame == b.askGame
            && a.showSpeakerNames == b.showSpeakerNames && a.fastSubtitleDetection == b.fastSubtitleDetection
            && a.xboxAudioOnDevice == b.xboxAudioOnDevice && a.homeStyle == b.homeStyle
            && a.xboxLowResolution == b.xboxLowResolution
    }

    /// İlk açılış ayarları: çeviri dili sistem dilinden.
    static func firstLaunch(preferredLanguages: [String] = Locale.preferredLanguages) -> AppSettings {
        var s = AppSettings()
        s.targetLanguage = Languages.preferred(preferredLanguages)
        return s
    }

    mutating func selectAreaPreset(_ preset: AreaPreset) {
        areaPreset = preset
        if let r = preset.region { region = r }
    }

    mutating func setCustomRegion(_ r: CropRegion) {
        region = r
        areaPreset = .custom
    }

    /// Paketler yalnız İngilizce→Türkçe çalışır.
    var packsActive: Bool { gamePacks && sourceLanguage == "en" && Languages.isTurkish(targetLanguage) }
}

// MARK: Kayıt biçimi

extension AppSettings: Codable {
    private enum K: String, CodingKey, CaseIterable {
        case region, areaPreset, extraAreas, style, sourceLanguage, targetLanguage, onlineTranslation, onlineEngine,
             geminiModel, openAIModel, claudeModel, localAIBaseURL, localAIModel, output, gamePacks, sharePool,
             autoReport, translateCorners, askGame, showSpeakerNames, fastSubtitleDetection, xboxAudioOnDevice,
             homeStyle, xboxLowResolution
    }

    /// Kurallar (önceki sürümle aynı): "zorunlu" alanın tipi yanlışsa çözme başarısız olur (bütün ayar sıfırlanır);
    /// "hoşgörülü" alan okunamazsa varsayılan alınır.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        let d = AppSettings()
        region = try c.decodeIfPresent(CropRegion.self, forKey: .region) ?? d.region
        if let p = (try? c.decodeIfPresent(AreaPreset.self, forKey: .areaPreset)) ?? nil {
            areaPreset = p
        } else {
            areaPreset = .matching(region)
        }
        extraAreas = Array((((try? c.decodeIfPresent([ExtraArea].self, forKey: .extraAreas)) ?? nil) ?? []).prefix(ExtraArea.maxCount))
        style = try c.decodeIfPresent(SubtitleStyle.self, forKey: .style) ?? d.style
        sourceLanguage = try c.decodeIfPresent(String.self, forKey: .sourceLanguage) ?? d.sourceLanguage
        targetLanguage = try c.decodeIfPresent(String.self, forKey: .targetLanguage) ?? d.targetLanguage
        onlineTranslation = try c.decodeIfPresent(Bool.self, forKey: .onlineTranslation) ?? d.onlineTranslation
        let engineRaw = (try? c.decodeIfPresent(String.self, forKey: .onlineEngine)) ?? nil
        onlineEngine = engineRaw.flatMap(TranslationEngine.init(rawValue:)) ?? d.onlineEngine
        geminiModel = try c.decodeIfPresent(String.self, forKey: .geminiModel) ?? d.geminiModel
        openAIModel = try c.decodeIfPresent(String.self, forKey: .openAIModel) ?? d.openAIModel
        claudeModel = try c.decodeIfPresent(String.self, forKey: .claudeModel) ?? d.claudeModel
        localAIBaseURL = try c.decodeIfPresent(String.self, forKey: .localAIBaseURL) ?? d.localAIBaseURL
        localAIModel = try c.decodeIfPresent(String.self, forKey: .localAIModel) ?? d.localAIModel
        if localAIModel == "qwen2.5:7b" || localAIModel.isEmpty { localAIModel = d.localAIModel }
        let outputRaw = (try? c.decodeIfPresent(String.self, forKey: .output)) ?? nil
        output = outputRaw == "computer" ? .computer : .tv
        gamePacks = try c.decodeIfPresent(Bool.self, forKey: .gamePacks) ?? d.gamePacks
        sharePool = try c.decodeIfPresent(Bool.self, forKey: .sharePool) ?? d.sharePool
        autoReport = ((try? c.decodeIfPresent(Bool.self, forKey: .autoReport)) ?? nil) ?? d.autoReport
        translateCorners = ((try? c.decodeIfPresent(Bool.self, forKey: .translateCorners)) ?? nil) ?? d.translateCorners
        askGame = try c.decodeIfPresent(Bool.self, forKey: .askGame) ?? d.askGame
        showSpeakerNames = try c.decodeIfPresent(Bool.self, forKey: .showSpeakerNames) ?? d.showSpeakerNames
        fastSubtitleDetection = try c.decodeIfPresent(Bool.self, forKey: .fastSubtitleDetection) ?? d.fastSubtitleDetection
        xboxAudioOnDevice = try c.decodeIfPresent(Bool.self, forKey: .xboxAudioOnDevice) ?? d.xboxAudioOnDevice
        xboxLowResolution = ((try? c.decodeIfPresent(Bool.self, forKey: .xboxLowResolution)) ?? nil) ?? d.xboxLowResolution
        let home = (try? c.decodeIfPresent(String.self, forKey: .homeStyle)) ?? nil
        homeStyle = ["livingRoom", "toggle"].contains(home ?? "") ? home! : d.homeStyle
        // Önceki sürümün zorunlu tuttuğu, bu sürümün kullanmadığı alanların tipi de denetlenir.
        let raw = try decoder.singleValueContainer().decode(AnyJSON.self)
        guard case let .object(dict) = raw else { throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "nesne değil")) }
        if let v = dict["overlayClickThrough"], !v.isBool { throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "overlayClickThrough")) }
        let known = Set(K.allCases.map(\.rawValue))
        unknown = dict.filter { !known.contains($0.key) }.mapValues(\.foundation)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: K.self)
        try c.encode(region, forKey: .region)
        try c.encode(areaPreset, forKey: .areaPreset)
        try c.encode(extraAreas, forKey: .extraAreas)
        try c.encode(style, forKey: .style)
        try c.encode(sourceLanguage, forKey: .sourceLanguage)
        try c.encode(targetLanguage, forKey: .targetLanguage)
        try c.encode(onlineTranslation, forKey: .onlineTranslation)
        try c.encode(onlineEngine, forKey: .onlineEngine)
        try c.encode(geminiModel, forKey: .geminiModel)
        try c.encode(openAIModel, forKey: .openAIModel)
        try c.encode(claudeModel, forKey: .claudeModel)
        try c.encode(localAIBaseURL, forKey: .localAIBaseURL)
        try c.encode(localAIModel, forKey: .localAIModel)
        try c.encode(output, forKey: .output)
        try c.encode(gamePacks, forKey: .gamePacks)
        try c.encode(sharePool, forKey: .sharePool)
        try c.encode(autoReport, forKey: .autoReport)
        try c.encode(translateCorners, forKey: .translateCorners)
        try c.encode(askGame, forKey: .askGame)
        try c.encode(showSpeakerNames, forKey: .showSpeakerNames)
        try c.encode(fastSubtitleDetection, forKey: .fastSubtitleDetection)
        try c.encode(xboxAudioOnDevice, forKey: .xboxAudioOnDevice)
        try c.encode(xboxLowResolution, forKey: .xboxLowResolution)
        try c.encode(homeStyle, forKey: .homeStyle)
    }

    /// UserDefaults'tan okur; yoksa ya da açılamazsa ilk açılış ayarları.
    static func load(from defaults: UserDefaults, preferredLanguages: [String] = Locale.preferredLanguages) -> AppSettings {
        guard let data = defaults.data(forKey: Keys.settings),
              let s = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return .firstLaunch(preferredLanguages: preferredLanguages)
        }
        return s
    }

    /// JSON verisi: bilinen alanlar ve kayıtta duran bilinmeyen alanlar birlikte.
    func encoded() -> Data? {
        guard let known = try? JSONEncoder().encode(self),
              var dict = (try? JSONSerialization.jsonObject(with: known)) as? [String: Any] else { return nil }
        for (k, v) in unknown where dict[k] == nil { dict[k] = v }
        return try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys])
    }

    func save(to defaults: UserDefaults) {
        if let data = encoded() { defaults.set(data, forKey: Keys.settings) }
    }
}

/// Bilinmeyen JSON değerlerini taşımak için.
enum AnyJSON: Decodable {
    case null, bool(Bool), number(Double), string(String), array([AnyJSON]), object([String: AnyJSON])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([AnyJSON].self) { self = .array(a) }
        else { self = .object(try c.decode([String: AnyJSON].self)) }
    }

    var isBool: Bool { if case .bool = self { true } else { false } }

    var foundation: Any {
        switch self {
        case .null: NSNull()
        case let .bool(b): b
        case let .number(n): n.rounded() == n && abs(n) < 1e15 ? Int(n) as Any : n as Any
        case let .string(s): s
        case let .array(a): a.map(\.foundation)
        case let .object(o): o.mapValues(\.foundation)
        }
    }
}
