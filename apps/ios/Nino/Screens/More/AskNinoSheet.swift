// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import SwiftUI

/// "Nino'ya Sor" sohbeti (uygulama açık kaldıkça bellekte durur).
@MainActor
final class AssistantChat: ObservableObject {
    static let shared = AssistantChat()

    struct Message: Identifiable, Equatable {
        enum Role: String { case user, assistant, error }
        let id = UUID()
        let role: Role
        let text: String
        var reportSent = false
        var offersReport = false
        var failed = false
    }

    @Published var messages: [Message] = []
    @Published var waiting = false
    private var task: Task<Void, Never>?

    func reset() {
        task?.cancel()
        waiting = false
        messages = []
    }

    func send(_ text: String, model: AppModel) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !waiting else { return }
        messages.removeAll { $0.role == .error }
        messages.append(Message(role: .user, text: trimmed))
        request(model: model)
    }

    func retry(model: AppModel) {
        guard let i = messages.lastIndex(where: { $0.role == .user }) else { return }
        messages[i].failed = false
        messages.removeAll { $0.role == .error }
        request(model: model)
    }

    private func request(model: AppModel) {
        waiting = true
        let history = messages.filter { $0.role != .error && !$0.failed }.suffix(24).map {
            ["role": $0.role.rawValue, "text": String($0.text.prefix(2000))]
        }
        let body: [String: Any] = ["v": 1, "install": NinoServer.installID(folders: model.folders), "app": AppInfo.version,
                                   "platform": "ios", "language": Loc.language, "messages": Array(history),
                                   "device": DeviceInfo.summary(model)]
        task = Task {
            defer { waiting = false }
            do {
                let reply = try await NinoServer.post("v1/assistant", body: body, agent: "nino-assistant/1", timeout: 90)
                guard let text = reply["reply"] as? String, !text.isEmpty else { throw NinoServer.Failure.server }
                messages.append(Message(role: .assistant, text: text, reportSent: (reply["report"] as? String) != nil))
            } catch {
                let f = error as? NinoServer.Failure ?? .server
                let retryable = [.busy, .offline, .server].contains(f)
                if retryable, let i = messages.lastIndex(where: { $0.role == .user }) { messages[i].failed = true }
                messages.append(Message(role: .error, text: Self.text(f), offersReport: f == .notReady || f == .tooMany))
            }
        }
    }

    private static func text(_ f: NinoServer.Failure) -> String {
        switch f {
        case .notReady: L("ask.error.notready")
        case .tooMany: L("ask.error.dailylimit")
        case .busy: L("ask.error.busy")
        case .tooLarge: L("ask.error.toolarge")
        case .rejected: L("ask.error.unreadable")
        case .offline, .server: L("ask.error.network")
        }
    }
}

