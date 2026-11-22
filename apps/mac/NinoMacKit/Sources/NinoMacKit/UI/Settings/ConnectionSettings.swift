// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import AppKit
import SwiftUI

// Bağlantı (ayarlar.md §4) ve PS5 giriş şifresi (§5).

/// Bağlantı kartı. Ayarlar'da `detailed` (açıklamalar ve kart denetimi ek); kısa hâli başka ekranlar içindir.
public struct ConnectionSettings: View {
    private let state: AppState
    private let detailed: Bool
    @State private var guideOpen = false
    @Environment(\.locale) private var locale

    public init(state: AppState, detailed: Bool) {
        self.state = state
        self.detailed = detailed
    }

    private var settings: MacSettings { state.settings }

    public var body: some View {
        NinoCard {
            SettingsSmallHeader(text: text("settings.connection.console"))
            NinoSegmentedPicker(selection: consoleBinding, options: [
                .init(.ps5, title: "PS5", systemImage: NinoSymbol.controller),
                .init(.xbox, title: "Xbox", systemImage: NinoSymbol.controllerFill),
            ])
            SettingsSmallHeader(text: text("settings.connection.picture"))
            NinoSegmentedPicker(selection: sourceBinding, options: sourceOptions)
            if settings.gameConsole == .xbox, settings.videoSource == .window {
                SHint("settings.connection.xboxHint")
            }
            switch settings.videoSource {
            case .card: cardPart
            case .window: windowPart
            case .ps5: if detailed { SHint("settings.connection.ps5Hint") }
            }
        }
        .sheet(isPresented: $guideOpen) {
            CaptureCardGuideSheet(state: state) { guideOpen = false }
        }
    }

    private func text(_ key: String) -> String { SettingsText.string(key, locale) }

    // MARK: Seçiciler

    private var consoleBinding: Binding<MacSettings.GameConsole> {
        Binding(get: { state.settings.gameConsole },
                set: { state.settings = SettingsRules.choosing(console: $0, in: state.settings) })
    }

    private var sourceBinding: Binding<MacSettings.VideoSource> {
        Binding(get: { state.settings.videoSource },
                set: { state.settings = SettingsRules.choosing(source: $0, in: state.settings) })
    }

    private var sourceOptions: [NinoSegmentedPicker<MacSettings.VideoSource>.Option] {
        let card = NinoSegmentedPicker<MacSettings.VideoSource>.Option(
            .card, title: text("settings.connection.source.card"), systemImage: NinoSymbol.captureCard)
        if settings.gameConsole == .xbox {
            return [.init(.window, title: text("settings.connection.source.xboxWindow"), systemImage: NinoSymbol.gameWindow),
                    card]
        }
        return [.init(.ps5, title: "PS5", systemImage: NinoSymbol.controller),
                .init(.window, title: text("settings.connection.source.window"), systemImage: NinoSymbol.gameWindow),
                card]
    }

    private var outputBinding: Binding<MacSettings.Output> {
        Binding(get: { state.settings.output }, set: { state.settings.output = $0 })
    }

    // MARK: Alt kısımlar

    @ViewBuilder private var cardPart: some View {
        SettingsSmallHeader(text: text("settings.connection.output"))
        NinoSegmentedPicker(selection: outputBinding, options: [
            .init(.tv, title: text("settings.connection.output.tv"), systemImage: NinoSymbol.outputTV),
            .init(.computer, title: text("settings.connection.output.computer"), systemImage: NinoSymbol.outputComputer),
            .init(.both, title: text("settings.connection.output.both"), systemImage: NinoSymbol.outputBoth),
        ])
        if state.subtitlesOnComputer {
            if detailed { SHint("settings.connection.computerHint") }
            overlayControls
        }
        if detailed {
            switch settings.output {
            case .tv: SHint("settings.connection.cardTVHint")
            case .computer: SHint("settings.connection.cardComputerHint")
            case .both:
                SHint("settings.connection.cardTVHint")
                SHint("settings.connection.cardComputerHint")
            }
            if state.translation == .off {
                CardCheckView(state: state, height: 170)
            }
            Button {
                guideOpen = true
            } label: {
                Label { SText("settings.connection.guide") } icon: { Image(systemName: NinoSymbol.connectionGuide) }
            }
            .buttonStyle(.nino(.secondary))
            .help(text("settings.connection.guideHelp"))
            .disabled(state.translation != .off)
        }
    }

    @ViewBuilder private var windowPart: some View {
        if settings.gameConsole == .ps5, detailed { SHint("settings.connection.remotePlayHint") }
        overlayControls
    }

    /// "Tıklamalar geçsin" + "Altyazı Penceresini Ayarla" yan yana (dar yerde alt alta) ve ipucu.
    @ViewBuilder private var overlayControls: some View {
        let toggle = SettingsSwitch(title: text("settings.connection.clickThrough"),
                                    isOn: Binding(get: { state.settings.overlayClickThrough },
                                                  set: { state.settings.overlayClickThrough = $0 }))
        let adjust = Button {
            state.overlayAdjusting = true
        } label: {
            SText("settings.connection.adjustWindow")
        }
        .buttonStyle(.nino(.secondary))
        .disabled(state.overlayAdjusting)
        ViewThatFits(in: .horizontal) {
            HStack(spacing: NinoSpacing.l) {
                toggle.fixedSize()
                Spacer(minLength: 0)
                adjust
            }
            VStack(alignment: .leading, spacing: NinoSpacing.m) {
                toggle
                adjust
            }
        }
        if detailed { SHint("settings.connection.clickHint") }
    }
}

