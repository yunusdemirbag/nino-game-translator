// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// Uygulamanın veri ve günlük klasörleri: `Library/Application Support/Nino` ve `Library/Logs/Nino`.
/// Önceki sürümün eski adlı klasörü açılışta bir kez yeni ada taşınır. Taşıma olmazsa bu çalıştırmada eski klasör
/// kullanılır; bütün dosyalar yolu yalnız buradan alır, böylece hiçbir dosya iki klasöre bölünmez.
struct AppFolders: Equatable {
    let support: URL
    let logs: URL

    static let name = "Nino"

    /// Açılışta, hiçbir dosya açılmadan önce bir kez çağrılır.
    static func prepare(library: URL? = nil, fileManager: FileManager = .default) -> AppFolders {
        let lib = library ?? fileManager.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        let supportBase = lib.appendingPathComponent("Application Support", isDirectory: true)
        let logsBase = lib.appendingPathComponent("Logs", isDirectory: true)
        return AppFolders(support: resolve(in: supportBase, fileManager: fileManager),
                          logs: resolve(in: logsBase, fileManager: fileManager))
    }

    /// Bir kök için: yeni klasör doluysa o; boşsa ya da yoksa ve eskisi varsa eskisi taşınır.
    static func resolve(in base: URL, fileManager: FileManager = .default) -> URL {
        let new = base.appendingPathComponent(name, isDirectory: true)
        let old = base.appendingPathComponent(LegacyNames.folder, isDirectory: true)
        try? fileManager.createDirectory(at: base, withIntermediateDirectories: true)
        let oldExists = fileManager.fileExists(atPath: old.path)
        if fileManager.fileExists(atPath: new.path) {
            let items = ((try? fileManager.contentsOfDirectory(atPath: new.path)) ?? []).filter { $0 != ".DS_Store" }
            guard items.isEmpty, oldExists else { return new }
            do {
                try fileManager.removeItem(at: new)
                try fileManager.moveItem(at: old, to: new)
                return new
            } catch {
                return fileManager.fileExists(atPath: new.path) ? new : old
            }
        }
        if oldExists {
            do {
                try fileManager.moveItem(at: old, to: new)
                return new
            } catch {
                return old
            }
        }
        try? fileManager.createDirectory(at: new, withIntermediateDirectories: true)
        return new
    }

    var historyFile: URL { support.appendingPathComponent("history.json") }
}
