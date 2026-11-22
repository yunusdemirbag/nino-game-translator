// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import SwiftUI

/// Xbox bağlantı listesi (kurulum.md §11): hoş geldin'in Xbox hâlinde ve ana ekrandaki "Xbox'ı Bağla"
/// penceresinde aynı. Liste görünürken motor Xbox durumunu saniyede bir yoklar.
public struct XboxConnectList: View {
    private let state: AppState
    @Environment(\.locale) private var locale
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(state: AppState) {
        self.state = state
    }

    private var link: XboxLink { state.setup.xbox }

    public var body: some View {
        VStack(spacing: NinoSpacing.s) {
            manualRow
            row(.install, symbol: "arrow.down.app.fill",
                title: link.greenlightInstalled ? "setup.xboxList.install.done" : "setup.xboxList.install",
                detail: "setup.xboxList.install.detail") { installButtons }
            row(.signIn, symbol: "person.crop.circle.badge.checkmark",
                title: link.signedIn || link.step > .signIn ? "setup.xboxList.signIn.done" : "setup.xboxList.signIn",
                detail: "setup.xboxList.signIn.detail") { signInButtons }
            row(.start, symbol: "play.tv.fill",
                title: link.streaming ? "setup.xboxList.start.done" : "setup.xboxList.start",
                detail: link.streaming ? "setup.xboxList.start.doneDetail" : "setup.xboxList.start.detail",
                showDetailWhenDone: true) { startButtons }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.85), value: link)
        .onAppear { state.setXboxPolling(true) }
        .onDisappear { state.setXboxPolling(false) }
    }

    // MARK: Satırlar

    /// Birinci satır her zaman "elle" satırıdır: gri rozet, düğme yok, açıklama görünür.
    private var manualRow: some View {
        HStack(alignment: .top, spacing: NinoSpacing.m) {
            badge(number: 1, kind: .later)
            VStack(alignment: .leading, spacing: 3) {
                Label { KText("setup.xboxList.remote") } icon: {
                    Image(systemName: "antenna.radiowaves.left.and.right").foregroundStyle(NinoColor.accentText)
                }
                .font(.nino(.headline))
                NinoHint(SetupText.string("setup.xboxList.remote.detail", locale))
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ninoTile(padding: NinoSpacing.m)
    }

    private enum BadgeKind { case done, current, later }

    private func row<Buttons: View>(_ step: XboxLink.Step, symbol: String, title: String, detail: String,
                                    showDetailWhenDone: Bool = false,
                                    @ViewBuilder buttons: () -> Buttons) -> some View {
        let current = link.step
        let kind: BadgeKind = step < current ? .done : (step == current ? .current : .later)
        let isDone = kind == .done || (step == .start && current == .done)
        let later = kind == .later
        return HStack(alignment: .top, spacing: NinoSpacing.m) {
            badge(number: step.rawValue, kind: isDone ? .done : kind)
            VStack(alignment: .leading, spacing: 3) {
                Label { KText(title) } icon: {
                    Image(systemName: symbol).foregroundStyle(later ? NinoColor.textSecondary : NinoColor.accentText)
                }
                .font(.nino(.headline))
                if !isDone || showDetailWhenDone { NinoHint(SetupText.string(detail, locale)) }
                if kind == .current {
                    buttons().padding(.top, NinoSpacing.xs)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ninoTile(padding: NinoSpacing.m)
        .overlay {
            if kind == .current {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(NinoColor.accent.opacity(0.7), lineWidth: 1.5)
            }
        }
        .opacity(later ? 0.55 : 1)
    }

    private func badge(number: Int, kind: BadgeKind) -> some View {
        ZStack {
            Circle().fill(badgeFill(kind))
            if kind == .done {
                Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
            } else {
                Text(verbatim: "\(number)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(kind == .current ? AnyShapeStyle(Color.white) : AnyShapeStyle(NinoColor.textSecondary))
            }
        }
        .frame(width: 26, height: 26)
    }

    private func badgeFill(_ kind: BadgeKind) -> AnyShapeStyle {
        switch kind {
        case .done: return AnyShapeStyle(NinoColor.success)
        case .current: return AnyShapeStyle(NinoColor.accent)
        case .later: return AnyShapeStyle(NinoColor.textSecondary.opacity(0.18))
        }
    }

    // MARK: Düğmeler

    @ViewBuilder private var installButtons: some View {
        if let progress = link.installProgress {
            VStack(alignment: .leading, spacing: NinoSpacing.xs) {
                // Düz çubuk (ImageRenderer sistemin ilerleme çubuğunu çizemiyor).
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(NinoColor.textSecondary.opacity(0.2))
                        Capsule().fill(NinoColor.accent)
                            .frame(width: proxy.size.width * min(max(progress, 0), 1))
                    }
                }
                .frame(maxWidth: 320)
                .frame(height: 6)
                Text(SetupText.string("setup.xboxList.installing %lld", locale, Int((progress * 100).rounded())))
                    .font(.nino(.callout).monospacedDigit())
                    .foregroundStyle(NinoColor.textSecondary)
            }
        } else {
            VStack(alignment: .leading, spacing: NinoSpacing.xs) {
                Button { state.installGreenlight() } label: {
                    Label { KText("setup.xboxList.install") } icon: { Image(systemName: "arrow.down.circle.fill") }
                }
                .buttonStyle(.nino(.primary))
                if let error = link.installError {
                    Text(error).font(.system(size: 12)).foregroundStyle(NinoColor.danger)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(SetupText.string("setup.xboxList.install.note", locale))
                        .font(.system(size: 12))
                        .foregroundStyle(NinoColor.textSecondary)
                }
            }
        }
    }

    private var signInButtons: some View {
        HStack(spacing: NinoSpacing.s) {
            Button { state.openGreenlight() } label: {
                Label { KText("setup.xboxList.openGreenlight") } icon: { Image(systemName: "play.fill") }
            }
            .buttonStyle(.nino(.primary))
            Button { openURL(SetupLinks.microsoftLink) } label: {
                Label { KText("setup.xboxList.openLink") } icon: { Image(systemName: "arrow.up.right.square") }
            }
            .buttonStyle(.nino(.secondary))
        }
    }

    private var startButtons: some View {
        Button { state.openGreenlight() } label: {
            Label { KText("setup.xboxList.goToGreenlight") } icon: { Image(systemName: "arrow.right.circle.fill") }
        }
        .buttonStyle(.nino(.primary))
    }
}
