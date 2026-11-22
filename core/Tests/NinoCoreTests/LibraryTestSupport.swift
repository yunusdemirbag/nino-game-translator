// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation
import XCTest
@testable import NinoCore

/// Testler için gzip yazıcı: "saklı" deflate blokları (sıkıştırmasız), isteğe bağlı başlık alanları.
enum TestGzip {
    static func make(_ payload: Data, name: String? = nil, comment: String? = nil, extra: [UInt8]? = nil,
                     headerCRC: Bool = false, corruptSize: Bool = false) -> Data {
        var out: [UInt8] = [0x1f, 0x8b, 8]
        var flags: UInt8 = 0
        if headerCRC { flags |= 0x02 }
        if extra != nil { flags |= 0x04 }
        if name != nil { flags |= 0x08 }
        if comment != nil { flags |= 0x10 }
        out += [flags, 0, 0, 0, 0, 0, 3]
        if let extra { out += [UInt8(extra.count & 0xff), UInt8(extra.count >> 8)] + extra }
        if let name { out += Array(name.utf8) + [0] }
        if let comment { out += Array(comment.utf8) + [0] }
        if headerCRC { out += [0, 0] }
        let bytes = [UInt8](payload)
        var i = 0
        repeat {
            let n = min(65_535, bytes.count - i)
            let final: UInt8 = i + n >= bytes.count ? 1 : 0
            out += [final, UInt8(n & 0xff), UInt8(n >> 8), UInt8(~n & 0xff), UInt8((~n >> 8) & 0xff)]
            out += bytes[i..<(i + n)]
            i += n
        } while i < bytes.count
        let crc = crc32(bytes)
        out += (0..<4).map { UInt8(truncatingIfNeeded: crc >> (8 * $0)) }
        let size = UInt32(truncatingIfNeeded: bytes.count) &+ (corruptSize ? 1 : 0)
        out += (0..<4).map { UInt8(truncatingIfNeeded: size >> (8 * $0)) }
        return Data(out)
    }

    static func crc32(_ bytes: [UInt8]) -> UInt32 {
        var c: UInt32 = 0xffffffff
        for b in bytes {
            c ^= UInt32(b)
            for _ in 0..<8 { c = c & 1 != 0 ? (c >> 1) ^ 0xedb88320 : c >> 1 }
        }
        return ~c
    }
}

func makeLibraryTempDirectory(_ name: String = "nino-library") throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func libraryKey(_ s: String) -> String { LineKey.hex(LineKey.key(s)!) }

func libraryJSON(_ object: Any) -> Data {
    try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
}

/// Gerçek paket klasörü: `NINO_LEGACY_PACKS_DIR` verilmezse test atlanır.
func legacyPacksDirectory() throws -> URL {
    guard let path = ProcessInfo.processInfo.environment["NINO_LEGACY_PACKS_DIR"], !path.isEmpty else {
        throw XCTSkip("NINO_LEGACY_PACKS_DIR verilmedi")
    }
    return URL(fileURLWithPath: path, isDirectory: true)
}

/// Sahte taşıyıcı: gerçek ağ yok. Her istek kaydedilir, cevabı işleyici verir.
final class FakePoolTransport: PoolTransport, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) async throws -> (Int, Data, [String: String])
    private let lock = NSLock()
    private var _requests: [URLRequest] = []
    private var handler: Handler

    init(_ handler: @escaping Handler = { _ in (404, Data(), [:]) }) { self.handler = handler }

    var requests: [URLRequest] { lock.withLock { _requests } }
    func paths() -> [String] { requests.compactMap { $0.url?.path } }
    func setHandler(_ h: @escaping Handler) { lock.withLock { handler = h } }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let h = lock.withLock { () -> Handler in
            _requests.append(request)
            return handler
        }
        let (status, data, headers) = try await h(request)
        return (data, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!)
    }
}

/// Elle ilerletilen saat ve sıralı kimlikler.
final class PoolTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var t: Date
    private var n = 0
    init(_ unix: TimeInterval = 1_763_300_000) { t = Date(timeIntervalSince1970: unix) }
    var now: Date { lock.withLock { t } }
    func advance(_ s: TimeInterval) { lock.withLock { t += s } }
    func nextUUID() -> UUID {
        lock.withLock {
            n += 1
            return UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", n))!
        }
    }
    var environment: PoolEnvironment {
        PoolEnvironment(now: { self.now }, uuid: { self.nextUUID() }, jitter: { 0 })
    }
}

let poolTestServer = URL(string: "https://pool.example.test")!

func poolJSON(_ object: Any) -> Data { try! JSONSerialization.data(withJSONObject: object) }

func poolBody(_ r: URLRequest) -> [String: Any] {
    (try? JSONSerialization.jsonObject(with: r.httpBody ?? Data())) as? [String: Any] ?? [:]
}
