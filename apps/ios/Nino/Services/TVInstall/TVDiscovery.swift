// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// Kurulum ekranının ağ işleri: bu telefonun ev ağındaki adresi ve ağın /24 bölümünde açık portlar.
enum TVDiscovery {
    /// Telefonun TV'nin göreceği IPv4 adresi: TV'ye giden yolun kaynak adresi; yoksa Wi-Fi (en*) adresi.
    static func phoneAddress(towards host: String?) -> String? {
        if let host, let source = routeSource(to: host) { return source }
        let all = interfaces()
        return (all.first { $0.name.hasPrefix("en") && isPrivate($0.address) } ?? all.first { isPrivate($0.address) })?.address
    }

    private struct Interface { let name: String; let address: String }

    private static func interfaces() -> [Interface] {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return [] }
        defer { freeifaddrs(list) }
        var out: [Interface] = []
        for p in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let e = p.pointee
            let flags = Int32(e.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0, flags & IFF_POINTOPOINT == 0,
                  let addr = e.ifa_addr, addr.pointee.sa_family == sa_family_t(AF_INET) else { continue }
            let name = String(cString: e.ifa_name)
            guard !["utun", "ipsec", "ppp", "pdp_ip", "awdl", "llw", "bridge"].contains(where: name.hasPrefix) else { continue }
            let ip = addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { String(cString: inet_ntoa($0.pointee.sin_addr)) }
            out.append(Interface(name: name, address: ip))
        }
        return out
    }

    static func isPrivate(_ ip: String) -> Bool {
        let p = ip.split(separator: ".").compactMap { Int($0) }
        guard p.count == 4 else { return false }
        return p[0] == 10 || (p[0] == 172 && (16...31).contains(p[1])) || (p[0] == 192 && p[1] == 168)
    }

    /// TV'ye giden UDP "bağlantısının" yerel adresi (paket gönderilmez).
    private static func routeSource(to host: String) -> String? {
        let target = inet_addr(host)
        guard target != INADDR_NONE else { return nil }
        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var remote = sockaddr_in()
        remote.sin_family = sa_family_t(AF_INET)
        remote.sin_port = in_port_t(9).bigEndian
        remote.sin_addr.s_addr = target
        let ok = withUnsafePointer(to: &remote) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard ok == 0 else { return nil }
        var local = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &local) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &len) }
        }
        guard named == 0, local.sin_addr.s_addr != 0 else { return nil }
        let ip = String(cString: inet_ntoa(local.sin_addr))
        return ip.hasPrefix("127.") ? nil : ip
    }

    /// Telefonun /24 ağında `port`u açık adresler (en çok 32 paralel deneme).
    static func scan(port: UInt16, near host: String?) async -> [String] {
        guard let phone = phoneAddress(towards: host), let dot = phone.lastIndex(of: ".") else { return [] }
        let prefix = phone[..<dot]
        let targets = (1...254).map { "\(prefix).\($0)" }.filter { $0 != phone }
        return await withTaskGroup(of: String?.self) { group in
            var found: [String] = []
            var next = 0
            func enqueue() {
                guard next < targets.count else { return }
                let t = targets[next]
                next += 1
                group.addTask { TCPChannel.isOpen(host: t, port: port, timeout: 0.7) ? t : nil }
            }
            for _ in 0..<32 { enqueue() }
            while let r = await group.next() {
                if let r { found.append(r) }
                enqueue()
            }
            return found.sorted { (Int($0.split(separator: ".").last ?? "") ?? 0) < (Int($1.split(separator: ".").last ?? "") ?? 0) }
        }
    }

    static func isOpen(_ host: String, _ port: UInt16, timeout: TimeInterval = 1.2) async -> Bool {
        await Task.detached { TCPChannel.isOpen(host: host, port: port, timeout: timeout) }.value
    }
}
