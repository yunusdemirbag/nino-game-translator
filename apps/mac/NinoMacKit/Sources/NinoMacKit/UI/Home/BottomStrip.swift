// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import SwiftUI

/// Alt şerit (ana-ekran.md §6): üç bölge. Solda görüntü kaynağı ve TV, ortada güncelleme, sağda çeviri bağlantısı.
/// Sol ve sağ bölge eşit esner, orta bölge tam ortada kalır; hiçbir öge ötekinin üstüne binmez.
/// Şeritte yalnız kısa durum yazar; uzun açıklama ögenin ipucundadır (ve TV sahnesinde).
struct BottomStrip: View {
    let state: AppState
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(NinoColor.glassEdge).frame(height: 1)
            HStack(spacing: 16) {
                HStack(spacing: 22) {
                    StatusItem(tone: HomeStatus.sourceTone(state), title: HomeStatus.sourceTitle(state, locale),
                               value: HomeStatus.sourceShortValue(state, locale),
                               help: HomeStatus.sourceValue(state, locale))
                        .layoutPriority(1)
                    if state.subtitlesOnTV { tvItem }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                UpdateCenter(state: state)
                    .frame(maxWidth: 300)
                translationLink
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, NinoSpacing.xl)
            .frame(height: 44)
        }
        .font(.nino(.caption))
    }

    @ViewBuilder private var tvItem: some View {
        if state.tvReady {
            // TV hazırken de tıklanır: TV kurulumunu açar (eski TV uygulamasını güncellemek dahil).
            let connected = state.connectedDisplays > 0
            let legacy: Bool = { if case .legacyApp = state.setup.tvApp { return true }; return false }()
            Button {
                state.openSetup(at: .tv)
            } label: {
                StatusItem(tone: legacy ? .warning : NinoStatusTone.tv(connected: state.connectedDisplays,
                                                                     translating: state.translation != .off),
                           title: "TV",
                           value: HomeText.string(legacy ? "home.short.tvUpdate"
                                                  : (connected ? "home.status.connected" : "home.short.tvWaiting"), locale)
                               + (legacy ? " ›" : ""),
                           help: HomeText.string(legacy ? "home.tv.updateHelp"
                                                 : (connected ? "home.status.connected" : "home.tv.waitingApp"), locale))
            }
            .buttonStyle(.plain)
        } else {
            Button {
                state.openSetup(at: .tv)
            } label: {
                StatusItem(tone: .warning, title: "TV", value: HomeText.string("home.short.tvSetUp", locale) + " ›",
                           help: HomeText.string("home.tv.connect", locale))
            }
            .buttonStyle(.plain)
        }
    }

    private var translationLink: some View {
        Button {
            state.open(.settingsTranslation)
        } label: {
            HStack(spacing: 5) {
                HText("home.translation").foregroundStyle(NinoColor.textSecondary)
                    .lineLimit(1)
                    .fixedSize()
                Text(HomeStatus.translationValue(state, locale))
                    .fontWeight(.semibold)
                    .foregroundStyle(NinoColor.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Image(systemName: NinoSymbol.chevron)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(NinoColor.textSecondary)
                    .padding(.leading, 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(HomeStatus.translationValue(state, locale))
    }
}

/// Alt şeritteki durum öğesi (§6.1): 7'lik nokta, yarı kalın başlık, ikincil değer.
struct StatusItem: View {
    let tone: NinoStatusTone
    let title: String
    let value: String
    /// Fareyle gelince görünen uzun açıklama.
    let help: String?

    var body: some View {
        HStack(spacing: 7) {
            NinoStatusDot(tone, size: 7)
            Text(title).fontWeight(.semibold).foregroundStyle(NinoColor.textPrimary)
                .lineLimit(1)
                .fixedSize()
            Text(value).foregroundStyle(NinoColor.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .font(.nino(.caption))
        .help(help ?? "")
        .accessibilityElement(children: .combine)
        .accessibilityHint(help ?? "")
    }
}

/// Alt şeridin ortasındaki güncelleme durumu (§6.3).
struct UpdateCenter: View {
    let state: AppState
    @Environment(\.locale) private var locale
    @Environment(\.ninoStaticRendering) private var isStatic

    var body: some View {
        switch state.update {
        case .readyToInstall, .waitingForTranslationToStop:
            pill(symbol: NinoSymbol.updateReady, text: HomeText.string("home.update.readyRestart", locale)) {
                state.installUpdate()
            }
        case .downloading(let version, _):
            HStack(spacing: 6) {
                if isStatic {
                    Image(systemName: "arrow.down").font(.system(size: 9, weight: .bold))
                } else {
                    ProgressView().controlSize(.mini)
                }
                Text(HomeText.string("home.update.downloading %@", locale, version)).lineLimit(1).truncationMode(.tail)
            }
            .font(.nino(.caption))
            .foregroundStyle(NinoColor.textSecondary)
        case .available(let version):
            pill(symbol: NinoSymbol.newVersion, text: HomeText.string("home.update.newVersion %@", locale, version)) {
                state.installUpdate()
            }
        case .idle, .checking, .upToDate, .failed:
            CheckForUpdates(state: state)
        }
    }

    private func pill(symbol: String, text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 11, weight: .bold))
                Text(text).font(.nino(.caption).weight(.semibold)).lineLimit(1).truncationMode(.tail)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Capsule().fill(NinoColor.accent))
        }
        .buttonStyle(.plain)
    }
}

private struct CheckForUpdates: View {
    let state: AppState
    @Environment(\.locale) private var locale
    @Environment(\.ninoStaticRendering) private var isStatic
    @State private var hovering = false
    @State private var spinning = false

    private var checking: Bool { state.update == .checking }

    var body: some View {
        HStack(spacing: 6) {
            Group {
                switch state.update {
                case .checking:
                    HText("home.update.checking")
                case .upToDate:
                    HStack(spacing: 5) {
                        Image(systemName: NinoSymbol.upToDate).font(.system(size: 10, weight: .bold))
                        HText("home.update.upToDate")
                    }
                default:
                    HText("home.update.check")
                }
            }
            .font(.nino(.caption))
            .foregroundStyle(NinoColor.textSecondary)
            .lineLimit(1)
            Button {
                state.checkForUpdates()
            } label: {
                Image(systemName: NinoSymbol.recheck)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(hovering ? NinoColor.textPrimary : NinoColor.textSecondary)
                    .rotationEffect(.degrees(spinning ? 360 : 0))
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(NinoColor.textSecondary.opacity(hovering ? 0.18 : 0.10)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(checking)
            .onHover { hovering = $0 }
            .help(HomeText.string("home.update.check", locale))
            .accessibilityLabel(HomeText.string("home.update.check", locale))
        }
        .onChange(of: checking, initial: true) { _, now in
            guard !isStatic else { return }
            if now {
                withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) { spinning = true }
            } else {
                withAnimation(.default) { spinning = false }
            }
        }
    }
}
