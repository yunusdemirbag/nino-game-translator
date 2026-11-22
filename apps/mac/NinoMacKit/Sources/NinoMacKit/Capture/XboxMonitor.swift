// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import AppKit
import CoreGraphics
import Foundation

/// Xbox bağlantı listesinin bilgileri nereden okunur (testlerde sahte).
public struct XboxProbe: Sendable {
    public var appExists: @Sendable () -> Bool
    public var isRunning: @Sendable () -> Bool
    public var configData: @Sendable () -> Data?
    /// Ekrandaki pencerelerin (sahip adı, başlık) listesi; başlıklar Ekran Kaydı izni ister.
    public var windowTitles: @Sendable () -> [(owner: String, title: String)]

    public init(appExists: @escaping @Sendable () -> Bool, isRunning: @escaping @Sendable () -> Bool,
                configData: @escaping @Sendable () -> Data?,
                windowTitles: @escaping @Sendable () -> [(owner: String, title: String)]) {
        self.appExists = appExists
        self.isRunning = isRunning
        self.configData = configData
        self.windowTitles = windowTitles
    }

    /// Bu Mac.
    public static func live(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> XboxProbe {
        XboxProbe(
            appExists: { GreenlightFacts.appLocations(home: home).contains { FileManager.default.fileExists(atPath: $0.path) } },
            isRunning: { !NSRunningApplication.runningApplications(withBundleIdentifier: GreenlightFacts.bundleID).isEmpty },
            configData: { try? Data(contentsOf: GreenlightFacts.configFile(home: home)) },
            windowTitles: {
                guard let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID)
                    as? [[String: Any]] else { return [] }
                return list.compactMap { w in
                    guard let owner = w[kCGWindowOwnerName as String] as? String,
                          let title = w[kCGWindowName as String] as? String else { return nil }
                    return (owner, title)
                }
            })
    }

    /// Bağlantı listesinin güncel hâli (kurulum ilerlemesi ve hatası korunur).
    public func read(keeping old: XboxLink) -> XboxLink {
        var link = old
        link.greenlightInstalled = appExists()
        link.signedIn = configData().map(GreenlightFacts.isSignedIn(configData:)) ?? false
        link.streaming = isRunning() && windowTitles().contains { w in
            w.owner.lowercased().contains("greenlight") && WindowRules.isGreenlightStreamTitle(w.title)
        }
        return link
    }
}
