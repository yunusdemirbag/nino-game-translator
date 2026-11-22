// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import SwiftUI

/// Cam anahtar (ana-ekran.md §5.2): 400×92 iz, üstünde kayan 116'lık cam küre. Her zaman soldan sağa.
struct GlassSwitch: View {
    let state: AppState
    let ui: HomeUIState
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.ninoStaticRendering) private var isStatic
    @State private var drag: CGFloat = 0
    @State private var dragging = false
    @State private var hovering = false

    static let trackSize = CGSize(width: 400, height: 92)
    static let knob: CGFloat = 116
    static let travel: CGFloat = trackSize.width - trackSize.height // 308

    private var on: Bool { state.translation == .on }
    private var preparing: Bool { state.translation == .starting }

    var body: some View {
        let base: CGFloat = on ? Self.travel : 0
        let position = min(Self.travel, max(0, base + drag))
        let p = Double(position / Self.travel)
        ZStack(alignment: .leading) {
            track(p)
            labels(p)
            knob(p)
                .offset(x: position - 12)
                .scaleEffect(hovering ? 1.04 : 1)
                .animation(.spring(response: 0.3), value: hovering)
                .onHover { hovering = $0 }
                .gesture(dragGesture)
        }
        .frame(width: Self.trackSize.width, height: Self.trackSize.height)
        .contentShape(Capsule())
        .onTapGesture { ui.togglePlug(state) }
        .opacity(state.canStart && preparing ? 0.6 : 1)
        .animation(reduceMotion ? nil : NinoMotion.spring(0.55, 0.8), value: on)
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(HomeText.string(on ? "home.action.stop" : "home.action.start", locale))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { ui.togglePlug(state) }
    }

    // MARK: İz

    private func track(_ p: Double) -> some View {
        let gray = NinoRGB(0.30, 0.36, 0.52)
        return ZStack {
            Capsule().fill(LinearGradient(colors: [NinoRGB(0.47, 0.55, 0.70).color, gray.color], startPoint: .top,
                                          endPoint: .bottom))
            Capsule().fill(LinearGradient(colors: [NinoFixedColor.flagRed.color, NinoFixedColor.flagRedDark.color],
                                          startPoint: .top, endPoint: .bottom))
                .opacity(p)
            Capsule()
                .fill(LinearGradient(stops: [.init(color: .white.opacity(0.35), location: 0),
                                             .init(color: .white.opacity(0), location: 0.5)],
                                     startPoint: .top, endPoint: .bottom))
                .padding(3)
            Capsule().strokeBorder(.white.opacity(0.45), lineWidth: 1)
        }
        .shadow(color: (p > 0.5 ? NinoFixedColor.flagRed : gray).color(opacity: 0.25 + 0.35 * p), radius: 22, y: 10)
    }

    // MARK: Yazılar

    private func labels(_ p: Double) -> some View {
        ZStack {
            VStack(alignment: .trailing, spacing: 2) {
                Text(idleHeadline).font(.ninoRounded(22, weight: .semibold))
                Text(idleCaption)
                    .font(.system(size: 12, weight: .medium))
                    .opacity(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 30)
            .opacity(1 - p)
            VStack(alignment: .leading, spacing: 2) {
                HText("home.switch.onTitle").font(.ninoRounded(26, weight: .bold))
                HText("home.switch.onSubtitle").font(.system(size: 12, weight: .medium)).opacity(0.85)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 34)
            .opacity(p)
        }
        .foregroundStyle(.white)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .allowsHitTesting(false)
    }

    private var idleHeadline: String {
        if preparing { return HomeText.string("home.status.connecting", locale) }
        if !state.canStart { return HomeText.string("home.switch.connectPS5", locale) }
        return HomeText.string("home.switch.turnOn", locale)
    }

    private var idleCaption: String {
        HomeText.string(state.canStart || preparing ? "home.switch.subtitles" : "home.switch.tapToSetUp", locale)
    }

    // MARK: Küre

    /// Kürenin iç dairesine göre güç simgesi ve ay-yıldız boyu.
    private static let powerGlyph: CGFloat = 0.42
    private static let emblem: CGFloat = 0.72

    private func knob(_ p: Double) -> some View {
        let k = Self.knob
        let inner = 0.62 * k
        return ZStack {
            Circle().fill(NinoRGB(0.36, 0.43, 0.60).color).frame(width: inner, height: inner)
            Circle().fill(NinoFixedColor.flagRed.color).frame(width: inner, height: inner).opacity(p)
            if preparing {
                if isStatic {
                    Image(systemName: "hourglass").font(.system(size: 20, weight: .semibold)).foregroundStyle(.white)
                } else {
                    ProgressView()
                        .controlSize(.regular)
                        .tint(.white)
                }
            } else {
                Image(systemName: NinoSymbol.power)
                    .font(.system(size: inner * Self.powerGlyph, weight: .bold))
                    .foregroundStyle(.white)
                    .opacity(1 - p)
                CrescentStar(cutout: NinoFixedColor.flagRed.color)
                    .frame(width: inner * Self.emblem, height: inner * Self.emblem)
                    .opacity(p)
                    .scaleEffect(0.7 + 0.3 * p)
            }
            glass(k)
            Ellipse()
                .fill(LinearGradient(colors: [.white.opacity(0.65), .white.opacity(0)], startPoint: .top,
                                     endPoint: .bottom))
                .frame(width: 0.55 * k, height: 0.28 * k)
                .offset(x: -0.12 * k, y: -0.28 * k)
                .blur(radius: 2)
        }
        .frame(width: k, height: k)
        .compositingGroup()
        .shadow(color: .black.opacity(0.18), radius: 14, y: 8)
        .contentShape(Circle())
    }

    @ViewBuilder private func glass(_ k: CGFloat) -> some View {
        ZStack {
            if isStatic {
                Circle().fill(Color.white.opacity(0.12))
            } else {
                Circle().fill(.ultraThinMaterial).opacity(0.35)
            }
            Circle().strokeBorder(LinearGradient(stops: [.init(color: .white.opacity(0.95), location: 0),
                                                         .init(color: .white.opacity(0.15), location: 0.5),
                                                         .init(color: .white.opacity(0.60), location: 1)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 2)
        }
        .frame(width: k, height: k)
    }

    // MARK: Sürükleme

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                dragging = true
                drag = value.translation.width
            }
            .onEnded { value in
                let end = (on ? Self.travel : 0) + value.translation.width
                let toggle = on ? end < Self.travel * 0.4 : end > Self.travel * 0.6
                withAnimation(reduceMotion ? nil : NinoMotion.spring(0.45, 0.78)) {
                    drag = 0
                    dragging = false
                }
                if toggle { ui.togglePlug(state) }
            }
    }
}

