// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation
import NinoCore
import XCTest
@testable import NinoMacKit

// TV kurulumu testlerinin sahte kapıları. Ağ ve süreç yok.

final class FakeHTTP: TVHTTP, @unchecked Sendable {
    private let lock = NSLock()
    var routes: [String: TVHTTPResponse] = [:]
    var handler: ((URL) -> TVHTTPResponse?)?
    private(set) var requested: [String] = []

    func set(_ url: String, _ status: Int, _ body: String) {
        lock.withLock { routes[url] = TVHTTPResponse(status: status, body: Data(body.utf8)) }
    }

    func get(_ url: URL, timeout: TimeInterval) async throws -> TVHTTPResponse {
        let (r, h): (TVHTTPResponse?, ((URL) -> TVHTTPResponse?)?) = lock.withLock {
            requested.append(url.absoluteString)
            return (routes[url.absoluteString], handler)
        }
        if let r { return r }
        if let x = h?(url) { return x }
        throw URLError(.cannotConnectToHost)
    }
}

final class FakePorts: TVPortProbe, @unchecked Sendable {
    private let lock = NSLock()
    var open: Set<String> = []
    func set(_ host: String, _ port: UInt16, _ isOpen: Bool) {
        lock.withLock { if isOpen { open.insert("\(host):\(port)") } else { open.remove("\(host):\(port)") } }
    }
    func isOpen(host: String, port: UInt16, timeout: TimeInterval) async -> Bool {
        lock.withLock { open.contains("\(host):\(port)") }
    }
}

final class FakeSSDP: SSDPTransport, @unchecked Sendable {
    var reply: (String, [SSDPTarget]) -> [SSDPResponse] = { _, _ in [] }
    private(set) var requests: [(String, [SSDPTarget])] = []
    func search(_ request: String, targets: [SSDPTarget], sendCount: Int, duration: TimeInterval) async -> [SSDPResponse] {
        requests.append((request, targets))
        return reply(request, targets)
    }
}

final class FakeNetwork: NetworkInterfaceListing, @unchecked Sendable {
    var list: [NetworkInterface]
    var source: String?
    init(_ list: [NetworkInterface] = [NetworkInterface(name: "en0", address: "192.168.0.10")], source: String? = nil) {
        self.list = list
        self.source = source
    }
    func interfaces() -> [NetworkInterface] { list }
    func sourceAddress(toward host: String, port: UInt16) -> String? { source }
}

/// Senaryolu WebSocket: gönderileni kaydeder, `script` gelen iletiye cevap üretir.
final class FakeSocket: TVWebSocket, @unchecked Sendable {
    let url: URL
    private let lock = NSLock()
    private(set) var sent: [String] = []
    private(set) var closed = false
    private let stream: AsyncStream<String>
    private let continuation: AsyncStream<String>.Continuation
    private var iterator: AsyncStream<String>.AsyncIterator
    var onSend: ((String, FakeSocket) -> Void)?

    init(url: URL, initial: [String] = []) {
        self.url = url
        (stream, continuation) = AsyncStream<String>.makeStream()
        iterator = stream.makeAsyncIterator()
        for m in initial { continuation.yield(m) }
    }

    func push(_ text: String) { continuation.yield(text) }

    func send(_ text: String) async throws {
        let handler: ((String, FakeSocket) -> Void)? = lock.withLock {
            sent.append(text)
            return onSend
        }
        handler?(text, self)
    }

    func receive() async throws -> String {
        var it = lock.withLock { iterator }
        guard let next = await it.next() else { throw URLError(.networkConnectionLost) }
        lock.withLock { iterator = it }
        return next
    }

    func close() {
        lock.withLock { closed = true }
        continuation.finish()
    }

    var sentObjects: [[String: Any]] {
        lock.withLock { sent }.compactMap { (try? JSONSerialization.jsonObject(with: Data($0.utf8))) as? [String: Any] }
    }
}

final class FakeSockets: TVWebSocketConnecting, @unchecked Sendable {
    private let lock = NSLock()
    /// URL → soket kurucusu; yoksa bağlantı hatası.
    var factory: (URL) -> FakeSocket? = { _ in nil }
    private(set) var opened: [FakeSocket] = []
    private(set) var attempted: [URL] = []

    func connect(url: URL, trustedHost: String, timeout: TimeInterval) async throws -> TVWebSocket {
        lock.withLock { attempted.append(url) }
        guard let s = factory(url) else { throw URLError(.cannotConnectToHost) }
        lock.withLock { opened.append(s) }
        return s
    }
}

final class FakeRunning: TVRunningProcess, @unchecked Sendable {
    let lines: AsyncStream<String>
    let exitCode: Int32?
    let stderr: String
    private(set) var inputClosed = false
    private(set) var terminated = false

    init(lines: [String], exitCode: Int32? = 0, stderr: String = "") {
        let (s, c) = AsyncStream<String>.makeStream()
        for l in lines { c.yield(l) }
        c.finish()
        self.lines = s
        self.exitCode = exitCode
        self.stderr = stderr
    }

    func errorTail() -> String { stderr }
    func closeInput() { inputClosed = true }
    func terminate() { terminated = true }
    func waitForExit(timeout: TimeInterval) async -> Int32? { exitCode }
}

final class FakeProcesses: TVProcessRunning, @unchecked Sendable {
    private let lock = NSLock()
    struct Call { var executable: String; var arguments: [String]; var input: Data? }
    private(set) var calls: [Call] = []
    var runHandler: (Call) -> TVProcessResult = { _ in TVProcessResult(exitCode: 0) }
    var startHandler: ([String]) -> FakeRunning = { _ in FakeRunning(lines: []) }

