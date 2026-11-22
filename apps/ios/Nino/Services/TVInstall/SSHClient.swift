// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import CommonCrypto
import CryptoKit
import Foundation
import Security

// LG geliştirici modunun SSH sunucusu (9922, kullanıcı "prisoner") için küçük SSH-2 istemcisi (RFC 4253/4252/4254):
// anahtar değişimi curve25519-sha256, ecdh-sha2-nistp256/384/521, diffie-hellman-group14-sha256/-sha1 ve group1-sha1
// (eski webOS'lardaki dropbear için); şifre aes128/192/256-ctr; doğrulama hmac-sha2-256/512 ve hmac-sha1 (etm dahil);
// kimlik RSA anahtarı (rsa-sha2-512/256, ssh-rsa). Tek iş: komut çalıştırmak, girdisini yazmak, çıktısını okumak.

struct SSHFailure: Error, CustomStringConvertible {
    enum Kind { case connect, auth, protocolError }
    let kind: Kind
    let description: String
    init(_ kind: Kind, _ description: String) {
        self.kind = kind
        self.description = description
    }
}

// MARK: - Kodlama

struct SSHWriter {
    var bytes = Bytes()
    mutating func byte(_ v: UInt8) { bytes.append(v) }
    mutating func bool(_ v: Bool) { bytes.append(v ? 1 : 0) }
    mutating func uint32(_ v: UInt32) { bytes.putBE32(v) }
    mutating func string(_ v: Bytes) { bytes.putBE32(UInt32(v.count)); bytes += v }
    mutating func string(_ v: String) { string(Bytes(v.utf8)) }
    mutating func names(_ v: [String]) { string(v.joined(separator: ",")) }
    /// İşaretsiz büyüklükten mpint.
    mutating func mpint(_ magnitude: Bytes) {
        var m = Array(magnitude.drop(while: { $0 == 0 }))
        if let first = m.first, first & 0x80 != 0 { m.insert(0, at: 0) }
        string(m)
    }
}

struct SSHReader {
    let bytes: Bytes
    var offset = 0
    init(_ bytes: Bytes) { self.bytes = bytes }

    mutating func byte() throws -> UInt8 {
        guard offset < bytes.count else { throw SSHFailure(.protocolError, "short message") }
        defer { offset += 1 }
        return bytes[offset]
    }

    mutating func bool() throws -> Bool { try byte() != 0 }

    mutating func uint32() throws -> UInt32 {
        guard offset + 4 <= bytes.count else { throw SSHFailure(.protocolError, "short message") }
        defer { offset += 4 }
        return bytes.be32(at: offset)
    }

    mutating func string() throws -> Bytes {
        let n = Int(try uint32())
        guard offset + n <= bytes.count else { throw SSHFailure(.protocolError, "short string") }
        defer { offset += n }
        return Array(bytes[offset..<(offset + n)])
    }

    mutating func text() throws -> String { String(decoding: try string(), as: UTF8.self) }
    mutating func names() throws -> [String] { try text().split(separator: ",").map(String.init) }
    mutating func mpint() throws -> Bytes { Array(try string().drop(while: { $0 == 0 })) }
    mutating func skip(_ n: Int) throws {
        guard offset + n <= bytes.count else { throw SSHFailure(.protocolError, "short message") }
        offset += n
    }
}

enum SSHMessage {
    static let disconnect: UInt8 = 1, ignore: UInt8 = 2, unimplemented: UInt8 = 3, debug: UInt8 = 4
    static let serviceRequest: UInt8 = 5, serviceAccept: UInt8 = 6, extInfo: UInt8 = 7
    static let kexInit: UInt8 = 20, newKeys: UInt8 = 21, kexDHInit: UInt8 = 30, kexDHReply: UInt8 = 31
    static let userauthRequest: UInt8 = 50, userauthFailure: UInt8 = 51, userauthSuccess: UInt8 = 52, userauthBanner: UInt8 = 53
    static let userauthPKOK: UInt8 = 60
    static let globalRequest: UInt8 = 80, requestFailure: UInt8 = 82
    static let channelOpen: UInt8 = 90, channelOpenConfirmation: UInt8 = 91, channelOpenFailure: UInt8 = 92
    static let windowAdjust: UInt8 = 93, channelData: UInt8 = 94, channelExtendedData: UInt8 = 95, channelEOF: UInt8 = 96
    static let channelClose: UInt8 = 97, channelRequest: UInt8 = 98, channelSuccess: UInt8 = 99, channelFailure: UInt8 = 100
}

