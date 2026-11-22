// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Observation
import SwiftUI

// Ayarlar penceresi (ayarlar.md §1–§3): üst satır, liste görünümü ve bölüm sayfaları.

/// Ayarlar'ın bölümleri, simgeleri ve renkleri (§2).
public enum SettingsSection: String, CaseIterable, Identifiable, Sendable {
    case connection, passcode, appearance, translation, obs, health, updates, askNino, report, about, reset
    case interface, language, packs, area

    public var id: String { rawValue }

    var titleKey: String { "settings.section.\(rawValue)" }

    var symbol: String {
        switch self {
        case .connection: return "cable.connector"
        case .passcode: return "lock"
        case .appearance: return "captions.bubble"
        case .translation: return "globe"
        case .obs: return "dot.radiowaves.left.and.right"
        case .health: return "waveform.path.ecg"
        case .updates: return "arrow.down.circle"
        case .askNino: return "bubble.left.and.text.bubble.right"
        case .report: return "exclamationmark.bubble"
        case .about: return "info.circle"
        case .reset: return "arrow.counterclockwise"
        case .interface: return "macwindow"
        case .language: return "character.bubble"
        case .packs: return "shippingbox"
        case .area: return "rectangle.dashed"
        }
    }

    var color: NinoRGB {
        switch self {
        case .connection: return NinoRGB(0.10, 0.45, 0.95)
        case .passcode: return NinoRGB(0.30, 0.35, 0.45)
        case .appearance: return NinoRGB(0.00, 0.44, 0.82)
        case .translation: return NinoRGB(0.00, 0.62, 0.75)
        case .obs: return NinoRGB(0.92, 0.26, 0.30)
        case .health: return NinoRGB(0.95, 0.30, 0.45)
        case .updates: return NinoRGB(0.12, 0.62, 0.36)
        case .askNino: return NinoRGB(0.00, 0.44, 0.82)
        case .report: return NinoRGB(0.96, 0.62, 0.12)
        case .about: return NinoRGB(0.45, 0.50, 0.60)
        case .reset: return NinoRGB(0.90, 0.30, 0.28)
        case .interface: return NinoRGB(0.36, 0.30, 0.95)
        case .language: return NinoRGB(0.20, 0.70, 0.40)
        case .packs: return NinoRGB(0.98, 0.55, 0.10)
        case .area: return NinoRGB(0.35, 0.40, 0.95)
        }
    }

    /// Listede görünmez (sayfası hazır); geri açmak için `false` döndürmek yeter.
    var isTuckedAway: Bool {
        switch self {
        case .interface, .language, .packs, .area: return true
        default: return false
        }
    }

    /// Listenin grupları (gizliler dahil sıra; gizliler süzülür).
    static let groups: [[SettingsSection]] = [
        [.connection, .passcode],
        [.appearance, .translation, .interface, .language, .packs, .area],
        [.obs],
        [.health, .updates, .askNino, .report, .about],
        [.reset],
    ]

    static var visibleGroups: [[SettingsSection]] {
        groups.compactMap { group in
            let shown = group.filter { !$0.isTuckedAway }
            return shown.isEmpty ? nil : shown
        }
    }

    /// Başka ajanın yazdığı sayfaya giden satırlar: bölüm açılmaz, o sayfa açılır.
    var externalSheet: Sheet? {
        switch self {
        case .health: return .health
        case .report: return .reportProblem
        default: return nil
        }
    }

    /// İçerik genişliği: Altyazı görünümü 900, diğerleri 640.
    var contentWidth: CGFloat { self == .appearance ? 900 : 640 }
}

/// Ayarlar penceresinin gezinme ve açılır grup durumu (ekran görüntüsü testleri de buradan kurar).
@MainActor
@Observable
public final class SettingsUIState {
    /// Açık bölüm; nil ise liste.
    public var section: SettingsSection?
    /// Çeviri › API anahtarları: açık sağlayıcı satırı (aynı anda bir tane; nil ise hepsi kapalı).
    public var openProvider: MacSettings.OnlineEngine?
    /// Yerel model › Sunucu ayarları.
    public var localAdvancedExpanded = false

    public init(section: SettingsSection? = nil) {
        self.section = section
    }

    func open(_ section: SettingsSection) {
        self.section = section
    }

    func back() {
        section = nil
    }
}

/// Ayarlar sayfası (sheet). `Sheet.settings` listeyle, `Sheet.settingsTranslation` Çeviri bölümüyle açılır.
@MainActor
public struct SettingsView: View {
    private let state: AppState
    @State private var ui: SettingsUIState
    private let size: CGSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Ana pencerenin boyundan her yanda "screen" boşluğu kadar küçük.
    public nonisolated static let size = CGSize(width: NinoSize.windowWidth - 2 * NinoSpacing.xl,
                                    height: NinoSize.windowHeight - 2 * NinoSpacing.xl)

