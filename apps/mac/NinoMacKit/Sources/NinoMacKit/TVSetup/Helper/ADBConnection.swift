// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// Tek ADB bağlantısı: CNXN/AUTH el sıkışması, akışlar (OPEN/OKAY/WRTE/CLSE), komutlar ve sync ile dosya gönderme.
///
/// Akışlar sırayla kullanılır (aynı anda bir iş). Kurallar (protocol.md): OKAY gelmeden ikinci WRTE gönderilmez;
/// gelen her WRTE'ye OKAY verilir; veri karşı tarafın CNXN'de söylediği en büyük boyuta bölünür.
public actor ADBConnection {
    public struct Timing: Sendable {
        /// Sıradan bir çerçeve için en uzun bekleme.
        public var frame: TimeInterval = 15
        /// Açık anahtar gönderildikten sonra TV'deki onay için.
        public var approval: TimeInterval = 60
        public init() {}
    }

    let stream: ADBByteStream
    let timing: Timing
    private var buffer = Data()
    public private(set) var maxData = ADBMessage.legacyMaxData
    public private(set) var banner: ADBBanner?
    private var nextLocalID: UInt32 = 1

    private struct StreamState {
        var remote: UInt32?
        var inbox = Data()
        var closed = false
        var canWrite = false
    }
    private var streams: [UInt32: StreamState] = [:]

    public init(stream: ADBByteStream, timing: Timing = Timing()) {
        self.stream = stream
        self.timing = timing
    }

    public func close() { stream.close() }

    // MARK: Çerçeve okuma/yazma

    func send(_ m: ADBMessage) async throws {
        try await stream.write(m.encoded())
    }

    private func fill(_ count: Int, timeout: TimeInterval) async throws {
        while buffer.count < count {
            let chunk = try await stream.read(max: 64 * 1024, timeout: timeout)
            buffer.append(chunk)
        }
    }

    func readFrame(timeout: TimeInterval? = nil) async throws -> ADBMessage {
        let t = timeout ?? timing.frame
        try await fill(ADBMessage.headerSize, timeout: t)
        let header: ADBMessage.Header
        do { header = try ADBMessage.decodeHeader(buffer.prefix(ADBMessage.headerSize)) } catch {
            stream.close()
            throw ADBError.protocolError("\(error)")
        }
        let total = ADBMessage.headerSize + Int(header.length)
        try await fill(total, timeout: t)
        let data = Data(buffer[(buffer.startIndex + ADBMessage.headerSize)..<(buffer.startIndex + total)])
        buffer.removeFirst(total)
        return ADBMessage(rawCommand: header.command, arg0: header.arg0, arg1: header.arg1, data: data)
    }

    // MARK: El sıkışma

    /// CNXN gönderir, AUTH'u yanıtlar. Önce saklı anahtarla imza; TV tanımazsa açık anahtar gönderilir ve
    /// `onApprovalNeeded` çağrılır (TV ekranında onay kutusu). `offerKey: false`: tanınmayan anahtarda açık anahtar
    /// gönderilmez, TV'de onay kutusu çıkmaz; `notApproved` atılır (sessiz denemeler, ör. hata ayıklama kaydı).
    @discardableResult
    public func handshake(key: ADBKey, keyName: String = "nino@mac", offerKey: Bool = true,
                          onApprovalNeeded: @Sendable () -> Void = {}) async throws -> ADBBanner {
        try await send(ADBMessage(.cnxn, ADBMessage.version, ADBMessage.maxData, ADBMessage.hostBanner()))
        var signed = false
        var sentKey = false
        while true {
            let m: ADBMessage
            do {
                m = try await readFrame(timeout: sentKey ? timing.approval : timing.frame)
            } catch let e as ADBError {
                if sentKey, e == .timeout || isClosed(e) { stream.close(); throw ADBError.notApproved }
                throw e
            }
            switch m.kind {
            case .cnxn:
                maxData = max(1024, min(Int(m.arg1), Int(ADBMessage.maxData)))
                let b = ADBBanner(m.data)
                banner = b
                return b
            case .auth where m.arg0 == ADBMessage.AuthType.token.rawValue:
                if !signed {
                    signed = true
                    try await send(ADBMessage(.auth, ADBMessage.AuthType.signature.rawValue, 0, try key.sign(token: m.data)))
                } else if !offerKey {
                    stream.close()
                    throw ADBError.notApproved
                } else if !sentKey {
                    sentKey = true
                    let line = try key.publicKeyLine(name: keyName) + "\u{0}"
                    try await send(ADBMessage(.auth, ADBMessage.AuthType.rsaPublicKey.rawValue, 0, Data(line.utf8)))
                    onApprovalNeeded()
                }
                // Açık anahtardan sonra gelen yeni jeton: onay hâlâ bekleniyor.
            case .stls:
                stream.close()
                throw ADBError.tlsRequired
            default:
                continue
            }
        }
    }

    private func isClosed(_ e: ADBError) -> Bool {
        if case .connectionClosed = e { return true }
        return false
    }

    // MARK: Akışlar

    /// Bir çerçeve okur ve ilgili akışa dağıtır.
    private func pump(timeout: TimeInterval?) async throws {
        let m = try await readFrame(timeout: timeout)
        let local = m.arg1
        switch m.kind {
        case .okay:
            guard var s = streams[local] else { return }
            if s.remote == nil { s.remote = m.arg0 } else { s.canWrite = true }
            streams[local] = s
        case .wrte:
            guard var s = streams[local], !s.closed else { return }
            s.inbox.append(m.data)
            streams[local] = s
            try await send(ADBMessage(.okay, local, m.arg0))
        case .clse:
            guard var s = streams[local] else { return }
            s.closed = true
            streams[local] = s
        default:
            return
        }
    }

    /// Hizmeti açar (`shell:…`, `exec:…`, `sync:`); yerel akış kimliğini döner.
    public func open(_ service: String) async throws -> UInt32 {
        let local = nextLocalID
        nextLocalID &+= 1
        streams[local] = StreamState()
        try await send(ADBMessage(.open, local, 0, ADBMessage.service(service)))
        while streams[local]?.remote == nil {
            if streams[local]?.closed == true {
                streams[local] = nil
                throw ADBError.openRefused(service)
            }
            try await pump(timeout: nil)
        }
        // OPEN, karşı yönde de "hazır" demektir: ilk WRTE için OKAY gerekmez.
        streams[local]?.canWrite = true
        return local
    }

    /// Veriyi parçalara bölüp yazar; her parçadan sonra OKAY beklenir.
    public func write(_ local: UInt32, _ data: Data, timeout: TimeInterval? = nil) async throws {
        var offset = data.startIndex
        while offset < data.endIndex {
            guard let s = streams[local], let remote = s.remote, !s.closed else {
                throw ADBError.connectionClosed("stream closed")
            }
            while streams[local]?.canWrite == false {
                if streams[local]?.closed == true { throw ADBError.connectionClosed("stream closed") }
                try await pump(timeout: timeout)
            }
            let end = min(offset + maxData, data.endIndex)
            streams[local]?.canWrite = false
            try await send(ADBMessage(.wrte, local, remote, Data(data[offset..<end])))
            offset = end
        }
    }

    /// En az `count` bayt gelene dek okur ve hepsini kuyruktan alır (akış kapanırsa elde olanı).
    public func read(_ local: UInt32, atLeast count: Int, timeout: TimeInterval? = nil) async throws -> Data {
        while let s = streams[local], s.inbox.count < count, !s.closed { try await pump(timeout: timeout) }
        let out = streams[local]?.inbox ?? Data()
        streams[local]?.inbox = Data()
        return out
    }

    /// Akış kapanana dek gelen her şey.
    public func readToEnd(_ local: UInt32, timeout: TimeInterval? = nil) async throws -> Data {
        while let s = streams[local], !s.closed { try await pump(timeout: timeout) }
        let out = streams[local]?.inbox ?? Data()
        streams[local] = nil
        return out
    }

    /// Akışı bizim taraftan kapatır.
    public func closeStream(_ local: UInt32) async {
        guard let s = streams[local] else { return }
        streams[local] = nil
        if !s.closed, let remote = s.remote { try? await send(ADBMessage(.clse, local, remote)) }
    }

    /// Hizmeti açar, varsa girdiyi yazar ve akış kapanana dek çıktıyı toplar.
    public func run(_ service: String, input: Data? = nil, timeout: TimeInterval? = nil) async throws -> Data {
        let local = try await open(service)
        if let input, !input.isEmpty { try await write(local, input, timeout: timeout) }
        return try await readToEnd(local, timeout: timeout)
    }

    /// `shell:` komutunun çıktısı (\r atılır).
    public func shell(_ command: String, timeout: TimeInterval? = nil) async throws -> String {
        let out = try await run("shell:" + command, timeout: timeout)
        return String(decoding: out, as: UTF8.self).replacingOccurrences(of: "\r", with: "")
    }

    // MARK: sync ile dosya gönderme (eski cihazlar)

    /// `sync:` hizmetiyle `path`'e yazar: SEND "yol,kip", DATA parçaları (en çok 64 KB), DONE zaman; yanıt OKAY/FAIL.
    public func push(_ data: Data, to path: String, mode: Int = 0o644, mtime: UInt32 = 0,
                     timeout: TimeInterval? = nil) async throws {
        let local = try await open("sync:")
        var req = Data()
        let target = Data("\(path),\(mode)".utf8)
        req.append(contentsOf: Array("SEND".utf8)); req.appendLE(UInt32(target.count)); req.append(target)
        var offset = data.startIndex
        while offset < data.endIndex {
            let end = min(offset + 64 * 1024, data.endIndex)
            req.append(contentsOf: Array("DATA".utf8)); req.appendLE(UInt32(end - offset))
            req.append(data[offset..<end])
            offset = end
        }
        req.append(contentsOf: Array("DONE".utf8)); req.appendLE(mtime)
        try await write(local, req, timeout: timeout)
        var reply = try await read(local, atLeast: 8, timeout: timeout)
        guard reply.count >= 8 else { await closeStream(local); throw ADBError.connectionClosed("sync") }
        let id = String(decoding: reply.prefix(4), as: UTF8.self)
        if id == "FAIL" {
            let len = Int(reply.readLE32(at: 4))
            if reply.count < 8 + len { reply.append(try await read(local, atLeast: 8 + len - reply.count, timeout: timeout)) }
            let msg = String(decoding: reply.dropFirst(8).prefix(len), as: UTF8.self)
            await closeStream(local)
            throw ADBError.protocolError("sync: \(msg)")
        }
        guard id == "OKAY" else { await closeStream(local); throw ADBError.protocolError("sync: \(id)") }
        var quit = Data("QUIT".utf8); quit.appendLE(0)
        try? await write(local, quit, timeout: timeout)
        await closeStream(local)
    }
}
