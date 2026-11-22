// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import CRemotePlay
import Foundation

/// C kütüphanesiyle ortak yardımcılar.
enum RemotePlayLib {
    private static let once: Void = { _ = chiaki_lib_init() }()

    static func initialize() { _ = once }

    static func message(_ code: ChiakiErrorCode) -> String {
        String(cString: chiaki_error_string(code))
    }
}

/// Remote Play hataları.
public enum RemotePlayError: Error, Equatable, CustomStringConvertible {
    case library(String)
    case badInput(String)
    case registrationCanceled
    /// Oturum yok ya da kapanmış (ör. şifre gönderirken).
    case notConnected
    case sessionEnded(reason: String)
    case timeout

    public var description: String {
        switch self {
        case let .library(m): return "Kütüphane hatası: \(m)"
        case let .badInput(m): return "Geçersiz bilgi: \(m)"
        case .registrationCanceled: return "Kayıt iptal edildi"
        case .notConnected: return "PS5 oturumu açık değil"
        case let .sessionEnded(r): return "Oturum kapandı: \(r)"
        case .timeout: return "Zaman aşımı"
        }
    }
}

/// Kütüphanenin kendi iş parçacıklarından gelen geri çağrıları işaretler.
/// Bu iş parçacıklarında oturumu beklemek (join) ya da kütüphane kilidini
/// yeniden istemek kilitlenmeye yol açar; işaretli iş parçacığında bu işler
/// arka kuyruğa bırakılır.
enum CallbackThread {
    private static let key: pthread_key_t = {
        var k = pthread_key_t()
        pthread_key_create(&k, nil)
        return k
    }()

    static var isCurrent: Bool { pthread_getspecific(key) != nil }

    static func run<T>(_ body: () throws -> T) rethrows -> T {
        let previous = pthread_getspecific(key)
        pthread_setspecific(key, UnsafeRawPointer(bitPattern: 1))
        defer { pthread_setspecific(key, previous) }
        return try body()
    }
}

/// C kütüphanesinin günlük satırlarını toplayan nesne.
final class RemotePlayLog: @unchecked Sendable {
    let pointer: UnsafeMutablePointer<ChiakiLog>
    private let lock = NSLock()
    private var lines: [String] = []
    var onLine: (@Sendable (String) -> Void)?

    init(mask: UInt32 = UInt32(CHIAKI_LOG_ERROR.rawValue | CHIAKI_LOG_WARNING.rawValue | CHIAKI_LOG_INFO.rawValue)) {
        pointer = .allocate(capacity: 1)
        chiaki_log_init(pointer, mask, { _, msg, user in
            guard let msg, let user else { return }
            let me = Unmanaged<RemotePlayLog>.fromOpaque(user).takeUnretainedValue()
            me.append(String(cString: msg))
        }, Unmanaged.passUnretained(self).toOpaque())
    }

    private func append(_ s: String) {
        lock.withLock {
            lines.append(s)
            if lines.count > 500 { lines.removeFirst(lines.count - 500) }
        }
        onLine?(s)
    }

    var recent: [String] { lock.withLock { lines } }

    deinit { pointer.deallocate() }
}

extension String {
    /// Sabit boyutlu C dizisini (char[N]) Swift metnine çevirir.
    init<T>(fixedCString tuple: T) {
        self = withUnsafeBytes(of: tuple) { raw in
            let bytes = raw.prefix { $0 != 0 }
            return String(decoding: bytes, as: UTF8.self)
        }
    }
}

/// Sabit boyutlu C dizisine bayt yazar (eksik kalan sıfırla doldurulur).
func writeFixed<T>(_ tuple: inout T, _ bytes: [UInt8]) {
    withUnsafeMutableBytes(of: &tuple) { raw in
        raw.initializeMemory(as: UInt8.self, repeating: 0)
        for (i, b) in bytes.prefix(raw.count).enumerated() { raw[i] = b }
    }
}

func readFixed<T>(_ tuple: T) -> [UInt8] {
    withUnsafeBytes(of: tuple) { Array($0) }
}
