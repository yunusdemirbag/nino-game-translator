// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import SwiftUI

/// Ana ekranın anahtarsız çeviri önerileri (TranslationNudges.swift):
/// - paketsiz bir oyun tanındı ve çevrimiçi anahtar yok: küçük, kapatılabilir "Bu oyun için çeviri anahtarı ekle"
///   (tıklayınca Ayarlar › Çeviri; kapatılınca o oyunda bir daha çıkmaz),
/// - cihaz içi çevirinin dil paketi eksik: bir kez indirme önerisi (Sistem Ayarları › Genel › Dil ve Bölge ›
///   Çeviri Dilleri). Kalıcı "dil paketi" uyarı kartı ayrıca yerinde kalır.
struct HomeKeySuggestion: View {
    let state: AppState
    @Environment(\.locale) private var locale
    @State private var packOfferShown = false

    static let languageSettings = URL(string: "x-apple.systempreferences:com.apple.Localization-Settings.extension")!

    var body: some View {
        Group {
            if let game = state.keySuggestionGame {
                card(game)
                    .padding(.horizontal, NinoSpacing.xl)
                    .padding(.top, 6)
                    .transition(.opacity)
            }
        }
        .onAppear(perform: considerPackOffer)
        .onChange(of: state.offersLanguagePack) { _, _ in considerPackOffer() }
        .alert(HomeText.string("home.packOffer.title", locale), isPresented: $packOfferShown) {
            Button(HomeText.string("home.packOffer.open", locale)) { NSWorkspace.shared.open(Self.languageSettings) }
            Button(HomeText.string("home.packOffer.later", locale), role: .cancel) {}
        } message: {
            Text(HomeText.string("home.packOffer.message %@ %@", locale,
                                 HomeStatus.languageName(state.settings.sourceLanguage, locale),
                                 HomeStatus.languageName(state.settings.targetLanguage, locale)))
        }
    }

    private func considerPackOffer() {
        guard state.offersLanguagePack, !packOfferShown else { return }
        state.nudges.markLanguagePackOffered()
        packOfferShown = true
    }

    private func card(_ game: RecognizedGame) -> some View {
        HStack(spacing: 10) {
            Button {
                state.open(.settingsTranslation)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "key.fill").foregroundStyle(NinoColor.accent)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(HomeText.string("home.keySuggestion.title", locale))
                            .font(.nino(.callout).weight(.semibold))
                            .foregroundStyle(NinoColor.accentText)
                        Text(HomeText.string("home.keySuggestion.detail %@", locale, game.name))
                            .font(.nino(.caption))
                            .foregroundStyle(NinoColor.textSecondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button {
                state.nudges.dismissKeySuggestion(gameID: game.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(NinoColor.textSecondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(HomeText.string("home.keySuggestion.dismiss", locale))
            .accessibilityLabel(HomeText.string("home.keySuggestion.dismiss", locale))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: 520)
        .ninoGlass(cornerRadius: NinoRadius.card, edge: false)
    }
}
