// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import SwiftUI

/// Geçmiş (gecmis-hakkinda-saglik.md §1): son 200 çevrilen satır, kopyala ve temizle.
public struct HistorySheet: View {
    private let state: AppState
    private let height: CGFloat
    @State private var confirmClear = false
    @Environment(\.locale) private var locale

    /// - Parameter windowHeight: Ana pencerenin yüksekliği; sayfa ondan iki "screen" boşluğu eksik.
    public init(state: AppState, windowHeight: CGFloat = NinoSize.windowHeight) {
        self.state = state
        height = windowHeight - 2 * NinoSpacing.xl
    }

    public var body: some View {
        let entries = state.history
        VStack(alignment: .leading, spacing: NinoSpacing.l) {
            ShText("sheets.history.title").font(.nino(.display))
            NinoHint(SheetsText.string("sheets.history.hint %lld", locale, HistoryStore.limit))
            if entries.isEmpty {
                Spacer(minLength: 0)
                NinoHint(SheetsText.string("sheets.history.empty", locale))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
            } else {
                SheetScroll {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                            if index > 0 { Divider().overlay(NinoColor.tileBorder) }
                            HistoryRow(entry: entry)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ninoTile(padding: NinoSpacing.l)
            }
            HStack(spacing: NinoSpacing.m) {
                CopyFeedbackButton(titleKey: "sheets.history.copyAll", copiedKey: "sheets.common.copied") {
                    HistoryStore.plainText(state.history)
                }
                .disabled(entries.isEmpty)
                Button {
                    confirmClear = true
                } label: {
                    ShText("sheets.history.clear")
                }
                .buttonStyle(.nino(.danger))
                .disabled(entries.isEmpty)
                Spacer(minLength: 0)
                Button {
                    state.activeSheet = nil
                } label: {
                    ShText("sheets.common.done")
                }
                .buttonStyle(.nino(.primary, size: .large))
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(NinoSpacing.xl)
        .frame(width: 640, height: height)
        .ninoScreen()
        .alert(SheetsText.string("sheets.history.clearTitle", locale), isPresented: $confirmClear) {
            Button(SheetsText.string("sheets.history.clear", locale), role: .destructive) { state.clearHistory() }
            Button(SheetsText.string("sheets.common.cancel", locale), role: .cancel) {}
        } message: {
            Text(SheetsText.string("sheets.history.clearMessage", locale))
        }
    }
}

struct HistoryRow: View {
    let entry: HistoryEntry
    @State private var justCopied = false
    @Environment(\.locale) private var locale

    var body: some View {
        HStack(alignment: .top, spacing: NinoSpacing.m) {
            VStack(alignment: .leading, spacing: NinoSpacing.xs) {
                Text(verbatim: header)
                    .font(.nino(.caption).monospacedDigit())
                    .foregroundStyle(NinoColor.textSecondary)
                Text(entry.translated)
                    .fixedSize(horizontal: false, vertical: true)
                Text(entry.source)
                    .font(.nino(.callout))
                    .foregroundStyle(NinoColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                Pasteboard.copy(HistoryStore.clipboardText(entry))
                justCopied = true
            } label: {
                Image(systemName: justCopied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(justCopied ? NinoColor.success : NinoColor.textSecondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(SheetsText.string(justCopied ? "sheets.common.copied" : "sheets.history.copy", locale))
            .accessibilityLabel(SheetsText.string(justCopied ? "sheets.common.copied" : "sheets.history.copy", locale))
        }
        .padding(.vertical, NinoSpacing.m)
    }

    private var header: String {
        var text = HistoryStore.timeText(entry.date)
        switch entry.origin {
        case .pack: text += " · " + SheetsText.string("sheets.history.originPack", locale)
        case .engine: text += " · " + SheetsText.string("sheets.history.originEngine", locale)
        case nil: break
        }
        return text
    }
}
