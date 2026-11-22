// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import SwiftUI

/// Salon sahnesi (ana-ekran.md §4.2–§4.10): 1672×941 tuval, ayrılan alana küçülür, hiç büyümez.
/// Her zaman soldan sağa çizilir.
struct LivingRoomScene: View {
    let state: AppState
    let ui: HomeUIState
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.ninoStaticRendering) private var isStatic
    /// Sahne hep soldan sağa çizilir; ipucunun metni ise arayüz dilinin yönünde yazılır.
    @Environment(\.layoutDirection) private var interfaceDirection

    /// Açılış gösterisi: fiş ilk 0,9 sn çıkık durur, indirme sayısı gizlidir.
    @State private var introHolding = true
    @State private var tvPhase: LivingRoomTVContent.Phase?
    @State private var counterAnimate = false
    @State private var dragOffset: CGSize = .zero
    @State private var dragging = false

    private var geometry: LivingRoomGeometry { .forConsole(state.settings.gameConsole) }
    private var holding: Bool { introHolding && !ui.livingRoomIntroPlayed && !isStatic }
    private var plugged: Bool { !holding && state.translation != .off }
    private var shownPhase: LivingRoomTVContent.Phase {
        tvPhase ?? (plugged ? .live : .standby)
    }

    var body: some View {
        GeometryReader { proxy in
            let scale = LivingRoomGeometry.scale(for: proxy.size)
            let origin = geometry.origin(in: proxy.size)
            canvas
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: LivingRoomGeometry.canvas.width * scale,
                       height: LivingRoomGeometry.canvas.height * scale, alignment: .topLeading)
                .offset(x: origin.x, y: origin.y)
            if let key = hintKey, !dragging, !holding {
                PlugHint(text: HomeText.string(key, locale),
                         placement: geometry.plugHintPlacement(in: proxy.size, maxWidth: 220),
                         direction: interfaceDirection)
                    .transition(.opacity)
            }
        }
        .background(ReturnKeyShortcut { ui.handleReturnKey(state) })
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(HomeText.string(plugged ? "home.action.stop" : "home.action.start", locale))
        .accessibilityHint(hintKey.map { HomeText.string($0, locale) } ?? "")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { ui.togglePlug(state) }
        .onAppear(perform: startIntro)
        .onChange(of: plugged) { _, now in
            if now {
                tvPhase = reduceMotion ? .live : .splash
                if reduceMotion { counterAnimate = true }
            } else {
                tvPhase = .standby
                counterAnimate = false
            }
        }
    }

    // MARK: Tuval

    private var canvas: some View {
        let plugPoint = currentPlugPoint
        let seated = plugged && !dragging
        let angle = seated ? 0 : geometry.plugAngle(at: plugPoint)
        let tvSize = CGSize(width: LivingRoomGeometry.logicalTVWidth, height: geometry.logicalTVHeight)
        let screen = geometry.tvScreen
        return ZStack(alignment: .topLeading) {
            LEDLights(geometry: geometry, lit: plugged, poolGame: state.game?.poolFirst == true)
            SocketGlow(center: geometry.socket, visible: !plugged)
            geometry.asset.image
                .interpolation(.high)
                .frame(width: LivingRoomGeometry.canvas.width, height: LivingRoomGeometry.canvas.height)
            Rectangle()
                .fill(Color.black)
                .frame(width: screen.width, height: screen.height)
                .offset(x: screen.minX, y: screen.minY)
            LivingRoomTVContent(phase: shownPhase, state: state, showCounter: !holding,
                                animateCounter: counterAnimate, size: tvSize,
                                onSplashFinished: splashFinished)
                .scaleEffect(geometry.tvContentScale, anchor: .topLeading)
                .frame(width: screen.width, height: screen.height, alignment: .topLeading)
                .clipped()
                .offset(x: screen.minX, y: screen.minY)
                .allowsHitTesting(false)
            Color.clear
                .frame(width: 120, height: 120)
                .contentShape(Rectangle())
                .onTapGesture { ui.togglePlug(state) }
                .position(geometry.socket)
            CableView(geometry: geometry, plug: plugPoint, seated: seated)
            PlugView(seated: seated, angle: angle, dragging: dragging)
                .gesture(dragGesture)
                .onTapGesture { ui.togglePlug(state) }
                .help(HomeText.string(plugged ? "home.plug.unplugToStop" : "home.plug.plugInToStart", locale))
                .position(plugPoint)
        }
        .frame(width: LivingRoomGeometry.canvas.width, height: LivingRoomGeometry.canvas.height, alignment: .topLeading)
        .coordinateSpace(.named("livingRoom"))
        .animation(reduceMotion ? nil : NinoMotion.spring(0.5, 0.78), value: plugged)
        .animation(reduceMotion ? nil : NinoMotion.spring(0.5, 0.78), value: dragging)
    }

    private var currentPlugPoint: CGPoint {
        let rest = geometry.restingPoint(plugged: plugged)
        return CGPoint(x: rest.x + dragOffset.width, y: rest.y + dragOffset.height)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named("livingRoom"))
            .onChanged { value in
                dragging = true
                dragOffset = value.translation
            }
            .onEnded { value in
                let rest = geometry.restingPoint(plugged: plugged)
                let drop = CGPoint(x: rest.x + value.translation.width, y: rest.y + value.translation.height)
                let near = geometry.isNearSocket(drop)
                withAnimation(reduceMotion ? nil : NinoMotion.spring(0.45, 0.75)) {
                    dragOffset = .zero
                    dragging = false
                }
                if near != plugged { ui.togglePlug(state) }
            }
    }

    // MARK: Gösteriler

    private func startIntro() {
        if isStatic || ui.livingRoomIntroPlayed {
            introHolding = false
            // Gösteri oynamışken çeviri zaten açıksa açılış atlanır, doğrudan canlı ekran.
            tvPhase = plugged ? .live : .standby
            return
        }
        Task { @MainActor in
            if !reduceMotion { try? await Task.sleep(for: .milliseconds(900)) }
            withAnimation(reduceMotion ? nil : NinoMotion.spring(0.55, 0.7)) {
                introHolding = false
            }
            ui.livingRoomIntroPlayed = true
        }
    }

    private func splashFinished() {
        guard tvPhase == .splash else { return }
        tvPhase = .live
        counterAnimate = true
    }
}