// MARK: - Algoritmalar

enum SSHHash {
    case sha1, sha256, sha384, sha512

    func digest(_ data: Bytes) -> Bytes {
        switch self {
        case .sha1: Bytes(Insecure.SHA1.hash(data: data))
        case .sha256: Bytes(SHA256.hash(data: data))
        case .sha384: Bytes(SHA384.hash(data: data))
        case .sha512: Bytes(SHA512.hash(data: data))
        }
    }
}

enum SSHKex: String, CaseIterable {
    case curve25519 = "curve25519-sha256"
    case curve25519LibSSH = "curve25519-sha256@libssh.org"
    case nistp256 = "ecdh-sha2-nistp256"
    case nistp384 = "ecdh-sha2-nistp384"
    case nistp521 = "ecdh-sha2-nistp521"
    case group14sha256 = "diffie-hellman-group14-sha256"
    case group14sha1 = "diffie-hellman-group14-sha1"
    case group1sha1 = "diffie-hellman-group1-sha1"

    var hash: SSHHash {
        switch self {
        case .curve25519, .curve25519LibSSH, .nistp256, .group14sha256: .sha256
        case .nistp384: .sha384
        case .nistp521: .sha512
        case .group14sha1, .group1sha1: .sha1
        }
    }
}

enum SSHAlgorithms {
    static let hostKeys = ["ssh-ed25519", "ecdsa-sha2-nistp256", "ecdsa-sha2-nistp384", "ecdsa-sha2-nistp521",
                           "rsa-sha2-512", "rsa-sha2-256", "ssh-rsa"]
    static let ciphers = ["aes128-ctr", "aes192-ctr", "aes256-ctr"]
    static let macs = ["hmac-sha2-256-etm@openssh.com", "hmac-sha2-512-etm@openssh.com", "hmac-sha2-256", "hmac-sha2-512",
                       "hmac-sha1-etm@openssh.com", "hmac-sha1"]

    static func keyLength(cipher: String) -> Int { cipher.hasPrefix("aes256") ? 32 : cipher.hasPrefix("aes192") ? 24 : 16 }

    /// Oakley grupları (RFC 3526 2048 bit, RFC 2409 1024 bit).
    static let group14 = BigNum(bigEndian: Bytes(hex:
        "FFFFFFFFFFFFFFFFC90FDAA22168C234C4C6628B80DC1CD129024E088A67CC74020BBEA63B139B22514A08798E3404DDEF9519B3CD3A431B302B0A6DF25F14374FE1356D6D51C245E485B576625E7EC6F44C42E9A637ED6B0BFF5CB6F406B7EDEE386BFB5A899FA5AE9F24117C4B1FE649286651ECE45B3DC2007CB8A163BF0598DA48361C55D39A69163FA8FD24CF5F83655D23DCA3AD961C62F356208552BB9ED529077096966D670C354E4ABC9804F1746C08CA18217C32905E462E36CE3BE39E772C180E86039B2783A2EC07A28FB5C55DF06F4C52C9DE2BCBF6955817183995497CEA956AE515D2261898FA051015728E5A8AACAA68FFFFFFFFFFFFFFFF")!)
    static let group1 = BigNum(bigEndian: Bytes(hex:
        "FFFFFFFFFFFFFFFFC90FDAA22168C234C4C6628B80DC1CD129024E088A67CC74020BBEA63B139B22514A08798E3404DDEF9519B3CD3A431B302B0A6DF25F14374FE1356D6D51C245E485B576625E7EC6F44C42E9A637ED6B0BFF5CB6F406B7EDEE386BFB5A899FA5AE9F24117C4B1FE649286651ECE65381FFFFFFFFFFFFFFFF")!)
}

struct SSHMac {
    let name: String
    let key: Bytes
    var etm: Bool { name.hasSuffix("-etm@openssh.com") }
    var length: Int { name.hasPrefix("hmac-sha2-512") ? 64 : name.hasPrefix("hmac-sha2-256") ? 32 : 20 }
    static func keyLength(_ name: String) -> Int { name.hasPrefix("hmac-sha2-512") ? 64 : name.hasPrefix("hmac-sha2-256") ? 32 : 20 }

