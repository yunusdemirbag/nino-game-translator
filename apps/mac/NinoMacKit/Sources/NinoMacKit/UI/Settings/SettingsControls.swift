// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import AppKit
import SwiftUI

// Ayarlar penceresinin küçük parçaları (ayarlar.md §2–§3, §14a). Sistem denetimlerinin ekran görüntüsünde
// çizilemeyenleri (anahtar, metin alanı, ilerleme, kaydırma) ya düz şekillerle çizilir ya da
// `ninoStaticRendering` açıkken şekille değiştirilir.

// MARK: - Metinler

/// Ayarlar'ın metin tablosu (`Resources/Settings.xcstrings`).
enum SettingsText {
    static let table = "Settings"

    static func string(_ key: String, _ locale: Locale, _ arguments: CVarArg...) -> String {
        NinoL10n.string(key, table: table, language: NinoL10n.languageCode(for: locale), arguments: arguments)
    }
}

/// Ayarlar tablosundan metin görünümü.
struct SText: View {
    private let key: String
    private let arguments: [CVarArg]

    init(_ key: String, _ arguments: CVarArg...) {
        self.key = key
        self.arguments = arguments
    }

    var body: some View {
        NinoText(key, table: SettingsText.table, arguments: arguments)
    }
}

/// Ayarlar tablosundan ipucu.
struct SHint: View {
    private let key: String
    private let arguments: [CVarArg]
    @Environment(\.locale) private var locale

    init(_ key: String, _ arguments: CVarArg...) {
        self.key = key
        self.arguments = arguments
    }

    var body: some View {
        NinoHint(NinoL10n.string(key, table: SettingsText.table, language: NinoL10n.languageCode(for: locale),
                                 arguments: arguments))
    }
}

// MARK: - Anahtar (switch)

/// Vurgu renkli, şekillerle çizilen anahtar. Etiket varsa solda durur.
struct NinoSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        NinoSwitchBody(configuration: configuration)
    }
}

private struct NinoSwitchBody: View {
    let configuration: ToggleStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: NinoSpacing.m) {
            configuration.label
            Spacer(minLength: 0)
            knob
        }
        .contentShape(Rectangle())
        .onTapGesture { if isEnabled { configuration.isOn.toggle() } }
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(Text(verbatim: configuration.isOn ? "1" : "0"))
    }

    private var knob: some View {
        let on = configuration.isOn
        return ZStack(alignment: on ? .trailing : .leading) {
            Capsule()
                .fill(on ? AnyShapeStyle(NinoColor.accent) : AnyShapeStyle(NinoColor.surface2))
                .overlay(Capsule().strokeBorder(on ? Color.clear : NinoColor.border.color(scheme), lineWidth: 1))
            Circle()
                .fill(Color.white)
                .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
                .padding(2)
        }
        .frame(width: 40, height: 24)
        .animation(NinoMotion.spring(0.25, 0.8), value: on)
    }
}

/// Başlık solda, anahtar sağda (§14a; Sorun Bildir de kullanır). Başlık "headline" yazı.
public struct NinoToggleRow: View {
    private let title: String
    @Binding private var isOn: Bool

    public init(_ title: String, isOn: Binding<Bool>) {
        self.title = title
        _isOn = isOn
    }

    public var body: some View {
        Toggle(isOn: $isOn) {
            Text(title).font(.nino(.headline)).fixedSize(horizontal: false, vertical: true)
        }
        .toggleStyle(NinoSwitchStyle())
    }
}

/// Gövde yazılı küçük anahtar satırı (kart içindeki "Tıklamalar geçsin" gibi).
struct SettingsSwitch: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) { Text(title).fixedSize(horizontal: false, vertical: true) }
            .toggleStyle(NinoSwitchStyle())
    }
}

// MARK: - Metin alanları

/// Gizli ya da açık metin alanı. Ekran görüntüsünde yer tutucusuyla şekil olarak çizilir.
struct SettingsField: View {
    let placeholder: String
    @Binding var text: String
    var secure: Bool = false
    var monospaced: Bool = false
    var onSubmit: () -> Void = {}
    @Environment(\.ninoStaticRendering) private var isStatic

