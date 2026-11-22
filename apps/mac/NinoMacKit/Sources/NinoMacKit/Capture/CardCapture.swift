// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import AVFoundation
import CoreGraphics
import Foundation
import NinoCore
import os

/// HDMI yakalama kartını (macOS'ta kamera gibi görünür) okuyan kaynak (kaynaklar.md §3).
///
/// Kareler 1920×1080 BGRA gelir, okuma hattına saniyede 10 kopya gider. Siyah görüntü ve takılma bekçisi
/// `CardWatchdog`'dadır. Aynı oturum kurulumdaki önizlemeye ve "Mac'te gösterme" penceresine de görüntü verir.
public final class CardCapture: NSObject, FrameSource, @unchecked Sendable {
    public let session = AVCaptureSession()
    private let hooks: CaptureHooks
    private let preferredID: @Sendable () -> String?
    /// Kartın sesi hoparlöre geçirilsin mi (oyun bu Mac'te gösteriliyorsa).
    private let playsAudio: Bool

    private let queue = DispatchQueue(label: "nino.capture.card.session")
    private let frameQueue = DispatchQueue(label: "nino.capture.card.frames", qos: .userInteractive)
    private let logger = Logger(subsystem: "com.ninotranslator.mac", category: "capture-card")

    private struct Running {
        var device: CardDeviceInfo?
        var watchdog = CardWatchdog(now: 0)
        var throttle = FrameThrottle(rate: 10)
        var index = 0
        var lastStatus: SourceStatus.CardLink?
        var active = false
    }

    private let running = Locked(Running())
    private let continuation = Locked<AsyncStream<Frame>.Continuation?>(nil)
    private let ticker = Locked<Task<Void, Never>?>(nil)
    private var observers: [NSObjectProtocol] = []
    /// Oturum yeniden kurulunca (görüntü katmanları yeniden bağlansın diye).
    public var onSessionRebuilt: (@Sendable () -> Void)?

    public init(preferredID: @escaping @Sendable () -> String?, playsAudio: Bool, hooks: CaptureHooks) {
        self.preferredID = preferredID
        self.playsAudio = playsAudio
        self.hooks = hooks
        super.init()
    }

    /// Okunan kartın adı (yoksa nil).
    public var deviceName: String? { running.get().device?.name }

    // MARK: Aygıtlar

