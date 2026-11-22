// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation
import Network
import Security

// TV kurulumunun bağlantıları. Kurulum kodu sıralı ve bloklayan biçimde yazıldı (adımlar birbirini bekler); hep arka
// plan iş parçacığında çalışır. Düz TCP için BSD soketi, TLS 1.3 için Network.framework kullanılır.

enum WireError: Error, CustomStringConvertible, Equatable {
    case closed
    case timeout
    case connect(String)
    case malformed(String)

    var description: String {
        switch self {
        case .closed: "connection closed by the TV"
        case .timeout: "timed out"
        case .connect(let why): "connect failed: \(why)"
        case .malformed(let why): "unexpected data: \(why)"
        }
    }
}

/// Bloklayan bayt akışı.
protocol ByteChannel: AnyObject {
    /// En az bir bayt döner; akış kapandıysa `WireError.closed`.
    func receive(upTo max: Int) throws -> Bytes
    func send(_ bytes: Bytes) throws
    func shutdown()
    var receiveTimeout: TimeInterval { get set }
}

/// Bir akışın üstünde "tam n bayt oku" ve geri bırakma.
final class ChannelReader {
    let channel: ByteChannel
    private var buffered = Bytes()
    private var start = 0

    init(_ channel: ByteChannel, prefetched: Bytes = []) {
        self.channel = channel
        buffered = prefetched
    }

    var available: Int { buffered.count - start }

    func read(exactly count: Int) throws -> Bytes {
        while available < count {
            compact()
            buffered += try channel.receive(upTo: Swift.max(32_768, count - available))
        }
        let out = Array(buffered[start..<start + count])
        start += count
        return out
    }

    /// Okunmuş ama kullanılmamış baytları alır (akış başka bir katmana devredilirken).
    func drain() -> Bytes {
        let rest = Array(buffered[start...])
        buffered = []
        start = 0
        return rest
    }

    private func compact() {
        if start > 0 {
            buffered.removeFirst(start)
            start = 0
        }
    }
}

/// Bloklayan TCP bağlantısı.
final class TCPChannel: ByteChannel {
    private var fd: Int32
    private let lock = NSLock()
    var receiveTimeout: TimeInterval = 60 { didSet { setTimeout(SO_RCVTIMEO, receiveTimeout) } }

    init(host: String, port: UInt16, timeout: TimeInterval = 8) throws {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        hints.ai_protocol = IPPROTO_TCP
        var info: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, String(port), &hints, &info) == 0, let first = info else {
            throw WireError.connect("\(host): address not resolved")
        }
        defer { freeaddrinfo(info) }
        var lastError = "no address"
        var opened: Int32 = -1
        for entry in sequence(first: first, next: { $0.pointee.ai_next }) {
            let s = socket(entry.pointee.ai_family, entry.pointee.ai_socktype, entry.pointee.ai_protocol)
            guard s >= 0 else { continue }
            if Self.connect(s, entry.pointee.ai_addr, entry.pointee.ai_addrlen, timeout: timeout) {
                opened = s
                break
            }
            lastError = String(cString: strerror(errno))
            Darwin.close(s)
        }
        guard opened >= 0 else { throw WireError.connect("\(host):\(port): \(lastError)") }
        fd = opened
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &on, socklen_t(MemoryLayout<Int32>.size))
        setTimeout(SO_RCVTIMEO, receiveTimeout)
        setTimeout(SO_SNDTIMEO, 120)
    }

    /// Kabul edilmiş bir soket (testlerdeki sahte sunucular).
    init(acceptedDescriptor: Int32) {
        fd = acceptedDescriptor
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        setTimeout(SO_RCVTIMEO, receiveTimeout)
    }

    deinit { shutdown() }

    private static func connect(_ s: Int32, _ address: UnsafeMutablePointer<sockaddr>?, _ length: socklen_t,
                                timeout: TimeInterval) -> Bool {
        let flags = fcntl(s, F_GETFL, 0)
        _ = fcntl(s, F_SETFL, flags | O_NONBLOCK)
        defer { _ = fcntl(s, F_SETFL, flags) }
        if Darwin.connect(s, address, length) == 0 { return true }
        guard errno == EINPROGRESS else { return false }
        var waiter = pollfd(fd: s, events: Int16(POLLOUT), revents: 0)
        let ready = poll(&waiter, 1, Int32(timeout * 1000))
        guard ready > 0 else {
            errno = ETIMEDOUT
            return false
        }
        var soError: Int32 = 0
        var size = socklen_t(MemoryLayout<Int32>.size)
        getsockopt(s, SOL_SOCKET, SO_ERROR, &soError, &size)
        if soError != 0 { errno = soError }
        return soError == 0
    }

    private func setTimeout(_ option: Int32, _ seconds: TimeInterval) -> Void {
        var value = timeval(tv_sec: Int(seconds), tv_usec: Int32((seconds - seconds.rounded(.down)) * 1_000_000))
        setsockopt(fd, SOL_SOCKET, option, &value, socklen_t(MemoryLayout<timeval>.size))
    }

    func receive(upTo max: Int) throws -> Bytes {
        var buffer = Bytes(repeating: 0, count: max)
        let n = buffer.withUnsafeMutableBytes { recv(fd, $0.baseAddress, max, 0) }
        if n > 0 { return Array(buffer[0..<n]) }
        if n == 0 { throw WireError.closed }
        if errno == EAGAIN || errno == EWOULDBLOCK { throw WireError.timeout }
        if errno == ECONNRESET || errno == EPIPE || errno == EBADF { throw WireError.closed }
        throw WireError.connect(String(cString: strerror(errno)))
    }

    func send(_ bytes: Bytes) throws {
        var offset = 0
        while offset < bytes.count {
            let n = bytes.withUnsafeBytes { Darwin.send(fd, $0.baseAddress! + offset, bytes.count - offset, 0) }
            if n <= 0 {
                if errno == EAGAIN || errno == EWOULDBLOCK { throw WireError.timeout }
                throw WireError.closed
            }
            offset += n
        }
    }

    func shutdown() {
        lock.lock()
        defer { lock.unlock() }
        guard fd >= 0 else { return }
        Darwin.shutdown(fd, SHUT_RDWR)
        Darwin.close(fd)
        fd = -1
    }

    /// Port kısa sürede bağlantı kabul ediyor mu?
    static func isOpen(host: String, port: UInt16, timeout: TimeInterval = 0.8) -> Bool {
        guard let c = try? TCPChannel(host: host, port: port, timeout: timeout) else { return false }
        c.shutdown()
        return true
    }
}

