// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import AVFoundation
import CoreGraphics
import Foundation
import VideoToolbox
import WebRTC

/// Xbox ev yayınının WebRTC bağlantısı (Google libwebrtc, stasel/WebRTC paketi). Görüntü yalnız alınır; ses ayar açıksa
/// bu cihazda çalınır, kapalıysa ses birimi hiç açılmaz. Mikrofon parçası eklenmez, Xbox'a ses ya da kumanda girdisi
/// gitmez. Veri kanallarında yalnız yayını ayakta tutan el sıkışma ve kare onayları gönderilir.
final class WebRTCXboxPeer: NSObject, XboxPeer, @unchecked Sendable {
    /// Okuma saniyede birkaç kez yapılır; her kareyi CGImage'a çevirmek gereksiz.
    private static let convertEvery: TimeInterval = 0.066
    /// Kare onayları paketlenme aralığı.
    private static let ackEvery: Duration = .milliseconds(16)

    /// Ses birimi elle yönetilir (ayar kapalıyken hiç açılmaz); bu, fabrika kurulmadan önce söylenmeli.
    private static let factory = makeFactory()

    private static func makeFactory() -> RTCPeerConnectionFactory {
        RTCInitializeSSL()
        let shared = RTCAudioSession.sharedInstance()
        (shared.useManualAudio, shared.isAudioEnabled) = (true, false)
        let decoders = RTCDefaultVideoDecoderFactory(), encoders = RTCDefaultVideoEncoderFactory()
        return RTCPeerConnectionFactory(encoderFactory: encoders, decoderFactory: decoders)
    }

    private let sink: XboxFrameSink
    private let wantsSound: Bool
    /// Xbox'tan 720p görüntü istenir (ayar).
    private let lowResolution: Bool
    private let log: @Sendable (String) -> Void
    private let state = NSLock()
    private var lock: NSLock { state }
    private var connection: RTCPeerConnection?
    private var openChannels = [String: RTCDataChannel]()
    private var channelWatchers: [ChannelWatcher] = []
    private var candidates: [XboxCandidate] = []
    private var gatheringDone = false
    private var reason: String?
    private var lastConversion: TimeInterval = 0
    private let clockZero = ProcessInfo.processInfo.systemUptime
    /// El sıkışmadan sonra gösterilen kareler onaylanır.
    private var ackQueue: [XboxChannelMessages.ShownFrame]?
    private var ackCounter: UInt32 = 0
    private var ackLoop: Task<Void, Never>?

    init(playAudio: Bool, lowResolution: Bool = false, log: @escaping @Sendable (String) -> Void = { _ in },
         sink: @escaping XboxFrameSink) throws {
        self.sink = sink
        self.lowResolution = lowResolution
        wantsSound = playAudio
        self.log = log
        super.init()
        let setup = RTCConfiguration()
        setup.iceServers = [RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302", "stun:stun1.l.google.com:19302"])]
        setup.sdpSemantics = .unifiedPlan
        guard let pc = Self.factory.peerConnection(with: setup, constraints: Self.noConstraints, delegate: self) else {
            throw XboxFailure(.unexpected, "WebRTC bağlantısı kurulamadı")
        }
        connection = pc
        // Sıra Xbox'ın beklediği gibi: veri kanalları, sonra ses (gönder-al) ve görüntü (yalnız al).
        for (label, subprotocol) in XboxChannelMessages.channels {
            let c = RTCDataChannelConfiguration()
            c.isOrdered = true
            c.protocol = subprotocol
            guard let channel = pc.dataChannel(forLabel: label, configuration: c) else {
                throw XboxFailure(.unexpected, "veri kanalı açılamadı: \(label)")
            }
            let watcher = ChannelWatcher(label: label, peer: self)
            channel.delegate = watcher
            openChannels[label] = channel
            channelWatchers.append(watcher)
        }
        func transceiver(_ media: RTCRtpMediaType, _ direction: RTCRtpTransceiverDirection) -> RTCRtpTransceiver? {
            let options = RTCRtpTransceiverInit()
            options.direction = direction
            return pc.addTransceiver(of: media, init: options)
        }
        let sound = transceiver(.audio, .sendRecv)
        let picture = transceiver(.video, .recvOnly)
        sound?.receiver.track?.isEnabled = wantsSound
        Self.sound(wantsSound)
        guard let track = picture?.receiver.track as? RTCVideoTrack else {
            throw XboxFailure(.unexpected, "görüntü alıcısı kurulamadı")
        }
        track.add(self)
    }

    private static let noConstraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)

