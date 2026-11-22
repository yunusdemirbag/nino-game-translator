// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import SwiftUI
import UIKit

// Xbox (Beta) kurulumu: Microsoft girişi (cihaz kodu) → hesaptaki Xbox'ı seçme. Xbox'ta ikinci hesap adımı yoktur.
// Tarif: docs/yeni/ios/ayarlar.md §8.2–8.4, kurulum.md §4.2.

/// Kurulum 1/3 (Xbox): Microsoft hesabıyla cihaz kodu girişi.
struct XboxLoginScreen: View {
    @EnvironmentObject private var model: AppModel
    var onBack: (() -> Void)?
    var onSkip: (() -> Void)?
    let onDone: () -> Void

    @State private var code: DeviceCodeChallenge?
    @State private var waiting = false
    @State private var copied = false
    @State private var error: String?
    @State private var job: Task<Void, Never>?

    var body: some View {
        NinoScreen {
            SetupHeader(step: 1, onBack: onBack, onSkip: onSkip)
        } content: {
            HeroTitle(step: L("setup.step", 1), title: L("xbox.signin.button"), lead: L("xbox.signin.body"))
            HStack(spacing: DS.Space.inline) {
                TagLabel(text: "Beta")
                if model.xboxSignedIn && code == nil {
                    StatusLabel(text: L("signin.status.done"), dotColor: DS.Palette.success)
                }
            }
            if code == nil && !waiting {
                Text(L("xbox.signin.hint"))
                    .font(DS.Font.body).foregroundStyle(DS.Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let code { codeTile(code) }
            if waiting {
                HStack(spacing: DS.Space.inline) {
                    ProgressView().tint(DS.Palette.accent)
                    Text(L("xbox.signin.waiting")).font(DS.Font.caption).foregroundStyle(DS.Palette.secondary)
                }
            }
            if let error { NoteLine(text: L("xbox.signin.failed", error)) }
        } footer: {
            if let code {
                Button(L("xbox.code.open")) { openPage(code) }.buttonStyle(.ghost)
            }
            Button(L("xbox.signin.button")) { begin() }
                .buttonStyle(.primary)
                .disabled(waiting)
        }
        .onDisappear { job?.cancel() }
    }

    private func codeTile(_ code: DeviceCodeChallenge) -> some View {
        Tile(spacing: 10) {
            Text(L("xbox.code.label")).font(DS.Font.caption).foregroundStyle(DS.Palette.secondary)
            Button { copy(code) } label: {
                Text(verbatim: code.userCode)
                    .font(DS.Font.display.monospaced())
                    .foregroundStyle(DS.Palette.accent)
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text(L("xbox.code.copy")))
            Button { openPage(code) } label: {
                Text(verbatim: code.displayURL)
                    .font(DS.Font.headline).foregroundStyle(DS.Palette.accent).underline()
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text(L("xbox.code.open")))
            Text(L("xbox.code.steps"))
                .font(DS.Font.caption).foregroundStyle(DS.Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if copied {
                Text(L("xbox.code.copied")).font(DS.Font.caption).foregroundStyle(DS.Palette.success)
            }
        }
    }

    private func copy(_ code: DeviceCodeChallenge) {
        UIPasteboard.general.string = code.userCode
        copied = true
    }

    /// Kodu kopyalar ve Microsoft'un sayfasını tarayıcıda açar.
    private func openPage(_ code: DeviceCodeChallenge) {
        copy(code)
        if let url = URL(string: code.verificationURL) { UIApplication.shared.open(url) }
    }

    private func begin() {
        job?.cancel()
        error = nil
        copied = false
        waiting = true
        job = Task {
            defer { waiting = false }
            do {
                let challenge = try await model.xboxRequestCode()
                code = challenge
                openPage(challenge)
                try await model.xboxWaitForApproval(challenge)
                code = nil
                onDone()
            } catch is CancellationError {
            } catch let failure as XboxFailure {
                error = XboxText.setup(failure)
                code = nil
            } catch {
                self.error = error.localizedDescription
                code = nil
            }
        }
    }
}

/// Kurulum 2/3 (Xbox): hesaptaki Xbox'lardan birini seçme.
struct XboxConsoleScreen: View {
    @EnvironmentObject private var model: AppModel
    var onBack: (() -> Void)?
    var onSkip: (() -> Void)?
    /// Giriş süresi dolduğunda "Microsoft ile giriş yapın".
    let onSignIn: () -> Void
    let onDone: () -> Void

    @State private var consoles: [XboxConsole]?
    @State private var selected: String?
    @State private var error: String?
    @State private var needsSignIn = false

    private var choice: XboxConsole? { consoles?.first { $0.id == selected && $0.streamingEnabled } }

    var body: some View {
        NinoScreen {
            SetupHeader(step: 2, onBack: onBack, onSkip: onSkip)
        } content: {
            HeroTitle(step: L("setup.step", 2), title: L("xbox.choose.title"), lead: L("xbox.choose.body"))
            if let consoles {
                if consoles.isEmpty && error == nil {
                    NoteLine(text: L("xbox.choose.none"), color: DS.Palette.secondary)
                }
                ForEach(consoles, id: \.id) { row($0) }
            } else {
                Tile {
                    Text(L("xbox.choose.searching")).font(DS.Font.body).foregroundStyle(DS.Palette.secondary)
                }
            }
            if let error { NoteLine(text: error) }
        } footer: {
            Button(L("common.searchagain")) { Task { await load() } }
                .buttonStyle(.ghost)
                .disabled(consoles == nil)
            if needsSignIn {
                Button(L("xbox.signin.button"), action: onSignIn).buttonStyle(.primary)
            } else {
                Button(L("xbox.choose.use")) {
                    if let choice { model.chooseXbox(choice) }
                    onDone()
                }
                .buttonStyle(.primary)
                .disabled(choice == nil)
            }
        }
        .task { await load() }
    }

    private func row(_ console: XboxConsole) -> some View {
        Button {
            if console.streamingEnabled { selected = console.id }
        } label: {
            Tile(selected: selected == console.id) {
                HStack(spacing: DS.Space.gap) {
                    Image(systemName: console.streamingEnabled ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(console.streamingEnabled ? DS.Palette.accent : DS.Palette.danger)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: console.displayName).font(DS.Font.headline)
                        Text(console.streamingEnabled ? L("xbox.choose.ready") : L("xbox.choose.off"))
                            .font(DS.Font.caption).foregroundStyle(DS.Palette.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(DS.Palette.text)
    }

    private func load() async {
        consoles = nil
        error = nil
        needsSignIn = false
        if selected == nil { selected = model.xboxConsole?.id }
        do {
            let list = try await model.xboxConsoles()
            consoles = list
            if !list.contains(where: { $0.id == selected && $0.streamingEnabled }) {
                selected = list.first(where: \.streamingEnabled)?.id
            }
        } catch let failure as XboxFailure {
            needsSignIn = failure.problem == .needsSignIn
            error = XboxText.setup(failure)
            consoles = []
        } catch {
            self.error = error.localizedDescription
            consoles = []
        }
    }
}

/// Xbox sorunlarının ekrandaki anlatımı.
enum XboxText {
    /// Kurulum ekranlarında (giriş, Xbox listesi).
    static func setup(_ failure: XboxFailure) -> String {
        switch failure.problem {
        case .needsSignIn, .declined: L("xbox.error.signin")
        case .codeExpired: L("xbox.error.code")
        case .noProfile: L("xbox.error.noprofile")
        case .offline: L("xbox.error.offline")
        case .startFailed: L("xbox.session.startfailed")
        case .unreachable, .busy, .timeout, .unexpected:
            L("xbox.error.unexpected", failure.detail.isEmpty ? failure.problem.rawValue : String(failure.detail.prefix(120)))
        }
    }

    /// Çeviri sürerken bağlantı durumu. `willRetry`: oturum kendiliğinden yeniden deneyecek.
    static func session(_ problem: XboxProblem, willRetry: Bool) -> String {
        switch problem {
        case .needsSignIn, .declined, .codeExpired: return L("xbox.error.signin")
        case .noProfile: return L("xbox.error.noprofile")
        case .startFailed: return L("xbox.session.startfailed")
        default: break
        }
        guard willRetry else { return L("xbox.session.gaveup") }
        switch problem {
        case .unreachable: return L("xbox.session.unreachable")
        case .busy: return L("xbox.session.busy")
        case .timeout: return L("xbox.session.timeout")
        case .offline: return L("xbox.session.dropped")
        default: return L("xbox.session.unexpected")
        }
    }
}
