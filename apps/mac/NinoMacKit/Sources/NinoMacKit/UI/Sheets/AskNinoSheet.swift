// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Nino'ya Sor sohbet sayfası (ninoya-sor.md §3): 540 × 660, başlık, mesajlar, yazma alanı.
/// Sohbet uygulama açık kaldıkça `SheetsStatus.chat`'te durur.
public struct AskNinoSheet: View {
    private let state: AppState
    @State private var dropTargeted = false
    @FocusState private var inputFocused: Bool
    @Environment(\.locale) private var locale

    public init(state: AppState) { self.state = state }

    /// Sohbetin en altındaki boş işaret: yeni ileti gelince buraya kaydırılır.
    private static let tailAnchor = "chat.tail"

    private var chat: AssistantChat { state.sheetsStatus.chat }

    /// Öneri haplarının anahtarları (dokununca arayüz dilindeki metni gönderilir).
    static let suggestionKeys = ["sheets.ask.suggest.ps5TVPhone", "sheets.ask.suggest.ps5MonitorComputer",
                                 "sheets.ask.suggest.xboxTV", "sheets.ask.suggest.tvApp"]

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(NinoColor.tileBorder)
            if chat.mode == .report {
                SheetScroll {
                    ReportProblemForm(state: state) { chat.mode = .chat }
                        .padding(NinoSpacing.xl)
                }
            } else {
                messages
                    .overlay {
                        if dropTargeted {
                            NinoRadius.shape(NinoRadius.card)
                                .strokeBorder(NinoColor.accent, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                                .padding(NinoSpacing.s)
                                .allowsHitTesting(false)
                        }
                    }
                composer
            }
        }
        .frame(width: 540, height: 660)
        .ninoScreen()
        .modifier(DropIfInteractive(isTargeted: $dropTargeted) { providers in
            guard chat.mode == .chat, chat.canAddPhoto else { return false }
            load { await PhotoLoader.load(providers: providers, limit: PhotoAttachment.maxCount - chat.attachments.count) }
            return true
        })
        .onAppear { inputFocused = true }
    }

    // MARK: Başlık

    private var header: some View {
        HStack(spacing: NinoSpacing.m) {
            if chat.mode == .report {
                Button {
                    chat.mode = .chat
                } label: {
                    Image(systemName: "chevron.left").font(.system(size: 14, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(SheetsText.string("sheets.common.back", locale))
                .accessibilityLabel(SheetsText.string("sheets.common.back", locale))
            }
            NinoBotView(size: 40, thinking: chat.waiting)
                .frame(width: 46, height: 46)
                .background(Circle().fill(Color.white))
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "Nino").font(.nino(.headline))
                ShText(chat.mode == .report ? "sheets.report.title" : "sheets.ask.subtitle")
                    .font(.nino(.caption))
                    .foregroundStyle(NinoColor.textSecondary)
            }
            Spacer(minLength: 0)
            if chat.hasMessages, chat.mode == .chat {
                Button {
                    chat.reset()
                    inputFocused = true
                } label: {
                    Label { ShText("sheets.ask.newChat") } icon: { Image(systemName: "square.and.pencil") }
                }
                .buttonStyle(.nino(.ghost))
            }
            Button {
                state.activeSheet = nil
            } label: {
                ShText("sheets.common.close")
            }
            .buttonStyle(.nino(.secondary))
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, NinoSpacing.xl)
        .padding(.vertical, NinoSpacing.m)
    }

    // MARK: Mesajlar

    private var messages: some View {
        ScrollViewReader { proxy in
            SheetScroll {
                VStack(alignment: .leading, spacing: NinoSpacing.m) {
                    BotBubble(text: SheetsText.string("sheets.ask.greeting", locale))
                    if !chat.hasMessages {
                        FlowLayout(spacing: NinoSpacing.s) {
                            ForEach(Self.suggestionKeys, id: \.self) { key in
                                SuggestionChip(text: SheetsText.string(key, locale)) {
                                    chat.send(text: SheetsText.string(key, locale), using: ask)
                                }
                            }
                        }
                        .padding(.leading, 34)
                    }
                    ForEach(Array(chat.messages.enumerated()), id: \.element.id) { index, message in
                        messageView(message, isLastUser: index == chat.messages.lastIndex { $0.role == .user })
                    }
                    if chat.waiting {
                        BotBubble(typing: true)
                    }
                    Color.clear.frame(height: 1).id(Self.tailAnchor)
                }
                .padding(NinoSpacing.xl)
            }
            .onChange(of: chat.messages.count) { _, _ in followLatest(proxy) }
            .onChange(of: chat.waiting) { _, _ in followLatest(proxy) }
            .onAppear { proxy.scrollTo(Self.tailAnchor, anchor: .bottom) }
        }
    }

    private func followLatest(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.25)) {
            proxy.scrollTo(Self.tailAnchor, anchor: .bottom)
        }
    }

    @ViewBuilder
    private func messageView(_ message: AssistantMessage, isLastUser: Bool) -> some View {
        switch message.role {
        case .user:
            UserBubble(message: message, showRetry: isLastUser && message.failed?.retryable == true,
                       retryDisabled: chat.waiting) {
                chat.retry(using: ask)
            }
        case .assistant:
            if let error = message.localError {
                BotBubble(text: SheetsText.string(Self.errorKey(error), locale),
                          reportButton: error.offersReport ? { chat.mode = .report } : nil)
            } else {
                BotBubble(text: message.text, formatted: true, reportSent: message.reportSent)
            }
        }
    }

    static func errorKey(_ error: AssistantError) -> String {
        switch error {
        case .disabled: return "sheets.ask.error.disabled"
        case .dailyLimit: return "sheets.ask.error.dailyLimit"
        case .busy: return "sheets.ask.error.busy"
        case .tooLarge: return "sheets.ask.error.tooLarge"
        case .rejected: return "sheets.ask.error.rejected"
        case .serverError, .offline, .noAddress: return "sheets.ask.error.offline"
        }
    }

    // MARK: Yazma alanı

    private var composer: some View {
        @Bindable var chat = chat
        return VStack(alignment: .leading, spacing: NinoSpacing.s) {
            if !chat.attachments.isEmpty || chat.preparingPhotos > 0 {
                HStack(spacing: NinoSpacing.s) {
                    ForEach(chat.attachments) { photo in
                        PhotoThumbnail(photo: photo, size: CGSize(width: 64, height: 48), cornerRadius: 8,
                                       closeSize: 16) {
                            chat.removePhoto(photo.id)
                        }
                    }
                    if chat.preparingPhotos > 0 { SheetSpinner() }
                }
            }
            if chat.photoError {
                Label { ShText("sheets.photo.unreadable") } icon: { Image(systemName: "exclamationmark.circle.fill") }
                    .font(.nino(.callout))
                    .foregroundStyle(NinoColor.danger)
            }
            HStack(alignment: .bottom, spacing: NinoSpacing.s) {
                Button(action: choosePhotos) {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(chat.canAddPhoto ? NinoColor.accentText : NinoColor.textSecondary)
                        .frame(width: 36, height: 36)
                        .ninoGlass(in: Circle(), interactive: true)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(!chat.canAddPhoto)
                .help(SheetsText.string("sheets.ask.addScreenshot", locale))
                .accessibilityLabel(SheetsText.string("sheets.ask.addScreenshot", locale))
                inputField(text: $chat.draft)
                Button { chat.send(using: ask) } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(chat.canSend ? AnyShapeStyle(NinoColor.accent)
                                                  : AnyShapeStyle(NinoColor.textSecondary.opacity(0.35))))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(!chat.canSend)
                .accessibilityLabel(SheetsText.string("sheets.ask.send", locale))
            }
        }
        .padding(.horizontal, NinoSpacing.xl)
        .padding(.vertical, NinoSpacing.m)
        .background {
            // ⌘V: panoda resim varsa ek olarak alınır; yazı varsa olağan yapıştırma.
            Button("") { paste() }
                .keyboardShortcut("v", modifiers: .command)
                .opacity(0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func inputField(text: Binding<String>) -> some View {
        Group {
            if state.sheetsStatus.chat.draft.isEmpty, isStaticRendering {
                ShText("sheets.ask.placeholder").foregroundStyle(NinoColor.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TextField(SheetsText.string("sheets.ask.placeholder", locale), text: text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...6)
                    .focused($inputFocused)
                    .onSubmit { chat.send(using: ask) }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(minHeight: 36)
        .ninoGlass(cornerRadius: 18)
    }

    @Environment(\.ninoStaticRendering) private var isStaticRendering

    // MARK: Eylemler

    private var ask: @MainActor ([AssistantMessage]) async -> Result<AssistantReply, AssistantError> {
        let state = state
        return { await state.askAssistant($0) }
    }

    private func choosePhotos() {
        let urls = PhotoLoader.choose()
        guard !urls.isEmpty else { return }
        let room = PhotoAttachment.maxCount - chat.attachments.count
        load { await PhotoLoader.load(urls: Array(urls.prefix(max(0, room)))) }
    }

    private func paste() {
        guard chat.mode == .chat, let found = PhotoLoader.pasteboardImages() else {
            NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
            return
        }
        guard chat.canAddPhoto else { return }
        let room = PhotoAttachment.maxCount - chat.attachments.count
        load {
            let a = await PhotoLoader.load(urls: Array(found.urls.prefix(room)))
            let b = await PhotoLoader.load(datas: Array(found.datas.prefix(max(0, room - a.photos.count))))
            return (a.photos + b.photos, a.failed || b.failed)
        }
    }

    private func load(_ work: @escaping @MainActor () async -> (photos: [PhotoAttachment], failed: Bool)) {
        let chat = chat
        chat.preparingPhotos += 1
        Task { @MainActor in
            let result = await work()
            chat.addPhotos(result.photos)
            chat.photoError = result.failed
            chat.preparingPhotos -= 1
        }
    }
}

// MARK: - Balonlar

struct SuggestionChip: View {
    let text: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.nino(.callout).weight(.medium))
                .foregroundStyle(NinoColor.accentText)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(NinoColor.accentSoft))
                .overlay(Capsule().strokeBorder(NinoColor.accent.opacity(0.35), lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct BotBubble: View {
    var text: String = ""
    var formatted = false
    var typing = false
    var reportSent = false
    var reportButton: (() -> Void)?
    @Environment(\.locale) private var locale

    var body: some View {
        HStack(alignment: .top, spacing: NinoSpacing.s) {
            NinoBotView(size: 26, blinks: typing, thinking: typing)
            VStack(alignment: .leading, spacing: NinoSpacing.s) {
                Group {
                    if typing {
                        TypingDots()
                            .padding(.vertical, 6)
                            .accessibilityElement()
                            .accessibilityLabel(SheetsText.string("sheets.ask.typing", locale))
                    } else if formatted {
                        FormattedReply(text: text)
                    } else {
                        Text(text).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .ninoGlass(cornerRadius: 18)
                if reportSent {
                    Label { ShText("sheets.ask.reportSent") } icon: { Image(systemName: "checkmark") }
                        .font(.nino(.caption).weight(.semibold))
                        .foregroundStyle(NinoColor.success)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(NinoColor.successSoft))
                }
                if let reportButton {
                    Button(action: reportButton) { ShText("sheets.report.title") }
                        .buttonStyle(.nino(.primary))
                }
            }
            Spacer(minLength: 48)
        }
    }
}

/// Biçimli robot cevabı: paragraflar, numaralı adımlar (rozet), maddeler; asılı girinti.
struct FormattedReply: View {
    let text: String

    var body: some View {
        let blocks = AssistantFormatting.parseBlocks(text)
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                blockView(block)
                    .padding(.top, index == 0 ? 0 : (block.isListItem && blocks[index - 1].isListItem ? 8 : 10))
            }
        }
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func blockView(_ block: AssistantFormatting.Block) -> some View {
        switch block {
        case .paragraph(let t):
            Text(AssistantFormatting.linkified(t)).fixedSize(horizontal: false, vertical: true)
        case .step(let number, let t):
            HStack(alignment: .firstTextBaseline, spacing: NinoSpacing.s) {
                Text(verbatim: number)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, number.count > 1 ? 5 : 0)
                    .frame(minWidth: 21, minHeight: 21)
                    .background(Capsule().fill(NinoColor.accent))
                Text(AssistantFormatting.linkified(t)).fixedSize(horizontal: false, vertical: true)
            }
        case .bullet(let t):
            HStack(alignment: .firstTextBaseline, spacing: NinoSpacing.s) {
                Text(verbatim: "•").font(.system(size: 15, weight: .bold)).foregroundStyle(NinoColor.accent)
                    .frame(width: 21)
                Text(AssistantFormatting.linkified(t)).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct UserBubble: View {
    let message: AssistantMessage
    let showRetry: Bool
    let retryDisabled: Bool
    let onRetry: () -> Void

    var body: some View {
        HStack {
            Spacer(minLength: 72)
            VStack(alignment: .trailing, spacing: NinoSpacing.xs) {
                VStack(alignment: .trailing, spacing: NinoSpacing.s) {
                    if !message.photos.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(message.photos) { photo in
                                if let image = NSImage(data: photo.jpeg) {
                                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                                        .frame(width: 84, height: 64)
                                        .clipShape(NinoRadius.shape(10))
                                }
                            }
                        }
                    }
                    if !message.text.isEmpty {
                        Text(message.text).foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(NinoRadius.shape(18).fill(NinoColor.accent))
                .opacity(message.failed != nil ? 0.6 : 1)
                if showRetry {
                    HStack(spacing: 6) {
                        Label { ShText("sheets.ask.notSent") } icon: { Image(systemName: "exclamationmark.circle.fill") }
                            .foregroundStyle(NinoColor.danger)
                        Button(action: onRetry) {
                            ShText("sheets.ask.tryAgain").foregroundStyle(NinoColor.accentText).underline()
                        }
                        .buttonStyle(.plain)
                        .disabled(retryDisabled)
                    }
                    .font(.nino(.caption))
                }
            }
        }
    }
}
