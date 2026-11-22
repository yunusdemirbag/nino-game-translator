// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import AppKit
import SwiftUI
import XCTest
@testable import NinoMacKit

/// Kurulum sihirbazının gezinme kuralları ve her adımın/hâlin ekran görüntüsü (`apps/mac/snapshots/setup-*.png`).
/// Ağa, kullanıcının verisine ve Anahtarlığa dokunmaz; motor `PreviewEngine`.
@MainActor
final class SetupSnapshotTests: XCTestCase {
    override func setUp() async throws {
        NinoFonts.registerBundledFonts()
    }

    /// AppState motoru zayıf tutar; motorlar test boyunca burada yaşar.
    private var engines: [PreviewEngine] = []

    private func fresh(language: String = "tr") -> (AppState, PreviewEngine) {
        var settings = MacSettings()
        settings.targetLanguage = language
        let state = AppState(settings: settings)
        let engine = PreviewEngine(state: state)
        engines.append(engine)
        return (state, engine)
    }

    // MARK: Metinler

    func testEverySetupKeyHasTurkishAndEnglish() throws {
        let url = HomeSnapshotTests.snapshotFolder.deletingLastPathComponent()
            .appendingPathComponent("NinoMacKit/Sources/NinoMacKit/Resources/Setup.xcstrings")
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        let keys = try XCTUnwrap(json?["strings"] as? [String: Any]).keys
        XCTAssertGreaterThan(keys.count, 200)
        for key in keys {
            XCTAssertNotEqual(NinoL10n.string(key, table: "Setup", language: "tr"), key, key)
            XCTAssertNotEqual(NinoL10n.string(key, table: "Setup", language: "en"), key, key)
        }
        XCTAssertEqual(NinoL10n.string("setup.dots %lld %lld", table: "Setup", language: "tr", arguments: [3, 7]),
                       "3. adım / 7")
        XCTAssertEqual(NinoL10n.string("setup.xboxList.installing %lld", table: "Setup", language: "tr",
                                       arguments: [42]), "Greenlight yükleniyor… %42")
    }

    // MARK: Gezinme (kurulum.md §12)

    func testStartStep() {
        XCTAssertEqual(SetupFlow.startStep(doneRecord: true, hasAccount: false, hasConsole: false, hasPairedTV: false), .done)
        XCTAssertEqual(SetupFlow.startStep(doneRecord: false, hasAccount: true, hasConsole: true, hasPairedTV: true), .tv)
        XCTAssertEqual(SetupFlow.startStep(doneRecord: nil, hasAccount: true, hasConsole: true, hasPairedTV: true), .done)
        XCTAssertEqual(SetupFlow.startStep(doneRecord: nil, hasAccount: true, hasConsole: false, hasPairedTV: true), .welcome)
    }

    func testPS5Path() {
        let (state, _) = fresh()
        XCTAssertFalse(SetupFlow.showsBack(state))
        XCTAssertEqual(SetupFlow.forwardButton(state), .none)
        SetupFlow.chooseConsole(.ps5, state)
        XCTAssertEqual(state.setup.welcome, .ps5)
        XCTAssertTrue(SetupFlow.showsBack(state))
        SetupFlow.goNext(state)
        XCTAssertEqual(state.setupStep, .secondAccount)
        SetupFlow.goNext(state)
        XCTAssertEqual(state.setupStep, .psnLogin)
        XCTAssertFalse(SetupFlow.canContinue(state))
        state.beginPSNSignIn()
        XCTAssertTrue(SetupFlow.canContinue(state))
        SetupFlow.goNext(state)
        XCTAssertEqual(state.setupStep, .console)
        XCTAssertFalse(SetupFlow.canContinue(state))
        state.searchConsoles()
        state.pairConsole(address: "192.168.0.20", code: "12345678")
        XCTAssertEqual(state.pairing, .paired)
        XCTAssertEqual(state.pairedConsole?.name, "PS5-123")
        SetupFlow.goNext(state)
        XCTAssertEqual(state.setupStep, .tv)
        XCTAssertFalse(SetupFlow.canContinue(state))
        SetupFlow.goBack(state)
        XCTAssertEqual(state.setupStep, .console)
        SetupFlow.goNext(state)
        state.pairTV(.androidTV)
        XCTAssertTrue(SetupFlow.canContinue(state))
        SetupFlow.goNext(state)
        XCTAssertEqual(state.setupStep, .test)
        XCTAssertEqual(SetupFlow.forwardButton(state), .none)
        state.overlayAdjusting = true
        SetupFlow.testSeen(state)
        XCTAssertFalse(state.overlayAdjusting)
        XCTAssertEqual(state.setupStep, .betterTranslation)
        XCTAssertEqual(SetupFlow.forwardButton(state), .skip)
        state.saveGeminiKey("key")
        XCTAssertEqual(SetupFlow.forwardButton(state), .proceed)
        SetupFlow.goNext(state)
        XCTAssertTrue(state.isSetupComplete)
    }

