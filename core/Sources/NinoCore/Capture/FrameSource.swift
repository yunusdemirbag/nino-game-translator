// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import CoreGraphics
import Foundation

/// Tek bir oyun karesi.
public struct Frame: @unchecked Sendable {
    public let image: CGImage
    /// Kaynağın verdiği sıra numarası.
    public let index: Int
    /// Kaynağın saati (saniye). Hat zamanı kare sayısıyla ölçer; bu yalnız bilgi içindir.
    public let time: TimeInterval

    public init(image: CGImage, index: Int, time: TimeInterval = 0) {
        self.image = image
        self.index = index
        self.time = time
    }
}

/// Kare veren her şey: Remote Play oturumu, ekran yakalama, deneme dosyaları.
///
/// Kurallar:
/// - Kaynak kareleri sırayla verir. Tüketici yavaşsa **eski kareleri atar**,
///   en yenisini tutar (`bufferingNewest(1)`); kare biriktirmez.
/// - Akış biterse kaynak kapanmış demektir.
/// - Kaynak, saniyede kaç kare vereceğini kendisi seçer (öneri: 5–10).
public protocol FrameSource: Sendable {
    func frames() -> AsyncStream<Frame>
}

/// Önceden verilmiş kareleri sırayla veren kaynak (testler ve deneme kareleri için).
public struct StaticFrameSource: FrameSource {
    public let images: [CGImage]

    public init(images: [CGImage]) {
        self.images = images
    }

    public func frames() -> AsyncStream<Frame> {
        let images = images.map { UncheckedBox($0) }
        return AsyncStream { continuation in
            for (i, box) in images.enumerated() { continuation.yield(Frame(image: box.value, index: i)) }
            continuation.finish()
        }
    }
}

struct UncheckedBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}
