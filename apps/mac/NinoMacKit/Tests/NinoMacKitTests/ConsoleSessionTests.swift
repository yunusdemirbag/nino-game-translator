// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import CoreGraphics
import Foundation
@testable import NinoMacKit
import NinoCore
import XCTest

// MARK: Sahteler

final class ConsoleFakeDiscovery: ConsoleDiscovering, @unchecked Sendable {
    private let lock = NSLock()
    private var _all: [DiscoveredPS5] = []
    private var _probe: ((String) -> DiscoveredPS5?)?
    private(set) var searches = 0
    private(set) var probes: [String] = []

    var all: [DiscoveredPS5] {
        get { lock.withLock { _all } }
        set { lock.withLock { _all = newValue } }
    }
    /// Yoksa `all` içinde adrese göre aranır.
    var probeAnswer: ((String) -> DiscoveredPS5?)? {
        get { lock.withLock { _probe } }
        set { lock.withLock { _probe = newValue } }
    }

    func search(duration: TimeInterval) async throws -> [DiscoveredPS5] {
        lock.withLock { searches += 1; return _all }
    }

    func probe(address: String, duration: TimeInterval) async throws -> DiscoveredPS5? {
        let (custom, all) = lock.withLock { () -> (((String) -> DiscoveredPS5?)?, [DiscoveredPS5]) in
            probes.append(address)
            return (_probe, _all)
        }
        if let custom { return custom(address) }
        return all.first { $0.address == address }
    }
}

final class ConsoleFakeLink: RemotePlayLink, @unchecked Sendable {
    let events: AsyncStream<RemotePlayLinkEvent>
    private let continuation: AsyncStream<RemotePlayLinkEvent>.Continuation
    let canSubmitPasscode: Bool
    let address: String
    private let lock = NSLock()
    private var _submitted: [String] = []
    private var _closed = false

    init(address: String, canSubmitPasscode: Bool) {
        self.address = address
        self.canSubmitPasscode = canSubmitPasscode
        (events, continuation) = AsyncStream<RemotePlayLinkEvent>.makeStream()
    }

    var submitted: [String] { lock.withLock { _submitted } }
    var closed: Bool { lock.withLock { _closed } }

    func send(_ e: RemotePlayLinkEvent) { continuation.yield(e) }
    func submitPasscode(_ code: String) { lock.withLock { _submitted.append(code) } }
    func close() {
        lock.withLock { _closed = true }
        continuation.finish()
    }
}

final class ConsoleFakeConnector: RemotePlayConnecting, @unchecked Sendable {
    private let lock = NSLock()
    private var _links: [ConsoleFakeLink] = []
    private(set) var openTimes: [TimeInterval] = []
    private(set) var wakes: [String] = []
    let clock: ConsoleClock
    var canSubmitPasscode = true
    /// Her açılışta çağrılır (ör. hemen kapanış olayı göndermek için).
    var onOpen: ((ConsoleFakeLink) -> Void)?
    var onWake: (() -> Void)?

    init(clock: ConsoleClock) { self.clock = clock }

    var links: [ConsoleFakeLink] { lock.withLock { _links } }

    func open(address: String, pairing: PS5Pairing, console: DiscoveredPS5?) throws -> RemotePlayLink {
        let link = ConsoleFakeLink(address: address, canSubmitPasscode: canSubmitPasscode)
        lock.withLock {
            _links.append(link)
            openTimes.append(clock.now())
        }
        onOpen?(link)
        return link
    }

    func wake(address: String, pairing: PS5Pairing) throws {
        lock.withLock { wakes.append(address) }
        onWake?()
    }
}

/// Uyuyanları ancak `advance` ile uyandıran sanal saat.
final class ConsoleTestClock: ConsoleClock, @unchecked Sendable {
    private struct Sleeper {
        let id: UUID
        let deadline: TimeInterval
        let continuation: CheckedContinuation<Void, Error>
    }
    private let lock = NSLock()
    private var t: TimeInterval = 0
    private var sleepers: [Sleeper] = []

    func now() -> TimeInterval { lock.withLock { t } }

