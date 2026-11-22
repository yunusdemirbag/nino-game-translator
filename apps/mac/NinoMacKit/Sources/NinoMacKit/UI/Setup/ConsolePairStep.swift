// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import SwiftUI

/// Adım 4: PS5'i bağla (kurulum.md §6). Adım açılınca PS5 araması başlar.
struct ConsolePairStep: View {
    let state: AppState
    @Environment(\.locale) private var locale
    @State private var pairAgain = false

    /// Eşli PS5 karosu: eşli PS5 varsa, "Yeniden eşle" denmediyse ve az önce bu formda eşlenmediyse.
    private var showsPairedTile: Bool {
        state.pairedConsole != nil && !pairAgain && state.pairing != .paired
    }

    var body: some View {
        NinoSetupStepLayout(icon: .symbol(NinoSymbol.controllerFill),
                            title: SetupText.string("setup.ps5.title", locale),
                            message: SetupText.string("setup.ps5.message", locale)) {
            if showsPairedTile, let console = state.pairedConsole {
                pairedTile(console)
            } else {
                ConsolePairForm(state: state)
            }
        }
        .onAppear { state.searchConsoles() }
    }

    private func pairedTile(_ console: PairedConsole) -> some View {
        HStack(spacing: NinoSpacing.m) {
            NinoGradientIconBox(systemName: "checkmark", size: 44)
            VStack(alignment: .leading, spacing: 3) {
                KText("setup.ps5.paired").font(.nino(.headline)).foregroundStyle(NinoColor.success)
                Text(verbatim: "\(console.name.isEmpty ? "PS5" : console.name) · \(console.host)")
                    .font(.nino(.callout))
                    .foregroundStyle(NinoColor.textSecondary)
            }
            Spacer(minLength: NinoSpacing.s)
            Button { pairAgain = true } label: { KText("setup.ps5.pairAgain") }
                .buttonStyle(.nino(.secondary))
        }
        .frame(maxWidth: .infinity)
        .ninoTile()
    }
}

/// Eşleştirme formu: hesap uyarısı, üç adım kartı, PS5 durum hapı, 8 kutulu kod, Bağlan.
struct ConsolePairForm: View {
    let state: AppState
    @Environment(\.locale) private var locale
    @Environment(\.ninoStaticRendering) private var isStatic
    @State private var code = ""
    @State private var selectedAddress: String?
    @State private var manualIPOpen = false
    @State private var manualIP = ""
    @FocusState private var codeFocused: Bool

    private var failed: Bool { if case .failed = state.pairing { return true }; return false }
    private var working: Bool { state.pairing == .pairing }
    private var justPaired: Bool { state.pairing == .paired }

    /// Bağlanılacak adres: elle yazılan IP, yoksa seçili (ya da ilk bulunan) PS5.
    private var address: String {
        let typed = manualIP.trimmingCharacters(in: .whitespaces)
        if manualIPOpen, !typed.isEmpty { return typed }
        return selectedAddress ?? state.setup.foundConsoles.first?.address ?? ""
    }

    private var canConnect: Bool {
        !working && !justPaired && code.count == 8 && state.psnAccount.isSignedIn && !address.isEmpty
    }

    var body: some View {
        VStack(spacing: NinoSpacing.l) {
            if !state.psnAccount.isSignedIn { accountWarning }
            stepCards
            statusPill
            codeBoxes
            Button(action: connect) {
                KText("setup.ps5.connect").frame(minWidth: 220 - 2 * NinoSpacing.l)
            }
            .buttonStyle(.nino(.primary, size: .large))
            .disabled(!canConnect)
            if working { SetupWorkingRow(text: SetupText.string("setup.ps5.connecting", locale)) }
            if justPaired, let console = state.pairedConsole {
                NinoOKLabel(SetupText.string("setup.ps5.success %@ %@", locale,
                                             console.name.isEmpty ? "PS5" : console.name, console.host))
                    .id("pairedMessage")
            }
            if case .failed(let message) = state.pairing {
                SetupErrorText(text: message, centered: true).frame(maxWidth: 560)
                Button { state.revealRemotePlayLog() } label: { KText("setup.ps5.showLog") }
                    .buttonStyle(.nino(.secondary))
            }
        }
        .frame(maxWidth: .infinity)
        .onAppear { if !isStatic { codeFocused = true } }
        .task(id: justPaired) { await advanceAfterPairing() }
    }

    // MARK: Parçalar

