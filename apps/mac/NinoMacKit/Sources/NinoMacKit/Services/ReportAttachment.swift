// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation
import UniformTypeIdentifiers

// Sorun Bildir'in ekleri: resim (küçültülmüş JPEG) ya da düz yazı dosyası (.txt, .log).
//
// Sunucu (`receiveReport`) bilinmeyen alanları atar ve `images` en çok 3 resim kabul eder; bu yüzden yazı dosyaları
// ayrı bir alan yerine `log` alanının sonuna "— ek: ad —" başlığıyla eklenir (geriye uyumlu: ek yoksa gövde aynı).

/// Bildirime eklenen düz yazı dosyası.
public struct ReportTextFile: Equatable, Sendable {
    public var name: String
    public var text: String

    public init(name: String, text: String) {
        self.name = name
        self.text = text
    }
}

/// Sorun Bildir'deki bir ek.
public struct ReportAttachment: Equatable, Sendable, Identifiable {
    public enum Content: Equatable, Sendable {
        case image(PhotoAttachment)
        case text(String)
    }

    public var id: UUID
    public var name: String
    public var content: Content

    public init(id: UUID = UUID(), name: String, content: Content) {
        self.id = id
        self.name = name
        self.content = content
    }

    public var photo: PhotoAttachment? {
        if case let .image(p) = content { return p }
        return nil
    }

    public var textFile: ReportTextFile? {
        if case let .text(t) = content { return ReportTextFile(name: name, text: t) }
        return nil
    }

    /// Gönderilecek bayt (resimde JPEG, yazıda UTF-8).
    public var byteCount: Int {
        switch content {
        case .image(let p): return p.jpeg.count
        case .text(let t): return t.utf8.count
        }
    }
}

/// Ek sınırları ve dosyadan okuma.
public enum ReportAttachments {
    /// Bildirim başına en çok dosya.
    public static let maxFiles = 5
    /// Sunucu `images` için en çok 3 kabul eder.
    public static let maxImages = 3
    /// Resim başına (sıkıştırılmış JPEG) en çok 1 MB.
    public static let maxImageBytes = 1_000_000
    /// Bütün eklerin toplamı. Base64 resmi 4/3 büyütür; gövdenin 4 MB sınırına günlükle birlikte sığsın diye 2,8 MB.
    public static let maxTotalBytes = 2_800_000
    /// Bundan büyük yazı dosyası okunmaz.
    public static let maxTextFileBytes = 1_000_000
    /// Bir yazı dosyasından gönderilen (sonundan) UTF-16 birimi ve bütün yazı eklerinin toplamı (`log` 60 000 tutar).
    public static let maxTextUnitsPerFile = 15_000
    public static let maxTextUnitsTotal = 30_000

    public enum Failure: Error, Equatable, Sendable {
        /// Açılamadı ya da desteklenmeyen tür.
        case unreadable
        /// Sınır aşıldı (sayı ya da boyut).
        case limit
    }

    /// Seçicinin ve sürükle-bırakın kabul ettiği türler.
    public static let types: [UTType] = [.image, .plainText, UTType(filenameExtension: "log") ?? .plainText]

    static func isText(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if ["txt", "log", "text"].contains(ext) { return true }
        guard let type = UTType(filenameExtension: ext) else { return false }
        return type.conforms(to: .plainText)
    }

    /// Dosyadan ek hazırlar (arka planda çağrılır).
    public static func prepare(fileAt url: URL) throws -> ReportAttachment {
        let name = url.lastPathComponent
        if isText(url) {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            guard size <= maxTextFileBytes else { throw Failure.limit }
            guard let data = try? Data(contentsOf: url), let text = decode(data) else { throw Failure.unreadable }
            return ReportAttachment(name: name, content: .text(text))
        }
        guard let photo = try? PhotoAttachment.prepare(fileAt: url) else { throw Failure.unreadable }
        guard photo.jpeg.count <= maxImageBytes else { throw Failure.limit }
        return ReportAttachment(name: name, content: .image(photo))
    }

    /// Resim verisinden (pano, sürükle-bırak).
    public static func prepare(imageData data: Data, name: String) throws -> ReportAttachment {
        guard let photo = try? PhotoAttachment.prepare(data: data) else { throw Failure.unreadable }
        guard photo.jpeg.count <= maxImageBytes else { throw Failure.limit }
        return ReportAttachment(name: name, content: .image(photo))
    }

    /// UTF-8 (BOM'lu da), olmazsa UTF-16 ve Latin-1. NUL içeren (ikili) dosya okunmaz.
    static func decode(_ data: Data) -> String? {
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) {
            return String(data: data, encoding: .utf16)
        }
        guard !data.contains(0) else { return nil }
        if let s = String(data: data, encoding: .utf8) {
            return s.hasPrefix("\u{FEFF}") ? String(s.dropFirst()) : s
        }
        return String(data: data, encoding: .isoLatin1)
    }

    /// `existing`e `new`den sığanlar eklenir; sığmayan varsa `limited` doğru.
    public static func merge(_ existing: [ReportAttachment], _ new: [ReportAttachment])
        -> (attachments: [ReportAttachment], limited: Bool) {
        var out = existing
        var limited = false
        for item in new {
            let images = out.filter { $0.photo != nil }.count
            let total = out.reduce(0) { $0 + $1.byteCount }
            if out.count >= maxFiles || (item.photo != nil && images >= maxImages)
                || total + item.byteCount > maxTotalBytes {
                limited = true
                continue
            }
            out.append(item)
        }
        return (out, limited)
    }

    /// `log` alanının sonuna eklenen yazı dosyaları; her biri sonundan en çok 15 000 birim, toplam en çok 30 000.
    static func textBlock(_ files: [ReportTextFile]) -> String {
        guard !files.isEmpty else { return "" }
        let parts = files.map { "— ek: \($0.name) —\n" + ReportContract.tail($0.text, limit: maxTextUnitsPerFile) }
        return ReportContract.tail(parts.joined(separator: "\n\n"), limit: maxTextUnitsTotal)
    }
}
