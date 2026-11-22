// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

// Kurulum sihirbazının ayrıntılı durumu (docs/yeni/mac/kurulum.md, tv-kurulumu.md §5).
// `AppState.setup` içinde durur; ekranlar okur, motor yazar.

/// Sihirbazın adım dışındaki bütün durumu.
public struct SetupDetail: Equatable, Sendable {
    /// Hoş geldin adımının hâli. Kaydedilmez: yarım kurulum yeniden açılınca yine sorulur (§3).
    public var welcome: WelcomeMode = .chooseConsole
    /// Yakalama kartı rehberi açık mı (§10); açıkken kart ve alt sıra yerine rehber görünür.
    public var captureGuideOpen: Bool = false
    /// Geliştirici derlemesindeki tasarım bayrağı: her adımda Devam açık (§12).
    public var continueAlwaysEnabled: Bool = false

    // MARK: İkinci hesap (§4)

    /// PS Remote Play ya da chiaki-ng bu Mac'te kurulu mu.
    public var remotePlayAppInstalled: Bool = true

    // MARK: PS5 (§6)

    public var consoleSearch: SearchPhase = .idle
    public var foundConsoles: [SetupConsole] = []
    /// Yerel ağ izni kapalı sayıldı mı (aramada hiçbir gönderim kabul edilmedi).
    public var consoleSearchBlocked: Bool = false

    // MARK: TV (§7)

    public var tvSearch: SearchPhase = .idle
    public var foundTVs: [DiscoveredTV] = []
    public var tvConnect: TVConnectState = .idle
    /// TV uygulaması kartı (tv-kurulumu.md §5). `.none` iken `AppState.tvInstall`'a bakılır.
    public var tvApp: TVAppCard = .none
    /// TV uygulaması paketi uygulamayla geldi mi (geliştirici derlemesinde gelmeyebilir).
    public var tvAppBundled: Bool = true

    // MARK: Deneme (§8)

    public var test: TestPhase = .ready

    // MARK: Daha doğal çeviri (§9)

    /// Anahtarlıkta Gemini anahtarı var mı.
    public var geminiKeySaved: Bool = false
    public var geminiTest: KeyTest = .idle
    /// Anahtar denenirken Gemini'nin çevirdiği örnek satır.
    public var geminiSample: String?

    // MARK: Yakalama kartı (§10) ve Xbox (§11)

    public var captureCard: CaptureCardCheck = CaptureCardCheck()
    public var xbox: XboxLink = XboxLink()

    public init() {}
}

public enum WelcomeMode: String, Sendable, CaseIterable { case chooseConsole, ps5, xbox }

public enum SearchPhase: Equatable, Sendable { case idle, searching, finished }

/// Aramada bulunan PS5 (ad ve adres).
public struct SetupConsole: Equatable, Hashable, Sendable, Identifiable {
    public var name: String
    public var address: String
    public var id: String { address }
    public init(name: String, address: String) {
        self.name = name
        self.address = address
    }
}

/// Ağda bulunan (ya da seçilen) TV.
public struct DiscoveredTV: Equatable, Hashable, Sendable, Identifiable {
    public var name: String
    public var host: String
    public var brand: PairedTV.Brand
    public var id: String { brand.rawValue + "|" + host }
    public init(name: String, host: String, brand: PairedTV.Brand) {
        self.name = name
        self.host = host
        self.brand = brand
    }

    /// Android TV ağda aranmaz: adı "Android TV", adresi boş bir kayıt (tv-kurulumu.md §2).
    public static let androidTV = DiscoveredTV(name: "Android TV", host: "", brand: .androidTV)
}

public enum TVConnectState: Equatable, Sendable {
    case idle
    case connecting(brand: PairedTV.Brand)
    case failed(TVConnectFailure)
}

public enum TVConnectFailure: Equatable, Sendable {
    /// Samsung bağlantıyı reddetti (`ms.channel.unauthorized`).
    case samsungRefused
    /// Samsung'un izin kutusu 60 sn'de onaylanmadı.
    case samsungNotAccepted
    /// Öbür her şey.
    case noResponse
}

