// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import SwiftUI

/// Ana ekranın iskeleti (ana-ekran.md §3): başlık, geliştirici rozeti, orta alan, alt şerit.
public struct HomeView: View {
    private let state: AppState
    private let ui: HomeUIState

    public init(state: AppState, ui: HomeUIState) {
        self.state = state
        self.ui = ui
    }

    public var body: some View {
        VStack(spacing: 0) {
            HomeHeader(state: state)
                .padding(.horizontal, NinoSpacing.xl)
                .padding(.top, 12)
            if state.adminBadges {
                Text(verbatim: "Admin modu açık (debug)")
                    .font(.nino(.callout).weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.orange))
                    .padding(.top, 6)
            }
            HomeKeySuggestion(state: state)
            Group {
                switch state.settings.homeStyle {
                case .livingRoom: LivingRoomHome(state: state, ui: ui)
                case .toggle: ToggleHome(state: state, ui: ui)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            BottomStrip(state: state)
        }
        .overlay(alignment: .bottomTrailing) {
            // Admin: salon sahnesi yokken bileşik TV karesi küçük önizlemede.
            if state.adminMode, state.settings.homeStyle != .livingRoom, let preview = state.adminTVPreview {
                AdminTVPreviewImage(preview: preview, badge: state.adminBadges)
                    .frame(width: 320, height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(.trailing, NinoSpacing.xl)
                    .padding(.bottom, 64)
                    .allowsHitTesting(false)
            }
        }
        .task(id: "updates") { await periodicUpdateCheck() }
    }

    /// Ana ekran açık kaldıkça yarım saatte bir yeni sürüme bakılır (ağa çıkma sınırını motor tutar).
    private func periodicUpdateCheck() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(30 * 60))
            if Task.isCancelled { break }
            state.checkForUpdates()
        }
    }
}

/// Salonlu orta alan (§4.1). Kaydırılmaz; sahne kalan alana göre küçülür.
struct LivingRoomHome: View {
    let state: AppState
    let ui: HomeUIState

    var body: some View {
        VStack(spacing: 12) {
            UpdateBanner(state: state)
            LivingRoomScene(state: state, ui: ui)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            HomeActionButtons(state: state)
            HomeWarnings(state: state)
        }
        .padding(.horizontal, NinoSpacing.xl)
        .padding(.vertical, 12)
    }
}

// MARK: - Başlık (§3.1)

struct HomeHeader: View {
    let state: AppState
    @Environment(\.locale) private var locale

    var body: some View {
        HStack(spacing: 8) {
            NinoLogo(size: 46)
            VStack(alignment: .leading, spacing: 5) {
                NinoWordmark(size: 24)
                Text(verbatim: state.version.short)
                    .font(.ninoRounded(10, weight: .bold))
                    .foregroundStyle(NinoColor.textSecondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(NinoColor.textSecondary.opacity(0.12)))
                    .help("\(state.version.short) (\(state.version.full))")
                    .accessibilityLabel(HomeText.string("home.version %@", locale, state.version.full))
            }
            Spacer()
            NinoRoundIconButton(systemName: NinoSymbol.history, label: HomeText.string("home.history", locale)) {
                state.open(.history)
            }
            NinoRoundIconButton(systemName: NinoSymbol.settings, label: HomeText.string("home.settings", locale)) {
                state.open(.settings)
            }
            .disabled(!state.isSetupComplete)
        }
    }
}

// MARK: - Xbox ve "Altyazı Penceresini Ayarla" düğmeleri (§4.1 / §5.1)

struct HomeActionButtons: View {
    let state: AppState

    var body: some View {
        if state.settings.videoSource == .window, state.settings.gameConsole == .xbox, state.xboxStep != .ready {
            Button {
                state.open(.xbox)
            } label: {
                Label {
                    HText(state.xboxStep == .waitingForWindow ? "home.xbox.start" : "home.xbox.connect")
                } icon: {
                    Image(systemName: NinoSymbol.controllerFill)
                }
                .frame(minWidth: 220 - 2 * NinoSpacing.l)
            }
            .buttonStyle(.nino(.primary, size: .large))
        }
        if state.subtitlesOnComputer {
            Button {
                state.overlayAdjusting = true
            } label: {
                HText("home.overlay.adjust")
            }
            .buttonStyle(.nino(.ghost))
            .disabled(state.overlayAdjusting)
        }
    }
}

// MARK: - Yeni sürüm şeridi (§6.3)

struct UpdateBanner: View {
    let state: AppState

    var body: some View {
        if let version = newVersion {
            HStack(spacing: 12) {
                Image(systemName: NinoSymbol.newVersion)
                    .font(.system(size: 22))
                    .foregroundStyle(NinoColor.accent)
                VStack(alignment: .leading, spacing: 2) {
                    HText("home.update.bannerTitle").font(.nino(.callout).weight(.semibold))
                    Text(verbatim: "Nino \(version)").font(.nino(.caption)).foregroundStyle(NinoColor.textSecondary)
                }
                Spacer(minLength: 0)
                Button {
                    state.installUpdate()
                } label: {
                    HText("home.update.download")
                }
                .buttonStyle(.nino(.primary))
            }
            .padding(12)
            .frame(maxWidth: 640)
            .ninoGlass(cornerRadius: NinoRadius.card, edge: false)
        }
    }

