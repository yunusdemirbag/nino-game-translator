// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import AppKit
import Observation
import SwiftUI

// Ekran dışı altyazı penceresi (ana-ekran.md §11): kenarsız, odak almayan, her şeyin üstünde yüzen panel.
// Pencere yönetimi basit tutuldu; görünüş SwiftUI'da (`SubtitleOverlayContent`).

/// Ayar kipinde klavye alabilen, öbür zamanlarda odak almayan panel.
final class SubtitleOverlayPanel: NSPanel {
    var allowsKey = false
    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }
}

/// İlk tıklama da çalışsın (öndeki uygulama değişmeden taşıma, "Bitti").
final class ClickThroughHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
public final class SubtitleOverlayController {
    /// Eski kaydı korumak için ad aynen kalır.
    public static let savedFrameName = "NinoSubtitleWindow"

    private let state: AppState
    private let stack = SubtitleStack()
    private var panel: SubtitleOverlayPanel?
    private var started = false

    public init(state: AppState) {
        self.state = state
    }

    /// Modele bağlar: görünürlük, fare geçişi, boy ve satırlar durumla birlikte güncellenir.
    public func start() {
        guard !started else { return }
        started = true
        observe()
    }

    private func observe() {
        withObservationTracking {
            update()
        } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
    }

    /// Görünür mü: altyazı bilgisayarda ve (satır var, ek alan var ya da ayar kipinde).
    static func shouldShow(_ state: AppState) -> Bool {
        state.subtitlesOnComputer
            && (state.lastLine != nil || !state.extraAreaTexts.isEmpty || state.overlayAdjusting)
    }

    private func update() {
        let show = Self.shouldShow(state)
        let adjusting = state.overlayAdjusting
        let clickThrough = state.settings.overlayClickThrough
        let fontSize = state.settings.style.fontSize
        let gameArea = state.settings.videoSource == .window ? state.gameAreaFrame : nil
        if let line = state.lastLine?.translated, !line.isEmpty {
            stack.push(line, stackPrevious: state.settings.style.stackPrevious)
        } else if adjusting {
            if stack.visibleLines.isEmpty {
                stack.showSample(NinoL10n.string("home.overlay.sample", table: HomeText.table,
                                                 language: MainWindowView.interfaceLanguage(for: state.settings.targetLanguage)))
            }
        } else {
            stack.clear()
        }
        guard show else {
            panel?.orderOut(nil)
            return
        }
        let panel = self.panel ?? makePanel()
        panel.allowsKey = adjusting
        panel.ignoresMouseEvents = clickThrough && !adjusting
        layout(panel, fontSize: fontSize, gameArea: adjusting ? nil : gameArea)
        if adjusting { panel.makeKeyAndOrderFront(nil) } else { panel.orderFrontRegardless() }
    }

    private func makePanel() -> SubtitleOverlayPanel {
        let panel = SubtitleOverlayPanel(contentRect: NSRect(x: 0, y: 0, width: 800, height: 240),
                                         styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
                                         defer: true)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        let content = SubtitleOverlayContent(state: state, stack: stack, mover: self)
            .environment(\.layoutDirection, .leftToRight)
        panel.contentView = ClickThroughHostingView(rootView: content)
        if !panel.setFrameUsingName(Self.savedFrameName) || !Self.isOnConnectedScreen(panel.frame) {
            panel.setFrame(Self.defaultFrame(height: 240), display: false)
        }
        panel.setFrameAutosaveName(Self.savedFrameName)
        self.panel = panel
        return panel
    }

    // MARK: Yer ve boy (§11.2)

    static func isOnConnectedScreen(_ frame: NSRect) -> Bool {
        NSScreen.screens.contains { $0.frame.intersects(frame) }
    }