    public init(state: AppState, ui: SettingsUIState? = nil) {
        self.init(state: state, ui: ui ?? SettingsUIState(), size: Self.size)
    }

    /// Ekran görüntüsü testleri uzun sayfaları kesmeden çizmek için boyu değiştirir.
    init(state: AppState, ui: SettingsUIState, size: CGSize) {
        self.state = state
        self.size = size
        _ui = State(initialValue: ui)
    }

    public init(state: AppState, initialSection: SettingsSection?) {
        self.init(state: state, ui: SettingsUIState(section: initialSection))
    }

    private var spring: Animation? { reduceMotion ? nil : NinoMotion.spring(0.4, 0.86) }

    public var body: some View {
        VStack(alignment: .leading, spacing: NinoSpacing.l) {
            topBar
            ZStack {
                if let section = ui.section {
                    page(section)
                        .id(section)
                        .transition(Self.pushTransition)
                } else {
                    page(nil)
                        .transition(Self.popTransition)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
        .padding(NinoSpacing.xl)
        .frame(width: size.width, height: size.height)
        .ninoScreen()
    }

    /// Bölüm sağdan kayarak ve belirerek gelir; liste sola kayarak gider.
    private static var pushTransition: AnyTransition {
        .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .trailing).combined(with: .opacity))
    }

    private static var popTransition: AnyTransition {
        .asymmetric(insertion: .move(edge: .leading).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity))
    }

    // MARK: Üst satır

    private var topBar: some View {
        HStack {
            if ui.section != nil {
                Button {
                    withAnimation(spring) { ui.back() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.backward").font(.system(size: 14, weight: .semibold))
                        SText("settings.back")
                    }
                    .font(.nino(.body).weight(.semibold))
                    .foregroundStyle(NinoColor.accentText)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut("[", modifiers: .command)
            } else {
                SText("settings.title")
                    .font(.ninoRounded(28, weight: .bold))
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer()
            Button {
                state.activeSheet = nil
            } label: {
                SText("settings.done")
            }
            .buttonStyle(.nino(.primary))
            .keyboardShortcut(.defaultAction)
        }
        .frame(minHeight: NinoSize.buttonHeight)
    }

    // MARK: Sayfalar

    @ViewBuilder
    private func page(_ section: SettingsSection?) -> some View {
        let width = section?.contentWidth ?? 640
        SettingsScroll {
            VStack(alignment: .leading, spacing: NinoSpacing.m) {
                if let section {
                    if section != .packs { SettingsSectionHeader(section: section) }
                    SettingsSectionContent(state: state, ui: ui, section: section)
                } else {
                    SettingsList(state: state) { open($0) }
                }
            }
            .frame(maxWidth: width, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.bottom, NinoSpacing.xl)
        }
    }

    private func open(_ section: SettingsSection) {
        if let sheet = section.externalSheet {
            state.open(sheet)
        } else if section == .askNino {
            // Ayarlar kapanır, kısa bir süre sonra sohbet açılır.
            state.activeSheet = nil
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(350))
                state.open(.askNino)
            }
        } else {
            withAnimation(spring) { ui.open(section) }
        }
    }
}

/// Bölümün içeriği.
struct SettingsSectionContent: View {
    let state: AppState
    let ui: SettingsUIState
    let section: SettingsSection

    var body: some View {
        switch section {
        case .connection:
            VStack(alignment: .leading, spacing: NinoSpacing.l) {
                ConnectionSettings(state: state, detailed: true)
                TVSettingsSection(state: state)
            }
        case .passcode: PasscodeSettings(state: state)
        case .appearance: AppearanceSettings(state: state)
        case .translation: TranslationSettings(state: state, ui: ui)
        case .obs: OBSSettings(state: state)
        case .updates: UpdatesSettings(state: state)
        case .askNino: AskNinoSettings(state: state)
        case .reset: ResetSettings(state: state)
        case .interface: InterfaceSettings(state: state)
        case .language: NinoCard { LanguageRows(state: state) }
        case .packs: GamePackSettings(state: state)
        case .area: SubtitleAreaSettings(state: state)
        // Hakkında Ayarlar'ın içinde bölüm olarak açılır: üstte "‹ Ayarlar" ve "Bitti" (menüden açılınca sayfadır).
        case .about: AboutContent(state: state).frame(maxWidth: 560).frame(maxWidth: .infinity)
        case .health, .report:
            // Bunlar ayrı sayfalardır (listeden açılır); buraya doğrudan gelinirse aynı sayfayı açan düğme.
            if let sheet = section.externalSheet {
                Button { state.open(sheet) } label: { SText(section.titleKey) }
                    .buttonStyle(.nino(.primary))
            }
        }
    }
}

// MARK: - Liste görünümü (§2)

