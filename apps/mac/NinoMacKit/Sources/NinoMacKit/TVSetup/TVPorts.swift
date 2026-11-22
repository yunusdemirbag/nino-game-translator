// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

// TV kurulumunun dış dünyaya açılan kapıları (docs/yeni/mac/tv-kurulumu.md).
// Ağ, süreç, saat ve günlük birer protokolün arkasındadır; birim testleri sahtesini verir.
// Gerçek uygulamalar `TVLiveTransports.swift` dosyasında.

// MARK: HTTP

public struct TVHTTPResponse: Equatable, Sendable {
    public var status: Int
    public var body: Data
    public init(status: Int, body: Data) {
        self.status = status
        self.body = body
    }

    public var text: String { String(decoding: body, as: UTF8.self) }
}

public protocol TVHTTP: Sendable {
    /// Düz GET. Bağlantı kurulamazsa ya da süre dolarsa hata fırlatır.
    func get(_ url: URL, timeout: TimeInterval) async throws -> TVHTTPResponse
}

// MARK: TCP kapısı

public protocol TVPortProbe: Sendable {
    /// Bu süre içinde TCP bağlantısı kabul ediliyor mu.
    func isOpen(host: String, port: UInt16, timeout: TimeInterval) async -> Bool
}

// MARK: SSDP

public struct SSDPTarget: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        /// 239.255.255.250:1900'e, bu yerel adresin bağdaştırıcısından (çok noktaya yayın arayüzü).
        case multicast(localAddress: String)
        /// Tek bir adrese (yedek taramada her adrese ayrı istek).
        case unicast(host: String)
    }
    public var kind: Kind
    public init(_ kind: Kind) { self.kind = kind }
}

public struct SSDPResponse: Equatable, Sendable {
    /// Başlık adları BÜYÜK harfle.
    public var headers: [String: String]
    /// Yanıtı gönderen adres.
    public var sender: String
    public init(headers: [String: String], sender: String) {
        self.headers = headers
        self.sender = sender
    }

    /// Ham yanıt metnini başlıklara ayırır.
    public static func parse(_ text: String, sender: String) -> SSDPResponse {
        var headers: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline).dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).uppercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { headers[name] = value }
        }
        return SSDPResponse(headers: headers, sender: sender)
    }
}

public protocol SSDPTransport: Sendable {
    /// İsteği her hedefe `sendCount` kez gönderir ve `duration` boyunca gelen yanıtları toplar.
    func search(_ request: String, targets: [SSDPTarget], sendCount: Int, duration: TimeInterval) async -> [SSDPResponse]
}

// MARK: WebSocket

public protocol TVWebSocket: AnyObject, Sendable {
    func send(_ text: String) async throws
    /// Bir sonraki metin iletisi. Bağlantı kapanınca hata fırlatır.
    func receive() async throws -> String
    func close()
}

public protocol TVWebSocketConnecting: Sendable {
    /// Bağlantıyı açar. `trustedHost` için kendinden imzalı sertifika kabul edilir (yalnız o adres).
    /// Çerezsiz oturum.
    func connect(url: URL, trustedHost: String, timeout: TimeInterval) async throws -> TVWebSocket
}

// MARK: Ağ bağdaştırıcıları

public struct NetworkInterface: Equatable, Sendable {
    public var name: String
    public var address: String
    public var netmask: String
    public var isUp: Bool
    public var isLoopback: Bool
    public var isPointToPoint: Bool

    public init(name: String, address: String, netmask: String = "255.255.255.0", isUp: Bool = true,
                isLoopback: Bool = false, isPointToPoint: Bool = false) {
        self.name = name
        self.address = address
        self.netmask = netmask
        self.isUp = isUp
        self.isLoopback = isLoopback
        self.isPointToPoint = isPointToPoint
    }
}

public protocol NetworkInterfaceListing: Sendable {
    /// Açık IPv4 bağdaştırıcıları.
    func interfaces() -> [NetworkInterface]
    /// Hedefe giden yolun kaynak adresi: UDP soketi "bağlanır" (paket gönderilmez), yerel uç okunur.
    func sourceAddress(toward host: String, port: UInt16) -> String?
}

// MARK: Süreç

public struct TVProcessResult: Equatable, Sendable {
    public var exitCode: Int32
    public var stdout: Data
    public var stderr: Data
    public var timedOut: Bool
    public init(exitCode: Int32, stdout: Data = Data(), stderr: Data = Data(), timedOut: Bool = false) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.timedOut = timedOut
    }

    public var output: String { String(decoding: stdout, as: UTF8.self) }
    public var errorOutput: String { String(decoding: stderr, as: UTF8.self) }
}

/// Uzun süren, satır satır çıktı veren süreç (gömülü yardımcı).
public protocol TVRunningProcess: AnyObject, Sendable {
    /// Standart çıktının satırları; çıktı kapanınca biter.
    var lines: AsyncStream<String> { get }
    /// Şimdiye kadarki hata çıktısı (son 16 KB).
    func errorTail() -> String
    /// Standart girişi kapatır (yardımcı bunu görünce kendini iptal eder).
    func closeInput()
    func terminate()
    /// Bu süre içinde biterse çıkış kodu; bitmezse nil.
    func waitForExit(timeout: TimeInterval) async -> Int32?
}

public protocol TVProcessRunning: Sendable {
    /// Süreci çalıştırır, bitmesini bekler. Süre dolarsa süreç kapatılır, `timedOut` doğru döner.
    func run(_ executable: URL, arguments: [String], input: Data?, timeout: TimeInterval) async throws -> TVProcessResult
    /// Süreci başlatır; standart giriş açık tutulur.
    func start(_ executable: URL, arguments: [String]) throws -> TVRunningProcess
}

// MARK: Saat

public protocol TVClock: Sendable {
    func now() -> Date
    func sleep(_ seconds: TimeInterval) async throws
}

public struct SystemTVClock: TVClock {
    public init() {}
    public func now() -> Date { Date() }
    public func sleep(_ seconds: TimeInterval) async throws {
        try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
    }
}

// MARK: Kurulum günlüğü

/// `~/Library/Logs/Nino/tvinstall.log`: satırlar `[yyyy-MM-dd HH:mm:ss] …` (en_US saat biçimi).
public final class TVInstallLog: @unchecked Sendable {
    /// Hata iletilerinde kullanıcıya gösterilen yol.
    public let path: String
    private let sink: @Sendable (String) -> Void

    public init(path: String, write: @escaping @Sendable (String) -> Void) {
        self.path = path
        self.sink = write
    }

    public func write(_ line: String) { sink(line) }

    public static let discard = TVInstallLog(path: "", write: { _ in })

    /// Dosyaya ekleyen günlük.
    public static func file(_ url: URL, now: @escaping @Sendable () -> Date = Date.init) -> TVInstallLog {
        let queue = DispatchQueue(label: "nino.tvinstall.log")
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return TVInstallLog(path: url.path) { message in
            let date = now()
            queue.async {
                let line = "[\(formatter.string(from: date))] \(message)\n"
                let fm = FileManager.default
                try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                if !fm.fileExists(atPath: url.path) { fm.createFile(atPath: url.path, contents: nil) }
                guard let h = try? FileHandle(forWritingTo: url) else { return }
                defer { try? h.close() }
                _ = try? h.seekToEnd()
                try? h.write(contentsOf: Data(line.utf8))
            }
        }
    }
}
