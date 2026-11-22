// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Sorun Bildir: tek ekran. Yazı alanı, resim ya da .txt için bırakma alanı (tıklayınca dosya seçici), Gönder.
/// Nino'nun bulguları, cihaz özeti ve uygulama kayıtları gövdeye kendiliğinden eklenir (ekranda gösterilmez).
/// Ayarlar › Sorun Bildir ve Nino'ya Sor da bunu gösterir. Taslak uygulama açık kaldıkça `SheetsStatus.report`'ta durur.
public struct ReportProblemForm: View {
    private let state: AppState
    private let onDone: () -> Void
    @Environment(\.locale) private var locale

    /// - Parameter onDone: Gönderildikten 1,6 sn sonra çağrılır (Ayarlar listesine dönülür).
    public init(state: AppState, onDone: @escaping () -> Void) {
        self.state = state
        self.onDone = onDone
    }

    private var draft: ReportDraft { state.sheetsStatus.report }

    public var body: some View {
        if draft.phase == .sent {
            NinoCard {
                VStack(spacing: NinoSpacing.m) {
                    Image(systemName: NinoSymbol.okFill).font(.system(size: 34)).foregroundStyle(NinoColor.success)
                    ShText("sheets.report.thanks").font(.nino(.headline))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, NinoSpacing.xl)
            }
        } else {
            form
        }
    }

    private var form: some View {
        @Bindable var draft = draft
        let sending = draft.phase == .sending
        return VStack(alignment: .leading, spacing: NinoSpacing.l) {
            SheetTextEditor(text: $draft.description, placeholder: SheetsText.string("sheets.report.placeholder", locale),
                            minHeight: 160)
                .disabled(sending)
                .opacity(sending ? 0.6 : 1)
            ReportDropZone(draft: draft)
                .disabled(sending)
            if let failure = draft.attachError { NinoErrorLabel(Self.attachText(failure, locale)) }
            if let error = draft.error { NinoErrorLabel(Self.errorText(error, locale)) }
            HStack(spacing: NinoSpacing.s) {
                if sending {
                    SheetSpinner()
                    ShText("sheets.report.sending").foregroundStyle(NinoColor.textSecondary)
                } else {
                    ShText("sheets.report.footer")
                        .font(.nino(.caption))
                        .foregroundStyle(NinoColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: NinoSpacing.m)
                Button(action: send) { ShText("sheets.report.send").frame(minWidth: 96) }
                    .buttonStyle(.nino(.primary, size: .large))
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!draft.canSend)
            }
        }
    }

    private func send() {
        let state = state
        let onDone = onDone
        Task { @MainActor in
            await state.sheetsStatus.report.send(build: { Self.build(state) },
                                                  using: { await state.sendProblemReport($0) },
                                                  onDone: onDone)
        }
    }

    /// Bildirimin içeriği: yazılan + ekler + Nino'nun bulguları + cihaz özeti + uygulama kayıtları.
    static func build(_ state: AppState) -> ProblemReport {
        let s = state.sheetsStatus
        let draft = s.report
        let cause = HealthRules.causes(s.healthMetrics).first.map { HealthText.causeTitle($0, Locale(identifier: "tr")) }
        let findings = ReportFindings.text(causeTitle: cause, problems: recentProblems(state), metrics: s.healthMetrics)
        let device = DeviceInfo.make(state: state, facts: s.deviceFacts, tvApp: s.tvApp).summary
        let logs = s.dataFolder.map { ReportLogs.collect(folder: $0, facts: s.deviceFacts) }
        return ProblemReport(kind: .user, description: draft.description, findings: findings,
                             photos: draft.photos, logs: logs, textFiles: draft.textFiles, device: device)
    }

    /// Son 3 günün sorunlarından en son 6'sı.
    static func recentProblems(_ state: AppState, now: Date = Date()) -> [ProblemRecord] {
        Array(state.sheetsStatus.problems.filter { now.timeIntervalSince($0.date) <= 3 * 86_400 }
            .sorted { $0.date > $1.date }.prefix(6))
    }

    static func errorText(_ error: ReportError, _ locale: Locale) -> String {
        switch error {
        case .dailyLimit: return SheetsText.string("sheets.report.error.dailyLimit", locale)
        case .offline: return SheetsText.string("sheets.report.error.offline", locale)
        case .tooLarge: return SheetsText.string("sheets.report.error.tooLarge", locale)
        case .server: return SheetsText.string("sheets.report.error.server", locale)
        }
    }