    private var accountWarning: some View {
        HStack(spacing: NinoSpacing.m) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 20))
                .foregroundStyle(NinoColor.warning)
            KText("setup.ps5.needAccount").font(.nino(.callout).weight(.semibold))
            Spacer(minLength: NinoSpacing.s)
            Button { state.setupStep = .psnLogin } label: { KText("setup.ps5.needAccount.signIn") }
                .buttonStyle(.nino(.primary))
        }
        .padding(NinoSpacing.m)
        .background(NinoRadius.shape(NinoRadius.control).fill(NinoColor.warning.opacity(0.10)))
    }

    private var stepCards: some View {
        HStack(spacing: NinoSpacing.m) {
            PairStepCard(number: 1, systemImage: "person.2.fill", title: "setup.ps5.step1.title",
                         path: "setup.ps5.step1.path")
            PairStepCard(number: 2, systemImage: NinoSymbol.settings, title: "setup.ps5.step2.title",
                         path: "setup.ps5.step2.path")
            PairStepCard(number: 3, systemImage: "number", title: "setup.ps5.step3.title",
                         path: "setup.ps5.step3.path")
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(failed ? 4 : 0)
        .overlay {
            if failed {
                RoundedRectangle(cornerRadius: NinoRadius.card + 4, style: .continuous)
                    .strokeBorder(NinoColor.warning.opacity(0.8), lineWidth: 1.5)
            }
        }
    }

    @ViewBuilder private var statusPill: some View {
        let search = state.setup.consoleSearch
        let found = state.setup.foundConsoles
        SetupPill {
            HStack(spacing: NinoSpacing.s) {
                if search == .searching {
                    SetupSpinner()
                    KText("setup.ps5.searching").foregroundStyle(NinoColor.textSecondary)
                } else if found.count > 1 {
                    Image(systemName: NinoSymbol.okFill).foregroundStyle(NinoColor.success)
                    Picker(selection: Binding(get: { selectedAddress ?? found[0].address },
                                              set: { selectedAddress = $0 })) {
                        ForEach(found) { console in
                            Text(verbatim: "\(console.name) — \(console.address)").tag(console.address)
                        }
                    } label: { EmptyView() }
                    .labelsHidden()
                    .fixedSize()
                } else if let only = found.first {
                    Image(systemName: NinoSymbol.okFill).foregroundStyle(NinoColor.success)
                    Text(SetupText.string("setup.ps5.found %@", locale, only.name.isEmpty ? "PS5" : only.name))
                } else if search == .finished {
                    Image(systemName: "exclamationmark.circle.fill").foregroundStyle(NinoColor.warning)
                    KText("setup.ps5.notFound")
                    if manualIPOpen {
                        TextField(text: $manualIP) { KText("setup.ps5.ipPlaceholder") }
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 230, height: 30)
                            .onSubmit(connect)
                    } else {
                        SetupLink(systemImage: nil, title: SetupText.string("setup.ps5.useIP", locale)) {
                            manualIPOpen = true
                        }
                    }
                }
                if search == .finished {
                    Text(verbatim: "·").foregroundStyle(NinoColor.textSecondary)
                    SetupLink(systemImage: nil, title: SetupText.string("setup.ps5.searchAgain", locale)) {
                        state.searchConsoles()
                    }
                }
            }
        }
        .help(search == .finished && found.isEmpty ? SetupText.string("setup.ps5.notFound.help", locale) : "")
    }

    private var codeBoxes: some View {
        ZStack {
            HStack(spacing: 8) {
                ForEach(0..<8, id: \.self) { index in
                    if index == 4 {
                        Text(verbatim: "–").font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(NinoColor.textSecondary)
                    }
                    CodeBox(digit: digit(at: index), current: codeFocused && index == min(code.count, 7))
                }
            }
            .environment(\.layoutDirection, .leftToRight)
            TextField("", text: Binding(get: { code }, set: { newValue in
                let filtered = ConsoleInput.filterCodeInput(newValue)
                if filtered != code, state.pairing != .pairing { state.pairing = .idle }
                code = filtered
            }))
            .textFieldStyle(.plain)
            .focused($codeFocused)
            .foregroundStyle(.clear)
            .tint(.clear)
            .opacity(0.02)
            .onSubmit(connect)
            .accessibilityLabel(SetupText.string("setup.ps5.codeLabel", locale))
        }
        .fixedSize()
        .contentShape(Rectangle())
        .onTapGesture { codeFocused = true }
    }

    private func digit(at index: Int) -> String? {
        guard index < code.count else { return nil }
        return String(code[code.index(code.startIndex, offsetBy: index)])
    }

    // MARK: Davranış

    private func connect() {
        guard canConnect else { return }
        state.pairConsole(address: address, code: code)
    }

    /// Başarıdan ~1 sn sonra kendiliğinden TV adımına geçilir; bu arada adım değiştiyse geçilmez.
    private func advanceAfterPairing() async {
        guard justPaired, !isStatic else { return }
        code = ""
        try? await Task.sleep(for: .seconds(1))
        guard !Task.isCancelled, state.setupStep == .console, state.pairing == .paired else { return }
        state.pairing = .idle
        state.setupStep = .tv
    }
}

/// Üç adım kartından biri: degrade simge, büyük numara, başlık ve yol.
private struct PairStepCard: View {
    let number: Int
    let systemImage: String
    let title: String
    let path: String

    var body: some View {
        VStack(alignment: .leading, spacing: NinoSpacing.s) {
            HStack(alignment: .top) {
                NinoGradientIconBox(systemName: systemImage, size: 36)
                Spacer(minLength: 0)
                Text(verbatim: "\(number)")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(NinoColor.textSecondary.opacity(0.6))
            }
            KText(title).font(.nino(.headline)).fixedSize(horizontal: false, vertical: true)
            KText(path)
                .font(.nino(.callout))
                .foregroundStyle(NinoColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 130 - 2 * NinoSpacing.m, alignment: .topLeading)
        .ninoTile(padding: NinoSpacing.m)
    }
}

/// Kod kutusu 44×56: rakam 26 yarı kalın yuvarlak eş genişlikli.
private struct CodeBox: View {
    let digit: String?
    let current: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        Text(verbatim: digit ?? "")
            .font(.system(size: 26, weight: .semibold, design: .rounded).monospacedDigit())
            .frame(width: 44, height: 56)
            .background(shape.fill(NinoColor.textSecondary.opacity(0.10)))
            .overlay(shape.strokeBorder(current ? AnyShapeStyle(NinoColor.accent)
                                                : AnyShapeStyle(NinoColor.textSecondary.opacity(0.45)),
                                        lineWidth: current ? 2 : 1.5))
    }
}
