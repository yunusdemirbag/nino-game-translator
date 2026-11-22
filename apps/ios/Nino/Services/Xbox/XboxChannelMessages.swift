// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// Ev yayınının WebRTC veri kanalları ve iletileri. Xbox, el sıkışması yapılmayan ya da gösterilen karelerin onayı
/// gelmeyen yayını kısa sürede (yaklaşık 40 sn) kapatır; bu yüzden kumanda girdisi göndermesek de bu iletiler gider.
enum XboxChannelMessages {
    /// Oluşturma sırasıyla kanal adı ve alt protokol.
    static let channels: [(label: String, subprotocol: String)] = [
        ("input", "1.0"), ("chat", "chatV1"), ("control", "controlV1"), ("message", "messageV1"),
    ]

    /// `message` kanalı açılınca gönderilir.
    static let handshake = XboxJSON.text(["type": "Handshake", "version": "messageV1",
                                          "id": "f9c5f412-0e69-4ede-8e62-92c7f5358c56", "cv": ""])

    static func isHandshakeAck(_ text: String) -> Bool {
        XboxJSON.string((try? XboxJSON.object(text)) ?? [:], "type") == "HandshakeAck"
    }

    /// El sıkışmadan sonra `control` kanalına.
    static let controlMessages = [
        XboxJSON.text(["message": "authorizationRequest", "accessKey": "4BDB3609-C1F1-4195-9B37-FEFF45DA8B8E"]),
        XboxJSON.text(["message": "gamepadChanged", "gamepadIndex": 0, "wasAdded": true] as XboxJSON.Object),
    ]

    /// İstenen görüntü boyu: 1080p ya da (ayarla) 720p.
    static func screenSize(lowResolution: Bool) -> (width: Int, height: Int) {
        lowResolution ? (1280, 720) : (1920, 1080)
    }

    /// El sıkışmadan sonra `message` kanalına: istemcinin ekranı ve özellikleri.
    static func clientMessages(width: Int = 1920, height: Int = 1080) -> [String] {
        let id = "41f93d5a-900f-4d33-b7a1-2d4ca6747072"
        func wrap(_ target: String, _ content: XboxJSON.Object) -> String {
            XboxJSON.text(["type": "Message", "target": target, "content": XboxJSON.text(content), "id": id, "cv": ""])
        }
        return [
            wrap("/streaming/systemUi/configuration", ["version": [0, 1, 0], "systemUis": [Int]()]),
            wrap("/streaming/properties/clientappinstallidchanged", ["clientAppInstallId": "c11ddb2e-c7e3-4f02-a62b-fd5448e0b851"]),
            wrap("/streaming/characteristics/orientationchanged", ["orientation": 0]),
            wrap("/streaming/characteristics/touchinputenabledchanged", ["touchInputEnabled": false]),
            wrap("/streaming/characteristics/clientdevicecapabilities", [:]),
            wrap("/streaming/characteristics/dimensionschanged", [
                "horizontal": width, "vertical": height, "preferredWidth": width, "preferredHeight": height,
                "safeAreaLeft": 0, "safeAreaTop": 0, "safeAreaRight": width, "safeAreaBottom": height,
                "supportsCustomResolution": true,
            ]),
        ]
    }

    /// `input` kanalının ikili paketleri küçük sonludur.
    private struct Packet {
        var data = Data()
        mutating func u8(_ v: UInt8) { data.append(v) }
        mutating func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        mutating func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        mutating func f64(_ v: Double) { withUnsafeBytes(of: v.bitPattern.littleEndian) { data.append(contentsOf: $0) } }
    }

    /// İstemci bilgisi (tür 8): sıra, an (ms), en çok dokunma noktası. 15 bayt.
    static func clientMetadata(sequence: UInt32 = 0, at ms: Double, touchPoints: UInt8 = 2) -> Data {
        var p = Packet()
        p.u16(8)
        p.u32(sequence)
        p.f64(ms)
        p.u8(touchPoints)
        return p.data
    }

    /// Bir pakette en çok bu kadar kare onaylanır.
    static let acksPerPacket = 29

    /// Gösterilen karelerin onayı (tür 1): sıra, an (ms), kare sayısı; her kare için karenin RTP zaman damgası ve
    /// varış/çözülme/gösterim/paketleme anları (ms, u32).
    static func frameAcks(sequence: UInt32, at ms: Double, frames: [ShownFrame]) -> Data {
        var p = Packet()
        p.u16(1)
        p.u32(sequence)
        p.f64(ms)
        p.u8(UInt8(min(frames.count, Int(UInt8.max))))
        func stamp(_ v: Double) -> UInt32 { UInt32(truncatingIfNeeded: Int64(v)) }
        for f in frames {
            p.u32(f.rtpTimestamp)
            p.u32(stamp(f.arrivedMs)) // ilk paket
            p.u32(stamp(f.arrivedMs)) // son paket
            p.u32(stamp(f.decodedMs)) // çözülme
            p.u32(stamp(f.decodedMs)) // gösterim
            p.u32(stamp(ms))          // onay paketi hazırlandı
            p.u32(stamp(ms))          // gönderildi
        }
        return p.data
    }

    struct ShownFrame: Equatable {
        let rtpTimestamp: UInt32
        let arrivedMs: Double
        let decodedMs: Double
    }

    /// Teklifte stereo ses istenir (ilk Opus satırına).
    static func preferStereo(_ sdp: String) -> String {
        guard let r = sdp.range(of: "useinbandfec=1") else { return sdp }
        return sdp.replacingCharacters(in: r, with: "useinbandfec=1; stereo=1")
    }
}
