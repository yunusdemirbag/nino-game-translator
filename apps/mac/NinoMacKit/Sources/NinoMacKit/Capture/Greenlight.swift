// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import CryptoKit
import Foundation

// Xbox: Greenlight (docs/yeni/mac/kaynaklar.md §4, kurulum.md §11). Nino Greenlight'ı yönetmez, gömmez;
// dışarıdan izler, isterse resmî GitHub sürümünden kurar ve açar.

public enum GreenlightFacts {
    public static let bundleID = "com.unknownskl.greenlight"
    public static let appName = "Greenlight.app"
    public static let latestReleaseURL = URL(string: "https://api.github.com/repos/unknownskl/greenlight/releases/latest")!
    public static let microsoftLink = URL(string: "https://www.microsoft.com/link")!
    public static let browserPlay = URL(string: "https://www.xbox.com/play/consoles")!

    /// Kurulu kopyanın arandığı yerler (önce sistemin Uygulamalar klasörü).
    public static func appLocations(home: URL) -> [URL] {
        [URL(fileURLWithPath: "/Applications").appendingPathComponent(appName),
         home.appendingPathComponent("Applications").appendingPathComponent(appName)]
    }

    public static func configFile(home: URL) -> URL {
        home.appendingPathComponent("Library/Application Support/greenlight-desktop/config.json")
    }

    /// Girişli mi: `user.tokenstore` (iç içe ya da düz anahtar) boş olmayan bir metin ("{}" değil) ya da nesne.
    /// Jetonların içeriğine bakılmaz.
    public static func isSignedIn(configData: Data) -> Bool {
        guard let root = try? JSONSerialization.jsonObject(with: configData) as? [String: Any] else { return false }
        func present(_ value: Any?) -> Bool {
            switch value {
            case let s as String:
                let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
                return !t.isEmpty && t != "{}"
            case is [String: Any]: return true
            default: return false
            }
        }
        if let user = root["user"] as? [String: Any], present(user["tokenstore"]) { return true }
        return present(root["user.tokenstore"])
    }

    /// Bağlantı listesinin ayrıntısından ana ekranın Xbox adımı.
    public static func xboxStep(_ link: XboxLink) -> XboxStep {
        if let p = link.installProgress { return .installing(progress: p) }
        switch link.step {
        case .done: return .ready
        case .start: return .waitingForWindow
        case .install, .signIn: return .notStarted
        }
    }
}

/// GitHub'ın "son sürüm" yanıtından kurulacak dosya.
public struct GreenlightAsset: Equatable, Sendable {
    public var name: String
    public var url: URL
    public var size: Int64?
    /// "sha256:<onaltılık>" özetinin onaltılık kısmı (verildiyse).
    public var sha256: String?

    public init(name: String, url: URL, size: Int64? = nil, sha256: String? = nil) {
        self.name = name
        self.url = url
        self.size = size
        self.sha256 = sha256
    }

    /// Adı `-universal.dmg` ile biten ilk dosya.
    public static func fromRelease(_ data: Data) -> GreenlightAsset? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let assets = root["assets"] as? [[String: Any]] else { return nil }
        for a in assets {
            guard let name = a["name"] as? String, name.hasSuffix("-universal.dmg"),
                  let link = a["browser_download_url"] as? String, let url = URL(string: link) else { continue }
            let size = (a["size"] as? NSNumber)?.int64Value
            var digest: String?
            if let d = a["digest"] as? String, d.hasPrefix("sha256:") { digest = String(d.dropFirst(7)).lowercased() }
            return GreenlightAsset(name: name, url: url, size: size, sha256: digest)
        }
        return nil
    }
}

/// Kurulumun dışarıya dokunan işleri. Testlerde sahtesi verilir (gerçek indirme yok).
public protocol GreenlightCarrier: Sendable {
    /// Son sürüm yanıtı (durum kodu, gövde).
    func latestRelease() async throws -> (status: Int, body: Data)
    /// Dosyayı indirir; `progress(indirilen, toplam?)`. İnen dosyanın yerini döner.
    func download(_ url: URL, progress: @escaping @Sendable (Int64, Int64?) -> Void) async throws -> URL
    /// Kalıbı görünmeden, salt okunur bağlar; bağlama noktasını döner.
    func attach(_ image: URL) async throws -> URL
    func detach(_ mountPoint: URL) async
}

public enum GreenlightInstallError: Error, Equatable, Sendable {
    case latestNotFound, downloadFailed, damaged, copyFailed

    /// Kullanıcıya gösterilen metin (`Capture.xcstrings`).
    public var message: String {
        switch self {
        case .latestNotFound: return CaptureText.string("capture.greenlight.error.latest")
        case .downloadFailed: return CaptureText.string("capture.greenlight.error.download")
        case .damaged: return CaptureText.string("capture.greenlight.error.damaged")
        case .copyFailed: return CaptureText.string("capture.greenlight.error.copy")
        }
    }
}

/// Tek tıkla kurulum (kaynaklar.md §4): son sürüm → indirme (%95'e kadar) → SHA-256 → kalıp → kopya → %100.
public struct GreenlightInstaller: Sendable {
    public let carrier: GreenlightCarrier
    /// Kopyalanacak yerler, sırayla (uygulamada /Applications, sonra ~/Applications).
    public let destinations: [URL]

