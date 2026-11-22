// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import AppKit
import SwiftUI
import XCTest
@testable import NinoMacKit

/// Ana ekranın ve ortak bileşenlerin ekran görüntülerini `apps/mac/snapshots/` altına yazar.
/// Karşılaştırma yapmaz; yalnız üretir. Ağa, kullanıcının verisine ve Anahtarlığa dokunmaz.
@MainActor
final class HomeSnapshotTests: XCTestCase {
    override func setUp() async throws {
        NinoFonts.registerBundledFonts()
    }

    // MARK: Metinler

    func testHomeStringsResolve() {
        XCTAssertEqual(NinoL10n.string("home.tv.live", table: "Home", language: "tr"), "CANLI")
        XCTAssertEqual(NinoL10n.string("home.tv.live", table: "Home", language: "en"), "LIVE")
        // Desteklenmeyen dil İngilizceye düşer.
        XCTAssertEqual(NinoL10n.string("home.tv.live", table: "Home", language: "ja"), "LIVE")
    }

    func testEveryHomeKeyHasTurkishAndEnglish() throws {
        let url = Self.snapshotFolder.deletingLastPathComponent()
            .appendingPathComponent("NinoMacKit/Sources/NinoMacKit/Resources/Home.xcstrings")
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        let keys = try XCTUnwrap(json?["strings"] as? [String: Any]).keys
        XCTAssertGreaterThan(keys.count, 50)
        for key in keys {
            XCTAssertNotEqual(NinoL10n.string(key, table: "Home", language: "tr"), key, key)
            XCTAssertNotEqual(NinoL10n.string(key, table: "Home", language: "en"), key, key)
        }
        for theme in SubtitleStyle.Theme.allCases {
            XCTAssertFalse(SubtitleNames.theme(theme, locale: Locale(identifier: "tr")).hasPrefix("home."))
        }
    }

    // MARK: Salon geometrisi

    func testLivingRoomGeometry() {
        let ps5 = LivingRoomGeometry.ps5
        let xbox = LivingRoomGeometry.xbox
        XCTAssertEqual(ps5.centeringShift, 36)
        XCTAssertEqual(xbox.centeringShift, 3)
        XCTAssertEqual(ps5.logicalTVHeight, 304, accuracy: 0.5)
        XCTAssertEqual(xbox.logicalTVHeight, 296, accuracy: 0.5)
        XCTAssertEqual(ps5.tvContentScale, 1.9575, accuracy: 0.001)
        XCTAssertEqual(xbox.tvContentScale, 2.015, accuracy: 0.001)
        // Sahne hiç büyümez; dar alanda küçülür.
        XCTAssertEqual(LivingRoomGeometry.scale(for: CGSize(width: 4000, height: 3000)), 1)
        XCTAssertEqual(LivingRoomGeometry.scale(for: CGSize(width: 836, height: 941)), 0.5, accuracy: 0.0001)
        // Sarkan fiş dik durur, prize yakın fiş prize döner.
        XCTAssertEqual(ps5.plugAngle(at: ps5.hangPoint), 0, accuracy: 0.0001)
        let nearLeft = CGPoint(x: ps5.socket.x - 100, y: ps5.socket.y)
        let expected = atan2(-(ps5.socket.x - nearLeft.x), ps5.socket.y - nearLeft.y)
        XCTAssertEqual(ps5.plugAngle(at: nearLeft), Double(expected), accuracy: 0.0001)
        XCTAssertTrue(ps5.isNearSocket(CGPoint(x: ps5.socket.x + 100, y: ps5.socket.y + 90)))
        XCTAssertFalse(ps5.isNearSocket(ps5.hangPoint))
        // Takılı kablo fişin 30 altında biter; birinci kontrol noktası çıkış yönünde 90.
        let seated = ps5.cableCurve(plug: ps5.socket, seated: true)
        XCTAssertEqual(seated.end, CGPoint(x: 1564, y: 408))
        XCTAssertEqual(seated.control1.x, 1552 + 45, accuracy: 0.001)
        XCTAssertEqual(seated.control2, CGPoint(x: 1574, y: 578))
        // Sarkan kablo fişin 40 üstündeki boğaza girer.
        let loose = ps5.cableCurve(plug: ps5.hangPoint, seated: false)
        XCTAssertEqual(loose.end, CGPoint(x: 1600, y: 845))
    }

