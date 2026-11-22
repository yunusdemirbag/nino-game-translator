// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Compression
import Foundation

// TV paketleri: GitHub'daki son Nino sürümünden indirilir ve önbelleğe alınır (internet yoksa önceki indirilen);
// derlemede uygulamaya gömülen kopyalar (apps/ios/scripts/tv-packages.sh) son çaredir. Her paketin kimliği
// denetlenir: başka bir uygulamanın paketi TV'ye kurulmaz.

struct TVPackage: Sendable {
    var bytes: Bytes
    var version: String
    /// Nereden geldiği (günlük için).
    var origin: String
}

struct TVPackageMissing: Error, CustomStringConvertible {
    let description: String
}

enum TVPackageKind: String, CaseIterable, Sendable {
    case android, samsung, lg

    /// Sürüm sayfasındaki dosya adı.
    var releaseAsset: String {
        switch self {
        case .android: "Nino-TV.apk"
        case .samsung: "Nino-TV.wgt"
        case .lg: "Nino-TV.ipk"
        }
    }

    /// Uygulamaya gömülü kopyanın adı (paketteki `tv/` klasöründe).
    var bundledName: String {
        switch self {
        case .android: "nino-tv.apk"
        case .samsung: "nino-samsung.wgt"
        case .lg: "nino-lg.ipk"
        }
    }

    /// Paketin kimliğini denetler ve sürümünü okur; Nino'nun paketi değilse nil.
    func inspect(_ bytes: Bytes) -> String? {
        switch self {
        case .android:
            guard let entry = try? ZipArchive(bytes).data(named: "AndroidManifest.xml"),
                  let manifest = BinaryXML.manifest(entry),
                  manifest.package == AndroidTVInstaller.packageID else { return nil }
            return manifest.versionName
        case .samsung:
            guard let config = try? ZipArchive(bytes).data(named: "config.xml") else { return nil }
            let text = String(decoding: config, as: UTF8.self)
            guard text.contains("\"\(SamsungInstaller.appID)\"") else { return nil }
            return firstCapture(#"<widget[^>]*\sversion="([0-9.]+)""#, text)
        case .lg:
            guard let control = WebOSPackage.control(bytes), control["Package"] == LGInstaller.appID else { return nil }
            return control["Version"]
        }
    }
}

/// Paketleri bulur: indirme → önbellek → gömülü.
struct TVPackageStore: Sendable {
    static let releaseBase = URL(string: "https://github.com/yunusdemirbag/nino-game-translator/releases/latest/download/")!

    let cache: URL
    var bundled: URL? = Bundle.main.resourceURL?.appendingPathComponent("tv", isDirectory: true)
    /// İndirme (testlerde değiştirilir). Hata atarsa önbellek kullanılır.
    var fetch: @Sendable (URL) throws -> Data = { url in try BlockingHTTP.get(url, timeout: 40) }

    func package(_ kind: TVPackageKind, log: TVInstallLog?) throws -> TVPackage {
        var candidates: [TVPackage] = []
        do {
            let data = Bytes(try fetch(Self.releaseBase.appendingPathComponent(kind.releaseAsset)))
            if let version = kind.inspect(data) {
                try? FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
                try? Data(data).write(to: cacheFile(kind), options: .atomic)
                candidates.append(TVPackage(bytes: data, version: version, origin: "download"))
            } else {
                log?.write("\(kind.releaseAsset) from the release is not Nino's TV package; ignored.")
            }
        } catch {
            log?.write("\(kind.releaseAsset) not downloaded: \(error)")
        }
        if candidates.isEmpty, let data = try? Data(contentsOf: cacheFile(kind)), let version = kind.inspect(Bytes(data)) {
            candidates.append(TVPackage(bytes: Bytes(data), version: version, origin: "cache"))
        }
        if let url = bundled?.appendingPathComponent(kind.bundledName), let data = try? Data(contentsOf: url),
           let version = kind.inspect(Bytes(data)) {
            candidates.append(TVPackage(bytes: Bytes(data), version: version, origin: "bundled"))
        }
        // En yeni sürüm; eşitse sıradaki (indirilen önce).
        guard var best = candidates.first else {
            throw TVPackageMissing(description: "no \(kind.rawValue) TV package (download, cache and bundle all missing)")
        }
        for c in candidates.dropFirst() where VersionOrder.isNewer(c.version, than: best.version) { best = c }
        log?.write("TV package \(kind.rawValue): \(best.version) (\(best.origin), \(best.bytes.count) bytes)")
        return best
    }

