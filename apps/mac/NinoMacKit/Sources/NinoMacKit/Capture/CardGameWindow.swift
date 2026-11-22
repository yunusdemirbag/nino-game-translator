// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import AVFoundation
import AppKit
import IOKit.pwr_mgt

/// Kartla "Mac'te gösterme" kipinin oyun penceresi (kaynaklar.md §3 "Oyun penceresi").
///
/// Dış ekran varsa orada, yoksa ana ekranda açılır, hemen tam ekrana geçer. Esc tam ekrandan çıkar, pencereyi
/// kapatmak çeviriyi durdurur. Oyun alanı her değişimde `AppState.gameAreaFrame`'e yazılır; tam ekran hâli
/// `AppState.cardFullScreen` ile iki yönlü eşlenir.
@MainActor
final class CardGameWindow: NSObject, NSWindowDelegate {
    private let state: AppState
    private let onClose: () -> Void
    private var window: GameWindow?
    private var videoView: CardVideoView?
    private var session: AVCaptureSession?
    private var sleepAssertion: IOPMAssertionID = 0
    private var observers: [NSObjectProtocol] = []
    private var cursorTimer: Timer?
    private var lastMouse = NSEvent.mouseLocation
    private var mouseStill: TimeInterval = 0
    private var closingByCode = false

    init(state: AppState, onClose: @escaping () -> Void) {
        self.state = state
        self.onClose = onClose
        super.init()
    }

    var isOpen: Bool { window != nil }

    /// Dahili olmayan (HDMI ile bağlı) ilk ekran; yoksa ana ekran.
    static func targetScreen() -> NSScreen? {
        let screens = NSScreen.screens
        if let hdmi = screens.first(where: { !isBuiltIn($0) }) { return hdmi }
        return NSScreen.main ?? screens.first
    }

    /// Ekran numarası okunamayan ekran dış ekran sayılmaz.
    private static func isBuiltIn(_ screen: NSScreen) -> Bool {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let number = screen.deviceDescription[key] as? NSNumber else { return true }
        return CGDisplayIsBuiltin(CGDirectDisplayID(number.uint32Value)) != 0
    }

    func show(session: AVCaptureSession) {
        self.session = session
        if let window {
            reattach()
            window.makeKeyAndOrderFront(nil)
            return
        }
        guard let screen = Self.targetScreen() else { return }
        let inner = screen.visibleFrame.insetBy(dx: 80, dy: 60)
        let fit = WindowRules.fit16x9(in: inner.size)
        let frame = CGRect(x: inner.midX - fit.width / 2, y: inner.midY - fit.height / 2, width: fit.width, height: fit.height)
        let w = GameWindow(contentRect: frame, styleMask: [.titled, .closable, .miniaturizable, .resizable],
                           backing: .buffered, defer: false, screen: screen)
        w.title = "Nino"
        w.backgroundColor = .black
        w.isReleasedWhenClosed = false
        w.contentAspectRatio = CGSize(width: 16, height: 9)
        w.collectionBehavior = [.fullScreenPrimary]
        w.delegate = self
        w.onEscape = { [weak self] in self?.exitFullScreen() }
        let view = CardVideoView(frame: CGRect(origin: .zero, size: frame.size))
        view.autoresizingMask = [.width, .height]
        view.attach(session)
        w.contentView = view
        window = w
        videoView = view
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        w.toggleFullScreen(nil)
        preventDisplaySleep(true)
        observeSystem()
        startCursorTimer()
        reportArea()
    }

    /// Kart oturumu yeniden kuruldu ya da ekran uyandı: katman yeniden bağlanır.
    func reattach() { videoView?.attach(session) }

    func close() {
        guard let w = window else { return }
        closingByCode = true
        w.close()
        closingByCode = false
        teardown()
    }

    private func teardown() {
        window = nil
        videoView?.attach(nil)
        videoView = nil
        session = nil
        preventDisplaySleep(false)
        for o in observers {
            NotificationCenter.default.removeObserver(o)
            NSWorkspace.shared.notificationCenter.removeObserver(o)
        }
        observers = []
        cursorTimer?.invalidate()
        cursorTimer = nil
        state.gameAreaFrame = nil
        state.cardFullScreen = false
    }

    /// Menüden "tam ekran aç/kapat" (küçültülmüşse önce geri getirilir).
    func setFullScreen(_ on: Bool) {
        guard let w = window else { return }
        if w.isMiniaturized { w.deminiaturize(nil) }
        if w.styleMask.contains(.fullScreen) != on { w.toggleFullScreen(nil) }
    }

    private func exitFullScreen() {
        guard let w = window, w.styleMask.contains(.fullScreen) else { return }
        w.toggleFullScreen(nil)
    }

    // MARK: Oyun alanı

    private func reportArea() {
        guard let w = window, !w.isMiniaturized, let content = w.contentView else {
            state.gameAreaFrame = nil
            return
        }
        let bounds = content.convert(content.bounds, to: nil)
        let inWindow = w.convertToScreen(bounds)
        let fit = WindowRules.fit16x9(in: inWindow.size)
        state.gameAreaFrame = CGRect(x: inWindow.midX - fit.width / 2, y: inWindow.midY - fit.height / 2,
                                     width: fit.width, height: fit.height)
    }

    func windowDidResize(_ notification: Notification) { reportArea() }
    func windowDidMove(_ notification: Notification) { reportArea() }
    func windowDidChangeScreen(_ notification: Notification) { reportArea() }
    func windowDidMiniaturize(_ notification: Notification) { state.gameAreaFrame = nil }
    func windowDidDeminiaturize(_ notification: Notification) { reportArea() }

    func windowDidEnterFullScreen(_ notification: Notification) {
        state.cardFullScreen = true
        reportArea()
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        state.cardFullScreen = false
        reportArea()
    }

    func windowWillClose(_ notification: Notification) {
        guard !closingByCode else { return }
        teardown()
        onClose()
    }

    // MARK: Sistem

    private func preventDisplaySleep(_ on: Bool) {
        if on, sleepAssertion == 0 {
            IOPMAssertionCreateWithName(kIOPMAssertionTypeNoDisplaySleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                        "Nino is displaying gameplay" as CFString, &sleepAssertion)
        } else if !on, sleepAssertion != 0 {
            IOPMAssertionRelease(sleepAssertion)
            sleepAssertion = 0
        }
    }

    private func observeSystem() {
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            observers.append(ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.reattach() }
            })
        }
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.reportArea() }
            })
    }

    /// Fare 2 sn durunca imleç gizlenir (oynatıcılardaki gibi; fare oynayınca geri gelir).
    private func startCursorTimer() {
        cursorTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let w = self.window, w.isKeyWindow else { return }
                let now = NSEvent.mouseLocation
                if now != self.lastMouse {
                    self.lastMouse = now
                    self.mouseStill = 0
                    return
                }
                self.mouseStill += 0.5
                if self.mouseStill >= 2, w.frame.contains(now) { NSCursor.setHiddenUntilMouseMoves(true) }
            }
        }
    }
}

/// Esc'yi tam ekrandan çıkmaya çeviren pencere (pencereyi kapatmaz).
final class GameWindow: NSWindow {
    var onEscape: (() -> Void)?

    override func cancelOperation(_ sender: Any?) { onEscape?() }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onEscape?() } else { super.keyDown(with: event) }
    }
}
