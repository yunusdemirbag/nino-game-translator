// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Compression
import CryptoKit
import XCTest
@testable import Nino

/// TV paketleri: zip, Android ikili XML, ipk ve paket deposunun indirme/önbellek/gömülü sırası (ağsız).
final class TVPackageTests: XCTestCase {
    func testStoredZipRoundTripAndDeflateRead() throws {
        let entries = [ZipArchive.Entry(name: "config.xml", data: Bytes("<widget/>".utf8)),
                       ZipArchive.Entry(name: "fonts/a.ttf", data: Bytes(repeating: 7, count: 5000))]
        let zip = ZipArchive(entries: entries).stored()
        let back = try ZipArchive(zip)
        XCTAssertEqual(back.entries.map(\.name), ["config.xml", "fonts/a.ttf"])
        XCTAssertEqual(back.data(named: "fonts/a.ttf"), entries[1].data)
        XCTAssertEqual(CRC32.of(Bytes("123456789".utf8)), 0xCBF4_3926)
        // Deflate kayıt: aynı veri sıkıştırılmış olarak.
        let packed = TestPack.deflate(entries[1].data)
        XCTAssertEqual(try Inflate.raw(packed, expected: 5000), entries[1].data)
        XCTAssertEqual(try Inflate.gunzip(TestPack.gzip(Bytes("hello".utf8))), Bytes("hello".utf8))
    }

    func testAndroidManifestIdentityAndVersion() throws {
        let apk = ZipArchive(entries: [.init(name: "AndroidManifest.xml",
                                             data: TestPack.binaryManifest(package: "com.ninotranslator.tv", version: "4.0.7"))]).stored()
        XCTAssertEqual(TVPackageKind.android.inspect(apk), "4.0.7")
        let other = ZipArchive(entries: [.init(name: "AndroidManifest.xml",
                                               data: TestPack.binaryManifest(package: "com.example.other", version: "9.9.9"))]).stored()
        XCTAssertNil(TVPackageKind.android.inspect(other), "başka bir uygulamanın paketi kabul edilmemeli")
    }

    func testIpkAndWgtInspection() throws {
        let ipk = TestPack.ipk(package: LGInstaller.appID, version: "4.0.3")
        XCTAssertEqual(TVPackageKind.lg.inspect(ipk), "4.0.3")
        XCTAssertNil(TVPackageKind.lg.inspect(TestPack.ipk(package: "com.example.tv", version: "4.0.3")))
        let wgt = TestPack.wgt(version: "4.0.3")
        XCTAssertEqual(TVPackageKind.samsung.inspect(wgt), "4.0.3")
    }

    /// Derlemede üretilen paketler uygulamada ve kimlikleri doğru; Samsung ara sertifikaları okunuyor.
    func testBundledPackagesAndSamsungAuthorities() throws {
        var store = TVPackageStore(cache: TVTestFiles.scratch())
        store.fetch = { _ in throw BlockingHTTP.Failure(status: 0, body: Data(), reason: "offline") }
        XCTAssertEqual(try store.package(.samsung, log: nil).origin, "bundled")
        XCTAssertEqual(try store.package(.lg, log: nil).origin, "bundled")
        XCTAssertEqual(SamsungCertificateService.authorities.count, 4)
    }

    func testStorePrefersNewestAndFallsBackToCache() throws {
        let dir = TVTestFiles.scratch()
        let bundled = dir.appendingPathComponent("bundle")
        try FileManager.default.createDirectory(at: bundled, withIntermediateDirectories: true)
        try Data(TestPack.ipk(package: LGInstaller.appID, version: "4.0.3")).write(to: bundled.appendingPathComponent("nino-lg.ipk"))
        var store = TVPackageStore(cache: dir.appendingPathComponent("cache"))
        store.bundled = bundled
        let newer = TestPack.ipk(package: LGInstaller.appID, version: "4.1.0")
        store.fetch = { url in
            XCTAssertEqual(url.lastPathComponent, "Nino-TV.ipk")
            return Data(newer)
        }
        XCTAssertEqual(try store.package(.lg, log: nil).version, "4.1.0")
        // İnternet yok: önceki indirilen (4.1.0) gömülüden (4.0.3) yeni olduğu için o kullanılır.
        store.fetch = { _ in throw BlockingHTTP.Failure(status: 0, body: Data(), reason: "offline") }
        let offline = try store.package(.lg, log: nil)
        XCTAssertEqual(offline.version, "4.1.0")
        XCTAssertEqual(offline.origin, "cache")
        // Başka uygulamanın paketi indirilirse yok sayılır.
        store.fetch = { _ in Data(TestPack.ipk(package: "com.example.tv", version: "9.0.0")) }
        XCTAssertEqual(try store.package(.lg, log: nil).version, "4.1.0")
        // Hiçbiri yoksa hata.
        var empty = TVPackageStore(cache: dir.appendingPathComponent("none"))
        empty.bundled = nil
        empty.fetch = { _ in throw BlockingHTTP.Failure(status: 404, body: Data(), reason: "") }
        XCTAssertThrowsError(try empty.package(.android, log: nil))
    }
}

