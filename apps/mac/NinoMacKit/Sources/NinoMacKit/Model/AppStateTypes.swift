// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import CoreGraphics
import Foundation

/// Kurulum sihirbazının adımları (docs/yeni/mac/kurulum.md).
public enum SetupStep: String, CaseIterable, Sendable {
    case welcome
    case secondAccount, psnLogin   // ikinci hesap ve PSN girişi
    case console, tv, test         // PS5, TV, deneme
    case betterTranslation
    case done
}

public enum TranslationPhase: Equatable, Sendable { case off, starting, on }

/// Görüntü kaynağının durumu (ana-ekran.md §8.3).
public enum SourceStatus: Equatable, Sendable {
    case ps5(ConsoleLink)
    case window(WindowLink)
    case card(CardLink)

    public enum ConsoleLink: Equatable, Sendable {
        case idle
        case connecting
        case streaming
        case dropped(DropReason)
    }

    public enum DropReason: Equatable, Sendable {
        case asleep
        case inUseElsewhere
        case refused
        case passcodeRequired
        case passcodeWrong
        case pairingInvalid
        case remotePlayDisabled
        case noPicture
        case notFound(address: String)
        case network
        case rejected(code: UInt32?)
        case other(detail: String?)
    }

    public enum WindowLink: Equatable, Sendable {
        case idle
        case appMissing
        case screenRecordingDenied
        case searching
        case reading(appName: String)
    }

    public enum CardLink: Equatable, Sendable {
        case idle
        case cameraDenied
        case noCard
        case black
        case reading(cardName: String)
    }
}

public struct PairedConsole: Equatable, Sendable {
    public var name: String
    public var host: String
    public init(name: String, host: String) {
        self.name = name
        self.host = host
    }
}

public struct PairedTV: Equatable, Sendable {
    public enum Brand: String, Sendable { case lg, samsung, androidTV }
    public var name: String
    public var host: String
    public var brand: Brand
    /// Denetim anahtarı saklı mı (LG istemci anahtarı, Samsung jetonu; Android TV'de her zaman evet).
    public var hasKey: Bool
    public init(name: String, host: String, brand: Brand, hasKey: Bool) {
        self.name = name
        self.host = host
        self.brand = brand
        self.hasKey = hasKey
    }
}

public enum PSNAccountState: Equatable, Sendable {
    case signedOut
    case signingIn
    case signedIn(accountID: Data)
    case failed(message: String)

    public var isSignedIn: Bool { if case .signedIn = self { return true }; return false }
}

public enum PairingState: Equatable, Sendable {
    case idle
    case searching
    case pairing
    case failed(message: String)
    case paired
}

public enum TVInstallState: Equatable, Sendable {
    case idle
    case searching
    case waitingForApproval
    case installing(progress: Double?)
    case installed(version: String?)
    case failed(message: String)
}

/// Ekranda gösterilen son satır.
public struct LiveLine: Equatable, Sendable {
    public enum Origin: String, Sendable { case pack, pool, cache, engine, untranslated }
    public var translated: String
    public var source: String
    public var origin: Origin
    /// Okumadan TV'ye kadar geçen süre (ms).
    public var latencyMs: Int?
    public init(translated: String, source: String, origin: Origin, latencyMs: Int? = nil) {
        self.translated = translated
        self.source = source
        self.origin = origin
        self.latencyMs = latencyMs
    }
}

public struct RecognizedGame: Equatable, Sendable {
    public enum Evidence: String, Sendable { case console, user, pack, screen, lastPlayed }
    public var id: String
    public var name: String
    /// Havuz öncelikli oyun (ör. GTA 6): satır önce ortak havuza sorulur.
    public var poolFirst: Bool
    public var evidence: Evidence
    public init(id: String, name: String, poolFirst: Bool, evidence: Evidence) {
        self.id = id
        self.name = name
        self.poolFirst = poolFirst
        self.evidence = evidence
    }
}

public enum TranslatorReadiness: Equatable, Sendable {
    case ready
    case languagePackMissing(source: String, target: String)
    case unsupported(source: String, target: String, systemHasTranslator: Bool)
}

public struct OnlineEngineProblem: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case badKey, quota, network, server, model, other }
    public var engine: MacSettings.OnlineEngine
    public var kind: Kind
    public init(engine: MacSettings.OnlineEngine, kind: Kind) {
        self.engine = engine
        self.kind = kind
    }
}

public struct TextReadingFailure: Equatable, Sendable {
    public var freeDiskGB: Double
    public init(freeDiskGB: Double) { self.freeDiskGB = freeDiskGB }
}