/// TV uygulaması kartının hâli (tv-kurulumu.md §5). Hata iletileri (§7) motorca hazırlanıp metin olarak gelir.
public enum TVAppCard: Equatable, Sendable {
    case none
    case working
    /// Güncel. `lgHoursLeft`: LG geliştirici modunun kalan saati (biliniyorsa).
    case ready(version: String, lgHoursLeft: Int?)
    /// TV'de yalnız eski kimlikli TV uygulaması var ve o açılıyor (çalışır). Yenisini kurmak önerilir, zorlanmaz.
    /// `version` boş olabilir (okunamadı).
    case legacyApp(version: String)
    /// LG: geliştirici modu kapalı; parola alanı burada da görünür.
    case lgDeveloperModeOff(passphraseError: String?)
    /// LG: geliştirici modu açık, Key Server parolası gerekiyor.
    case lgPassphrase(error: String?)
    /// Samsung: yardımcı tarayıcıda girişi bekliyor.
    case samsungSignIn(url: String)
    /// Samsung denetim kartı.
    case samsungCheck(SamsungCheck)
    /// Android TV: ağda ADB'si açık TV yok.
    case androidDebuggingOff
    /// Android TV: TV'de hata ayıklama onayı bekleniyor.
    case androidApprove
    /// Hata (ana ileti + boş satır + sebep, motorca birleştirilmiş).
    case failed(message: String)
}

/// Samsung denetiminin sonucu (tv-kurulumu.md §5.2).
public struct SamsungCheck: Equatable, Sendable {
    public enum Problem: Equatable, Sendable {
        /// Henüz bilgi yok.
        case checking
        case noAnswer
        case developerModeOff
        case wrongAddress
        case leadingZeros
        case reversed
        case loopback
        case notRestarted
        /// Eksik adım yok ama TV bağlantıyı kesti; `reason`: yardımcının verdiği sebep.
        case dropped(reason: String?)
    }

    public enum TypeCodeResult: Equatable, Sendable { case sending, sent, unreachable }

    public var problem: Problem
    /// Geliştirici modu (nil: bilinmiyor).
    public var developerMode: Bool?
    /// TV'deki Host PC IP (boş ya da 0.0.0.0 ise nil).
    public var tvHostIP: String?
    /// Bu Mac'in TV'ye giden adresi.
    public var macAddress: String
    /// Kurulum kapısı (26101) açık mı.
    public var installGateOpen: Bool
    /// Model yılı ("23_…" → 2023).
    public var modelYear: Int?
    public var typeCode: TypeCodeResult?
    /// Kurulum günlüğünün yolu (koptu hâlinde gösterilir).
    public var logPath: String

    public init(problem: Problem, developerMode: Bool? = nil, tvHostIP: String? = nil, macAddress: String,
                installGateOpen: Bool = false, modelYear: Int? = nil, typeCode: TypeCodeResult? = nil,
                logPath: String = "") {
        self.problem = problem
        self.developerMode = developerMode
        self.tvHostIP = tvHostIP
        self.macAddress = macAddress
        self.installGateOpen = installGateOpen
        self.modelYear = modelYear
        self.typeCode = typeCode
        self.logPath = logPath
    }

    /// TV yanıt veriyor mu (üç satırlık özet ancak o zaman gösterilir).
    public var tvAnswers: Bool {
        switch problem {
        case .noAnswer, .checking: return false
        default: return true
        }
    }

    /// Adres sorunu mu (kurulum denenmez).
    public var isAddressProblem: Bool {
        switch problem {
        case .wrongAddress, .leadingZeros, .reversed, .loopback: return true
        default: return false
        }
    }
}

public enum TestPhase: Equatable, Sendable {
    /// Henüz gönderilmedi.
    case ready
    case sending
    /// Gönderildi, soru soruluyor.
    case sent
    /// "Hayır" dendi.
    case notSeen
    /// "Hayır"dan sonra yeniden gönderiliyor.
    case resending
}

public enum KeyTest: Equatable, Sendable {
    case idle
    case testing
    case failed(message: String)
}

/// Yakalama kartı denetimi (§10).
public struct CaptureCardCheck: Equatable, Sendable {
    public enum Status: Equatable, Sendable {
        case searching
        case noPermission
        case noCard
        case black
        case working(name: String)
        /// Kart bulundu ama görüntü durdu.
        case stopped(name: String)
    }

    public struct Device: Equatable, Hashable, Sendable, Identifiable {
        public var id: String
        public var name: String
        public init(id: String, name: String) {
            self.id = id
            self.name = name
        }
    }

    public var status: Status = .searching
    public var devices: [Device] = []
    /// nil: otomatik.
    public var selectedDeviceID: String?

    public init(status: Status = .searching, devices: [Device] = [], selectedDeviceID: String? = nil) {
        self.status = status
        self.devices = devices
        self.selectedDeviceID = selectedDeviceID
    }
}

/// Xbox bağlantısının ayrıntısı (§11, kaynaklar.md §4).
public struct XboxLink: Equatable, Sendable {
    public var greenlightInstalled: Bool = false
    public var signedIn: Bool = false
    public var streaming: Bool = false
    /// Greenlight kuruluyorsa 0…1.
    public var installProgress: Double?
    public var installError: String?

    public init(greenlightInstalled: Bool = false, signedIn: Bool = false, streaming: Bool = false,
                installProgress: Double? = nil, installError: String? = nil) {
        self.greenlightInstalled = greenlightInstalled
        self.signedIn = signedIn
        self.streaming = streaming
        self.installProgress = installProgress
        self.installError = installError
    }