/// Fiş ipucu (§4.9): prizin hemen üstünde tek kısa satırlık küçük balon ve prizi gösteren ok. Balon TV ile pencere
/// kenarı arasında kalır, hiçbir görselin üstüne binmez. Ok ucu sahne ölçeğiyle prize bağlıdır; balonun yazısı
/// ölçeklenmez (dar pencerede de okunur).
struct PlugHint: View {
    let text: String
    let placement: LivingRoomGeometry.HintPlacement
    let direction: LayoutDirection

    var body: some View {
        let box = placement.box
        ZStack(alignment: .topLeading) {
            Text(text)
                .font(.nino(.callout))
                .foregroundStyle(NinoColor.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, NinoSpacing.m)
                .padding(.vertical, 6)
                .ninoGlass(cornerRadius: NinoRadius.inner + 2, edge: true)
                .environment(\.layoutDirection, direction)
                .frame(width: box.width, height: box.height, alignment: .bottomTrailing)
                .position(x: box.midX, y: box.midY)
            Image(systemName: "arrow.down")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(NinoColor.accent)
                .frame(width: 18, height: 18)
                .position(x: placement.arrowTip.x, y: placement.arrowTip.y - 9)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension LivingRoomScene {
    /// İpucunun metni, ilk uyan (§4.9): açıkken fişi çıkarmaya, başlatılabiliyorken takmaya çağırır;
    /// başlatılamıyorsa önce ne bağlanacağını söyler.
    var hintKey: String? {
        if state.translation != .off { return plugged ? "home.plug.unplugToStop" : nil }
        if state.canStart { return "home.plug.plugInToStart" }
        if state.settings.gameConsole == .xbox { return "home.hint.connectTVFirst" }
        return "home.hint.connectPS5First"
    }
}
