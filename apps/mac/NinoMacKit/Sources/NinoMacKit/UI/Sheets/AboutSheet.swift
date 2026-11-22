// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import AppKit
import SwiftUI

/// Hakkında içeriği: logo ve sürüm, geliştirici ve destek veren, güncelleme denetimi, kaynak kodu / ölçüm /
/// gizlilik, lisans ve telif, açık kaynak bileşenler ve marka uyarısı.
/// Menüden sayfa olarak (Kapat ile), Ayarlar › Nino Hakkında'dan Ayarlar'ın içinde bölüm olarak açılır.
public struct AboutContent: View {
    private let state: AppState
    @Environment(\.colorScheme) private var scheme
    @Environment(\.locale) private var locale

    public init(state: AppState) { self.state = state }

    private var version: AppVersionInfo { state.version }

    /// Herkese açık depo (AGPL-3.0) ve içindeki gizlilik metni.
    private static let repository = "https://github.com/yunusdemirbag/nino-game-translator"
    public static var sourceURL: URL { URL(string: repository)! }
    public static var privacyURL: URL { URL(string: repository + "/blob/main/PRIVACY.md")! }

    /// Kullanılan açık kaynak bileşenler ve lisansları (çevrilmez).
    public static let components: [(name: String, license: String)] = [
        ("chiaki-ng", "AGPL-3.0"),
        ("OpenSSL", "Apache-2.0"),
        ("json-c", "MIT"),
        ("libevent", "BSD-3-Clause"),
        ("miniupnpc", "BSD-3-Clause"),
        ("Sparkle", "MIT"),
        ("Barlow, Nunito", "SIL OFL 1.1"),
    ]

    /// Yalnız iki ad: rol anahtarı, simge, ad (adlar bütün dillerde aynı yazılır).
    static let people: [(roleKey: String, symbol: String, name: String)] = [
        ("sheets.about.role.developer", "hammer.fill", "Yunus Demirbağ"),
        ("sheets.about.role.supporters", "heart.fill", "M. Akif Demirbağ"),
    ]

    /// Lisans satırının sonundaki telif bildirimleri (çevrilmez; NOTICE).
    static let copyrights = ["Nino © 2026 Yunus Demirbağ.", "Chiaki © Florian Märkl and contributors."]

    /// "V4.1 (4.1.0)": kısa ad + parantez içinde tam sürüm.
    static func versionLine(_ version: AppVersionInfo) -> String { "\(version.short) (\(version.full))" }

    public var body: some View {
        VStack(spacing: NinoSpacing.l) {
            header
            peopleCard
            AboutUpdateCard(state: state)
            linksCard
            ShText("sheets.about.trademark")
                .font(.system(size: 11))
                .foregroundStyle(NinoColor.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Parçalar

    private var header: some View {
        VStack(spacing: NinoSpacing.s) {
            NinoLogo(size: 96)
                .shadow(color: NinoColor.accent.color(scheme).opacity(0.35), radius: 18)
            Text(verbatim: "Nino Game Translator")
                .font(.ninoRounded(30, weight: .bold))
            Text(verbatim: Self.versionLine(version))
                .font(.nino(.caption).monospacedDigit())
                .foregroundStyle(NinoColor.textSecondary)
        }
    }

    private var peopleCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(Self.people.enumerated()), id: \.offset) { index, person in
                if index > 0 {
                    Rectangle().fill(NinoColor.border.opacity(0.6)).frame(height: 1).padding(.leading, 52)
                }
                HStack(spacing: NinoSpacing.m) {
                    AboutBadge { Image(systemName: person.symbol).font(.system(size: 13, weight: .semibold)) }
                    ShText(person.roleKey).foregroundStyle(NinoColor.textSecondary)
                    Spacer(minLength: NinoSpacing.m)
                    Text(verbatim: person.name).fontWeight(.bold)
                }
                .font(.nino(.body))
                .padding(.horizontal, NinoSpacing.l)
                .frame(maxWidth: .infinity, minHeight: 50)
            }
        }
        .ninoGlass(cornerRadius: NinoRadius.card)
    }

