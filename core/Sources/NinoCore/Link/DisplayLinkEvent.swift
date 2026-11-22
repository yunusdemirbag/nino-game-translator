// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// Bir TV bağlantısının yaşam olayı: bağlandı, koptu ya da zaman aşımıyla düşürüldü.
///
/// Üç yol da aynı türü yayınlar: eski 8787 SSE (`LegacyEventServer.onLinkEvent`), 47800 giriş WebSocket'i
/// (`NinoSenderIngress.onLinkEvent`) ve giden bağlantı (`NinoSender.setLinkEventHandler`). Her bağlantı için tam bir
/// "bağlandı" ve tam bir "koptu/zaman aşımı" gelir (ilk neden geçerlidir). OBS izleyicileri olay üretmez.
public struct DisplayLinkEvent: Sendable, Equatable {
    public enum Kind: String, Sendable {
        case connected
        case disconnected
        /// Kopmanın nedeni bir süre sınırı (kalp atışı, asılı yazma).
        case timedOut = "timed-out"
    }

    public enum Route: String, Sendable {
        /// Eski TV uygulamaları: 8787, HTTP + SSE.
        case legacySSE = "sse-8787"
        /// Web TV'ler bize bağlanır: 47800, WebSocket.
        case ingress = "ws-47800"
        /// Biz dinleyen TV'ye bağlanırız (`NinoSender`).
        case outgoing
    }

    public enum Reason: String, Sendable {
        /// Karşı taraf bağlantıyı kapattı (FIN, WebSocket close).
        case peerClosed = "peer-closed"
        /// Okuma ya da bağlantı hatası (ağ, sıfırlama).
        case readFailed = "read-failed"
        /// Yazma hata verdi.
        case writeFailed = "write-failed"
        /// Yazılanlar karşıya gitmiyor (okumayı bırakmış istemci): süre ya da birikme sınırı aşıldı.
        case writeStalled = "write-stalled"
        /// Kalp atışına cevap / karşıdan ses gelmedi.
        case heartbeatTimeout = "heartbeat-timeout"
        /// Aynı adresten yeni bir dinleyici geldi; eskisi ölü sayıldı.
        case replaced
        /// Bozuk veri ya da protokol hatası.
        case protocolError = "protocol-error"
        /// Sunucu durduruldu.
        case serverStopped = "server-stopped"
        /// Bu taraf kapattı (durdurma, yeniden bağlanma).
        case localClose = "local-close"

        public var isTimeout: Bool { self == .writeStalled || self == .heartbeatTimeout }
        /// Kopma bu taraftan mı istendi (sayılmaz)?
        public var isLocal: Bool { self == .serverStopped || self == .localClose }
    }

    public var kind: Kind
    public var route: Route
    /// Karşı tarafın adresi (yalnız günlük için; ölçüme gitmez).
    public var host: String
    /// Bu bağlantının kimliği (yeniden bağlanınca değişir).
    public var connectionID: String
    /// TV'nin bildirdiği model ve TV uygulamasının sürümü (biliniyorsa).
    public var model: String?
    public var appVersion: String?
    public var at: Date
    /// Bağlı kalma süresi (yalnız kopmada).
    public var duration: TimeInterval?
    /// Kopma nedeni (yalnız kopmada).
    public var reason: Reason?

    public init(kind: Kind, route: Route, host: String, connectionID: String, model: String? = nil,
                appVersion: String? = nil, at: Date = Date(), duration: TimeInterval? = nil, reason: Reason? = nil) {
        self.kind = kind
        self.route = route
        self.host = host
        self.connectionID = connectionID
        self.model = model
        self.appVersion = appVersion
        self.at = at
        self.duration = duration
        self.reason = reason
    }

    static func connected(_ route: Route, host: String, id: String, model: String?, appVersion: String?,
                          at: Date = Date()) -> DisplayLinkEvent {
        DisplayLinkEvent(kind: .connected, route: route, host: host, connectionID: id, model: model,
                         appVersion: appVersion, at: at)
    }

    static func dropped(_ route: Route, host: String, id: String, model: String?, appVersion: String?,
                        since: Date?, reason: Reason, at: Date = Date()) -> DisplayLinkEvent {
        DisplayLinkEvent(kind: reason.isTimeout ? .timedOut : .disconnected, route: route, host: host,
                         connectionID: id, model: model, appVersion: appVersion, at: at,
                         duration: since.map { max(0, at.timeIntervalSince($0)) }, reason: reason)
    }
}

public typealias DisplayLinkEventHandler = @Sendable (DisplayLinkEvent) -> Void