    func run(_ executable: URL, arguments: [String], input: Data?, timeout: TimeInterval) async throws -> TVProcessResult {
        let c = Call(executable: executable.lastPathComponent, arguments: arguments, input: input)
        let h = lock.withLock { calls.append(c); return runHandler }
        return h(c)
    }

    func start(_ executable: URL, arguments: [String]) throws -> TVRunningProcess {
        let h = lock.withLock {
            calls.append(Call(executable: executable.lastPathComponent, arguments: arguments, input: nil))
            return startHandler
        }
        return h(arguments)
    }

    var allCalls: [Call] { lock.withLock { calls } }
}

/// Uykusu anında biten, her uykuda zamanı ilerleten saat.
final class FastClock: TVClock, @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_800_000_000)
    func now() -> Date { lock.withLock { current } }
    func sleep(_ seconds: TimeInterval) async throws {
        lock.withLock { current = current.addingTimeInterval(seconds) }
        try Task.checkCancellation()
        await Task.yield()
    }
}

final class LogSink: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []
    lazy var log = TVInstallLog(path: "/tmp/tvinstall.log") { [weak self] l in self?.append(l) }
    func append(_ l: String) { lock.withLock { lines.append(l) } }
    var all: [String] { lock.withLock { lines } }
}

/// Kayıt tutan sahte çıkış.
actor FakeDisplayOutput: DisplayOutput {
    private(set) var shown: [ShowPayload] = []
    private(set) var events: [NinoEvent] = []
    func show(_ payload: ShowPayload) async throws { shown.append(payload) }
    func clear(id: Int?) async throws {}
    func send(_ event: NinoEvent) async throws { events.append(event) }
}

final class FakeServer: TVSubtitleServer, @unchecked Sendable {
    private let lock = NSLock()
    let display = FakeDisplayOutput()
    var connected: [String?] = []
    private(set) var started = 0
    var output: any DisplayOutput { display }
    func ensureRunning() async throws { lock.withLock { started += 1 } }
    func port() async -> UInt16 { 8787 }
    func connectedTVApps() async -> [String?] { lock.withLock { connected } }
    func lastSubtitleBox() async -> NinoBox? { nil }
}

/// Sahte kapıların toplu kurulumu.
struct TVFakes {
    let http = FakeHTTP()
    let ports = FakePorts()
    let ssdp = FakeSSDP()
    let sockets = FakeSockets()
    let network = FakeNetwork()
    let processes = FakeProcesses()
    let clock = FastClock()
    let logSink = LogSink()
    let vault = MemoryVault()
    let server = FakeServer()
    let folder: DataFolder
    let defaults: UserDefaults
    let packagesDir: URL
    var opened: [URL] = []

    init() {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("nino-tvtests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        folder = DataFolder(support: tmp.appendingPathComponent("support"), logs: tmp.appendingPathComponent("logs"))
        packagesDir = tmp.appendingPathComponent("tv-app")
        try? FileManager.default.createDirectory(at: packagesDir, withIntermediateDirectories: true)
        for name in ["com.ninotranslator.tv_0.7.0_all.ipk", "nino-tizen_0.7.0.wgt", "nino-androidtv_0.7.0.apk"] {
            FileManager.default.createFile(atPath: packagesDir.appendingPathComponent(name).path, contents: Data("pkg".utf8))
        }
        suiteName = "nino.tests.tv.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    let suiteName: String

    /// Geçici suite'i ve klasörü siler.
    func cleanUp() {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: packagesDir.deletingLastPathComponent())
    }

    var records: SecureRecords { SecureRecords(vault: vault) }

    func environment(helper: Bool = true, timing: TVSetupEnvironment.Timing = TVFakes.fastTiming) -> TVSetupEnvironment {
        TVSetupEnvironment(http: http, ports: ports, ssdp: ssdp, sockets: sockets, network: network, processes: processes,
                           clock: clock, log: logSink.log, records: records,
                           packages: TVAppPackages.scan(folder: packagesDir),
                           helperExecutable: helper ? URL(fileURLWithPath: "/fake/nino-tv-helper") : nil,
                           folder: folder, server: server, defaults: defaults, appStoreBuild: false,
                           openURL: { _ in true }, timing: timing)
    }

    static var fastTiming: TVSetupEnvironment.Timing {
        var t = TVSetupEnvironment.Timing()
        t.lg.approval = 0.3
        t.lg.firstMessage = 0.3
        t.lg.request = 0.3
        t.samsung.approval = 0.3
        t.samsung.connect = 0.3
        t.lgDeveloper.verifyAfterInstalled = 4
        t.lgDeveloper.verifyWithoutResult = 4
        return t
    }
}

/// Koşul tutana kadar ana kuyrukta bekler.
@MainActor
func waitUntil(_ timeout: TimeInterval = 3, _ condition: @MainActor () -> Bool) async {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition(), Date() < deadline { try? await Task.sleep(nanoseconds: 10_000_000) }
}

final class TVSetupFakesTests: XCTestCase {
    func testFakeSocketDeliversPushedMessages() async throws {
        let s = FakeSocket(url: URL(string: "ws://x")!, initial: ["a"])
        s.push("b")
        let a = try await s.receive()
        let b = try await s.receive()
        XCTAssertEqual([a, b], ["a", "b"])
        s.close()
        do { _ = try await s.receive(); XCTFail() } catch {}
    }
}