    func compute(_ data: Bytes) -> Bytes {
        let k = SymmetricKey(data: key)
        if name.hasPrefix("hmac-sha2-512") { return Bytes(HMAC<SHA512>.authenticationCode(for: data, using: k)) }
        if name.hasPrefix("hmac-sha2-256") { return Bytes(HMAC<SHA256>.authenticationCode(for: data, using: k)) }
        return Bytes(HMAC<Insecure.SHA1>.authenticationCode(for: data, using: k))
    }
}

/// AES-CTR (CommonCrypto), akış olarak.
final class AESCounter {
    private var ref: CCCryptorRef?

    init(key: Bytes, iv: Bytes) throws {
        let status = CCCryptorCreateWithMode(CCOperation(kCCEncrypt), CCMode(kCCModeCTR), CCAlgorithm(kCCAlgorithmAES),
                                             CCPadding(ccNoPadding), iv, key, key.count, nil, 0, 0,
                                             CCModeOptions(kCCModeOptionCTR_BE), &ref)
        guard status == kCCSuccess else { throw SSHFailure(.protocolError, "AES-CTR unavailable (\(status))") }
    }

    deinit { if let ref { CCCryptorRelease(ref) } }

    func apply(_ data: Bytes) -> Bytes {
        guard !data.isEmpty else { return [] }
        var out = Bytes(repeating: 0, count: data.count)
        var moved = 0
        CCCryptorUpdate(ref, data, data.count, &out, out.count, &moved)
        return out
    }
}

/// Bir yöndeki paket katmanı (RFC 4253 6): şifre, doğrulama ve sıra numarası.
final class SSHPacketDirection {
    var cipher: AESCounter?
    var mac: SSHMac?
    var sequence: UInt32 = 0
    var blockSize: Int { cipher == nil ? 8 : 16 }
}

/// Paketleri yazar/okur; iki uçta da aynıdır (testlerdeki sahte sunucu da kullanır).
final class SSHPacketCodec {
    let channel: ByteChannel
    let reader: ChannelReader
    let outgoing = SSHPacketDirection()
    let incoming = SSHPacketDirection()

    init(channel: ByteChannel, reader: ChannelReader) {
        self.channel = channel
        self.reader = reader
    }

    func send(_ payload: Bytes) throws {
        let block = outgoing.blockSize
        let etm = outgoing.mac?.etm == true
        // etm'de uzunluk alanı şifrelenmez ve dolgu hesabına girmez.
        let covered = etm ? 1 + payload.count : 5 + payload.count
        var padding = block - covered % block
        if padding < 4 { padding += block }
        var packet = Bytes()
        packet.putBE32(UInt32(1 + payload.count + padding))
        packet.append(UInt8(padding))
        packet += payload
        packet += Bytes.random(padding)
        var seq = Bytes()
        seq.putBE32(outgoing.sequence)
        var wire: Bytes
        if let mac = outgoing.mac, mac.etm {
            let body = outgoing.cipher?.apply(Array(packet[4...])) ?? Array(packet[4...])
            wire = Array(packet[0..<4]) + body
            wire += mac.compute(seq + wire)
        } else {
            let tag = outgoing.mac?.compute(seq + packet) ?? []
            wire = (outgoing.cipher?.apply(packet) ?? packet) + tag
        }
        outgoing.sequence &+= 1
        try channel.send(wire)
    }

    func receive() throws -> Bytes {
        let block = incoming.blockSize
        var seq = Bytes()
        seq.putBE32(incoming.sequence)
        incoming.sequence &+= 1
        let packet: Bytes
        if let mac = incoming.mac, mac.etm {
            let lengthField = try reader.read(exactly: 4)
            let length = Int(lengthField.be32(at: 0))
            guard length >= 5, length <= 256 * 1024 else { throw SSHFailure(.protocolError, "bad packet length \(length)") }
            let body = try reader.read(exactly: length)
            let tag = try reader.read(exactly: mac.length)
            guard mac.compute(seq + lengthField + body) == tag else { throw SSHFailure(.protocolError, "MAC mismatch") }
            packet = lengthField + (incoming.cipher?.apply(body) ?? body)
        } else {
            let first = try reader.read(exactly: block)
            let head = incoming.cipher?.apply(first) ?? first
            let length = Int(head.be32(at: 0))
            guard length >= 5, length <= 256 * 1024, (length + 4) % block == 0 else {
                throw SSHFailure(.protocolError, "bad packet length \(length)")
            }
            let rest = try reader.read(exactly: length + 4 - block)
            packet = head + (incoming.cipher?.apply(rest) ?? rest)
            if let mac = incoming.mac {
                let tag = try reader.read(exactly: mac.length)
                guard mac.compute(seq + packet) == tag else { throw SSHFailure(.protocolError, "MAC mismatch") }
            }
        }
        let padding = Int(packet[4])
        guard 5 + padding <= packet.count else { throw SSHFailure(.protocolError, "bad padding") }
        return Array(packet[5..<(packet.count - padding)])
    }
}

