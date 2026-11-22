// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import CoreGraphics
import Foundation

// Oyun penceresi kaynağının saf kuralları (docs/yeni/mac/kaynaklar.md §2, §4): hangi pencere okunur, tam ekran
// sayılır mı, okunacak 16:9 oyun alanı nerede. Ekran yakalama çerçevesine dokunmaz; testler doğrudan sınar.

/// Ekrandaki bir pencerenin kurallar için gereken özeti. Çerçeve genel ekran koordinatında (sol üst başlangıç).
public struct CaptureWindowInfo: Equatable, Sendable {
    public var id: UInt32
    public var appName: String
    public var bundleID: String
    public var title: String
    public var frame: CGRect
    public var layer: Int
    public var isOnScreen: Bool
    /// Nino'nun kendi penceresi mi (altyazı penceresi asla okunmaz).
    public var isOwn: Bool

    public init(id: UInt32, appName: String, bundleID: String, title: String, frame: CGRect, layer: Int = 0,
                isOnScreen: Bool = true, isOwn: Bool = false) {
        self.id = id
        self.appName = appName
        self.bundleID = bundleID
        self.title = title
        self.frame = frame
        self.layer = layer
        self.isOnScreen = isOnScreen
        self.isOwn = isOwn
    }
}

/// Hangi oyun penceresi aranıyor.
public enum WindowTarget: Equatable, Sendable {
    /// PS Remote Play / chiaki-ng (ayardaki seçim). `customMatch`: geliştirici derlemesinde başka uygulama.
    case playStation(MacSettings.RemotePlayApp, customMatch: String? = nil)
    /// Greenlight ya da tarayıcıdaki xbox.com/play.
    case xbox
}

public enum WindowRules {
    /// En küçük pencere ölçüsü (her yolda).
    public static let minimumSize = CGSize(width: 320, height: 180)
    /// Okunan alan bu boya ölçeklenir (PS5 kareleriyle aynı).
    public static let outputSize = CGSize(width: 1920, height: 1080)
    /// Tam ekran değilken üstten düşülen başlık çubuğu.
    public static let titleBarHeight: CGFloat = 28
    /// Pencere arama aralığı (sn).
    public static let searchInterval: TimeInterval = 1.5
    /// Değişmeyen görüntüde son karenin yeniden verilme sıklığı (saniyede).
    public static let repeatRate: Double = 10
    /// Tarayıcıdaki Xbox bulut oyun sekmesinin başlığında geçen sözcükler (küçük harf).
    static let xboxBrowserTitles = ["xbox", "uzaktan oynama", "remote play"]

    public static let browserBundlePrefixes = [
        "com.apple.safari", "com.google.chrome", "com.microsoft.edgemac", "company.thebrowser.browser",
        "org.mozilla.firefox", "com.brave.browser", "com.operasoftware.opera", "com.vivaldi.vivaldi",
    ]

    public static func isBrowser(_ w: CaptureWindowInfo) -> Bool {
        let id = w.bundleID.lowercased()
        return browserBundlePrefixes.contains { id.hasPrefix($0) }
    }

    static func ownerMatches(_ w: CaptureWindowInfo, _ needles: [String]) -> Bool {
        let name = w.appName.lowercased(), id = w.bundleID.lowercased()
        return needles.contains { name.contains($0) || id.contains($0) }
    }

    static func playStationNeedles(_ choice: MacSettings.RemotePlayApp) -> [String] {
        switch choice {
        case .automatic: return ["remote play", "remoteplay", "chiaki"]
        case .sony: return ["remote play", "remoteplay"]
        case .chiaki: return ["chiaki"]
        }
    }

    static func bigEnough(_ w: CaptureWindowInfo) -> Bool {
        w.frame.width >= minimumSize.width && w.frame.height >= minimumSize.height
    }

    /// Listelenecek pencereler: katman 0, Nino'ya ait değil; PS5 yolunda yalnız ekrandakiler.
    public static func eligible(_ windows: [CaptureWindowInfo], target: WindowTarget) -> [CaptureWindowInfo] {
        windows.filter { w in
            guard w.layer == 0, !w.isOwn else { return false }
            if case .playStation = target, !w.isOnScreen { return false }
            return true
        }
    }

    /// Greenlight'ın yayın penceresi başlığı: "Greenlight - <kelime> <konsol kimliği>". Kimlik en az 8 karakter,
    /// tamamen onaltılık ve en az bir rakamlı. Menü sayfaları ("Greenlight - My consoles") sayılmaz.
    public static func isGreenlightStreamTitle(_ title: String) -> Bool {
        let prefix = "Greenlight - "
        guard title.hasPrefix(prefix) else { return false }
        let rest = title.dropFirst(prefix.count)
        let words = rest.split(whereSeparator: { $0 == " " })
        guard words.count >= 2, let last = words.last else { return false }
        guard last.count >= 8, last.allSatisfy({ $0.isHexDigit }), last.contains(where: { $0.isNumber }) else { return false }
        return true
    }

    public static func isGreenlightOwner(_ w: CaptureWindowInfo) -> Bool { ownerMatches(w, ["greenlight"]) }

    public static func isGreenlightStream(_ w: CaptureWindowInfo) -> Bool {
        isGreenlightOwner(w) && isGreenlightStreamTitle(w.title)
    }

