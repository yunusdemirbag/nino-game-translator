// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import SwiftUI

enum AppInfo {
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "" }
    static var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "" }
    static let privacyURL = URL(string: "https://github.com/yunusdemirbag/nino-game-translator#gizlilik")!
    static let helpURL = URL(string: "https://github.com/yunusdemirbag/nino-game-translator/issues")!
    static let sourceURL = URL(string: "https://github.com/yunusdemirbag/nino-game-translator")!
}

/// Profil: cihazlar, tercihler, yardım.
struct ProfileScreen: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Binding var path: [Route]
    @State private var askNino = false
    @State private var report = false

    var body: some View {
        NinoScreen {
            BackHeader(L("settings.profile"), onBack: { dismiss() })
        } content: {
            Tile {
                HStack(spacing: DS.Space.gap) {
                    NinoLogo(size: 56)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: "Nino Game Translator").font(DS.Font.title)
                        Text(L("engine.apple.detail")).font(DS.Font.caption).foregroundStyle(DS.Palette.secondary)
                    }
                }
            }
            BentoGrid {
                Button { path.append(.target) } label: {
                    ValueTile(symbol: "tv", tone: .ok, label: L("settings.devices"),
                              value: L("devices.counts", model.consolePaired ? 1 : 0, model.hasPairedTV ? 1 : 0))
                }
                .buttonStyle(.plain)
                Button { path.append(.psn) } label: {
                    ValueTile(symbol: "person.2.fill", label: L("settings.psn"),
                              value: model.accountID == nil ? L("devices.status.notsetup") : L("signin.status.done"))
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(DS.Palette.text)
            Tile(spacing: 0) {
                navRow("gamecontroller.fill", L("devices.console"), detail: model.isXbox ? "Xbox (Beta)" : "PlayStation 5") { path.append(.platform) }
                RowDivider()
                navRow("gamecontroller", model.isXbox ? L("settings.xbox") : L("settings.ps5"),
                       detail: model.isXbox ? model.xboxConsole?.name : model.console?.name) { path.append(.ps5) }
                RowDivider()
                navRow("tv", L("settings.target"), detail: targetDetail) { path.append(.target) }
            }
            Tile(spacing: 0) {
                toggleRow(L("settings.notifications"), L("packs.updates"), $model.notifyPackUpdates)
                RowDivider()
                toggleRow(L("settings.ps5.connection"), L("settings.notify.drop"),
                          Binding(get: { model.notifyDisconnect }, set: { on in
                              model.notifyDisconnect = on
                              if on { ConnectionAlert.requestPermission() }
                          }))
                RowDivider()
                toggleRow(L("settings.pool.contribute"), L("settings.pool.detail"), $model.settings.sharePool)
                RowDivider()
                toggleRow(L("ask.suggest.whichgame"),
                          L("settings.gameask.detail"), $model.settings.askGame)
                RowDivider()
                toggleRow(L("settings.speaker"),
                          L("settings.speaker.detail"),
                          $model.settings.showSpeakerNames)
                RowDivider()
                toggleRow(L("settings.read.fastcheck"),
                          L("settings.read.fastcheck.detail"),
                          $model.settings.fastSubtitleDetection)
                if model.isXbox {
                    RowDivider()
                    toggleRow(L("xbox.audio.toggle"),
                              L("xbox.audio.detail"),
                              $model.settings.xboxAudioOnDevice)
                    RowDivider()
                    toggleRow(L("xbox.lowres.toggle"),
                              L("xbox.lowres.detail"),
                              $model.settings.xboxLowResolution)
                }
            }
            HelpLinks(askNino: $askNino, report: $report) { path.append(.about) }
            Text(verbatim: "Nino Game Translator \(AppInfo.version) · © 2026 Yunus Demirbağ · AGPL-3.0")
                .font(DS.Font.caption)
                .foregroundStyle(DS.Palette.secondary)
                .frame(maxWidth: .infinity)
        }
        .sheet(isPresented: $askNino) { AskNinoSheet() }
        .sheet(isPresented: $report) { ReportProblemSheet() }
    }

    private var targetDetail: String {
        if model.settings.output.showsOnPhone { return L("devices.thisphone") }
        if let tv = model.tv, model.hasPairedTV { return tv.name.isEmpty ? "TV" : tv.name }
        return L("devices.status.notsetup")
    }

    private func navRow(_ symbol: String, _ title: String, detail: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ListRow(symbol: symbol, title: title, detail: detail) { RowChevron() }
        }
        .buttonStyle(.plain)
    }

    private func toggleRow(_ title: String, _ detail: String, _ value: Binding<Bool>) -> some View {
        Toggle(isOn: value) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(DS.Font.headline)
                Text(detail).font(DS.Font.caption).foregroundStyle(DS.Palette.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(DS.Palette.accent)
        .padding(.vertical, 12)
    }
}

/// Yardım satırları: gizlilik, yardım, Nino'ya Sor, Sorun Bildir, Hakkında.
struct HelpLinks: View {
    @Environment(\.openURL) private var openURL
    @Binding var askNino: Bool
    @Binding var report: Bool
    let onAbout: () -> Void

    var body: some View {
        Tile(spacing: 0) {
            row("hand.raised", L("settings.privacy")) { openURL(AppInfo.privacyURL) }
            RowDivider()
            row("questionmark.circle", L("settings.help")) { openURL(AppInfo.helpURL) }
            RowDivider()
            row("bubble.left.and.text.bubble.right", L("ask.title")) { askNino = true }
            RowDivider()
            row("exclamationmark.bubble", L("report.title")) { report = true }
            RowDivider()
            row("info.circle", L("settings.about"), detail: AppInfo.version, action: onAbout)
        }
    }

    private func row(_ symbol: String, _ title: String, detail: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ListRow(symbol: symbol, title: title, detail: detail) { RowChevron() }
        }
        .buttonStyle(.plain)
    }
}

/// Hakkında.
struct AboutScreen: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NinoScreen {
            BackHeader(L("settings.about"), onBack: { dismiss() })
        } content: {
            Tile {
                NinoLogo(size: 56)
                Text(verbatim: "Nino Game Translator \(AppInfo.version)").font(DS.Font.title)
                Text(verbatim: "Nino © 2026 Yunus Demirbağ").font(DS.Font.caption).foregroundStyle(DS.Palette.secondary)
                Text(L("about.license"))
                    .font(DS.Font.body).foregroundStyle(DS.Palette.secondary)
                Link(L("about.source"), destination: AppInfo.sourceURL).font(DS.Font.headline).foregroundStyle(DS.Palette.accent)
            }
        }
    }
}