    func sleep(seconds: TimeInterval) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
                let resumeNow = lock.withLock { () -> Bool in
                    if Task.isCancelled { return true }
                    sleepers.append(Sleeper(id: id, deadline: t + seconds, continuation: c))
                    return false
                }
                if resumeNow { c.resume(throwing: CancellationError()) }
            }
        } onCancel: {
            let s = lock.withLock { () -> Sleeper? in
                guard let i = sleepers.firstIndex(where: { $0.id == id }) else { return nil }
                return sleepers.remove(at: i)
            }
            s?.continuation.resume(throwing: CancellationError())
        }
    }

    func advance(by dt: TimeInterval) {
        let due = lock.withLock { () -> [Sleeper] in
            t += dt
            let ready = sleepers.filter { $0.deadline <= t + 1e-9 }
            sleepers.removeAll { $0.deadline <= t + 1e-9 }
            return ready
        }
        due.forEach { $0.continuation.resume() }
    }
}

final class ConsoleStatusLog: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [SourceStatus.ConsoleLink] = []
    func add(_ s: SourceStatus.ConsoleLink) { lock.withLock { items.append(s) } }
    var all: [SourceStatus.ConsoleLink] { lock.withLock { items } }
    var last: SourceStatus.ConsoleLink? { all.last }
}

final class ConsoleBox: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [Int] = []
    func add(_ i: Int) { lock.withLock { items.append(i) } }
    var all: [Int] { lock.withLock { items } }
}

func consoleTestImage() -> CGImage {
    let ctx = CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 8,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    return ctx.makeImage()!
}

// MARK: Saf kurallar

final class ConsoleSessionRulesTests: XCTestCase {
    func classify(_ quit: String, _ log: [String] = [], answered: Bool = true) -> SourceStatus.DropReason? {
        DropClassifier.classify(quitReason: quit, log: log, probeAnswered: answered, address: "10.0.0.5")
    }

    func testQuitReasonMapping() {
        XCTAssertNil(classify("Stopped"))
        XCTAssertEqual(classify("Remote Play on Console is already in use"), .inUseElsewhere)
        XCTAssertEqual(classify("Unknown Session Request Error", ["Reported Application Reason: 0x80108b09 (x)"]),
                       .pairingInvalid)
        XCTAssertEqual(classify("Unknown Session Request Error", ["Reported Application Reason: 0x80108b02"]),
                       .pairingInvalid)
        XCTAssertEqual(classify("Unknown Session Request Error", ["Reported Application Reason: 0x80108b26"]),
                       .pairingInvalid)
        XCTAssertEqual(classify("Unknown Session Request Error", ["Reported Application Reason: 0x80108b12"]),
                       .remotePlayDisabled)
        XCTAssertEqual(classify("Unknown Session Request Error", ["Reported Application Reason: 0x80108b33"]),
                       .rejected(code: 0x8010_8B33))
        XCTAssertEqual(classify("Connection Refused in Session Request"), .rejected(code: nil))
        // PS5'e hiç bağlanılamadı (kapalı ya da adres yanlış): ret değil.
        let connectFailed = ["Session request connect failed: Timeout", "Session request connect failed eventually."]
        XCTAssertEqual(classify("Unknown Session Request Error", connectFailed, answered: false),
                       .notFound(address: "10.0.0.5"))
        XCTAssertEqual(classify("Unknown Session Request Error", connectFailed, answered: true), .network)
        XCTAssertEqual(classify("Connection Refused in Session Request", answered: false), .notFound(address: "10.0.0.5"))
        XCTAssertEqual(classify("Unknown Session Request Error", ["Reported Application Reason: 0x80108b33"],
                                answered: false), .rejected(code: 0x8010_8B33))
        XCTAssertEqual(classify("Connection Refused in Ctrl"), .refused)
        XCTAssertEqual(classify("The Console Registration using PSN has failed"), .pairingInvalid)
        XCTAssertEqual(classify("Remote has disconnected from Stream Connection the because Server shut down"), .asleep)
        XCTAssertEqual(classify("Ctrl failed to connect"), .network)
        XCTAssertEqual(classify("RP-Version mismatch"), .other(detail: "RP-Version mismatch"))
        XCTAssertEqual(classify("None"), .other(detail: nil))
    }

