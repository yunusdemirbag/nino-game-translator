// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import SwiftUI
import UIKit

/// Geçmiş: çevrilen son 200 satır, en yenisi üstte.
struct HistoryScreen: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false
    @State private var confirmClear = false

    var body: some View {
        NinoScreen {
            BackHeader(L("settings.history"), onBack: { dismiss() })
        } content: {
            Text(L("history.limit", SubtitleHistory.limit))
                .font(DS.Font.caption).foregroundStyle(DS.Palette.secondary)
            if model.history.entries.isEmpty {
                Text(L("history.empty"))
                    .font(DS.Font.body).foregroundStyle(DS.Palette.secondary)
            } else {
                Tile(spacing: 0) {
                    ForEach(Array(model.history.entries.enumerated()), id: \.element.id) { i, entry in
                        if i > 0 { RowDivider() }
                        row(entry)
                    }
                }
            }
        } footer: {
            if !model.history.entries.isEmpty {
                HStack(spacing: DS.Space.gap) {
                    Button {
                        UIPasteboard.general.string = model.history.entries
                            .map { "\($0.translation)\n\($0.source)" }.joined(separator: "\n\n")
                        copied = true
                    } label: {
                        Label(copied ? L("common.copied") : L("common.copyall"), systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(.secondary)
                    Button { confirmClear = true } label: { Label(L("common.clear"), systemImage: "trash") }
                        .buttonStyle(.danger)
                }
            }
        }
        .confirmationDialog(L("history.clear.confirm"), isPresented: $confirmClear, titleVisibility: .visible) {
            Button(L("common.clear"), role: .destructive) { model.clearHistory() }
        } message: {
            Text(L("history.clear.note"))
        }
    }

    private func row(_ entry: SubtitleHistory.Entry) -> some View {
        let pack = entry.origin == .pack
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 0) {
                Text(entry.date.formatted(date: .omitted, time: .standard))
                Text(verbatim: " · ")
                Text(pack ? L("packs.pack") : L("settings.engine")).foregroundStyle(pack ? DS.Palette.pro : DS.Palette.tertiary)
            }
            .font(DS.Font.caption.monospacedDigit())
            .foregroundStyle(DS.Palette.tertiary)
            Text(verbatim: TextDirection.prepared(entry.translation))
                .font(DS.Font.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .subtitleDirection(for: entry.translation, fill: true)
            Text(verbatim: entry.source).font(DS.Font.caption).foregroundStyle(DS.Palette.secondary)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .contextMenu {
            Button { UIPasteboard.general.string = "\(entry.translation)\n\(entry.source)" } label: {
                Label(L("common.copy"), systemImage: "doc.on.doc")
            }
        }
    }
}
