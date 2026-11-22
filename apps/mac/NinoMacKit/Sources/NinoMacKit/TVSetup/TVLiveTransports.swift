// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Darwin
import Foundation
import Network
import NinoCore

// TV kapılarının gerçek uygulamaları. Birim testleri bunları kullanmaz.

// MARK: HTTP

public struct URLSessionTVHTTP: TVHTTP {
    let session: URLSession

    public init() {
        let c = URLSessionConfiguration.ephemeral
        c.httpCookieStorage = nil
        c.httpShouldSetCookies = false
        c.urlCache = nil
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: c)
    }

    public func get(_ url: URL, timeout: TimeInterval) async throws -> TVHTTPResponse {
        var r = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        r.httpMethod = "GET"
        let (data, response) = try await session.data(for: r)
        return TVHTTPResponse(status: (response as? HTTPURLResponse)?.statusCode ?? 0, body: data)
    }
}

// MARK: TCP

public struct NWPortProbe: TVPortProbe {
    public init() {}

    public func isOpen(host: String, port: UInt16, timeout: TimeInterval) async -> Bool {
        guard let p = NWEndpoint.Port(rawValue: port) else { return false }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: p, using: .tcp)
        let once = TVOnce()
        return await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if once.claim() { connection.cancel(); cont.resume(returning: true) }
                case .failed, .cancelled, .waiting:
                    if once.claim() { connection.cancel(); cont.resume(returning: false) }
                default: break
                }
            }
            connection.start(queue: .global())
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if once.claim() { connection.cancel(); cont.resume(returning: false) }
            }
        }
    }
}

// MARK: SSDP (BSD soketleri)

public struct BSDSSDPTransport: SSDPTransport {
    public init() {}

    public func search(_ request: String, targets: [SSDPTarget], sendCount: Int, duration: TimeInterval) async -> [SSDPResponse] {
        await Task.detached(priority: .userInitiated) { Self.blockingSearch(request, targets: targets, sendCount: sendCount,
                                                                           duration: duration) }.value
    }

    static func blockingSearch(_ request: String, targets: [SSDPTarget], sendCount: Int, duration: TimeInterval) -> [SSDPResponse] {
        var sockets: [Int32] = []
        defer { sockets.forEach { close($0) } }
        let payload = Array(request.utf8)
        func makeSocket(bindTo local: String?) -> Int32? {
            let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
            guard fd >= 0 else { return nil }
            var yes: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
            var addr = sockaddr_in()
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            addr.sin_addr.s_addr = local.map { inet_addr($0) } ?? INADDR_ANY
            let ok = withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
            }
            guard ok == 0 else { close(fd); return nil }
            if let local {
                var iface = in_addr(s_addr: inet_addr(local))
                setsockopt(fd, IPPROTO_IP, IP_MULTICAST_IF, &iface, socklen_t(MemoryLayout<in_addr>.size))
            }
            var ttl: UInt8 = 2
            setsockopt(fd, IPPROTO_IP, IP_MULTICAST_TTL, &ttl, socklen_t(MemoryLayout<UInt8>.size))
            _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
            return fd
        }
        func send(_ fd: Int32, to host: String) {
            var dest = sockaddr_in()
            dest.sin_family = sa_family_t(AF_INET)
            dest.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            dest.sin_port = UInt16(1900).bigEndian
            dest.sin_addr.s_addr = inet_addr(host)
            _ = payload.withUnsafeBytes { buf in
                withUnsafePointer(to: &dest) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        sendto(fd, buf.baseAddress, buf.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
            }
        }

        var unicastSocket: Int32?
        for _ in 0..<max(1, sendCount) {
            for t in targets {
                switch t.kind {
                case let .multicast(local):
                    if let fd = makeSocket(bindTo: local) { sockets.append(fd); send(fd, to: "239.255.255.250") }
                case let .unicast(host):
                    if unicastSocket == nil, let fd = makeSocket(bindTo: nil) { unicastSocket = fd; sockets.append(fd) }
                    if let fd = unicastSocket { send(fd, to: host) }
                }
            }
        }

        var out: [SSDPResponse] = []
        let deadline = Date().addingTimeInterval(duration)
        var buffer = [UInt8](repeating: 0, count: 4096)
        while Date() < deadline, !sockets.isEmpty {
            var fds = sockets.map { pollfd(fd: $0, events: Int16(POLLIN), revents: 0) }
            let wait = Int32(max(1, deadline.timeIntervalSinceNow * 1000))
            guard poll(&fds, nfds_t(fds.count), min(wait, 200)) >= 0 else { break }
            for p in fds where p.revents & Int16(POLLIN) != 0 {
                var from = sockaddr_in()
                var len = socklen_t(MemoryLayout<sockaddr_in>.size)
                let n = withUnsafeMutablePointer(to: &from) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { recvfrom(p.fd, &buffer, buffer.count, 0, $0, &len) }
                }
                guard n > 0 else { continue }
                let sender = String(cString: inet_ntoa(from.sin_addr))
                out.append(SSDPResponse.parse(String(decoding: buffer[0..<n], as: UTF8.self), sender: sender))
            }
        }
        return out
    }
}

