// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import AppKit
import CoreGraphics
import CoreMedia
import Foundation
import NinoCore
import ScreenCaptureKit

/// Kaynağın uygulamaya bildirdikleri (durum, oyun alanının ekrandaki yeri, günlük satırı).
public struct CaptureHooks: Sendable {
    public var window: @Sendable (SourceStatus.WindowLink) -> Void
    public var card: @Sendable (SourceStatus.CardLink) -> Void
    /// Oyun alanı (AppKit ekran koordinatı, sol alt başlangıç); nil: alan yok.
    public var gameArea: @Sendable (CGRect?) -> Void
    /// Altyazı günlüğü.
    public var log: @Sendable (String) -> Void

    public init(window: @escaping @Sendable (SourceStatus.WindowLink) -> Void = { _ in },
                card: @escaping @Sendable (SourceStatus.CardLink) -> Void = { _ in },
                gameArea: @escaping @Sendable (CGRect?) -> Void = { _ in },
                log: @escaping @Sendable (String) -> Void = { _ in }) {
        self.window = window
        self.card = card
        self.gameArea = gameArea
        self.log = log
    }
}

/// Ekran Kaydı izni: yoksa macOS izin penceresi süreç başına bir kez istenir.
enum ScreenRecordingPermission {
    private static let asked = Locked(false)

    static var granted: Bool { CGPreflightScreenCaptureAccess() }

    /// İzin varsa `true`; yoksa (ilk seferde) ister ve `false` döner.
    static func ensure() -> Bool {
        if granted { return true }
        let first = asked.update { a -> Bool in
            defer { a = true }
            return !a
        }
        if first { _ = CGRequestScreenCaptureAccess() }
        return false
    }
}

/// Bu Mac'teki oyun penceresini (PS Remote Play / chiaki-ng ya da Xbox penceresi) okuyan kaynak (kaynaklar.md §2).
///
/// 1,5 sn'de bir pencere aranır; seçilen pencerenin 16:9 oyun alanı 1920×1080'e ölçeklenip saniyede 10 kez verilir
/// (görüntü değişmese de son kare yeniden verilir). Pencere kapanır ya da akış hata verirse yeniden aranır.
public final class WindowCapture: NSObject, FrameSource, @unchecked Sendable {
    public let target: WindowTarget
    private let hooks: CaptureHooks

    private struct Tracked {
        var id: UInt32
        var frame: CGRect
        var appName: String
        var stream: SCStream
    }

    private let tracked = Locked<Tracked?>(nil)
    private let latest = Locked<CGImage?>(nil)
    private let lastStatus = Locked<SourceStatus.WindowLink?>(nil)
    private let lastCandidates = Locked<[String]>([])
    private let loop = Locked<Task<Void, Never>?>(nil)
    private let wakeUp = Locked<Bool>(false)
    private let outputQueue = DispatchQueue(label: "nino.capture.window", qos: .userInteractive)

    public init(target: WindowTarget, hooks: CaptureHooks) {
        self.target = target
        self.hooks = hooks
        super.init()
    }

    // MARK: FrameSource

