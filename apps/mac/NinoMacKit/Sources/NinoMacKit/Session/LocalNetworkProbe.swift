// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Darwin
import Foundation

/// Yerel ağ izni tahmini (kurulum.md §6 "Yerel ağ izni tahmini", kaynaklar.md "Yerel ağ izni").
///
/// macOS izni doğrudan okutmaz. Doğrudan bağlı alt ağda en az 4 adrese PS5 arama paketi (UDP 9302) gönderilir; hiçbir
/// gönderim kabul edilmediyse, hepsi "No route to host" ya da "not permitted" ile düştüyse ve hiçbir PS5 yanıt
/// vermediyse izin kapalı sayılır. Tek hata satırı işaret değildir.
public enum LocalNetworkProbe {
    public enum Verdict: Equatable, Sendable { case blocked, allowed, unknown }

    /// En az bu kadar adres denenmiş olmalı.
    public static let minimumAttempts = 4
    public static let port: UInt16 = 9302
    static let packet = "SRCH * HTTP/1.1\ndevice-discovery-protocol-version:00030010\n"

    /// Gönderim sonuçlarından karar. `results`: her adres için `nil` (kabul edildi) ya da `errno`.
    public static func verdict(_ results: [Int32?], ps5Answered: Bool) -> Verdict {
        if ps5Answered || results.contains(where: { $0 == nil }) { return .allowed }
        guard results.count >= minimumAttempts else { return .unknown }
        let permission: Set<Int32> = [EHOSTUNREACH, EPERM, EACCES]
        return results.allSatisfy { $0.map(permission.contains) ?? false } ? .blocked : .unknown
    }

    /// Bu Mac'in doğrudan bağlı IPv4 alt ağında denenecek adresler (kendisi hariç, en çok `limit`).
    public static func candidates(address: UInt32, mask: UInt32, limit: Int = 8) -> [UInt32] {
        let network = address & mask
        let broadcast = network | ~mask
        guard broadcast > network + 1 else { return [] }
        var out: [UInt32] = []
        var host = network + 1
        while host < broadcast, out.count < limit {
            if host != address { out.append(host) }
            host += 1
        }
        return out
    }

    /// Gerçek deneme (ağa paket gider; testlerde çağrılmaz).
    public static func run() async -> Verdict {
        await Task.detached { probe() }.value
    }

    private static func probe() -> Verdict {
        guard let (address, mask) = localIPv4() else { return .unknown }
        let targets = candidates(address: address, mask: mask)
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return .unknown }
        defer { close(fd) }
        var results: [Int32?] = []
        let bytes = Array(packet.utf8)
        for host in targets {
            var sin = sockaddr_in()
            sin.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            sin.sin_family = sa_family_t(AF_INET)
            sin.sin_port = port.bigEndian
            sin.sin_addr = in_addr(s_addr: host.bigEndian)
            let sent = withUnsafePointer(to: &sin) { p in
                p.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(fd, bytes, bytes.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            results.append(sent >= 0 ? nil : errno)
        }
        // Yanıt: 1 sn içinde herhangi bir PS5 cevabı.
        var tv = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var buffer = [UInt8](repeating: 0, count: 2048)
        let n = recv(fd, &buffer, buffer.count, 0)
        let answered = n > 0 && String(decoding: buffer[0..<n], as: UTF8.self).contains("HTTP/1.1")
        return verdict(results, ps5Answered: answered)
    }

    /// Kablolu ya da kablosuz ilk IPv4 arayüzü (geri döngü ve bağlantı yerel adresleri hariç).
    private static func localIPv4() -> (UInt32, UInt32)? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return nil }
        defer { freeifaddrs(list) }
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let p = cursor {
            defer { cursor = p.pointee.ifa_next }
            let flags = Int32(p.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0, let a = p.pointee.ifa_addr, let m = p.pointee.ifa_netmask,
                  a.pointee.sa_family == sa_family_t(AF_INET) else { continue }
            let addr = a.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
            let mask = m.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
            if addr >> 16 == 0xA9FE { continue } // 169.254/16
            return (addr, mask)
        }
        return nil
    }
}
