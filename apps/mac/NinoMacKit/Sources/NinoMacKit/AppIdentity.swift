// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// Uygulamanın kimliği ve kullanıcı verisinin yeri.
///
/// Yayın yapısı kullanıcının gerçek verisini kullanır (`com.ninotranslator.mac`,
/// `Application Support/Nino`, aynı Anahtarlık hizmeti). Deneme yapısı ayrı bir
/// kimlik ve ayrı bir klasörle çalışır; kurulu Nino'nun verisine dokunmaz.
public struct AppIdentity: Sendable, Equatable {
    public enum Flavor: String, Sendable { case release, development, testing }

    public let flavor: Flavor
    /// UserDefaults alanı (paket kimliği).
    public let defaultsDomain: String
    /// Anahtarlık hizmet adı.
    public let keychainService: String
    /// `~/Library/Application Support/<ad>` ve `~/Library/Logs/<ad>`.
    public let folderName: String

    public static let release = AppIdentity(flavor: .release, defaultsDomain: "com.ninotranslator.mac",
                                            keychainService: "com.ninotranslator.mac", folderName: "Nino")
    public static let development = AppIdentity(flavor: .development, defaultsDomain: "com.ninotranslator.mac.dev",
                                                keychainService: "com.ninotranslator.mac.dev", folderName: "Nino Dev")

    /// Çalışan uygulamanın kimliğine göre seçilir: `.dev` ile biten paket deneme yapısıdır.
    public static func current(bundleID: String? = Bundle.main.bundleIdentifier) -> AppIdentity {
        if let bundleID, bundleID.hasSuffix(".dev") { return .development }
        if bundleID == release.defaultsDomain { return .release }
        return .development
    }

    public init(flavor: Flavor, defaultsDomain: String, keychainService: String, folderName: String) {
        self.flavor = flavor
        self.defaultsDomain = defaultsDomain
        self.keychainService = keychainService
        self.folderName = folderName
    }

    public var supportFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(folderName, isDirectory: true)
    }

    public var logsFolder: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent(folderName, isDirectory: true)
    }
}
