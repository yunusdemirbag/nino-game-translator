// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

// ADB ileti çerçevesi (AOSP adb `docs/dev/protocol.md`): 24 baytlık başlık, altı adet küçük-sonlu 32 bit sözcük
// (komut, arg0, arg1, veri uzunluğu, veri sağlaması, sihir = komut ^ 0xffffffff) ve ardından veri.

public struct ADBMessage: Equatable, Sendable {
    public enum Command: UInt32, Sendable {
        case cnxn = 0x4e58_4e43
        case auth = 0x4854_5541
        case open = 0x4e45_504f
        case okay = 0x5941_4b4f
        case clse = 0x4553_4c43
        case wrte = 0x4554_5257
        case stls = 0x534c_5453
        case sync = 0x434e_5953
    }

    public static let headerSize = 24
    /// Sağlama atlanabilen sürüm; yine de bayt toplamı gönderilir (eski cihazlar onu denetler).
    public static let version: UInt32 = 0x0100_0001
    /// Bizim kabul ettiğimiz en büyük veri. Karşı taraf daha küçüğünü CNXN'de söyler.
    public static let maxData: UInt32 = 256 * 1024
    /// CNXN ve AUTH en çok bu kadar olmalı (eski adbd 4096'yı sabit tutuyordu).
    public static let legacyMaxData = 4096

    public enum AuthType: UInt32, Sendable {
        case token = 1
        case signature = 2
        case rsaPublicKey = 3
    }

    public var command: UInt32
    public var arg0: UInt32
    public var arg1: UInt32
    public var data: Data

    public init(_ command: Command, _ arg0: UInt32, _ arg1: UInt32, _ data: Data = Data()) {
        self.command = command.rawValue
        self.arg0 = arg0
        self.arg1 = arg1
        self.data = data
    }

    public init(rawCommand: UInt32, arg0: UInt32, arg1: UInt32, data: Data) {
        command = rawCommand
        self.arg0 = arg0
        self.arg1 = arg1
        self.data = data
    }

    public var kind: Command? { Command(rawValue: command) }

    /// Verinin bayt toplamı (eski sürümlerin sağlaması).
    public static func checksum(_ data: Data) -> UInt32 {
        data.reduce(UInt32(0)) { $0 &+ UInt32($1) }
    }

    public func encoded() -> Data {
        var out = Data(capacity: Self.headerSize + data.count)
        for word in [command, arg0, arg1, UInt32(data.count), Self.checksum(data), command ^ 0xffff_ffff] {
            out.appendLE(word)
        }
        out.append(data)
        return out
    }

    public struct Header: Equatable, Sendable {
        public var command: UInt32
        public var arg0: UInt32
        public var arg1: UInt32
        public var length: UInt32
        public var checksum: UInt32
    }

    public enum FrameError: Error, Equatable {
        case badMagic
        case tooLarge(UInt32)
        case badChecksum
    }

    /// 24 baytlık başlığı çözer.
    public static func decodeHeader(_ d: Data) throws -> Header {
        precondition(d.count >= headerSize)
        let w = (0..<6).map { d.readLE32(at: $0 * 4) }
        guard w[5] == w[0] ^ 0xffff_ffff else { throw FrameError.badMagic }
        guard w[3] <= maxData else { throw FrameError.tooLarge(w[3]) }
        return Header(command: w[0], arg0: w[1], arg1: w[2], length: w[3], checksum: w[4])
    }

    /// Bağlantı (CNXN) verisi: "host::features=…" + NUL.
    public static func hostBanner(features: [String] = ["cmd", "stat_v2", "ls_v2"]) -> Data {
        Data("host::features=\(features.joined(separator: ","))\u{0}".utf8)
    }

    /// Hizmet adı (OPEN verisi) NUL ile biter.
    public static func service(_ name: String) -> Data { Data((name + "\u{0}").utf8) }
}

/// Cihazın CNXN afişi: "device::ro.product.name=…;ro.product.model=…;features=…".
public struct ADBBanner: Equatable, Sendable {
    public var systemType: String
    public var properties: [String: String]
    public var features: Set<String>

    public init(_ data: Data) {
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: CharacterSet(charactersIn: "\u{0}"))
        let parts = text.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
        systemType = parts.first.map(String.init) ?? ""
        var props: [String: String] = [:]
        if parts.count == 3 {
            for item in parts[2].split(separator: ";") {
                guard let eq = item.firstIndex(of: "=") else { continue }
                props[String(item[..<eq])] = String(item[item.index(after: eq)...])
            }
        }
        properties = props
        features = Set((props["features"] ?? "").split(separator: ",").map(String.init))
    }

    public var model: String? { properties["ro.product.model"] }
}

extension Data {
    mutating func appendLE(_ v: UInt32) {
        var le = v.littleEndian
        Swift.withUnsafeBytes(of: &le) { append(contentsOf: $0) }
    }

    func readLE32(at offset: Int) -> UInt32 {
        let i = startIndex + offset
        return UInt32(self[i]) | UInt32(self[i + 1]) << 8 | UInt32(self[i + 2]) << 16 | UInt32(self[i + 3]) << 24
    }
}
