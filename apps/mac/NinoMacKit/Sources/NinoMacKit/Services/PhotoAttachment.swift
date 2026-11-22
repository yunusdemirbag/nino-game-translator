// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Sorun Bildir ve Nino'ya Sor'a eklenen fotoğraf: küçültülmüş JPEG (ninoya-sor.md §3 "Fotoğraf ekleme yolları").
public struct PhotoAttachment: Equatable, Sendable, Identifiable {
    public var id: UUID
    public var jpeg: Data
    public var pixelWidth: Int
    public var pixelHeight: Int

    public init(id: UUID = UUID(), jpeg: Data, pixelWidth: Int, pixelHeight: Int) {
        self.id = id
        self.jpeg = jpeg
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }

    /// Mesaj ya da bildirim başına en çok.
    public static let maxCount = 3
    /// Bu boydan büyük dosya okunmaz (yanlışlıkla seçilen video gibi).
    public static let maxFileBytes = 60 * 1024 * 1024
    /// En uzun kenar.
    public static let maxSide = 1600
    /// Bunu geçerse boyut dörtte üçe indirilip yeniden denenir.
    public static let targetBytes = 900 * 1024
    public static let minSide = 200
    static let qualities: [Double] = [0.7, 0.55, 0.4]

    public enum Failure: Error, Equatable { case unreadable, tooLarge }

    /// Dosyadan: 60 MB'tan büyükse okunmaz.
    public static func prepare(fileAt url: URL) throws -> PhotoAttachment {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= maxFileBytes else { throw Failure.tooLarge }
        guard let data = try? Data(contentsOf: url) else { throw Failure.unreadable }
        return try prepare(data: data)
    }

    /// Resim verisinden (pano, sürükle-bırak).
    public static func prepare(data: Data) throws -> PhotoAttachment {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0,
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            throw Failure.unreadable
        }
        let width = (props[kCGImagePropertyPixelWidth] as? Int) ?? 0
        let height = (props[kCGImagePropertyPixelHeight] as? Int) ?? 0
        guard width > 0, height > 0 else { throw Failure.unreadable }
        var side = min(maxSide, max(width, height))
        while true {
            // Döndürme bilgisi uygulanmış küçük resim.
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: side,
            ]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
                  let flat = flatten(image) else { throw Failure.unreadable }
            for quality in qualities {
                if let jpeg = encode(flat, quality: quality), jpeg.count <= targetBytes || side <= minSide {
                    return PhotoAttachment(jpeg: jpeg, pixelWidth: flat.width, pixelHeight: flat.height)
                }
            }
            let next = side * 3 / 4
            if next < minSide {
                guard let jpeg = encode(flat, quality: qualities.last ?? 0.4) else { throw Failure.unreadable }
                return PhotoAttachment(jpeg: jpeg, pixelWidth: flat.width, pixelHeight: flat.height)
            }
            side = next
        }
    }

    /// Saydam alan beyaza boyanır.
    static func flatten(_ image: CGImage) -> CGImage? {
        guard let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(rect)
        context.draw(image, in: rect)
        return context.makeImage()
    }

    static func encode(_ image: CGImage, quality: Double) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }

    /// Sunucuya giden biçim.
    public var json: [String: Any] { ["mime": "image/jpeg", "data": jpeg.base64EncodedString()] }
}
