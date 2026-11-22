// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// Dönen günlük dosyası (docs/yeni/mac/veri-uyumu.md §4, havuz-paketler.md §8).
///
/// Satır biçimi `[yyyy-MM-dd HH:mm:ss.SSS] <ileti>`. Yazma arka planda, sırayla yapılır.
/// Dosya sınırı geçince `<ad>.1`'e taşınır (eskisinin yerine). Yazılamazsa sessizce geçer.
public final class RotatingLog: @unchecked Sendable {
    public static let defaultLimit = 1_000_000

    public let url: URL
    public let limit: Int
    private let queue: DispatchQueue
    private let now: @Sendable () -> Date
    private let formatter: DateFormatter
    private var handle: FileHandle?
    private var size: Int = 0
    private let mirrorLock = NSLock()
    private var mirrorHandler: (@Sendable (Date, String) -> Void)?

    public init(url: URL, limit: Int = RotatingLog.defaultLimit, now: @escaping @Sendable () -> Date = Date.init) {
        self.url = url
        self.limit = limit
        self.now = now
        queue = DispatchQueue(label: "nino.log." + url.lastPathComponent)
        formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    }

    deinit { try? handle?.close() }

    public var rotatedURL: URL { url.appendingPathExtension("1") }

    /// Her satırın kopyası aynı zamanla (yalnız admin/debug yapısındaki hata ayıklama kaydı kurar; hızlı olmalı).
    public var mirror: (@Sendable (Date, String) -> Void)? {
        get { mirrorLock.withLock { mirrorHandler } }
        set { mirrorLock.withLock { mirrorHandler = newValue } }
    }

    public func write(_ message: String) {
        let date = now()
        mirror?(date, message)
        queue.async { [self] in
            let line = "[\(formatter.string(from: date))] \(message)\n"
            append(Data(line.utf8))
        }
    }

    /// Bekleyen yazmaların bitmesini bekler (kapanış ve testler).
    public func flush() {
        queue.sync { try? handle?.synchronize() }
    }

    private func append(_ data: Data) {
        guard openIfNeeded() else { return }
        if size > 0, size + data.count > limit { rotate() }
        guard openIfNeeded() else { return }
        do {
            try handle?.write(contentsOf: data)
            size += data.count
        } catch {
            try? handle?.close()
            handle = nil
        }
    }

    private func openIfNeeded() -> Bool {
        if handle != nil { return true }
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !fm.fileExists(atPath: url.path) { fm.createFile(atPath: url.path, contents: nil) }
            let h = try FileHandle(forWritingTo: url)
            size = Int(try h.seekToEnd())
            handle = h
            return true
        } catch {
            return false
        }
    }

    private func rotate() {
        try? handle?.close()
        handle = nil
        let fm = FileManager.default
        try? fm.removeItem(at: rotatedURL)
        try? fm.moveItem(at: url, to: rotatedURL)
        size = 0
    }

    /// Altyazı günlüğündeki alıntı: satırlar ` / ` ile birleşir, en çok 120 karakter
    /// (aşarsa 119 + `…`), çift tırnak içinde.
    public static func quote(_ text: String, limit: Int = 120) -> String {
        let joined = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " / ")
        let body = joined.count > limit ? String(joined.prefix(limit - 1)) + "…" : joined
        return "\"\(body)\""
    }
}
