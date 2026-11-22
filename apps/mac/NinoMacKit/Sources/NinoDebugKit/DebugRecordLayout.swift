// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// Hata ayıklama kaydının klasör düzeni (yalnız admin/debug yapısı; `~/Library/Logs/<Nino>/debug-kayit/`).
///
/// Her akış kendi alt klasöründe, dosya adı başlangıç zamanıdır (Unix ms):
/// - açık parça `<başlangıç>.<uzantı>`, kapanmış parça `<başlangıç>-<bitiş>.<uzantı>`,
/// - tek anlık dosyalar (olay karesi, TV ekran görüntüsü) `<zaman>.<uzantı>`.
/// Video parçalarında kare zamanı = başlangıç + sunum zamanı (ms); ayrı indeks gerekmez.
/// `cikti/` (nino-debug çıktıları) ve `olcum.json` halka tampona girmez, hiç silinmez.
public enum DebugStream: String, CaseIterable, Sendable {
    /// PS5'ten gelen, Nino'nun okuduğu kare (okuma bölgesi ve kutular çizili), video.
    case ps5
    /// Mac uygulama penceresi, video.
    case mac
    /// Olay anlarında tam boy çizimli kare (JPEG).
    case olay
    /// Android TV ekran görüntüsü (adb `screencap -p`, PNG).
    case tv
    /// Altyazı günlüğü, Remote Play günlüğü ve durum olayları (JSONL).
    case gunluk
    /// TV'ye giden protokol mesajları (JSONL).
    case mesaj

    public var fileExtension: String {
        switch self {
        case .ps5, .mac: return "mov"
        case .olay: return "jpg"
        case .tv: return "png"
        case .gunluk, .mesaj: return "jsonl"
        }
    }

    /// Tek anlık dosya mı (bitiş zamanı = başlangıç)?
    public var isInstant: Bool { self == .olay || self == .tv }
}

public struct DebugRecordLayout: Sendable, Equatable {
    public static let folderName = "debug-kayit"
    public static let outputFolderName = "cikti"
    public static let measureFileName = "olcum.json"

    public let root: URL

    public init(root: URL) { self.root = root }

    /// `logsFolder` = `~/Library/Logs/Nino` (yayın) ya da `~/Library/Logs/Nino Dev` (deneme yapısı).
    public init(logsFolder: URL) { root = logsFolder.appendingPathComponent(Self.folderName, isDirectory: true) }

    public func folder(_ s: DebugStream) -> URL { root.appendingPathComponent(s.rawValue, isDirectory: true) }
    public var outputFolder: URL { root.appendingPathComponent(Self.outputFolderName, isDirectory: true) }
    public var measureFile: URL { root.appendingPathComponent(Self.measureFileName) }

    public func createFolders() {
        for s in DebugStream.allCases {
            try? FileManager.default.createDirectory(at: folder(s), withIntermediateDirectories: true)
        }
    }

    public func openFile(_ s: DebugStream, startMs: Int64) -> URL {
        folder(s).appendingPathComponent("\(startMs).\(s.fileExtension)")
    }

    public static func closedName(startMs: Int64, endMs: Int64, ext: String) -> String { "\(startMs)-\(endMs).\(ext)" }

    /// Dosya adından zamanlar: `123.mov` → (123, nil), `123-456.mov` → (123, 456). Uymayan ad nil.
    public static func parseName(_ name: String) -> (start: Int64, end: Int64?)? {
        guard let dot = name.lastIndex(of: ".") else { return nil }
        let stem = name[..<dot]
        let parts = stem.split(separator: "-", omittingEmptySubsequences: false)
        guard let first = parts.first, let start = Int64(first), start > 0 else { return nil }
        if parts.count == 1 { return (start, nil) }
        guard parts.count == 2, let end = Int64(parts[1]), end >= start else { return nil }
        return (start, end)
    }
}

/// Kayıttaki tek dosya.
public struct DebugRecordFile: Sendable, Equatable {
    public var stream: DebugStream
    public var url: URL
    public var startMs: Int64
    /// Kapanmış parçada adındaki bitiş; açık (ya da çökmeden kalmış) parçada değişme zamanı.
    public var endMs: Int64
    public var isOpen: Bool
    public var bytes: Int64

