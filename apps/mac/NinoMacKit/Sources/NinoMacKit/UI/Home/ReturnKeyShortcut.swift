// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import AppKit
import SwiftUI

/// Ana ekranda Enter (Return ya da sayısal tuş takımındaki Enter) fişi takar/çıkarır.
/// Yalnız pencere öndeyken, bir metin alanı odakta değilken ve üstte sayfa yokken; tuş başka işe gitmez.
struct ReturnKeyShortcut: NSViewRepresentable {
    /// Tuş işlendi mi (işlendiyse olay yutulur).
    let onReturn: @MainActor () -> Bool

    func makeNSView(context: Context) -> MonitorView {
        let view = MonitorView()
        view.onReturn = onReturn
        return view
    }

    func updateNSView(_ view: MonitorView, context: Context) { view.onReturn = onReturn }

    static func dismantleNSView(_ view: MonitorView, coordinator: ()) { view.stop() }

    /// Return (36) ve sayısal Enter (76).
    static let returnKeyCodes: Set<UInt16> = [36, 76]

    /// Olay bu pencerede fişe mi gitmeli (pencere öndeki ana pencere, sayfa yok, metin alanı odakta değil,
    /// değiştirici tuş yok, basılı tutma tekrarı değil).
    @MainActor
    static func shouldHandle(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, isRepeat: Bool,
                             window: NSWindow?, eventWindow: NSWindow?) -> Bool {
        guard returnKeyCodes.contains(keyCode), !isRepeat else { return false }
        guard modifiers.intersection([.command, .option, .control, .shift]).isEmpty else { return false }
        guard let window, eventWindow === window, window.isKeyWindow, window.attachedSheet == nil,
              window.sheets.isEmpty else { return false }
        return !(window.firstResponder is NSText)
    }

    final class MonitorView: NSView {
        var onReturn: (@MainActor () -> Bool)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                let handle = MainActor.assumeIsolated {
                    ReturnKeyShortcut.shouldHandle(keyCode: event.keyCode, modifiers: event.modifierFlags,
                                                   isRepeat: event.isARepeat, window: self.window,
                                                   eventWindow: event.window)
                        && (self.onReturn?() ?? false)
                }
                return handle ? nil : event
            }
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
    }
}
