// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Network
import Security
import XCTest
@testable import Nino

/// Kablosuz hata ayıklama eşlemesi: telefon (alice) ↔ sahte TV (bob), 127.0.0.1'de TLS 1.3 üstünde.
final class AdbPairingTests: XCTestCase {
    func testPairingSucceedsWithRightCodeAndFailsWithWrongCode() throws {
        let dir = TVTestFiles.scratch()
        let tvIdentity = try TLSClientIdentity.make(key: try RSAPrivateKey.generate(), certificateFile: dir.appendingPathComponent("tv.cer"))
        let phone = try AdbIdentity.stored(in: dir)

        let tv = try FakePairingTV(identity: tvIdentity, code: "482913")
        defer { tv.stop() }
        try AdbPairing.pair(host: "127.0.0.1", port: tv.port, code: "482913", identity: phone)
        XCTAssertEqual(tv.receivedKeyLine.get(), phone.publicKeyLine)

        XCTAssertThrowsError(try AdbPairing.pair(host: "127.0.0.1", port: tv.port, code: "000000", identity: phone)) {
            XCTAssertEqual(($0 as? AndroidTVFailure)?.problem, .pairingFailed)
        }
    }

    /// Gerçek `adb pair` ile uyum: yalnız elle çalıştırılır (NINO_ADB_PAIR_INTEROP=1; Mac'te
    /// `adb pair 127.0.0.1:47123 123456` komutu bu sahte TV'ye bağlanır).
    func testRealAdbPairInterop() throws {
        guard ProcessInfo.processInfo.environment["NINO_ADB_PAIR_INTEROP"] == "1" else { throw XCTSkip("manual interop test") }
        let dir = TVTestFiles.scratch()
        let tvIdentity = try TLSClientIdentity.make(key: try RSAPrivateKey.generate(), certificateFile: dir.appendingPathComponent("tv.cer"))
        let tv = try FakePairingTV(identity: tvIdentity, code: "123456", port: 47123)
        defer { tv.stop() }
        let deadline = Date().addingTimeInterval(80)
        while tv.receivedKeyLine.get() == nil, Date() < deadline { Thread.sleep(forTimeInterval: 0.2) }
        let line = try XCTUnwrap(tv.receivedKeyLine.get(), "adb pair did not complete")
        print("INTEROP adb key line: \(line.prefix(24))…")
    }
}

/// TV tarafı (bob): TLS 1.3 sunucusu, SPAKE2, şifreli PeerInfo alışverişi.
final class FakePairingTV {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "test.pairing")
    let receivedKeyLine = LockedValue<String?>(nil)
    private(set) var port: UInt16 = 0

    init(identity: SecIdentity, code: String, port fixed: UInt16 = 0) throws {
        let tls = NWProtocolTLS.Options()
        let sec = tls.securityProtocolOptions
        sec_protocol_options_set_local_identity(sec, sec_identity_create(identity)!)
        sec_protocol_options_set_min_tls_protocol_version(sec, .TLSv13)
        sec_protocol_options_set_peer_authentication_required(sec, true)
        sec_protocol_options_set_verify_block(sec, { _, _, reply in reply(true) }, queue)
        let params = NWParameters(tls: tls)
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: fixed == 0 ? .any : NWEndpoint.Port(rawValue: fixed)!)
        params.allowLocalEndpointReuse = true
        listener = try NWListener(using: params)
        let received = receivedKeyLine
        let queue = self.queue
        listener.newConnectionHandler = { conn in
            conn.stateUpdateHandler = { state in
                guard case .ready = state,
                      let meta = conn.metadata(definition: NWProtocolTLS.definition) as? NWProtocolTLS.Metadata else { return }
                let label = AdbPairing.exporterLabel
                let secret = label.withUnsafeBufferPointer { b in
                    b.withMemoryRebound(to: CChar.self) {
                        sec_protocol_metadata_create_secret(meta.securityProtocolMetadata, label.count, $0.baseAddress!, 64)
                    }
                }
                guard let exported = secret.map({ Bytes($0 as DispatchData) }) else { return }
                Thread.detachNewThread {
                    let channel = NWBlockingChannel(conn)
                    let reader = ChannelReader(channel)
                    guard let theirs = try? AdbPairing.readFrame(reader, type: AdbPairing.spakeMessage) else { return }
                    let spake = Spake2(role: .bob, password: Bytes(code.utf8) + exported)
                    try? channel.send(AdbPairing.frame(AdbPairing.spakeMessage, spake.message))
                    guard let key = spake.finish(theirs),
                          let sealed = try? AdbPairing.readFrame(reader, type: AdbPairing.peerInfo) else { return }
                    var cipher = AdbPairing.PairingCipher(keyMaterial: key)
                    guard let info = cipher.open(sealed) else { conn.cancel(); return }
                    received.set(String(decoding: info.dropFirst().prefix { $0 != 0 }, as: UTF8.self))
                    let mine = (try? cipher.seal(AdbPairing.peerInfoBlock("tv-key tv@fake"))) ?? []
                    try? channel.send(AdbPairing.frame(AdbPairing.peerInfo, mine))
                }
            }
            conn.start(queue: queue)
        }
        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { if case .ready = $0 { ready.signal() } }
        listener.start(queue: queue)
        _ = ready.wait(timeout: .now() + 5)
        port = listener.port?.rawValue ?? 0
    }

    func stop() { listener.cancel() }
}

/// NWConnection'ı bloklayan akış olarak kullanır (test sunucuları için).
final class NWBlockingChannel: ByteChannel {
    let conn: NWConnection
    var receiveTimeout: TimeInterval = 15
    init(_ conn: NWConnection) { self.conn = conn }

    func receive(upTo max: Int) throws -> Bytes {
        let done = DispatchSemaphore(value: 0)
        let out = LockedValue<Bytes?>(nil)
        conn.receive(minimumIncompleteLength: 1, maximumLength: max) { data, _, _, _ in
            out.set(data.map(Bytes.init))
            done.signal()
        }
        guard done.wait(timeout: .now() + receiveTimeout) == .success, let d = out.get(), !d.isEmpty else { throw WireError.closed }
        return d
    }

    func send(_ bytes: Bytes) throws { conn.send(content: Data(bytes), completion: .idempotent) }
    func shutdown() { conn.cancel() }
}