// MARK: - Oturum

final class SSHSession {
    static let clientVersion = "SSH-2.0-Nino_TV_1"
    private let tcp: TCPChannel
    private let codec: SSHPacketCodec
    private var serverVersion = ""
    private var sessionID: Bytes = []
    private var serverSignatureAlgorithms: [String]?
    private var nextChannel: UInt32 = 0

    struct ExecResult {
        var status: Int?
        var stdout: Bytes
        var stderr: Bytes
        var text: String { String(decoding: stdout + stderr, as: UTF8.self) }
    }

    private init(tcp: TCPChannel, reader: ChannelReader) {
        self.tcp = tcp
        codec = SSHPacketCodec(channel: tcp, reader: reader)
    }

    static func connect(host: String, port: UInt16, user: String, key: RSAPrivateKey, timeout: TimeInterval = 8) throws -> SSHSession {
        let tcp: TCPChannel
        do {
            tcp = try TCPChannel(host: host, port: port, timeout: timeout)
        } catch {
            throw SSHFailure(.connect, "\(host):\(port): \(error)")
        }
        tcp.receiveTimeout = 20
        let session = SSHSession(tcp: tcp, reader: ChannelReader(tcp))
        do {
            try session.exchangeVersions()
            try session.keyExchange()
            try session.authenticate(user: user, key: key)
            tcp.receiveTimeout = 120
            return session
        } catch let f as SSHFailure {
            session.close()
            throw f
        } catch {
            session.close()
            throw SSHFailure(.connect, "\(error)")
        }
    }

    func close() { tcp.shutdown() }

    private func exchangeVersions() throws {
        try tcp.send(Bytes((Self.clientVersion + "\r\n").utf8))
        // Sunucu sürümden önce başka satırlar da yazabilir.
        for _ in 0..<50 {
            var line = Bytes()
            while true {
                let b = try codec.reader.read(exactly: 1)[0]
                if b == 0x0A { break }
                line.append(b)
                guard line.count < 1024 else { throw SSHFailure(.protocolError, "version line too long") }
            }
            if line.last == 0x0D { line.removeLast() }
            let text = String(decoding: line, as: UTF8.self)
            if text.hasPrefix("SSH-") {
                guard text.hasPrefix("SSH-2.0-") || text.hasPrefix("SSH-1.99-") else {
                    throw SSHFailure(.protocolError, "unsupported server \(text)")
                }
                serverVersion = text
                return
            }
        }
        throw SSHFailure(.protocolError, "no SSH version line")
    }

    /// Anahtar değişimi dışındaki iletileri bekletmeden okur (yok sayılabilenleri atlar).
    private func nextMessage() throws -> Bytes {
        while true {
            let m = try codec.receive()
            guard let type = m.first else { continue }
            switch type {
            case SSHMessage.ignore, SSHMessage.debug, SSHMessage.unimplemented:
                continue
            case SSHMessage.disconnect:
                var r = SSHReader(m)
                try r.skip(1)
                _ = try? r.uint32()
                throw SSHFailure(.protocolError, "server disconnected: \((try? r.text()) ?? "")")
            case SSHMessage.extInfo:
                var r = SSHReader(m)
                try r.skip(1)
                let count = try r.uint32()
                for _ in 0..<count {
                    let name = try r.text()
                    let value = try r.text()
                    if name == "server-sig-algs" { serverSignatureAlgorithms = value.split(separator: ",").map(String.init) }
                }
                continue
            case SSHMessage.globalRequest:
                var r = SSHReader(m)
                try r.skip(1)
                _ = try r.string()
                if try r.bool() { try codec.send([SSHMessage.requestFailure]) }
                continue
            case SSHMessage.kexInit:
                // Sunucu yeniden anahtar değişimi başlattı.
                try keyExchange(serverInit: m)
                continue
            default:
                return m
            }
        }
    }

