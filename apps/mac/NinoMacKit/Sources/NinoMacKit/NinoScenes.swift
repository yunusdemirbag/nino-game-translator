// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import AppKit
import SwiftUI

/// Uygulamanın modeli: ekranların durumu, işi yapan motor, arayüz durumu ve ekran dışı pencere.
/// `AppState.engine` zayıf tutulur; motoru burada güçlü tutarız.
@MainActor
public final class NinoAppModel {
    public let state: AppState
    public let engine: AppEngine
    public let ui: HomeUIState
    public let overlay: SubtitleOverlayController
    /// Bilgisayardaki ekran öğeleri katmanı (telefon paneli, harita kartı…; `ComputerScreenRules`).
    public let screenLayer: ComputerScreenPanelController

    public init(state: AppState, engine: AppEngine, ui: HomeUIState? = nil) {
        NinoFonts.registerBundledFonts()
        self.state = state
        self.engine = engine
        self.ui = ui ?? HomeUIState()
        self.overlay = SubtitleOverlayController(state: state)
        self.screenLayer = ComputerScreenPanelController(state: state)
        state.attach(engine)
        state.version = AppVersionInfo.from(bundle: .main)
    }

    /// Uygulamanın gerçek modeli: çalışan yapının kimliğiyle (`AppIdentity.current`) gerçek motor.
    /// Süreç başına bir kez kurulur (SwiftUI sahneyi yeniden kurunca ikinci motor açılmasın).
    public static var live: NinoAppModel {
        if let shared = sharedLive { return shared }
        let state = AppState()
        let engine = LiveEngine.live(identity: .current(), state: state)
        let model = NinoAppModel(state: state, engine: engine)
        sharedLive = model
        return model
    }

    private static var sharedLive: NinoAppModel?

    /// Sahte motorla örnek durum (önizlemeler ve testler).
    public static func preview() -> NinoAppModel {
        let state = PreviewEngine.sampleState()
        let engine = PreviewEngine(state: state)
        return NinoAppModel(state: state, engine: engine)
    }
}

/// Uygulamanın bütün pencereleri (docs/yeni/mac/ana-ekran.md §1, §2, §13).
public struct NinoScenes: Scene {
    @State private var model: NinoAppModel

    /// Gerçek motorla açılır.
    public init() {
        _model = State(initialValue: NinoAppModel.live)
    }

    /// Durumu ve motoru dışarıdan alır (gerçek motor bağlanınca).
    public init(model: NinoAppModel) {
        _model = State(initialValue: model)
    }

    private var state: AppState { model.state }
    private var language: String { MainWindowView.interfaceLanguage(for: state.settings.targetLanguage) }

    private func text(_ key: String) -> String {
        NinoL10n.string(key, table: HomeText.table, language: language)
    }

    public var body: some Scene {
        Window(Text(verbatim: "Nino"), id: NinoWindowID.main) {
            MainWindowView(state: state, ui: model.ui)
                .background(WindowBridge(state: state, onAppear: {
                    model.overlay.start()
                    model.screenLayer.start(hub: (model.engine as? LiveEngine)?.links.hub)
                }))
                .toolbarBackground(.hidden, for: .windowToolbar)
                .modifier(WindowBackgroundModifier())
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: NinoSize.windowWidth, height: NinoSize.windowHeight)
        .commands { commands }

        Window(Text(verbatim: text("home.stream.title")), id: NinoWindowID.stream) {
            StreamWindowContent(state: state)
                .frame(minWidth: 480, minHeight: 270)
        }
        .defaultSize(width: 1280, height: 720)
        .defaultPosition(.center)

        MenuBarExtra(isInserted: Binding(get: { state.isSetupComplete && state.subtitlesOnComputer }, set: { _ in })) {
            MenuBarContent(state: state, language: language)
        } label: {
            Image(systemName: NinoSymbol.menuBar)
            Text(verbatim: "Nino")
        }
    }

    @CommandsBuilder private var commands: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button(text("home.menu.about")) { state.open(.about) }
            OpenWindowCatcher()
        }
        CommandGroup(replacing: .appSettings) {
            Button(text("home.menu.settings")) { state.open(.settings) }
                .keyboardShortcut(",", modifiers: .command)
                .disabled(!state.isSetupComplete)
        }
    }
}

public enum NinoWindowID {
    public static let main = "main"
    public static let stream = "stream"
}

/// macOS 15+: pencerenin kendi zemini `background` belirteci.
private struct WindowBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.containerBackground(NinoColor.background, for: .window)
        } else {
            content
        }
    }
}

/// Yayın penceresini durumla açıp kapatır; açılışta ekran dışı pencereyi bağlar.
private struct WindowBridge: View {
    let state: AppState
    let onAppear: () -> Void
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        Color.clear
            .onAppear {
                NinoAppDelegate.openWindowAction = openWindow
                onAppear()
            }
            .onChange(of: state.streamWindowOpen) { _, open in
                if open { openWindow(id: NinoWindowID.stream) } else { dismissWindow(id: NinoWindowID.stream) }
            }
    }
}

/// Menü çubuğu öğesinin içi (§2.2).
private struct MenuBarContent: View {
    let state: AppState
    let language: String
    @Environment(\.openWindow) private var openWindow

    private var locale: Locale { Locale(identifier: language) }

    var body: some View {
        if state.settings.videoSource == .card {
            Text(HomeStatus.sourceText(state, locale))
            if state.translation == .on, state.subtitlesOnComputer {
                Button(HomeText.string("home.menu.gameFullScreen", locale)) { state.cardFullScreen.toggle() }
                    .keyboardShortcut("f", modifiers: [.control, .command])
            }
            Divider()
        }
        Toggle(HomeText.string("home.menu.clickThrough", locale),
               isOn: Binding(get: { state.settings.overlayClickThrough },
                             set: { state.settings.overlayClickThrough = $0 }))
        Button(HomeText.string("home.overlay.adjust", locale)) { state.overlayAdjusting = true }
        Divider()
        Button(HomeText.string("home.menu.openNino", locale)) {
            NinoAppDelegate.openWindowAction = openWindow
            NinoAppDelegate.showMainWindow()
        }
    }
}
