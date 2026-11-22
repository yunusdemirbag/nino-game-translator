// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import SwiftUI

// Cam yüzey (tasarim-dili.md §6) ve pencere zemini (§7).

public extension EnvironmentValues {
    /// Ekran görüntüsü üretirken açılır: sistem camı, malzemeler, kaydırma alanı, dönen gösterge gibi
    /// ImageRenderer'ın çizemediği şeyler düz şekillerle çizilir; animasyon ve açılış gösterileri atlanır
    /// (her görünüm ilk anda son hâlindedir).
    @Entry var ninoStaticRendering: Bool = false
}

/// Cam yüzey: cam dolgusu + macOS 26'da Liquid Glass (eskilerde en ince buzlu malzeme) + isteğe bağlı 1 pt kenar.
public struct NinoGlassModifier<S: InsettableShape>: ViewModifier {
    public var shape: S
    public var interactive: Bool
    public var edge: Bool
    @Environment(\.ninoStaticRendering) private var isStatic

    public init(shape: S, interactive: Bool = false, edge: Bool = true) {
        self.shape = shape
        self.interactive = interactive
        self.edge = edge
    }

    public func body(content: Content) -> some View {
        glass(content)
            .background(shape.fill(NinoColor.glassFill))
            .overlay {
                if edge { shape.strokeBorder(NinoColor.glassEdge, lineWidth: 1).allowsHitTesting(false) }
            }
    }

    @ViewBuilder
    private func glass(_ content: Content) -> some View {
        if isStatic {
            content
        } else if #available(macOS 26.0, *) {
            content.glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            content.background(shape.fill(.ultraThinMaterial))
        }
    }
}

public extension View {
    /// Cam zemin. `interactive`: tıklanabilir yüzeylerde sistemin basma tepkisi (macOS 26+).
    func ninoGlass<S: InsettableShape>(in shape: S, interactive: Bool = false, edge: Bool = true) -> some View {
        modifier(NinoGlassModifier(shape: shape, interactive: interactive, edge: edge))
    }

    /// Köşesi verilen sürekli yuvarlak dikdörtgen biçiminde cam zemin.
    func ninoGlass(cornerRadius: CGFloat, interactive: Bool = false, edge: Bool = true) -> some View {
        ninoGlass(in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous), interactive: interactive,
                  edge: edge)
    }
}

/// Bütün pencerelerin ve sayfaların zemini (§7): degrade + iki hareketli ışık.
/// Pencerenin kenarlarına kadar uzanır (başlık çubuğunun altı dahil).
public struct NinoWindowBackground: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.ninoStaticRendering) private var isStatic
    @State private var drifted = false

    public init() {}

    public var body: some View {
        let dark = scheme == .dark
        GeometryReader { proxy in
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            ZStack {
                LinearGradient(
                    colors: dark
                        ? [NinoRGB(0.02, 0.04, 0.10).color, NinoRGB(0.04, 0.09, 0.22).color]
                        : [NinoRGB(0.97, 0.98, 1.00).color, NinoRGB(0.89, 0.93, 0.99).color],
                    startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle()
                    .fill(NinoRGB(0.00, 0.44, 0.82).color(opacity: dark ? 0.35 : 0.22))
                    .frame(width: 520, height: 520)
                    .blur(radius: 120)
                    .position(x: center.x + (drifted ? -260 : -200), y: center.y + (drifted ? -220 : -170))
                Circle()
                    .fill(NinoRGB(0.00, 0.13, 0.36).color(opacity: dark ? 0.55 : 0.16))
                    .frame(width: 600, height: 600)
                    .blur(radius: 140)
                    .position(x: center.x + (drifted ? 300 : 240), y: center.y + (drifted ? 260 : 210))
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion, !isStatic else { return }
            withAnimation(.easeInOut(duration: 9).repeatForever(autoreverses: true)) { drifted = true }
        }
    }
}

public extension View {
    /// Uygulama zemini + varsayılan yazı (body, textPrimary) ve işaret rengi (accentText).
    func ninoScreen() -> some View {
        self
            .font(.nino(.body))
            .foregroundStyle(NinoColor.textPrimary)
            .tint(NinoColor.accentText)
            .background(NinoWindowBackground())
    }
}