    private var linksCard: some View {
        VStack(alignment: .leading, spacing: NinoSpacing.m) {
            linkButton("sheets.about.source", symbol: "chevron.left.forwardslash.chevron.right", url: Self.sourceURL)
            // Ölçüm: kapatma düğmesi yok (olcum.md); ne gönderildiği açıkça yazılır.
            ShText("sheets.about.telemetry")
                .font(.nino(.caption))
                .foregroundStyle(NinoColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            linkButton("sheets.about.privacy", symbol: "hand.raised", url: Self.privacyURL)
            Text(verbatim: ([SheetsText.string("sheets.about.license", locale)] + Self.copyrights).joined(separator: " "))
                .font(.system(size: 11))
                .foregroundStyle(NinoColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Divider().overlay(NinoColor.tileBorder)
            ShText("sheets.about.components")
                .font(.nino(.caption).weight(.semibold))
                .foregroundStyle(NinoColor.textSecondary)
            VStack(spacing: 6) {
                ForEach(Self.components, id: \.name) { item in
                    HStack {
                        Text(verbatim: item.name).font(.nino(.callout))
                        Spacer(minLength: NinoSpacing.m)
                        Text(verbatim: item.license)
                            .font(.nino(.caption).monospacedDigit())
                            .foregroundStyle(NinoColor.textSecondary)
                    }
                }
            }
        }
        .padding(NinoSpacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ninoGlass(cornerRadius: NinoRadius.card)
    }

    private func linkButton(_ key: String, symbol: String, url: URL) -> some View {
        Button { NSWorkspace.shared.open(url) } label: {
            Label { ShText(key) } icon: { Image(systemName: symbol) }
                .font(.nino(.callout).weight(.semibold))
                .foregroundStyle(NinoColor.accentText)
        }
        .buttonStyle(.plain)
        .help(url.absoluteString)
    }
}

/// Güncelleme denetimi: ana penceredeki "Güncellemelere bak" ile aynı eylem (`state.checkForUpdates`) ve durum
/// (`state.update`); yeni sürüm varsa ya da indiyse kurma düğmesi (`state.installUpdate`).
struct AboutUpdateCard: View {
    let state: AppState
    @Environment(\.locale) private var locale

    var body: some View {
        HStack(alignment: .center, spacing: NinoSpacing.m) {
            AboutBadge { Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 13, weight: .semibold)) }
            VStack(alignment: .leading, spacing: 4) {
                status
                if case let .downloading(_, progress?) = state.update {
                    ProgressView(value: min(max(progress, 0), 1)).progressViewStyle(.linear).tint(NinoColor.accent)
                }
            }
            Spacer(minLength: NinoSpacing.m)
            action
        }
        .font(.nino(.body))
        .padding(.horizontal, NinoSpacing.l)
        .frame(maxWidth: .infinity, minHeight: 58)
        .ninoGlass(cornerRadius: NinoRadius.card)
    }

    @ViewBuilder private var status: some View {
        switch state.update {
        case .idle:
            Text(verbatim: AboutContent.versionLine(state.version))
                .foregroundStyle(NinoColor.textSecondary)
                .monospacedDigit()
        case .checking:
            HStack(spacing: 6) {
                SheetSpinner()
                ShText("sheets.about.update.checking").foregroundStyle(NinoColor.textSecondary)
            }
        case .upToDate:
            Label { ShText("sheets.about.update.upToDate") } icon: {
                Image(systemName: NinoSymbol.okFill).foregroundStyle(NinoColor.success)
            }
        case .available(let version):
            Text(SheetsText.string("sheets.about.update.available %@", locale, version)).fontWeight(.semibold)
        case .downloading(let version, _):
            Text(SheetsText.string("sheets.about.update.downloading %@", locale, version))
                .foregroundStyle(NinoColor.textSecondary)
        case .readyToInstall(let version), .waitingForTranslationToStop(let version):
            Text(SheetsText.string("sheets.about.update.ready %@", locale, version)).fontWeight(.semibold)
        case .failed:
            Text(SheetsText.string("sheets.about.update.failed", locale))
                .foregroundStyle(NinoColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var action: some View {
        switch state.update {
        case .available:
            Button { state.installUpdate() } label: { ShText("sheets.about.update.install") }
                .buttonStyle(.nino(.primary))
        case .readyToInstall, .waitingForTranslationToStop:
            Button { state.installUpdate() } label: { ShText("sheets.about.update.restart") }
                .buttonStyle(.nino(.primary))
        case .downloading:
            EmptyView()
        case .idle, .checking, .upToDate, .failed:
            Button { state.checkForUpdates() } label: { ShText("sheets.about.update.check") }
                .buttonStyle(.nino(.secondary))
                .disabled(state.update == .checking)
        }
    }
}

/// Hakkında'nın simge zemini: açık vurgudan koyu laciverte geçen kare (köşe 8) ya da daire, içi beyaz.
private struct AboutBadge<Content: View>: View {
    var side: CGFloat = 28
    var round = false
    @ViewBuilder let content: () -> Content
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let fill = LinearGradient(colors: [NinoColor.accentHi.color(scheme), NinoFixedColor.deepNavy.color],
                                  startPoint: .top, endPoint: .bottom)
        content()
            .foregroundStyle(.white)
            .frame(width: side, height: side)
            .background {
                if round { Circle().fill(fill) } else { RoundedRectangle(cornerRadius: 8, style: .continuous).fill(fill) }
            }
            .accessibilityHidden(true)
    }
}

/// Menü çubuğu › About Nino: 520 pt sayfa; içerik kayar, Kapat altta sabit.
public struct AboutSheet: View {
    private let state: AppState

    public init(state: AppState) { self.state = state }

    /// Sayfanın boyu: Ayarlar sayfasıyla aynı (ana pencereden her yanda "screen" kadar küçük).
    static let height = SettingsView.size.height

    public var body: some View {
        VStack(spacing: 0) {
            SheetScroll {
                AboutContent(state: state)
                    .padding([.horizontal, .top], NinoSpacing.xxl)
                    .padding(.bottom, NinoSpacing.l)
            }
            .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .top)
            .clipped()
            Divider().overlay(NinoColor.tileBorder)
            Button {
                state.activeSheet = nil
            } label: {
                ShText("sheets.common.close").frame(minWidth: 120)
            }
            .buttonStyle(.nino(.primary, size: .large))
            .keyboardShortcut(.defaultAction)
            .padding(NinoSpacing.xl)
        }
        .frame(width: 520, height: Self.height)
        .ninoScreen()
    }
}
