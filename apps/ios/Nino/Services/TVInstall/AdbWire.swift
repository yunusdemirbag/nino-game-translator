// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

// adb ve Samsung'un sdb'si aynı çerçeveyi kullanır: 24 baytlık küçük-endian başlık (komut, iki değişken, veri boyu,
// veri toplamı, komutun tersi) ve veri. Akışlar OPEN/OKAY/WRTE/CLSE ile açılır; her WRTE karşı taraftan OKAY bekler.
// Protokol: AOSP packages/modules/adb/protocol.txt.

struct WireMessage: Equatable {
    static let connect: UInt32 = 0x4E58_4E43   // CNXN
    static let auth: UInt32 = 0x4854_5541      // AUTH
    static let open: UInt32 = 0x4E45_504F      // OPEN
    static let okay: UInt32 = 0x5941_4B4F      // OKAY
    static let write: UInt32 = 0x4554_5257     // WRTE
    static let close: UInt32 = 0x4553_4C43     // CLSE
    static let startTLS: UInt32 = 0x534C_5453  // STLS
    static let headerSize = 24

    var command: UInt32
    var arg0: UInt32
    var arg1: UInt32
    var payload: Bytes = []

    static func sum(_ data: Bytes) -> UInt32 { data.reduce(0) { $0 &+ UInt32($1) } }

    var encoded: Bytes {
        var out = Bytes()
        out.reserveCapacity(WireMessage.headerSize + payload.count)
        out.putLE32(command)
        out.putLE32(arg0)
        out.putLE32(arg1)
        out.putLE32(UInt32(payload.count))
        out.putLE32(WireMessage.sum(payload))
        out.putLE32(~command)
        return out + payload
    }

    /// Çerçeve okur. `verifySum`: sdb toplamı denetler; yeni adbd'ler toplamı 0 gönderir.
    static func read(from reader: ChannelReader, verifySum: Bool, maxPayload: Int = 1 << 24) throws -> WireMessage {
        let head = try reader.read(exactly: headerSize)
        let command = head.le32(at: 0)
        let length = Int(head.le32(at: 12))
        guard head.le32(at: 20) == ~command else {
            throw WireError.malformed(String(format: "bad frame magic for %08x", command))
        }
        guard length <= maxPayload else { throw WireError.malformed("frame too large (\(length))") }
        let payload = length > 0 ? try reader.read(exactly: length) : []
        if verifySum, head.le32(at: 16) != sum(payload) { throw WireError.malformed("frame checksum") }
        return WireMessage(command: command, arg0: head.le32(at: 4), arg1: head.le32(at: 8), payload: payload)
    }

    var name: String { String(bytes: le32Bytes(command), encoding: .ascii) ?? String(format: "%08x", command) }
}

/// Çerçeve bağlantısı ve üstündeki akışlar. Bir anda tek akış kullanılır; çerçeveler çağıranın iş parçacığında okunur.
class WireLink {
    private(set) var channel: ByteChannel
    private(set) var reader: ChannelReader
    let verifySum: Bool
    /// Bir WRTE'deki en çok veri (CNXN'de karşı taraf bildirir).
    var maxPayload = 4096
    private var lastLocalID: UInt32

    init(channel: ByteChannel, verifySum: Bool, firstLocalID: UInt32 = 0) {
        self.channel = channel
        reader = ChannelReader(channel)
        self.verifySum = verifySum
        lastLocalID = firstLocalID
    }

    /// Alttaki akışı değiştirir (STLS sonrası TLS).
    func replaceChannel(_ newChannel: ByteChannel) {
        channel = newChannel
        reader = ChannelReader(newChannel)
    }

    func send(_ m: WireMessage) throws { try channel.send(m.encoded) }
    func receive() throws -> WireMessage { try WireMessage.read(from: reader, verifySum: verifySum) }

    func open(_ service: String) throws -> WireStream {
        lastLocalID += 1
        let stream = WireStream(localID: lastLocalID, link: self)
        try send(WireMessage(command: WireMessage.open, arg0: stream.localID, arg1: 0, payload: Bytes(service.utf8) + [0]))
        while stream.remoteID == 0 {
            if stream.isClosed { throw WireError.malformed("the TV refused service \(service.prefix(40))") }
            try stream.pump()
        }
        return stream
    }

    /// Hizmeti açar, girdiyi yazar, hizmet kapanana dek bütün çıktıyı toplar.
    func run(_ service: String, input: Bytes? = nil) throws -> String {
        let stream = try open(service)
        defer { stream.close() }
        if let input { try stream.write(input) }
        return String(decoding: try stream.readToEnd(), as: UTF8.self)
    }

    func close() { channel.shutdown() }
}

final class WireStream {
    let localID: UInt32
    fileprivate(set) var remoteID: UInt32 = 0
    private var inbox: [Bytes] = []
    private var acknowledged = false
    private(set) var isClosed = false
    private unowned let link: WireLink

    fileprivate init(localID: UInt32, link: WireLink) {
        self.localID = localID
        self.link = link
    }

    /// Bir sonraki veri parçası; akış kapandıysa nil.
    func readChunk() throws -> Bytes? {
        while inbox.isEmpty {
            if isClosed { return nil }
            try pump()
        }
        return inbox.removeFirst()
    }

    func readToEnd() throws -> Bytes {
        var all = Bytes()
        while let chunk = try readChunk() { all += chunk }
        return all
    }

    func read(exactly count: Int) throws -> Bytes {
        var out = Bytes()
        while out.count < count {
            guard let chunk = try readChunk() else { throw WireError.closed }
            let need = count - out.count
            if chunk.count > need {
                out += chunk[0..<need]
                inbox.insert(Array(chunk[need...]), at: 0)
            } else {
                out += chunk
            }
        }
        return out
    }