    private func keyExchange(serverInit received: Bytes? = nil) throws {
        let firstTime = sessionID.isEmpty
        var w = SSHWriter()
        w.byte(SSHMessage.kexInit)
        w.bytes += Bytes.random(16)
        w.names(SSHKex.allCases.map(\.rawValue) + (firstTime ? ["ext-info-c"] : []))
        w.names(SSHAlgorithms.hostKeys)
        w.names(SSHAlgorithms.ciphers)
        w.names(SSHAlgorithms.ciphers)
        w.names(SSHAlgorithms.macs)
        w.names(SSHAlgorithms.macs)
        w.names(["none"])
        w.names(["none"])
        w.names([])
        w.names([])
        w.bool(false)
        w.uint32(0)
        let clientInit = w.bytes
        try codec.send(clientInit)

        var serverInit = received ?? []
        while serverInit.first != SSHMessage.kexInit {
            serverInit = try codec.receive()
            if serverInit.first == SSHMessage.disconnect { throw SSHFailure(.protocolError, "server disconnected during key exchange") }
        }
        var r = SSHReader(serverInit)
        try r.skip(17)
        let kexNames = try r.names(), hostNames = try r.names()
        let cipherOut = try r.names(), cipherIn = try r.names()
        let macOut = try r.names(), macIn = try r.names()
        _ = try r.names(); _ = try r.names(); _ = try r.names(); _ = try r.names()
        let guessFollows = try r.bool()

        func pick(_ mine: [String], _ theirs: [String], _ what: String) throws -> String {
            guard let hit = mine.first(where: theirs.contains) else {
                throw SSHFailure(.protocolError, "no common \(what): server offers \(theirs.joined(separator: ","))")
            }
            return hit
        }
        guard let kex = SSHKex(rawValue: try pick(SSHKex.allCases.map(\.rawValue), kexNames, "key exchange")) else {
            throw SSHFailure(.protocolError, "key exchange")
        }
        let hostAlgorithm = try pick(SSHAlgorithms.hostKeys, hostNames, "host key")
        let cOut = try pick(SSHAlgorithms.ciphers, cipherOut, "cipher")
        let cIn = try pick(SSHAlgorithms.ciphers, cipherIn, "cipher")
        let mOut = try pick(SSHAlgorithms.macs, macOut, "MAC")
        let mIn = try pick(SSHAlgorithms.macs, macIn, "MAC")
        if guessFollows, kexNames.first != kex.rawValue || hostNames.first != hostAlgorithm { _ = try codec.receive() }

        // İstemcinin geçici anahtarı ve ortak sır
        let clientPublic: Bytes
        let finish: (Bytes) throws -> Bytes   // sunucunun açık değeri → ortak sırrın büyüklüğü
        var dhStyle = false
        switch kex {
        case .curve25519, .curve25519LibSSH:
            let k = Curve25519.KeyAgreement.PrivateKey()
            clientPublic = Bytes(k.publicKey.rawRepresentation)
            finish = { s in
                let shared = try k.sharedSecretFromKeyAgreement(with: .init(rawRepresentation: s)).withUnsafeBytes { Bytes($0) }
                guard shared.contains(where: { $0 != 0 }) else { throw SSHFailure(.protocolError, "bad shared secret") }
                return shared
            }
        case .nistp256:
            let k = P256.KeyAgreement.PrivateKey()
            clientPublic = Bytes(k.publicKey.x963Representation)
            finish = { s in try k.sharedSecretFromKeyAgreement(with: .init(x963Representation: s)).withUnsafeBytes { Bytes($0) } }
        case .nistp384:
            let k = P384.KeyAgreement.PrivateKey()
            clientPublic = Bytes(k.publicKey.x963Representation)
            finish = { s in try k.sharedSecretFromKeyAgreement(with: .init(x963Representation: s)).withUnsafeBytes { Bytes($0) } }
        case .nistp521:
            let k = P521.KeyAgreement.PrivateKey()
            clientPublic = Bytes(k.publicKey.x963Representation)
            finish = { s in try k.sharedSecretFromKeyAgreement(with: .init(x963Representation: s)).withUnsafeBytes { Bytes($0) } }
        case .group14sha256, .group14sha1, .group1sha1:
            dhStyle = true
            let p = kex == .group1sha1 ? SSHAlgorithms.group1 : SSHAlgorithms.group14
            let x = BigNum(bigEndian: Bytes.random(64)) + BigNum(2)
            clientPublic = BigNum(2).power(x, modulus: p).bigEndianMinimal
            finish = { s in
                let f = BigNum(bigEndian: s)
                guard BigNum(1) < f, f < p - BigNum(1) else { throw SSHFailure(.protocolError, "bad DH value") }
                return f.power(x, modulus: p).bigEndianMinimal
            }
        }
        var initMessage = SSHWriter()
        initMessage.byte(SSHMessage.kexDHInit)
        if dhStyle { initMessage.mpint(clientPublic) } else { initMessage.string(clientPublic) }
        try codec.send(initMessage.bytes)

        var reply = try codec.receive()
        while reply.first == SSHMessage.ignore || reply.first == SSHMessage.debug { reply = try codec.receive() }
        guard reply.first == SSHMessage.kexDHReply else { throw SSHFailure(.protocolError, "expected KEX reply, got \(reply.first ?? 0)") }
        var rr = SSHReader(reply)
        try rr.skip(1)
        let hostKey = try rr.string()
        let serverPublic = dhStyle ? try rr.mpint() : try rr.string()
        let signature = try rr.string()
        let shared = try finish(serverPublic)

        var h = SSHWriter()
        h.string(Self.clientVersion)
        h.string(serverVersion)
        h.string(clientInit)
        h.string(serverInit)
        h.string(hostKey)
        if dhStyle { h.mpint(clientPublic); h.mpint(serverPublic) } else { h.string(clientPublic); h.string(serverPublic) }
        h.mpint(shared)
        let exchangeHash = kex.hash.digest(h.bytes)
        try SSHHostKey.verify(hostKey: hostKey, signature: signature, data: exchangeHash, negotiated: hostAlgorithm)
        if sessionID.isEmpty { sessionID = exchangeHash }

        try codec.send([SSHMessage.newKeys])
        var done = try codec.receive()
        while done.first == SSHMessage.ignore || done.first == SSHMessage.debug { done = try codec.receive() }
        guard done.first == SSHMessage.newKeys else { throw SSHFailure(.protocolError, "expected NEWKEYS") }

        var k = SSHWriter()
        k.mpint(shared)
        let keys = SSHKeyDerivation(hash: kex.hash, sharedMpint: k.bytes, exchangeHash: exchangeHash, sessionID: sessionID)
        try SSHKeyDerivation.install(keys, codec: codec, client: true, cipherOut: cOut, cipherIn: cIn, macOut: mOut, macIn: mIn)
    }

