// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import SwiftUI

/// Adım 5: TV'yi bağla (kurulum.md §7). TV ile konuşan iş motorda (TVSetup); burası durumu çizer.
struct TVStep: View {
    let state: AppState
    @Environment(\.locale) private var locale
    @Environment(\.openURL) private var openURL
    /// LG/Samsung listesi açık mı (tür sorusu yerine).
    @State private var listOpen = false
    /// Son seçilen TV'nin markası (uygulama paketi yoksa rehber kartı için).
    @State private var chosenBrand: PairedTV.Brand?

    private var connecting: Bool { if case .connecting = state.setup.tvConnect { return true }; return false }

    var body: some View {
        NinoSetupStepLayout(icon: .symbol("tv.fill"), title: SetupText.string("setup.tv.title", locale),
                            message: SetupText.string("setup.tv.message", locale)) {
            VStack(alignment: .leading, spacing: NinoSpacing.l) {
                if let tv = state.pairedTV {
                    NinoOKLabel(SetupText.string("setup.tv.paired %@", locale, tv.name))
                }
                if state.pairedTV == nil && !connecting {
                    if listOpen || state.setup.tvSearch == .searching { networkList } else { chooser }
                }
                if case .connecting(let brand) = state.setup.tvConnect {
                    SetupWorkingRow(text: SetupText.string(brand == .samsung ? "setup.tv.connecting.samsung"
                                                                             : "setup.tv.connecting", locale))
                }
                if case .failed(let failure) = state.setup.tvConnect {
                    SetupErrorText(text: SetupText.string(failureKey(failure), locale))
                }
                TVAppCardView(state: state)
                if showsGuideCard { guideCard }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            if state.pairedTV != nil, state.setup.tvApp == .none, state.tvInstall == .idle { state.recheckTVApp() }
        }
    }

    private func failureKey(_ failure: TVConnectFailure) -> String {
        switch failure {
        case .samsungRefused: return "setup.tv.error.samsungRefused"
        case .samsungNotAccepted: return "setup.tv.error.samsungNotAccepted"
        case .noResponse: return "setup.tv.error.noResponse"
        }
    }

    // MARK: Tür sorusu

    private var chooser: some View {
        VStack(alignment: .leading, spacing: NinoSpacing.m) {
            KText("setup.tv.which").font(.nino(.headline))
            VStack(alignment: .leading, spacing: NinoSpacing.xs) {
                NinoOptionCard(artwork: .asset(.tvOptionAndroid), title: "Android TV / Google TV",
                               subtitle: SetupText.string("setup.tv.android.detail", locale)) {
                    chosenBrand = .androidTV
                    state.pairTV(.androidTV)
                }
                if state.settings.gameConsole != .xbox {
                    SetupLink(systemImage: "photo.on.rectangle",
                              title: SetupText.string("setup.tv.android.photoGuide", locale)) {
                        openURL(SetupLinks.androidPhotoGuide)
                    }
                    .padding(.leading, NinoSpacing.xs)
                }
            }
            NinoOptionCard(artwork: .asset(.tvOptionLGSamsung), title: SetupText.string("setup.tv.lgSamsung", locale),
                           subtitle: SetupText.string("setup.tv.lgSamsung.detail", locale)) {
                listOpen = true
                state.searchTVs()
            }
            NinoOptionCard(artwork: .asset(.tvOptionMac), title: SetupText.string("setup.tv.noTV", locale),
                           subtitle: SetupText.string(state.settings.gameConsole == .xbox ? "setup.tv.noTV.xbox"
                                                                                          : "setup.tv.noTV.ps5",
                                                      locale)) {
                SetupFlow.noTV(state)
            }
        }
    }

    // MARK: LG / Samsung listesi

    private var networkList: some View {
        let searching = state.setup.tvSearch == .searching
        return VStack(alignment: .leading, spacing: NinoSpacing.m) {
            VStack(alignment: .leading, spacing: NinoSpacing.m) {
                HStack(spacing: NinoSpacing.m) {
                    NinoGradientIconBox(systemName: "wifi", size: 32)
                    KText("setup.tv.list.title").font(.nino(.headline))
                    if searching { SetupSpinner() }
                    Spacer(minLength: NinoSpacing.s)
                    Button { state.searchTVs() } label: { KText("setup.tv.list.searchAgain") }
                        .buttonStyle(.nino(.secondary))
                        .disabled(searching)
                }
                if state.setup.foundTVs.isEmpty, !searching {
                    NinoHint(SetupText.string("setup.tv.list.empty", locale))
                }
                ForEach(state.setup.foundTVs) { tv in
                    HStack {
                        Text(verbatim: "\(tv.name) — \(tv.host)")
                        Spacer(minLength: NinoSpacing.s)
                        Button {
                            chosenBrand = tv.brand
                            state.pairTV(tv)
                        } label: { KText("setup.tv.list.connect") }
                        .buttonStyle(.nino(.primary))
                        .disabled(connecting)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .ninoTile()
            Button {
                listOpen = false
                state.setup.tvSearch = .idle
            } label: {
                Label { KText("setup.tv.list.another") } icon: {
                    Image(systemName: "chevron.left").flipsForRightToLeftLayoutDirection(true)
                }
            }
            .buttonStyle(.nino(.ghost))
        }
    }

    // MARK: Paket yoksa rehber kartı

    private var showsGuideCard: Bool {
        guard !state.setup.tvAppBundled else { return false }
        let brand = state.pairedTV?.brand ?? chosenBrand
        return brand != nil && brand != .lg
    }

    private var guideCard: some View {
        NinoCard(title: SetupText.string("setup.tvApp.title", locale)) {
            NinoHint(SetupText.string("setup.tv.guide.text", locale))
            SetupLink(systemImage: "book", title: SetupText.string("setup.tv.guide.open", locale)) {
                openURL(SetupLinks.tvAppGuide)
            }
        }
    }
}
