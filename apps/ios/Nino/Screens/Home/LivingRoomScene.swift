// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import SwiftUI
import UIKit

/// Salon sahnesinin görsel üzerindeki ölçüleri (piksel, 1672 genişlikli görsele göre).
struct SceneGeometry {
    let image: String
    let screen: CGRect
    let frame: CGRect
    let table: CGRect
    let socket: CGPoint
    let cablePath: [CGPoint]
    let cableStart: CGPoint
    let exitDirection: CGVector
    let hangingPlug: CGPoint

    static let width: CGFloat = 1672
    /// Kutu görselden 24 piksel uzun (Xbox'ta sarkan fiş taşmasın).
    static let height: CGFloat = 965

    static let ps5 = SceneGeometry(image: "LivingRoom",
                                   screen: CGRect(x: 149, y: 40, width: 1151, height: 595),
                                   frame: CGRect(x: 139, y: 27, width: 1171, height: 621),
                                   table: CGRect(x: 49, y: 713, width: 1502, height: 160),
                                   socket: CGPoint(x: 1564, y: 378),
                                   cablePath: [CGPoint(x: 1490, y: 706), CGPoint(x: 1522, y: 706), CGPoint(x: 1535, y: 709),
                                               CGPoint(x: 1545, y: 716), CGPoint(x: 1552, y: 727)],
                                   cableStart: CGPoint(x: 1550, y: 734),
                                   exitDirection: CGVector(dx: 0.5, dy: 0.87),
                                   hangingPlug: CGPoint(x: 1600, y: 885))

    static let xbox = SceneGeometry(image: "LivingRoomXbox",
                                    screen: CGRect(x: 136, y: 40, width: 1185, height: 596),
                                    frame: CGRect(x: 121, y: 26, width: 1214, height: 630),
                                    table: CGRect(x: 43, y: 733, width: 1580, height: 167),
                                    socket: CGPoint(x: 1561, y: 381),
                                    cablePath: [],
                                    cableStart: CGPoint(x: 1572, y: 722),
                                    exitDirection: CGVector(dx: 1, dy: 0.1),
                                    hangingPlug: CGPoint(x: 1646, y: 912))
}

/// Ana ekrandaki salon: duvarda TV, sehpada konsol, sağda priz. Fiş prize takılınca çeviri başlar.
struct LivingRoomScene: View {
    var xbox = false
    let active: Bool
    let streaming: Bool
    let line: String?
    var source: String? = nil
    var problem: String? = nil
    let badge: String
    var gtaMode = false
    var downloads: Int = 0
    let onToggle: () -> Void
    let onOpenTV: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Açılış gösterisi süreç başına bir kez oynar.
    @MainActor private static var introPlayed = false
    @State private var introPending = !LivingRoomScene.introPlayed
    @State private var drag: CGSize = .zero
    @State private var dragging = false
    @State private var socketPulse = false
    @State private var splashDone = true

    private var g: SceneGeometry { xbox ? .xbox : .ps5 }
    private var plugged: Bool { active && !introPending }

