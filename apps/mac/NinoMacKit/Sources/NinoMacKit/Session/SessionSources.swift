// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import CoreGraphics
import Foundation
import NinoCore

/// Çeviri oturumunun görüntü kaynağı: kareler, durdurma ve durum bildirimi.
public struct SessionSource: Sendable {
    public let frames: FrameSource
    public let stop: @Sendable () -> Void
    /// "Hemen yeniden bağlan" (Mac uyandı, ağ değişti).
    public let reconnect: @Sendable () -> Void

    public init(frames: FrameSource, stop: @escaping @Sendable () -> Void = {}, reconnect: @escaping @Sendable () -> Void = {}) {
        self.frames = frames
        self.stop = stop
        self.reconnect = reconnect
    }
}

/// Kaynağın oturuma bildirdikleri.
public struct SourceCallbacks: Sendable {
    public var status: @Sendable (SourceStatus) -> Void
    /// PS5 başka adreste bulundu (kasaya yazıldı).
    public var consoleMoved: @Sendable (PS5Pairing) -> Void
    /// Oyun penceresinden okunurken oyun alanının ekrandaki yeri (AppKit ekran koordinatı; bilinmiyorsa nil).
    /// Bilgisayardaki altyazı penceresi bu alana oturur (`AppState.gameAreaFrame`).
    public var gameArea: @Sendable (CGRect?) -> Void

    public init(status: @escaping @Sendable (SourceStatus) -> Void, consoleMoved: @escaping @Sendable (PS5Pairing) -> Void = { _ in },
                gameArea: @escaping @Sendable (CGRect?) -> Void = { _ in }) {
        self.status = status
        self.consoleMoved = consoleMoved
        self.gameArea = gameArea
    }
}

public enum SessionSources {
    /// Ayara göre kaynak. PS5: Remote Play oturumu; pencere: ScreenCaptureKit; kart: AVFoundation (Capture/).
    public static func live(settings: MacSettings, store: ConsoleRecordStore, log: ConsoleLog,
                            callbacks: SourceCallbacks) -> SessionSource {
        switch settings.videoSource {
        case .ps5:
            let controller = ConsoleSessionController.live(store: store, log: log)
            controller.onStatus = { callbacks.status(.ps5($0)) }
            controller.onPairingChanged = { callbacks.consoleMoved($0) }
            return SessionSource(frames: controller, stop: { controller.stop() }, reconnect: { controller.reconnectNow() })
        case .window:
            // Uygulamada LiveEngine `CaptureCoordinator.makeSource` kullanır (oyun alanı, günlük, Xbox durumu);
            // bu yalnız durum bildiren yalın hâli.
            let target: WindowTarget = settings.gameConsole == .xbox ? .xbox : .playStation(settings.remotePlayApp)
            let capture = WindowCapture(target: target, hooks: CaptureHooks(window: { callbacks.status(.window($0)) },
                                                                              gameArea: { callbacks.gameArea($0) }))
            return SessionSource(frames: capture, stop: { capture.stop() }, reconnect: { capture.reconnect() })
        case .card:
            let capture = CardCapture(preferredID: { nil }, playsAudio: false,
                                      hooks: CaptureHooks(card: { callbacks.status(.card($0)) }))
            return SessionSource(frames: capture, stop: { capture.stop() }, reconnect: { capture.reconnect() })
        }
    }
}

/// Hiç kare vermeyen, yalnız iptal edilince biten kaynak (henüz yazılmamış kaynakların yerine).
public struct IdleFrameSource: FrameSource {
    public init() {}
    public func frames() -> AsyncStream<Frame> { AsyncStream { _ in } }
}

/// Verilen kareleri aralıklı ve gerekirse tekrarlı veren kaynak (testler ve deneme).
public struct ScriptedFrameSource: FrameSource {
    public struct Step: @unchecked Sendable {
        public var image: CGImage
        /// Bu kare kaç kez verilir.
        public var repeats: Int
        public init(_ image: CGImage, repeats: Int = 1) {
            self.image = image
            self.repeats = repeats
        }
    }

    public let steps: [Step]
    public let interval: Duration
    /// Bütün kareler verilince akış bitsin mi (yoksa iptale kadar açık kalır).
    public let finishAtEnd: Bool

    public init(steps: [Step], interval: Duration = .milliseconds(50), finishAtEnd: Bool = false) {
        self.steps = steps
        self.interval = interval
        self.finishAtEnd = finishAtEnd
    }

    public func frames() -> AsyncStream<Frame> {
        let steps = steps, interval = interval, finish = finishAtEnd
        return AsyncStream(bufferingPolicy: .unbounded) { continuation in
            let task = Task {
                var index = 0
                for step in steps {
                    for _ in 0..<max(1, step.repeats) {
                        if Task.isCancelled { break }
                        continuation.yield(Frame(image: step.image, index: index))
                        index += 1
                        try? await Task.sleep(for: interval)
                    }
                }
                if finish { continuation.finish() }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