    public enum Step: Int, Sendable, Comparable {
        case install = 2, signIn = 3, start = 4, done = 5
        public static func < (a: Step, b: Step) -> Bool { a.rawValue < b.rawValue }
    }

    /// Sıradaki adım: yayın açıksa bitti; kurulu değilse kurulum; girişli değilse giriş; değilse yayın.
    public var step: Step {
        if streaming { return .done }
        if !greenlightInstalled { return .install }
        if !signedIn { return .signIn }
        return .start
    }
}

// MARK: - Kurulum eylemleri

public extension AppState {
    /// Sihirbazı bitirir (ana ekran). "Bitti" kaydını motor yazar.
    func finishSetup() {
        setup.captureGuideOpen = false
        setupStep = .done
        setupOpenedFromHome = false
        engine?.setupFinished()
    }

    func beginPSNSignIn() { engine?.beginPSNSignIn() }
    /// Elle yazılan hesap kimliği; geçersizse `false`.
    func enterPSNAccountID(_ text: String) -> Bool { engine?.enterPSNAccountID(text) ?? false }
    func signOutPSN() { engine?.signOutPSN() }
    var psnLoginController: PSNLoginController? { engine?.psnLoginController }

    func searchConsoles() { engine?.searchConsoles() }
    func pairConsole(address: String, code: String) { engine?.pairConsole(address: address, code: code) }
    func revealRemotePlayLog() { engine?.revealRemotePlayLog() }
    func refreshRemotePlayApps() { engine?.refreshRemotePlayApps() }

    func searchTVs() { engine?.searchTVs() }
    func pairTV(_ tv: DiscoveredTV) { engine?.pairTV(tv) }
    func recheckTVApp() { engine?.recheckTVApp() }
    func recheckTVAppNow() { engine?.recheckTVAppNow() }
    /// Eski TV uygulaması kuruluyken kullanıcı yenisini kurmak istedi.
    func upgradeLegacyTVApp() { engine?.upgradeLegacyTVApp() }
    func installTVApp(passphrase: String?) { engine?.installTVApp(passphrase: passphrase) }
    func samsungTryAnyway() { engine?.samsungTryAnyway() }
    func samsungTypeDeveloperCode() { engine?.samsungTypeDeveloperCode() }
    func reopenSamsungSignIn() { engine?.reopenSamsungSignIn() }

    func sendTestSubtitle() { engine?.sendTestSubtitle() }
    func saveGeminiKey(_ key: String) { engine?.saveGeminiKey(key) }

    func installGreenlight() { engine?.installGreenlight() }
    func openGreenlight() { engine?.openGreenlight() }
    func setXboxPolling(_ on: Bool) { engine?.setXboxPolling(on) }
    func setCaptureCardPreview(_ on: Bool) { engine?.setCaptureCardPreview(on) }
    func selectCaptureDevice(_ id: String?) {
        setup.captureCard.selectedDeviceID = id
        engine?.selectCaptureDevice(id)
    }

    /// Gemini hazır mı: motor Gemini, çevrimiçi çeviri açık ve anahtar saklı.
    var geminiReady: Bool {
        settings.onlineTranslation && settings.onlineEngine == .gemini && setup.geminiKeySaved
    }
}

// MARK: - Motorun kurulum yöntemleri (varsayılanları: hiçbir şey yapmaz)

/// Motor bu yöntemleri gerçekleştirmezse kurulum ekranı yine açılır ama eylemler boşa gider.
public extension AppEngine {
    func setupFinished() {}
    func beginPSNSignIn() {}
    func enterPSNAccountID(_ text: String) -> Bool { false }
    func signOutPSN() {}
    var psnLoginController: PSNLoginController? { nil }
    func searchConsoles() {}
    func pairConsole(address: String, code: String) {}
    func revealRemotePlayLog() {}
    func refreshRemotePlayApps() {}
    func searchTVs() {}
    func pairTV(_ tv: DiscoveredTV) {}
    func recheckTVApp() {}
    func recheckTVAppNow() { recheckTVApp() }
    func upgradeLegacyTVApp() { recheckTVAppNow() }
    func installTVApp(passphrase: String?) {}
    func samsungTryAnyway() {}
    func samsungTypeDeveloperCode() {}
    func reopenSamsungSignIn() {}
    func sendTestSubtitle() {}
    func saveGeminiKey(_ key: String) {}
    func installGreenlight() {}
    func openGreenlight() {}
    func setXboxPolling(_ on: Bool) {}
    func setCaptureCardPreview(_ on: Bool) {}
    func selectCaptureDevice(_ id: String?) {}
}