    var body: some View {
        GeometryReader { geo in
            let s = geo.size.width / SceneGeometry.width
            ZStack(alignment: .topLeading) {
                lights(s)
                socketGlow(s)
                Image(g.image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: geo.size.width, height: 941 * s)
                tvScreen(s)
                cable(s)
                plug(s)
                hitArea(at: point(g.socket, s), size: 60)
                    .onTapGesture { haptic(); onToggle() }
                plugHandle(s)
            }
        }
        .aspectRatio(SceneGeometry.width / SceneGeometry.height, contentMode: .fit)
        .environment(\.layoutDirection, .leftToRight)
        .animation(.spring(response: 0.5, dampingFraction: 0.78), value: plugged)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(plugged ? L("scene.stop") : L("scene.start")))
        .accessibilityValue(Text(verbatim: plugged && streaming ? (line ?? "") : ""))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onToggle() }
        .task { await playIntro() }
        .onChange(of: plugged) { _, now in
            if now && !reduceMotion { splashDone = false }
        }
    }

    private func point(_ p: CGPoint, _ s: CGFloat) -> CGPoint { CGPoint(x: p.x * s, y: p.y * s) }

    private func playIntro() async {
        guard introPending else { return }
        LivingRoomScene.introPlayed = true
        if reduceMotion { introPending = false; return }
        if active { splashDone = true }
        try? await Task.sleep(for: .milliseconds(900))
        withAnimation(.spring(response: 0.55, dampingFraction: 0.7)) { introPending = false }
    }

    private func haptic() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }

    // MARK: Işıklar

    private var wideColors: [Color] {
        gtaMode ? [Color(red: 1, green: 0.24, blue: 0.62), Color(red: 0.74, green: 0.5, blue: 0.96), Color(red: 0.3, green: 0.78, blue: 1)]
            : Array(repeating: Color(red: 0.12, green: 0.36, blue: 1), count: 3)
    }

    private var narrowColors: [Color] {
        gtaMode ? [Color(red: 1, green: 0.52, blue: 0.78), Color(red: 0.84, green: 0.7, blue: 1), Color(red: 0.58, green: 0.88, blue: 1)]
            : [Color(red: 0.3, green: 0.55, blue: 1)]
    }

    private var stripColors: [Color] {
        gtaMode ? narrowColors : [Color(red: 0.45, green: 0.65, blue: 1)]
    }

    private func lights(_ s: CGFloat) -> some View {
        let f = g.frame, t = g.table
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 30 * s)
                .fill(LinearGradient(colors: wideColors, startPoint: .leading, endPoint: .trailing))
                .frame(width: (f.width + 40) * s, height: (f.height + 40) * s)
                .blur(radius: 46 * s)
                .offset(x: (f.minX - 20) * s, y: (f.minY - 20) * s)
            RoundedRectangle(cornerRadius: 10 * s)
                .fill(LinearGradient(colors: narrowColors + narrowColors, startPoint: .leading, endPoint: .trailing))
                .frame(width: (f.width + 10) * s, height: (f.height + 10) * s)
                .blur(radius: 12 * s)
                .offset(x: (f.minX - 5) * s, y: (f.minY - 5) * s)
            Capsule()
                .fill(LinearGradient(colors: wideColors, startPoint: .leading, endPoint: .trailing))
                .frame(width: (t.width - 60) * s, height: 40 * s)
                .blur(radius: 26 * s)
                .offset(x: (t.minX + 30) * s, y: (t.maxY - 14) * s)
            Capsule()
                .fill(LinearGradient(colors: stripColors + stripColors, startPoint: .leading, endPoint: .trailing))
                .frame(width: (t.width - 90) * s, height: max(1.5, 8 * s))
                .blur(radius: 4 * s)
                .offset(x: (t.minX + 45) * s, y: (t.maxY - 4) * s)
        }
        .opacity(plugged ? 1 : 0)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.8), value: plugged)
        .animation(.easeInOut(duration: 1.2), value: gtaMode)
        .allowsHitTesting(false)
    }

    private func socketGlow(_ s: CGFloat) -> some View {
        let c = point(g.socket, s)
        let base: CGFloat = 86
        return ZStack {
            RoundedRectangle(cornerRadius: 16 * s)
                .fill(Color(red: 0.3, green: 0.66, blue: 1))
                .frame(width: (base + 26) * s, height: (base + 26) * s)
                .blur(radius: 18 * s)
                .opacity(reduceMotion ? 0.95 : (socketPulse ? 0.95 : 0.3))
            RoundedRectangle(cornerRadius: 12 * s)
                .fill(Color(red: 0.62, green: 0.84, blue: 1))
                .frame(width: (base + 8) * s, height: (base + 8) * s)
                .blur(radius: 5 * s)
                .opacity(reduceMotion ? 1 : (socketPulse ? 1 : 0.45))
        }
        .position(c)
        .opacity(plugged ? 0 : 1)
        .animation(.easeOut(duration: 0.5), value: plugged)
        .allowsHitTesting(false)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.95).repeatForever(autoreverses: true)) { socketPulse = true }
        }
    }

    // MARK: TV ekranı

    private func tvScreen(_ s: CGFloat) -> some View {
        let r = g.screen
        let logicalWidth: CGFloat = 300
        let logicalHeight = logicalWidth * r.height / r.width
        let scale = r.width * s / logicalWidth
        return ZStack {
            Color.black
            Group {
                if !plugged {
                    TVStandby(downloads: introPending ? 0 : downloads)
                } else if !splashDone {
                    SplashView { withAnimation(.easeOut(duration: 0.4)) { splashDone = true } }
                        .frame(width: 1040, height: 586)
                        .scaleEffect(logicalWidth / 1040)
                        .frame(width: logicalWidth, height: logicalHeight)
                        .clipped()
                } else {
                    TVLive(streaming: streaming, line: line, source: source, problem: problem, badge: badge,
                           gtaMode: gtaMode, downloads: downloads)
                }
            }
            .frame(width: logicalWidth, height: logicalHeight)
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: r.width * s, height: r.height * s, alignment: .topLeading)
        }
        .frame(width: r.width * s, height: r.height * s)
        .clipped()
        .offset(x: r.minX * s, y: r.minY * s)
        .contentShape(Rectangle())
        .onTapGesture { if plugged && streaming { onOpenTV() } }
    }

    // MARK: Fiş ve kablo

    /// Büyütme: fiş görselde çok küçük kaldığı için.
    private func magnify(_ s: CGFloat) -> CGFloat { min(1.6, max(1, 0.3 / s)) }

    /// Fişin sahne pikselindeki yeri.
    private func plugPoint(_ s: CGFloat) -> CGPoint {
        let base = plugged && !dragging ? g.socket : g.hangingPlug
        guard dragging else { return base }
        return CGPoint(x: base.x + drag.width / s, y: base.y + drag.height / s)
    }

    /// Fişin dönüşü: uzakta dik sarkar, prize yaklaştıkça prize döner.
    private func plugAngle(_ s: CGFloat) -> Angle {
        let p = plugPoint(s)
        let big = hypot(g.hangingPlug.x - g.socket.x, g.hangingPlug.y - g.socket.y)
        let d = hypot(p.x - g.socket.x, p.y - g.socket.y)
        guard big > 120, d > 1 else { return .zero }
        var t = (big - d) / (big - 120)
        t = min(1, max(0, t))
        let eased = t * t * (3 - 2 * t)
        // Fişten prize olan yönün dikeyden (yukarı) açısı.
        let angle = atan2(g.socket.x - p.x, -(g.socket.y - p.y))
        return .radians(Double(eased * angle))
    }

    private func cable(_ s: CGFloat) -> some View {
        let k = magnify(s)
        let path = Path { p in
            let points = g.cablePath.isEmpty ? [g.cableStart] : g.cablePath
            p.move(to: point(points[0], s))
            for q in points.dropFirst() { p.addLine(to: point(q, s)) }
            let start = points.last!
            let dir = g.exitDirection
            if plugged && !dragging {
                let end = CGPoint(x: g.socket.x, y: g.socket.y + 30)
                p.addCurve(to: point(end, s),
                           control1: point(CGPoint(x: start.x + dir.dx * 90, y: start.y + dir.dy * 90), s),
                           control2: point(CGPoint(x: end.x + 10, y: end.y + 170), s))
            } else {
                let pp = plugPoint(s)
                let a = plugAngle(s).radians
                let tip = CGVector(dx: -sin(a), dy: cos(a))
                let back = CGPoint(x: pp.x - tip.dx * 40 * k, y: pp.y - tip.dy * 40 * k)
                let sag = max(0, 330 - hypot(back.x - start.x, back.y - start.y)) * 0.45
                p.addCurve(to: point(back, s),
                           control1: point(CGPoint(x: start.x + dir.dx * 70, y: start.y + dir.dy * 70 + sag), s),
                           control2: point(CGPoint(x: back.x - tip.dx * 80, y: back.y - tip.dy * 80 + sag), s))
            }
        }
        return ZStack(alignment: .topLeading) {
            path.stroke(Color(white: 0.06), style: StrokeStyle(lineWidth: max(1.8, 8 * s), lineCap: .round, lineJoin: .round))
                .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
            if g.cablePath.isEmpty {
                RoundedRectangle(cornerRadius: 3 * s)
                    .fill(Color(white: 0.08))
                    .frame(width: 14 * s, height: 12 * s)
                    .position(point(g.cableStart, s))
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder private func plug(_ s: CGFloat) -> some View {
        let k = s * magnify(s)
        let p = point(plugPoint(s), s)
        if plugged && !dragging {
            Circle()
                .fill(LinearGradient(colors: [Color(white: 0.24), Color(white: 0.04)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                .frame(width: 58 * k, height: 58 * k)
                .shadow(color: .black.opacity(0.45), radius: 3, y: 2)
                .position(p)
                .allowsHitTesting(false)
        } else {
            VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 5 * k).fill(Color(white: 0.06)).frame(width: 13 * k, height: 14 * k)
                RoundedRectangle(cornerRadius: 9 * k)
                    .fill(LinearGradient(colors: [Color(white: 0.22), Color(white: 0.04)], startPoint: .leading, endPoint: .trailing))
                    .overlay(RoundedRectangle(cornerRadius: 9 * k).strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5))
                    .frame(width: 36 * k, height: 50 * k)
                HStack(spacing: 14 * k) {
                    ForEach(0..<2, id: \.self) { _ in
                        Capsule()
                            .fill(LinearGradient(colors: [Color(white: 0.92), Color(white: 0.6)], startPoint: .leading, endPoint: .trailing))
                            .frame(width: 6 * k, height: 24 * k)
                    }
                }
            }
            .rotationEffect(plugAngle(s))
            .scaleEffect(dragging ? 1.1 : 1)
            .shadow(color: .black.opacity(0.3), radius: 2, y: 1.5)
            .position(p)
            .allowsHitTesting(false)
        }
    }

    private func hitArea(at p: CGPoint, size: CGFloat) -> some View {
        Color.clear
            .frame(width: size, height: size)
            .contentShape(Rectangle())
            .position(p)
    }

    private func plugHandle(_ s: CGFloat) -> some View {
        let base = point(plugged ? g.socket : g.hangingPlug, s)
        return Color.clear
            .frame(width: 60, height: 60)
            .contentShape(Rectangle())
            .position(x: base.x + (dragging ? drag.width : 0), y: base.y + (dragging ? drag.height : 0))
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { v in
                        dragging = true
                        drag = v.translation
                    }
                    .onEnded { v in
                        let base = plugged ? g.socket : g.hangingPlug
                        let end = CGPoint(x: base.x + v.translation.width / s, y: base.y + v.translation.height / s)
                        let inSocket = hypot(end.x - g.socket.x, end.y - g.socket.y) < 160
                        withAnimation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.75)) {
                            dragging = false
                            drag = .zero
                        }
                        if inSocket != plugged { haptic(); onToggle() }
                    }
            )
            .simultaneousGesture(TapGesture().onEnded { haptic(); onToggle() })
    }
}