    public func frames() -> AsyncStream<Frame> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let task = Task { [weak self] in
                guard let self else { return }
                let repeater = Task {
                    var index = 0
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .milliseconds(Int(1000 / WindowRules.repeatRate)))
                        if let image = self.latest.get() {
                            continuation.yield(Frame(image: image, index: index, time: Date().timeIntervalSince1970))
                            index += 1
                        }
                    }
                }
                await self.searchLoop()
                repeater.cancel()
                continuation.finish()
            }
            loop.update { $0 = task }
            continuation.onTermination = { [weak self] _ in self?.stop() }
        }
    }

    public func stop() {
        loop.update { t -> Task<Void, Never>? in defer { t = nil }; return t }?.cancel()
        stopStream()
    }

    /// "Hemen yeniden bağlan": akış kapatılır, hemen yeniden aranır.
    public func reconnect() {
        stopStream()
        wakeUp.update { $0 = true }
    }

    // MARK: Arama

    private func searchLoop() async {
        report(.searching)
        while !Task.isCancelled {
            await searchOnce()
            let step = 100
            var waited = 0
            while waited < Int(WindowRules.searchInterval * 1000), !Task.isCancelled {
                if wakeUp.update({ w -> Bool in defer { w = false }; return w }) { break }
                try? await Task.sleep(for: .milliseconds(step))
                waited += step
            }
        }
        stopStream()
    }

    private func searchOnce() async {
        guard ScreenRecordingPermission.ensure() else {
            stopStream()
            report(.screenRecordingDenied)
            return
        }
        let onScreenOnly: Bool = { if case .playStation = target { return true }; return false }()
        guard let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: onScreenOnly) else {
            report(.searching)
            return
        }
        let pid = getpid()
        let infos: [(CaptureWindowInfo, SCWindow)] = content.windows.map { w in
            let app = w.owningApplication
            let info = CaptureWindowInfo(id: w.windowID, appName: app?.applicationName ?? "",
                                         bundleID: app?.bundleIdentifier ?? "", title: w.title ?? "",
                                         frame: w.frame, layer: w.windowLayer, isOnScreen: w.isOnScreen,
                                         isOwn: app?.processID == pid)
            return (info, w)
        }
        let displays = content.displays.map(\.frame)
        let windows = infos.map(\.0)
        let picked = WindowRules.pick(windows, target: target, displays: displays)
        let current = tracked.get()
        switch WindowDecision.decide(currentID: current?.id, currentFrame: current?.frame, picked: picked) {
        case .keep:
            break
        case .keepSearching, .stop:
            stopStream()
            report(.searching)
            let lines = WindowRules.candidateLines(windows, target: target, displays: displays)
            let changed = lastCandidates.update { old -> Bool in
                defer { old = lines }
                return old != lines
            }
            if changed { hooks.log("oyun penceresi adayları: " + (lines.isEmpty ? "yok" : lines.joined(separator: " | "))) }
        case .updateArea:
            guard let picked, let current else { return }
            let config = configuration(for: picked, displays: displays)
            try? await current.stream.updateConfiguration(config)
            tracked.update { $0?.frame = picked.frame }
            reportArea(picked, displays: displays)
        case .restart:
            guard let picked, let scWindow = infos.first(where: { $0.0.id == picked.id })?.1 else { return }
            stopStream()
            await start(picked, scWindow: scWindow, displays: displays)
        }
    }

    private func configuration(for window: CaptureWindowInfo, displays: [CGRect]) -> SCStreamConfiguration {
        let full = WindowRules.isFullScreen(window.frame, displays: displays)
        let area = WindowRules.gameArea(windowSize: window.frame.size, fullScreen: full)
        let c = SCStreamConfiguration()
        c.sourceRect = area
        c.width = Int(WindowRules.outputSize.width)
        c.height = Int(WindowRules.outputSize.height)
        c.pixelFormat = kCVPixelFormatType_32BGRA
        c.showsCursor = false
        c.capturesAudio = false
        c.queueDepth = 3
        c.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(WindowRules.repeatRate))
        return c
    }

    private func start(_ window: CaptureWindowInfo, scWindow: SCWindow, displays: [CGRect]) async {
        let filter = SCContentFilter(desktopIndependentWindow: scWindow)
        let stream = SCStream(filter: filter, configuration: configuration(for: window, displays: displays), delegate: self)
        do {
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: outputQueue)
            try await stream.startCapture()
        } catch {
            hooks.log("oyun penceresi: akış açılamadı (\(error.localizedDescription))")
            return
        }
        tracked.update { $0 = Tracked(id: window.id, frame: window.frame, appName: window.appName, stream: stream) }
        reportArea(window, displays: displays)
        report(.reading(appName: window.appName))
    }

    private func stopStream() {
        let old = tracked.update { t -> Tracked? in defer { t = nil }; return t }
        latest.update { $0 = nil }
        guard let old else { return }
        hooks.gameArea(nil)
        Task { try? await old.stream.stopCapture() }
    }

    private func reportArea(_ window: CaptureWindowInfo, displays: [CGRect]) {
        let full = WindowRules.isFullScreen(window.frame, displays: displays)
        let local = WindowRules.gameArea(windowSize: window.frame.size, fullScreen: full)
        let global = local.offsetBy(dx: window.frame.minX, dy: window.frame.minY)
        let primary = CGDisplayBounds(CGMainDisplayID()).height
        hooks.gameArea(WindowRules.appKitRect(global, primaryHeight: primary))
    }

    private func report(_ status: SourceStatus.WindowLink) {
        let changed = lastStatus.update { old -> Bool in
            defer { old = status }
            return old != status
        }
        guard changed else { return }
        hooks.window(status)
        switch status {
        case .screenRecordingDenied: hooks.log("oyun penceresi: macOS kayıt izni yok, pencere okunamıyor")
        case .searching: hooks.log("oyun penceresi: aranıyor")
        case let .reading(app): hooks.log("oyun penceresi: \(app) okunuyor")
        case .idle, .appMissing: break
        }
    }
}

extension WindowCapture: SCStreamOutput, SCStreamDelegate {
    public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int, SCFrameStatus(rawValue: raw) == .complete,
              let buffer = sampleBuffer.imageBuffer,
              let copy = PixelCopy.image(from: buffer) else { return }
        latest.update { $0 = copy.image }
    }

    public func stream(_ stream: SCStream, didStopWithError error: Error) {
        // Pencere kapandı ya da akış bozuldu: yeniden aranır (çeviri durmaz).
        let ours = tracked.get()?.stream === stream
        guard ours else { return }
        hooks.log("oyun penceresi: akış durdu (\(error.localizedDescription))")
        tracked.update { $0 = nil }
        latest.update { $0 = nil }
        hooks.gameArea(nil)
        wakeUp.update { $0 = true }
    }
}
