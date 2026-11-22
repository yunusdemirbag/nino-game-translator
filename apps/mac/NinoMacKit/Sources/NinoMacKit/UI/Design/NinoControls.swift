// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import SwiftUI

// Logo (§8.1), kelime işareti (§8.2), bölmeli seçici (§8.15), seçenek kartı (§8.16), kurulum adımı düzeni (§8.18).

// MARK: - Logo (§8.1)

/// `Logo` görseli, istenen boyda kareye yerleşir. Kenardaki parıltı payı için 1,21 kat büyük çizilir,
/// taşan saydam pay kesilmez. Ekran okuyucudan gizli.
public struct NinoLogo: View {
    private let size: CGFloat

    public init(size: CGFloat) { self.size = size }

    /// Görselin saydam kenarı: çizim kutudan %21 büyük açılır, kutuya kırpılır.
    static let artworkBleed: CGFloat = 1.21

    public var body: some View {
        NinoAsset.logo.image
            .interpolation(.high)
            .frame(width: size * Self.artworkBleed, height: size * Self.artworkBleed)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

// MARK: - Kelime işareti (§8.2)

/// "Nino" (S, kalın, yuvarlak) ve altında "GAME TRANSLATOR". Çevrilmez.
public struct NinoWordmark: View {
    private let size: CGFloat
    private let alignment: HorizontalAlignment

    /// Ekran okuyucunun okuduğu tam ad (çevrilmez).
    static let spokenName = "Nino Game Translator"

    public init(size: CGFloat, alignment: HorizontalAlignment = .leading) {
        self.size = size
        self.alignment = alignment
    }

    public var body: some View {
        VStack(alignment: alignment, spacing: size / 50) {
            Text(verbatim: "Nino")
                .font(.ninoRounded(size, weight: .bold))
                .foregroundStyle(NinoColor.textPrimary)
            Text(verbatim: "GAME TRANSLATOR")
                .font(.ninoRounded(max(8, size * 0.32), weight: .semibold))
                .tracking(size * 0.09)
                .foregroundStyle(NinoColor.textSecondary)
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.spokenName)
    }
}

// MARK: - Bölmeli seçici (§8.15)

/// Apple'ın segment denetimine benzer cam kapsül seçici.
///
///     NinoSegmentedPicker(selection: $output, options: [
///         .init(.tv, title: "TV", systemImage: NinoSymbol.outputTV), …])
public struct NinoSegmentedPicker<Value: Hashable>: View {
    public struct Option: Identifiable {
        public var value: Value
        public var title: String
        public var systemImage: String?
        public var id: Value { value }

        public init(_ value: Value, title: String, systemImage: String? = nil) {
            self.value = value
            self.title = title
            self.systemImage = systemImage
        }
    }

    @Binding private var selection: Value
    private let options: [Option]
    @Namespace private var namespace
    @Environment(\.colorScheme) private var scheme

    public init(selection: Binding<Value>, options: [Option]) {
        _selection = selection
        self.options = options
    }

    public var body: some View {
        HStack(spacing: 4) {
            ForEach(options) { option in
                segment(option)
            }
        }
        .padding(4)
        .ninoGlass(in: Capsule())
        .animation(NinoMotion.spring(0.35, 0.8), value: selection)
    }

    private func segment(_ option: Option) -> some View {
        let selected = option.value == selection
        return Button {
            selection = option.value
        } label: {
            HStack(spacing: 6) {
                if let systemImage = option.systemImage {
                    Image(systemName: systemImage).font(.system(size: 12, weight: .semibold))
                }
                Text(option.title)
                    .font(.nino(.callout).weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(selected ? AnyShapeStyle(Color.white) : AnyShapeStyle(NinoColor.textSecondary))
            .frame(maxWidth: .infinity, minHeight: 34)
            .padding(.horizontal, 8)
            .background {
                if selected {
                    Capsule()
                        .fill(NinoGradients.primaryFill(scheme))
                        .shadow(color: NinoColor.accent.color(scheme).opacity(0.4), radius: 8, y: 3)
                        .matchedGeometryEffect(id: "selection", in: namespace)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Seçenek kartı (§8.16)

/// Tıklanabilir satır karo: görsel (88×60) ya da 44'lük degrade simge, başlık + açıklama, sağda ok.
public struct NinoOptionCard: View {
    public enum Artwork {
        case asset(NinoAsset)
        case image(Image)
        case symbol(String)
    }

    private let artwork: Artwork
    private let title: String
    private let subtitle: String?
    private let action: () -> Void
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    public init(artwork: Artwork, title: String, subtitle: String? = nil, action: @escaping () -> Void) {
        self.artwork = artwork
        self.title = title
        self.subtitle = subtitle
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: NinoSpacing.l) {
                art
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.nino(.headline)).foregroundStyle(NinoColor.textPrimary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.nino(.callout))
                            .foregroundStyle(NinoColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: NinoSymbol.chevron)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(hovering ? NinoColor.accentText : NinoColor.textSecondary)
                    .offset(x: hovering ? 3 : 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .ninoTile(active: hovering)
            .contentShape(NinoRadius.shape(NinoRadius.card))
        }
        .buttonStyle(.plain)
        .scaleEffect(hovering ? 1.01 : 1)
        .opacity(isEnabled ? 1 : 0.5)
        .animation(NinoMotion.spring(0.3, 0.8), value: hovering)
        .onHover { hovering = $0 && isEnabled }
    }

    @ViewBuilder private var art: some View {
        switch artwork {
        case .asset(let asset):
            asset.image.aspectRatio(contentMode: .fit).frame(width: 88, height: 60)
        case .image(let image):
            image.resizable().aspectRatio(contentMode: .fit).frame(width: 88, height: 60)
        case .symbol(let name):
            NinoGradientIconBox(systemName: name, size: 44)
        }
    }
}

// MARK: - Kurulum adımı düzeni (§8.18)

/// Kurulum ekranlarının ortak düzeni: simge (56'lık degrade kutu ya da 84'lük logo), 26 pt başlık,
/// 14 pt açıklama (en çok 540), altında 8 boşlukla içerik. Simge yay ile belirir.
public struct NinoSetupStepLayout<Content: View>: View {
    public enum Icon {
        case symbol(String)
        case logo
    }

    private let icon: Icon
    private let title: String
    private let message: String?
    private let content: Content
    @State private var appeared = false
    @Environment(\.ninoStaticRendering) private var isStatic
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    public init(icon: Icon, title: String, message: String? = nil, @ViewBuilder content: () -> Content) {
        self.icon = icon
        self.title = title
        self.message = message
        self.content = content()
    }

    public var body: some View {
        let shown = appeared || isStatic || reduceMotion
        VStack(spacing: NinoSpacing.m) {
            iconView
                .scaleEffect(shown ? 1 : 0.7)
                .opacity(shown ? 1 : 0)
            Text(title)
                .font(.ninoRounded(26, weight: .bold))
                .multilineTextAlignment(.center)
            if let message {
                Text(message)
                    .font(.system(size: 14))
                    .foregroundStyle(NinoColor.textSecondary)
                    .lineSpacing(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 540)
                    .fixedSize(horizontal: false, vertical: true)
            }
            content.padding(.top, NinoSpacing.s)
        }
        .onAppear {
            withAnimation(NinoMotion.spring(0.55, 0.7)) { appeared = true }
        }
    }

    @ViewBuilder private var iconView: some View {
        switch icon {
        case .symbol(let name):
            NinoGradientIconBox(systemName: name, size: 56)
        case .logo:
            NinoLogo(size: 84).shadow(color: NinoColor.accent.color(scheme).opacity(0.45), radius: 24)
        }
    }
}