    var body: some View {
        Group {
            if isStatic {
                Text(text.isEmpty ? placeholder : (secure ? String(repeating: "•", count: text.count) : text))
                    .foregroundStyle(text.isEmpty ? NinoColor.textSecondary.opacity(0.7) : NinoColor.textPrimary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, NinoSpacing.l)
                    .frame(minHeight: 44)
                    .ninoGlass(cornerRadius: NinoRadius.control)
            } else if secure {
                SecureField(placeholder, text: $text).onSubmit(onSubmit).ninoTextField()
            } else {
                TextField(placeholder, text: $text).onSubmit(onSubmit).ninoTextField()
            }
        }
        .font(monospaced ? .system(size: 14, design: .monospaced) : .nino(.body))
    }
}

// MARK: - İlerleme ve bekleme

struct SettingsProgressBar: View {
    let value: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(NinoColor.surface2)
                Capsule().fill(NinoColor.accent).frame(width: proxy.size.width * min(1, max(0, value)))
            }
        }
        .frame(height: 6)
        .accessibilityValue(Text(verbatim: "\(Int(value * 100))%"))
    }
}

/// Küçük dönen gösterge; ekran görüntüsünde saat simgesi.
struct SettingsSpinner: View {
    @Environment(\.ninoStaticRendering) private var isStatic

    var body: some View {
        if isStatic {
            Image(systemName: "hourglass").font(.system(size: 12, weight: .semibold))
                .foregroundStyle(NinoColor.textSecondary)
        } else {
            ProgressView().controlSize(.small)
        }
    }
}

// MARK: - Kaydırma alanı

/// Kaydırma çubuğu gizli dikey alan. Ekran görüntüsünde düz yığın (üstten hizalı, taşan kesilir).
struct SettingsScroll<Content: View>: View {
    @ViewBuilder let content: Content
    @Environment(\.ninoStaticRendering) private var isStatic

    var body: some View {
        if isStatic {
            // Taşan içerik düzeni büyütmesin diye örtü olarak çizilir.
            Color.clear
                .overlay(alignment: .top) { content.fixedSize(horizontal: false, vertical: true) }
                .clipped()
        } else {
            ScrollView(.vertical) { content }
                .scrollIndicators(.hidden)
        }
    }
}

// MARK: - Satır parçaları

/// Küçük ikincil başlık ("Konsol", "Oyun görüntüsü nereden").
struct SettingsSmallHeader: View {
    let text: String
    var body: some View {
        Text(text).font(.nino(.caption)).foregroundStyle(NinoColor.textSecondary)
    }
}

/// Solda etiket, sağda açılır seçici.
struct SettingsPickerRow<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [(Value, String)]

    var body: some View {
        HStack(spacing: NinoSpacing.m) {
            Text(title).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: NinoSpacing.s)
            Picker(selection: $selection) {
                ForEach(options, id: \.0) { option in
                    Text(verbatim: option.1).tag(option.0)
                }
            } label: {
                Text(title)
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
        }
    }
}

/// Başlıklı kaydırıcı: üstte ad ve değer, altta uçlarında küçük yazılar olan kaydırıcı.
/// `onDragStart` sürüklemenin başında bir kez çağrılır (deneme altyazısı için).
struct SettingsSliderRow: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let minLabel: String
    let maxLabel: String
    var valueText: String? = nil
    var onDragStart: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer(minLength: 0)
                if let valueText {
                    Text(verbatim: valueText).font(.nino(.callout).monospacedDigit())
                        .foregroundStyle(NinoColor.textSecondary)
                }
            }
            HStack(spacing: NinoSpacing.s) {
                Text(minLabel).font(.nino(.callout)).foregroundStyle(NinoColor.textSecondary)
                Slider(value: Binding(get: { Double(value) }, set: { value = Int($0.rounded()) }),
                       in: Double(range.lowerBound)...Double(range.upperBound), step: 1) { editing in
                    if editing { onDragStart() }
                }
                .controlSize(.small)
                Text(maxLabel).font(.nino(.callout)).foregroundStyle(NinoColor.textSecondary)
            }
        }
    }
}