struct AskNinoSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var chat = AssistantChat.shared
    @State private var draft = ""
    @State private var report = false

    private var suggestions: [String] {
        [L("setup.combo.tvphone"), L("setup.combo.monitor"), L("setup.combo.xbox"), L("ask.suggest.tvinstall")]
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        botBubble(L("ask.greeting"))
                        if chat.messages.isEmpty {
                            FlowLayout(spacing: 8) {
                                ForEach(suggestions, id: \.self) { s in
                                    Button { chat.send(s, model: model) } label: {
                                        Text(s)
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle(DS.Palette.accent)
                                            .padding(.horizontal, 14).padding(.vertical, 9)
                                            .background(Capsule().fill(Color.white.opacity(0.9)))
                                            .overlay(Capsule().strokeBorder(DS.Palette.accent.opacity(0.3), lineWidth: 1))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.leading, 36)
                        }
                        ForEach(chat.messages) { m in message(m) }
                        if chat.waiting {
                            HStack(alignment: .bottom, spacing: 8) {
                                BotFace(size: 28, thinking: true)
                                TypingDots().padding(.horizontal, 14).padding(.vertical, 14).background(bubbleBackground)
                                    .accessibilityLabel(Text(L("ask.typing")))
                            }
                        }
                        Color.clear.frame(height: 1).id("end")
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: chat.messages.count) { _, _ in withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo("end") } }
                .onChange(of: chat.waiting) { _, _ in withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo("end") } }
                .onAppear { proxy.scrollTo("end") }
            }
            composer
        }
        .background(ScreenBackground())
        .foregroundStyle(DS.Palette.text)
        .presentationBackground(DS.Palette.bg)
        .sheet(isPresented: $report) { ReportProblemSheet() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            BotFace(size: 42, thinking: chat.waiting)
                .frame(width: 50, height: 50)
                .background(Circle().fill(Color.white.opacity(0.95)))
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "Nino").font(.headline)
                Text(L("settings.setuphelper")).font(.subheadline).foregroundStyle(DS.Palette.secondary)
            }
            Spacer(minLength: 0)
            if !chat.messages.isEmpty {
                SquareIconButton(symbol: "square.and.pencil", label: L("ask.newchat")) { chat.reset() }
            }
            SquareIconButton(symbol: "xmark", label: L("common.close.alt")) { dismiss() }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 8)
    }

    private var bubbleBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.92))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(DS.Palette.border, lineWidth: 1))
    }

    private func botBubble(_ text: String, offersReport: Bool = false) -> some View {
        HStack(alignment: .bottom, spacing: 8) {
            BotFace(size: 28)
            VStack(alignment: .leading, spacing: 10) {
                Text(LocalizedStringKey(text)).font(DS.Font.body).textSelection(.enabled)
                if offersReport {
                    Button { report = true } label: {
                        Label(L("report.title"), systemImage: "exclamationmark.bubble")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .background(Capsule().fill(DS.Palette.accent))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(bubbleBackground)
            Spacer(minLength: 32)
        }
    }

    @ViewBuilder private func message(_ m: AssistantChat.Message) -> some View {
        switch m.role {
        case .assistant, .error:
            botBubble(m.text, offersReport: m.offersReport)
            if m.reportSent {
                Label(L("report.status.sent"), systemImage: "checkmark.circle.fill")
                    .font(DS.Font.caption.weight(.semibold)).foregroundStyle(DS.Palette.success)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(DS.Palette.success.opacity(0.12)))
                    .padding(.leading, 36)
            }
        case .user:
            VStack(alignment: .trailing, spacing: 4) {
                HStack {
                    Spacer(minLength: 56)
                    Text(m.text).font(DS.Font.body).foregroundStyle(.white).textSelection(.enabled)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(DS.Palette.accent))
                        .opacity(m.failed ? 0.6 : 1)
                }
                if m.failed {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.circle.fill").foregroundStyle(DS.Palette.danger)
                        Text(L("report.status.failed"))
                        Button(L("common.retry")) { chat.retry(model: model) }.fontWeight(.semibold).disabled(chat.waiting)
                    }
                    .font(DS.Font.caption)
                }
            }
        }
    }

    private var composer: some View {
        let canSend = !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !chat.waiting
        return HStack(alignment: .bottom, spacing: 8) {
            TextField(L("ask.input.placeholder"), text: $draft, axis: .vertical)
                .lineLimit(1...5)
                .font(DS.Font.body)
                .padding(.horizontal, 14).padding(.vertical, 9)
                .frame(minHeight: 40)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.white.opacity(0.95)))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(DS.Palette.borderStrong, lineWidth: 1))
            Button {
                chat.send(draft, model: model)
                draft = ""
            } label: {
                Image(systemName: "arrow.up").font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(canSend ? DS.Palette.accent : DS.Palette.tertiary.opacity(0.5)))
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .accessibilityLabel(Text(L("common.send")))
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(DS.Palette.bg.opacity(0.9).ignoresSafeArea(edges: .bottom))
    }
}