    /// Veriyi parça parça yazar; her parça için karşı tarafın OKAY'ini bekler.
    func write(_ data: Bytes) throws {
        var offset = 0
        while offset < data.count {
            guard !isClosed else { throw WireError.closed }
            let end = min(data.count, offset + link.maxPayload)
            acknowledged = false
            try link.send(WireMessage(command: WireMessage.write, arg0: localID, arg1: remoteID, payload: Array(data[offset..<end])))
            while !acknowledged {
                guard !isClosed else { throw WireError.closed }
                try pump()
            }
            offset = end
        }
    }

    /// Bir çerçeve okuyup işler.
    func pump() throws {
        let m = try link.receive()
        switch m.command {
        case WireMessage.okay where m.arg1 == localID:
            if remoteID == 0 { remoteID = m.arg0 } else { acknowledged = true }
        case WireMessage.write where m.arg1 == localID:
            if remoteID == 0 { remoteID = m.arg0 }
            inbox.append(m.payload)
            try link.send(WireMessage(command: WireMessage.okay, arg0: localID, arg1: m.arg0))
        case WireMessage.write:
            try link.send(WireMessage(command: WireMessage.close, arg0: m.arg1, arg1: m.arg0))
        case WireMessage.close where m.arg1 == localID || m.arg1 == 0:
            isClosed = true
            try? link.send(WireMessage(command: WireMessage.close, arg0: localID, arg1: m.arg0))
        case WireMessage.open:
            // TV'nin açmak istediği akışlar (ters bağlantı) reddedilir.
            try link.send(WireMessage(command: WireMessage.close, arg0: 0, arg1: m.arg0))
        default:
            break
        }
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        try? link.send(WireMessage(command: WireMessage.close, arg0: localID, arg1: remoteID))
    }
}

/// `sync:` alt protokolü: 4 harfli kimlik + küçük-endian uzunluk + veri.
enum SyncProtocol {
    static func packet(_ id: String, _ body: ArraySlice<UInt8>) -> Bytes {
        var out = Bytes(id.utf8)
        out.putLE32(UInt32(body.count))
        return out + body
    }

    /// Dosyayı gönderir. `doneCarriesLength`: sdb'nin DONE'u da uzunluk alanı taşır (Samsung sdbd'de böyle çalışıyor).
    static func push(_ data: Bytes, to remote: String, over link: WireLink, mode: Int?, doneCarriesLength: Bool) throws {
        let stream = try link.open("sync:")
        defer { stream.close() }
        let target = mode.map { "\(remote),\(0o100000 | $0)" } ?? remote
        try stream.write(packet("SEND", ArraySlice(Bytes(target.utf8))))
        var offset = 0
        while offset < data.count {
            let end = min(data.count, offset + 64 * 1024)
            try stream.write(packet("DATA", data[offset..<end]))
            offset = end
        }
        let stamp = UInt32(Date().timeIntervalSince1970)
        if doneCarriesLength {
            try stream.write(packet("DONE", ArraySlice(le32Bytes(stamp))))
        } else {
            try stream.write(Bytes("DONE".utf8) + le32Bytes(stamp))
        }
        while true {
            let head = try stream.read(exactly: 8)
            let id = String(decoding: head[0..<4], as: UTF8.self)
            let length = Int(head.le32(at: 4))
            if id == "OKAY" { return }
            let body = (1...65_536).contains(length) ? try stream.read(exactly: length) : []
            if id == "FAIL" {
                throw WireError.malformed("sync failed: \(String(decoding: body, as: UTF8.self))")
            }
        }
    }
}

/// adb ve sdb'nin kimlik anahtarı: 2048 bit RSA.
struct AdbIdentity {
    let key: RSAPrivateKey
    /// adb TLS'i için kendinden imzalı sertifika dosyası.
    let certificateFile: URL
    var label = "nino@iphone"

    static func stored(in directory: URL) throws -> AdbIdentity {
        let file = directory.appendingPathComponent("adbkey")
        return AdbIdentity(key: try RSAPrivateKey.stored(at: file), certificateFile: directory.appendingPathComponent("adbkey.cer"))
    }

    /// Android'in RSAPublicKey yapısı: sözcük sayısı, n0inv, n ve R² mod n (küçük-endian), e.
    var androidPublicKey: Bytes {
        let n = BigNum(bigEndian: key.modulus)
        let size = 256
        let rr = (BigNum(1) << (size * 8 * 2)) % n
        var out = Bytes()
        out.putLE32(UInt32(size / 4))
        out.putLE32(BigNum.negInverse32(n.words.first ?? 1))
        out += n.littleEndian(count: size)
        out += rr.littleEndian(count: size)
        out.putLE32(BigNum(bigEndian: key.exponent).words.first ?? 65_537)
        return out
    }

    /// "base64 kullanıcı@cihaz" satırı (adb'nin adbkey.pub biçimi).
    var publicKeyLine: String { Data(androidPublicKey).base64EncodedString() + " " + label }

    /// adbd: TV'nin 20 baytlık jetonu SHA-1 özeti yerine geçer (yeniden özetlenmez).
    func signAdbToken(_ token: Bytes) throws -> Bytes { try key.sign(token, .rsaSignatureDigestPKCS1v15SHA1) }

    /// sdbd: jeton SHA-1 ile özetlenip imzalanır.
    func signSdbToken(_ token: Bytes) throws -> Bytes { try key.sign(token, .rsaSignatureMessagePKCS1v15SHA1) }
}
