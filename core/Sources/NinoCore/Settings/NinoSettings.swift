// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// Kullanıcı ayarları. Dosyada olmayan her alan varsayılanını alır; böylece
/// eski bir ayar dosyası yeni sürümde de açılır.
public struct NinoSettings: Codable, Equatable, Sendable {
    public struct Reading: Codable, Equatable, Sendable {
        public var region: NormalizedRect = .defaultSubtitle
        public var minConfidence: Float = 0.40
        public var stableFrames: Int = 3
        public var missingFrames: Int = 2
        public var similarity: Double = 0.85
        public var ignoredPhrases: [String] = NoiseFilter.defaultIgnoredPhrases.sorted()

        public init() {}

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let d = Reading()
            region = try c.decodeIfPresent(NormalizedRect.self, forKey: .region) ?? d.region
            minConfidence = try c.decodeIfPresent(Float.self, forKey: .minConfidence) ?? d.minConfidence
            stableFrames = max(1, try c.decodeIfPresent(Int.self, forKey: .stableFrames) ?? d.stableFrames)
            missingFrames = max(1, try c.decodeIfPresent(Int.self, forKey: .missingFrames) ?? d.missingFrames)
            similarity = try c.decodeIfPresent(Double.self, forKey: .similarity) ?? d.similarity
            ignoredPhrases = try c.decodeIfPresent([String].self, forKey: .ignoredPhrases) ?? d.ignoredPhrases
        }
    }

    public struct Translation: Codable, Equatable, Sendable {
        public var sourceLanguage = "en"
        public var targetLanguage = "tr"
        /// Sırayla denenen sağlayıcılar. Anahtarları Keychain'dedir.
        public var providers: [HTTPTranslationProvider.Configuration] = []
        public var providerTimeoutSeconds: Double = 3
        /// Varsa Apple'ın cihaz içi çevirisini zincirin başına koy.
        public var useOnDevice = true
        public var userTerms: [Term] = []
        public var selectedGameID: String?

        public init() {}

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let d = Translation()
            sourceLanguage = try c.decodeIfPresent(String.self, forKey: .sourceLanguage) ?? d.sourceLanguage
            targetLanguage = try c.decodeIfPresent(String.self, forKey: .targetLanguage) ?? d.targetLanguage
            providers = try c.decodeIfPresent([HTTPTranslationProvider.Configuration].self, forKey: .providers) ?? d.providers
            providerTimeoutSeconds = try c.decodeIfPresent(Double.self, forKey: .providerTimeoutSeconds) ?? d.providerTimeoutSeconds
            useOnDevice = try c.decodeIfPresent(Bool.self, forKey: .useOnDevice) ?? d.useOnDevice
            userTerms = try c.decodeIfPresent([Term].self, forKey: .userTerms) ?? d.userTerms
            selectedGameID = try c.decodeIfPresent(String.self, forKey: .selectedGameID)
        }
    }

    public struct Display: Codable, Equatable, Sendable {
        /// Elle girilen TV adresi. Yoksa ağda aranır.
        public var host: String?
        public var port: UInt16 = NinoLink.defaultPort
        public var position: SubtitlePosition = .bottom
        public var autoDiscover = true
        /// Son bağlanılan TV'nin kimliği (TXT `id`).
        public var lastDisplayID: String?

        public init() {}

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let d = Display()
            host = try c.decodeIfPresent(String.self, forKey: .host)
            port = try c.decodeIfPresent(UInt16.self, forKey: .port) ?? d.port
            position = try c.decodeIfPresent(SubtitlePosition.self, forKey: .position) ?? d.position
            autoDiscover = try c.decodeIfPresent(Bool.self, forKey: .autoDiscover) ?? d.autoDiscover
            lastDisplayID = try c.decodeIfPresent(String.self, forKey: .lastDisplayID)
        }
    }

    public static let currentVersion = 1

    public var version = NinoSettings.currentVersion
    public var reading = Reading()
    public var translation = Translation()
    public var display = Display()

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
        reading = try c.decodeIfPresent(Reading.self, forKey: .reading) ?? Reading()
        translation = try c.decodeIfPresent(Translation.self, forKey: .translation) ?? Translation()
        display = try c.decodeIfPresent(Display.self, forKey: .display) ?? Display()
    }

    /// Okuma hattı ayarları.
    public var readingConfiguration: ReadingConfiguration {
        ReadingConfiguration(region: reading.region,
                             filter: NoiseFilter(minConfidence: reading.minConfidence, ignoredPhrases: Set(reading.ignoredPhrases)),
                             stableFrames: reading.stableFrames,
                             missingFrames: reading.missingFrames,
                             similarity: reading.similarity)
    }

    /// Sağlayıcı anahtarının Keychain'deki hesap adı.
    public static func secretAccount(forProvider name: String) -> String { "provider.\(name).key" }

    /// Ayarlardaki sağlayıcıları anahtarlarıyla birlikte kurar. `onDevice`
    /// verilirse (ve ayar açıksa) zincirin başına konur.
    public func makeProviders(secrets: SecretStore, session: URLSession = .shared,
                              onDevice: TranslationProvider? = nil) -> [TranslationProvider] {
        let head: [TranslationProvider] = translation.useOnDevice ? [onDevice].compactMap { $0 } : []
        return head + translation.providers.map { config in
            let key = try? secrets.get(Self.secretAccount(forProvider: config.name))
            return HTTPTranslationProvider(configuration: config, apiKey: key ?? nil, session: session)
        }
    }
}

/// Ayarları diskte tutar.
public struct SettingsStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public init(directories: NinoDirectories) {
        self.init(fileURL: directories.settingsFile)
    }

    /// Dosya yoksa varsayılanlar döner. Bozuksa `settings.bad.json` olarak
    /// kenara alınır ve varsayılanlar döner.
    public func load() -> NinoSettings {
        guard let data = try? Data(contentsOf: fileURL) else { return NinoSettings() }
        do {
            return try JSONDecoder().decode(NinoSettings.self, from: data)
        } catch {
            let bad = fileURL.deletingPathExtension().appendingPathExtension("bad.json")
            try? FileManager.default.removeItem(at: bad)
            try? FileManager.default.moveItem(at: fileURL, to: bad)
            return NinoSettings()
        }
    }

    public func save(_ settings: NinoSettings) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try e.encode(settings).write(to: fileURL, options: .atomic)
    }
}