    func testXboxPathSkipsPS5StepsAndBackReturnsToXbox() {
        let (state, _) = fresh()
        SetupFlow.chooseConsole(.xbox, state)
        SetupFlow.goNext(state)
        XCTAssertEqual(state.setupStep, .tv)
        XCTAssertEqual(state.settings.gameConsole, .xbox)
        XCTAssertEqual(state.settings.videoSource, .window)
        SetupFlow.goBack(state)
        XCTAssertEqual(state.setupStep, .welcome)
        XCTAssertEqual(state.setup.welcome, .xbox)
        SetupFlow.goBack(state)
        XCTAssertEqual(state.setup.welcome, .chooseConsole)
    }

    func testShortcuts() {
        let (state, engine) = fresh()
        SetupFlow.playOnThisComputer(state)
        XCTAssertTrue(state.isSetupComplete)
        XCTAssertEqual(state.settings.videoSource, .window)
        XCTAssertTrue(engine.calls.contains("setupFinished"))

        let (second, _) = fresh()
        second.setupStep = .secondAccount
        SetupFlow.readRemotePlayWindow(second)
        XCTAssertTrue(second.isSetupComplete)
        XCTAssertEqual(second.settings.output, .computer)

        let (tv, _) = fresh()
        tv.setupStep = .tv
        SetupFlow.noTV(tv)
        XCTAssertEqual(tv.setupStep, .test)
        XCTAssertEqual(tv.settings.output, .computer)

        let (card, _) = fresh()
        card.setup.captureGuideOpen = true
        SetupFlow.captureGuideDone(toTV: true, card)
        XCTAssertFalse(card.setup.captureGuideOpen)
        XCTAssertEqual(card.settings.videoSource, .card)
        XCTAssertEqual(card.setupStep, .tv)
        card.pairedTV = PairedTV(name: "TV", host: "1.2.3.4", brand: .lg, hasKey: true)
        SetupFlow.captureGuideDone(toTV: true, card)
        XCTAssertEqual(card.setupStep, .test)
    }

    func testDotIndexAndXboxSteps() {
        XCTAssertEqual(SetupStep.allCases.map(SetupFlow.dotIndex), [0, 1, 2, 3, 4, 5, 6, 6])
        XCTAssertEqual(XboxLink().step, .install)
        XCTAssertEqual(XboxLink(greenlightInstalled: true).step, .signIn)
        XCTAssertEqual(XboxLink(greenlightInstalled: true, signedIn: true).step, .start)
        XCTAssertEqual(XboxLink(streaming: true).step, .done)
    }

    func testTVAppCardFallsBackToInstallState() {
        let (state, _) = fresh()
        state.pairedTV = PairedTV(name: "TV", host: "", brand: .androidTV, hasKey: true)
        state.tvInstall = .waitingForApproval
        XCTAssertEqual(TVAppCardView.card(state), .androidApprove)
        state.tvInstall = .installed(version: "4.1.0")
        XCTAssertEqual(TVAppCardView.card(state), .ready(version: "4.1.0", lgHoursLeft: nil))
        state.setup.tvApp = .working
        XCTAssertEqual(TVAppCardView.card(state), .working)
    }

    // MARK: Ekran görüntüleri

