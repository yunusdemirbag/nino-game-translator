// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import AppKit
import SwiftUI

// Sihirbazın küçük ortak parçaları (kurulum.md §2 "Ortak küçük parçalar").

/// Küçük dönen gösterge. Ekran görüntüsünde ImageRenderer çizemediği için düz bir simge.
struct SetupSpinner: View {
    var tint: Color?
    @Environment(\.ninoStaticRendering) private var isStatic

    var body: some View {
        if isStatic {
            Image(systemName: "circle.dotted")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(tint.map { AnyShapeStyle($0) } ?? AnyShapeStyle(NinoColor.textSecondary))
                .frame(width: 16, height: 16)
        } else {
            ProgressView().controlSize(.small).tint(tint)
        }
    }
}

/// Gösterge + açıklama yazısı.
struct SetupWorkingRow: View {
    let text: String
    var body: some View {
        HStack(spacing: NinoSpacing.s) {
            SetupSpinner()
            Text(text)
                .font(.nino(.callout))
                .foregroundStyle(NinoColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Simgeli bağlantı düğmesi: açıklama yarı kalın, accentText.
struct SetupLink: View {
    let systemImage: String?
    let title: String
    var help: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title).multilineTextAlignment(.leading)
            }
            .font(.nino(.callout).weight(.semibold))
            .foregroundStyle(NinoColor.accentText)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help ?? "")
    }
}

/// Seçilebilir hata metni (ortalı ya da sola yaslı).
struct SetupErrorText: View {
    let text: String
    var centered = false

    var body: some View {
        Label {
            Text(text)
                .textSelection(.enabled)
                .multilineTextAlignment(centered ? .center : .leading)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: NinoSymbol.errorFill)
        }
        .font(.nino(.callout))
        .foregroundStyle(NinoColor.warning)
    }
}

/// Sıkı adım satırı: 26'lık degrade daire, 13 kalın beyaz rakam, gövde yazısı (§9).
struct SetupCompactStep: View {
    let number: Int
    let text: String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: NinoSpacing.m) {
            Text("\(number)")
                .font(.system(size: 13, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Circle().fill(NinoGradients.iconFill(scheme)))
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5 }
            Text(text).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

/// Simge + kısa not (açıklama küçük, textSecondary).
struct SetupNote: View {
    let systemImage: String
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: NinoSpacing.s) {
            Image(systemName: systemImage).frame(width: 18)
            Text(text).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(NinoColor.textSecondary)
    }
}

/// Sayfa noktaları: 7×7 kapsül, geçerli olan 24 genişliğe uzar; geçerli ve geçilmişler accent (§2).
struct SetupPageDots: View {
    let count: Int
    let current: Int
    @Environment(\.locale) private var locale

    var body: some View {
        HStack(spacing: 7) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index <= current ? AnyShapeStyle(NinoColor.accent)
                                           : AnyShapeStyle(NinoColor.textSecondary.opacity(0.3)))
                    .frame(width: index == current ? 24 : 7, height: 7)
            }
        }
        .animation(NinoMotion.spring(0.4, 0.8), value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(SetupText.string("setup.dots %lld %lld", locale, current + 1, count))
    }
}

/// İnce cam ayraç (güvence satırları arası).
struct SetupDivider: View {
    var body: some View {
        Rectangle().fill(NinoColor.border.opacity(0.4)).frame(height: 1)
    }
}

/// Satır içi cam hap (PS5 durumu).
struct SetupPill<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        content
            .font(.nino(.callout).weight(.semibold))
            .padding(.horizontal, NinoSpacing.l)
            .padding(.vertical, NinoSpacing.s)
            .background(Capsule().fill(Color.white.opacity(0.06)))
            .overlay(Capsule().strokeBorder(NinoColor.glassEdge, lineWidth: 1))
    }
}

/// Bağlantılar.
enum SetupLinks {
    static let remotePlay = URL(string: "https://remoteplay.dl.playstation.net/remoteplay/")!
    static let chiaki = URL(string: "https://github.com/chiaki-ng/chiaki-ng/releases/latest")!
    static let xboxCloud = URL(string: "https://www.xbox.com/play/consoles")!
    static let androidPhotoGuide =
        URL(string: "https://github.com/yunusdemirbag/nino-game-translator/blob/main/docs/KURULUM-ANDROID-TV.md")!
    static let tvAppGuide =
        URL(string: "https://github.com/yunusdemirbag/nino-game-translator/blob/main/docs/KURULUM.md#5-tv-uygulamas%C4%B1n%C4%B1-kurma")!
    static let geminiKey = URL(string: "https://aistudio.google.com/apikey")!
    static let microsoftLink = URL(string: "https://www.microsoft.com/link")!
    static let cameraSettings = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!
}

/// Çeviri dili seçenekleri: bayrak ve dilin kendi adı (çevrilmez).
enum SetupLanguages {
    static let all: [(code: String, flag: String, name: String)] = [
        ("tr", "🇹🇷", "Türkçe"), ("ar", "🇸🇦", "العربية"), ("hi", "🇮🇳", "हिन्दी"),
        ("id", "🇮🇩", "Bahasa Indonesia"), ("th", "🇹🇭", "ไทย"), ("vi", "🇻🇳", "Tiếng Việt"),
        ("ur", "🇵🇰", "اردو"), ("bn", "🇧🇩", "বাংলা"), ("ms", "🇲🇾", "Bahasa Melayu"),
        ("tl", "🇵🇭", "Filipino"), ("nl", "🇳🇱", "Nederlands"),
    ]

    static func entry(_ code: String) -> (code: String, flag: String, name: String) {
        all.first { $0.code == code } ?? all[0]
    }
}

/// Çeviri dili hap düğmesi (§3b): bayrak + dilin adı + aşağı ok; basınca bayraklı liste.
struct SetupLanguagePicker: View {
    let state: AppState
    @Environment(\.locale) private var locale
    @Environment(\.ninoStaticRendering) private var isStatic

    var body: some View {
        let title = SetupText.string("setup.language", locale)
        Group {
            if isStatic {
                label
            } else {
                Menu {
                    ForEach(SetupLanguages.all, id: \.code) { language in
                        Button {
                            state.settings.targetLanguage = language.code
                        } label: {
                            Text(verbatim: "\(language.flag)  \(language.name)"
                                 + (language.code == state.settings.targetLanguage ? "  ✓" : ""))
                        }
                    }
                } label: {
                    label
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
        .help(title)
        .accessibilityLabel(title)
    }

    private var label: some View {
        let current = SetupLanguages.entry(state.settings.targetLanguage)
        return HStack(spacing: 6) {
            Text(verbatim: current.flag).font(.system(size: 18))
            Text(verbatim: current.name).font(.nino(.callout).weight(.semibold))
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(NinoColor.textSecondary)
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(Capsule().fill(Color.white.opacity(0.08)))
        .overlay(Capsule().strokeBorder(NinoColor.accent.opacity(0.6), lineWidth: 1))
        .contentShape(Capsule())
    }
}