// MARK: - TLS

/// TLS 1.3 istemcisi. Sunucu sertifikası denetlenmez (adb de denetlemez: TV kendinden imzalıdır); istemci kendi
/// sertifikasını gösterir.
final class TLSChannel: ByteChannel {
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "nino.tvinstall.tls")
    var receiveTimeout: TimeInterval = 60

    init(host: String, port: UInt16, identity: SecIdentity?, timeout: TimeInterval = 12) throws {
        let tls = NWProtocolTLS.Options()
        let sec = tls.securityProtocolOptions
        sec_protocol_options_set_min_tls_protocol_version(sec, .TLSv13)
        sec_protocol_options_set_max_tls_protocol_version(sec, .TLSv13)
        if let identity {
            var cert: SecCertificate?
            SecIdentityCopyCertificate(identity, &cert)
            let local = cert.flatMap { sec_identity_create_with_certificates(identity, [$0] as CFArray) }
                ?? sec_identity_create(identity)
            if let local {
                sec_protocol_options_set_local_identity(sec, local)
                sec_protocol_options_set_challenge_block(sec, { _, reply in reply(local) }, queue)
            }
        }
        sec_protocol_options_set_verify_block(sec, { _, _, reply in reply(true) }, queue)
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { throw WireError.connect("bad port \(port)") }
        connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort,
                                  using: NWParameters(tls: tls, tcp: NWProtocolTCP.Options()))
        let ready = DispatchSemaphore(value: 0)
        let outcome = LockedValue<String?>(nil)
        let fired = LockedValue(false)
        connection.stateUpdateHandler = { state in
            let message: String??
            switch state {
            case .ready: message = .some(nil)
            case .failed(let e), .waiting(let e): message = .some("\(e)")
            case .cancelled: message = .some("cancelled")
            default: message = nil
            }
            guard let message, !fired.swap(true) else { return }
            outcome.set(message)
            ready.signal()
        }
        connection.start(queue: queue)
        if ready.wait(timeout: .now() + timeout) == .timedOut {
            connection.cancel()
            throw WireError.connect("TLS handshake timed out")
        }
        if let failure = outcome.get() {
            connection.cancel()
            throw WireError.connect("TLS: \(failure)")
        }
    }

    /// RFC 8446 7.5 dışa aktarıcı (bağlamsız).
    func exportKeyingMaterial(label: Bytes, length: Int) -> Bytes? {
        guard let meta = connection.metadata(definition: NWProtocolTLS.definition) as? NWProtocolTLS.Metadata else {
            return nil
        }
        let secret: __DispatchData? = label.withUnsafeBufferPointer { buf in
            buf.withMemoryRebound(to: CChar.self) {
                sec_protocol_metadata_create_secret(meta.securityProtocolMetadata, label.count, $0.baseAddress!, length)
            }
        }
        guard let secret else { return nil }
        return Bytes(secret as DispatchData)
    }

    func receive(upTo max: Int) throws -> Bytes {
        let done = DispatchSemaphore(value: 0)
        let result = LockedValue<Result<Bytes, Error>>(.failure(WireError.timeout))
        connection.receive(minimumIncompleteLength: 1, maximumLength: max) { data, _, complete, error in
            if let data, !data.isEmpty {
                result.set(.success(Bytes(data)))
            } else if let error {
                result.set(.failure(WireError.connect("\(error)")))
            } else if complete {
                result.set(.failure(WireError.closed))
            } else {
                result.set(.failure(WireError.closed))
            }
            done.signal()
        }
        if done.wait(timeout: .now() + receiveTimeout) == .timedOut { throw WireError.timeout }
        return try result.get().get()
    }

    func send(_ bytes: Bytes) throws {
        let done = DispatchSemaphore(value: 0)
        let failure = LockedValue<NWError?>(nil)
        connection.send(content: Data(bytes), completion: .contentProcessed { error in
            failure.set(error)
            done.signal()
        })
        if done.wait(timeout: .now() + 120) == .timedOut { throw WireError.timeout }
        if failure.get() != nil { throw WireError.closed }
    }

    func shutdown() { connection.cancel() }
}