    /// Ana ekranın görünür alanının %70'i genişliğinde, ortada, alttan %4 yukarıda.
    static func defaultFrame(height: CGFloat) -> NSRect {
        let visible = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let width = visible.width * 0.7
        return NSRect(x: visible.midX - width / 2, y: visible.minY + visible.height * 0.04, width: width, height: height)
    }

    /// Pencere yüksekliği: yazı boyu × ölçek × 8,1 + 140 × ölçek (yuvarlanır).
    static func height(fontSize: Int, scale: CGFloat) -> CGFloat {
        (CGFloat(fontSize) * scale * 8.1 + 140 * scale).rounded()
    }

    /// Ölçek: pencerenin ekranının yüksekliği / 1080 (oyun alanında alanın yüksekliği / 1080).
    var scale: CGFloat {
        if !state.overlayAdjusting, state.settings.videoSource == .window, let area = state.gameAreaFrame {
            return area.height / 1080
        }
        let screen = panel?.screen ?? NSScreen.main
        return (screen?.frame.height ?? 1080) / 1080
    }

    private func layout(_ panel: SubtitleOverlayPanel, fontSize: Int, gameArea: CGRect?) {
        if let area = gameArea {
            // Oyun alanının altına oturur; kullanıcının kayıtlı yeri değişmesin diye kayıt kapalı.
            panel.setFrameAutosaveName("")
            let scale = area.height / 1080
            let width = area.width * 0.9
            let height = Self.height(fontSize: fontSize, scale: scale)
            panel.setFrame(NSRect(x: area.midX - width / 2, y: area.minY + area.height * 0.03, width: width,
                                  height: height), display: true)
            return
        }
        if panel.frameAutosaveName != Self.savedFrameName {
            panel.setFrameUsingName(Self.savedFrameName)
            panel.setFrameAutosaveName(Self.savedFrameName)
        }
        let height = Self.height(fontSize: fontSize, scale: scale)
        var frame = panel.frame
        if abs(frame.height - height) > 0.5 {
            frame.size.height = height // alt kenar sabit kalır
            panel.setFrame(frame, display: true)
        }
    }

    // MARK: Taşıma ve genişletme

    private var dragStart: (mouse: NSPoint, frame: NSRect)?

    func beginDrag() {
        guard let panel else { return }
        dragStart = (NSEvent.mouseLocation, panel.frame)
    }

    /// Fare imlecinin ekrandaki yeriyle taşır (ekranlar arasında da).
    func drag() {
        guard let panel, let start = dragStart else { return }
        let mouse = NSEvent.mouseLocation
        panel.setFrameOrigin(NSPoint(x: start.frame.minX + mouse.x - start.mouse.x,
                                     y: start.frame.minY + mouse.y - start.mouse.y))
    }

    /// Kenardan genişletme: ortası yerinde kalır, iki yana eşit büyür. En az 320, en çok ekran genişliği.
    func resize(edge: HorizontalEdge) {
        guard let panel, let start = dragStart else { return }
        let dx = NSEvent.mouseLocation.x - start.mouse.x
        let grow = edge == .trailing ? dx : -dx
        let maxWidth = panel.screen?.frame.width ?? 4000
        let width = min(maxWidth, max(320, start.frame.width + 2 * grow))
        panel.setFrame(NSRect(x: start.frame.midX - width / 2, y: start.frame.minY, width: width,
                              height: start.frame.height), display: true)
    }

    func endDrag() {
        dragStart = nil
        // Ekran değişmiş olabilir: yeniden ölç.
        if let panel { layout(panel, fontSize: state.settings.style.fontSize, gameArea: nil) }
    }

    func finishAdjusting() {
        state.overlayAdjusting = false
    }
}

/// Ekran dışı pencerenin içi (§11.3). Alta yaslı katmanlar.
public struct SubtitleOverlayContent: View {
    let state: AppState
    let stack: SubtitleStack
    let mover: SubtitleOverlayController?