/// Fiş takılı değilken TV: siyah, ortada ipucu.
private struct TVStandby: View {
    let downloads: Int

    var body: some View {
        let text = L("scene.plug").uppercased(with: Loc.locale)
        ZStack(alignment: .topTrailing) {
            Color.black
            Text(text)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .tracking(TextDirection.isArabic(text) ? 0 : 1.5)
                .foregroundStyle(.white.opacity(0.45))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if downloads > 0 {
                DownloadCounter(total: downloads, counting: false).padding(12)
            }
        }
    }
}

/// Fiş takılıyken TV: rozet, sayaç, altyazı ya da durum.
private struct TVLive: View {
    let streaming: Bool
    let line: String?
    let source: String?
    let problem: String?
    let badge: String
    let gtaMode: Bool
    let downloads: Int

    var body: some View {
        ZStack {
            if gtaMode {
                SunsetBackdrop().transition(.opacity)
            } else {
                LinearGradient(colors: [Color(red: 0.09, green: 0.12, blue: 0.24), Color(red: 0.15, green: 0.09, blue: 0.18)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            VStack(spacing: 0) {
                HStack(alignment: .top) {
                    HStack(spacing: 5) {
                        Circle().fill(Color(rgb: 0xE5162B)).frame(width: 6, height: 6)
                        Text(badge)
                            .font(.system(size: 9, weight: .bold))
                            .tracking(TextDirection.isArabic(badge) ? 0 : 1)
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 18)
                    .background(Capsule().fill(Color.black.opacity(0.4)))
                    Spacer(minLength: 0)
                    if downloads > 0 { DownloadCounter(total: downloads, counting: true) }
                }
                Spacer(minLength: 0)
                bottom.padding(.bottom, 4)
            }
            .padding(12)
        }
        .animation(.easeOut(duration: 0.3), value: line)
        .animation(.easeOut(duration: 0.3), value: gtaMode)
    }

    @ViewBuilder private var bottom: some View {
        if let problem {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(problem).foregroundStyle(.white.opacity(0.9))
                    .lineLimit(5).minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.system(size: 11, weight: .medium))
        } else if !streaming {
            Text(L("home.stage.connecting")).font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.7))
        } else if let line, !line.isEmpty {
            VStack(spacing: 3) {
                if let source {
                    Text(verbatim: source).font(.system(size: 9)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                }
                Text(verbatim: TextDirection.prepared(line))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.black.opacity(0.62)))
                    .subtitleDirection(for: line)
            }
            .id(line)
            .transition(.opacity.combined(with: .offset(y: 5)))
        } else {
            Text(L("home.stage.waiting")).font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.55))
        }
    }
}