struct SettingsList: View {
    let state: AppState
    let open: (SettingsSection) -> Void

    var body: some View {
        VStack(spacing: NinoSpacing.xl) {
            ForEach(Array(SettingsSection.visibleGroups.enumerated()), id: \.offset) { _, group in
                VStack(spacing: 0) {
                    ForEach(Array(group.enumerated()), id: \.element) { index, section in
                        if index > 0 {
                            Rectangle().fill(NinoColor.border.opacity(0.6)).frame(height: 1)
                                .padding(.leading, 58)
                        }
                        SettingsListRow(section: section) { open(section) }
                    }
                }
                .clipShape(NinoRadius.shape(NinoRadius.card))
                .ninoGlass(cornerRadius: NinoRadius.card)
            }
        }
    }
}

private struct SettingsListRow: View {
    let section: SettingsSection
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: NinoSpacing.m) {
                SettingsSectionIcon(section: section)
                SText(section.titleKey).foregroundStyle(NinoColor.textPrimary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.forward")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(NinoColor.textSecondary.opacity(0.7))
            }
            .padding(.horizontal, NinoSpacing.l)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(hovering ? NinoColor.accentSoft.opacity(0.6) : NinoColor.accentSoft.opacity(0))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

// MARK: - Nino'ya Sor (§11), Güncellemeler (§10), Sıfırla (§13)

struct AskNinoSettings: View {
    let state: AppState

    var body: some View {
        NinoCard {
            SHint("settings.ask.hint")
            Button {
                state.activeSheet = nil
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(350))
                    state.open(.askNino)
                }
            } label: {
                SText("settings.section.askNino")
            }
            .buttonStyle(.nino(.primary))
        }
    }
}

struct UpdatesSettings: View {
    let state: AppState
    @Environment(\.locale) private var locale

    var body: some View {
        NinoCard {
            HStack(spacing: NinoSpacing.m) {
                NinoLogo(size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: "Nino Game Translator").font(.nino(.headline))
                    Text(SettingsText.string("settings.updates.version %@", locale, state.version.full))
                        .font(.nino(.callout)).foregroundStyle(NinoColor.textSecondary)
                }
                Spacer(minLength: NinoSpacing.s)
                Button {
                    state.forceCheckForUpdates()
                } label: {
                    SText(state.update == .checking ? "settings.updates.checking" : "settings.updates.check")
                }
                .buttonStyle(.nino(.secondary))
                .disabled(state.update == .checking)
            }
            status
            SHint("settings.updates.auto")
        }
    }

    @ViewBuilder private var status: some View {
        switch state.update {
        case .available(let version), .readyToInstall(let version), .waitingForTranslationToStop(let version):
            VStack(alignment: .leading, spacing: NinoSpacing.s) {
                HStack(spacing: NinoSpacing.s) {
                    Image(systemName: "sparkles").foregroundStyle(NinoColor.accentText)
                    Text(SettingsText.string("settings.updates.ready %@", locale, version)).fontWeight(.bold)
                    Spacer(minLength: NinoSpacing.s)
                    Button { state.openReleaseNotes() } label: { SText("settings.updates.whatsNew") }
                        .buttonStyle(.nino(.secondary))
                    Button { state.installUpdate() } label: { SText("settings.updates.download") }
                        .buttonStyle(.nino(.primary))
                }
                SHint("settings.updates.installHint")
            }
        case .downloading(let version, let progress):
            VStack(alignment: .leading, spacing: NinoSpacing.s) {
                Text(SettingsText.string("settings.updates.downloading %@", locale, version))
                    .foregroundStyle(NinoColor.textSecondary)
                if let progress { SettingsProgressBar(value: progress) }
            }
        case .upToDate:
            NinoOKLabel(SettingsText.string("settings.updates.upToDate", locale))
        case .failed:
            NinoErrorLabel(SettingsText.string("settings.updates.failed", locale))
        case .idle, .checking:
            EmptyView()
        }
    }
}

struct ResetSettings: View {
    let state: AppState
    @State private var confirming = false
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: NinoSpacing.l) {
            SText("settings.reset.hint")
                .foregroundStyle(NinoColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: NinoSpacing.m) {
                Button { state.resetFromTV() } label: { SText("settings.reset.fromTV") }
                    .buttonStyle(.nino(.secondary))
                Button { confirming = true } label: { SText("settings.reset.everything") }
                    .buttonStyle(.nino(.danger))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ninoTile()
        .alert(SettingsText.string("settings.reset.confirmTitle", locale), isPresented: $confirming) {
            Button(SettingsText.string("settings.reset.everything", locale), role: .destructive) {
                state.resetEverything()
            }
            Button(SettingsText.string("settings.cancel", locale), role: .cancel) {}
        } message: {
            SText("settings.reset.confirmMessage")
        }
    }
}
