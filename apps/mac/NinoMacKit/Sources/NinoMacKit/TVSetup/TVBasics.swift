// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// Ortak sabitler (tv-kurulumu.md, giriş).
public enum TVApp {
    /// LG ve Android paketi.
    public static let lgID = "com.ninotranslator.tv"
    public static let androidPackage = "com.ninotranslator.tv"
    public static let samsungID = "NinoTVApps.Nino"

    // Sahada eski kimlikli TV uygulaması da olabilir (kodlu adlar `LegacyNames`'te). Açma sırası: önce yeni kimlik,
    // kurulu değilse ya da açılamazsa eski. Samsung'da yeni paket eskisinin yanına kurulur; eskisi kaldırılmaz.
    static var legacyLGID: String { LegacyNames.tvPackage }
    static var legacyAndroidPackage: String { LegacyNames.tvPackage }
    static var legacySamsungID: String { LegacyNames.samsungTVAppID }
    /// Denenecek kimlikler, sırayla.
    static var lgIDs: [String] { [lgID, legacyLGID] }
    static var samsungIDs: [String] { [samsungID, legacySamsungID] }
    /// TV uygulamasına verilen `server` parametresi.
    public static func serverURL(macAddress: String?, port: UInt16) -> String {
        let host = (macAddress?.isEmpty == false) ? macAddress! : "127.0.0.1"
        return "http://\(host):\(port)"
    }
}

// MARK: Sürüm

/// Sayısal sürüm karşılaştırması: "0.10" > "0.9". Sayı olmayan parça 0 sayılır.
public struct TVVersion: Comparable, Equatable, Sendable, CustomStringConvertible {
    public let text: String
    public let parts: [Int]

    public init(_ text: String) {
        self.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        parts = self.text.split(whereSeparator: { $0 == "." || $0 == "-" || $0 == "+" }).map { part in
            Int(part.prefix(while: \.isNumber)) ?? 0
        }
    }

    public var description: String { text }

    public static func < (a: TVVersion, b: TVVersion) -> Bool {
        let n = max(a.parts.count, b.parts.count)
        for i in 0..<n {
            let x = i < a.parts.count ? a.parts[i] : 0
            let y = i < b.parts.count ? b.parts[i] : 0
            if x != y { return x < y }
        }
        return false
    }

    public static func == (a: TVVersion, b: TVVersion) -> Bool { !(a < b) && !(b < a) }

    /// `installed` en az `bundled` kadar yeni mi (yoksa ya da boşsa hayır).
    public static func isCurrent(_ installed: String?, bundled: String) -> Bool {
        guard let installed, !installed.isEmpty else { return false }
        return !(TVVersion(installed) < TVVersion(bundled))
    }
}

// MARK: Paketler

/// Mac uygulamasının içindeki `tv-app` klasöründeki TV uygulaması paketleri.
public struct TVAppPackage: Equatable, Sendable {
    public var url: URL
    public var version: String
    public var fileName: String { url.lastPathComponent }
}

public struct TVAppPackages: Equatable, Sendable {
    public var lg: TVAppPackage?
    public var samsung: TVAppPackage?
    public var android: TVAppPackage?

    public init(lg: TVAppPackage? = nil, samsung: TVAppPackage? = nil, android: TVAppPackage? = nil) {
        self.lg = lg
        self.samsung = samsung
        self.android = android
    }

    public func package(for brand: PairedTV.Brand) -> TVAppPackage? {
        switch brand {
        case .lg: return lg
        case .samsung: return samsung
        case .androidTV: return android
        }
    }

    /// "Nino kurabilir mi": paket uygulamayla geldiyse evet.
    public func canInstall(_ brand: PairedTV.Brand) -> Bool { package(for: brand) != nil }

    /// Klasördeki dosyalardan. Aynı türden birden çoksa en yeni sürüm.
    public static func scan(folder: URL?) -> TVAppPackages {
        guard let folder,
              let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return TVAppPackages() }
        var out = TVAppPackages()
        func pick(_ current: TVAppPackage?, _ new: TVAppPackage) -> TVAppPackage {
            guard let current else { return new }
            return TVVersion(new.version) > TVVersion(current.version) ? new : current
        }
        for name in names.sorted() {
            guard let version = version(fromFileName: name) else { continue }
            let p = TVAppPackage(url: folder.appendingPathComponent(name), version: version)
            switch (name as NSString).pathExtension.lowercased() {
            case "ipk": out.lg = pick(out.lg, p)
            case "wgt": out.samsung = pick(out.samsung, p)
            case "apk": out.android = pick(out.android, p)
            default: break
            }
        }
        return out
    }

    /// LG: `com.ninotranslator.tv_<sürüm>_all.ipk`; öbürleri son alt çizgiden sonraki parça.
    public static func version(fromFileName name: String) -> String? {
        let ext = (name as NSString).pathExtension.lowercased()
        let stem = (name as NSString).deletingPathExtension
        if ext == "ipk" {
            let prefix = TVApp.lgID + "_"
            guard stem.hasPrefix(prefix), stem.hasSuffix("_all") else { return nil }
            let v = String(stem.dropFirst(prefix.count).dropLast(4))
            return v.isEmpty ? nil : v
        }
        guard ext == "wgt" || ext == "apk", let underscore = stem.lastIndex(of: "_") else { return nil }
        let v = String(stem[stem.index(after: underscore)...])
        return v.isEmpty ? nil : v
    }
}