    public func overlaps(fromMs: Int64, toMs: Int64) -> Bool { startMs <= toMs && endMs >= fromMs }
}

/// Klasörü tarar: zaman damgası → dosya eşlemesi.
public enum DebugRecordIndex {
    public static func scan(_ layout: DebugRecordLayout, streams: [DebugStream] = DebugStream.allCases) -> [DebugRecordFile] {
        let fm = FileManager.default
        var out: [DebugRecordFile] = []
        for s in streams {
            let dir = layout.folder(s)
            guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { continue }
            for name in names where name.hasSuffix("." + s.fileExtension) {
                guard let t = DebugRecordLayout.parseName(name) else { continue }
                let url = dir.appendingPathComponent(name)
                let attrs = try? fm.attributesOfItem(atPath: url.path)
                let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
                let modified = (attrs?[.modificationDate] as? Date).map { Int64($0.timeIntervalSince1970 * 1000) }
                let end: Int64
                if let e = t.end { end = e } else if s.isInstant { end = t.start } else { end = max(t.start, modified ?? t.start) }
                out.append(DebugRecordFile(stream: s, url: url, startMs: t.start, endMs: end,
                                           isOpen: t.end == nil && !s.isInstant, bytes: size))
            }
        }
        return out.sorted { ($0.startMs, $0.stream.rawValue) < ($1.startMs, $1.stream.rawValue) }
    }

    public static func files(_ layout: DebugRecordLayout, fromMs: Int64, toMs: Int64,
                             streams: [DebugStream] = DebugStream.allCases) -> [DebugRecordFile] {
        scan(layout, streams: streams).filter { $0.overlaps(fromMs: fromMs, toMs: toMs) }
    }
}

/// Halka tampon: akış klasörlerinin toplamı sınırı geçince en eski dosyalar silinir.
public enum DebugRing {
    public static let defaultLimit: Int64 = 2 * 1024 * 1024 * 1024

    /// Silinecekler (en eskiden başlayarak; yazılmakta olan dosyalar korunur).
    public static func toDelete(_ files: [DebugRecordFile], limit: Int64, protected: Set<String> = []) -> [DebugRecordFile] {
        var total = files.reduce(Int64(0)) { $0 + $1.bytes }
        guard total > limit else { return [] }
        var out: [DebugRecordFile] = []
        for f in files.sorted(by: { $0.startMs < $1.startMs }) where !protected.contains(f.url.lastPathComponent) {
            guard total > limit else { break }
            out.append(f)
            total -= f.bytes
        }
        return out
    }

    /// Tek klasörlük halka (ör. `frames/video/`): adı sıralı dosyaların en eskisinden başlayarak, toplam sınırın
    /// altına inene dek siler (`protected` adlar ve alt klasörler korunur). Silinen bayt döner.
    @discardableResult
    public static func pruneFolder(_ folder: URL, limit: Int64, protected: Set<String> = []) -> Int64 {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: folder.path) else { return 0 }
        var files: [(String, Int64)] = []
        for n in names.sorted() {
            var isDir: ObjCBool = false
            let path = folder.appendingPathComponent(n).path
            guard fm.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue else { continue }
            files.append((n, ((try? fm.attributesOfItem(atPath: path)[.size]) as? NSNumber)?.int64Value ?? 0))
        }
        var total = files.reduce(Int64(0)) { $0 + $1.1 }
        var freed: Int64 = 0
        for (n, size) in files where total > limit && !protected.contains(n) {
            if (try? fm.removeItem(at: folder.appendingPathComponent(n))) != nil {
                total -= size
                freed += size
            }
        }
        return freed
    }

    /// Siler; silinen bayt döner.
    @discardableResult
    public static func prune(_ layout: DebugRecordLayout, limit: Int64, protected: Set<String> = []) -> Int64 {
        let victims = toDelete(DebugRecordIndex.scan(layout), limit: limit, protected: protected)
        var freed: Int64 = 0
        for f in victims where (try? FileManager.default.removeItem(at: f.url)) != nil { freed += f.bytes }
        return freed
    }
}
