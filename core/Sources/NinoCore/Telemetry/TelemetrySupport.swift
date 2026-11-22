// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Compression
import Foundation

/// Her parçada giden ortak alanlar (`ctx`).
public struct TelemetryContext: Codable, Equatable, Sendable {
    public var platform: String
    public var app: String
    public var os: String
    public var device: String
    /// Bağlı TV'nin markası (`androidtv`, `samsung`, `lg`); yoksa boş.
    public var tv: String
    public var channel: String

    public init(platform: String, app: String, os: String, device: String, tv: String = "", channel: String = "release") {
        self.platform = platform
        self.app = app
        self.os = os
        self.device = device
        self.tv = tv
        self.channel = channel
    }

    /// Bu cihazın bilgileriyle: platform (`mac`/`ios`), işletim sistemi sürümü, model kimliği (ad değil).
    public static func current(app: String, channel: String = "release") -> TelemetryContext {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        let version = v.patchVersion > 0 ? "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)" : "\(v.majorVersion).\(v.minorVersion)"
        #if os(macOS)
        return TelemetryContext(platform: "mac", app: app, os: "macOS \(version)", device: sysctlString("hw.model") ?? "Mac", channel: channel)
        #else
        var model = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? ""
        if model.isEmpty {
            var info = utsname()
            uname(&info)
            model = withUnsafeBytes(of: &info.machine) { raw in
                String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
            }
        }
        return TelemetryContext(platform: "ios", app: app, os: "iOS \(version)", device: model, channel: channel)
        #endif
    }

    #if os(macOS)
    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }
    #endif
}

/// Sunucunun uzaktan ölçüm ayarı (`/v1/config` → `telemetry`, ve her `/v1/events` cevabı).
public struct TelemetryRemoteConfig: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var sample: Double
    public var maxPerDay: Int
    public var flushSeconds: Int
    /// Otomatik teşhis: sunucunun kapattığı kurallar ve eşikler (yoksa tarifteki varsayılanlar).
    public var diag: DiagConfig?

    public struct DiagConfig: Codable, Equatable, Sendable {
        public var off: [String]
        public var limits: [String: Double]
        public init(off: [String] = [], limits: [String: Double] = [:]) {
            self.off = off
            self.limits = limits
        }
        public func isOff(_ rule: String) -> Bool { off.contains(rule) }
        public func limit(_ name: String, default value: Double) -> Double { limits[name] ?? value }
    }

    public init(enabled: Bool = true, sample: Double = 1, maxPerDay: Int = 1000, flushSeconds: Int = 600, diag: DiagConfig? = nil) {
        self.enabled = enabled
        self.sample = sample
        self.maxPerDay = maxPerDay
        self.flushSeconds = flushSeconds
        self.diag = diag
    }

    /// Kurulum bu örneklemde mi: `fnv1a32(kimlik) % 10000 < sample × 10000`. Kurulum başına sabittir.
    public static func isSampled(install: String, sample: Double) -> Bool {
        if sample >= 1 { return true }
        if sample <= 0 { return false }
        var hash: UInt32 = 0x811c9dc5
        for byte in install.lowercased().utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 0x0100_0193
        }
        return Double(hash % 10000) < sample * 10000
    }
}

/// gzip (RFC 1952) sıkıştırıcı: gövde Compression çerçevesinin ham DEFLATE çıktısı, başına gzip başlığı, sonuna CRC32
/// ve boy. Açıcı `Gzip.decompress`.
public enum TelemetryGzip {
    public static func compress(_ data: Data) -> Data? {
        let input = [UInt8](data)
        var deflated: [UInt8]
        if input.isEmpty {
            deflated = [0x03, 0x00]
        } else {
            let capacity = input.count + input.count / 8 + 1024
            deflated = [UInt8](repeating: 0, count: capacity)
            let n = compression_encode_buffer(&deflated, capacity, input, input.count, nil, COMPRESSION_ZLIB)
            guard n > 0 else { return nil }
            deflated.removeSubrange(n...)
        }
        var out: [UInt8] = [0x1f, 0x8b, 8, 0, 0, 0, 0, 0, 0, 0xff]
        out += deflated
        for value in [crc32(input), UInt32(truncatingIfNeeded: input.count)] {
            out += [UInt8(value & 0xff), UInt8((value >> 8) & 0xff), UInt8((value >> 16) & 0xff), UInt8(value >> 24)]
        }
        return Data(out)
    }

    private static let table: [UInt32] = (0..<256).map { n -> UInt32 in
        var c = UInt32(n)
        for _ in 0..<8 { c = c & 1 != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    static func crc32(_ bytes: [UInt8]) -> UInt32 {
        var c: UInt32 = 0xffff_ffff
        for b in bytes { c = table[Int((c ^ UInt32(b)) & 0xff)] ^ (c >> 8) }
        return c ^ 0xffff_ffff
    }
}

/// Sunucuya gönderim. Testlerde sahtesi kullanılır.
public protocol TelemetryTransport: Sendable {
    /// Gövdeyi gönderir; ağ hatasında hata fırlatır.
    func send(_ body: Data, gzip: Bool, to url: URL) async throws -> TelemetryResponse
}

public struct TelemetryResponse: Sendable, Equatable {
    public var status: Int
    public var body: Data
    public var retryAfter: Int?

    public init(status: Int, body: Data = Data(), retryAfter: Int? = nil) {
        self.status = status
        self.body = body
        self.retryAfter = retryAfter
    }
}

public struct URLSessionTelemetryTransport: TelemetryTransport {
    public let session: URLSession
    public let timeout: TimeInterval

    public init(session: URLSession = .shared, timeout: TimeInterval = 20) {
        self.session = session
        self.timeout = timeout
    }

    public func send(_ body: Data, gzip: Bool, to url: URL) async throws -> TelemetryResponse {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        if gzip { request.setValue("gzip", forHTTPHeaderField: "content-encoding") }
        request.httpBody = body
        let (data, response) = try await session.data(for: request)
        let http = response as? HTTPURLResponse
        let retry = http?.value(forHTTPHeaderField: "retry-after").flatMap { Int($0) }
        return TelemetryResponse(status: http?.statusCode ?? 0, body: data, retryAfter: retry)
    }
}