    func testNetworkWithoutSearchAnswerIsNotFound() {
        XCTAssertEqual(classify("Ctrl failed to connect", answered: false), .notFound(address: "10.0.0.5"))
        XCTAssertEqual(classify("Weird", answered: false), .notFound(address: "10.0.0.5"))
        XCTAssertEqual(classify("Remote Play on Console is already in use", answered: false), .inUseElsewhere)
    }

    func testBackoffSequence() {
        var p = ReconnectPolicy()
        let delays = (0..<7).map { _ -> TimeInterval in
            guard case let .retry(d, _) = p.next(after: ConsoleAttemptOutcome(reason: .network)) else { return -1 }
            return d
        }
        XCTAssertEqual(delays, [2, 4, 8, 16, 30, 30, 30])
    }

    func testLongSessionResetsBackoffShortOneDoesNot() {
        var p = ReconnectPolicy()
        _ = p.next(after: ConsoleAttemptOutcome(reason: .network))
        _ = p.next(after: ConsoleAttemptOutcome(reason: .network))
        XCTAssertEqual(p.next(after: ConsoleAttemptOutcome(reason: .network, connected: true, gotFrames: true, duration: 30)),
                       .retry(after: 8, showing: .network))
        XCTAssertEqual(p.next(after: ConsoleAttemptOutcome(reason: .network, connected: true, gotFrames: true, duration: 61)),
                       .retry(after: 2, showing: .network))
    }

    func testInUseWaitsAtLeastEight() {
        var p = ReconnectPolicy()
        let delays = (0..<4).map { _ -> TimeInterval in
            guard case let .retry(d, _) = p.next(after: ConsoleAttemptOutcome(reason: .inUseElsewhere)) else { return -1 }
            return d
        }
        XCTAssertEqual(delays, [8, 16, 30, 30])
    }

    func testFinalReasonsGiveUp() {
        for r: SourceStatus.DropReason in [.pairingInvalid, .remotePlayDisabled, .passcodeRequired, .passcodeWrong, .noPicture] {
            var p = ReconnectPolicy()
            XCTAssertEqual(p.next(after: ConsoleAttemptOutcome(reason: r)), .giveUp(r))
        }
        for r: SourceStatus.DropReason in [.asleep, .inUseElsewhere, .refused, .network, .notFound(address: "a"),
                                           .rejected(code: 1), .other(detail: nil)] {
            var p = ReconnectPolicy()
            guard case .retry = p.next(after: ConsoleAttemptOutcome(reason: r)) else { return XCTFail("\(r)") }
        }
    }

    func testThreeFramelessSessionsGiveUp() {
        var p = ReconnectPolicy()
        let frameless = ConsoleAttemptOutcome(reason: .other(detail: nil), connected: true, gotFrames: false, duration: 8)
        guard case .retry = p.next(after: frameless) else { return XCTFail() }
        // Görüntülü bir oturum sayacı sıfırlar.
        _ = p.next(after: ConsoleAttemptOutcome(reason: .network, connected: true, gotFrames: true, duration: 5))
        guard case .retry = p.next(after: frameless), case .retry = p.next(after: frameless) else { return XCTFail() }
        XCTAssertEqual(p.next(after: frameless), .giveUp(.noPicture))
        p.reset()
        guard case .retry(2, _) = p.next(after: frameless) else { return XCTFail() }
    }

    func testLocatorPick() {
        let a = DiscoveredPS5(hostID: "A", name: "Salon", address: "10.0.0.2", asleep: false)
        let b = DiscoveredPS5(hostID: "B", name: "Oda", address: "10.0.0.3", asleep: false)
        let ps4 = DiscoveredPS5(hostID: "C", name: "Salon", address: "10.0.0.4", asleep: false, isPS5: false)
        XCTAssertEqual(ConsoleLocator.pick(from: [a, ps4], name: "başka"), a)
        XCTAssertEqual(ConsoleLocator.pick(from: [a, b], name: "oda"), b)
        XCTAssertNil(ConsoleLocator.pick(from: [a, b], name: "Mutfak"))
        XCTAssertNil(ConsoleLocator.pick(from: [a, a], name: "Salon"))
        XCTAssertNil(ConsoleLocator.pick(from: [], name: "Salon"))
        XCTAssertTrue(ConsoleLocator.mayScanWholeNetwork(lastScan: nil, now: 0))
        XCTAssertFalse(ConsoleLocator.mayScanWholeNetwork(lastScan: 10, now: 50))
        XCTAssertTrue(ConsoleLocator.mayScanWholeNetwork(lastScan: 10, now: 70))
    }