    /// İndirmeden bilinen en yeni sürüm (önbellekteki ya da uygulamaya gömülü paket); yoksa nil.
    func localVersion(_ kind: TVPackageKind) -> String? {
        let urls = [cacheFile(kind), bundled?.appendingPathComponent(kind.bundledName)].compactMap { $0 }
        var best: String?
        for url in urls {
            guard let data = try? Data(contentsOf: url), let v = kind.inspect(Bytes(data)) else { continue }
            if best.map({ VersionOrder.isNewer(v, than: $0) }) ?? true { best = v }
        }
        return best
    }

    private func cacheFile(_ kind: TVPackageKind) -> URL { cache.appendingPathComponent(kind.bundledName) }
}

func firstCapture(_ pattern: String, _ text: String) -> String? {
    guard let re = try? NSRegularExpression(pattern: pattern),
          let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
          let r = Range(m.range(at: 1), in: text) else { return nil }
    return String(text[r])
}

// MARK: - Zip

/// Zip okuyucu (sıkıştırmasız ve deflate kayıtlar) ve sıkıştırmasız zip yazıcı.
struct ZipArchive {
    struct Entry {
        var name: String
        var data: Bytes
    }

    let entries: [Entry]

    init(entries: [Entry]) { self.entries = entries }

    init(_ zip: Bytes) throws {
        guard zip.count >= 22 else { throw TVPackageMissing(description: "zip too short") }
        var end = zip.count - 22
        while end >= 0, zip.le32(at: end) != 0x0605_4B50 { end -= 1 }
        guard end >= 0 else { throw TVPackageMissing(description: "zip end record missing") }
        let count = zip.le16(at: end + 10)
        var p = Int(zip.le32(at: end + 16))
        var out: [Entry] = []
        for _ in 0..<count {
            guard p + 46 <= zip.count, zip.le32(at: p) == 0x0201_4B50 else { throw TVPackageMissing(description: "zip directory") }
            let method = zip.le16(at: p + 10)
            let packed = Int(zip.le32(at: p + 20)), size = Int(zip.le32(at: p + 24))
            let nameLength = zip.le16(at: p + 28), extra = zip.le16(at: p + 30), comment = zip.le16(at: p + 32)
            let local = Int(zip.le32(at: p + 42))
            guard p + 46 + nameLength <= zip.count, local + 30 <= zip.count else { throw TVPackageMissing(description: "zip entry") }
            let name = String(decoding: zip[(p + 46)..<(p + 46 + nameLength)], as: UTF8.self)
            p += 46 + nameLength + extra + comment
            let start = local + 30 + zip.le16(at: local + 26) + zip.le16(at: local + 28)
            guard start + packed <= zip.count else { throw TVPackageMissing(description: "zip entry \(name)") }
            let raw = Array(zip[start..<(start + packed)])
            switch method {
            case 0: out.append(Entry(name: name, data: raw))
            case 8: out.append(Entry(name: name, data: try Inflate.raw(raw, expected: size)))
            default: throw TVPackageMissing(description: "zip method \(method) for \(name)")
            }
        }
        entries = out
    }

    func data(named name: String) -> Bytes? { entries.first { $0.name == name }?.data }