public struct HistoryEntry: Equatable, Sendable, Identifiable {
    public var id: UUID
    public var date: Date
    public var source: String
    public var translated: String
    /// Paketten mi, çeviri motorundan mı (Geçmiş satırındaki "Paket" / "Çeviri motoru"); bilinmiyorsa nil.
    public var origin: HistoryOrigin? = nil
    public init(id: UUID = UUID(), date: Date, source: String, translated: String) {
        self.id = id
        self.date = date
        self.source = source
        self.translated = translated
    }
}

public enum XboxStep: Equatable, Sendable { case notStarted, installing(progress: Double?), waitingForWindow, ready }

public enum Sheet: String, Identifiable, Sendable {
    case about, askNino, settings, settingsTranslation, history, xbox, reportProblem, health
    public var id: String { rawValue }
}

public enum UpdateStatus: Equatable, Sendable {
    case idle
    case checking
    case upToDate
    /// Yeni sürüm bulundu ama inmiyor (180 sn'de inmediyse ya da otomatik indirme yoksa).
    case available(version: String)
    case downloading(version: String, progress: Double?)
    case readyToInstall(version: String)
    case waitingForTranslationToStop(version: String)
    case failed(message: String)
}

/// Sistem sağlığı ekranının okuduğu özet (gecmis-hakkinda-saglik.md).
public struct HealthSnapshot: Sendable, Equatable {
    public enum Level: Int, Comparable, Sendable {
        case good, fair, poor
        public static func < (a: Level, b: Level) -> Bool { a.rawValue < b.rawValue }
    }
    public var consoleLink: Level = .good
    public var videoStream: Level = .good
    public var translation: Level = .good
    public var wired: Bool?
    public var incidents: [Incident] = []
    /// TV bağlantısının son kopması (Sistem sağlığı TV satırı). Bu taraftan kapatmalar yazılmaz.
    public var lastTVDrop: TVDropNote?

    public struct Incident: Equatable, Sendable, Identifiable {
        public var id: UUID
        public var date: Date
        public var cause: String
        public init(id: UUID = UUID(), date: Date, cause: String) {
            self.id = id
            self.date = date
            self.cause = cause
        }
    }

    public init() {}
}

/// TV'nin son kopması: ne zaman ve kabaca neden.
public struct TVDropNote: Sendable, Equatable {
    public enum Cause: String, Sendable, CaseIterable {
        /// TV bağlantıyı kendisi kapattı ya da yeniden bağlandı.
        case closed
        /// TV cevap vermez oldu (kalp atışı, asılı gönderim).
        case timeout
        /// Ağ ya da gönderim hatası.
        case network
        /// Mac uykudan uyandı.
        case resume
    }
    public var date: Date
    public var cause: Cause
    public init(date: Date, cause: Cause) {
        self.date = date
        self.cause = cause
    }
}

// MARK: - Ana ekranın eklediği türler (UI/Home)

/// Uygulamanın sürümü: başlıktaki hap ("V4.1") ve ipucundaki tam sürüm ("V4.1 (4.1.0)").
public struct AppVersionInfo: Equatable, Sendable {
    /// Kısa ad, ör. "V4.1".
    public var short: String
    /// Tam sürüm, ör. "4.1.0".
    public var full: String
    public init(short: String, full: String) {
        self.short = short
        self.full = full
    }

    /// Uygulama paketinin bilgi dosyasından: "4.1.0" → "V4.1".
    public static func from(bundle: Bundle) -> AppVersionInfo {
        let full = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0"
        let parts = full.split(separator: ".")
        let short = "V" + parts.prefix(2).joined(separator: ".")
        return AppVersionInfo(short: short, full: full)
    }
}

/// Yayın penceresinin zemini (veri-uyumu.md `streamBackground`).
public enum StreamBackground: String, CaseIterable, Sendable {
    case green, black, magenta
}

/// Ek alan çevirisi (görev, bildirim, telefon): ekran dışı ve yayın penceresinin üstündeki kutular.
public struct ExtraAreaText: Equatable, Sendable, Identifiable {
    public enum Alignment: String, Sendable { case leading, center, trailing }
    public var id: String
    public var text: String
    /// Oyundaki yazının bulunduğu yan.
    public var alignment: Alignment
    public init(id: String, text: String, alignment: Alignment) {
        self.id = id
        self.text = text
        self.alignment = alignment
    }
}

/// Admin önizlemesi: PS5 karesi + TV'nin çizdiği katman (gizli TV sayfası), en çok 960 genişlik.
public struct AdminTVPreview: Equatable, @unchecked Sendable {
    public var image: CGImage
    public var at: Date
    public init(image: CGImage, at: Date) {
        self.image = image
        self.at = at
    }
    public static func == (a: AdminTVPreview, b: AdminTVPreview) -> Bool { a.at == b.at && a.image === b.image }
}
