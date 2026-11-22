// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import SwiftUI

// Düğmeler (tasarim-dili.md §8.3), metin alanı (§8.4), yuvarlak simge düğmesi (§8.17).
//
//   Button("…") { … }.buttonStyle(.nino(.primary))
//   Button("…") { … }.buttonStyle(.nino(.secondary, size: .large, fullWidth: true))
//   TextField("…", text: $x).ninoTextField()
//   NinoRoundIconButton(systemName: "gearshape.fill", label: "Ayarlar") { … }

public enum NinoButtonKind: Sendable { case primary, secondary, danger, ghost }

public enum NinoButtonSize: Sendable {
    /// 40
    case regular
    /// 44
    case large
    /// 52 (ana eylem)
    case hero

    public var minHeight: CGFloat {
        switch self {
        case .regular: return NinoSize.buttonHeight
        case .large: return NinoSize.buttonHeightLarge
        case .hero: return NinoSize.buttonHeightHero
        }
    }
}

public struct NinoButtonStyle: ButtonStyle {
    public var kind: NinoButtonKind
    public var size: NinoButtonSize
    public var fullWidth: Bool

    public init(_ kind: NinoButtonKind, size: NinoButtonSize = .regular, fullWidth: Bool = false) {
        self.kind = kind
        self.size = size
        self.fullWidth = fullWidth
    }

    public func makeBody(configuration: Configuration) -> some View {
        NinoButtonBody(configuration: configuration, kind: kind, size: size, fullWidth: fullWidth)
    }
}

public extension ButtonStyle where Self == NinoButtonStyle {
    static func nino(_ kind: NinoButtonKind, size: NinoButtonSize = .regular, fullWidth: Bool = false) -> NinoButtonStyle {
        NinoButtonStyle(kind, size: size, fullWidth: fullWidth)
    }
}

private struct NinoButtonBody: View {
    /// Birincil düğmenin üst kenar ışığı: yukarıda belirgin, aşağıda neredeyse yok.
    static let rimLight = LinearGradient(colors: [.white.opacity(0.45), .white.opacity(0.05)], startPoint: .top, endPoint: .bottom)
    let configuration: ButtonStyleConfiguration
    let kind: NinoButtonKind
    let size: NinoButtonSize
    let fullWidth: Bool
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var scheme

    private var shape: RoundedRectangle { NinoRadius.shape(NinoRadius.control) }
    private var pressed: Bool { configuration.isPressed }

    var body: some View {
        configuration.label
            .font(.nino(.button))
            .lineLimit(1)
            .foregroundStyle(foreground)
            .padding(.horizontal, kind == .ghost ? 12 : NinoSpacing.l)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: size.minHeight)
            .background { background }
            .contentShape(shape)
            .scaleEffect(pressed ? 0.97 : 1)
            .opacity(disabledOpacity)
            .animation(.easeOut(duration: 0.12), value: pressed)
    }

    private var foreground: NinoColor {
        switch kind {
        case .primary: return isEnabled ? .onAccent : .textSecondary
        case .secondary: return .textPrimary
        case .danger: return .danger
        case .ghost: return .accentText
        }
    }

    private var disabledOpacity: Double {
        guard !isEnabled else { return 1 }
        return kind == .primary ? 0.75 : 0.45
    }

    @ViewBuilder private var background: some View {
        switch kind {
        case .primary:
            if isEnabled {
                shape
                    .fill(LinearGradient(colors: [(pressed ? NinoColor.accentHi : NinoColor.accent).color(scheme),
                                                  NinoFixedColor.deepNavy.color],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(shape.strokeBorder(Self.rimLight, lineWidth: 1))
                    .shadow(color: NinoColor.accent.color(scheme).opacity(pressed ? 0.15 : 0.35), radius: 14, y: 6)
            } else {
                Color.clear.ninoGlass(in: shape)
            }
        case .secondary:
            Color.clear
                .ninoGlass(in: shape, interactive: true)
        case .danger:
            shape.fill(NinoColor.dangerSoft)
        case .ghost:
            Color.clear
        }
    }
}

// MARK: - Metin alanı (§8.4)

public extension View {
    /// Düz metin alanını Nino görünüşüne sokar: body yazı, 16 yatay iç boşluk, en az 44, cam, köşe 14.
    func ninoTextField() -> some View {
        self
            .textFieldStyle(.plain)
            .font(.nino(.body))
            .padding(.horizontal, NinoSpacing.l)
            .frame(minHeight: 44)
            .ninoGlass(cornerRadius: NinoRadius.control)
    }
}

// MARK: - Yuvarlak simge düğmesi (§8.17)

/// 36'lık cam daire içinde 14 pt simge. Üstüne gelince simge accentText, düğme %108.
public struct NinoRoundIconButton: View {
    private let systemName: String
    private let label: String
    private let action: () -> Void
    @State private var hovering = false

    /// - Parameter label: İpucu balonu ve ekran okuyucu etiketi (çevrilmiş).
    public init(systemName: String, label: String, action: @escaping () -> Void) {
        self.systemName = systemName
        self.label = label
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(hovering ? NinoColor.accentText : NinoColor.textPrimary)
                .frame(width: 36, height: 36)
                .ninoGlass(in: Circle(), interactive: true)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .scaleEffect(hovering ? 1.08 : 1)
        .animation(NinoMotion.spring(0.3, 0.7), value: hovering)
        .onHover { hovering = $0 }
        .help(label)
        .accessibilityLabel(label)
    }
}
