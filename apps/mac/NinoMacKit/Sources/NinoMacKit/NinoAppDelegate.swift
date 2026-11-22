// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import AppKit
import SwiftUI

/// Ana pencerenin her zaman geri gelebilmesi (ana-ekran.md §1–2):
/// - Açılışta ana pencere yoksa açılır (SwiftUI, önceki oturumda kapalı kalan `Window` sahnesini geri kurmaz).
/// - Dock simgesine tıklayınca ana pencere kapalıysa açılır ve öne gelir.
/// - Son pencere kapanınca uygulama kapanmaz; çeviri arka planda sürer.
/// Gizli TV sayfası penceresi (ekran dışı, kimliksiz) ve menü çubuğu "pencere" sayılmaz.
@MainActor
public final class NinoAppDelegate: NSObject, NSApplicationDelegate {
    /// SwiftUI'nin `openWindow` eylemi; menülerdeki görünmez bir görünüm açılışta buraya bırakır.
    static var openWindowAction: OpenWindowAction?

    override public init() { super.init() }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // SwiftUI pencereleri açılışın hemen ardından kurar; ona fırsat verip sonra bakarız.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            if !Self.mainWindowVisible { Self.showMainWindow() }
        }
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // `flag` gizli TV sayfası penceresini de sayar; ana pencereye kendimiz bakarız.
        if !Self.mainWindowVisible { Self.showMainWindow() }
        return false
    }

    /// SwiftUI ana penceresi (kimliği "main" ile başlar).
    static var mainWindow: NSWindow? {
        NSApp.windows.first { isMainWindow($0) }
    }

    static var mainWindowVisible: Bool {
        guard let w = mainWindow else { return false }
        return w.isVisible || w.isMiniaturized
    }

    static func isMainWindow(_ w: NSWindow) -> Bool {
        guard let id = w.identifier?.rawValue else { return false }
        return id == NinoWindowID.main || id.hasPrefix(NinoWindowID.main + "-")
    }

    /// Ana pencereyi açar (ya da küçültülmüşse geri getirir) ve öne alır.
    static func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let w = mainWindow, w.isMiniaturized {
            w.deminiaturize(nil)
            w.makeKeyAndOrderFront(nil)
            return
        }
        if let open = openWindowAction {
            open(id: NinoWindowID.main)
        } else if let item = NSApp.windowsMenu?.items.first(where: { $0.title == "Nino" }), let action = item.action {
            // Yedek: SwiftUI'nin Pencere menüsüne koyduğu "Nino" öğesi.
            NSApp.sendAction(action, to: item.target, from: item)
        }
        DispatchQueue.main.async { mainWindow?.makeKeyAndOrderFront(nil) }
    }
}

/// Menülerde görünmez satır: SwiftUI'nin `openWindow` eylemini açılışta delegeye bırakır
/// (ana pencere hiç kurulmadıysa pencerenin içinden alınamaz).
struct OpenWindowCatcher: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let _ = { NinoAppDelegate.openWindowAction = openWindow }()
        EmptyView()
    }
}