/// Açılır-kapanır grup: küçük ikincil etiket ve dönen ok.
struct SettingsDisclosure<Content: View>: View {
    let title: String
    @Binding var isExpanded: Bool
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: NinoSpacing.m) {
            Button {
                withAnimation(NinoMotion.spring(0.3, 0.85)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.forward")
                        .font(.system(size: 10, weight: .bold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    Text(title).font(.nino(.caption))
                }
                .foregroundStyle(NinoColor.textSecondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(Text(verbatim: isExpanded ? "1" : "0"))
            if isExpanded {
                content.transition(.opacity)
            }
        }
    }
}

/// Seçim dairesi: seçiliyse dolu iç daireli vurgu renkli, değilse boş ikincil renkli (18 pt).
struct SettingsRadio: View {
    let selected: Bool
    var body: some View {
        ZStack {
            Circle().strokeBorder(selected ? AnyShapeStyle(NinoColor.accent) : AnyShapeStyle(NinoColor.textSecondary),
                                  lineWidth: 1.5)
            if selected { Circle().fill(NinoColor.accent).padding(4.5) }
        }
        .frame(width: 18, height: 18)
        .accessibilityHidden(true)
    }
}

/// Bölümün renkli simge kutusu: listede 30 pt (geçişli), bölüm başında 40 pt (düz, gölgeli).
struct SettingsSectionIcon: View {
    let section: SettingsSection
    var large: Bool = false

    var body: some View {
        let size: CGFloat = large ? 40 : 30
        let shape = RoundedRectangle(cornerRadius: large ? 11 : 8, style: .continuous)
        let color = section.color
        Image(systemName: section.symbol)
            .font(.system(size: large ? 18 : 14, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background {
                if large {
                    shape.fill(color.color).shadow(color: color.color(opacity: 0.45), radius: 10, y: 4)
                } else {
                    shape.fill(LinearGradient(colors: [color.color(opacity: 0.85), color.color],
                                              startPoint: .top, endPoint: .bottom))
                }
            }
            .accessibilityHidden(true)
    }
}

/// Bölüm sayfasının ortak başı (§3): 40'lık renkli kare + 28 pt kalın yuvarlak ad.
struct SettingsSectionHeader: View {
    let section: SettingsSection

    var body: some View {
        HStack(spacing: NinoSpacing.m) {
            SettingsSectionIcon(section: section, large: true)
            SText(section.titleKey)
                .font(.ninoRounded(28, weight: .bold))
                .accessibilityAddTraits(.isHeader)
        }
    }
}

/// Seçilebilir karo (motor seçenekleri): seçiliyken vurgulu kenar.
struct SettingsChoiceTile<Content: View>: View {
    let selected: Bool
    let action: () -> Void
    @ViewBuilder let content: Content
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(NinoSpacing.m)
                .background {
                    NinoRadius.shape(NinoRadius.control)
                        .fill(selected ? AnyShapeStyle(NinoColor.accentSoft) : AnyShapeStyle(Color.clear))
                }
                .ninoGlass(cornerRadius: NinoRadius.control, edge: !selected)
                .overlay {
                    if selected {
                        NinoRadius.shape(NinoRadius.control).strokeBorder(NinoColor.accent, lineWidth: 1.5)
                    } else if hovering {
                        NinoRadius.shape(NinoRadius.control).strokeBorder(NinoColor.accent.opacity(0.4), lineWidth: 1)
                    }
                }
                .contentShape(NinoRadius.shape(NinoRadius.control))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Eş aralıklı, seçilebilir adres kutusu ve yanında Kopyala düğmesi (OBS).
struct SettingsCopyRow: View {
    let address: String
    @State private var copied = false
    @Environment(\.locale) private var locale

    var body: some View {
        HStack(spacing: NinoSpacing.s) {
            Text(verbatim: address)
                .font(.system(size: 13, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, NinoSpacing.m)
                .frame(maxWidth: .infinity, minHeight: NinoSize.buttonHeight, alignment: .leading)
                .background(NinoRadius.shape(NinoRadius.inner).fill(NinoColor.surface2))
            Button(SettingsText.string(copied ? "settings.obs.copied" : "settings.obs.copy", locale)) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(address, forType: .string)
                copied = true
            }
            .buttonStyle(.nino(.secondary))
        }
    }
}
