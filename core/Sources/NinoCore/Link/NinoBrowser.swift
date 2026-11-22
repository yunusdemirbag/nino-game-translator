// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation
import Network

/// Ağda bulunan bir Nino TV'si.
public struct DiscoveredDisplay: Hashable, Sendable {
    public let name: String
    public let id: String?
    public let version: Int?
    public let endpoint: NWEndpoint

    /// TXT kaydından bilgi çıkarır.
    public static func parse(name: String, txt: [String: String], endpoint: NWEndpoint) -> DiscoveredDisplay {
        DiscoveredDisplay(name: name, id: txt["id"].flatMap { $0.isEmpty ? nil : $0 },
                          version: txt["v"].flatMap(Int.init), endpoint: endpoint)
    }

    /// Bu sürümle konuşabilir miyiz? (TXT'de sürüm yoksa denemeye değer sayılır.)
    public var isCompatible: Bool {
        guard let version else { return true }
        return NinoLink.supportedVersions.contains(version)
    }
}

/// Bonjour ile `_nino._tcp` hizmetlerini arar.
public final class NinoBrowser: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.ninotranslator.browser")
    private var browser: NWBrowser?

    public init() {}

    /// Bulunan TV listesini her değişiklikte verir. Akış bitince arama durur.
    public func displays() -> AsyncStream<[DiscoveredDisplay]> {
        AsyncStream { continuation in
            let params = NWParameters()
            params.includePeerToPeer = false
            let browser = NWBrowser(for: .bonjourWithTXTRecord(type: NinoLink.serviceType, domain: nil), using: params)
            browser.browseResultsChangedHandler = { results, _ in
                let list = results.compactMap { result -> DiscoveredDisplay? in
                    guard case let .service(name, _, _, _) = result.endpoint else { return nil }
                    var txt: [String: String] = [:]
                    if case let .bonjour(record) = result.metadata { txt = record.dictionary }
                    return DiscoveredDisplay.parse(name: name, txt: txt, endpoint: result.endpoint)
                }
                continuation.yield(list.sorted { $0.name < $1.name })
            }
            browser.stateUpdateHandler = { state in
                if case .failed = state { continuation.finish() }
            }
            continuation.onTermination = { _ in browser.cancel() }
            self.browser = browser
            browser.start(queue: queue)
        }
    }

    public func stop() {
        browser?.cancel()
        browser = nil
    }

    /// Bonjour hizmetini IP ve bağlantı noktasına çözer.
    public static func resolve(_ endpoint: NWEndpoint, timeout: TimeInterval = 5) async throws -> (host: String, port: UInt16) {
        // IPv4 tercih edilir: kapsamlı IPv6 adresleri URL'de sorun çıkarır.
        let params = NWParameters.tcp
        if let ip = params.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options { ip.version = .v4 }
        let connection = NWConnection(to: endpoint, using: params)
        defer { connection.cancel() }
        return try await withTimeout(.seconds(timeout)) {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<(host: String, port: UInt16), Error>) in
                let once = Once()
                connection.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        if case let .hostPort(host, port)? = connection.currentPath?.remoteEndpoint, once.claim() {
                            var h = "\(host)"
                            if !h.contains(":"), let p = h.firstIndex(of: "%") { h = String(h[..<p]) }
                            cont.resume(returning: (h, port.rawValue))
                        }
                    case let .failed(error):
                        if once.claim() { cont.resume(throwing: error) }
                    case .cancelled:
                        if once.claim() { cont.resume(throwing: CancellationError()) }
                    default:
                        break
                    }
                }
                connection.start(queue: .global())
            }
        }
    }
}