/// GTA 6 kipinin gün batımı fonu.
struct SunsetBackdrop: View {
    var body: some View {
        LinearGradient(stops: [
            .init(color: Color(red: 0.10, green: 0.08, blue: 0.34), location: 0),
            .init(color: Color(red: 0.46, green: 0.16, blue: 0.62), location: 0.40),
            .init(color: Color(red: 0.93, green: 0.29, blue: 0.60), location: 0.74),
            .init(color: Color(red: 1.00, green: 0.55, blue: 0.48), location: 1),
        ], startPoint: .top, endPoint: .bottom)
        .overlay(Color.black.opacity(0.28))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Oyunlardaki para göstergesi gibi "Toplam indirme".
struct DownloadCounter: View {
    let total: Int
    let counting: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = 0
    @State private var hit = false

    private var arabic: Bool { Languages.isRightToLeft(Loc.language) }

    var body: some View {
        VStack(alignment: .trailing, spacing: 1) {
            outlined(Text(L("scene.downloads").uppercased(with: Loc.locale))
                .font(.custom("Impact", size: 7.5).weight(.black))
                .tracking(arabic ? 0 : 0.6), width: 0.6)
            outlined(Text(shown.formatted(.number.locale(Loc.locale)))
                .font(.custom("Impact", size: 18).weight(.black).monospacedDigit()), width: 1, color: Color(red: 0.48, green: 0.91, blue: 0.48))
                .scaleEffect(hit ? 1.32 : 1, anchor: .trailing)
                .shadow(color: Color(red: 0.48, green: 0.91, blue: 0.48).opacity(hit ? 1 : 0), radius: 9)
        }
        .transformEffect(arabic ? .identity : CGAffineTransform(a: 1, b: 0, c: -0.12, d: 1, tx: 2, ty: 0))
        .task(id: total) { await count() }
    }

    private func outlined(_ text: Text, width w: CGFloat, color: Color = .white) -> some View {
        ZStack {
            ForEach([CGSize(width: w, height: 0), CGSize(width: -w, height: 0), CGSize(width: 0, height: w), CGSize(width: 0, height: -w)], id: \.width) { o in
                text.foregroundStyle(.black).offset(o)
            }
            text.foregroundStyle(.black.opacity(0.9)).offset(y: w + 0.5)
            text.foregroundStyle(color)
        }
    }

    private func count() async {
        guard counting, !reduceMotion, total > 3 else { shown = total; return }
        shown = 0
        for i in 1...3 {
            try? await Task.sleep(for: .milliseconds(280))
            shown = i
        }
        let start = Date()
        while true {
            let p = min(1, Date().timeIntervalSince(start) / 1.55)
            shown = max(3, Int(Double(total) * pow(p, 2.6)))
            if p >= 1 { break }
            try? await Task.sleep(for: .milliseconds(16))
        }
        shown = total
        withAnimation(.spring(response: 0.22, dampingFraction: 0.45)) { hit = true }
        try? await Task.sleep(for: .milliseconds(260))
        withAnimation(.spring(response: 0.45, dampingFraction: 0.6)) { hit = false }
    }
}
