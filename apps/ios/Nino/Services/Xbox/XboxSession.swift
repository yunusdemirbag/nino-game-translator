// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import CoreGraphics
import Foundation
import NinoCore
import os

/// Xbox günlüğü (Xcode konsolunda ve Konsol uygulamasında "xbox" kategorisi). Jeton ve kod yazılmaz.
enum XboxLog {
    private static let logger = Logger(subsystem: "com.ninotranslator.ios", category: "xbox")
    static let write: @Sendable (String) -> Void = { text in logger.info("\(text, privacy: .public)") }
}

/// Görüntü bağlantısının WebRTC tarafı. Gerçeği `WebRTCXboxPeer`; testlerde sahtesi.
protocol XboxPeer: AnyObject, Sendable {
    /// Yerel SDP teklifi (stereo düzeltmesiyle, yerel açıklama olarak kurulmuş).
    func makeOffer() async throws -> String
    func acceptAnswer(_ sdp: String) async throws
    /// Yerel adaylar toplanana kadar (en çok `timeout`) bekler.
    func localCandidates(timeout: TimeInterval) async -> [XboxCandidate]
    /// Dönüş: eklenebilen aday sayısı.
    func addRemoteCandidates(_ candidates: [XboxCandidate]) async -> Int
    /// Bağlantı kapandıysa nedeni.
    var closedReason: String? { get }
    func close()
}

/// Peer'in görüntü karelerini verdiği yer.
typealias XboxFrameSink = @Sendable (CGImage) -> Void

/// Xbox ev yayını oturumu: sinyalleşme, WebRTC, canlı tutma ve yeniden deneme. Kareler bütün yeniden bağlanmalar
/// boyunca tek bir `FrameSource` akışından gelir; durum değişiklikleri `statuses()` akışından.
final class XboxSession: FrameSource, @unchecked Sendable {
    enum Status: Equatable, Sendable {
        case connecting
        case streaming
        /// `willRetry`: kendiliğinden yeniden denenecek mi.
        case lost(XboxProblem, willRetry: Bool, detail: String)
    }

    struct Timing: Sendable {
        var candidateWait: TimeInterval = 5
        var firstFrameTimeout: TimeInterval = 20
        var keepAliveEvery: TimeInterval = 30
        var tick: TimeInterval = 0.25
        var plan = XboxSessionPlan()
    }

    typealias PeerFactory = @Sendable (_ playAudio: Bool, _ sink: @escaping XboxFrameSink) throws -> XboxPeer

    let console: XboxConsole
    private let cloud: XboxCloud
    private let playAudio: Bool
    private let makePeer: PeerFactory
    private let timing: Timing
    private let log: @Sendable (String) -> Void

    private let lock = NSLock()
    private var plan: XboxSessionPlan
    private var worker: Task<Void, Never>?
    private var peer: XboxPeer?
    private var sessionID: String?
    private var restartWanted = false
    private var frameCount = 0
    /// Bütün denemeler boyunca artan kare sırası.
    private var frameSerial = 0
    private var lastFrameAt: TimeInterval = 0

    private let frameStream: AsyncStream<Frame>
    private let frameOut: AsyncStream<Frame>.Continuation
    private let statusStream: AsyncStream<Status>
    private let statusOut: AsyncStream<Status>.Continuation

    init(console: XboxConsole, cloud: XboxCloud, playAudio: Bool, timing: Timing = Timing(),
         log: @escaping @Sendable (String) -> Void = { _ in }, makePeer: @escaping PeerFactory) {
        self.console = console
        self.cloud = cloud
        self.playAudio = playAudio
        self.timing = timing
        self.log = log
        self.makePeer = makePeer
        plan = timing.plan
        (frameStream, frameOut) = AsyncStream<Frame>.makeStream(bufferingPolicy: .bufferingNewest(1))
        (statusStream, statusOut) = AsyncStream<Status>.makeStream(bufferingPolicy: .unbounded)
    }

    func frames() -> AsyncStream<Frame> { frameStream }
    func statuses() -> AsyncStream<Status> { statusStream }

    /// Toplam alınan (çevrilen) kare sayısı.
    var framesReceived: Int { lock.withLock { frameCount } }

    func start() {
        lock.withLock {
            guard worker == nil else { return }
            worker = Task.detached(priority: .userInitiated) { [weak self] in await self?.run() }
        }
    }

    func stop() {
        let (task, peer, id) = lock.withLock { () -> (Task<Void, Never>?, XboxPeer?, String?) in
            plan.stop()
            defer { worker = nil; self.peer = nil; sessionID = nil }
            return (worker, self.peer, sessionID)
        }
        task?.cancel()
        peer?.close()
        frameOut.finish()
        statusOut.finish()
        if let id {
            let cloud = cloud
            Task.detached { try? await cloud.close(id) }
        }
    }

    /// Uygulama öne geldiğinde: canlı yayın ya da bekleyen yeniden deneme kapatılıp beklemeden baştan açılır. Açılmakta
    /// olan bir denemeye dokunulmaz (Xbox'a ikinci kez "oynat" gitmesin).
    func reconnectNow() {
        lock.withLock {
            switch plan.stage {
            case .live, .backingOff: restartWanted = true
            default: break
            }
        }
    }

    // MARK: Döngü

    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    private func decide(_ body: (inout XboxSessionPlan) -> XboxSessionPlan.Next) -> XboxSessionPlan.Next {
        lock.withLock { body(&plan) }
    }

