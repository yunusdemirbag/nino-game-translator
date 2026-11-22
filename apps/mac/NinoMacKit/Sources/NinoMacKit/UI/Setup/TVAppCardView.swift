// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import AppKit
import SwiftUI

/// TV uygulaması kartı (tv-kurulumu.md §5). Hâli `AppState.setup.tvApp`'ten; o boşsa `AppState.tvInstall`'dan.
/// "Geliştirici modu kapalı" ve Samsung denetim hâllerinde ekran açık kaldıkça 3 sn'de bir TV'ye yeniden sorulur.
struct TVAppCardView: View {
    let state: AppState
    @Environment(\.locale) private var locale
    @Environment(\.ninoStaticRendering) private var isStatic

    private var brand: PairedTV.Brand { state.pairedTV?.brand ?? .lg }

    /// Kartın geçerli hâli.
    static func card(_ state: AppState) -> TVAppCard {
        if state.setup.tvApp != .none { return state.setup.tvApp }
        switch state.tvInstall {
        case .idle: return .none
        case .searching: return state.pairedTV?.brand == .androidTV ? .androidDebuggingOff : .working
        case .waitingForApproval: return .androidApprove
        case .installing: return .working
        case .installed(let version): return .ready(version: version ?? "", lgHoursLeft: nil)
        case .failed(let message): return .failed(message: message)
        }
    }

    private var card: TVAppCard { Self.card(state) }

    private var polls: Bool {
        switch card {
        case .lgDeveloperModeOff, .androidDebuggingOff, .samsungCheck: return true
        default: return false
        }
    }

    var body: some View {
        if card != .none {
            NinoCard(title: SetupText.string("setup.tvApp.title", locale)) {
                content
            }
            .task(id: polls) { await poll() }
        }
    }

    private func poll() async {
        guard polls, !isStatic else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, polls else { return }
            state.recheckTVApp()
        }
    }

    @ViewBuilder private var content: some View {
        switch card {
        case .none:
            EmptyView()
        case .working:
            SetupWorkingRow(text: SetupText.string("setup.tvApp.installing", locale))
        case .ready(let version, let hours):
            NinoOKLabel(SetupText.string("setup.tvApp.ready %@", locale, version))
            readyHint(hours: hours)
        case .legacyApp:
            NinoOKLabel(SetupText.string("setup.tvApp.legacy", locale))
            NinoHint(SetupText.string("setup.tvApp.legacy.hint", locale))
            Button { state.upgradeLegacyTVApp() } label: { KText("setup.tvApp.legacy.update") }
                .buttonStyle(.nino(.secondary))
        case .lgDeveloperModeOff(let error):
            Text(SetupText.string("setup.tvApp.lg.notInstalled", locale)).fixedSize(horizontal: false, vertical: true)
            ForEach(1...3, id: \.self) { n in NinoHint(SetupText.string("setup.tvApp.lg.step\(n)", locale)) }
            PassphraseField(state: state, error: error)
        case .lgPassphrase(let error):
            Text(SetupText.string("setup.tvApp.lg.lastStep", locale)).fixedSize(horizontal: false, vertical: true)
            PassphraseField(state: state, error: error)
        case .samsungSignIn(let url):
            SamsungSignInCard(state: state, url: url)
        case .samsungCheck(let check):
            SamsungCheckCard(state: state, check: check)
        case .androidDebuggingOff:
            Text(SetupText.string("setup.tvApp.android.notInstalled", locale))
                .fixedSize(horizontal: false, vertical: true)
            ForEach(1...3, id: \.self) { n in NinoHint(SetupText.string("setup.tvApp.android.step\(n)", locale)) }
            SetupWorkingRow(text: SetupText.string("setup.tvApp.android.looking", locale))
            NinoHint(SetupText.string("setup.tvApp.android.menuHint", locale))
            AndroidUSBLink()
        case .androidApprove:
            Text(SetupText.string("setup.tvApp.android.approve", locale)).fixedSize(horizontal: false, vertical: true)
            NinoHint(SetupText.string("setup.tvApp.android.approveHint", locale))
            SetupWorkingRow(text: SetupText.string("setup.tvApp.android.waiting", locale))
        case .failed(let message):
            SetupErrorText(text: message)
            Button { state.recheckTVAppNow() } label: { KText("setup.tvApp.tryAgain") }
                .buttonStyle(.nino(.secondary))
        }
    }

    @ViewBuilder private func readyHint(hours: Int?) -> some View {
        switch brand {
        case .lg:
            if let hours {
                NinoHint(SetupText.string("setup.tvApp.lg.hoursLeft %lld", locale, hours))
            } else {
                NinoHint(SetupText.string("setup.tvApp.lg.extends", locale))
            }
        case .samsung:
            NinoHint(SetupText.string("setup.tvApp.samsung.anynet", locale))
        case .androidTV:
            EmptyView()
        }
    }
}

