// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

// Yakalama kartının saf kuralları (docs/yeni/mac/kaynaklar.md §3): aygıt seçimi, siyah kare, takılma bekçisi,
// kare seyreltme ve durum eşlemesi. Saat dışarıdan verilir (testlerde sahte saat = düz sayılar).

/// Bir görüntü ya da ses aygıtının kurallar için özeti.
public struct CardDeviceInfo: Equatable, Sendable {
    public var id: String
    public var name: String
    /// USB model kimliği (AVCaptureDevice.modelID).
    public var modelID: String

    public init(id: String, name: String, modelID: String = "") {
        self.id = id
        self.name = name
        self.modelID = modelID
    }
}

public enum CardRules {
    /// Adı bilinen web kameraları (kart sayılmaz).
    public static let webcamWords = ["facetime", "webcam", "iphone", "ipad", "logitech", "brio", "c920", "c922",
                                     "continuity", "desk view"]
    /// Kart ipucu kelimeleri.
    public static let cardWords = ["capture", "hdmi", "elgato", "avermedia", "live gamer", "game", "cam link", "razer",
                                   "ripsaw", "ugreen", "usb video", "uvc", "hd60", "4k x", "4k s", "magewell", "video"]

    public static func looksLikeWebcam(_ name: String) -> Bool {
        let n = name.lowercased()
        return webcamWords.contains { n.contains($0) }
    }

    /// Okunacak kart: seçilen takılıysa o; değilse web kamerasına benzemeyenlerden adında kart ipucu geçen ilki,
    /// yoksa onların ilki. Hiçbiri yoksa nil.
    public static func pickDevice(_ devices: [CardDeviceInfo], preferredID: String?) -> CardDeviceInfo? {
        if let preferredID, let chosen = devices.first(where: { $0.id == preferredID }) { return chosen }
        let rest = devices.filter { !looksLikeWebcam($0.name) }
        if let hinted = rest.first(where: { d in
            let n = d.name.lowercased()
            return cardWords.contains { n.contains($0) }
        }) { return hinted }
        return rest.first
    }

    /// Kartın ses aygıtı: aynı USB model kimliği, yoksa adı birbirini içeren.
    public static func matchAudio(for card: CardDeviceInfo, in audio: [CardDeviceInfo]) -> CardDeviceInfo? {
        if !card.modelID.isEmpty, let same = audio.first(where: { $0.modelID == card.modelID }) { return same }
        let name = card.name.lowercased()
        return audio.first { a in
            let other = a.name.lowercased()
            return !other.isEmpty && !name.isEmpty && (other.contains(name) || name.contains(other))
        }
    }

    // MARK: Siyah kare

    /// Örnekleme adımı (piksel).
    public static let blackSampleStep = 32
    /// En parlak örnek bunun altındaysa kare siyahtır.
    public static let blackThreshold: UInt8 = 24

    /// BGRA kare siyah mı: 32 pikselde bir örnek, en parlak kanal bile 24/255'in altında.
    public static func isBlack(base: UnsafeRawPointer, width: Int, height: Int, bytesPerRow: Int) -> Bool {
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        var y = 0
        while y < height {
            let row = bytes + y * bytesPerRow
            var x = 0
            while x < width {
                let p = row + x * 4
                if p[0] >= blackThreshold || p[1] >= blackThreshold || p[2] >= blackThreshold { return false }
                x += blackSampleStep
            }
            y += blackSampleStep
        }
        return true
    }

    /// Kart durumunun ana ekrandaki üç hâli: okunuyor ya da siyah → akıyor; durdu → bağlı değil; öbürleri → bağlanıyor.
    public enum Link: Equatable, Sendable { case streaming, connecting, disconnected }

    public static func link(_ card: SourceStatus.CardLink) -> Link {
        switch card {
        case .reading, .black: return .streaming
        case .idle: return .disconnected
        case .cameraDenied, .noCard: return .connecting
        }
    }

    /// Kart denetiminin (kurulum §10) durumu. `stoppedName`: kart bulundu ama görüntü gelmiyor.
    public static func checkStatus(_ card: SourceStatus.CardLink, stoppedName: String? = nil) -> CaptureCardCheck.Status {
        switch card {
        case .idle: return stoppedName.map { .stopped(name: $0) } ?? .searching
        case .cameraDenied: return .noPermission
        case .noCard: return .noCard
        case .black: return .black
        case let .reading(name): return .working(name: name)
        }
    }
}

/// Kartın siyah görüntü ve takılma bekçisi (kaynaklar.md §3 "Okuma"). Saat saniye olarak verilir.
public struct CardWatchdog: Equatable, Sendable {
    /// Bu kadar kesintisiz siyah → "siyah görüntü".
    public static let blackAfter: TimeInterval = 4
    /// İlk takılma eşiği ve kare gelince dönülen aralık.
    public static let firstStall: TimeInterval = 3
    public static let maxStall: TimeInterval = 30

    public enum Picture: Equatable, Sendable { case waiting, reading, black }

    public private(set) var picture: Picture = .waiting
    public private(set) var stallLimit: TimeInterval = CardWatchdog.firstStall
    private var blackSince: TimeInterval?
    private var lastActivity: TimeInterval

    /// `now`: oturumun açıldığı an.
    public init(now: TimeInterval) { lastActivity = now }

    /// Kare geldi. Görüntü hâli değiştiyse yenisini döner.
    @discardableResult
    public mutating func frame(now: TimeInterval, black: Bool) -> Picture? {
        lastActivity = now
        stallLimit = Self.firstStall
        let before = picture
        if black {
            if blackSince == nil { blackSince = now }
            if let since = blackSince, now - since >= Self.blackAfter { picture = .black }
        } else {
            blackSince = nil
            picture = .reading
        }
        return picture == before ? nil : picture
    }

    /// Saniyede bir çağrılır. Oturum baştan kurulmalıysa `true` (aralık iki katına çıkar, en çok 30).
    public mutating func tick(now: TimeInterval) -> Bool {
        guard now - lastActivity >= stallLimit else { return false }
        lastActivity = now
        stallLimit = min(stallLimit * 2, Self.maxStall)
        return true
    }
}

/// Saniyede en çok `rate` kare geçirir (kart 60 verir, okuma hattına 10 gider).
public struct FrameThrottle: Equatable, Sendable {
    public let interval: TimeInterval
    private var last: TimeInterval?

    public init(rate: Double) { interval = 1 / rate }

    public mutating func shouldPass(now: TimeInterval) -> Bool {
        if let last, now - last < interval * 0.95 { return false }
        last = now
        return true
    }
}
