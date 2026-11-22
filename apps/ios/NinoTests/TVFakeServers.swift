// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation
import Security
@testable import Nino

/// 127.0.0.1'de rastgele portta dinleyen, her bağlantıyı ayrı iş parçacığında işleyen sahte TV sunucusu.
final class LoopbackServer: @unchecked Sendable {
    private var fd: Int32
    private(set) var port: UInt16 = 0
    private let handler: (TCPChannel) -> Void
    private let stopped = LockedValue(false)

    init(_ handler: @escaping (TCPChannel) -> Void) throws {
        self.handler = handler
        fd = socket(AF_INET, SOCK_STREAM, 0)
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &on, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard bound == 0, listen(fd, 8) == 0 else { throw WireError.connect("test listener") }
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &len) }
        }
        port = UInt16(bigEndian: addr.sin_port)
        let listenFD = fd
        let thread = Thread { [weak self] in
            while true {
                let client = accept(listenFD, nil, nil)
                guard client >= 0, let self, !self.stopped.get() else { return }
                let channel = TCPChannel(acceptedDescriptor: client)
                channel.receiveTimeout = 20
                Thread.detachNewThread { self.handler(channel); channel.shutdown() }
            }
        }
        thread.start()
    }

    func stop() {
        stopped.set(true)
        Darwin.shutdown(fd, SHUT_RDWR)
        Darwin.close(fd)
    }
}

/// Sahte adbd/sdbd: çerçeveleri okur, hizmetleri `services` ile yanıtlar.
final class FakeWireDevice {
    struct Service {
        /// Hizmet adının başı ("shell:dumpsys").
        let prefix: String
        /// Gelen girdiyi bekleme boyu (exec:cmd package install -S N için N).
        var inputLength: (String) -> Int = { _ in 0 }
        let reply: (String, Bytes) -> String
    }

    let verifySum: Bool
    let banner: Bytes
    var services: [Service] = []
    /// Kimlik doğrulama istenir mi; istenirse güvenilen anahtar, onaylanacak açık anahtar satırı ve imza türü.
    var requireAuth = false
    let trustedKey = LockedValue<SecKey?>(nil)
    var expectedKeyLine: String?
    var signature: SecKeyAlgorithm = .rsaSignatureDigestPKCS1v15SHA1
    let approvals = LockedValue(0)
    let seenServices = LockedValue<[String]>([])
    let received = LockedValue<[String: Bytes]>([:])

    init(verifySum: Bool, banner: String) {
        self.verifySum = verifySum
        self.banner = Bytes(banner.utf8)
    }

    func serve(_ channel: TCPChannel) {
        let reader = ChannelReader(channel)
        func send(_ m: WireMessage) { try? channel.send(m.encoded) }
        func read() -> WireMessage? { try? WireMessage.read(from: reader, verifySum: verifySum) }
        guard let hello = read(), hello.command == WireMessage.connect else { return }
        if requireAuth {
            var token = Bytes.random(20)
            send(WireMessage(command: WireMessage.auth, arg0: 1, arg1: 0, payload: token))
            authLoop: while let m = read() {
                guard m.command == WireMessage.auth else { return }
                switch m.arg0 {
                case 2:
                    if let key = trustedKey.get(),
                       RSAVerify.check(key, signature, message: token, signature: m.payload) {
                        break authLoop
                    }
                    token = Bytes.random(20)
                    send(WireMessage(command: WireMessage.auth, arg0: 1, arg1: 0, payload: token))
                case 3:
                    let line = String(decoding: m.payload.filter { $0 != 0 }, as: UTF8.self)
                    guard line == expectedKeyLine else { return }
                    approvals.set(approvals.get() + 1)
                    break authLoop
                default: return
                }
            }
        }
        send(WireMessage(command: WireMessage.connect, arg0: 0x0100_0000, arg1: 4096, payload: banner))
        var nextRemote: UInt32 = 100
        while let m = read() {
            guard m.command == WireMessage.open else { continue }
            let name = String(decoding: m.payload.filter { $0 != 0 }, as: UTF8.self)
            seenServices.set(seenServices.get() + [name])
            nextRemote += 1
            let me = nextRemote, them = m.arg0
            guard let service = services.first(where: { name.hasPrefix($0.prefix) }) else {
                send(WireMessage(command: WireMessage.close, arg0: 0, arg1: them))
                continue
            }
            send(WireMessage(command: WireMessage.okay, arg0: me, arg1: them))
            var input = Bytes()
            let need = service.inputLength(name)
            var syncMode = name == "sync:"
            while input.count < need || syncMode {
                guard let w = read() else { return }
                if w.command == WireMessage.close { break }
                guard w.command == WireMessage.write else { continue }
                input += w.payload
                send(WireMessage(command: WireMessage.okay, arg0: me, arg1: them))
                if syncMode, let file = FakeWireDevice.completeSync(input) {
                    received.set(received.get().merging([file.path: file.data]) { $1 })
                    syncMode = false
                }
            }
            let reply = Bytes(service.reply(name, input).utf8)
            if !reply.isEmpty {
                send(WireMessage(command: WireMessage.write, arg0: me, arg1: them, payload: reply))
                guard let ack = read(), ack.command == WireMessage.okay else { return }
            }
            send(WireMessage(command: WireMessage.close, arg0: me, arg1: them))
            // İstemcinin CLSE'si
            _ = read()
        }
    }

    /// sync: SEND yol, DATA…, DONE bitti mi? Bitince yol ve veri.
    static func completeSync(_ input: Bytes) -> (path: String, data: Bytes)? {
        var i = 0
        var path = ""
        var data = Bytes()
        while i + 8 <= input.count {
            let id = String(decoding: input[i..<i + 4], as: UTF8.self)
            let n = Int(input.le32(at: i + 4))
            if id == "DONE" { return (path, data) }
            guard i + 8 + n <= input.count else { return nil }
            let body = Array(input[(i + 8)..<(i + 8 + n)])
            if id == "SEND" { path = String(decoding: body, as: UTF8.self) }
            if id == "DATA" { data += body }
            i += 8 + n
        }
        return nil
    }
}