    static func attachText(_ failure: ReportAttachments.Failure, _ locale: Locale) -> String {
        switch failure {
        case .unreadable: return SheetsText.string("sheets.report.file.unreadable", locale)
        case .limit: return SheetsText.string("sheets.report.file.limit", locale)
        }
    }
}

/// Bırakma alanı: boşken büyük kesikli kutu; ek varsa küçük resimler/dosya kartları ve "+" kutusu.
/// Tıklayınca dosya seçici açılır; resim ve .txt dosyaları sürüklenip bırakılabilir.
struct ReportDropZone: View {
    let draft: ReportDraft
    @State private var targeted = false
    @Environment(\.locale) private var locale

    private static let tile = CGSize(width: 96, height: 72)

    var body: some View {
        Group {
            if draft.attachments.isEmpty { emptyZone } else { filledZone }
        }
        .modifier(DropIfInteractive(isTargeted: $targeted, perform: drop))
    }

    private var emptyZone: some View {
        let shape = NinoRadius.shape(NinoRadius.control)
        return Button(action: choose) {
            VStack(spacing: NinoSpacing.s) {
                Image(systemName: draft.preparing > 0 ? "hourglass" : "square.and.arrow.down")
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(targeted ? NinoColor.accentText : NinoColor.textSecondary)
                ShText("sheets.report.drop").font(.nino(.callout).weight(.semibold))
                ShText("sheets.report.dropHint")
                    .font(.nino(.caption))
                    .foregroundStyle(NinoColor.textSecondary)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 116)
            .background(shape.fill(targeted ? AnyShapeStyle(NinoColor.accentSoft) : AnyShapeStyle(Color.clear)))
            .overlay(border(shape))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
    }

    private var filledZone: some View {
        HStack(alignment: .top, spacing: NinoSpacing.m) {
            ForEach(draft.attachments) { item in
                VStack(spacing: 4) {
                    if let photo = item.photo {
                        PhotoThumbnail(photo: photo, size: Self.tile, cornerRadius: 12) { draft.remove(item.id) }
                    } else {
                        TextFileTile(size: Self.tile) { draft.remove(item.id) }
                    }
                    Text(verbatim: item.name)
                        .font(.system(size: 10))
                        .foregroundStyle(NinoColor.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(width: Self.tile.width)
                }
            }
            if draft.canAdd { addTile }
            Spacer(minLength: 0)
        }
        .padding(NinoSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(border(NinoRadius.shape(NinoRadius.control)))
    }

    private var addTile: some View {
        let shape = NinoRadius.shape(12)
        return Button(action: choose) {
            Image(systemName: draft.preparing > 0 ? "hourglass" : "plus")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(targeted ? NinoColor.accentText : NinoColor.textSecondary)
                .frame(width: Self.tile.width, height: Self.tile.height)
                .background(shape.fill(NinoColor.textSecondary.opacity(0.06)))
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .help(SheetsText.string("sheets.report.drop", locale))
        .accessibilityLabel(SheetsText.string("sheets.report.drop", locale))
    }

    private func border(_ shape: some InsettableShape) -> some View {
        shape.strokeBorder(targeted ? AnyShapeStyle(NinoColor.accent) : AnyShapeStyle(NinoColor.glassEdge),
                           style: StrokeStyle(lineWidth: targeted ? 2 : 1, dash: targeted ? [] : [6, 4]))
    }

    private func drop(_ providers: [NSItemProvider]) -> Bool {
        guard draft.canAdd else {
            draft.attachError = .limit
            return false
        }
        draft.preparing += 1
        Task { @MainActor in
            let result = await ReportAttachmentLoader.load(providers: providers)
            draft.add(result.items, failed: result.failed)
            draft.preparing -= 1
        }
        return true
    }

    private func choose() {
        guard draft.canAdd else { return }
        let urls = ReportAttachmentLoader.choose()
        guard !urls.isEmpty else { return }
        draft.preparing += 1
        Task { @MainActor in
            let result = await ReportAttachmentLoader.load(urls: urls)
            draft.add(result.items, failed: result.failed)
            draft.preparing -= 1
        }
    }
}

/// Yazı dosyasının kartı: belge simgesi, sağ üstte kaldırma.
private struct TextFileTile: View {
    let size: CGSize
    let onRemove: () -> Void
    @Environment(\.locale) private var locale

    var body: some View {
        let shape = NinoRadius.shape(12)
        Image(systemName: "doc.text")
            .font(.system(size: 26, weight: .regular))
            .foregroundStyle(NinoColor.accentText)
            .frame(width: size.width, height: size.height)
            .background(shape.fill(NinoColor.accentSoft))
            .overlay(shape.strokeBorder(NinoColor.glassEdge, lineWidth: 1))
            .overlay(alignment: .topTrailing) {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(Color.black.opacity(0.55)))
                        .overlay(Circle().strokeBorder(.white.opacity(0.8), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .padding(4)
                .help(SheetsText.string("sheets.report.file.remove", locale))
                .accessibilityLabel(SheetsText.string("sheets.report.file.remove", locale))
            }
    }
}

/// Ekleri arka planda hazırlar (resim küçültme, yazı okuma).
enum ReportAttachmentLoader {
    static func load(urls: [URL]) async -> (items: [ReportAttachment], failed: Bool) {
        await Task.detached(priority: .userInitiated) {
            var items: [ReportAttachment] = []
            var failed = false
            for url in urls.prefix(ReportAttachments.maxFiles) {
                do { items.append(try ReportAttachments.prepare(fileAt: url)) } catch { failed = true }
            }
            return (items, failed || urls.count > ReportAttachments.maxFiles)
        }.value
    }

    /// Sürükle-bırak: önce dosya adresi, olmazsa resim verisi.
    static func load(providers: [NSItemProvider]) async -> (items: [ReportAttachment], failed: Bool) {
        var urls: [URL] = []
        var datas: [Data] = []
        for provider in providers.prefix(ReportAttachments.maxFiles) {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
               let url = await fileURL(from: provider) {
                urls.append(url)
            } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier),
                      let data = await imageData(from: provider) {
                datas.append(data)
            }
        }
        let a = await load(urls: urls)
        let images = await Task.detached(priority: .userInitiated) {
            datas.enumerated().map { index, data in
                try? ReportAttachments.prepare(imageData: data, name: "image-\(index + 1).jpg")
            }
        }.value
        let missing = providers.prefix(ReportAttachments.maxFiles).count - urls.count - datas.count
        return (a.items + images.compactMap { $0 }, a.failed || images.contains { $0 == nil } || missing > 0)
    }

    private static func fileURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: URL.self) { url, _ in continuation.resume(returning: url) }
        }
    }

    private static func imageData(from provider: NSItemProvider) async -> Data? {
        await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }

    /// Çoklu seçimli seçici: resimler ve düz yazı.
    @MainActor
    static func choose() -> [URL] {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = ReportAttachments.types
        return panel.runModal() == .OK ? panel.urls : []
    }
}

/// Ayrı sayfa olarak: başlık, kaydırılan form, Kapat.
public struct ReportProblemSheet: View {
    private let state: AppState

    public init(state: AppState) { self.state = state }

    public var body: some View {
        VStack(alignment: .leading, spacing: NinoSpacing.l) {
            HStack {
                ShText("sheets.report.title").font(.nino(.display))
                Spacer()
                Button {
                    state.activeSheet = nil
                } label: {
                    ShText("sheets.common.close")
                }
                .buttonStyle(.nino(.secondary))
                .keyboardShortcut(.cancelAction)
            }
            SheetScroll {
                ReportProblemForm(state: state) { state.activeSheet = nil }
                    .padding(.bottom, NinoSpacing.s)
            }
        }
        .padding(NinoSpacing.xl)
        .frame(width: 640, height: NinoSize.windowHeight - 2 * NinoSpacing.xl)
        .ninoScreen()
    }
}

/// Sürükle-bırak; ekran görüntüsünde (çizilemediği için) eklenmez.
struct DropIfInteractive: ViewModifier {
    @Binding var isTargeted: Bool
    let perform: ([NSItemProvider]) -> Bool
    @Environment(\.ninoStaticRendering) private var isStatic

    func body(content: Content) -> some View {
        if isStatic {
            content
        } else {
            content.onDrop(of: [.fileURL, .image], isTargeted: $isTargeted, perform: perform)
        }
    }
}
