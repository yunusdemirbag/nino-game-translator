// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import AppKit
import NinoCore
import Observation
import WebKit

/// Ekran öğeleri katmanının paneli: kenarsız, saydam, odak almayan, tıklamaları geçiren.
final class ComputerScreenPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Bilgisayardaki ekran öğeleri katmanı (telefon paneli, harita kartı, köşeler, ipuçları; kural:
/// `ComputerScreenRules`). TV sayfası oyunun ekrandaki alanının (`AppState.gameAreaFrame`) tam üstündeki panelde
/// çalışır ve 1920 × 1080 düzenini korur (yakınlaştırma = alan genişliği / 1920); öğeler TV'dekiyle aynı yerde ve
/// görünümdedir. Alt altyazı ve ek alanlar burada çizilmez (altyazı penceresinde).
///
/// Sayfa yalnız katman gerekebilecekken (altyazı bilgisayarda ve çeviri açık) kurulur, çeviri durunca bırakılır.
/// Panel altyazı penceresinin bir düzey altında durur (altyazı öğelerin üstünde kalır).
@MainActor
public final class ComputerScreenPanelController {
    static let level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue - 1)

    private let state: AppState
    public let feed = ComputerScreenFeed()
    private var panel: ComputerScreenPanel?
    private var page: TVPageWeb?
    /// Sayfa yokken gelen son ekran mesajı (sayfa kurulunca verilir).
    private var lastScreen: String?
    private var hasItems = false
    private var expiry: Task<Void, Never>?
    private var started = false

    public init(state: AppState) {
        self.state = state
        feed.onMessage = { [weak self] json in
            Task { @MainActor in self?.receive(json) }
        }
    }

    /// Modele ve hub'a bağlar (hub yoksa yalnız model; önizleme).
    public func start(hub: DisplayHub?) {
        guard !started else { return }
        started = true
        if let hub {
            let feed = self.feed
            Task { await hub.add(feed, key: ComputerScreenFeed.hubKey) }
        }
        observe()
    }

    private func observe() {
        withObservationTracking {
            update()
        } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
    }

    /// Katmana giden bir mesaj (JSON).
    func receive(_ json: String) {
        if let change = ComputerScreenRules.hasItems(after: json) {
            hasItems = change.has
            lastScreen = change.has ? json : nil
            expiry?.cancel()
            expiry = nil
            if change.has, change.durationMs > 0 {
                let ms = change.durationMs
                expiry = Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(ms))
                    guard !Task.isCancelled else { return }
                    self?.hasItems = false
                    self?.update()
                }
            }
        }
        page?.receive(json)
        update()
    }

    private var mayShow: Bool { state.subtitlesOnComputer && state.translation == .on }

    private func update() {
        let area = state.gameAreaFrame
        guard mayShow else {
            tearDown()
            return
        }
        let page = self.page ?? makePage()
        let visible = ComputerScreenRules.isVisible(subtitlesOnComputer: state.subtitlesOnComputer,
                                                    translating: state.translation == .on, gameArea: area,
                                                    hasItems: hasItems)
        guard visible, let area else {
            panel?.orderOut(nil)
            return
        }
        let panel = self.panel ?? makePanel(page)
        layout(panel, page: page, area: area)
        panel.orderFrontRegardless()
    }

    private func makePage() -> TVPageWeb {
        let page = TVPageWeb(frame: CGRect(origin: .zero, size: TVPageWeb.layoutSize), hidden: ComputerScreenRules.hiddenParts)
        if let lastScreen { page.receive(lastScreen) }
        self.page = page
        return page
    }

    private func makePanel(_ page: TVPageWeb) -> ComputerScreenPanel {
        let panel = ComputerScreenPanel(contentRect: NSRect(x: 0, y: 0, width: 960, height: 540),
                                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = true
        panel.isExcludedFromWindowsMenu = true
        // isFloatingPanel düzeyi .floating'e çeker; kullanılmaz, düzey en sonda.
        panel.level = Self.level
        page.webView.autoresizingMask = [.width, .height]
        panel.contentView = page.webView
        self.panel = panel
        return panel
    }

    private func layout(_ panel: ComputerScreenPanel, page: TVPageWeb, area: CGRect) {
        let zoom = ComputerScreenRules.pageZoom(for: area)
        if abs(page.webView.pageZoom - zoom) > 0.0001 { page.webView.pageZoom = zoom }
        if panel.frame != area { panel.setFrame(area, display: true) }
    }

    private func tearDown() {
        if state.translation == .off {
            expiry?.cancel()
            expiry = nil
            hasItems = false
            lastScreen = nil
        }
        guard panel != nil || page != nil else { return }
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel?.close()
        panel = nil
        page = nil
    }

    // MARK: Testler

    var pageForTesting: TVPageWeb? { page }
    var panelForTesting: NSPanel? { panel }
    var isShowing: Bool { panel?.isVisible ?? false }
}
