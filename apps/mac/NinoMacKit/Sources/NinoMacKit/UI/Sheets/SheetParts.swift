// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import AppKit
import SwiftUI
import UniformTypeIdentifiers

// Sayfaların ortak parçaları: metin tablosu, kaydırma, yazı alanı, anahtar, dönen gösterge,
// "Kopyalandı" düğmesi, fotoğraf küçük resimleri ve ekleme kutusu.
// Ekran görüntüsünde (`ninoStaticRendering`) çizilemeyen sistem denetimleri düz şekillerle çizilir.

/// Sayfaların metin tablosu (`Resources/Sheets.xcstrings`).
enum SheetsText {
    static let table = "Sheets"

    static func string(_ key: String, _ locale: Locale, _ arguments: CVarArg...) -> String {
        NinoL10n.string(key, table: table, language: NinoL10n.languageCode(for: locale), arguments: arguments)
    }

    static func string(_ key: String, language: String, _ arguments: CVarArg...) -> String {
        NinoL10n.string(key, table: table, language: language, arguments: arguments)
    }
}

/// Sayfa tablosundan metin görünümü.
struct ShText: View {
    private let key: String
    private let arguments: [CVarArg]

    init(_ key: String, _ arguments: CVarArg...) {
        self.key = key
        self.arguments = arguments
    }

    var body: some View { NinoText(key, table: SheetsText.table, arguments: arguments) }
}

/// Dikey kaydırma; ekran görüntüsünde düz yığın.
struct SheetScroll<Content: View>: View {
    private let content: Content
    @Environment(\.ninoStaticRendering) private var isStatic

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        if isStatic {
            VStack(spacing: 0) { content }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .clipped()
        } else {
            ScrollView { content }
        }
    }
}

/// Çok satırlı yazı alanı: cam yüzey, "control" köşe, boşken yer tutucu.
struct SheetTextEditor: View {
    @Binding var text: String
    let placeholder: String
    var minHeight: CGFloat = 140
    @Environment(\.ninoStaticRendering) private var isStatic

