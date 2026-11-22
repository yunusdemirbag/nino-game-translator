// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation
import Security

/// sdb hataları (tv-kurulumu.md §9.3).
public enum SDBError: Error, Equatable, Sendable, CustomStringConvertible {
    case unreachable(String)
    /// Akış erken bitti ("TV bağlantıyı kapattı").
    case closed(String)
    case timeout
    case badFrame(String)
    case protocolError(String)
    case openRefused(String)
    case syncFailed(String)

    public var description: String {
        switch self {
        case let .unreachable(m): return m
        case let .closed(m): return m.isEmpty ? "TV bağlantıyı kapattı" : "TV bağlantıyı kapattı (\(m))"
        case .timeout: return "TV yanıt vermedi (süre doldu)"
        case let .badFrame(m): return m
        case let .protocolError(m): return m
        case .openRefused: return "TV kanalı açmadı"
        case let .syncFailed(m): return m
        }
    }

    /// Bağlantının koptuğunu gösteren hata mı (kurulum çıktısı sınıflaması §9.10 kural 1 için).
    public var isTransportLoss: Bool {
        switch self {
        case .closed, .timeout, .unreachable: return true
        default: return false
        }
    }
}

/// sdb çerçevesi: ADB ile aynı 24 baytlık düzen; sürüm 0x01000000, denetim toplamı her zaman denetlenir.
enum SDBFrame {
    static let version: UInt32 = 0x0100_0000
    static let maxPayload: UInt32 = 4096
    static let maxFrame: UInt32 = 16 * 1024 * 1024

    static func encode(_ m: ADBMessage) -> Data { m.encoded() }

    struct Header: Equatable {
        var command: UInt32
        var arg0: UInt32
        var arg1: UInt32
        var length: UInt32
        var checksum: UInt32
    }

    static func decodeHeader(_ d: Data) throws -> Header {
        precondition(d.count >= ADBMessage.headerSize)
        let w = (0..<6).map { d.readLE32(at: $0 * 4) }
        guard w[3] <= maxFrame else { throw SDBError.badFrame("Invalid length in frame (\(w[3]))") }
        guard w[5] == w[0] ^ 0xffff_ffff else { throw SDBError.badFrame("Invalid magic in frame") }
        return Header(command: w[0], arg0: w[1], arg1: w[2], length: w[3], checksum: w[4])
    }
}

/// Samsung sdbd'si için AUTH imzası: jeton önce SHA-1 ile özetlenir (Android adbd özetlemeden imzalar; §9.3).
extension ADBKey {
    func sdbSign(token: Data) throws -> Data {
        var err: Unmanaged<CFError>?
        guard let sig = SecKeyCreateSignature(privateKey, .rsaSignatureMessagePKCS1v15SHA1, token as CFData, &err) as Data? else {
            throw KeyError.signFailed(err.map { "\($0.takeRetainedValue())" } ?? "SecKeyCreateSignature")
        }
        return sig
    }
}