    private func authenticate(user: String, key: RSAPrivateKey) throws {
        var w = SSHWriter()
        w.byte(SSHMessage.serviceRequest)
        w.string("ssh-userauth")
        try codec.send(w.bytes)
        guard try nextMessage().first == SSHMessage.serviceAccept else { throw SSHFailure(.protocolError, "ssh-userauth refused") }

        var blob = SSHWriter()
        blob.string("ssh-rsa")
        blob.mpint(key.exponent)
        blob.mpint(key.modulus)
        let all: [(String, SecKeyAlgorithm)] = [("rsa-sha2-512", .rsaSignatureMessagePKCS1v15SHA512),
                                                ("rsa-sha2-256", .rsaSignatureMessagePKCS1v15SHA256),
                                                ("ssh-rsa", .rsaSignatureMessagePKCS1v15SHA1)]
        let offered = serverSignatureAlgorithms.map { names in all.filter { names.contains($0.0) } } ?? all
        var lastReason = "no algorithm"
        for (name, algorithm) in offered.isEmpty ? all : offered {
            var signed = SSHWriter()
            signed.string(sessionID)
            signed.byte(SSHMessage.userauthRequest)
            signed.string(user)
            signed.string("ssh-connection")
            signed.string("publickey")
            signed.bool(true)
            signed.string(name)
            signed.string(blob.bytes)
            var sig = SSHWriter()
            sig.string(name)
            sig.string(try key.sign(signed.bytes, algorithm))
            var request = SSHWriter()
            request.bytes = Array(signed.bytes[(4 + sessionID.count)...])
            request.string(sig.bytes)
            try codec.send(request.bytes)
            while true {
                let m = try nextMessage()
                switch m.first {
                case SSHMessage.userauthSuccess: return
                case SSHMessage.userauthBanner: continue
                case SSHMessage.userauthFailure:
                    var r = SSHReader(m)
                    try r.skip(1)
                    lastReason = "server allows: \(((try? r.names()) ?? []).joined(separator: ","))"
                default:
                    throw SSHFailure(.protocolError, "unexpected auth reply \(m.first ?? 0)")
                }
                break
            }
        }
        throw SSHFailure(.auth, "key refused (\(lastReason))")
    }