    var body: some View {
        ZStack(alignment: .topLeading) {
            if isStatic {
                Text(text.isEmpty ? " " : text).padding(.horizontal, 5)
            } else {
                TextEditor(text: $text)
                    .scrollContentBackground(.hidden)
                    .font(.nino(.body))
            }
            if text.isEmpty {
                Text(placeholder)
                    .foregroundStyle(NinoColor.textSecondary)
                    .padding(.horizontal, 5)
                    .allowsHitTesting(false)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
        .ninoGlass(cornerRadius: NinoRadius.control)
    }
}

/// Tek satır yazı alanı; ekran görüntüsünde düz kutu.
struct SheetTextField: View {
    @Binding var text: String
    let placeholder: String
    var onSubmit: () -> Void = {}
    @Environment(\.ninoStaticRendering) private var isStatic

    var body: some View {
        if isStatic {
            Text(text.isEmpty ? placeholder : text)
                .foregroundStyle(text.isEmpty ? NinoColor.textSecondary : NinoColor.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, NinoSpacing.l)
                .frame(minHeight: 44)
                .ninoGlass(cornerRadius: NinoRadius.control)
        } else {
            TextField(placeholder, text: $text)
                .onSubmit(onSubmit)
                .ninoTextField()
        }
    }
}

/// Anahtar; ekran görüntüsünde çizilmiş kapsül.
struct SheetToggle: View {
    @Binding var isOn: Bool
    let label: String
    @Environment(\.ninoStaticRendering) private var isStatic

    var body: some View {
        if isStatic {
            Capsule()
                .fill(isOn ? AnyShapeStyle(NinoColor.accent) : AnyShapeStyle(NinoColor.surface2))
                .frame(width: 38, height: 22)
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle().fill(.white).padding(2).shadow(radius: 1)
                }
                .accessibilityLabel(label)
        } else {
            Toggle(label, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }
}

/// Küçük dönen gösterge; ekran görüntüsünde yarım halka.
struct SheetSpinner: View {
    @Environment(\.ninoStaticRendering) private var isStatic

    var body: some View {
        if isStatic {
            Circle().trim(from: 0, to: 0.7).stroke(NinoColor.textSecondary, lineWidth: 2).frame(width: 14, height: 14)
        } else {
            ProgressView().controlSize(.small)
        }
    }
}

/// Basınca metni "Kopyalandı" olan düğme.
struct CopyFeedbackButton: View {
    let titleKey: String
    let copiedKey: String
    var kind: NinoButtonKind = .secondary
    let text: () -> String
    @State private var copied = false

    var body: some View {
        Button {
            Pasteboard.copy(text())
            copied = true
        } label: {
            ShText(copied ? copiedKey : titleKey)
        }
        .buttonStyle(.nino(kind))
    }
}

@MainActor
enum Pasteboard {
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

// MARK: - Fotoğraflar

/// Eklenmiş bir fotoğrafın küçük resmi ve sağ üstte kaldırma düğmesi.
struct PhotoThumbnail: View {
    let photo: PhotoAttachment
    let size: CGSize
    let cornerRadius: CGFloat
    var closeSize: CGFloat = 18
    let onRemove: () -> Void
    @Environment(\.locale) private var locale

    var body: some View {
        let shape = NinoRadius.shape(cornerRadius)
        Group {
            if let image = NSImage(data: photo.jpeg) {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(NinoColor.accentSoft)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(shape)
        .overlay(shape.strokeBorder(NinoColor.glassEdge, lineWidth: 1))
        .overlay(alignment: .topTrailing) {
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: closeSize * 0.45, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: closeSize, height: closeSize)
                    .background(Circle().fill(Color.black.opacity(0.55)))
                    .overlay(Circle().strokeBorder(.white.opacity(0.8), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .padding(4)
            .help(SheetsText.string("sheets.photo.remove", locale))
            .accessibilityLabel(SheetsText.string("sheets.photo.remove", locale))
        }
    }
}

/// Fotoğrafları arka planda hazırlar (küçültme, JPEG). Okunamayan atlanır.
enum PhotoLoader {
    static let imageTypes: [UTType] = [.image]

    /// Dosyalardan; sonuç ve okunamayan var mı.
    static func load(urls: [URL]) async -> (photos: [PhotoAttachment], failed: Bool) {
        await Task.detached(priority: .userInitiated) {
            var photos: [PhotoAttachment] = []
            var failed = false
            for url in urls {
                if let photo = try? PhotoAttachment.prepare(fileAt: url) { photos.append(photo) } else { failed = true }
            }
            return (photos, failed)
        }.value
    }

    static func load(datas: [Data]) async -> (photos: [PhotoAttachment], failed: Bool) {
        await Task.detached(priority: .userInitiated) {
            var photos: [PhotoAttachment] = []
            var failed = false
            for data in datas {
                if let photo = try? PhotoAttachment.prepare(data: data) { photos.append(photo) } else { failed = true }
            }
            return (photos, failed)
        }.value
    }

    /// Sürükle-bırak öğeleri: önce dosya adresi, olmazsa resim verisi. En çok `limit` öğe.
    static func load(providers: [NSItemProvider], limit: Int) async -> (photos: [PhotoAttachment], failed: Bool) {
        var urls: [URL] = []
        var datas: [Data] = []
        for provider in providers.prefix(limit) {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
               let url = await fileURL(from: provider) {
                urls.append(url)
            } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier),
                      let data = await imageData(from: provider) {
                datas.append(data)
            }
        }
        let a = await load(urls: urls)
        let b = await load(datas: datas)
        let missing = providers.prefix(limit).count - urls.count - datas.count
        return (a.photos + b.photos, a.failed || b.failed || missing > 0)
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

    /// Panodan: resim dosyası ya da resim verisi. Yazı varsa nil (normal yapıştırma olur).
    @MainActor
    static func pasteboardImages() -> (urls: [URL], datas: [Data])? {
        let board = NSPasteboard.general
        if let urls = board.readObjects(forClasses: [NSURL.self],
                                        options: [.urlReadingFileURLsOnly: true,
                                                  .urlReadingContentsConformToTypes: [UTType.image.identifier]])
            as? [URL], !urls.isEmpty {
            return (urls, [])
        }
        if board.string(forType: .string) != nil { return nil }
        for type in [NSPasteboard.PasteboardType.png, .tiff] {
            if let data = board.data(forType: type) { return ([], [data]) }
        }
        return nil
    }

    /// Çoklu seçimli resim seçici.
    @MainActor
    static func choose() -> [URL] {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = imageTypes
        return panel.runModal() == .OK ? panel.urls : []
    }
}
