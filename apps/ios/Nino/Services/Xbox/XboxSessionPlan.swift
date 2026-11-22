// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// Ev yayını oturumunun kuralları (yan etkisiz; `XboxSession` uygular, testler doğrudan sınar).
///
/// Akış: oturum aç → `/state` sorulur; `ReadyToConnect` gelince bir kez konsola bağlanılır; `Provisioned` gelince
/// WebRTC el sıkışması → ilk kare gelince canlı. Kopma ya da hata olursa 5, 15, 45 sn sonra baştan denenir; üç ardışık
/// başarısızlıktan sonra durulur. En az bir dakika canlı kalan yayının kopması yeni bir dizi başlatır. Konsol yayını
/// kendisi reddettiyse (`Failed` ya da dolu `errorDetails`) ve giriş/profil sorunlarında hiç denenmez: konsolu art arda
/// tetiklemek, konsolun oyunu başka cihaza devretmesine yol açar ve oyuncunun oturumu bozulur.
struct XboxSessionPlan: Equatable {
    enum Stage: Equatable {
        case idle
        case opening
        case waiting(polls: Int, connectSent: Bool)
        case negotiating
        case live(since: TimeInterval)
        case backingOff(XboxProblem, attempt: Int)
        case gaveUp(XboxProblem)
        case stopped
    }

    enum Next: Equatable {
        case open
        case askState(after: TimeInterval)
        case connect
        case negotiate
        /// Kapat, verilen süre sonra baştan aç.
        case retry(after: TimeInterval)
        /// Kapat, bir daha deneme.
        case end(XboxProblem)
        case nothing

        /// Deneme bitti (kapatılıp beklenecek ya da durulacak).
        var endsAttempt: Bool {
            switch self {
            case .retry, .end: true
            default: false
            }
        }
    }

    var maxPolls = 90
    var pollInterval: TimeInterval = 1
    var retryDelays: [TimeInterval] = [5, 15, 45]
    var healthyAfter: TimeInterval = 60

    private(set) var stage: Stage = .idle
    /// Ardışık başarısız deneme sayısı.
    private(set) var failures = 0

    var isStopped: Bool { stage == .stopped }

    mutating func begin() -> Next {
        guard stage != .stopped else { return .nothing }
        stage = .opening
        return .open
    }

    mutating func opened() -> Next {
        guard stage == .opening else { return .nothing }
        stage = .waiting(polls: 0, connectSent: false)
        return .askState(after: 0)
    }

    /// `/state` yanıtı geldi.
    mutating func observed(_ status: XboxStreamState, at now: TimeInterval) -> Next {
        guard case let .waiting(polls, connectSent) = stage else { return .nothing }
        if status.state == "Failed" || (status.state != "Provisioned" && status.errorDetails != nil) {
            return fail(Self.refusal(status.errorDetails), at: now, permanent: true)
        }
        if status.state == "Provisioned" {
            stage = .negotiating
            return .negotiate
        }
        if status.state == "ReadyToConnect" && !connectSent {
            stage = .waiting(polls: polls, connectSent: true)
            return .connect
        }
        return poll(polls, connectSent, at: now)
    }

    /// Konsola bağlanma isteği kabul edildi.
    mutating func connectAccepted(at now: TimeInterval) -> Next {
        guard case let .waiting(polls, connectSent) = stage else { return .nothing }
        return poll(polls, connectSent, at: now)
    }

    private mutating func poll(_ polls: Int, _ connectSent: Bool, at now: TimeInterval) -> Next {
        guard polls + 1 < maxPolls else { return fail(.timeout, at: now) }
        stage = .waiting(polls: polls + 1, connectSent: connectSent)
        return .askState(after: pollInterval)
    }

    /// İlk kare geldi. Dönüş: canlıya yeni mi geçildi.
    mutating func firstFrame(at now: TimeInterval) -> Bool {
        guard stage == .negotiating else { return false }
        stage = .live(since: now)
        return true
    }

    /// Bir hata ya da kopma. `permanent`: konsol yayını kendisi reddetti.
    mutating func fail(_ problem: XboxProblem, at now: TimeInterval, permanent: Bool = false) -> Next {
        guard stage != .stopped else { return .nothing }
        if case let .live(since) = stage, now - since >= healthyAfter { failures = 0 }
        failures += 1
        if permanent || problem.needsUser || failures > retryDelays.count {
            stage = .gaveUp(problem)
            return .end(problem)
        }
        stage = .backingOff(problem, attempt: failures)
        return .retry(after: retryDelays[failures - 1])
    }

    /// Kullanıcı isteğiyle hemen yeniden bağlanma (uygulama öne geldi); deneme sayılmaz.
    mutating func restartNow() -> Next {
        switch stage {
        case .stopped, .gaveUp: return .nothing
        default:
            stage = .idle
            return begin()
        }
    }

    mutating func stop() { stage = .stopped }

    /// Konsolun reddinin nedeni.
    static func refusal(_ details: String?) -> XboxProblem {
        let t = (details ?? "").lowercased()
        if ["inuse", "busy", "alreadystreaming"].contains(where: t.contains) { return .busy }
        if t.contains("startstreamingsession") || t.contains("start streaming session") { return .startFailed }
        return .unreachable
    }
}
