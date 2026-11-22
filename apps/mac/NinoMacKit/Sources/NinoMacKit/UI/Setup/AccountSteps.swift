// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import SwiftUI

// MARK: - Adım 2: İkinci PSN hesabı (kurulum.md §4)

struct SecondAccountStep: View {
    let state: AppState
    @Environment(\.locale) private var locale
    @Environment(\.openURL) private var openURL

    var body: some View {
        NinoSetupStepLayout(icon: .symbol("person.crop.circle.badge.plus"),
                            title: SetupText.string("setup.account.title", locale),
                            message: SetupText.string("setup.account.message", locale)) {
            VStack(alignment: .leading, spacing: NinoSpacing.m) {
                ForEach(1...4, id: \.self) { n in
                    NinoNumberedRow(number: n, text: SetupText.string("setup.account.step\(n)", locale))
                }
                NinoHint(SetupText.string("setup.account.mainAccountHint", locale))
                    .padding(.horizontal, NinoSpacing.xs)
                windowCard.padding(.top, NinoSpacing.xs)
            }
        }
        .onAppear { state.refreshRemotePlayApps() }
    }

    private var windowCard: some View {
        VStack(alignment: .leading, spacing: NinoSpacing.m) {
            HStack(spacing: NinoSpacing.m) {
                KText("setup.account.window.title")
                    .font(.nino(.body).weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: NinoSpacing.s)
                Button { SetupFlow.readRemotePlayWindow(state) } label: { KText("setup.account.window.select") }
                    .buttonStyle(.nino(.secondary))
            }
            NinoHint(SetupText.string("setup.account.window.hint", locale))
            if !state.setup.remotePlayAppInstalled {
                SetupErrorText(text: SetupText.string("setup.account.window.missing", locale))
                HStack(spacing: NinoSpacing.m) {
                    Button { openURL(SetupLinks.remotePlay) } label: { KText("setup.account.window.getRemotePlay") }
                        .buttonStyle(.nino(.secondary))
                    Button { openURL(SetupLinks.chiaki) } label: { KText("setup.account.window.getChiaki") }
                        .buttonStyle(.nino(.secondary))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ninoTile()
    }
}

// MARK: - Adım 3: PSN girişi (§5)

struct PSNLoginStep: View {
    let state: AppState
    @Environment(\.locale) private var locale
    @State private var manualOpen = false
    @State private var manualText = ""
    @State private var manualInvalid = false

    private var working: Bool {
        state.psnAccount == .signingIn || state.psnLoginController?.isWorking == true
    }

    var body: some View {
        NinoSetupStepLayout(icon: .symbol("key.fill"), title: SetupText.string("setup.psn.title", locale),
                            message: SetupText.string("setup.psn.message", locale)) {
            VStack(spacing: NinoSpacing.l) {
                if case .signedIn(let id) = state.psnAccount {
                    signedIn(id)
                } else {
                    signedOut
                }
            }
            .frame(maxWidth: .infinity)
        }
        .sheet(isPresented: sheetBinding) {
            if let controller = state.psnLoginController { PSNLoginView(controller: controller) }
        }
    }

    private var sheetBinding: Binding<Bool> {
        Binding(get: { state.psnLoginController?.isPresented ?? false },
                set: { shown in if !shown { state.psnLoginController?.cancel() } })
    }

    // MARK: Giriş yapılmamışken

    @ViewBuilder private var signedOut: some View {
        VStack(alignment: .leading, spacing: NinoSpacing.m) {
            assurance("lock.shield.fill", "setup.psn.assure.password")
            SetupDivider()
            assurance("person.text.rectangle.fill", "setup.psn.assure.idOnly")
            SetupDivider()
            assurance("checkmark.seal.fill", "setup.psn.assure.once")
        }
        .frame(maxWidth: 520 - 2 * NinoSpacing.l, alignment: .leading)
        .ninoTile()

        Button { state.beginPSNSignIn() } label: {
            Label { KText("setup.psn.signIn") } icon: { Image(systemName: "person.crop.circle.fill") }
                .frame(minWidth: 260 - 2 * NinoSpacing.l)
        }
        .buttonStyle(.nino(.primary, size: .large))
        .disabled(working)
        if working { SetupSpinner() }

        if let message = errorMessage {
            SetupErrorText(text: message, centered: true).frame(maxWidth: 520)
        }

        if manualOpen {
            VStack(spacing: NinoSpacing.m) {
                NinoHint(SetupText.string("setup.psn.manual.hint", locale))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)
                HStack(spacing: NinoSpacing.m) {
                    TextField(text: $manualText) { Text(verbatim: "AbCdEfGhIjk=") }
                        .ninoTextField()
                        .frame(maxWidth: 240)
                        .onSubmit(saveManual)
                        .onChange(of: manualText) { _, _ in manualInvalid = false }
                    Button(action: saveManual) { KText("setup.psn.manual.save") }
                        .buttonStyle(.nino(.primary, size: .large))
                }
                if manualInvalid {
                    SetupErrorText(text: SetupText.string("setup.psn.manual.invalid", locale), centered: true)
                }
            }
        } else {
            SetupLink(systemImage: nil, title: SetupText.string("setup.psn.manual.open", locale)) {
                manualOpen = true
            }
        }
    }

    private var errorMessage: String? {
        if let text = state.psnLoginController?.errorMessage() { return text }
        if case .failed(let message) = state.psnAccount { return message }
        return nil
    }

    private func assurance(_ symbol: String, _ key: String) -> some View {
        HStack(spacing: NinoSpacing.m) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(NinoColor.accentText)
                .frame(width: 26)
            KText(key).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func saveManual() {
        if state.enterPSNAccountID(manualText) {
            manualText = ""
            manualOpen = false
            manualInvalid = false
        } else {
            manualInvalid = true
        }
    }

    // MARK: Giriş yapılmışken

    private func signedIn(_ id: Data) -> some View {
        HStack(spacing: NinoSpacing.m) {
            NinoGradientIconBox(systemName: "person.crop.circle.badge.checkmark", size: 44)
            VStack(alignment: .leading, spacing: 3) {
                KText("setup.psn.signedIn").font(.nino(.headline)).foregroundStyle(NinoColor.success)
                Text(SetupText.string("setup.psn.accountID", locale) + ": " + PSNAuth.maskedAccountID(id))
                    .font(.nino(.callout).monospaced())
                    .foregroundStyle(NinoColor.textSecondary)
            }
            Spacer(minLength: NinoSpacing.s)
            Button { state.signOutPSN() } label: { KText("setup.psn.signOut") }
                .buttonStyle(.nino(.danger))
        }
        .frame(maxWidth: 520 - 2 * NinoSpacing.l)
        .ninoTile()
    }
}
