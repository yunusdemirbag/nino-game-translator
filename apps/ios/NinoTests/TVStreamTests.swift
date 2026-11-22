// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Network
import Security
import XCTest
@testable import Nino

/// TV kurulumunun bağlantı katmanı: yalnız 127.0.0.1'de, rastgele portlarda (ağdaki cihazlara dokunmaz).
final class TVStreamTests: XCTestCase {
    func testTLSWithClientIdentityExporterAndBridge() throws {
        let dir = TVTestFiles.scratch()
        let serverKey = try RSAPrivateKey.generate()
        let clientKey = try RSAPrivateKey.generate()
        let serverIdentity = try TLSClientIdentity.make(key: serverKey, certificateFile: dir.appendingPathComponent("server.cer"))
        let clientIdentity = try TLSClientIdentity.make(key: clientKey, certificateFile: dir.appendingPathComponent("client.cer"))

        let server = try TLSEchoServer(identity: serverIdentity)
        defer { server.stop() }

        // Önce düz TCP ile bağlanıp "STLS" benzeri bir ön bayt alınır, sonra köprü üstünden TLS kurulur.
        let tcp = try TCPChannel(host: "127.0.0.1", port: server.plainPort)
        let reader = ChannelReader(tcp)
        XCTAssertEqual(try reader.read(exactly: 4), Bytes("STLS".utf8))
        let bridge = try LoopbackBridge(upstream: tcp, prefetched: reader.drain())
        defer { bridge.close() }
        let tls = try TLSChannel(host: "127.0.0.1", port: bridge.port, identity: clientIdentity)
        defer { tls.shutdown() }
        tls.receiveTimeout = 10
        try tls.send(Bytes("ping".utf8))
        let echoed = try ChannelReader(tls).read(exactly: 4)
        XCTAssertEqual(echoed, Bytes("ping".utf8))

        let mine = tls.exportKeyingMaterial(label: Bytes("adb-label\u{0}".utf8), length: 64)
        XCTAssertEqual(mine?.count, 64)
        XCTAssertEqual(mine, server.exported.get(), "dışa aktarılan anahtar iki uçta aynı olmalı")
        XCTAssertEqual(server.clientKey.get(), clientKey.publicPKCS1, "sunucu istemcinin sertifikasını görmeli")
    }
}

enum TVTestFiles {
    static func scratch() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tvinstall-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

/// Bir düz TCP portunda "STLS" yazıp aynı soketi bir TLS sunucusuna aktaran sahte sunucu (adb'nin STLS'i gibi).
final class TLSEchoServer {
    private let plain: NWListener
    private let tlsListener: NWListener
    private let queue = DispatchQueue(label: "test.tls")
    let exported = LockedValue<Bytes?>(nil)
    let clientKey = LockedValue<Bytes?>(nil)
    private(set) var plainPort: UInt16 = 0
    private(set) var tlsPort: UInt16 = 0

    init(identity: SecIdentity) throws {
        let tls = NWProtocolTLS.Options()
        let sec = tls.securityProtocolOptions
        sec_protocol_options_set_local_identity(sec, sec_identity_create(identity)!)
        sec_protocol_options_set_min_tls_protocol_version(sec, .TLSv13)
        sec_protocol_options_set_peer_authentication_required(sec, true)
        let clientKey = self.clientKey
        sec_protocol_options_set_verify_block(sec, { _, trust, reply in
            let chain = SecTrustCopyCertificateChain(sec_trust_copy_ref(trust).takeRetainedValue()) as? [SecCertificate]
            if let leaf = chain?.first, let key = SecCertificateCopyKey(leaf),
               let data = SecKeyCopyExternalRepresentation(key, nil) as Data? {
                clientKey.set(Bytes(data))
            }
            reply(true)
        }, queue)
        let tlsParams = NWParameters(tls: tls)
        tlsParams.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        tlsListener = try NWListener(using: tlsParams)
        let plainParams = NWParameters.tcp
        plainParams.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        plain = try NWListener(using: plainParams)

        let exported = self.exported
        let queue = self.queue
        tlsListener.newConnectionHandler = { conn in
            conn.stateUpdateHandler = { state in
                if case .ready = state,
                   let meta = conn.metadata(definition: NWProtocolTLS.definition) as? NWProtocolTLS.Metadata {
                    let label = Bytes("adb-label\u{0}".utf8)
                    let secret = label.withUnsafeBufferPointer { buf in
                        buf.withMemoryRebound(to: CChar.self) {
                            sec_protocol_metadata_create_secret(meta.securityProtocolMetadata, label.count, $0.baseAddress!, 64)
                        }
                    }
                    exported.set(secret.map { Bytes($0 as DispatchData) })
                }
            }
            conn.start(queue: queue)
            func echo() {
                conn.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, done, error in
                    if let data, !data.isEmpty { conn.send(content: data, completion: .idempotent) }
                    if !done && error == nil { echo() }
                }
            }
            echo()
        }
        let readyTLS = DispatchSemaphore(value: 0)
        tlsListener.stateUpdateHandler = { if case .ready = $0 { readyTLS.signal() } }
        tlsListener.start(queue: queue)
        _ = readyTLS.wait(timeout: .now() + 5)
        let tlsPort = tlsListener.port!.rawValue
        self.tlsPort = tlsPort

        // Düz port: "STLS" yazar, sonra baytları TLS dinleyicisine aktarır.
        plain.newConnectionHandler = { inbound in
            inbound.start(queue: queue)
            inbound.send(content: Data("STLS".utf8), completion: .idempotent)
            let outbound = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: tlsPort)!, using: .tcp)
            outbound.start(queue: queue)
            func pipe(_ a: NWConnection, _ b: NWConnection) {
                a.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, done, error in
                    if let data, !data.isEmpty { b.send(content: data, completion: .idempotent) }
                    if done || error != nil { b.cancel() } else { pipe(a, b) }
                }
            }
            pipe(inbound, outbound)
            pipe(outbound, inbound)
        }
        let readyPlain = DispatchSemaphore(value: 0)
        plain.stateUpdateHandler = { if case .ready = $0 { readyPlain.signal() } }
        plain.start(queue: queue)
        _ = readyPlain.wait(timeout: .now() + 5)
        plainPort = plain.port!.rawValue
    }

    func stop() {
        plain.cancel()
        tlsListener.cancel()
    }
}