private struct AndroidUSBLink: View {
    @Environment(\.locale) private var locale
    @Environment(\.openURL) private var openURL

    var body: some View {
        SetupLink(systemImage: "externaldrive", title: SetupText.string("setup.tvApp.android.usb", locale)) {
            openURL(SetupLinks.tvAppGuide)
        }
    }
}

/// LG Key Server parolası.
private struct PassphraseField: View {
    let state: AppState
    let error: String?
    @Environment(\.locale) private var locale
    @State private var lgCode = ""

    var body: some View {
        NinoHint(SetupText.string("setup.tvApp.lg.passphraseHint", locale))
        HStack(spacing: NinoSpacing.m) {
            TextField(text: $lgCode) { Text(verbatim: "Passphrase") }
                .ninoTextField()
                .frame(maxWidth: 240)
                .onSubmit(install)
            Button(action: install) { KText("setup.tvApp.lg.install") }
                .buttonStyle(.nino(.primary, size: .large))
                .disabled(lgCode.allSatisfy(\.isWhitespace))
        }
        if let error { SetupErrorText(text: error) }
    }

    private func install() {
        let text = lgCode.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        state.installTVApp(passphrase: text)
    }
}

// MARK: - Samsung giriş kartı (§5.2)

private struct SamsungSignInCard: View {
    let state: AppState
    let url: String
    @Environment(\.locale) private var locale

    var body: some View {
        Text(SetupText.string("setup.tvApp.samsung.signIn", locale)).fixedSize(horizontal: false, vertical: true)
        NinoHint(SetupText.string("setup.tvApp.samsung.signIn.why", locale))
        NinoHint(SetupText.string("setup.tvApp.samsung.signIn.noAccount", locale))
        NinoHint(SetupText.string("setup.tvApp.samsung.signIn.popup", locale))
        HStack(spacing: NinoSpacing.m) {
            SetupWorkingRow(text: SetupText.string("setup.tvApp.samsung.signIn.waiting", locale))
            Spacer(minLength: NinoSpacing.s)
            Button { state.reopenSamsungSignIn() } label: { KText("setup.tvApp.samsung.signIn.reopen") }
                .buttonStyle(.nino(.secondary))
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url, forType: .string)
            } label: { KText("setup.tvApp.samsung.signIn.copy") }
                .buttonStyle(.nino(.secondary))
        }
    }
}

// MARK: - Samsung denetim kartı (§5.2)

private struct SamsungCheckCard: View {
    let state: AppState
    let check: SamsungCheck
    @Environment(\.locale) private var locale

    private var developerOn: Bool { check.problem != .developerModeOff && check.developerMode != false }

    private func text(_ key: String, _ args: CVarArg...) -> String {
        NinoL10n.string(key, table: SetupText.table, language: NinoL10n.languageCode(for: locale), arguments: args)
    }

    var body: some View {
        if check.tvAnswers {
            VStack(alignment: .leading, spacing: NinoSpacing.s) {
                CheckLine(mark: developerOn ? .ok : .missing,
                          text: text(developerOn ? "setup.samsung.row.modeOn" : "setup.samsung.row.modeOff"))
                CheckLine(mark: addressMark, text: addressText)
                CheckLine(mark: restartMark,
                          text: text(check.installGateOpen ? "setup.samsung.restart.ok" : "setup.samsung.restart"))
            }
        }
        explanation
    }

    private var addressMark: CheckLine.Mark {
        guard developerOn else { return .pending }
        if check.isAddressProblem { return .missing }
        if let ip = check.tvHostIP { return ip == check.macAddress ? .ok : .pending }
        return .pending
    }

    private var addressText: String {
        if developerOn, let ip = check.tvHostIP, ip != check.macAddress {
            return text("setup.samsung.address.mismatch %@ %@", ip, check.macAddress)
        }
        return text("setup.samsung.address.ok %@", check.macAddress)
    }

    private var restartMark: CheckLine.Mark {
        guard developerOn else { return .pending }
        if check.installGateOpen { return .ok }
        return check.problem == .notRestarted ? .missing : .pending
    }