// MARK: - Kart denetimi (kurulum.md §10 "Kart denetimi", Ayarlar'da 170 pt)

struct CardCheckView: View {
    let state: AppState
    let height: CGFloat
    @Environment(\.locale) private var locale
    @Environment(\.ninoStaticRendering) private var isStatic

    private var status: CaptureCardCheck.Status { state.setup.captureCard.status }

    var body: some View {
        VStack(alignment: .leading, spacing: NinoSpacing.s) {
            preview
            statusRow
        }
        .onAppear { if !isStatic, state.translation == .off { state.setCaptureCardPreview(true) } }
        .onDisappear { if !isStatic { state.setCaptureCardPreview(false) } }
    }

    private var preview: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return ZStack {
            shape.fill(Color.black)
            switch status {
            case .noPermission, .searching, .noCard:
                VStack(spacing: NinoSpacing.s) {
                    Image(systemName: status == .noPermission ? "lock.fill" : NinoSymbol.captureCard)
                        .font(.system(size: 30, weight: .semibold))
                    Text(SettingsText.string(status == .noPermission ? "settings.card.permissionTitle"
                                                                       : "settings.card.lookingTitle", locale))
                        .font(.nino(.headline))
                }
                .foregroundStyle(Color.white.opacity(0.85))
            case .black, .working, .stopped:
                CardPreviewView()
            }
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .topLeading) { pill.padding(10) }
        .clipShape(shape)
        .accessibilityHidden(true)
    }

    private var pill: some View {
        let (dot, name): (Color, String) = {
            switch status {
            case .working(let name): return (.green, name)
            case .stopped(let name): return (.gray, name)
            case .black: return (.orange, SettingsText.string("settings.connection.source.card", locale))
            case .noCard: return (.orange, SettingsText.string("settings.card.noCard", locale))
            case .searching: return (.orange, SettingsText.string("settings.card.searching", locale))
            case .noPermission: return (.orange, SettingsText.string("settings.card.noPermission", locale))
            }
        }()
        return HStack(spacing: 6) {
            Circle().fill(dot).frame(width: 7, height: 7)
            Text(verbatim: name).font(.system(size: 11, weight: .semibold)).lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .frame(height: 24)
        .background(Capsule().fill(Color.black.opacity(0.5)))
    }

    @ViewBuilder private var statusRow: some View {
        switch status {
        case .working:
            Label { SText("settings.card.working") } icon: { Image(systemName: NinoSymbol.okFill) }
                .font(.nino(.callout)).foregroundStyle(NinoColor.success)
        case .black, .stopped:
            NinoErrorLabel(SettingsText.string("settings.card.black", locale))
        case .noPermission:
            NinoErrorLabel(SettingsText.string("settings.card.permission", locale))
            Button {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                    NSWorkspace.shared.open(url)
                }
            } label: { SText("settings.card.openCameraSettings") }
                .buttonStyle(.nino(.secondary))
        case .noCard:
            NinoErrorLabel(SettingsText.string("settings.card.plugIn", locale))
        case .searching:
            EmptyView()
        }
    }
}

/// Bağlantı rehberi sayfası (720×700). Rehberin sayfaları kurulum ekranındadır (kurulum.md §10);
/// burada kart denetimi ve kapatma düğmesi durur.
struct CaptureCardGuideSheet: View {
    let state: AppState
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: NinoSpacing.l) {
            HStack {
                SText("settings.connection.guide").font(.ninoRounded(28, weight: .bold))
                Spacer()
                Button(action: close) { SText("settings.guide.cancel") }
                    .buttonStyle(.nino(.primary))
                    .keyboardShortcut(.defaultAction)
            }
            SHint("settings.connection.guideHelp")
            CardCheckView(state: state, height: 220)
            Spacer(minLength: 0)
        }
        .padding(NinoSpacing.xl)
        .frame(width: 720, height: 700)
        .ninoScreen()
    }
}

// MARK: - PS5 giriş şifresi (§5)

struct PasscodeSettings: View {
    let state: AppState
    @State private var code = ""
    @State private var invalid = false
    @Environment(\.locale) private var locale

    var body: some View {
        NinoCard {
            SHint("settings.passcode.hint")
            if state.settingsStatus.passcodeSaved {
                HStack {
                    SText("settings.passcode.saved")
                    Spacer()
                    Button {
                        state.removePS5Passcode()
                    } label: { SText("settings.passcode.remove") }
                        .buttonStyle(.nino(.secondary))
                }
            } else {
                HStack(spacing: NinoSpacing.s) {
                    SettingsField(placeholder: SettingsText.string("settings.passcode.placeholder", locale),
                                  text: $code, secure: true, onSubmit: save)
                        .frame(maxWidth: 220)
                    Button(action: save) { SText("settings.passcode.save") }
                        .buttonStyle(.nino(.secondary))
                        .disabled(code.trimmingCharacters(in: .whitespaces).isEmpty)
                    Spacer(minLength: 0)
                }
                if invalid {
                    SText("settings.passcode.invalid").font(.nino(.callout)).foregroundStyle(NinoColor.textSecondary)
                }
            }
        }
    }

    private func save() {
        guard let valid = SettingsRules.passcode(code) else {
            invalid = true
            return
        }
        invalid = false
        state.savePS5Passcode(valid)
        code = ""
    }
}
