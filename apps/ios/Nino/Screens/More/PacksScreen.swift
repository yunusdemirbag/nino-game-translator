// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import SwiftUI

/// Oyun paketleri: hazır Türkçe çeviriler; oyun başına açılıp kapanır.
struct PacksScreen: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var updating = false

    var body: some View {
        NinoScreen {
            BackHeader(L("settings.packs"), onBack: { dismiss() }) { TagLabel(text: L("engine.price.free")) }
        } content: {
            Text(L("packs.auto.note"))
                .font(DS.Font.body).foregroundStyle(DS.Palette.secondary)
            Tile {
                if !Languages.isTurkish(model.settings.targetLanguage) {
                    Text(L("packs.turkishonly"))
                        .font(DS.Font.caption).foregroundStyle(DS.Palette.secondary)
                }
                Toggle(isOn: $model.settings.gamePacks) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("settings.packs.toggle")).font(DS.Font.headline)
                        Text(summary).font(DS.Font.caption).foregroundStyle(DS.Palette.secondary)
                    }
                }
                .tint(DS.Palette.accent)
            }
            if !model.packs.packs.isEmpty {
                Text(L("packs.toggle.hint")).font(DS.Font.caption).foregroundStyle(DS.Palette.secondary)
                BentoGrid {
                    ForEach(model.packs.packs) { pack in packTile(pack) }
                }
            }
            Tile {
                HStack(spacing: DS.Space.gap) {
                    TileSymbol(symbol: "arrow.down.circle")
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("packs.comingsoon")).font(DS.Font.headline)
                        Text(L("packs.updates.detail")).font(DS.Font.caption).foregroundStyle(DS.Palette.secondary)
                    }
                }
            }
        } footer: {
            Button {
                updating = true
                Task {
                    await model.updatePacksNow()
                    updating = false
                }
            } label: {
                HStack(spacing: 8) {
                    if updating { ProgressView().tint(DS.Palette.text) }
                    Text(L("packs.updateNow"))
                }
            }
            .buttonStyle(.secondary)
            .disabled(updating || NinoServer.base == nil)
        }
        .task { if model.packs.packs.isEmpty { await model.loadPacks() } }
    }

    private var summary: String {
        let lines = model.packs.totalLines
        let lineText = lines >= 1000 ? L("packs.count.klines", lines / 1000) : L("packs.count.lines", lines)
        return [L("packs.count.games", model.packs.packs.count), lineText, L("packs.offline")].joined(separator: " · ")
    }

    private func packTile(_ pack: GamePack) -> some View {
        let off = model.disabledPacks.contains(pack.id)
        let playing = model.isRunning && model.playingPack == pack.title
        let lines = pack.lineCount >= 1000 ? L("packs.count.klines", pack.lineCount / 1000) : L("packs.count.lines", pack.lineCount)
        return Button { model.togglePack(pack.id) } label: {
            Tile(selected: playing) {
                HStack(alignment: .top) {
                    GameBadge(text: pack.monogram)
                    Spacer(minLength: 0)
                    if playing {
                        StatusLabel(text: L("home.nowplaying"), dotColor: DS.Palette.success)
                    } else if off {
                        TagLabel(text: L("common.off"))
                    }
                }
                Spacer(minLength: 8)
                Text(verbatim: pack.title).font(DS.Font.headline).lineLimit(2)
                Text(lines).font(DS.Font.caption).foregroundStyle(DS.Palette.secondary)
            }
            .opacity(off || !model.settings.gamePacks ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .foregroundStyle(DS.Palette.text)
        .accessibilityValue(Text(off ? L("common.off") : L("common.on")))
    }
}
