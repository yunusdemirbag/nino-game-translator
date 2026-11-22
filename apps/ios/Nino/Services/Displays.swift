// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation
import NinoCore

/// TV uygulamalarını bulma ve bağlanma (Nino Bağlantı Protokolü; telefon bağlanır, TV dinler).
enum Displays {
    struct Found: Equatable, Hashable, Identifiable {
        let name: String
        let host: String
        let port: UInt16
        let id: String?
        var brand: PairedTV.Brand

        var tv: PairedTV { PairedTV(name: name, host: host, brand: brand) }
    }

    /// Adından markayı tahmin eder (TV uygulaması markasını bildirmiyor).
    static func guessBrand(_ name: String) -> PairedTV.Brand {
        let lower = name.lowercased()
        if lower.contains("samsung") { return .samsung }
        if lower.contains("lg") || lower.contains("webos") { return .lg }
        return .androidTV
    }

    /// Ağdaki uyumlu TV uygulamalarını `seconds` sn arar ve adreslerini çözer.
    static func discover(seconds: Double = 3) async -> [Found] {
        let browser = NinoBrowser()
        defer { browser.stop() }
        let box = LatestBox<[DiscoveredDisplay]>()
        let task = Task { for await list in browser.displays() { box.set(list) } }
        try? await Task.sleep(for: .milliseconds(Int(seconds * 1000)))
        task.cancel()
        var result: [Found] = []
        for d in (box.get() ?? []) where d.isCompatible {
            guard let r = try? await NinoBrowser.resolve(d.endpoint, timeout: 3) else { continue }
            result.append(Found(name: d.name, host: r.host, port: r.port, id: d.id, brand: guessBrand(d.name)))
        }
        return result
    }

    /// TV'ye bağlanır ve el sıkışır. Başarılıysa canlı tutma başlar.
    static func connect(host: String, port: UInt16 = NinoLink.defaultPort) async throws -> NinoSender {
        let sender = NinoSender(host: host, port: port, device: "iPhone",
                                client: "nino-ios/\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0")")
        _ = try await sender.connect()
        await sender.startKeepAlive()
        return sender
    }

    /// Adresteki TV uygulamasına ulaşılabiliyor mu (tek HTTP isteği).
    static func probe(host: String, port: UInt16 = NinoLink.defaultPort) async -> Bool {
        (try? await NinoHTTPClient.info(host: host, port: port)) != nil
    }

    /// Elle yazılan adresi temizler; geçersizse nil.
    static func cleanAddress(_ text: String) -> String? {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        if let r = s.range(of: "://") { s = String(s[r.upperBound...]) }
        if let i = s.firstIndex(where: { "/?#".contains($0) }) { s = String(s[..<i]) }
        let colons = s.filter { $0 == ":" }.count
        if colons > 1 { return nil }
        if colons == 1 {
            let parts = s.split(separator: ":", omittingEmptySubsequences: false)
            guard parts[1].allSatisfy(\.isASCII), !parts[1].isEmpty, parts[1].allSatisfy(\.isNumber) else { return nil }
            s = String(parts[0])
        }
        while s.hasSuffix(".") { s.removeLast() }
        guard !s.isEmpty else { return nil }
        if s.allSatisfy({ $0 == "." || ($0.isASCII && $0.isNumber) }) {
            let parts = s.split(separator: ".", omittingEmptySubsequences: false)
            guard parts.count == 4 else { return nil }
            var out: [String] = []
            for p in parts {
                guard (1...3).contains(p.count), let v = Int(p), v <= 255 else { return nil }
                out.append(String(v))
            }
            return out.joined(separator: ".")
        }
        guard s.count <= 253, s.contains(where: { $0.isLetter }) else { return nil }
        for label in s.split(separator: ".", omittingEmptySubsequences: false) {
            guard (1...63).contains(label.count),
                  label.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }),
                  label.first != "-", label.last != "-" else { return nil }
        }
        return s.lowercased()
    }
}