    func testPairingKeysUsable() {
        let key = Data("1a2b".utf8) + Data(repeating: 0, count: 12)
        XCTAssertTrue(PS5Pairing(host: "", name: "", registKey: key, morning: Data(repeating: 1, count: 16)).hasUsableKeys)
        XCTAssertFalse(PS5Pairing(host: "", name: "", registKey: key, morning: Data(count: 16)).hasUsableKeys)
        XCTAssertFalse(PS5Pairing(host: "", name: "", registKey: Data(count: 15), morning: key).hasUsableKeys)
    }
}

// MARK: Denetleyici (sahte ağ, sanal saat)

final class ConsoleSessionControllerTests: XCTestCase {
    let pairing = PS5Pairing(host: "10.0.0.5", name: "Salon PS5", registKey: Data("1a2b3c4d".utf8) + Data(count: 8),
                             morning: Data(repeating: 7, count: 16))
    var clock: ConsoleTestClock!
    var discovery: ConsoleFakeDiscovery!
    var connector: ConsoleFakeConnector!
    var store: MemoryConsoleRecordStore!
    var statuses: ConsoleStatusLog!
    var controller: ConsoleSessionController!
    /// Akış bırakılırsa denetleyici durur; testte tutulur.
    var stream: AsyncStream<Frame>?

    override func setUp() {
        clock = ConsoleTestClock()
        discovery = ConsoleFakeDiscovery()
        connector = ConsoleFakeConnector(clock: clock)
        store = MemoryConsoleRecordStore(pairing: pairing, accountID: Data(repeating: 1, count: 8))
        statuses = ConsoleStatusLog()
        controller = ConsoleSessionController(store: store, discovery: discovery, connector: connector, clock: clock)
        let s = statuses!
        controller.onStatus = { s.add($0) }
    }

    override func tearDown() {
        controller.stop()
    }

    func awake(_ address: String = "10.0.0.5") -> DiscoveredPS5 {
        DiscoveredPS5(hostID: "H1", name: "Salon PS5", address: address, asleep: false)
    }

    /// Görevlerin ilerlemesine izin verir.
    func settle() async {
        for _ in 0..<50 { await Task.yield() }
        try? await Task.sleep(nanoseconds: 2_000_000)
    }

    /// Koşul sağlanana kadar sanal saati adım adım ilerletir.
    @discardableResult
    func drive(step: TimeInterval = 0.5, upTo limit: TimeInterval = 400,
               until condition: @escaping () -> Bool) async -> Bool {
        while clock.now() <= limit {
            await settle()
            if condition() { return true }
            clock.advance(by: step)
        }
        return condition()
    }

    func collect(_ stream: AsyncStream<Frame>) -> ConsoleBox {
        let box = ConsoleBox()
        Task { for await f in stream { box.add(f.index) } }
        return box
    }

    func testConnectsAndStreamsFramesAtMostTwentyPerSecond() async {
        discovery.all = [awake()]
        let box = collect(controller.frames())
        let opened = await drive { self.connector.links.count == 1 }
        XCTAssertTrue(opened)
        let link = connector.links[0]
        XCTAssertEqual(link.address, "10.0.0.5")
        link.send(.connected)
        link.send(.frame(Frame(image: consoleTestImage(), index: 1)))
        link.send(.frame(Frame(image: consoleTestImage(), index: 2)))   // aynı anda: atlanır
        await drive { box.all == [1] }
        clock.advance(by: 0.1)
        link.send(.frame(Frame(image: consoleTestImage(), index: 3)))
        let got = await drive(step: 0.01, upTo: clock.now() + 1) { box.all == [1, 3] }
        XCTAssertTrue(got, "\(box.all)")
        XCTAssertEqual(statuses.last, .streaming)
        XCTAssertEqual(statuses.all.first, .connecting)
        XCTAssertTrue(connector.wakes.isEmpty)
    }