/// Ay yıldız (§5.2): kenarı s olan kare içinde, r = 0,42 s. Oyuk `cutout` rengiyle boyanır.
struct CrescentStar: View {
    let cutout: Color

    var body: some View {
        Canvas { context, size in
            let s = min(size.width, size.height)
            let r = 0.42 * s
            let moonCenter = CGPoint(x: 0.42 * s, y: s / 2)
            context.fill(Path(ellipseIn: CGRect(x: moonCenter.x - r, y: moonCenter.y - r, width: 2 * r, height: 2 * r)),
                         with: .color(.white))
            let hole = 0.8 * r
            let holeCenter = CGPoint(x: 0.42 * s + 0.32 * r, y: s / 2)
            context.fill(Path(ellipseIn: CGRect(x: holeCenter.x - hole, y: holeCenter.y - hole, width: 2 * hole,
                                                height: 2 * hole)),
                         with: .color(cutout))
            context.fill(Self.star(center: CGPoint(x: 0.8 * s, y: s / 2), outer: s * 0.34 / 2), with: .color(.white))
        }
    }

    /// Beş köşeli yıldız; iç yarıçap dışın 0,382 katı, ilk uç sola (π).
    static func star(center: CGPoint, outer: CGFloat) -> Path {
        let inner = outer * 0.382
        var path = Path()
        for index in 0..<10 {
            let angle = Double.pi + Double(index) * .pi / 5
            let radius = index.isMultiple(of: 2) ? outer : inner
            let point = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
            index == 0 ? path.move(to: point) : path.addLine(to: point)
        }
        path.closeSubpath()
        return path
    }
}