    /// Fiş ipucu prizin üstünde: ok ucu prizin tam üstünde, balon TV'nin sağında ve alanın içinde.
    func testPlugHintPlacement() {
        for geometry in [LivingRoomGeometry.ps5, .xbox] {
            for size in [CGSize(width: 992, height: 520), CGSize(width: 1500, height: 900), CGSize(width: 1800, height: 1000)] {
                let socket = geometry.viewPoint(geometry.socket, in: size)
                let hint = geometry.plugHintPlacement(in: size)
                XCTAssertEqual(hint.arrowTip.x, socket.x, accuracy: 0.001)
                XCTAssertLessThan(hint.arrowTip.y, socket.y)
                XCTAssertLessThan(hint.box.maxY, hint.arrowTip.y)
                XCTAssertGreaterThanOrEqual(hint.box.minX, geometry.viewPoint(CGPoint(x: geometry.tvFrame.maxX, y: 0), in: size).x)
                XCTAssertLessThanOrEqual(hint.box.maxX, size.width)
                XCTAssertGreaterThan(hint.box.maxX, socket.x)
                XCTAssertGreaterThan(hint.box.height, 40)
            }
        }
        // Tuval noktası ölçek ve ortalama kaymasıyla taşınır.
        let size = CGSize(width: 836, height: 941)
        let p = LivingRoomGeometry.ps5.viewPoint(.zero, in: size)
        XCTAssertEqual(p, LivingRoomGeometry.ps5.origin(in: size))
    }

    /// Alt şeridin kısa etiketleri 12 dilde var ve kısa; her kopma nedeni kısa bir etikete düşer.
    func testShortStatusLabels() {
        let languages = ["en", "tr", "ar", "bn", "fil", "hi", "id", "ms", "nl", "th", "ur", "vi"]
        for key in HomeStatus.shortKeys {
            for language in languages {
                let value = NinoL10n.string(key, table: "Home", language: language)
                XCTAssertNotEqual(value, key, "\(key) \(language)")
                XCTAssertLessThanOrEqual(value.count, 24, "\(key) \(language): \(value)")
            }
        }
        let reasons: [SourceStatus.DropReason] = [.asleep, .inUseElsewhere, .refused, .passcodeRequired, .passcodeWrong,
                                                  .pairingInvalid, .remotePlayDisabled, .noPicture,
                                                  .notFound(address: "192.168.0.93"), .network, .rejected(code: 7),
                                                  .rejected(code: nil), .other(detail: "x"), .other(detail: nil)]
        for reason in reasons { XCTAssertTrue(HomeStatus.shortKeys.contains(HomeStatus.dropShortKey(reason))) }
        let state = notFoundState(language: "tr")
        let tr = Locale(identifier: "tr")
        XCTAssertEqual(HomeStatus.sourceShortValue(state, tr), "Bulunamadı")
        XCTAssertTrue(HomeStatus.sourceValue(state, tr).contains("192.168.0.93"))
        // Çeviri etiketi: oyun yoksa yalnız "Nino"; hiçbir dilde "Premium" ya da "ücretsiz" yok.
        XCTAssertEqual(HomeStatus.translationValue(state, tr), "Nino")
        XCTAssertEqual(HomeStatus.translationValue(state, Locale(identifier: "en")), "Nino")
        state.game = RecognizedGame(id: "gta6", name: "GTA 6", poolFirst: true, evidence: .screen)
        XCTAssertEqual(HomeStatus.translationValue(state, tr), "Nino · GTA 6 Aktif")
        XCTAssertEqual(HomeStatus.translationValue(state, Locale(identifier: "en")), "Nino · GTA 6 active")
        state.settings.onlineTranslation = true
        state.settings.onlineEngine = .deepl
        XCTAssertEqual(HomeStatus.translationValue(state, tr), "Nino · GTA 6 Aktif", "havuz öncelikli oyun önce gelir")
        state.game = RecognizedGame(id: "x", name: "Other", poolFirst: false, evidence: .screen)
        XCTAssertEqual(HomeStatus.translationValue(state, tr), "DeepL")
        state.settings.onlineTranslation = false
        XCTAssertEqual(HomeStatus.translationValue(state, tr), "Nino · Other Aktif")
        for language in ["en", "tr", "ar", "bn", "fil", "hi", "id", "ms", "nl", "th", "ur", "vi"] {
            let value = NinoL10n.string("home.translation.poolGame %@", table: "Home", language: language)
            XCTAssertFalse(value.localizedCaseInsensitiveContains("premium"), language)
        }
    }