// MARK: Ağ bağdaştırıcıları

public struct SystemNetworkInterfaces: NetworkInterfaceListing {
    public init() {}

    public func interfaces() -> [NetworkInterface] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(head) }
        var out: [NetworkInterface] = []
        var p: UnsafeMutablePointer<ifaddrs>? = first
        while let i = p {
            defer { p = i.pointee.ifa_next }
            guard let sa = i.pointee.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET) else { continue }
            let flags = Int32(i.pointee.ifa_flags)
            func text(_ ptr: UnsafeMutablePointer<sockaddr>?) -> String {
                guard let ptr else { return "" }
                return ptr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { String(cString: inet_ntoa($0.pointee.sin_addr)) }
            }
            out.append(NetworkInterface(name: String(cString: i.pointee.ifa_name), address: text(sa),
                                        netmask: text(i.pointee.ifa_netmask),
                                        isUp: flags & IFF_UP != 0 && flags & IFF_RUNNING != 0,
                                        isLoopback: flags & IFF_LOOPBACK != 0,
                                        isPointToPoint: flags & IFF_POINTOPOINT != 0))
        }
        return out
    }

    public func sourceAddress(toward host: String, port: UInt16) -> String? {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var dest = sockaddr_in()
        dest.sin_family = sa_family_t(AF_INET)
        dest.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        dest.sin_port = port.bigEndian
        guard inet_pton(AF_INET, host, &dest.sin_addr) == 1 else { return nil }
        let ok = withUnsafePointer(to: &dest) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard ok == 0 else { return nil }
        var local = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let got = withUnsafeMutablePointer(to: &local) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &len) }
        }
        guard got == 0 else { return nil }
        let s = String(cString: inet_ntoa(local.sin_addr))
        return s == "0.0.0.0" ? nil : s
    }
}

// MARK: WebSocket

/// URLSession WebSocket'i: kendinden imzalı sertifika yalnız verilen adres için kabul edilir, çerez yok.
public struct URLSessionTVWebSockets: TVWebSocketConnecting {
    public init() {}

    public func connect(url: URL, trustedHost: String, timeout: TimeInterval) async throws -> TVWebSocket {
        let socket = URLSessionTVWebSocket(url: url, trustedHost: trustedHost, timeout: timeout)
        try await socket.open(timeout: timeout)
        return socket
    }
}

final class URLSessionTVWebSocket: NSObject, TVWebSocket, URLSessionWebSocketDelegate, @unchecked Sendable {
    private let trustedHost: String
    private var session: URLSession!
    private var task: URLSessionWebSocketTask!
    private let lock = NSLock()
    private var openContinuation: CheckedContinuation<Void, Error>?

    init(url: URL, trustedHost: String, timeout: TimeInterval) {
        self.trustedHost = trustedHost
        super.init()
        let c = URLSessionConfiguration.ephemeral
        c.httpCookieStorage = nil
        c.httpShouldSetCookies = false
        c.timeoutIntervalForRequest = max(timeout, 5)
        session = URLSession(configuration: c, delegate: self, delegateQueue: nil)
        task = session.webSocketTask(with: url)
        task.maximumMessageSize = 4 * 1024 * 1024
    }