    func testFrameStreamSurvivesReconnect() async {
        discovery.all = [awake()]
        let box = collect(controller.frames())
        await drive { self.connector.links.count == 1 }
        connector.links[0].send(.connected)
        connector.links[0].send(.frame(Frame(image: consoleTestImage(), index: 1)))
        await drive { box.all == [1] }
        connector.links[0].send(.ended(quitReason: "Ctrl failed to connect", log: []))
        await drive { self.statuses.last == .dropped(.network) }
        let reopened = await drive { self.connector.links.count == 2 }
        XCTAssertTrue(reopened)
        XCTAssertTrue(connector.links[0].closed)
        connector.links[1].send(.connected)
        connector.links[1].send(.frame(Frame(image: consoleTestImage(), index: 9)))
        let got = await drive { box.all == [1, 9] }
        XCTAssertTrue(got, "\(box.all)")
    }

    func testBackoffBetweenFailedSessions() async {
        discovery.all = [awake()]
        connector.onOpen = { $0.send(.ended(quitReason: "Ctrl failed to connect", log: [])) }
        stream = controller.frames()
        let done = await drive(step: 0.25) { self.connector.openTimes.count >= 6 }
        XCTAssertTrue(done)
        let t = connector.openTimes
        let gaps = zip(t.dropFirst(), t).map { $0 - $1 }
        XCTAssertEqual(gaps, [2, 4, 8, 16, 30])
    }

    func testWakesSleepingPS5ThenConnects() async {
        discovery.all = [DiscoveredPS5(hostID: "H1", name: "Salon PS5", address: "10.0.0.5", asleep: true)]
        connector.onWake = { [discovery] in discovery!.all = [DiscoveredPS5(hostID: "H1", name: "Salon PS5", address: "10.0.0.5", asleep: false)] }
        stream = controller.frames()
        let opened = await drive { self.connector.links.count == 1 }
        XCTAssertTrue(opened)
        XCTAssertEqual(connector.wakes, ["10.0.0.5"])
        XCTAssertLessThanOrEqual(connector.openTimes[0], 20)
    }

    func testSleepingPS5ThatNeverWakesIsAsleepAndRetried() async {
        discovery.all = [DiscoveredPS5(hostID: "H1", name: "Salon PS5", address: "10.0.0.5", asleep: true)]
        stream = controller.frames()
        let dropped = await drive { self.statuses.last == .dropped(.asleep) }
        XCTAssertTrue(dropped)
        XCTAssertGreaterThanOrEqual(clock.now(), 20)
        XCTAssertTrue(connector.links.isEmpty)
        let retried = await drive { self.connector.wakes.count == 2 }
        XCTAssertTrue(retried)
    }

    func testFindsPS5AtNewAddressAndSavesIt() async throws {
        discovery.all = [awake("10.0.0.77")]
        let changed = ConsoleBox()
        controller.onPairingChanged = { p in if p.host == "10.0.0.77" { changed.add(1) } }
        stream = controller.frames()
        let opened = await drive { self.connector.links.count == 1 }
        XCTAssertTrue(opened)
        XCTAssertEqual(connector.links[0].address, "10.0.0.77")
        XCTAssertEqual(try store.loadPairing()?.host, "10.0.0.77")
        XCTAssertEqual(changed.all, [1])
    }

    func testUnusableSavedAddressScansAndNeverStoresBadAddress() async throws {
        try store.savePairing(PS5Pairing(host: "0.0.0.0", name: "Salon PS5", registKey: pairing.registKey,
                                         morning: pairing.morning))
        discovery.all = []
        stream = controller.frames()
        let dropped = await drive { self.statuses.last == .dropped(.network) }
        XCTAssertTrue(dropped)
        XCTAssertTrue(discovery.probes.isEmpty)
        XCTAssertEqual(discovery.searches, 1)
        XCTAssertEqual(try store.loadPairing()?.host, "0.0.0.0")
        XCTAssertTrue(connector.links.isEmpty)
    }

    func testNoAnswerAtSavedAddressStillTriesThenReportsNotFound() async {
        discovery.all = []
        connector.onOpen = { $0.send(.ended(quitReason: "Ctrl failed to connect", log: [])) }
        stream = controller.frames()
        let dropped = await drive { self.statuses.last == .dropped(.notFound(address: "10.0.0.5")) }
        XCTAssertTrue(dropped)
        XCTAssertEqual(connector.links.count, 1)
        // Tüm ağ taraması her denemede yapılmaz.
        await drive { self.connector.links.count == 3 }
        XCTAssertLessThan(discovery.searches, 3)
    }