    func testBalancedSubtitleLines() {
        let short = SubtitleText.balancedLines("Buraya gel.")
        XCTAssertEqual(short.text, "Buraya gel.")
        let long = SubtitleText.balancedLines("NADIA: Feneri yak ve kayığı iskeleye bağla, yoksa dalgalar onu sabaha kadar açığa sürükler.")
        XCTAssertTrue(long.text.hasPrefix("NADIA: Feneri"))
        XCTAssertLessThanOrEqual(long.text.components(separatedBy: "\n").count, 3)
        XCTAssertGreaterThanOrEqual(long.shrink, 0.75)
    }

    // MARK: Ortak bileşenler

    func testDesignGallery() throws {
        for scheme in [ColorScheme.light, .dark] {
            try render(DesignGallery(), size: CGSize(width: 760, height: 1000), scheme: scheme,
                       name: "design-gallery-\(scheme == .dark ? "dark" : "light")")
        }
    }

    // MARK: Ana ekran

    private func homeState(translating: Bool, style: MacSettings.HomeStyle = .livingRoom,
                           language: String = "tr", console: MacSettings.GameConsole = .ps5) -> AppState {
        let state = PreviewEngine.sampleState()
        state.settings.homeStyle = style
        state.settings.targetLanguage = language
        state.settings.gameConsole = console
        state.version = AppVersionInfo(short: "V4.5", full: "4.5.0")
        if translating {
            state.translation = .on
            state.source = .ps5(.streaming)
            state.connectedDisplays = 1
        }
        return state
    }

    private func renderHome(_ state: AppState, scheme: ColorScheme, name: String) throws {
        let ui = HomeUIState(skipIntro: true)
        try render(MainWindowView(state: state, ui: ui), size: CGSize(width: 1040, height: 720), scheme: scheme,
                   locale: MainWindowView.interfaceLanguage(for: state.settings.targetLanguage), name: name)
    }

    func testLivingRoomOff() throws {
        try renderHome(homeState(translating: false), scheme: .light, name: "home-livingroom-off-light")
        try renderHome(homeState(translating: false), scheme: .dark, name: "home-livingroom-off-dark")
    }

    func testLivingRoomOn() throws {
        try renderHome(homeState(translating: true), scheme: .light, name: "home-livingroom-on-light")
        try renderHome(homeState(translating: true), scheme: .dark, name: "home-livingroom-on-dark")
    }

    func testLivingRoomXbox() throws {
        let state = homeState(translating: true, console: .xbox)
        state.settings.videoSource = .window
        state.source = .window(.reading(appName: "Xbox"))
        state.xboxStep = .waitingForWindow
        try renderHome(state, scheme: .dark, name: "home-livingroom-xbox-dark")
    }

    func testGlassSwitch() throws {
        try renderHome(homeState(translating: false, style: .toggle), scheme: .light, name: "home-toggle-off-light")
        try renderHome(homeState(translating: true, style: .toggle), scheme: .dark, name: "home-toggle-on-dark")
    }

    func testArabicRightToLeft() throws {
        let state = homeState(translating: true, language: "ar")
        state.lastLine = LiveLine(translated: "تعال إلى هنا، الآن.", source: "Come here, now.", origin: .engine)
        try renderHome(state, scheme: .light, name: "home-livingroom-ar-rtl")
        try renderHome(homeState(translating: false, language: "ar"), scheme: .dark, name: "home-livingroom-ar-rtl-off")
    }

    /// Salon kaydırılmaz: şerit ve uyarı varken sahne küçülür.
    /// Arapça ve Tayca ana ekran (`apps/mac/snapshots/l10n-home-*.png`): taşma/kesilme denetimi için.
    func testLocalizedHome() throws {
        for language in ["ar", "th"] {
            try renderHome(homeState(translating: true, language: language), scheme: .light,
                           name: "l10n-home-livingroom-\(language)")
            try renderHome(homeState(translating: false, style: .toggle, language: language), scheme: .dark,
                           name: "l10n-home-toggle-\(language)")
        }
    }

    func testLivingRoomWithBannerAndWarning() throws {
        let state = homeState(translating: true)
        state.update = .available(version: "4.2.0")
        state.translator = .languagePackMissing(source: "en", target: "tr")
        try renderHome(state, scheme: .light, name: "home-livingroom-banner-warning-light")
    }