    private func shot(_ state: AppState, _ name: String, scheme: ColorScheme = .light, height: CGFloat = 900) throws {
        let ui = HomeUIState(skipIntro: true)
        try render(MainWindowView(state: state, ui: ui), size: CGSize(width: 1040, height: height),
                                       scheme: scheme,
                                       locale: MainWindowView.interfaceLanguage(for: state.settings.targetLanguage),
                                       name: "setup-" + name)
    }

    func testWelcome() throws {
        let (state, _) = fresh()
        try shot(state, "welcome-choose-light", height: 720)
        try shot(state, "welcome-choose-dark", scheme: .dark, height: 720)
        SetupFlow.chooseConsole(.ps5, state)
        try shot(state, "welcome-ps5-light")
        let (other, _) = fresh(language: "id")
        SetupFlow.chooseConsole(.ps5, other)
        try shot(other, "welcome-ps5-en-dark", scheme: .dark)
        let (arabic, _) = fresh(language: "ar")
        try shot(arabic, "welcome-choose-ar-rtl", height: 720)
    }

    /// Arapça ve Tayca kurulum ekranları (`apps/mac/snapshots/l10n-setup-*.png`): taşma/kesilme denetimi için.
    func testLocalizedWelcome() throws {
        for language in ["ar", "th"] {
            let (state, _) = fresh(language: language)
            try render(MainWindowView(state: state, ui: HomeUIState(skipIntro: true)), size: CGSize(width: 1040, height: 720),
                       scheme: .light, locale: language, name: "l10n-setup-welcome-\(language)")
            SetupFlow.chooseConsole(.ps5, state)
            try render(MainWindowView(state: state, ui: HomeUIState(skipIntro: true)), size: CGSize(width: 1040, height: 900),
                       scheme: .light, locale: language, name: "l10n-setup-ps5-\(language)")
        }
    }

    func testXboxWelcome() throws {
        let (state, _) = fresh()
        SetupFlow.chooseConsole(.xbox, state)
        try shot(state, "welcome-xbox-install")
        state.setup.xbox = XboxLink(installProgress: 0.42)
        try shot(state, "welcome-xbox-installing", scheme: .dark)
        state.setup.xbox = XboxLink(greenlightInstalled: true)
        try shot(state, "welcome-xbox-signin")
        state.setup.xbox = XboxLink(greenlightInstalled: true, signedIn: true, streaming: true)
        try shot(state, "welcome-xbox-done", scheme: .dark)
    }

    func testAccountSteps() throws {
        let (state, _) = fresh()
        state.setupStep = .secondAccount
        state.setup.remotePlayAppInstalled = false
        try shot(state, "account", height: 1000)
        state.setupStep = .psnLogin
        try shot(state, "psn-signedout")
        state.psnAccount = .failed(message: "Sony girişi tamamlamadı. Bir dakika bekleyin, sonra yeniden giriş yapın.")
        try shot(state, "psn-error", scheme: .dark)
        state.psnAccount = .signedIn(accountID: Data([0x01, 0x23, 0x45, 0x67, 0x89, 0xAB, 0xCD, 0xEF]))
        try shot(state, "psn-signedin")
    }

    func testConsoleStep() throws {
        let (state, _) = fresh()
        state.setupStep = .console
        state.setup.consoleSearch = .searching
        try shot(state, "ps5-searching-noaccount", height: 1000)
        state.psnAccount = .signedIn(accountID: Data(repeating: 1, count: 8))
        state.setup.consoleSearch = .finished
        state.setup.foundConsoles = [SetupConsole(name: "PS5-123", address: "192.168.0.20")]
        try shot(state, "ps5-found", scheme: .dark)
        state.setup.foundConsoles = []
        try shot(state, "ps5-notfound")
        state.setup.foundConsoles = [SetupConsole(name: "PS5-123", address: "192.168.0.20"),
                                     SetupConsole(name: "PS5-Oda", address: "192.168.0.21")]
        state.pairing = .failed(message: "Kod yanlış ya da süresi dolmuş. PS5'te Cihazı Eşleştir'i yeniden açın ve yeni kodu girin. (0x80108b09)")
        try shot(state, "ps5-failed", height: 1000)
        state.pairing = .pairing
        try shot(state, "ps5-pairing", scheme: .dark)
        state.pairing = .paired
        state.pairedConsole = PairedConsole(name: "PS5-123", host: "192.168.0.20")
        try shot(state, "ps5-justpaired")
        state.pairing = .idle
        try shot(state, "ps5-paired-tile", height: 720)
    }