    /// Sıkıştırmasız zip (tarih 1980-01-01, UTF-8 adlar).
    func stored() -> Bytes {
        var body = Bytes(), directory = Bytes()
        for e in entries {
            let name = Bytes(e.name.utf8)
            let crc = CRC32.of(e.data)
            var common = Bytes()
            common.putLE16(20)          // gereken sürüm
            common.putLE16(0x0800)      // UTF-8 ad
            common.putLE16(0)           // yöntem: stored
            common.putLE16(0)           // saat
            common.putLE16(0x21)        // tarih 1980-01-01
            common.putLE32(crc)
            common.putLE32(UInt32(e.data.count))
            common.putLE32(UInt32(e.data.count))
            common.putLE16(name.count)
            common.putLE16(0)           // ek alan
            let offset = UInt32(body.count)
            body.putLE32(0x0403_4B50)
            body += common + name + e.data
            directory.putLE32(0x0201_4B50)
            directory.putLE16(20)       // yazan sürüm
            directory += common
            directory.putLE16(0)        // yorum
            directory.putLE16(0)        // disk
            directory.putLE16(0)        // iç öznitelik
            directory.putLE32(0)        // dış öznitelik
            directory.putLE32(offset)
            directory += name
        }
        var out = body + directory
        out.putLE32(0x0605_4B50)
        out.putLE16(0)
        out.putLE16(0)
        out.putLE16(entries.count)
        out.putLE16(entries.count)
        out.putLE32(UInt32(directory.count))
        out.putLE32(UInt32(body.count))
        out.putLE16(0)
        return out
    }
}

enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { n in
        (0..<8).reduce(UInt32(n)) { c, _ in c & 1 == 1 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
    }

    static func of(_ data: Bytes) -> UInt32 {
        ~data.reduce(~UInt32(0)) { table[Int(($0 ^ UInt32($1)) & 0xFF)] ^ ($0 >> 8) }
    }
}

/// Ham deflate ve gzip açma (Compression çerçevesinin ZLIB'i ham deflate'tir).
enum Inflate {
    static func raw(_ data: Bytes, expected: Int? = nil) throws -> Bytes {
        if data.isEmpty { return [] }
        var capacity = max(expected ?? 0, data.count * 4, 1024)
        while capacity <= 512 * 1024 * 1024 {
            var out = Bytes(repeating: 0, count: capacity)
            let n = data.withUnsafeBufferPointer { src in
                out.withUnsafeMutableBufferPointer { dst in
                    compression_decode_buffer(dst.baseAddress!, capacity, src.baseAddress!, data.count, nil, COMPRESSION_ZLIB)
                }
            }
            if n == 0 { throw TVPackageMissing(description: "inflate failed") }
            if n < capacity || n == expected { return Array(out[0..<n]) }
            capacity *= 4
        }
        throw TVPackageMissing(description: "inflated data too large")
    }

    static func gunzip(_ data: Bytes) throws -> Bytes {
        guard data.count > 18, data[0] == 0x1F, data[1] == 0x8B, data[2] == 8 else {
            throw TVPackageMissing(description: "not gzip")
        }
        let flags = data[3]
        var p = 10
        if flags & 4 != 0 { p += 2 + data.le16(at: p) }
        if flags & 8 != 0 { while p < data.count, data[p] != 0 { p += 1 }; p += 1 }
        if flags & 16 != 0 { while p < data.count, data[p] != 0 { p += 1 }; p += 1 }
        if flags & 2 != 0 { p += 2 }
        guard p < data.count - 8 else { throw TVPackageMissing(description: "gzip header") }
        let size = Int(data.le32(at: data.count - 4))
        return try raw(Array(data[p..<(data.count - 8)]), expected: size)
    }
}

// MARK: - Android ikili XML

/// AndroidManifest.xml'in ikili biçiminden paket adı ve sürüm adı.
enum BinaryXML {
    struct Manifest {
        var package: String?
        var versionName: String?
    }

    static func manifest(_ data: Bytes) -> Manifest? {
        guard data.count > 8, data.le16(at: 0) == 0x0003 else { return nil }
        var strings: [String] = []
        var result = Manifest()
        var p = 8
        while p + 8 <= data.count {
            let type = data.le16(at: p), header = data.le16(at: p + 2)
            let size = Int(data.le32(at: p + 4))
            guard size > 0, p + size <= data.count else { break }
            if type == 0x0001 {
                strings = stringPool(Array(data[p..<(p + size)]))
            } else if type == 0x0102, p + header + 20 <= data.count {
                let body = p + header
                let element = Int(data.le32(at: body + 4))
                let attrStart = data.le16(at: body + 8), attrSize = data.le16(at: body + 10), attrCount = data.le16(at: body + 12)
                if element < strings.count, strings[element] == "manifest" {
                    for i in 0..<attrCount {
                        let a = body + attrStart + i * attrSize
                        guard a + 20 <= data.count else { break }
                        let name = Int(data.le32(at: a + 4)), raw = data.le32(at: a + 8)
                        let dataType = data[a + 15], value = Int(data.le32(at: a + 16))
                        let text: String? = raw != UInt32.max && Int(raw) < strings.count ? strings[Int(raw)]
                            : (dataType == 0x03 && value < strings.count ? strings[value] : nil)
                        guard name < strings.count else { continue }
                        if strings[name] == "package" { result.package = text }
                        if strings[name] == "versionName" { result.versionName = text }
                    }
                    return result
                }
            }
            p += size
        }
        return result.package == nil ? nil : result
    }

