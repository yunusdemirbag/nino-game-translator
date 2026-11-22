// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import SwiftUI

/// Sorun Bildir taslağı (uygulama açık kaldıkça bellekte durur).
@MainActor
final class ReportDraft: ObservableObject {
    static let shared = ReportDraft()
    @Published var text = ""
    @Published var contact = ""
    @Published var includeLog = true
}

struct ReportProblemSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var draft = ReportDraft.shared
    @State private var sending = false
    @State private var sent = false
    @State private var error: String?

    var body: some View {
        NinoScreen {
            HStack {
                Text(L("report.title")).font(DS.Font.title)
                Spacer(minLength: 0)
                SquareIconButton(symbol: "xmark", label: L("common.close.alt")) { dismiss() }
            }
            .frame(height: DS.Size.icon)
        } content: {
            if sent {
                Tile {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 28)).foregroundStyle(DS.Palette.success)
                        Text(L("report.thanks")).font(DS.Font.headline)
                    }
                }
            } else {
                Tile {
                    Text(L("report.noticed")).font(DS.Font.headline)
                    Text(L("report.noissue"))
                        .font(DS.Font.caption).foregroundStyle(DS.Palette.secondary)
                    Button(L("settings.sendproblems")) { Task { await send(userText: "") } }
                        .buttonStyle(.secondary).disabled(sending)
                }
                Tile {
                    Text(L("report.more.title")).font(DS.Font.headline)
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $draft.text)
                            .scrollContentBackground(.hidden)
                            .font(DS.Font.body)
                            .padding(.horizontal, 8)
                            .frame(minHeight: 130)
                            .background(RoundedRectangle(cornerRadius: DS.Radius.control).fill(DS.Palette.surface2))
                            .overlay(RoundedRectangle(cornerRadius: DS.Radius.control).strokeBorder(DS.Palette.border, lineWidth: 1))
                            .onChange(of: draft.text) { _, _ in error = nil }
                        if draft.text.isEmpty {
                            Text(L("report.description.placeholder"))
                                .font(DS.Font.body).foregroundStyle(DS.Palette.tertiary)
                                .padding(.horizontal, 13).padding(.vertical, 8)
                                .allowsHitTesting(false)
                        }
                    }
                }
                Tile {
                    Text(L("report.contact.title")).font(DS.Font.headline)
                    TextField(L("report.contact.placeholder"), text: $draft.contact)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textFieldStyle(NinoFieldStyle())
                    RowDivider()
                    Toggle(isOn: $draft.includeLog) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L("report.log.include")).font(DS.Font.headline)
                            Text(L("report.log.note"))
                                .font(DS.Font.caption).foregroundStyle(DS.Palette.secondary)
                        }
                    }
                    .tint(DS.Palette.accent)
                }
                Tile {
                    Toggle(isOn: $model.settings.autoReport) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L("settings.autoreport")).font(DS.Font.headline)
                            Text(L("settings.autoreport.detail"))
                                .font(DS.Font.caption).foregroundStyle(DS.Palette.secondary)
                        }
                    }
                    .tint(DS.Palette.accent)
                }
                if let error { NoteLine(text: error) }
                Text(L("report.privacy.note"))
                    .font(DS.Font.caption).foregroundStyle(DS.Palette.secondary)
            }
        } footer: {
            if !sent {
                Button { Task { await send(userText: draft.text) } } label: {
                    HStack(spacing: 8) {
                        if sending { ProgressView().tint(.white) }
                        Text(sending ? L("report.status.sending") : L("common.send"))
                    }
                }
                .buttonStyle(.primary)
                .disabled(sending)
            }
        }
        .disabled(sending)
        .presentationBackground(DS.Palette.bg)
    }

    private func send(userText: String) async {
        sending = true
        error = nil
        defer { sending = false }
        let typed = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        var text = typed.isEmpty ? "[Elle gönderildi] Açıklama yazılmadı; Nino'nun gördükleri aşağıda." : typed
        text += "\n\n— Nino'nun gördükleri —"
        var body: [String: Any] = ["v": 1, "install": NinoServer.installID(folders: model.folders), "app": AppInfo.version,
                                   "platform": "ios", "language": Languages.normalized(model.settings.targetLanguage),
                                   "text": String(text.prefix(4000)),
                                   "device": DeviceInfo.summary(model)]
        let contact = draft.contact.trimmingCharacters(in: .whitespacesAndNewlines)
        if !contact.isEmpty { body["contact"] = String(contact.prefix(200)) }
        do {
            _ = try await NinoServer.post("v1/reports", body: body, agent: "nino-report/1", timeout: 120)
            sent = true
            try? await Task.sleep(for: .milliseconds(1600))
            draft.text = ""
            draft.contact = ""
            dismiss()
        } catch {
            switch error as? NinoServer.Failure ?? .server {
            case .tooMany: self.error = L("report.error.dailylimit")
            case .offline: self.error = L("report.error.network")
            case .tooLarge: self.error = L("report.error.toolarge")
            default: self.error = L("report.error.generic")
            }
        }
    }
}
