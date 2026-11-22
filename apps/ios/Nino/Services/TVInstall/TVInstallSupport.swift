// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// Kurulum sırasında ekranda yazan adım.
enum InstallStage: Equatable, Sendable {
    case connecting, reading, installing, uninstalling, launching
    /// Samsung
    case signIn, certificate, signing
    /// Android TV
    case pairing, approveOnTV, waitingForPlay
    /// LG
    case fetchingKey
}

/// Kurulum bitince: TV'deki sürüm ve gerçekten kurulup kurulmadığı (zaten güncelse false).
struct TVInstallOutcome: Equatable, Sendable {
    var version: String
    var installed: Bool
}

/// TV kurulumunun dosyaları: `Application Support/Nino/tv/` (kalicilik.md: tv/adb, tv/sdb, tv/samsung, tv/lg,
/// tv/tvinstall.log). İndirilen TV paketleri `tv/packages/` altında durur.
struct TVInstallFiles: Sendable {
    let root: URL

    init(support: URL) { root = support.appendingPathComponent("tv", isDirectory: true) }
    init(root: URL) { self.root = root }

    func folder(_ name: String) -> URL {
        let url = root.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    var adb: URL { folder("adb") }
    var sdb: URL { folder("sdb") }
    var samsung: URL { folder("samsung") }
    var lg: URL { folder("lg") }
    var packages: URL { folder("packages") }
    var logFile: URL { root.appendingPathComponent("tvinstall.log") }

    /// LG geliştirici modu anahtarının dosyası (adresteki harf/rakam/`._-` dışı `_`).
    func lgKeyFile(host: String) -> URL {
        let safe = String(host.trimmingCharacters(in: .whitespaces).map { c -> Character in
            c.isASCII && (c.isLetter || c.isNumber || "._-".contains(c)) ? c : "_"
        })
        return lg.appendingPathComponent(safe + ".key")
    }
}

/// Kurulum günlüğü: her adım ve TV'nin yanıtları (`yyyy-MM-dd HH:mm:ss satır`). 512 KB'yi geçince baştan başlar.
final class TVInstallLog: @unchecked Sendable {
    let file: URL
    private let lock = NSLock()
    private let stamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    init(file: URL) { self.file = file }

    func write(_ line: String) {
        lock.lock()
        defer { lock.unlock() }
        let text = Data("\(stamp.string(from: Date())) \(line)\n".utf8)
        let fm = FileManager.default
        try? fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let size = (try? fm.attributesOfItem(atPath: file.path))?[.size] as? Int, size > 512 * 1024 {
            try? fm.removeItem(at: file)
        }
        if let handle = try? FileHandle(forWritingTo: file) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: text)
            try? handle.close()
        } else {
            try? text.write(to: file)
        }
    }

    /// Çok satırlı TV yanıtlarını kısaltır.
    static func short(_ text: String, limit: Int = 600) -> String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.count <= limit ? t : String(t.prefix(limit)) + "…"
    }
}

/// Bloklayan kurulum kodunu arka planda çalıştırır; adımlar ana iş parçacığına iletilir.
func runOffMain<T: Sendable>(_ work: @escaping @Sendable (@escaping @Sendable (InstallStage) -> Void) throws -> T,
                             stage: @escaping @MainActor (InstallStage) -> Void) async throws -> T {
    try await Task.detached(priority: .userInitiated) {
        try work { s in Task { @MainActor in stage(s) } }
    }.value
}

/// Bloklayan HTTP isteği (kurulum iş parçacığından). 2xx değilse ya da yanıt yoksa hata.
enum BlockingHTTP {
    struct Failure: Error, CustomStringConvertible {
        let status: Int
        let body: Data
        let reason: String
        var description: String { status == 0 ? reason : "HTTP \(status): \(String(decoding: body.prefix(300), as: UTF8.self))" }
    }

    static func send(_ request: URLRequest, session: URLSession = .shared) throws -> Data {
        let done = DispatchSemaphore(value: 0)
        let box = LockedValue<(Data?, URLResponse?, Error?)>((nil, nil, nil))
        session.dataTask(with: request) { data, response, error in
            box.set((data, response, error))
            done.signal()
        }.resume()
        if done.wait(timeout: .now() + request.timeoutInterval + 5) == .timedOut {
            throw Failure(status: 0, body: Data(), reason: "no answer")
        }
        let (data, response, error) = box.get()
        if let error { throw Failure(status: 0, body: Data(), reason: error.localizedDescription) }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(status) else { throw Failure(status: status, body: data ?? Data(), reason: "") }
        return data ?? Data()
    }

    static func get(_ url: URL, timeout: TimeInterval) throws -> Data {
        var r = URLRequest(url: url)
        r.timeoutInterval = timeout
        return try send(r)
    }
}