    private static func stringPool(_ chunk: Bytes) -> [String] {
        guard chunk.count >= 28 else { return [] }
        let count = Int(chunk.le32(at: 8)), flags = chunk.le32(at: 16), start = Int(chunk.le32(at: 20))
        let header = chunk.le16(at: 2)
        let utf8 = flags & 0x100 != 0
        var out: [String] = []
        for i in 0..<count {
            let offsetAt = header + i * 4
            guard offsetAt + 4 <= chunk.count else { break }
            var p = start + Int(chunk.le32(at: offsetAt))
            guard p < chunk.count else { out.append(""); continue }
            if utf8 {
                // karakter sayısı, sonra bayt sayısı (her biri 1–2 bayt)
                p += chunk[p] & 0x80 != 0 ? 2 : 1
                guard p < chunk.count else { out.append(""); continue }
                var n = Int(chunk[p])
                if n & 0x80 != 0, p + 1 < chunk.count { n = (n & 0x7F) << 8 | Int(chunk[p + 1]); p += 2 } else { p += 1 }
                out.append(p + n <= chunk.count ? String(decoding: chunk[p..<(p + n)], as: UTF8.self) : "")
            } else {
                guard p + 2 <= chunk.count else { out.append(""); continue }
                var n = chunk.le16(at: p)
                p += 2
                if n & 0x8000 != 0, p + 2 <= chunk.count { n = (n & 0x7FFF) << 16 | chunk.le16(at: p); p += 2 }
                var units: [UInt16] = []
                for k in 0..<n where p + 2 * k + 2 <= chunk.count { units.append(UInt16(chunk.le16(at: p + 2 * k))) }
                out.append(String(decoding: units, as: UTF16.self))
            }
        }
        return out
    }
}

// MARK: - webOS paketi (.ipk)

/// ipk: `ar` arşivi (debian-binary, control.tar.gz, data.tar.gz).
enum WebOSPackage {
    static func members(_ ar: Bytes) -> [String: Bytes] {
        guard ar.count > 8, Bytes(ar[0..<8]) == Bytes("!<arch>\n".utf8) else { return [:] }
        var out: [String: Bytes] = [:]
        var p = 8
        while p + 60 <= ar.count {
            let name = String(decoding: ar[p..<(p + 16)], as: UTF8.self).trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let size = Int(String(decoding: ar[(p + 48)..<(p + 58)], as: UTF8.self).trimmingCharacters(in: .whitespaces)) ?? 0
            let start = p + 60
            guard start + size <= ar.count else { break }
            out[name] = Array(ar[start..<(start + size)])
            p = start + size + (size % 2)
        }
        return out
    }

    /// tar içindeki dosyalar (yalnız düz dosyalar).
    static func tarFiles(_ tar: Bytes) -> [String: Bytes] {
        var out: [String: Bytes] = [:]
        var p = 0
        while p + 512 <= tar.count {
            let block = tar[p..<(p + 512)]
            if block.allSatisfy({ $0 == 0 }) { break }
            let name = String(decoding: block.prefix(100).prefix { $0 != 0 }, as: UTF8.self)
            let sizeText = String(decoding: tar[(p + 124)..<(p + 136)].prefix { $0 != 0 && $0 != 0x20 }, as: UTF8.self)
            let size = Int(sizeText, radix: 8) ?? 0
            let kind = tar[p + 156]
            let start = p + 512
            guard start + size <= tar.count else { break }
            if kind == 0x30 || kind == 0 { out[name.hasPrefix("./") ? String(name.dropFirst(2)) : name] = Array(tar[start..<(start + size)]) }
            p = start + (size + 511) / 512 * 512
        }
        return out
    }

    /// control dosyasının alanları (Package, Version …).
    static func control(_ ipk: Bytes) -> [String: String]? {
        guard let gz = members(ipk)["control.tar.gz"], let tar = try? Inflate.gunzip(gz),
              let file = tarFiles(tar)["control"] else { return nil }
        var fields: [String: String] = [:]
        for line in String(decoding: file, as: UTF8.self).split(whereSeparator: \.isNewline) {
            guard let colon = line.firstIndex(of: ":") else { continue }
            fields[String(line[..<colon])] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        return fields
    }
}
