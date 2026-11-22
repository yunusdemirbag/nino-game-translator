// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// LG ve Samsung'u SSDP ile, sessiz kalırsa /24 taramasıyla bulur.
public struct TVDiscovery: Sendable {
    public struct Timing: Sendable {
        public var ssdpWindow: TimeInterval = 3
        public var ssdpSendCount = 2
        public var scanProbeTimeout: TimeInterval = 0.8
        public var scanSSDPWindow: TimeInterval = 2.5
        public var scanConcurrency = 64
        public var nameTimeout: TimeInterval = 2
        public init() {}
    }

    public static let lgSearchTarget = "urn:lge-com:service:webos-second-screen:1"
    public static let samsungSearchTarget = "urn:samsung.com:device:RemoteControlReceiver:1"

    let http: TVHTTP
    let ssdp: SSDPTransport
    let network: NetworkInterfaceListing
    let timing: Timing

    public init(http: TVHTTP, ssdp: SSDPTransport, network: NetworkInterfaceListing, timing: Timing = Timing()) {
        self.http = http
        self.ssdp = ssdp
        self.network = network
        self.timing = timing
    }

    public static func searchRequest(target: String) -> String {
        "M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: \"ssdp:discover\"\r\nMX: 2\r\nST: \(target)\r\n\r\n"
    }

    /// TV adımı: LG ve Samsung araması birlikte; sonuçlar birleşir, adres sırasıyla.
    public func searchAll() async -> [DiscoveredTV] {
        async let lg = search(.lg)
        async let samsung = search(.samsung)
        return Self.merge(await lg + samsung)
    }

    /// Tek marka (adres değişince yeniden bulma da bunu kullanır). Android TV için boş.
    public func search(_ brand: PairedTV.Brand) async -> [DiscoveredTV] {
        guard brand != .androidTV else { return [] }
        let homes = MacAddressPicker.homeNetworks(network.interfaces())
        let target = brand == .lg ? Self.lgSearchTarget : Self.samsungSearchTarget
        let targets = homes.map { SSDPTarget(.multicast(localAddress: $0.address)) }
        let responses = await ssdp.search(Self.searchRequest(target: target), targets: targets,
                                          sendCount: timing.ssdpSendCount, duration: timing.ssdpWindow)
        let hosts = Self.hosts(from: responses, target: target)
        if !hosts.isEmpty {
            var out: [DiscoveredTV] = []
            for h in hosts { out.append(DiscoveredTV(name: await name(brand, host: h), host: h, brand: brand)) }
            return Self.merge(out)
        }
        return await scan(brand, homes: homes)
    }

