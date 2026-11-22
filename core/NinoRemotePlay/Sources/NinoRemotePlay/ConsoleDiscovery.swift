// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import CRemotePlay
import Darwin
import Foundation

/// Yerel ağda bulunan bir konsol.
public struct ConsoleInfo: Equatable, Hashable, Sendable {
    public enum State: String, Sendable { case ready, standby, unknown }

    /// Keşifteki "host-id": PS5'in MAC adresi, 12 onaltılık hane. Elle girilen adreste boş olabilir.
    public let hostID: String
    public let name: String
    public let address: String
    public let state: State
    public let isPS5: Bool
    public let systemVersion: String
    /// Kayıt için gereken sürüm hedefi (kütüphanenin iç değeri).
    public let target: Int32
    public let runningAppName: String?
    public let runningAppTitleID: String?
    /// "PS5" ya da "PS4" (keşif cevabındaki host-type).
    public let hostType: String?
    /// Konsolun istek kapısı (genelde 997).
    public let requestPort: UInt16?

    public init(hostID: String = "", name: String = "", address: String, state: State = .unknown,
                isPS5: Bool = true, systemVersion: String = "", target: Int32? = nil,
                runningAppName: String? = nil, runningAppTitleID: String? = nil,
                hostType: String? = nil, requestPort: UInt16? = nil) {
        self.hostID = hostID
        self.name = name
        self.address = address
        self.state = state
        self.isPS5 = isPS5
        self.systemVersion = systemVersion
        self.target = target ?? ConsoleInfo.defaultTarget(isPS5: isPS5)
        self.runningAppName = runningAppName
        self.runningAppTitleID = runningAppTitleID
        self.hostType = hostType
        self.requestPort = requestPort
    }

    /// Keşif cevabı yokken (elle IP) kullanılacak güncel sürüm hedefi.
    public static func defaultTarget(isPS5: Bool) -> Int32 {
        Int32(bitPattern: (isPS5 ? CHIAKI_TARGET_PS5_1 : CHIAKI_TARGET_PS4_10).rawValue)
    }

    /// `hostID` 12 onaltılık haneyse MAC adresi (6 bayt).
    public var macAddress: [UInt8]? {
        let hex = Array(hostID.utf8)
        guard hex.count == 12 else { return nil }
        var out: [UInt8] = []
        for i in stride(from: 0, to: 12, by: 2) {
            guard let b = UInt8(String(decoding: hex[i..<i + 2], as: UTF8.self), radix: 16) else { return nil }
            out.append(b)
        }
        return out
    }
}

/// Ağda PS5 arar. Sonuçlar her değişiklikte akışa düşer.
public final class ConsoleDiscovery: @unchecked Sendable {
    private let log = RemotePlayLog()
    private let lock = NSLock()
    private var service: UnsafeMutablePointer<ChiakiDiscoveryService>?
    private var continuation: AsyncStream<[ConsoleInfo]>.Continuation?

    public init() {
        RemotePlayLib.initialize()
    }

    deinit { stop() }

    /// Aramayı başlatır. Akış bitince ya da `stop()` çağrılınca arama durur.
    /// - Parameter host: Verilirse yalnız bu adrese sorulur (unicast; ör. "192.168.0.20").
    ///   Yayın (broadcast) geçmeyen ağlarda ya da elle girilen IP'yi doğrulamak için.
    public func consoles(pingInterval: TimeInterval = 0.5, host: String? = nil) throws -> AsyncStream<[ConsoleInfo]> {
        stop()
        let (stream, continuation) = AsyncStream<[ConsoleInfo]>.makeStream(bufferingPolicy: .bufferingNewest(1))
        lock.withLock { self.continuation = continuation }

        let target = host?.trimmingCharacters(in: .whitespaces)
        if let target, target.isEmpty || target.contains(":") {
            continuation.finish()
            throw RemotePlayError.badInput("adres IPv4 ya da ad olmalı")
        }
        var send = sockaddr_in()
        send.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        send.sin_family = sa_family_t(AF_INET)
        // Unicast'te adres kütüphane içinde `send_host`tan çözülür.
        send.sin_addr.s_addr = target == nil ? 0xffffffff : 0
        var sendStorage = sockaddr_storage()
        withUnsafeMutableBytes(of: &sendStorage) { dst in
            withUnsafeBytes(of: send) { dst.copyMemory(from: $0) }
        }
        var broadcasts = target == nil ? Self.broadcastAddresses() : []
        let hostCString = target.map { strdup($0) } ?? nil
        defer { free(hostCString) }

        let svc = UnsafeMutablePointer<ChiakiDiscoveryService>.allocate(capacity: 1)
        var options = ChiakiDiscoveryServiceOptions()
        options.hosts_max = 16
        options.host_drop_pings = 3
        options.ping_ms = UInt64(pingInterval * 1000)
        options.ping_initial_ms = UInt64(pingInterval * 1000)
        options.send_host = hostCString
        options.cb = { hosts, count, user in
            guard let user else { return }
            let me = Unmanaged<ConsoleDiscovery>.fromOpaque(user).takeUnretainedValue()
            var list: [ConsoleInfo] = []
            for i in 0..<count {
                guard let h = hosts?[i] else { continue }
                list.append(ConsoleDiscovery.convert(h))
            }
            let c = me.lock.withLock { me.continuation }
            c?.yield(list.sorted { $0.name < $1.name })
        }
        options.cb_user = Unmanaged.passUnretained(self).toOpaque()

        let err: ChiakiErrorCode = withUnsafeMutablePointer(to: &sendStorage) { sendPtr in
            broadcasts.withUnsafeMutableBufferPointer { bc in
                options.send_addr = sendPtr
                options.send_addr_size = MemoryLayout<sockaddr_in>.size
                options.broadcast_addrs = bc.count > 0 ? bc.baseAddress : nil
                options.broadcast_num = bc.count
                // Seçenekler kütüphane içinde kopyalanır.
                return chiaki_discovery_service_init(svc, &options, log.pointer)
            }
        }
        guard err == CHIAKI_ERR_SUCCESS else {
            svc.deallocate()
            continuation.finish()
            throw RemotePlayError.library(RemotePlayLib.message(err))
        }
        lock.withLock { service = svc }
        continuation.onTermination = { [weak self] _ in self?.stop() }
        return stream
    }