    /// - Parameter mover: Pencereyi taşıyan denetleyici; önizlemede nil.
    public init(state: AppState, stack: SubtitleStack, mover: SubtitleOverlayController?) {
        self.state = state
        self.stack = stack
        self.mover = mover
    }

    public var body: some View {
        GeometryReader { proxy in
            let scale = mover?.scale ?? proxy.size.height / 400
            ZStack(alignment: .bottom) {
                if state.overlayAdjusting { adjustFrame }
                lines(scale: scale)
                if state.overlayAdjusting {
                    handles
                    topBar.frame(maxHeight: .infinity, alignment: .top)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .bottom)
        }
        .environment(\.locale, Locale(identifier: MainWindowView.interfaceLanguage(for: state.settings.targetLanguage)))
        .environment(\.layoutDirection, .leftToRight)
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                if value.translation == .zero { mover?.beginDrag() } else { mover?.drag() }
            }
            .onEnded { _ in mover?.endDrag() }
    }

    private var adjustFrame: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        return ZStack {
            shape.fill(Color.black.opacity(0.35))
            shape.strokeBorder(NinoColor.accent, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
        }
        .contentShape(shape)
        .gesture(moveGesture)
    }

    /// Üst çubuk satırların üstünde çizilir ki ek alan kutusu "Bitti"yi örtmesin.
    private var topBar: some View {
            HStack(spacing: 12) {
                HText("home.overlay.instructions")
                    .font(.nino(.callout).weight(.semibold))
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
                Button {
                    mover?.finishAdjusting()
                } label: {
                    HText("home.overlay.done")
                }
                .buttonStyle(.nino(.primary))
                .keyboardShortcut(.defaultAction)
            }
            .padding(12)
            .contentShape(Rectangle())
            .gesture(moveGesture)
    }

    private var handles: some View {
        HStack {
            resizeGrip(.leading)
            Spacer()
            resizeGrip(.trailing)
        }
    }

    private func resizeGrip(_ side: HorizontalEdge) -> some View {
        Capsule()
            .fill(NinoColor.accent)
            .frame(width: 6, height: 48)
            .padding(.horizontal, 6)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .onChanged { value in
                    if value.translation == .zero { mover?.beginDrag() } else { mover?.resize(edge: side) }
                }
                .onEnded { _ in mover?.endDrag() })
    }

    private func lines(scale: CGFloat) -> some View {
        let style = state.settings.style
        let band = style.backgroundShape == .band
        return VStack(spacing: 14 * scale) {
            ForEach(state.extraAreaTexts) { extra in
                ExtraAreaBox(extra.text, style: style, scale: scale)
                    .frame(maxWidth: .infinity, alignment: extra.alignment.frameAlignment)
                    .gesture(moveGesture)
            }
            Spacer(minLength: 0)
            ForEach(stack.visibleLines.sorted { $0.rank > $1.rank }) { entry in
                line(entry, style: style, scale: scale)
                    .opacity(SubtitleStack.opacity(for: entry))
                    .gesture(moveGesture)
            }
        }
        .padding(.horizontal, band ? 0 : 24 * scale)
        .padding(.bottom, 8 * scale)
    }

    @ViewBuilder
    private func line(_ entry: SubtitleStack.StackedLine, style: SubtitleStyle, scale: CGFloat) -> some View {
        let isCurrent = entry.rank == 0
        let paragraph = entry.text.contains("\n\n")
        if style.theme != .classic && !paragraph {
            ThemedSubtitleLine(entry.text, style: style,
                               size: CGFloat(style.fontSize) * scale * (isCurrent ? 1 : 0.8), lineLimit: nil)
        } else {
            ClassicSubtitleLine(entry.text, style: style, scale: scale, isCurrent: isCurrent, isParagraph: paragraph)
                .frame(maxWidth: .infinity, alignment: paragraph ? .leading : .center)
        }
    }
}

extension ExtraAreaText.Alignment {
    var frameAlignment: Alignment {
        switch self {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }
}
