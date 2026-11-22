// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import SwiftUI

/// Ayarlar › Bağlantı › Televizyon: eşli TV, bağlantı durumu, TV uygulamasının kartı (eski sürüm kuruluysa
/// "Yeni Sürümü Kur" burada da görünür) ve TV kurulumunu açma. TV hazır olsa da TV kurulumuna her zaman buradan girilir.
struct TVSettingsSection: View {
    let state: AppState
    @Environment(\.locale) private var locale
    @Environment(\.ninoStaticRendering) private var isStatic

    private func text(_ key: String, _ args: CVarArg...) -> String {
        NinoL10n.string(key, table: SettingsText.table, language: NinoL10n.languageCode(for: locale), arguments: args)
    }

    var body: some View {
        NinoCard {
            SettingsSmallHeader(text: text("settings.tv.header"))
            if let tv = state.pairedTV {
                HStack(spacing: NinoSpacing.s) {
                    NinoStatusDot(state.connectedDisplays > 0 ? .good : .warning)
                    Text(verbatim: tv.name).font(.nino(.headline))
                    Spacer(minLength: NinoSpacing.s)
                    Text(state.connectedDisplays > 0 ? text("settings.tv.connected") : text("settings.tv.waiting"))
                        .font(.nino(.callout))
                        .foregroundStyle(NinoColor.textSecondary)
                }
                TVAppCardView(state: state)
                if tv.brand == .androidTV {
                    // TCL gibi bazı Google TV'lerde PS5 görüntüsü uygulamanın içinde siyah gelir: o zaman altyazı
                    // TV'nin kendi HDMI ekranının üstüne katman olarak çizilir.
                    SettingsSwitch(title: text("settings.tv.overlay"), isOn: Binding(
                        get: { state.settings.style.displayMode == .overlay },
                        set: { state.settings.style.displayMode = $0 ? .overlay : .inApp }))
                    SHint("settings.tv.overlayHint")
                }
            } else {
                SHint("settings.tv.none")
            }
            Button {
                state.activeSheet = nil
                state.openSetup(at: .tv)
            } label: {
                SText("settings.tv.openSetup")
            }
            .buttonStyle(.nino(.secondary))
        }
        .onAppear {
            // Kart boşsa TV uygulamasının sürümü sorulur (eski sürüm kuruluysa "Yeni Sürümü Kur" çıkar).
            guard !isStatic, state.pairedTV != nil, TVAppCardView.card(state) == .none else { return }
            state.recheckTVApp()
        }
    }
}