    func testTVStep() throws {
        let (state, _) = fresh()
        state.setupStep = .tv
        try shot(state, "tv-choose", height: 960)
        state.setup.tvSearch = .searching
        state.setup.foundTVs = [DiscoveredTV(name: "LG OLED55", host: "192.168.0.31", brand: .lg),
                                DiscoveredTV(name: "Samsung QLED", host: "192.168.0.44", brand: .samsung)]
        try shot(state, "tv-list-searching", scheme: .dark)
        state.setup.tvSearch = .finished
        state.setup.foundTVs = []
        try shot(state, "tv-list-empty")
        state.setup.tvConnect = .connecting(brand: .samsung)
        try shot(state, "tv-connecting-samsung")
        state.setup.tvConnect = .failed(.samsungNotAccepted)
        state.setup.tvApp = .failed(message: "TV uygulaması kurulamadı. Tekrar deneyin.")
        try shot(state, "tv-connect-failed", scheme: .dark)
    }

    private func pairedTVState(_ brand: PairedTV.Brand, _ card: TVAppCard) -> AppState {
        let (state, _) = fresh()
        state.setupStep = .tv
        state.pairedTV = PairedTV(name: brand == .lg ? "LG OLED55" : (brand == .samsung ? "Samsung QLED" : "Android TV"),
                                  host: "192.168.0.31", brand: brand, hasKey: true)
        state.setup.tvApp = card
        return state
    }

    func testTVAppCards() throws {
        try shot(pairedTVState(.lg, .ready(version: "4.1.0", lgHoursLeft: 812)), "tvapp-lg-ready", height: 720)
        try shot(pairedTVState(.lg, .lgDeveloperModeOff(passphraseError: nil)), "tvapp-lg-devmode", height: 1000)
        try shot(pairedTVState(.lg, .lgPassphrase(error: "Passphrase eşleşmedi; TV'de yazanı tekrar girin.")),
                 "tvapp-lg-passphrase", scheme: .dark)
        try shot(pairedTVState(.androidTV, .androidDebuggingOff), "tvapp-android-off", height: 1000)
        try shot(pairedTVState(.androidTV, .androidApprove), "tvapp-android-approve", scheme: .dark, height: 720)
        try shot(pairedTVState(.samsung, .samsungSignIn(url: "https://account.samsung.com/")), "tvapp-samsung-signin")
        try shot(pairedTVState(.samsung, .samsungReady), "tvapp-samsung-ready", scheme: .dark, height: 720)
        let mac = "192.168.0.12"
        try shot(pairedTVState(.samsung, .samsungCheck(SamsungCheck(problem: .developerModeOff, developerMode: false,
                                                                    macAddress: mac, modelYear: 2023))),
                 "tvapp-samsung-modeoff", height: 1100)
        try shot(pairedTVState(.samsung, .samsungCheck(SamsungCheck(problem: .wrongAddress, developerMode: true,
                                                                    tvHostIP: "192.168.0.50", macAddress: mac,
                                                                    typeCode: .sent))),
                 "tvapp-samsung-wrongaddress", scheme: .dark, height: 1400)
        try shot(pairedTVState(.samsung, .samsungCheck(SamsungCheck(problem: .notRestarted, developerMode: true,
                                                                    tvHostIP: mac, macAddress: mac))),
                 "tvapp-samsung-notrestarted")
        try shot(pairedTVState(.samsung, .samsungCheck(SamsungCheck(problem: .dropped(reason: "ConnectionLost"),
                                                                    developerMode: true, tvHostIP: "192.168.0.50",
                                                                    macAddress: mac, installGateOpen: true,
                                                                    logPath: "~/Library/Logs/Nino/tvinstall.log"))),
                 "tvapp-samsung-dropped", height: 1000)
        let guide = pairedTVState(.samsung, .none)
        guide.setup.tvAppBundled = false
        try shot(guide, "tv-guide-card", height: 720)
    }