    /// Komutu çalıştırır; `input` verilirse girdisine yazılır ve girdi kapatılır.
    func exec(_ command: String, input: Bytes? = nil, timeout: TimeInterval = 300) throws -> ExecResult {
        nextChannel += 1
        let local = nextChannel
        let localWindow: UInt32 = 2 * 1024 * 1024
        var w = SSHWriter()
        w.byte(SSHMessage.channelOpen)
        w.string("session")
        w.uint32(local)
        w.uint32(localWindow)
        w.uint32(32 * 1024)
        try codec.send(w.bytes)

        var remote: UInt32 = 0
        var remoteWindow = 0
        var remoteMaxPacket = 0
        let open = try nextMessage()
        var r = SSHReader(open)
        try r.skip(1)
        guard open.first == SSHMessage.channelOpenConfirmation else {
            throw SSHFailure(.protocolError, "session refused")
        }
        _ = try r.uint32()
        remote = try r.uint32()
        remoteWindow = Int(try r.uint32())
        remoteMaxPacket = max(1024, min(Int(try r.uint32()), 32 * 1024))

        var result = ExecResult(status: nil, stdout: [], stderr: [])
        var closed = false
        var eof = false
        var consumed = 0
        let deadline = Date().addingTimeInterval(timeout)

        func handle(_ m: Bytes) throws {
            var r = SSHReader(m)
            let type = try r.byte()
            guard type >= SSHMessage.windowAdjust, type <= SSHMessage.channelFailure else { return }
            _ = try r.uint32()
            switch type {
            case SSHMessage.windowAdjust:
                remoteWindow += Int(try r.uint32())
            case SSHMessage.channelData, SSHMessage.channelExtendedData:
                if type == SSHMessage.channelExtendedData { _ = try r.uint32() }
                let data = try r.string()
                if type == SSHMessage.channelData { result.stdout += data } else { result.stderr += data }
                consumed += data.count
                if consumed > Int(localWindow) / 2 {
                    var adj = SSHWriter()
                    adj.byte(SSHMessage.windowAdjust)
                    adj.uint32(remote)
                    adj.uint32(UInt32(consumed))
                    try codec.send(adj.bytes)
                    consumed = 0
                }
            case SSHMessage.channelEOF:
                eof = true
            case SSHMessage.channelClose:
                closed = true
            case SSHMessage.channelRequest:
                let name = try r.text()
                let wantReply = try r.bool()
                if name == "exit-status" { result.status = Int(try r.uint32()) }
                if wantReply {
                    var f = SSHWriter()
                    f.byte(SSHMessage.channelFailure)
                    f.uint32(remote)
                    try codec.send(f.bytes)
                }
            default:
                break
            }
        }
        func step() throws {
            guard Date() < deadline else { throw SSHFailure(.protocolError, "command timed out") }
            try handle(try nextMessage())
        }

        var request = SSHWriter()
        request.byte(SSHMessage.channelRequest)
        request.uint32(remote)
        request.string("exec")
        request.bool(true)
        request.string(command)
        try codec.send(request.bytes)
        while true {
            let m = try nextMessage()
            if m.first == SSHMessage.channelSuccess { break }
            if m.first == SSHMessage.channelFailure { throw SSHFailure(.protocolError, "exec refused") }
            try handle(m)
            if closed { return result }
        }

        if let input {
            var offset = 0
            while offset < input.count {
                while remoteWindow <= 0 {
                    try step()
                    if closed { throw SSHFailure(.protocolError, "channel closed while sending") }
                }
                let n = min(input.count - offset, remoteWindow, remoteMaxPacket - 64)
                var d = SSHWriter()
                d.byte(SSHMessage.channelData)
                d.uint32(remote)
                d.string(Array(input[offset..<(offset + n)]))
                try codec.send(d.bytes)
                offset += n
                remoteWindow -= n
            }
        }
        var e = SSHWriter()
        e.byte(SSHMessage.channelEOF)
        e.uint32(remote)
        try codec.send(e.bytes)
        while !closed {
            try step()
        }
        _ = eof
        var c = SSHWriter()
        c.byte(SSHMessage.channelClose)
        c.uint32(remote)
        try? codec.send(c.bytes)
        return result
    }
}

/// RFC 4253 7.2 anahtar türetme.
struct SSHKeyDerivation {
    let hash: SSHHash
    let sharedMpint: Bytes
    let exchangeHash: Bytes
    let sessionID: Bytes