    /// Tek bir adrese sorar; cevap gelirse konsolu, gelmezse `nil` döner.
    public func probe(host: String, timeout: TimeInterval = 3) async throws -> ConsoleInfo? {
        let stream = try consoles(pingInterval: 0.5, host: host)
        let found: ConsoleInfo? = await withTaskGroup(of: ConsoleInfo?.self) { group in
            group.addTask {
                for await list in stream { if let c = list.first { return c } }
                return nil
            }
            group.addTask { try? await Task.sleep(for: .seconds(timeout)); return nil }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        stop()
        return found
    }

    public func stop() {
        let (s, c) = lock.withLock { () -> (UnsafeMutablePointer<ChiakiDiscoveryService>?, AsyncStream<[ConsoleInfo]>.Continuation?) in
            defer { service = nil; continuation = nil }
            return (service, continuation)
        }
        if let s {
            chiaki_discovery_service_fini(s)
            s.deallocate()
        }
        c?.finish()
    }

    static func convert(_ h: ChiakiDiscoveryHost) -> ConsoleInfo {
        func s(_ p: UnsafePointer<CChar>?) -> String { p.map { String(cString: $0) } ?? "" }
        var host = h
        let state: ConsoleInfo.State
        switch h.state {
        case CHIAKI_DISCOVERY_HOST_STATE_READY: state = .ready
        case CHIAKI_DISCOVERY_HOST_STATE_STANDBY: state = .standby
        default: state = .unknown
        }
        func opt(_ p: UnsafePointer<CChar>?) -> String? { let v = s(p); return v.isEmpty ? nil : v }
        return ConsoleInfo(hostID: s(h.host_id), name: s(h.host_name), address: s(h.host_addr), state: state,
                           isPS5: chiaki_discovery_host_is_ps5(&host),
                           systemVersion: s(h.system_version),
                           target: Int32(bitPattern: chiaki_discovery_host_system_version_target(&host).rawValue),
                           runningAppName: opt(h.running_app_name), runningAppTitleID: opt(h.running_app_titleid),
                           hostType: opt(h.host_type), requestPort: h.host_request_port == 0 ? nil : h.host_request_port)
    }

    /// Bu cihazın IPv4 ağlarının yayın adresleri (ör. 192.168.1.255).
    static func broadcastAddresses() -> [sockaddr_storage] {
        var result: [sockaddr_storage] = []
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0, let first = ifap else { return [] }
        defer { freeifaddrs(ifap) }
        for p in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let i = p.pointee
            guard let addr = i.ifa_addr, addr.pointee.sa_family == sa_family_t(AF_INET),
                  (i.ifa_flags & UInt32(IFF_BROADCAST)) != 0, (i.ifa_flags & UInt32(IFF_LOOPBACK)) == 0,
                  let bc = i.ifa_dstaddr else { continue }
            var storage = sockaddr_storage()
            withUnsafeMutableBytes(of: &storage) { dst in
                dst.copyMemory(from: UnsafeRawBufferPointer(start: bc, count: MemoryLayout<sockaddr_in>.size))
            }
            result.append(storage)
        }
        return result
    }
}