/// Açık bir TCP bağlantısında TLS'e geçiş (adb'nin STLS'i): Network.framework var olan bir sokette TLS başlatamaz.
/// Bu yüzden 127.0.0.1'de tek bağlantılık bir dinleyici açılır; TLS oraya kurulur ve baytlar TV bağlantısına aynen
/// aktarılır.
final class LoopbackBridge {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "nino.tvinstall.bridge")
    private let upstream: ByteChannel
    private let local = LockedValue<NWConnection?>(nil)
    private(set) var port: UInt16 = 0

    init(upstream: ByteChannel, prefetched: Bytes) throws {
        self.upstream = upstream
        let params = NWParameters.tcp
        // Yalnız 127.0.0.1'e bağlanır. (acceptLocalOnly açılınca dinleyici geri döngüden gelen bağlantıyı da reddediyor.)
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: params)
        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready, .failed, .cancelled: ready.signal()
            default: break
            }
        }
        let queue = self.queue
        let local = self.local
        listener.newConnectionHandler = { [weak self] connection in
            guard let self, local.get() == nil else {
                connection.cancel()
                return
            }
            local.set(connection)
            connection.start(queue: queue)
            if !prefetched.isEmpty { connection.send(content: Data(prefetched), completion: .idempotent) }
            self.forwardFromTV(to: connection)
            self.forwardToTV(from: connection)
        }
        listener.start(queue: queue)
        _ = ready.wait(timeout: .now() + 5)
        guard let p = listener.port?.rawValue else {
            listener.cancel()
            throw WireError.connect("local bridge did not start")
        }
        port = p
    }

    private func forwardFromTV(to connection: NWConnection) {
        let upstream = self.upstream
        let thread = Thread {
            upstream.receiveTimeout = 900
            while true {
                let chunk: Bytes
                do { chunk = try upstream.receive(upTo: 65_536) } catch { break }
                let sent = DispatchSemaphore(value: 0)
                connection.send(content: Data(chunk), completion: .contentProcessed { _ in sent.signal() })
                sent.wait()
            }
            connection.cancel()
        }
        thread.name = "nino.tvinstall.bridge.down"
        thread.start()
    }

    private func forwardToTV(from connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, complete, error in
            guard let self else { return }
            if let data, !data.isEmpty, (try? self.upstream.send(Bytes(data))) != nil {
                self.forwardToTV(from: connection)
            } else if complete || error != nil || data == nil {
                self.upstream.shutdown()
            }
        }
    }

    func close() {
        listener.cancel()
        local.get()?.cancel()
        upstream.shutdown()
    }
}

/// Kilitli küçük değer kutusu (geri çağrılar ile bloklayan kod arasında).
final class LockedValue<T>: @unchecked Sendable {
    private var value: T
    private let lock = NSLock()
    init(_ value: T) { self.value = value }
    func get() -> T { lock.withLock { value } }
    func set(_ newValue: T) { lock.withLock { value = newValue } }
    /// Yeni değeri koyar, eskisini döner.
    func swap(_ newValue: T) -> T {
        lock.withLock {
            let old = value
            value = newValue
            return old
        }
    }
}
