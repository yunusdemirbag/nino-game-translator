// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// TV ekranındaki altyazı durumu.
public struct DisplayBoard: Equatable, Sendable {
    public private(set) var current: ShowPayload?

    public init() {}

    /// `show` eskisinin yerine geçer. Değişiklik olduysa `true`.
    @discardableResult
    public mutating func show(_ p: ShowPayload) -> Bool {
        guard current != p else { return false }
        current = p
        return true
    }

    /// `id` verilirse yalnız ekrandaki o ise kaldırır; yoksa temizler.
    @discardableResult
    public mutating func clear(id: Int?) -> Bool {
        guard let c = current else { return false }
        if let id, id != c.id { return false }
        current = nil
        return true
    }
}

/// TV'nin tek bir göndericiyle olan konuşması. Ağdan bağımsız, saf durum makinesi.
public struct DisplaySession: Sendable {
    public enum State: Equatable, Sendable { case awaitingHello, ready, closed }

    public enum Output: Equatable, Sendable {
        case send(NinoMessage)
        case show(ShowPayload)
        case clear(id: Int?)
        /// El sıkışma bitti, oturum hazır.
        case ready(version: Int)
        case close
    }

    public let name: String
    public let supportedVersions: [Int]
    public private(set) var state: State = .awaitingHello
    public private(set) var version: Int?

    public init(name: String, supportedVersions: [Int] = NinoLink.supportedVersions) {
        self.name = name
        self.supportedVersions = supportedVersions
    }

    /// Gelen tek bir metin mesajını işler.
    public mutating func receive(_ text: String) -> [Output] {
        guard state != .closed else { return [] }
        if text.utf8.count > NinoLink.maxMessageBytes {
            return fail(NinoLink.ErrorCode.tooLarge)
        }
        let message: NinoMessage
        do {
            message = try NinoMessage(string: text)
        } catch {
            if state == .awaitingHello { return fail(NinoLink.ErrorCode.badHandshake) }
            return [.send(.error(code: NinoLink.ErrorCode.badMessage, message: "\(error)", versions: nil))]
        }

        switch state {
        case .awaitingHello:
            guard case let .hello(v, _, _) = message else { return fail(NinoLink.ErrorCode.badHandshake) }
            guard supportedVersions.contains(v) else {
                state = .closed
                return [.send(.error(code: NinoLink.ErrorCode.versionUnsupported, message: nil, versions: supportedVersions)), .close]
            }
            state = .ready
            version = v
            return [.send(.welcome(version: v, name: name)), .ready(version: v)]
        case .ready:
            switch message {
            case let .show(p): return [.show(p)]
            case let .clear(id): return [.clear(id: id)]
            case let .ping(t): return [.send(.pong(t: t))]
            default: return []
            }
        case .closed:
            return []
        }
    }

    /// El sıkışma süresi doldu.
    public mutating func handshakeTimedOut() -> [Output] {
        guard state == .awaitingHello else { return [] }
        state = .closed
        return [.close]
    }

    /// Başka bir gönderici bu oturumun yerini aldı.
    public mutating func replaced() -> [Output] {
        guard state == .ready else { return [] }
        return fail(NinoLink.ErrorCode.replaced)
    }

    private mutating func fail(_ code: String) -> [Output] {
        state = .closed
        return [.send(.error(code: code, message: nil, versions: nil)), .close]
    }
}