    func open(timeout: TimeInterval) async throws {
        try await withTimeout(timeout) { [self] in
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
                lock.withLock { openContinuation = c }
                task.resume()
            }
        }
    }

    private func finishOpen(_ error: Error?) {
        let c: CheckedContinuation<Void, Error>? = lock.withLock {
            defer { openContinuation = nil }
            return openContinuation
        }
        if let error { c?.resume(throwing: error) } else { c?.resume() }
    }

    func send(_ text: String) async throws { try await task.send(.string(text)) }

    func receive() async throws -> String {
        try await withTaskCancellationHandler {
            while true {
                switch try await task.receive() {
                case let .string(s): return s
                case let .data(d): return String(decoding: d, as: UTF8.self)
                @unknown default: continue
                }
            }
        } onCancel: { [task] in
            task?.cancel(with: .goingAway, reason: nil)
        }
    }

    func close() {
        task.cancel(with: .goingAway, reason: nil)
        session.invalidateAndCancel()
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        finishOpen(nil)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        finishOpen(error ?? URLError(.networkConnectionLost))
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           challenge.protectionSpace.host == trustedHost, let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

// MARK: Süreç

public struct FoundationProcessRunner: TVProcessRunning {
    public init() {}

    public func run(_ executable: URL, arguments: [String], input: Data?, timeout: TimeInterval) async throws -> TVProcessResult {
        let p = Process()
        p.executableURL = executable
        p.arguments = arguments
        let out = Pipe(), err = Pipe(), inp = Pipe()
        p.standardOutput = out
        p.standardError = err
        p.standardInput = inp
        let outBuffer = LockedData(), errBuffer = LockedData()
        out.fileHandleForReading.readabilityHandler = { h in outBuffer.append(h.availableData) }
        err.fileHandleForReading.readabilityHandler = { h in errBuffer.append(h.availableData) }
        let exited = DispatchSemaphore(value: 0)
        p.terminationHandler = { _ in exited.signal() }
        try p.run()
        if let input {
            DispatchQueue.global().async {
                try? inp.fileHandleForWriting.write(contentsOf: input)
                try? inp.fileHandleForWriting.close()
            }
        } else {
            try? inp.fileHandleForWriting.close()
        }
        let timedOut = await Task.detached { exited.wait(timeout: .now() + timeout) == .timedOut }.value
        if timedOut {
            p.terminate()
            _ = await Task.detached { exited.wait(timeout: .now() + 2) }.value
        }
        out.fileHandleForReading.readabilityHandler = nil
        err.fileHandleForReading.readabilityHandler = nil
        outBuffer.append(out.fileHandleForReading.readDataToEndOfFile())
        errBuffer.append(err.fileHandleForReading.readDataToEndOfFile())
        return TVProcessResult(exitCode: p.isRunning ? -1 : p.terminationStatus, stdout: outBuffer.data,
                               stderr: errBuffer.data, timedOut: timedOut)
    }

    public func start(_ executable: URL, arguments: [String]) throws -> TVRunningProcess {
        try FoundationRunningProcess(executable: executable, arguments: arguments)
    }
}

final class LockedData: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()
    var limit: Int?
    func append(_ d: Data) {
        guard !d.isEmpty else { return }
        lock.withLock {
            buffer.append(d)
            if let limit, buffer.count > limit { buffer = buffer.suffix(limit) }
        }
    }
    var data: Data { lock.withLock { buffer } }
    func reset(_ d: Data) { lock.withLock { buffer = d } }
}

final class FoundationRunningProcess: TVRunningProcess, @unchecked Sendable {
    private let process = Process()
    private let input = Pipe()
    private let stderrBuffer = LockedData()
    private let exited = DispatchSemaphore(value: 0)
    let lines: AsyncStream<String>

    init(executable: URL, arguments: [String]) throws {
        process.executableURL = executable
        process.arguments = arguments
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = input
        stderrBuffer.limit = 16 * 1024
        let (stream, cont) = AsyncStream<String>.makeStream()
        lines = stream
        let pending = LockedData()
        out.fileHandleForReading.readabilityHandler = { h in
            let d = h.availableData
            if d.isEmpty {
                h.readabilityHandler = nil
                let rest = String(decoding: pending.data, as: UTF8.self)
                if !rest.isEmpty { cont.yield(rest) }
                cont.finish()
                return
            }
            pending.append(d)
            var text = String(decoding: pending.data, as: UTF8.self)
            guard let last = text.lastIndex(of: "\n") else { return }
            let complete = String(text[..<last])
            text = String(text[text.index(after: last)...])
            let leftover = Data(text.utf8)
            pending.reset(leftover)
            for line in complete.split(separator: "\n", omittingEmptySubsequences: true) { cont.yield(String(line)) }
        }
        let errBuffer = stderrBuffer
        err.fileHandleForReading.readabilityHandler = { h in
            let d = h.availableData
            if d.isEmpty { h.readabilityHandler = nil } else { errBuffer.append(d) }
        }
        let sem = exited
        process.terminationHandler = { _ in sem.signal() }
        try process.run()
    }

    func errorTail() -> String { String(decoding: stderrBuffer.data, as: UTF8.self) }
    func closeInput() { try? input.fileHandleForWriting.close() }
    func terminate() { if process.isRunning { process.terminate() } }

    func waitForExit(timeout: TimeInterval) async -> Int32? {
        let sem = exited
        let done = await Task.detached { sem.wait(timeout: .now() + timeout) == .success }.value
        if done { sem.signal() }
        return done ? process.terminationStatus : nil
    }
}

// MARK: Bonjour

/// Yeni Nino TV uygulamaları (`_nino._tcp`), göndericiler elenir.
public struct BonjourNinoDisplayFinder: NinoDisplayFinding {
    public init() {}

    public func find(timeout: TimeInterval) async -> [FoundNinoDisplay] {
        let browser = NinoBrowser()
        defer { browser.stop() }
        let stream = browser.displays()
        let collector = Task { () -> [DiscoveredDisplay] in
            var last: [DiscoveredDisplay] = []
            for await list in stream {
                last = list
                if Task.isCancelled { break }
            }
            return last
        }
        try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
        browser.stop()
        collector.cancel()
        let latest = await collector.value
        var out: [FoundNinoDisplay] = []
        for d in latest where d.isCompatible {
            guard let r = try? await NinoBrowser.resolve(d.endpoint, timeout: 3) else { continue }
            let info = try? await NinoInfo.fetch(host: r.host, port: r.port)
            if info?.isSender == true { continue }
            out.append(FoundNinoDisplay(name: d.name, id: d.id, host: r.host, port: r.port, appVersion: info?.appVersion))
        }
        return out
    }
}
