// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import AppKit
import Foundation
import WebKit

/// TV'nin çizdiği katmanın birebir aynısı (yalnız admin/debug yapısı): TV web sayfası (`TVPageWeb`) gizli, ekran dışı
/// bir pencerede 1920×1080 çalışır. TV'lere giden protokol mesajları aynen verilir; görüntüsü (saydam zeminli) PS5
/// karesinin üstüne konur.
@MainActor
public final class TVPageRenderer {
    public static let size = TVPageWeb.layoutSize
    /// Görüntü genişliği (nokta); bileşik karede PS5 karesinin boyuna ölçeklenir.
    static let snapshotWidth: CGFloat = 1280

    private var window: NSWindow?
    private var page: TVPageWeb?

    public static func pageFolder() -> URL? { TVPageWeb.pageFolder() }

    public init() {
        guard Self.pageFolder() != nil else { return }
        let page = TVPageWeb(frame: CGRect(origin: .zero, size: Self.size))
        let web = page.webView
        page.keepDrawingWhenOccluded()
        let w = NSWindow(contentRect: CGRect(x: -30000, y: -30000, width: Self.size.width, height: Self.size.height),
                         styleMask: [.borderless], backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false
        w.ignoresMouseEvents = true
        w.isExcludedFromWindowsMenu = true
        w.collectionBehavior = [.transient, .ignoresCycle, .stationary]
        w.backgroundColor = .clear
        w.isOpaque = false
        w.hasShadow = false
        w.contentView = web
        w.orderFrontRegardless()
        w.setFrameOrigin(CGPoint(x: -30000, y: -30000))
        window = w
        self.page = page
    }

    public var isReady: Bool { page?.ready ?? false }

    /// TV'ye giden bir protokol mesajı (JSON metni).
    public func receive(_ json: String) { page?.receive(json) }

    /// Son durumu tutar: sayfa sonradan açılırsa ya da yeniden yüklenirse aynı katman kurulur.
    func remember(_ json: String) { page?.remember(json) }

    var replayMessages: [String] { page?.replayMessages ?? [] }

    /// Katmanın görüntüsü (saydam zemin); sayfa hazır değilse nil.
    public func snapshot() async -> CGImage? {
        let box = await withCheckedContinuation { (c: CheckedContinuation<ImageBox, Never>) in
            snapshot { c.resume(returning: ImageBox(image: $0)) }
        }
        return box.image
    }

    public func snapshot(_ done: @escaping @MainActor (CGImage?) -> Void) {
        guard let page else { return done(nil) }
        page.snapshot(width: Self.snapshotWidth, done)
    }

    private struct ImageBox: @unchecked Sendable { let image: CGImage? }

    public func close() {
        window?.orderOut(nil)
        window?.close()
        window = nil
        page = nil
    }
}

enum DebugTextJS {
    /// JS metni için çift tırnaklı kaçış.
    static func quote(_ s: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [s], options: [.fragmentsAllowed])) ?? Data("[\"\"]".utf8)
        let arr = String(decoding: data, as: UTF8.self)
        return String(arr.dropFirst().dropLast())
    }
}