    /// Pencere bir ekranı kaplıyor mu: sol kenar, genişlik ve alt kenar (±2) örtüşür, yükseklik ekranın %85'inden fazla.
    public static func isFullScreen(_ frame: CGRect, displays: [CGRect]) -> Bool {
        displays.contains { d in
            abs(frame.minX - d.minX) <= 2 && abs(frame.width - d.width) <= 2 && abs(frame.maxY - d.maxY) <= 2
                && frame.height > d.height * 0.85
        }
    }

    /// Okunacak pencereyi seçer; yoksa nil.
    public static func pick(_ windows: [CaptureWindowInfo], target: WindowTarget, displays: [CGRect]) -> CaptureWindowInfo? {
        let pool = eligible(windows, target: target).filter(bigEnough)
        func largest(_ list: [CaptureWindowInfo]) -> CaptureWindowInfo? {
            list.max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
        }
        switch target {
        case let .playStation(choice, custom):
            var needles = playStationNeedles(choice)
            if let custom, !custom.isEmpty { needles = [custom.lowercased()] }
            return largest(pool.filter { ownerMatches($0, needles) })
        case .xbox:
            if let stream = largest(pool.filter(isGreenlightStream)) { return stream }
            let titled = pool.filter { w in
                if isGreenlightOwner(w) { return true }
                guard isBrowser(w) else { return false }
                let title = w.title.lowercased()
                return Self.xboxBrowserTitles.contains { title.contains($0) }
            }
            if let w = largest(titled) { return w }
            return largest(pool.filter { isBrowser($0) && isFullScreen($0.frame, displays: displays) })
        }
    }

    /// Pencere içindeki oyun alanı (pencereye göre, sol üst başlangıç). Piksellerden değil ölçüden hesaplanır:
    /// tam ekran değilse üstten başlık çubuğu (28, en çok yüksekliğin ¼'ü) düşülür, kalana sığan en büyük 16:9 ortalanır.
    public static func gameArea(windowSize: CGSize, fullScreen: Bool) -> CGRect {
        let top = fullScreen ? 0 : min(titleBarHeight, windowSize.height / 4)
        let available = CGSize(width: windowSize.width, height: max(0, windowSize.height - top))
        let fit = fit16x9(in: available)
        return CGRect(x: (available.width - fit.width) / 2, y: top + (available.height - fit.height) / 2,
                      width: fit.width, height: fit.height)
    }

    /// Verilen alana sığan en büyük 16:9.
    public static func fit16x9(in size: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0 else { return .zero }
        let ratio: CGFloat = 16.0 / 9.0
        if size.width / size.height > ratio { return CGSize(width: size.height * ratio, height: size.height) }
        return CGSize(width: size.width, height: size.width / ratio)
    }

    /// Genel ekran koordinatındaki (sol üst) dikdörtgeni AppKit ekran koordinatına (sol alt) çevirir.
    /// `primaryHeight`: ana ekranın yüksekliği.
    public static func appKitRect(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// Bulunamayınca günlüğe yazılan aday satırları: tarayıcılar ve yeterince büyükler, en çok 12.
    public static func candidateLines(_ windows: [CaptureWindowInfo], target: WindowTarget, displays: [CGRect]) -> [String] {
        eligible(windows, target: target)
            .filter { isBrowser($0) || bigEnough($0) }
            .prefix(12)
            .map { w in
                var line = "\(w.appName) \"\(w.title)\" \(Int(w.frame.width))x\(Int(w.frame.height))"
                if isFullScreen(w.frame, displays: displays) { line += " tam ekran" }
                return line
            }
    }
}

/// Bu Mac'te Remote Play uygulamaları (kaynaklar.md §2 "kurulu mu").
public enum RemotePlayApps {
    public static let sonyBundleID = "com.playstation.RemotePlay"
    public static let chiakiBundleID = "org.streetpea.chiaking"
    public static let sonyDownload = URL(string: "https://remoteplay.dl.playstation.net/remoteplay/")!
    public static let chiakiDownload = URL(string: "https://github.com/chiaki-ng/chiaki-ng/releases/latest")!

    /// Seçime göre gereken paket kimlikleri; "otomatik"te ikisinden biri yeter.
    public static func bundleIDs(for choice: MacSettings.RemotePlayApp) -> [String] {
        switch choice {
        case .automatic: return [sonyBundleID, chiakiBundleID]
        case .sony: return [sonyBundleID]
        case .chiaki: return [chiakiBundleID]
        }
    }

    /// `isInstalled`: paket kimliğiyle uygulama bulunuyor mu (uygulamada Launch Services).
    public static func installed(choice: MacSettings.RemotePlayApp, isInstalled: (String) -> Bool) -> Bool {
        bundleIDs(for: choice).contains(where: isInstalled)
    }
}

/// Her aramada okunan pencereyle ne yapılacağı (kaynaklar.md §2 "Okuma").
public enum WindowDecision: Equatable, Sendable {
    /// Aynı pencere, aynı yer: dokunma.
    case keep
    /// Aynı pencere taşındı ya da büyüdü: akış kapatılmadan alan güncellenir.
    case updateArea
    /// Başka pencere: akış yeniden kurulur.
    case restart
    /// Pencere yok: akış kapanır, aranmaya devam edilir.
    case stop
    /// Pencere yok, akış da yok.
    case keepSearching

    public static func decide(currentID: UInt32?, currentFrame: CGRect?, picked: CaptureWindowInfo?) -> WindowDecision {
        guard let picked else { return currentID == nil ? .keepSearching : .stop }
        guard let currentID, currentID == picked.id else { return .restart }
        return currentFrame == picked.frame ? .keep : .updateArea
    }
}