    /// Oyun sesi: açıkken hoparlörden (ya da bağlı kulaklıktan) medya gibi çalar; görüşme kipi sesi ahizeye verirdi.
    private static func sound(_ enabled: Bool) {
        let shared = RTCAudioSession.sharedInstance()
        if enabled {
            let preferred = RTCAudioSessionConfiguration.webRTC()
            (preferred.category, preferred.mode) = (AVAudioSession.Category.playAndRecord.rawValue, AVAudioSession.Mode.default.rawValue)
            preferred.categoryOptions = [.allowBluetoothA2DP, .defaultToSpeaker]
            RTCAudioSessionConfiguration.setWebRTC(preferred)
        }
        shared.isAudioEnabled = enabled
    }

    private var ms: Double { (ProcessInfo.processInfo.systemUptime - clockZero) * 1000 }

    // MARK: XboxPeer

    var closedReason: String? { lock.withLock { reason } }

    func makeOffer() async throws -> String {
        guard let pc = lock.withLock({ connection }) else { throw XboxFailure(.offline, "bağlantı kapalı") }
        let offer: RTCSessionDescription = try await withCheckedThrowingContinuation { cont in
            pc.offer(for: Self.noConstraints) { sdp, error in
                if let sdp { cont.resume(returning: sdp) } else {
                    cont.resume(throwing: XboxFailure(.unexpected, "Yerel SDP oluşturulamadı: \(error?.localizedDescription ?? "?")"))
                }
            }
        }
        let tuned = RTCSessionDescription(type: .offer, sdp: XboxChannelMessages.preferStereo(offer.sdp))
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            pc.setLocalDescription(tuned) { error in
                if let error { cont.resume(throwing: XboxFailure(.unexpected, "yerel SDP: \(error.localizedDescription)")) } else { cont.resume() }
            }
        }
        return tuned.sdp
    }

    func acceptAnswer(_ sdp: String) async throws {
        guard let pc = lock.withLock({ connection }) else { throw XboxFailure(.offline, "bağlantı kapalı") }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            pc.setRemoteDescription(RTCSessionDescription(type: .answer, sdp: sdp)) { error in
                if let error { cont.resume(throwing: XboxFailure(.unexpected, "Xbox SDP: \(error.localizedDescription)")) } else { cont.resume() }
            }
        }
    }

    func localCandidates(timeout: TimeInterval) async -> [XboxCandidate] {
        let end = ProcessInfo.processInfo.systemUptime + timeout
        while !lock.withLock({ gatheringDone }), ProcessInfo.processInfo.systemUptime < end, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(100))
        }
        return lock.withLock { candidates }
    }

    func addRemoteCandidates(_ list: [XboxCandidate]) async -> Int {
        guard let pc = lock.withLock({ connection }) else { return 0 }
        var added = 0
        for c in list {
            guard let line = c.line else { continue }
            let ok: Bool = await withCheckedContinuation { cont in
                pc.add(RTCIceCandidate(sdp: line, sdpMLineIndex: c.sdpMLineIndex, sdpMid: c.sdpMid)) { cont.resume(returning: $0 == nil) }
            }
            if ok { added += 1 }
        }
        return added
    }

    func close() {
        ackLoop?.cancel()
        ackLoop = nil
        let pc: RTCPeerConnection? = lock.withLock {
            reason = reason ?? "kapatıldı"
            ackQueue = nil
            channelWatchers.removeAll()
            return connection.take()
        }
        let doomed: [RTCDataChannel] = lock.withLock {
            let list = Array(openChannels.values)
            openChannels.removeAll()
            return list
        }
        doomed.forEach {
            $0.delegate = nil
            $0.close()
        }
        pc?.close()
        Self.sound(false)
    }

    // MARK: Veri kanalları

    private func send(_ label: String, _ data: Data, binary: Bool) {
        let target = lock.withLock { openChannels[label] }
        guard let target, target.readyState == .open else { return }
        target.sendData(RTCDataBuffer(data: data, isBinary: binary))
    }

    private func send(_ label: String, text: String) { send(label, Data(text.utf8), binary: false) }

    fileprivate func channel(_ label: String, changedTo state: RTCDataChannelState) {
        log("kanal \(label): \(state.rawValue)")
        switch (label, state) {
        case ("message", .open): send("message", text: XboxChannelMessages.handshake)
        case ("input", .closed): lock.withLock { reason = reason ?? "görüntü kanalı kapandı" }
        default: break
        }
    }

    fileprivate func channel(_ label: String, received buffer: RTCDataBuffer) {
        // İkili iletiler (input kanalında sunucu bilgisi ve titreşim) gerekmiyor.
        if buffer.isBinary { return }
        let message = String(decoding: buffer.data, as: UTF8.self)
        if label != "message" || !XboxChannelMessages.isHandshakeAck(message) {
            log("kanal \(label): \(message.prefix(200))")
            return
        }
        log("el sıkışma tamam")
        for text in XboxChannelMessages.controlMessages { send("control", text: text) }
        send("input", XboxChannelMessages.clientMetadata(at: ms), binary: true)
        let size = XboxChannelMessages.screenSize(lowResolution: lowResolution)
        for text in XboxChannelMessages.clientMessages(width: size.width, height: size.height) { send("message", text: text) }
        beginAcknowledging()
    }

    /// Her 16 ms'de bekleyen kare onaylarından bir paket gönderir.
    private func beginAcknowledging() {
        lock.withLock { ackQueue = [] }
        ackLoop?.cancel()
        ackLoop = Task.detached { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: WebRTCXboxPeer.ackEvery)
                guard let self else { return }
                self.flushAcks()
            }
        }
    }

    private func flushAcks() {
        let packet: Data? = lock.withLock {
            guard var queue = ackQueue, !queue.isEmpty else { return nil }
            let take = min(queue.count, XboxChannelMessages.acksPerPacket)
            let batch = Array(queue[..<take])
            queue.removeSubrange(..<take)
            ackQueue = queue
            ackCounter &+= 1
            return XboxChannelMessages.frameAcks(sequence: ackCounter, at: ms, frames: batch)
        }
        if let packet { send("input", packet, binary: true) }
    }
}

