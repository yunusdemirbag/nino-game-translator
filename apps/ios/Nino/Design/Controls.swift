// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import SwiftUI

// MARK: Başlıklar

/// Büyük ekran başlığı: isteğe bağlı adım satırı, 32 pt başlık, açıklama.
struct HeroTitle: View {
    var step: String? = nil
    let title: String
    var lead: String? = nil
    /// Kimlik başlığında 6, alt sayfa başlığında 4.
    var spacing: CGFloat = 6

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            if let step {
                Text(step).font(DS.Font.step).foregroundStyle(DS.Palette.accent)
            }
            Text(title)
                .font(DS.Font.heroTitle)
                .tracking(-0.5)
                .foregroundStyle(DS.Palette.text)
                .fixedSize(horizontal: false, vertical: true)
            if let lead {
                Text(lead)
                    .font(DS.Font.heroLead)
                    .foregroundStyle(DS.Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, spacing == 4 ? 2 : 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Alt sayfaların üst satırı: geri düğmesi, başlık, sağda isteğe bağlı öğe.
struct BackHeader<Trailing: View>: View {
    let title: String
    let onBack: () -> Void
    let trailing: Trailing

    init(_ title: String, onBack: @escaping () -> Void, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.onBack = onBack
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: DS.Space.gap) {
            SquareIconButton(symbol: "chevron.left", label: L("common.back"), action: onBack)
            Text(title).font(DS.Font.title).lineLimit(1).minimumScaleFactor(0.7)
            Spacer(minLength: 0)
            trailing
        }
        .frame(height: DS.Size.icon)
    }
}

extension BackHeader where Trailing == EmptyView {
    init(_ title: String, onBack: @escaping () -> Void) {
        self.init(title, onBack: onBack, trailing: { EmptyView() })
    }
}

// MARK: Simge düğmesi

/// 44×44 cam kare simge düğmesi.
struct SquareIconButton: View {
    let symbol: String
    let label: String
    var tint: Color = DS.Palette.text
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: DS.Size.icon, height: DS.Size.icon)
                .glassSquare()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }
}

/// Profil düğmesi: baş harfler ya da kişi simgesi.
struct ProfileButton: View {
    var initials: String = ""
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if initials.isEmpty {
                    Image(systemName: "person").font(.system(size: 17, weight: .semibold))
                } else {
                    Text(initials).font(.system(size: 13, weight: .semibold))
                }
            }
            .foregroundStyle(DS.Palette.text)
            .frame(width: DS.Size.icon, height: DS.Size.icon)
            .glassSquare()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(L("settings.profile")))
    }
}

extension View {
    fileprivate func glassSquare() -> some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
        return background(shape.fill(DS.Palette.surface))
            .overlay(shape.strokeBorder(DS.Palette.border, lineWidth: 1))
            .shadow(color: DS.Palette.pro.opacity(0.08), radius: 8, y: 3)
    }
}

// MARK: Düğmeler

/// Nino'nun kapsül düğmeleri.
struct PillButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, ghost, danger }
    var kind: Kind = .primary
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let label = configuration.label
            .font(DS.Font.headline)
            .lineLimit(1)
            .padding(.horizontal, kind == .ghost ? 12 : 20)
            .frame(maxWidth: kind == .ghost ? nil : .infinity)
            .frame(minHeight: kind == .ghost ? DS.Size.smallButton : DS.Size.button)
            .foregroundStyle(foreground)
            .background(background(pressed: pressed))
            .contentShape(Capsule())
        return label
            .scaleEffect(pressed ? 0.97 : 1)
            .opacity(isEnabled ? 1 : 0.4)
            .animation(.easeOut(duration: 0.12), value: pressed)
    }

    private var foreground: Color {
        switch kind {
        case .primary: .white
        case .secondary: DS.Palette.text
        case .ghost: DS.Palette.accentText
        case .danger: DS.Palette.danger
        }
    }

    @ViewBuilder private func background(pressed: Bool) -> some View {
        switch kind {
        case .primary:
            Capsule()
                .fill(LinearGradient(colors: [DS.Palette.primaryTop, DS.Palette.text], startPoint: .top, endPoint: .bottom))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
                .shadow(color: DS.Palette.text.opacity(0.28), radius: 14, y: 8)
                .opacity(pressed ? 0.85 : 1)
        case .secondary:
            Capsule().fill(Color.white.opacity(0.9))
                .overlay(Capsule().strokeBorder(DS.Palette.borderStrong, lineWidth: 1))
        case .ghost:
            Color.clear
        case .danger:
            Capsule().fill(DS.Palette.dangerSoft)
        }
    }
}

extension ButtonStyle where Self == PillButtonStyle {
    static var primary: PillButtonStyle { PillButtonStyle(kind: .primary) }
    static var secondary: PillButtonStyle { PillButtonStyle(kind: .secondary) }
    static var ghost: PillButtonStyle { PillButtonStyle(kind: .ghost) }
    static var danger: PillButtonStyle { PillButtonStyle(kind: .danger) }
}

/// "PS5'siz Deneyin": PS5 olmadan örnek altyazılı ana ekran.
struct TryWithoutPS5Button: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label { Text(L("demo.try")) } icon: { Image(systemName: "sparkles") }
                .minimumScaleFactor(0.75)
        }
        .buttonStyle(.ghost)
        .layoutPriority(1)
        .accessibilityIdentifier("tryWithoutPS5")
    }
}

// MARK: Seçiciler

/// 2–4 seçenekten birini seçtiren kutu.
struct SegmentPicker<Value: Hashable>: View {
    let options: [(value: Value, title: String)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: DS.Space.hair) {
            ForEach(options, id: \.value) { option in
                let selected = option.value == selection
                Button { selection = option.value } label: {
                    Text(option.title)
                        .font(.system(size: 15, weight: selected ? .semibold : .medium))
                        .foregroundStyle(selected ? DS.Palette.text : DS.Palette.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background { if selected { SelectedChip() } }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(DS.Space.hair)
        .background(RoundedRectangle(cornerRadius: DS.Radius.control).fill(DS.Palette.surface2))
        .sensoryFeedback(.selection, trigger: selection)
    }
}

/// Segment ve ızgaradaki seçili parçanın beyaz zemini.
struct SelectedChip: View {
    var body: some View {
        RoundedRectangle(cornerRadius: DS.Radius.inner)
            .fill(Color.white)
            .shadow(color: DS.Palette.pro.opacity(0.10), radius: 4, y: 2)
    }
}

/// Giriş alanı görünümü.
struct NinoFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
        return configuration
            .font(.system(size: 17))
            .foregroundStyle(DS.Palette.text)
            .padding(.horizontal, DS.Space.tile)
            .frame(minHeight: DS.Size.field)
            .background(shape.fill(Color.white.opacity(0.9)))
            .overlay(shape.strokeBorder(DS.Palette.borderStrong, lineWidth: 1))
    }
}