    @ViewBuilder private var explanation: some View {
        let tvIP = check.tvHostIP ?? ""
        switch check.problem {
        case .checking:
            SetupWorkingRow(text: text("setup.samsung.checking"))
        case .noAnswer:
            SetupWorkingRow(text: text("setup.samsung.noAnswer"))
            NinoHint(text("setup.samsung.noAnswer.hint"))
        case .developerModeOff:
            Text(text("setup.samsung.modeOff")).fixedSize(horizontal: false, vertical: true)
            SamsungWindowSteps(state: state, check: check)
            NinoHint(text("setup.samsung.modeOff.account"))
        case .wrongAddress:
            SetupErrorText(text: text("setup.samsung.wrongAddress %@ %@", tvIP, check.macAddress))
            SamsungWindowSteps(state: state, check: check)
            tryAnyway
        case .leadingZeros:
            SetupErrorText(text: text("setup.samsung.leadingZeros %@ %@", tvIP, check.macAddress))
            SamsungWindowSteps(state: state, check: check)
            tryAnyway
        case .reversed:
            SetupErrorText(text: text("setup.samsung.reversed %@ %@", tvIP, check.macAddress))
            SamsungWindowSteps(state: state, check: check)
            tryAnyway
        case .loopback:
            SetupErrorText(text: text("setup.samsung.loopback %@", check.macAddress))
            SamsungWindowSteps(state: state, check: check)
        case .notRestarted:
            SetupErrorText(text: text("setup.samsung.notRestarted"))
            NinoHint(text("setup.samsung.notRestarted.hint"))
        case .dropped(let reason):
            if check.tvHostIP == check.macAddress {
                SetupErrorText(text: text("setup.samsung.dropped"))
            } else {
                SetupErrorText(text: text("setup.samsung.notAccepted"))
                NinoHint(text("setup.samsung.macAddress %@", check.macAddress))
                NinoHint(text("setup.samsung.restartHold"))
            }
            if let reason, !reason.isEmpty {
                Text(text("setup.samsung.details") + " " + reason)
                    .font(.nino(.callout))
                    .foregroundStyle(NinoColor.textSecondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !check.logPath.isEmpty {
                Text(text("setup.sendLog %@", check.logPath))
                    .font(.nino(.callout))
                    .foregroundStyle(NinoColor.textSecondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button { state.recheckTVAppNow() } label: { KText("setup.tvApp.tryAgain") }
                .buttonStyle(.nino(.secondary))
        }
    }

    private var tryAnyway: some View {
        Button { state.samsungTryAnyway() } label: { KText("setup.samsung.tryAnyway") }
            .buttonStyle(.nino(.secondary))
    }
}

/// Denetim satırı: tamam (yeşil onay), eksik (turuncu ünlem), sırası gelmedi (gri daire, gri yazı).
private struct CheckLine: View {
    enum Mark { case ok, missing, pending }
    let mark: Mark
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: NinoSpacing.s) {
            Image(systemName: symbol).foregroundStyle(color)
            Text(text)
                .foregroundStyle(mark == .pending ? NinoColor.textSecondary : NinoColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.nino(.callout))
    }

    private var symbol: String {
        switch mark {
        case .ok: return NinoSymbol.okFill
        case .missing: return "exclamationmark.circle.fill"
        case .pending: return "circle"
        }
    }

    private var color: NinoColor {
        switch mark {
        case .ok: return .success
        case .missing: return .warning
        case .pending: return .textSecondary
        }
    }
}

/// Samsung geliştirici modu penceresinin adımları ve "Pencere açılmıyor mu?" bölümü.
private struct SamsungWindowSteps: View {
    let state: AppState
    let check: SamsungCheck
    @Environment(\.locale) private var locale
    @State private var expanded = false

    private func text(_ key: String, _ args: CVarArg...) -> String {
        NinoL10n.string(key, table: SetupText.table, language: NinoL10n.languageCode(for: locale), arguments: args)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: NinoSpacing.s) {
            let newModel = (check.modelYear ?? 0) >= 2022
            NinoHint(text(newModel ? "setup.samsung.window.step1.new" : "setup.samsung.window.step1.old"))
            NinoHint(text("setup.samsung.window.step2"))
            NinoHint(text("setup.samsung.window.step3 %@", check.macAddress))
            NinoHint(text("setup.samsung.window.step4"))
            let open = expanded || check.typeCode != nil
            Button {
                withAnimation(.easeOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: open ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .flipsForRightToLeftLayoutDirection(true)
                    Text(text("setup.samsung.window.notOpening"))
                }
                .font(.nino(.callout))
                .foregroundStyle(NinoColor.textPrimary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open {
                VStack(alignment: .leading, spacing: NinoSpacing.s) {
                    ForEach(1...4, id: \.self) { n in NinoHint(text("setup.samsung.window.tip\(n)")) }
                    HStack(spacing: NinoSpacing.s) {
                        Button { state.samsungTypeDeveloperCode() } label: { KText("setup.samsung.typeCode") }
                            .buttonStyle(.nino(.secondary))
                            .disabled(check.typeCode == .sending)
                        if check.typeCode == .sending { SetupSpinner() }
                    }
                    if check.typeCode == .sent { NinoHint(text("setup.samsung.typeCode.sent")) }
                    if check.typeCode == .unreachable { SetupErrorText(text: text("setup.samsung.typeCode.unreachable")) }
                }
                .padding(.top, NinoSpacing.s)
            }
        }
    }
}