    func testTestStep() throws {
        let (state, _) = fresh()
        state.setupStep = .test
        state.settings.output = .computer
        try shot(state, "test-computer-ready", height: 720)
        state.settings.output = .tv
        state.setup.test = .sent
        try shot(state, "test-tv-sent", scheme: .dark, height: 720)
        state.setup.test = .notSeen
        state.connectedDisplays = 1
        try shot(state, "test-tv-notseen", height: 800)
        state.setup.test = .sending
        try shot(state, "test-tv-sending", scheme: .dark, height: 720)
    }

    func testBetterTranslation() throws {
        let (state, _) = fresh()
        state.setupStep = .betterTranslation
        state.settingsStatus.gamePacks = [GamePackInfo(id: "rdr2", name: "Red Dead Redemption 2", lines: 61_203),
                                          GamePackInfo(id: "gow", name: "God of War Ragnarök", lines: 18_450)]
        // Varsayılan: "Ücretsiz" seçili, anahtar alanı açık, atlama bilgisi görünür.
        XCTAssertFalse(state.settings.onlineTranslation)
        XCTAssertEqual(SetupFlow.forwardButton(state), .skip)
        try shot(state, "gemini-form", height: 1180)
        state.setup.geminiTest = .failed(message: "Gemini anahtarı geçersiz. Anahtarı yeniden kopyalayın.")
        try shot(state, "gemini-failed", scheme: .dark, height: 1180)
        state.saveGeminiKey("key")
        XCTAssertEqual(SetupFlow.forwardButton(state), .proceed)
        try shot(state, "gemini-ready", height: 1000)
    }

    func testCaptureCardGuide() throws {
        let (state, _) = fresh()
        state.setup.welcome = .ps5
        state.setup.captureGuideOpen = true
        try shot(state, "card-connection")
        for (page, name) in [(1, "card-hdcp"), (2, "card-plug")] {
            let guide = CaptureCardGuide(state: state, context: .wizard, initialPage: page) {}
            try render(guide.background(NinoWindowBackground()),
                                           size: CGSize(width: 1040, height: 900), scheme: page == 1 ? .dark : .light,
                                           name: "setup-" + name)
        }
        state.setup.captureCard = CaptureCardCheck(status: .noPermission)
        try render(CaptureCardGuide(state: state, context: .settingsWindow, initialPage: 2) {}
                                        .background(NinoWindowBackground()),
                                       size: CGSize(width: 760, height: 820), scheme: .dark,
                                       name: "setup-card-plug-permission")
        state.setup.captureCard = CaptureCardCheck(status: .working(name: "Elgato HD60 X"),
                                                   devices: [.init(id: "a", name: "Elgato HD60 X"),
                                                             .init(id: "b", name: "FaceTime HD")])
        try render(CaptureCardCheckView(state: state) { Color.indigo }.padding(24)
                                        .background(NinoWindowBackground()),
                                       size: CGSize(width: 640, height: 380), scheme: .light,
                                       name: "setup-card-check-working")
    }
}

extension SetupSnapshotTests {
    func render<V: View>(_ view: V, size: CGSize, scheme: ColorScheme, locale: String = "tr", name: String) throws {
        let content = view
            .frame(width: size.width, height: size.height)
            .environment(\.colorScheme, scheme)
            .environment(\.locale, Locale(identifier: locale))
            .environment(\.layoutDirection, NinoL10n.isRightToLeft(languageCode: locale) ? .rightToLeft : .leftToRight)
            .environment(\.ninoStaticRendering, true)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        renderer.proposedSize = ProposedViewSize(size)
        let image: NSImage = try XCTUnwrap(renderer.nsImage, "\(name) çizilemedi")
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let png = try XCTUnwrap(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
        let folder = HomeSnapshotTests.snapshotFolder
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try png.write(to: folder.appendingPathComponent(name + ".png"))
    }
}

private extension TVAppCard {
    static let samsungReady = TVAppCard.ready(version: "4.1.0", lgHoursLeft: nil)
}
