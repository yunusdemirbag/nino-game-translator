// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// Nino'nun veri klasörü ve içindeki yerler.
public struct NinoDirectories: Sendable, Equatable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    /// Varsayılan: Application Support/Nino (iOS'ta uygulamanın kendi kabında).
    public static func standard(fileManager: FileManager = .default) throws -> NinoDirectories {
        let base = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return NinoDirectories(root: base.appendingPathComponent("Nino", isDirectory: true))
    }

    public var settingsFile: URL { root.appendingPathComponent("settings.json") }
    public var cacheDirectory: URL { root.appendingPathComponent("cache", isDirectory: true) }
    public var translationCacheFile: URL { cacheDirectory.appendingPathComponent("translations.json") }
    public var packsDirectory: URL { root.appendingPathComponent("packs", isDirectory: true) }
    public var logsDirectory: URL { root.appendingPathComponent("logs", isDirectory: true) }

    /// Klasörleri oluşturur (varsa dokunmaz).
    public func prepare(fileManager: FileManager = .default) throws {
        for dir in [root, cacheDirectory, packsDirectory, logsDirectory] {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }
}