    func derive(_ letter: Character, _ length: Int) -> Bytes {
        var out = hash.digest(sharedMpint + exchangeHash + [letter.asciiValue!] + sessionID)
        while out.count < length { out += hash.digest(sharedMpint + exchangeHash + out) }
        return Array(out.prefix(length))
    }

    /// Yeni anahtarları kodlayıcıya koyar (istemci: A/C/E gönderen, B/D/F alan).
    static func install(_ k: SSHKeyDerivation, codec: SSHPacketCodec, client: Bool, cipherOut: String, cipherIn: String,
                        macOut: String, macIn: String) throws {
        let (ivOut, ivIn, keyOut, keyIn, macKeyOut, macKeyIn): (Character, Character, Character, Character, Character, Character) =
            client ? ("A", "B", "C", "D", "E", "F") : ("B", "A", "D", "C", "F", "E")
        codec.outgoing.cipher = try AESCounter(key: k.derive(keyOut, SSHAlgorithms.keyLength(cipher: cipherOut)), iv: k.derive(ivOut, 16))
        codec.incoming.cipher = try AESCounter(key: k.derive(keyIn, SSHAlgorithms.keyLength(cipher: cipherIn)), iv: k.derive(ivIn, 16))
        codec.outgoing.mac = SSHMac(name: macOut, key: k.derive(macKeyOut, SSHMac.keyLength(macOut)))
        codec.incoming.mac = SSHMac(name: macIn, key: k.derive(macKeyIn, SSHMac.keyLength(macIn)))
    }
}

/// Sunucu anahtarı imzasını denetler (anahtarın sunucuda olduğunu gösterir; anahtar kaydedilmez: TV her geliştirici
/// modu açılışında yenisini üretebilir).
enum SSHHostKey {
    static func verify(hostKey: Bytes, signature: Bytes, data: Bytes, negotiated: String) throws {
        var k = SSHReader(hostKey)
        let keyType = try k.text()
        var s = SSHReader(signature)
        let sigType = try s.text()
        let sig = try s.string()
        let ok: Bool
        switch keyType {
        case "ssh-ed25519":
            let pub = try Curve25519.Signing.PublicKey(rawRepresentation: try k.string())
            ok = pub.isValidSignature(sig, for: data)
        case "ecdsa-sha2-nistp256", "ecdsa-sha2-nistp384", "ecdsa-sha2-nistp521":
            _ = try k.string()
            let point = try k.string()
            var sr = SSHReader(sig)
            let rBytes = try sr.mpint(), sBytes = try sr.mpint()
            func fixed(_ v: Bytes, _ n: Int) -> Bytes { Bytes(repeating: 0, count: max(0, n - v.count)) + v.suffix(n) }
            switch keyType {
            case "ecdsa-sha2-nistp256":
                let raw = fixed(rBytes, 32) + fixed(sBytes, 32)
                ok = try P256.Signing.PublicKey(x963Representation: point)
                    .isValidSignature(try .init(rawRepresentation: raw), for: SHA256.hash(data: data))
            case "ecdsa-sha2-nistp384":
                let raw = fixed(rBytes, 48) + fixed(sBytes, 48)
                ok = try P384.Signing.PublicKey(x963Representation: point)
                    .isValidSignature(try .init(rawRepresentation: raw), for: SHA384.hash(data: data))
            default:
                let raw = fixed(rBytes, 66) + fixed(sBytes, 66)
                ok = try P521.Signing.PublicKey(x963Representation: point)
                    .isValidSignature(try .init(rawRepresentation: raw), for: SHA512.hash(data: data))
            }
        case "ssh-rsa":
            let e = try k.mpint(), n = try k.mpint()
            let pkcs1 = ASN1.seq(ASN1.unsigned(n), ASN1.unsigned(e))
            guard let pub = RSAVerify.publicKey(pkcs1: pkcs1) else { throw SSHFailure(.protocolError, "bad RSA host key") }
            let algorithm: SecKeyAlgorithm = switch sigType {
            case "rsa-sha2-512": .rsaSignatureMessagePKCS1v15SHA512
            case "rsa-sha2-256": .rsaSignatureMessagePKCS1v15SHA256
            default: .rsaSignatureMessagePKCS1v15SHA1
            }
            ok = RSAVerify.check(pub, algorithm, message: data, signature: sig)
        default:
            throw SSHFailure(.protocolError, "host key type \(keyType)")
        }
        guard ok else { throw SSHFailure(.protocolError, "host signature invalid (\(negotiated))") }
    }
}