/// Tek sdb bağlantısı: el sıkışma, tek kanal, `shell:`, `capability:`, `sync:` (tv-kurulumu.md §9.3).
public actor SDBConnection {
    public struct Timing: Sendable {
        /// Okuma zaman aşımı (telefon 120 sn).
        public var read: TimeInterval = 120
        public init() {}
    }

    public static let hostBanner = "host::sdb-net-client"

    let stream: ADBByteStream
    let timing: Timing
    private var buffer = Data()
    public private(set) var maxData = Int(SDBFrame.maxPayload)
    public private(set) var banner: String?
    private var nextLocalID: UInt32 = 98 // 'a' + 1

    private struct Channel {
        var local: UInt32
        var remote: UInt32?
        var inbox = Data()
        var closed = false
        /// Son yazılan parçanın OKAY'i geldi mi.
        var acked = true
    }
    private var channel: Channel?

    public init(stream: ADBByteStream, timing: Timing = Timing()) {
        self.stream = stream
        self.timing = timing
    }

    public func close() { stream.close() }

    // MARK: Çerçeve

    func send(_ command: ADBMessage.Command, _ a0: UInt32, _ a1: UInt32, _ data: Data = Data()) async throws {
        do { try await stream.write(SDBFrame.encode(ADBMessage(command, a0, a1, data))) } catch {
            throw Self.map(error)
        }
    }

    static func map(_ e: Error) -> Error {
        if let a = e as? ADBError {
            switch a {
            case let .connectionClosed(m): return SDBError.closed(m)
            case .timeout: return SDBError.timeout
            case let .unreachable(m): return SDBError.unreachable(m)
            default: return SDBError.protocolError("\(a)")
            }
        }
        return e
    }

    private func fill(_ count: Int) async throws {
        while buffer.count < count {
            do { buffer.append(try await stream.read(max: 64 * 1024, timeout: timing.read)) } catch {
                throw Self.map(error)
            }
        }
    }

    func readFrame() async throws -> ADBMessage {
        try await fill(ADBMessage.headerSize)
        let h: SDBFrame.Header
        do { h = try SDBFrame.decodeHeader(buffer.prefix(ADBMessage.headerSize)) } catch {
            stream.close()
            throw error
        }
        let total = ADBMessage.headerSize + Int(h.length)
        try await fill(total)
        let data = Data(buffer[(buffer.startIndex + ADBMessage.headerSize)..<(buffer.startIndex + total)])
        buffer.removeFirst(total)
        guard ADBMessage.checksum(data) == h.checksum else {
            stream.close()
            throw SDBError.badFrame("Invalid checksum in frame")
        }
        return ADBMessage(rawCommand: h.command, arg0: h.arg0, arg1: h.arg1, data: data)
    }

    // MARK: El sıkışma

    /// CNXN gönderir, AUTH'u yanıtlar; TV'nin afişini döner.
    @discardableResult
    public func handshake(key: ADBKey, keyName: String = "nino@mac") async throws -> String {
        try await send(.cnxn, SDBFrame.version, SDBFrame.maxPayload, Data(Self.hostBanner.utf8))
        var tokens = 0
        var sentKey = false
        while true {
            let m = try await readFrame()
            switch m.kind {
            case .cnxn:
                if m.arg1 > 0 { maxData = Int(min(SDBFrame.maxPayload, m.arg1)) }
                let b = String(decoding: m.data, as: UTF8.self).trimmingCharacters(in: CharacterSet(charactersIn: "\u{0}"))
                banner = b
                return b
            case .auth:
                switch m.arg0 {
                case 1:
                    // İlk jeton imzalanır. TV imzayı tanımayıp yeni jeton verirse (adbd gibi) açık anahtar bir kez
                    // gönderilir; ardından da jeton gelirse TV anahtarı kabul etmiyor demektir (sonsuz döngü olmasın).
                    tokens += 1
                    if tokens == 1 {
                        try await send(.auth, 2, 0, try key.sdbSign(token: m.data))
                    } else if !sentKey {
                        sentKey = true
                        try await send(.auth, 3, 0, Data((try key.publicKeyLine(name: keyName) + "\u{0}").utf8))
                    } else {
                        stream.close()
                        throw SDBError.protocolError("TV sdb anahtarını kabul etmedi (AUTH)")
                    }
                case 3:
                    sentKey = true
                    let line = try key.publicKeyLine(name: keyName) + "\u{0}"
                    try await send(.auth, 3, 0, Data(line.utf8))
                default:
                    stream.close()
                    throw SDBError.protocolError("Unknown AUTH type")
                }
            default:
                stream.close()
                throw SDBError.protocolError("Expected CNXN or AUTH")
            }
        }
    }

    // MARK: Kanal

    /// Bir çerçeve okur, kanala dağıtır.
    private func pump() async throws {
        let m = try await readFrame()
        switch m.kind {
        case .okay:
            guard var c = channel, m.arg1 == c.local else { return }
            if c.remote == nil { c.remote = m.arg0 } else { c.acked = true }
            channel = c
        case .wrte:
            guard var c = channel, m.arg1 == c.local, !c.closed else {
                try await send(.clse, m.arg1, m.arg0)
                return
            }
            if c.remote == nil { c.remote = m.arg0 }
            c.inbox.append(m.data)
            channel = c
            try await send(.okay, c.local, m.arg0)
        case .clse:
            guard var c = channel, m.arg1 == c.local else { return }
            let wasClosed = c.closed
            c.closed = true
            channel = c
            if !wasClosed { try? await send(.clse, c.local, m.arg0) }
        case .open:
            try await send(.clse, m.arg1, m.arg0)
        default:
            return
        }
    }

    /// Hizmeti açar (`shell:…`, `capability:`, `sync:`).
    func open(_ service: String) async throws -> UInt32 {
        let local = nextLocalID
        nextLocalID &+= 1
        channel = Channel(local: local)
        try await send(.open, local, 0, Data((service + "\u{0}").utf8))
        while channel?.remote == nil {
            if channel?.closed == true {
                channel = nil
                throw SDBError.openRefused(service)
            }
            try await pump()
        }
        return local
    }

    func write(_ data: Data) async throws {
        var offset = data.startIndex
        while offset < data.endIndex {
            guard let c = channel, let remote = c.remote, !c.closed else { throw SDBError.closed("kanal kapandı") }
            let end = min(offset + maxData, data.endIndex)
            channel?.acked = false
            try await send(.wrte, c.local, remote, Data(data[offset..<end]))
            offset = end
            while channel?.acked == false {
                if channel?.closed == true { throw SDBError.closed("kanal kapandı") }
                try await pump()
            }
        }
    }

    /// En az `count` bayt (kanal kapanırsa eldeki).
    func read(atLeast count: Int) async throws -> Data {
        while let c = channel, c.inbox.count < count, !c.closed { try await pump() }
        guard var c = channel else { return Data() }
        let n = min(count, c.inbox.count)
        let out = Data(c.inbox.prefix(n))
        c.inbox.removeFirst(n)
        channel = c
        return out
    }

    func readToEnd() async throws -> Data {
        while let c = channel, !c.closed { try await pump() }
        let out = channel?.inbox ?? Data()
        channel = nil
        return out
    }

    func closeChannel() async {
        guard let c = channel else { return }
        channel = nil
        if !c.closed, let remote = c.remote { try? await send(.clse, c.local, remote) }
    }

    // MARK: Hizmetler

    /// `shell:<komut>` çıktısının tamamı (UTF-8).
    public func shell(_ command: String) async throws -> String {
        _ = try await open("shell:" + command)
        let out = try await readToEnd()
        return String(decoding: out, as: UTF8.self)
    }

    /// `capability:` yanıtı.
    public func capability() async throws -> [String: String] {
        _ = try await open("capability:")
        return Self.parseCapability(try await readToEnd())
    }

    /// İlk 2 bayt atlanır; `anahtar:değer` satırları, boş parçalar atılır, tam 2 parça kalanlar; ilk gelen geçerli.
    static func parseCapability(_ data: Data) -> [String: String] {
        let text = String(decoding: data.dropFirst(2), as: UTF8.self)
        var out: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: ":", omittingEmptySubsequences: true)
            guard parts.count == 2 else { continue }
            let k = String(parts[0]), v = String(parts[1])
            if out[k] == nil { out[k] = v }
        }
        return out
    }

    /// `sync:` ile dosya gönderir: SEND yol, DATA (64 KB), DONE zaman; yanıt OKAY / FAIL.
    public func push(_ data: Data, to path: String, mtime: UInt32) async throws {
        _ = try await open("sync:")
        func packet(_ id: String, _ payload: Data) -> Data {
            var d = Data(id.utf8)
            d.appendLE(UInt32(payload.count))
            d.append(payload)
            return d
        }
        try await write(packet("SEND", Data(path.utf8)))
        var offset = data.startIndex
        while offset < data.endIndex {
            let end = min(offset + 64 * 1024, data.endIndex)
            try await write(packet("DATA", Data(data[offset..<end])))
            offset = end
        }
        // DONE: tarifteki gibi uzunluk 4, veri zaman (ADB'de zaman uzunluk alanındadır).
        var stamp = Data()
        stamp.appendLE(mtime)
        try await write(packet("DONE", stamp))
        while true {
            let h = try await read(atLeast: 8)
            guard h.count == 8 else { await closeChannel(); throw SDBError.closed("sync") }
            let id = String(decoding: h.prefix(4), as: UTF8.self)
            let len = Int(h.readLE32(at: 4))
            switch id {
            case "OKAY":
                await closeChannel()
                return
            case "FAIL":
                let body = len > 0 ? try await read(atLeast: min(len, 64 * 1024)) : Data()
                let msg = String(decoding: body, as: UTF8.self)
                await closeChannel()
                throw SDBError.syncFailed("sdb sync: FAIL: \(msg.isEmpty ? "unknown" : msg)")
            default:
                continue
            }
        }
    }
}