    func testWarningsAndUpdate() throws {
        let state = homeState(translating: true, style: .toggle)
        state.update = .available(version: "4.2.0")
        state.localNetworkBlocked = true
        state.textReadingFailure = TextReadingFailure(freeDiskGB: 4.2)
        try renderHome(state, scheme: .light, name: "home-toggle-warnings-light")
    }

    /// PS5 bulunamadı (çeviri açık, TV uygulaması bekleniyor): şeritte yalnız kısa durum, fişin üstünde ipucu.
    private func notFoundState(language: String) -> AppState {
        let state = homeState(translating: true, language: language)
        state.source = .ps5(.dropped(.notFound(address: "192.168.0.93")))
        state.connectedDisplays = 0
        return state
    }

    /// Oyun tanındı (GTA 6): sağ altta "Çeviri  Nino · GTA 6 Aktif"; oyun yoksa yalnız "Nino".
    func testTranslationLabel() throws {
        for language in ["tr", "ar"] {
            for scheme in [ColorScheme.light, .dark] {
                let state = homeState(translating: true, language: language)
                state.game = RecognizedGame(id: "gta6", name: "GTA 6", poolFirst: true, evidence: .screen)
                try renderHome(state, scheme: scheme,
                               name: "home-game-gta6-\(language)-\(scheme == .dark ? "dark" : "light")")
            }
        }
    }

    func testPS5NotFound() throws {
        for language in ["tr", "ar", "nl"] {
            for scheme in [ColorScheme.light, .dark] {
                try renderHome(notFoundState(language: language), scheme: scheme,
                               name: "home-ps5-notfound-\(language)-\(scheme == .dark ? "dark" : "light")")
            }
        }
    }

    /// En kalabalık şerit (uzun dillerde): kısa durum, TV, yeni sürüm hapı ve uzun oyun adı yan yana.
    func testCrowdedStrip() throws {
        for language in ["bn", "nl", "ar", "tr"] {
            let state = notFoundState(language: language)
            state.source = .ps5(.dropped(.remotePlayDisabled))
            state.update = .available(version: "4.6.0")
            state.game = RecognizedGame(id: "long", name: "Tom Clancy's Ghost Recon Breakpoint Ultimate Edition",
                                        poolFirst: true, evidence: .screen)
            try renderHome(state, scheme: .light, name: "home-strip-crowded-\(language)")
        }
    }

    /// Fiş takılı değil, PS5 bağlı değil: ipucu önce neyin bağlanacağını söyleyip prizi gösterir (PS5 ve Xbox salonu).
    func testPlugHintUnplugged() throws {
        let ps5 = homeState(translating: false)
        ps5.pairedConsole = nil
        ps5.source = .ps5(.idle)
        try renderHome(ps5, scheme: .light, name: "home-plughint-off-ps5")
        let xbox = homeState(translating: false, console: .xbox)
        xbox.settings.videoSource = .window
        xbox.source = .window(.idle)
        xbox.pairedTV = nil
        try renderHome(xbox, scheme: .dark, name: "home-plughint-off-xbox")
        let arabic = homeState(translating: false, language: "ar")
        arabic.pairedConsole = nil
        try renderHome(arabic, scheme: .dark, name: "home-plughint-off-ar")
    }

    func testSubtitleThemes() throws {
        try render(ThemeGallery(), size: CGSize(width: 900, height: 820), scheme: .dark, name: "subtitle-themes")
    }

    func testOverlayAndStreamWindows() throws {
        let state = homeState(translating: true)
        state.settings.output = .both
        state.overlayAdjusting = true
        state.extraAreaTexts = [ExtraAreaText(id: "quest", text: "Görev: Lucia'yı bul", alignment: .trailing)]
        let stack = SubtitleStack()
        stack.push("Buraya gel, hemen.", stackPrevious: true)
        try render(SubtitleOverlayContent(state: state, stack: stack, mover: nil)
                    .background(Color.gray), size: CGSize(width: 1000, height: 300), scheme: .dark,
                   name: "overlay-adjusting")
        state.lastLine = LiveLine(translated: "Buraya gel, hemen.", source: "Come here, now.", origin: .pack)
        try render(StreamWindowContent(state: state), size: CGSize(width: 960, height: 540), scheme: .dark,
                   name: "stream-window")
    }

    func testSplash() throws {
        try render(NinoSplashView(), size: CGSize(width: 1040, height: 720), scheme: .dark, name: "splash-dark")
    }

    // MARK: Yardımcılar