    public static func videoDevices() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.external], mediaType: .video, position: .unspecified).devices
    }

    static func audioDevices() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external], mediaType: .audio,
                                         position: .unspecified).devices
    }

    static func info(_ d: AVCaptureDevice) -> CardDeviceInfo {
        CardDeviceInfo(id: d.uniqueID, name: d.localizedName, modelID: d.modelID)
    }

    /// Kart denetimindeki seçici için takılı görüntü aygıtları.
    public static func deviceList() -> [CaptureCardCheck.Device] {
        videoDevices().map { CaptureCardCheck.Device(id: $0.uniqueID, name: $0.localizedName) }
    }

    // MARK: FrameSource

    public func frames() -> AsyncStream<Frame> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { c in
            continuation.update { $0 = c }
            c.onTermination = { [weak self] _ in self?.stop() }
            start()
        }
    }

    /// Okumayı başlatır (önizleme kare akışı olmadan da çağırır).
    public func start() {
        let first = running.update { r -> Bool in
            defer { r.active = true }
            return !r.active
        }
        guard first else { return }
        observe()
        Task { await self.authorizeAndBuild() }
        let t = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self?.tick()
            }
        }
        ticker.update { $0 = t }
    }

    public func stop() {
        running.update { $0.active = false }
        ticker.update { t -> Task<Void, Never>? in defer { t = nil }; return t }?.cancel()
        for o in observers { NotificationCenter.default.removeObserver(o) }
        observers = []
        queue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
        let c = continuation.update { c -> AsyncStream<Frame>.Continuation? in defer { c = nil }; return c }
        c?.finish()
    }

    /// Uyanınca ya da seçim değişince: oturum baştan kurulur.
    public func reconnect() {
        guard running.get().active else { return }
        queue.async { self.build() }
    }

    // MARK: Kurma

    private func authorizeAndBuild() async {
        let video = await Self.access(.video)
        guard video else {
            report(.cameraDenied)
            return
        }
        if playsAudio { _ = await Self.access(.audio) }
        queue.async { self.build() }
    }

    private static func access(_ type: AVMediaType) async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: type) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: type)
        default: return false
        }
    }

    /// Oturumu seçilen kartla kurar (oturum sırasında).
    private func build() {
        guard running.get().active else { return }
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            report(.cameraDenied)
            return
        }
        let devices = Self.videoDevices()
        let chosen = CardRules.pickDevice(devices.map(Self.info), preferredID: preferredID())
        session.beginConfiguration()
        for input in session.inputs { session.removeInput(input) }
        for output in session.outputs { session.removeOutput(output) }
        guard let chosen, let device = devices.first(where: { $0.uniqueID == chosen.id }),
              let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else {
            session.commitConfiguration()
            if session.isRunning { session.stopRunning() }
            running.update { $0.device = nil }
            report(.noCard)
            return
        }
        session.addInput(input)
        if session.canSetSessionPreset(.hd1920x1080) { session.sessionPreset = .hd1920x1080 }
        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 1920,
            kCVPixelBufferHeightKey as String: 1080,
        ]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: frameQueue)
        if session.canAddOutput(output) { session.addOutput(output) }

        if playsAudio, AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
           let audio = CardRules.matchAudio(for: chosen, in: Self.audioDevices().map(Self.info)),
           let audioDevice = Self.audioDevices().first(where: { $0.uniqueID == audio.id }),
           let audioInput = try? AVCaptureDeviceInput(device: audioDevice), session.canAddInput(audioInput) {
            session.addInput(audioInput)
            let speaker = AVCaptureAudioPreviewOutput()
            speaker.volume = 1.0
            if session.canAddOutput(speaker) { session.addOutput(speaker) }
        }
        session.commitConfiguration()
        if !session.isRunning { session.startRunning() }

        let now = ProcessInfo.processInfo.systemUptime
        running.update { r in
            r.device = chosen
            r.watchdog = CardWatchdog(now: now)
            r.throttle = FrameThrottle(rate: 10)
        }
        let format = device.activeFormat
        let size = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        let fps = format.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0
        let subtype = CMFormatDescriptionGetMediaSubType(format.formatDescription)
        logger.log("kart bağlandı: \(chosen.name, privacy: .public) \(size.width)x\(size.height) en çok \(fps) kare/sn biçim \(subtype)")
        onSessionRebuilt?()
    }

    private func observe() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        let changed: (Notification) -> Void = { [weak self] note in
            guard let self, let device = note.object as? AVCaptureDevice, device.hasMediaType(.video) else { return }
            // Aynı kart zaten okunuyorsa dokunulmaz.
            let current = self.running.get().device?.id
            if note.name == AVCaptureDevice.wasConnectedNotification, current != nil,
               Self.videoDevices().contains(where: { $0.uniqueID == current }), self.session.isRunning { return }
            if note.name == AVCaptureDevice.wasDisconnectedNotification, current != nil, device.uniqueID != current { return }
            self.reconnect()
        }
        observers.append(center.addObserver(forName: AVCaptureDevice.wasConnectedNotification, object: nil, queue: nil, using: changed))
        observers.append(center.addObserver(forName: AVCaptureDevice.wasDisconnectedNotification, object: nil, queue: nil, using: changed))
        observers.append(center.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: nil) { [weak self] _ in
            self?.reconnect()
        })
    }

    // MARK: Bekçi

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        let (restart, hasDevice) = running.update { r -> (Bool, Bool) in
            guard r.active, r.device != nil else { return (false, r.device != nil) }
            return (r.watchdog.tick(now: now), true)
        }
        if restart {
            logger.log("kart: 3 sn'den uzun süredir kare yok, oturum yeniden kuruluyor")
            hooks.log("yakalama kartı: görüntü takıldı, yeniden bağlanılıyor")
            queue.async { self.build() }
        } else if !hasDevice, running.get().active, AVCaptureDevice.authorizationStatus(for: .video) == .authorized,
                  CardRules.pickDevice(Self.videoDevices().map(Self.info), preferredID: preferredID()) != nil {
            queue.async { self.build() }
        }
    }

    private func report(_ status: SourceStatus.CardLink) {
        let changed = running.update { r -> Bool in
            defer { r.lastStatus = status }
            return r.lastStatus != status
        }
        guard changed else { return }
        hooks.card(status)
        switch status {
        case .cameraDenied: hooks.log("yakalama kartı: kamera izni verilmemiş")
        case .noCard: hooks.log("yakalama kartı: takılı kart yok")
        case .black: hooks.log("yakalama kartı: görüntü siyah (\(deviceName ?? "?"))")
        case let .reading(name): hooks.log("yakalama kartı: \(name) okunuyor")
        case .idle: break
        }
    }
}

extension CardCapture: AVCaptureVideoDataOutputSampleBufferDelegate {
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                              from connection: AVCaptureConnection) {
        let now = ProcessInfo.processInfo.systemUptime
        guard running.update({ $0.throttle.shouldPass(now: now) }), let buffer = sampleBuffer.imageBuffer,
              let copy = PixelCopy.image(from: buffer, checkBlack: true) else { return }
        let (picture, index, name) = running.update { r -> (CardWatchdog.Picture?, Int, String) in
            defer { r.index += 1 }
            return (r.watchdog.frame(now: now, black: copy.black), r.index, r.device?.name ?? "")
        }
        switch picture {
        case .reading: report(.reading(cardName: name))
        case .black: report(.black)
        case .waiting, nil: break
        }
        continuation.get()?.yield(Frame(image: copy.image, index: index, time: now))
    }
}
