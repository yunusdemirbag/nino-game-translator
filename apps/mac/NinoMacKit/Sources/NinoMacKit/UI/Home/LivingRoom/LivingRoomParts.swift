// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import SwiftUI

// Salonun çizilen parçaları: LED ışıkları (§4.6), priz ışığı (§4.7), kablo ve fiş (§4.8).
// Hepsi tuval koordinatında, 1672×941'lik bir ZStack içinde çizilir.

// MARK: - LED ışıkları (§4.6)

struct LEDLights: View {
    let geometry: LivingRoomGeometry
    let lit: Bool
    /// Havuz öncelikli oyun tanındı (GTA renkleri).
    let poolGame: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var wide: [Color] {
        poolGame
            ? [NinoRGB(1.0, 0.24, 0.62).color, NinoRGB(0.74, 0.50, 0.96).color, NinoRGB(0.30, 0.78, 1.0).color]
            : Array(repeating: NinoRGB(0.12, 0.36, 1.0).color, count: 3)
    }

    private var narrow: [Color] {
        poolGame
            ? [NinoRGB(1.0, 0.52, 0.78).color, NinoRGB(0.84, 0.70, 1.0).color, NinoRGB(0.58, 0.88, 1.0).color]
            : Array(repeating: NinoRGB(0.3, 0.55, 1.0).color, count: 3)
    }

    private var strip: [Color] {
        poolGame ? narrow : Array(repeating: NinoRGB(0.45, 0.65, 1.0).color, count: 3)
    }

    var body: some View {
        let frame = geometry.tvFrame
        let cabinet = geometry.cabinet
        ZStack(alignment: .topLeading) {
            light(RoundedRectangle(cornerRadius: 30, style: .continuous), wide,
                  rect: frame.insetBy(dx: -20, dy: -20), blur: 46)
            light(RoundedRectangle(cornerRadius: 10, style: .continuous), narrow,
                  rect: frame.insetBy(dx: -5, dy: -5), blur: 12)
            light(Capsule(), wide,
                  rect: CGRect(x: cabinet.minX + 30, y: cabinet.maxY - 14, width: cabinet.width - 60, height: 40),
                  blur: 26)
            light(Capsule(), strip,
                  rect: CGRect(x: cabinet.minX + 45, y: cabinet.maxY - 4, width: cabinet.width - 90, height: 8),
                  blur: 4)
        }
        .frame(width: LivingRoomGeometry.canvas.width, height: LivingRoomGeometry.canvas.height, alignment: .topLeading)
        .opacity(lit ? 1 : 0)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.8), value: lit)
        .animation(reduceMotion ? nil : .easeInOut(duration: 1.2), value: poolGame)
        .allowsHitTesting(false)
    }

    private func light<S: Shape>(_ shape: S, _ colors: [Color], rect: CGRect, blur: CGFloat) -> some View {
        shape
            .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
            .frame(width: rect.width, height: rect.height)
            .blur(radius: blur)
            .offset(x: rect.minX, y: rect.minY)
    }
}

// MARK: - Priz ışığı (§4.7)

struct SocketGlow: View {
    let center: CGPoint
    let visible: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.ninoStaticRendering) private var isStatic
    @State private var bright = false

    var body: some View {
        let steady = reduceMotion || isStatic
        let on = steady || bright
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(NinoRGB(0.30, 0.66, 1.0).color)
                .frame(width: 112, height: 112)
                .blur(radius: 18)
                .opacity(on ? 0.95 : 0.3)
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(NinoRGB(0.62, 0.84, 1.0).color)
                .frame(width: 94, height: 94)
                .blur(radius: 5)
                .opacity(on ? 1 : 0.45)
        }
        .position(center)
        .opacity(visible ? 1 : 0)
        .animation(.easeInOut(duration: 0.5), value: visible)
        .allowsHitTesting(false)
        .onAppear {
            guard !steady else { return }
            withAnimation(.easeInOut(duration: 0.95).repeatForever(autoreverses: true)) { bright = true }
        }
    }
}

// MARK: - Kablo (§4.8)

/// Kablo eğrisi; fişin yeri ve "oturmuşluk" (0 çıkık/sürükleniyor, 1 takılı) yay ile değişir.
struct CableShape: Shape {
    let geometry: LivingRoomGeometry
    var plug: CGPoint
    var seated: CGFloat

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, CGFloat> {
        get { AnimatablePair(AnimatablePair(plug.x, plug.y), seated) }
        set {
            plug = CGPoint(x: newValue.first.first, y: newValue.first.second)
            seated = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let loose = geometry.cableCurve(plug: plug, seated: false)
        let tight = geometry.cableCurve(plug: plug, seated: true)
        func mix(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
            CGPoint(x: a.x + (b.x - a.x) * seated, y: a.y + (b.y - a.y) * seated)
        }
        var path = Path()
        if let first = geometry.cableTail.first {
            path.move(to: first)
            for point in geometry.cableTail.dropFirst() { path.addLine(to: point) }
        } else {
            path.move(to: loose.start)
        }
        path.addCurve(to: mix(loose.end, tight.end), control1: mix(loose.control1, tight.control1),
                      control2: mix(loose.control2, tight.control2))
        return path
    }
}

struct CableView: View {
    let geometry: LivingRoomGeometry
    let plug: CGPoint
    let seated: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            CableShape(geometry: geometry, plug: plug, seated: seated ? 1 : 0)
                .stroke(Color(white: 0.06), style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
                .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
            if geometry.drawsCableHeadPlug {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color(white: 0.08))
                    .frame(width: 14, height: 12)
                    .position(geometry.cableHead)
            }
        }
        .frame(width: LivingRoomGeometry.canvas.width, height: LivingRoomGeometry.canvas.height)
        .allowsHitTesting(false)
    }
}

// MARK: - Fiş (§4.8)

struct PlugView: View {
    /// Takılı ve sürüklenmiyor: prizin önünde yuvarlak kapak.
    let seated: Bool
    let angle: Double
    let dragging: Bool

    var body: some View {
        ZStack {
            if seated {
                Circle()
                    .fill(LinearGradient(colors: [Color(white: 0.24), Color(white: 0.04)], startPoint: .topLeading,
                                         endPoint: .bottomTrailing))
                    .overlay(Circle().strokeBorder(.white.opacity(0.18), lineWidth: 1.5))
                    .frame(width: 58, height: 58)
                    .shadow(color: .black.opacity(0.45), radius: 6, y: 4)
                    .transition(.opacity)
            } else {
                loosePlug
                    .rotationEffect(.radians(angle))
                    .scaleEffect(dragging ? 1.08 : 1)
                    .transition(.opacity)
            }
        }
        .frame(width: 120, height: 140)
        .contentShape(Rectangle())
    }

    private var loosePlug: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color(white: 0.06))
                .frame(width: 13, height: 14)
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.22), Color(white: 0.04)], startPoint: .leading,
                                     endPoint: .trailing))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(.white.opacity(0.14), lineWidth: 1))
                .frame(width: 36, height: 50)
            HStack(spacing: 14) {
                prong
                prong
            }
        }
        .compositingGroup()
        .shadow(color: .black.opacity(0.3), radius: 4, y: 3)
    }

    private var prong: some View {
        Capsule()
            .fill(LinearGradient(colors: [Color(white: 0.92), Color(white: 0.60)], startPoint: .leading,
                                 endPoint: .trailing))
            .frame(width: 6, height: 24)
    }
}