    static var snapshotFolder: URL {
        URL(fileURLWithPath: #filePath).resolvingSymlinksInPath()
            .deletingLastPathComponent() // NinoMacKitTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // NinoMacKit
            .deletingLastPathComponent() // apps/mac
            .appendingPathComponent("snapshots", isDirectory: true)
    }

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
        let folder = Self.snapshotFolder
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try png.write(to: folder.appendingPathComponent(name + ".png"))
    }
}

/// Ortak bileşenlerin tek sayfada görünüşü (yalnız public API ile).
private struct DesignGallery: View {
    @State private var segment = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                NinoLogo(size: 46)
                NinoWordmark(size: 24)
                Spacer()
                NinoRoundIconButton(systemName: NinoSymbol.history, label: "Geçmiş") {}
                NinoRoundIconButton(systemName: NinoSymbol.settings, label: "Ayarlar") {}
            }
            HStack(spacing: 12) {
                Button("Birincil") {}.buttonStyle(.nino(.primary))
                Button("İkincil") {}.buttonStyle(.nino(.secondary))
                Button("Tehlikeli") {}.buttonStyle(.nino(.danger))
                Button("Hayalet") {}.buttonStyle(.nino(.ghost))
                Button("Kapalı") {}.buttonStyle(.nino(.primary)).disabled(true)
            }
            Button("Ana eylem") {}.buttonStyle(.nino(.primary, size: .hero, fullWidth: true))
            NinoSegmentedPicker(selection: $segment, options: [
                .init(0, title: "TV", systemImage: NinoSymbol.outputTV),
                .init(1, title: "Bilgisayar", systemImage: NinoSymbol.outputComputer),
                .init(2, title: "İkisi de", systemImage: NinoSymbol.outputBoth),
            ])
            HStack(alignment: .top, spacing: 12) {
                NinoStatusTile(systemName: "playstation.logo", title: "PS5", value: "Bağlı", tone: .good)
                NinoStatusTile(systemName: NinoSymbol.outputTV, title: "TV", value: "TV uygulaması bekleniyor",
                               tone: .warning)
                NinoStatusTile(systemName: "sparkles", title: "Çeviri", value: "Ücretsiz", tone: .idle) {
                    Button("Değiştir") {}.buttonStyle(.nino(.ghost))
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            NinoCard(title: "Kart başlığı") {
                NinoStatusRow(title: "PS5", value: "Bağlı", tone: .good)
                NinoStatusRow(title: "TV", value: "Bekleniyor", tone: .warning)
                HStack {
                    NinoTag("v1.2")
                    NinoTag("Paket", kind: .pack)
                    NinoTag("Canlı", kind: .live)
                    NinoTileIcon(systemName: "sparkles")
                    NinoGradientIconBox(systemName: "tv", size: 44)
                }
                NinoHint("İpucu metni burada durur, uzunsa alt satıra kayar.")
                NinoErrorLabel("Bir şeyler ters gitti.")
                NinoOKLabel("Tamam")
            }
            NinoNumberedRow(number: 1, text: "PS5'te Ayarlar › Sistem › Uzaktan Oynama'yı açın.")
            NinoOptionCard(artwork: .asset(.tvOptionAndroid), title: "Android TV", subtitle: "Google TV ve Android TV") {}
            NinoOptionCard(artwork: .symbol(NinoSymbol.gameWindow), title: "Oyun penceresi", subtitle: "PS Remote Play") {}
            TextField("Metin alanı", text: .constant("Metin")).ninoTextField()
        }
        .padding(24)
        .ninoScreen()
    }
}

/// Altı altyazı teması ve dört yazı tipi.
private struct ThemeGallery: View {
    var body: some View {
        VStack(spacing: 18) {
            ForEach(SubtitleStyle.Theme.allCases, id: \.self) { theme in
                var style = SubtitleStyle()
                let _ = style.apply(theme: theme)
                ThemedSubtitleLine("\(SubtitleNames.theme(theme, locale: Locale(identifier: "tr"))): Buraya gel, hemen.",
                                   style: style, size: 34)
            }
            HStack(spacing: 18) {
                ForEach(NinoFonts.subtitleFontOrder, id: \.self) { font in
                    var style = SubtitleStyle()
                    let _ = style.font = font
                    ThemedSubtitleLine(SubtitleNames.font(font, locale: Locale(identifier: "tr")), style: style, size: 26)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LinearGradient(colors: [.orange, .purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
    }
}