    public init(carrier: GreenlightCarrier, destinations: [URL]) {
        self.carrier = carrier
        self.destinations = destinations
    }

    /// İlerleme: indirilen/boyut × 0,95, en çok 0,95.
    public static func downloadProgress(received: Int64, total: Int64?) -> Double? {
        guard let total, total > 0 else { return nil }
        return min(0.95, Double(received) / Double(total) * 0.95)
    }

    public static func sha256Hex(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Kurar; başarılıysa kopyalanan uygulamanın yerini döner. `progress` 0…1 (bilinmiyorsa nil).
    public func install(progress: @escaping @Sendable (Double?) -> Void) async throws -> URL {
        progress(0)
        let release: (status: Int, body: Data)
        do { release = try await carrier.latestRelease() } catch { throw GreenlightInstallError.latestNotFound }
        guard release.status == 200, let asset = GreenlightAsset.fromRelease(release.body) else {
            throw GreenlightInstallError.latestNotFound
        }
        let file: URL
        do {
            file = try await carrier.download(asset.url) { received, total in
                progress(Self.downloadProgress(received: received, total: total ?? asset.size))
            }
        } catch { throw GreenlightInstallError.downloadFailed }
        defer { try? FileManager.default.removeItem(at: file) }

        if let expected = asset.sha256 {
            guard let actual = try? Self.sha256Hex(of: file), actual == expected else { throw GreenlightInstallError.damaged }
        }

        let mount: URL
        do { mount = try await carrier.attach(file) } catch { throw GreenlightInstallError.copyFailed }
        let copied = Self.copyApp(from: mount, to: destinations)
        await carrier.detach(mount)
        guard let copied else { throw GreenlightInstallError.copyFailed }
        progress(1)
        return copied
    }

    /// Kalıptaki `.app`'i sırayla hedeflere kopyalar (varsa eskisi silinir); olmazsa nil.
    static func copyApp(from mount: URL, to destinations: [URL]) -> URL? {
        let fm = FileManager.default
        guard let app = (try? fm.contentsOfDirectory(at: mount, includingPropertiesForKeys: nil))?
            .first(where: { $0.pathExtension == "app" }) else { return nil }
        for folder in destinations {
            let target = folder.appendingPathComponent(GreenlightFacts.appName)
            do {
                try fm.createDirectory(at: folder, withIntermediateDirectories: true)
                if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
                try fm.copyItem(at: app, to: target)
                return target
            } catch {
                continue
            }
        }
        return nil
    }
}

/// Gerçek taşıyıcı: GitHub (URLSession) ve `hdiutil`.
public struct LiveGreenlightCarrier: GreenlightCarrier {
    public init() {}

    public func latestRelease() async throws -> (status: Int, body: Data) {
        var request = URLRequest(url: GreenlightFacts.latestReleaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        return ((response as? HTTPURLResponse)?.statusCode ?? 0, data)
    }

    public func download(_ url: URL, progress: @escaping @Sendable (Int64, Int64?) -> Void) async throws -> URL {
        let delegate = DownloadDelegate(progress: progress)
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                delegate.continuation = continuation
                session.downloadTask(with: url).resume()
            }
        } onCancel: {
            session.invalidateAndCancel()
        }
    }

    /// İndirme ilerlemesini bildirir, bitince dosyayı kalıcı geçici yere taşır.
    final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
        let progress: @Sendable (Int64, Int64?) -> Void
        var continuation: CheckedContinuation<URL, Error>?
        private let lock = NSLock()

        init(progress: @escaping @Sendable (Int64, Int64?) -> Void) { self.progress = progress }

        private func finish(_ result: Result<URL, Error>) {
            lock.lock()
            let c = continuation
            continuation = nil
            lock.unlock()
            c?.resume(with: result)
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                        totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
            progress(totalBytesWritten, totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : nil)
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
            guard let http = downloadTask.response as? HTTPURLResponse, http.statusCode == 200 else {
                finish(.failure(URLError(.badServerResponse)))
                return
            }
            let target = FileManager.default.temporaryDirectory.appendingPathComponent("greenlight-\(UUID().uuidString).dmg")
            do {
                try FileManager.default.moveItem(at: location, to: target)
                finish(.success(target))
            } catch {
                finish(.failure(error))
            }
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            if let error { finish(.failure(error)) }
        }
    }

    public func attach(_ image: URL) async throws -> URL {
        let mount = FileManager.default.temporaryDirectory.appendingPathComponent("greenlight-mount-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
        let status = try await Self.run("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", "-noautoopen", "-quiet",
                                                             "-mountpoint", mount.path, image.path])
        guard status == 0 else { throw CocoaError(.fileReadUnknown) }
        return mount
    }

    public func detach(_ mountPoint: URL) async {
        _ = try? await Self.run("/usr/bin/hdiutil", ["detach", "-quiet", "-force", mountPoint.path])
        try? FileManager.default.removeItem(at: mountPoint)
    }

    static func run(_ tool: String, _ arguments: [String]) async throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do { try process.run() } catch { continuation.resume(throwing: error) }
        }
    }
}