    /// Yanıtın `ST`/`NT`'si hedefse `LOCATION`'daki adres (yoksa gönderen).
    static func hosts(from responses: [SSDPResponse], target: String) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for r in responses {
            let st = r.headers["ST"] ?? r.headers["NT"] ?? ""
            guard st.caseInsensitiveCompare(target) == .orderedSame else { continue }
            let host = r.headers["LOCATION"].flatMap { URL(string: $0)?.host } ?? r.sender
            if !host.isEmpty, seen.insert(host).inserted { out.append(host) }
        }
        return out.sorted(by: IPv4.ordered)
    }

    static func merge(_ list: [DiscoveredTV]) -> [DiscoveredTV] {
        var seen = Set<String>()
        return list.filter { seen.insert($0.id).inserted }.sorted {
            $0.host == $1.host ? $0.brand.rawValue < $1.brand.rawValue : IPv4.ordered($0.host, $1.host)
        }
    }

    // MARK: Ad

    func name(_ brand: PairedTV.Brand, host: String) async -> String {
        switch brand {
        case .lg:
            return await lgDescription(host: host).flatMap(Self.friendlyName) ?? "LG TV"
        case .samsung:
            return await samsungName(host: host) ?? "Samsung TV"
        case .androidTV:
            return "Android TV"
        }
    }

    func lgDescription(host: String, timeout: TimeInterval? = nil) async -> String? {
        guard let url = Self.deviceURL(host, port: 1990),
              let r = try? await http.get(url, timeout: timeout ?? timing.nameTimeout), r.status == 200 else { return nil }
        return r.text
    }

    /// TV'nin yerel HTTP adresi: `http://<adres>:<kapı>/<yol>`.
    static func deviceURL(_ host: String, port: Int, path: String = "") -> URL? {
        URL(string: "http://\(host):\(port)/\(path)")
    }

    /// Samsung'un cihaz bilgisi uç noktası.
    static func samsungInfoURL(_ host: String) -> URL? { deviceURL(host, port: 8001, path: "api/v2/") }

    /// UPnP açıklamasındaki ilk `friendlyName` öğesinin içi (boşsa nil).
    static func friendlyName(_ xml: String) -> String? {
        let tag = "friendlyName"
        guard let opening = xml.range(of: "<\(tag)>"),
              let closing = xml[opening.upperBound...].range(of: "</\(tag)>") else { return nil }
        let inner = xml[opening.upperBound..<closing.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        return inner.isEmpty ? nil : xmlUnescape(inner)
    }

    /// XML'in beş hazır varlığı; `&amp;` en sonda çözülür (çift çözme olmasın).
    static let xmlEntities: [(entity: String, character: String)] = [
        ("&quot;", "\""), ("&apos;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&amp;", "&"),
    ]

    static func xmlUnescape(_ s: String) -> String {
        xmlEntities.reduce(s) { $0.replacingOccurrences(of: $1.entity, with: $1.character) }
    }

    func samsungName(host: String, timeout: TimeInterval? = nil) async -> String? {
        guard let url = Self.samsungInfoURL(host),
              let r = try? await http.get(url, timeout: timeout ?? timing.nameTimeout), r.status == 200 else { return nil }
        return SamsungDeviceInfo.parse(r.body)?.name
    }

    // MARK: Yedek tarama

    /// Mac'in her ev ağının /24 bölümü (kendisi hariç), aynı anda en çok 64 adres.
    func scan(_ brand: PairedTV.Brand, homes: [NetworkInterface]) async -> [DiscoveredTV] {
        let own = Set(homes.map(\.address))
        var addresses: [String] = []
        var seen = Set<String>()
        for h in homes { for a in IPv4.slash24(of: h.address, excluding: own) where seen.insert(a).inserted { addresses.append(a) } }
        guard !addresses.isEmpty else { return [] }
        let all = addresses

        // LG'de her adrese ayrı SSDP isteği de gider.
        async let unicast: [String] = brand == .lg
            ? Self.hosts(from: await ssdp.search(Self.searchRequest(target: Self.lgSearchTarget),
                                                 targets: all.map { SSDPTarget(.unicast(host: $0)) },
                                                 sendCount: 1, duration: timing.scanSSDPWindow),
                         target: Self.lgSearchTarget)
            : []

        let probed = await withTaskGroup(of: DiscoveredTV?.self) { group -> [DiscoveredTV] in
            var out: [DiscoveredTV] = []
            var iterator = all.makeIterator()
            func addNext() -> Bool {
                guard let a = iterator.next() else { return false }
                group.addTask { await probe(brand, host: a) }
                return true
            }
            for _ in 0..<timing.scanConcurrency where !addNext() { break }
            while let r = await group.next() {
                if let r { out.append(r) }
                _ = addNext()
            }
            return out
        }
        var found = probed
        for h in await unicast where !found.contains(where: { $0.host == h }) {
            found.append(DiscoveredTV(name: await name(.lg, host: h), host: h, brand: .lg))
        }
        return Self.merge(found)
    }

    func probe(_ brand: PairedTV.Brand, host: String) async -> DiscoveredTV? {
        let t = timing.scanProbeTimeout
        switch brand {
        case .lg:
            if let xml = await lgDescription(host: host, timeout: t), Self.looksLikeLG(xml) {
                return DiscoveredTV(name: Self.friendlyName(xml) ?? "LG TV", host: host, brand: .lg)
            }
            if let url = URL(string: "http://\(host):3000/"), let r = try? await http.get(url, timeout: t),
               r.text == "Hello world" {
                return DiscoveredTV(name: await name(.lg, host: host), host: host, brand: .lg)
            }
            return nil
        case .samsung:
            guard let n = await samsungName(host: host, timeout: t) else { return nil }
            return DiscoveredTV(name: n, host: host, brand: .samsung)
        case .androidTV:
            return nil
        }
    }

    static func looksLikeLG(_ xml: String) -> Bool {
        let l = xml.lowercased()
        return l.contains("<device") && (l.contains("lg electronics") || l.contains("webos"))
    }
}

// MARK: Adres değişirse

/// Bağlantı başarısız olunca (en çok 30 sn'de bir) aynı markadaki TV'ler yeniden aranır.
public struct TVReaddressPolicy: Sendable {
    public var minimumInterval: TimeInterval = 30
    private(set) var lastAttempt: Date?

    public init(minimumInterval: TimeInterval = 30) { self.minimumInterval = minimumInterval }

    /// Şimdi yeniden aranabilir mi; evetse an kaydedilir.
    public mutating func shouldSearch(now: Date) -> Bool {
        if let lastAttempt, now.timeIntervalSince(lastAttempt) < minimumInterval { return false }
        lastAttempt = now
        return true
    }

    /// Kayıtlı adres listede yoksa: aynı adlı tek TV, yoksa bulunan tek TV. Birden çok tanımadık TV varsa nil.
    public static func newAddress(saved: TVRecord, found: [DiscoveredTV]) -> DiscoveredTV? {
        let same = found.filter { $0.brand == saved.brand }
        if same.contains(where: { $0.host == saved.host }) { return nil }
        let named = same.filter { $0.name == saved.name }
        if named.count == 1 { return named[0] }
        if same.count == 1 { return same[0] }
        return nil
    }
}

// MARK: Yeni Nino TV uygulamaları (Bonjour)

/// Bonjour ile bulunan bir Nino TV uygulaması (TV dinler, Mac bağlanır).
public struct FoundNinoDisplay: Equatable, Hashable, Sendable {
    public var name: String
    public var id: String?
    public var host: String
    public var port: UInt16
    public var appVersion: String?
    public init(name: String, id: String?, host: String, port: UInt16, appVersion: String? = nil) {
        self.name = name
        self.id = id
        self.host = host
        self.port = port
        self.appVersion = appVersion
    }
}

public protocol NinoDisplayFinding: Sendable {
    /// Bu süre içinde bulunan TV uygulamaları (göndericiler elenmiş).
    func find(timeout: TimeInterval) async -> [FoundNinoDisplay]
}