/// Testlerde paket üretimi.
enum TestPack {
    static func deflate(_ data: Bytes) -> Bytes {
        var out = Bytes(repeating: 0, count: data.count + 1024)
        let n = compression_encode_buffer(&out, out.count, data, data.count, nil, COMPRESSION_ZLIB)
        return Array(out[0..<n])
    }

    static func gzip(_ data: Bytes) -> Bytes {
        var out: Bytes = [0x1F, 0x8B, 8, 0, 0, 0, 0, 0, 0, 3] + deflate(data)
        out.putLE32(CRC32.of(data))
        out.putLE32(UInt32(data.count))
        return out
    }

    static func tar(_ files: [(String, Bytes)]) -> Bytes {
        var out = Bytes()
        for (name, data) in files {
            var h = Bytes(repeating: 0, count: 512)
            let n = Bytes(name.utf8)
            h.replaceSubrange(0..<n.count, with: n)
            let size = Bytes(String(format: "%011o", data.count).utf8)
            h.replaceSubrange(124..<(124 + size.count), with: size)
            h[156] = 0x30
            out += h + data + Bytes(repeating: 0, count: (512 - data.count % 512) % 512)
        }
        return out + Bytes(repeating: 0, count: 1024)
    }

    static func ar(_ members: [(String, Bytes)]) -> Bytes {
        var out = Bytes("!<arch>\n".utf8)
        for (name, data) in members {
            let head = name.padding(toLength: 16, withPad: " ", startingAt: 0) + "0".padding(toLength: 12, withPad: " ", startingAt: 0)
                + "0     0     100644  " + String(data.count).padding(toLength: 10, withPad: " ", startingAt: 0) + "`\n"
            out += Bytes(head.utf8) + data
            if data.count % 2 == 1 { out.append(0x0A) }
        }
        return out
    }

    static func ipk(package: String, version: String) -> Bytes {
        let control = Bytes("Package: \(package)\nVersion: \(version)\nArchitecture: all\n".utf8)
        return ar([("debian-binary", Bytes("2.0\n".utf8)),
                   ("control.tar.gz", gzip(tar([("./control", control)]))),
                   ("data.tar.gz", gzip(tar([("usr/palm/applications/\(package)/index.html", Bytes("<html/>".utf8))])))])
    }

    static func wgt(version: String) -> Bytes {
        let config = """
        <?xml version="1.0" encoding="UTF-8"?>
        <widget xmlns="http://www.w3.org/ns/widgets" xmlns:tizen="http://tizen.org/ns/widgets" id="https://example.org/nino" version="\(version)" viewmodes="maximized">
            <tizen:application id="\(SamsungInstaller.appID)" package="\(SamsungInstaller.packageID)" required_version="2.4"/>
        </widget>
        """
        return ZipArchive(entries: [.init(name: "config.xml", data: Bytes(config.utf8)),
                                    .init(name: "index.html", data: Bytes("<html></html>".utf8))]).stored()
    }

    /// En küçük ikili AndroidManifest.xml: dize havuzu ve `manifest` öğesi (package, versionName).
    static func binaryManifest(package: String, version: String) -> Bytes {
        let strings = ["manifest", "package", "versionName", package, version]
        var pool = Bytes(), offsets = Bytes()
        for s in strings {
            offsets.putLE32(UInt32(pool.count))
            let b = Bytes(s.utf8)
            pool += [UInt8(b.count), UInt8(b.count)] + b + [0]
        }
        while pool.count % 4 != 0 { pool.append(0) }
        var sp = Bytes()
        sp.putLE16(0x0001); sp.putLE16(28)
        sp.putLE32(UInt32(28 + offsets.count + pool.count))
        sp.putLE32(UInt32(strings.count)); sp.putLE32(0)
        sp.putLE32(0x100); sp.putLE32(UInt32(28 + offsets.count)); sp.putLE32(0)
        sp += offsets + pool

        var el = Bytes()
        el.putLE16(0x0102); el.putLE16(16)
        el.putLE32(UInt32(16 + 20 + 2 * 20))
        el.putLE32(1); el.putLE32(UInt32.max)
        el.putLE32(UInt32.max); el.putLE32(0)            // ns, name = "manifest"
        el.putLE16(20); el.putLE16(20); el.putLE16(2)     // attrStart, attrSize, count
        el.putLE16(0); el.putLE16(0); el.putLE16(0)
        for (name, value) in [(1, 3), (2, 4)] {
            el.putLE32(UInt32.max); el.putLE32(UInt32(name)); el.putLE32(UInt32(value))
            el.putLE16(8); el.append(0); el.append(3); el.putLE32(UInt32(value))
        }
        var out = Bytes()
        out.putLE16(0x0003); out.putLE16(8)
        out.putLE32(UInt32(8 + sp.count + el.count))
        return out + sp + el
    }
}