private extension Optional {
    /// Değeri verir ve yerine nil koyar.
    mutating func take() -> Wrapped? {
        defer { self = nil }
        return self
    }
}

// MARK: Kareler

extension WebRTCXboxPeer: RTCVideoRenderer {
    func setSize(_ size: CGSize) {}

    func renderFrame(_ frame: RTCVideoFrame?) {
        guard let frame else { return }
        let uptime = ProcessInfo.processInfo.systemUptime
        let shown = XboxChannelMessages.ShownFrame(rtpTimestamp: UInt32(bitPattern: frame.timeStamp),
                                                   arrivedMs: (uptime - clockZero) * 1000,
                                                   decodedMs: (uptime - clockZero) * 1000)
        let due: Bool = lock.withLock {
            // Onay kuyruğu sınırlı: kanal tıkanırsa en eskiler düşer.
            if ackQueue != nil {
                ackQueue!.append(shown)
                if ackQueue!.count > 600 { ackQueue!.removeFirst(ackQueue!.count - 600) }
            }
            if uptime - lastConversion < Self.convertEvery { return false }
            lastConversion = uptime
            return true
        }
        if due, let picture = Self.picture(of: frame.buffer) { sink(picture) }
    }

    /// Kareden okuma için resim: donanım çözücüsünden geleni olduğu gibi; yazılım çözücüsünün I420 karesinden yalnız
    /// parlaklık düzlemi (gri; yazı okumaya yeter).
    static func picture(of buffer: RTCVideoFrameBuffer) -> CGImage? {
        if let native = buffer as? RTCCVPixelBuffer {
            var made: CGImage?
            return VTCreateCGImageFromCVPixelBuffer(native.pixelBuffer, options: nil, imageOut: &made) == noErr ? made : nil
        }
        let planes = buffer.toI420()
        let w = Int(planes.width), h = Int(planes.height), rowBytes = Int(planes.strideY)
        guard w > 0, h > 0, rowBytes >= w,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue),
              let out = ctx.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        let outRow = ctx.bytesPerRow
        for row in 0..<h {
            (out + row * outRow).update(from: planes.dataY + row * rowBytes, count: w)
        }
        return ctx.makeImage()
    }
}

// MARK: Bağlantı olayları

extension WebRTCXboxPeer: RTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        log("ICE durumu: \(newState.rawValue)")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        if newState == .complete { lock.withLock { gatheringDone = true } }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        let c = XboxCandidate(candidate: candidate.sdp, sdpMid: candidate.sdpMid, sdpMLineIndex: candidate.sdpMLineIndex)
        lock.withLock { candidates.append(c) }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCPeerConnectionState) {
        log("bağlantı durumu: \(newState.rawValue)")
        if newState == .failed || newState == .closed {
            lock.withLock { if reason == nil { reason = "WebRTC bağlantısı kesildi" } }
        }
    }
}

/// Bir veri kanalının olaylarını bağlantıya iletir.
private final class ChannelWatcher: NSObject, RTCDataChannelDelegate {
    let label: String
    weak var peer: WebRTCXboxPeer?

    init(label: String, peer: WebRTCXboxPeer) {
        self.label = label
        self.peer = peer
    }

    func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) { peer?.channel(label, changedTo: dataChannel.readyState) }

    func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        peer?.channel(label, received: buffer)
    }
}