    private func run() async {
        var next = decide { $0.begin() }
        while !Task.isCancelled {
            switch next {
            case .nothing:
                return
            case let .end(problem):
                await closeAttempt()
                log("vazgeçildi: \(problem.rawValue)")
                return
            case let .retry(delay):
                await closeAttempt()
                await wait(delay)
                if Task.isCancelled { return }
                next = decide { $0.begin() }
            default:
                next = await attempt(next)
            }
        }
    }

    /// Bir oturum açma denemesi. Dönüş: `retry`/`end` (deneme bitti) ya da `open` (hemen baştan).
    private func attempt(_ first: XboxSessionPlan.Next) async -> XboxSessionPlan.Next {
        var next = first
        lock.withLock { restartWanted = false }
        statusOut.yield(.connecting)
        var id = ""
        do {
            while !Task.isCancelled {
                switch next {
                case .open:
                    id = try await cloud.play(console: console.id)
                    lock.withLock { sessionID = id }
                    log("oturum açıldı")
                    next = decide { $0.opened() }
                case let .askState(after):
                    if after > 0 { try await Task.sleep(for: .seconds(after)) }
                    let state = try await cloud.state(id)
                    let at = now
                    next = decide { $0.observed(state, at: at) }
                    if next.endsAttempt { report(state.errorDetails ?? "durum: \(state.state)", next) }
                case .connect:
                    try await cloud.connect(id)
                    let at = now
                    next = decide { $0.connectAccepted(at: at) }
                    if next.endsAttempt { report("Xbox hazır olmadı", next) }
                case .negotiate:
                    return try await negotiateAndWatch(id)
                case .retry, .end, .nothing:
                    return next
                }
            }
            return .nothing
        } catch is CancellationError {
            return .nothing
        } catch {
            let failure = error as? XboxFailure ?? XboxFailure(.unexpected, "\(error)")
            let at = now
            let decided = decide { $0.fail(failure.problem, at: at) }
            report(failure.detail, decided, problem: failure.problem)
            return decided
        }
    }

    /// WebRTC el sıkışması; sonra yayın bitene kadar izler (canlı tutma, ilk kare süresi, kopma, yeniden başlatma).
    private func negotiateAndWatch(_ id: String) async throws -> XboxSessionPlan.Next {
        lock.withLock {
            frameCount = 0
            lastFrameAt = 0
        }
        let peer = try makePeer(playAudio) { [weak self] image in self?.received(image) }
        lock.withLock { self.peer = peer }
        let offer = try await peer.makeOffer()
        let answer = try await cloud.exchangeSDP(id, offer: offer)
        try await peer.acceptAnswer(answer)
        let local = await peer.localCandidates(timeout: timing.candidateWait)
        log("ICE: \(local.count) yerel aday")
        let remote = try await cloud.exchangeICE(id, local: local)
        let added = await peer.addRemoteCandidates(remote)
        log("ICE: \(added)/\(remote.count) Xbox adayı alındı")

        let started = now
        var lastKeepAlive = started
        while !Task.isCancelled {
            if lock.withLock({ restartWanted }) {
                lock.withLock { restartWanted = false }
                log("hemen yeniden bağlanılıyor")
                await closeAttempt()
                return decide { $0.restartNow() }
            }
            if let reason = peer.closedReason { throw XboxFailure(.offline, reason) }
            if framesReceived == 0, now - started > timing.firstFrameTimeout {
                throw XboxFailure(.unreachable, "\(Int(timing.firstFrameTimeout)) sn içinde görüntü gelmedi")
            }
            if now - lastKeepAlive >= timing.keepAliveEvery {
                lastKeepAlive = now
                do { try await cloud.keepAlive(id) } catch { log("canlı tutma: \(error)") }
            }
            try await Task.sleep(for: .seconds(timing.tick))
        }
        throw CancellationError()
    }

    private func received(_ image: CGImage) {
        let at = now
        let (index, becameLive) = lock.withLock { () -> (Int, Bool) in
            frameCount += 1
            frameSerial += 1
            lastFrameAt = at
            return (frameSerial, frameCount == 1 ? plan.firstFrame(at: at) : false)
        }
        if becameLive {
            log("ilk kare \(image.width)x\(image.height)")
            statusOut.yield(.streaming)
        }
        frameOut.yield(Frame(image: image, index: index, time: at))
    }

    private func report(_ detail: String, _ next: XboxSessionPlan.Next, problem: XboxProblem? = nil) {
        let stage = lock.withLock { plan.stage }
        let kind: XboxProblem
        switch stage {
        case let .backingOff(p, _), let .gaveUp(p): kind = p
        default: kind = problem ?? .unexpected
        }
        let retrying: Bool
        if case .retry = next { retrying = true } else { retrying = false }
        log("kopma (\(kind.rawValue)): \(detail)\(retrying ? "; yeniden denenecek" : "; durdu")")
        guard !lock.withLock({ plan.isStopped }) else { return }
        statusOut.yield(.lost(kind, willRetry: retrying, detail: detail))
    }

    private func closeAttempt() async {
        let (peer, id) = lock.withLock { () -> (XboxPeer?, String?) in
            defer { self.peer = nil; sessionID = nil }
            return (self.peer, sessionID)
        }
        peer?.close()
        if let id { try? await cloud.close(id) }
    }

    /// Bekler; `reconnectNow` gelirse beklemeyi keser.
    private func wait(_ seconds: TimeInterval) async {
        let end = now + seconds
        while !Task.isCancelled, now < end {
            if lock.withLock({ restartWanted }) {
                lock.withLock { restartWanted = false }
                return
            }
            try? await Task.sleep(for: .seconds(min(timing.tick, max(0.001, end - now))))
        }
    }
}