    func testSendsSavedPasscodeThenGivesUpWhenWrong() async {
        discovery.all = [awake()]
        store.setLoginPasscode("4321")
        stream = controller.frames()
        await drive { self.connector.links.count == 1 }
        let link = connector.links[0]
        link.send(.passcodeRequested(incorrect: false))
        let sent = await drive { link.submitted == ["4321"] }
        XCTAssertTrue(sent)
        link.send(.passcodeRequested(incorrect: true))
        let gaveUp = await drive { self.statuses.last == .dropped(.passcodeWrong) }
        XCTAssertTrue(gaveUp)
        await drive(upTo: clock.now() + 60) { false }
        XCTAssertEqual(connector.links.count, 1)
    }

    func testPasscodeRequiredWithoutSavedOne() async {
        discovery.all = [awake()]
        stream = controller.frames()
        await drive { self.connector.links.count == 1 }
        connector.links[0].send(.passcodeRequested(incorrect: false))
        let gaveUp = await drive { self.statuses.last == .dropped(.passcodeRequired) }
        XCTAssertTrue(gaveUp)
        XCTAssertTrue(connector.links[0].submitted.isEmpty)
    }

    func testPairingRejectedGivesUp() async {
        discovery.all = [awake()]
        connector.onOpen = {
            $0.send(.ended(quitReason: "Unknown Session Request Error",
                           log: ["Reported Application Reason: 0x80108b09 (Regist Failed)"]))
        }
        stream = controller.frames()
        let gaveUp = await drive { self.statuses.last == .dropped(.pairingInvalid) }
        XCTAssertTrue(gaveUp)
        await drive(upTo: clock.now() + 60) { false }
        XCTAssertEqual(connector.links.count, 1)
    }

    func testWatchdogReconnectsAndThreeFramelessSessionsMeanNoPicture() async {
        discovery.all = [awake()]
        connector.onOpen = { $0.send(.connected) }
        stream = controller.frames()
        let gaveUp = await drive { self.statuses.last == .dropped(.noPicture) }
        XCTAssertTrue(gaveUp)
        XCTAssertEqual(connector.links.count, 3)
        XCTAssertTrue(connector.links.allSatisfy(\.closed))
        let t = connector.openTimes
        XCTAssertEqual(t[1] - t[0], 8 + 2, accuracy: 1.01)
    }

    func testReconnectNowResetsAndRestarts() async {
        discovery.all = [awake()]
        connector.onOpen = { $0.send(.ended(quitReason: "Ctrl failed to connect", log: [])) }
        stream = controller.frames()
        await drive(step: 0.25) { self.connector.openTimes.count >= 4 }   // bekleme 16 sn'ye çıktı
        let before = connector.openTimes.count
        let at = clock.now()
        controller.reconnectNow()
        let restarted = await drive(step: 0.25) { self.connector.openTimes.count == before + 1 }
        XCTAssertTrue(restarted)
        XCTAssertLessThan(connector.openTimes.last! - at, 1)
        await drive(step: 0.25) { self.connector.openTimes.count == before + 2 }
        let t = connector.openTimes
        XCTAssertEqual(t[t.count - 1] - t[t.count - 2], 2, accuracy: 0.01)
    }

    func testStopFinishesStreamAndClosesLink() async {
        discovery.all = [awake()]
        let stream = controller.frames()
        await drive { self.connector.links.count == 1 }
        let ended = ConsoleBox()
        Task { for await _ in stream {}; ended.add(1) }
        controller.stop()
        let finished = await drive { ended.all == [1] && self.connector.links[0].closed }
        XCTAssertTrue(finished)
        XCTAssertEqual(statuses.last, .idle)
    }

    func testMissingPairingGivesUp() async throws {
        let empty = MemoryConsoleRecordStore()
        let c = ConsoleSessionController(store: empty, discovery: discovery, connector: connector, clock: clock)
        let s = ConsoleStatusLog()
        c.onStatus = { s.add($0) }
        stream = c.frames()
        let gaveUp = await drive { s.last == .dropped(.pairingInvalid) }
        XCTAssertTrue(gaveUp)
        c.stop()
    }
}