// MARK: IPv4

enum IPv4 {
    static func parse(_ s: String) -> UInt32? {
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var v: UInt32 = 0
        for p in parts {
            guard !p.isEmpty, p.count <= 3, p.allSatisfy(\.isNumber), let n = UInt32(p), n <= 255 else { return nil }
            v = v << 8 | n
        }
        return v
    }

    static func format(_ v: UInt32) -> String {
        "\(v >> 24 & 0xFF).\(v >> 16 & 0xFF).\(v >> 8 & 0xFF).\(v & 0xFF)"
    }

    /// 10.x, 172.16–31.x, 192.168.x.
    static func isPrivate(_ s: String) -> Bool {
        guard let v = parse(s) else { return false }
        let a = v >> 24, b = v >> 16 & 0xFF
        return a == 10 || (a == 172 && (16...31).contains(b)) || (a == 192 && b == 168)
    }

    static func sameSubnet(_ a: String, _ b: String, mask: String) -> Bool {
        guard let x = parse(a), let y = parse(b), let m = parse(mask) else { return false }
        return x & m == y & m
    }

    /// /24 bölümündeki adresler (1–254), `excluding` hariç.
    static func slash24(of address: String, excluding: Set<String> = []) -> [String] {
        guard let v = parse(address) else { return [] }
        let base = v & 0xFFFF_FF00
        return (1...254).map { format(base | UInt32($0)) }.filter { !excluding.contains($0) }
    }

    /// Adres sırası (sayısal); IPv4 olmayanlar sona, metin sırasıyla.
    static func ordered(_ a: String, _ b: String) -> Bool {
        switch (parse(a), parse(b)) {
        case let (x?, y?): return x < y
        case (.some, nil): return true
        case (nil, .some): return false
        default: return a < b
        }
    }
}

// MARK: Mac'in adresi (§1)

/// TV'ye verilen ve Samsung'da Host PC IP olarak yazılacak adres.
public enum MacAddressPicker {
    static let virtualPrefixes = ["utun", "ipsec", "ppp", "gif", "stf", "vmnet", "vboxnet", "bridge", "feth",
                                  "tap", "tun", "awdl", "llw", "anpi", "zt", "pdp_ip"]

    public static func isVirtual(_ i: NetworkInterface) -> Bool {
        i.isPointToPoint || virtualPrefixes.contains { i.name.hasPrefix($0) }
    }

    /// Kullanılabilir (açık, geri döngü olmayan, IPv4) bağdaştırıcılar.
    static func usable(_ list: [NetworkInterface]) -> [NetworkInterface] {
        list.filter { $0.isUp && !$0.isLoopback && IPv4.parse($0.address) != nil && !$0.address.hasPrefix("127.")
            && $0.address != "0.0.0.0" }
    }

    /// Kurallar: 1) TV'ye giden yolun kaynak adresi (açık bir bağdaştırıcının adresiyse);
    /// 2) TV ile aynı alt ağdaki gerçek bağdaştırıcı; 3) `en*` üzerindeki özel adres; 4) herhangi bir gerçek
    /// bağdaştırıcı; 5) sanal bağdaştırıcılar.
    public static func pick(tvHost: String?, interfaces: [NetworkInterface], routeSource: String?) -> String? {
        let list = usable(interfaces)
        if let s = routeSource, s != "0.0.0.0", !s.hasPrefix("127."), list.contains(where: { $0.address == s }) {
            return s
        }
        let real = list.filter { !isVirtual($0) }
        if let tvHost, IPv4.parse(tvHost) != nil,
           let same = real.first(where: { IPv4.sameSubnet($0.address, tvHost, mask: $0.netmask) }) {
            return same.address
        }
        if let en = real.first(where: { $0.name.hasPrefix("en") && IPv4.isPrivate($0.address) }) { return en.address }
        if let any = real.first { return any.address }
        return list.first?.address
    }

    public static func pick(tvHost: String?, network: NetworkInterfaceListing) -> String? {
        let source = (tvHost?.isEmpty == false) ? network.sourceAddress(toward: tvHost!, port: 8001) : nil
        return pick(tvHost: tvHost, interfaces: network.interfaces(), routeSource: source)
    }

    /// Ev ağı bağdaştırıcıları (gerçek, özel adresli): SSDP ve /24 taraması bunlardan yapılır.
    public static func homeNetworks(_ interfaces: [NetworkInterface]) -> [NetworkInterface] {
        var seen = Set<String>()
        return usable(interfaces).filter { !isVirtual($0) && IPv4.isPrivate($0.address) && seen.insert($0.address).inserted }
    }
}