    /// Yeni sürüm biliniyor ve henüz kurulmaya hazır değil.
    private var newVersion: String? {
        switch state.update {
        case .available(let version), .downloading(let version, _): return version
        default: return nil
        }
    }
}

// MARK: - Uyarılar (§8.2)

struct HomeWarnings: View {
    let state: AppState
    @Environment(\.locale) private var locale

    var body: some View {
        let cards = warnings
        if !cards.isEmpty {
            VStack(spacing: 12) {
                ForEach(cards) { card in
                    WarningCard(card: card)
                }
            }
            .frame(maxWidth: 640)
        }
    }

    private var warnings: [WarningCard.Model] {
        var list: [WarningCard.Model] = []
        let source = state.settings.sourceLanguage
        let target = state.settings.targetLanguage
        switch state.translator {
        case .ready:
            break
        case .languagePackMissing:
            list.append(.init(id: "pack", symbol: NinoSymbol.languagePack,
                              title: HomeText.string("home.warning.languagePack %@ %@", locale,
                                                     HomeStatus.languageName(source, locale),
                                                     HomeStatus.languageName(target, locale)),
                              hint: HomeText.string("home.warning.languagePackHint", locale),
                              button: HomeText.string("home.warning.openLanguageRegion", locale),
                              url: "x-apple.systempreferences:com.apple.Localization-Settings.extension"))
        case .unsupported(_, _, let systemHasTranslator):
            if !state.settings.onlineTranslation {
                list.append(.init(id: "unsupported", symbol: NinoSymbol.warning,
                                  title: HomeText.string("home.warning.unsupported %@ %@", locale,
                                                         HomeStatus.languageName(source, locale),
                                                         HomeStatus.languageName(target, locale)),
                                  hint: HomeText.string(systemHasTranslator ? "home.warning.unsupportedHint"
                                                        : "home.warning.needsMacOS26", locale)))
            }
        }
        if state.translation == .on, state.localNetworkBlocked {
            list.append(.init(id: "localNetwork", symbol: NinoSymbol.errorFill, title: nil,
                              hint: HomeText.string("home.warning.localNetwork", locale),
                              button: HomeText.string("home.warning.openSystemSettings", locale),
                              url: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork"))
        }
        if state.translation == .on, let problem = state.onlineEngineProblem {
            let description = HomeText.string(Self.problemKey(problem.kind), locale)
            list.append(.init(id: "engine", symbol: NinoSymbol.warning,
                              title: HomeText.string("home.warning.engineDown %@", locale,
                                                     HomeStatus.engineName(problem.engine)),
                              hint: description + " " + HomeText.string("home.warning.freeMeanwhile", locale)))
        }
        if let failure = state.textReadingFailure {
            let hint = failure.freeDiskGB < 10
                ? String(format: HomeText.string("home.warning.diskFull %.1f", locale), locale: locale,
                         failure.freeDiskGB)
                : HomeText.string("home.warning.restartMac", locale)
            list.append(.init(id: "reading", symbol: NinoSymbol.warning,
                              title: HomeText.string("home.warning.cantRead", locale), hint: hint))
        }
        return list
    }

    static func problemKey(_ kind: OnlineEngineProblem.Kind) -> String {
        switch kind {
        case .badKey: return "home.engineProblem.badKey"
        case .quota: return "home.engineProblem.quota"
        case .network: return "home.engineProblem.network"
        case .server: return "home.engineProblem.server"
        case .model: return "home.engineProblem.model"
        case .other: return "home.engineProblem.other"
        }
    }
}

struct WarningCard: View {
    struct Model: Identifiable {
        var id: String
        var symbol: String
        /// Başlık (body yarı kalın, warning). Yoksa ipucu başlık gibi çizilir (yerel ağ kartı).
        var title: String?
        var hint: String
        var button: String?
        var url: String?
    }

    let card: Model

    var body: some View {
        NinoCard {
            if let title = card.title {
                Label { Text(title).fixedSize(horizontal: false, vertical: true) } icon: {
                    Image(systemName: card.symbol)
                }
                .font(.nino(.body).weight(.semibold))
                .foregroundStyle(NinoColor.warning)
                NinoHint(card.hint)
            } else {
                Label { Text(card.hint).fixedSize(horizontal: false, vertical: true) } icon: {
                    Image(systemName: card.symbol)
                }
                .font(.nino(.callout).weight(.semibold))
                .foregroundStyle(NinoColor.warning)
            }
            if let button = card.button, let url = card.url.flatMap(URL.init(string:)) {
                Button(button) { NSWorkspace.shared.open(url) }
                    .buttonStyle(.nino(.secondary))
            }
        }
    }
}
