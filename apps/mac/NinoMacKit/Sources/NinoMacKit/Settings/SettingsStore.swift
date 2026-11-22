// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// UserDefaults'taki küçük kayıtların adları (docs/yeni/mac/veri-uyumu.md §1.1).
public enum DefaultsKey {
    public static let settings = "settings"
    public static let adminMode = "ninoAdminMode"
    public static let lastGamePoolFirst = "ninoLastGamePoolFirst"
    public static let captureCardID = "NinoCaptureCardID"
    public static let resumeAfterRelaunch = "ninoResumeAfterRelaunch"
    public static let downloadTotal = "ninoDownloadTotal"
    public static let freeNavigation = "NinoFreeNav"
    public static func devSessionRenewed(host: String) -> String {
        "devSessionRenewed." + host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

/// Ayarları okur ve yazar. Her değişiklikte bütün nesne yeniden yazılır.
public final class SettingsStore: @unchecked Sendable {
    public let defaults: UserDefaults
    private let lock = NSLock()

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// Kimliğe göre doğru UserDefaults alanı.
    public convenience init(identity: AppIdentity) {
        let defaults = Bundle.main.bundleIdentifier == identity.defaultsDomain
            ? UserDefaults.standard
            : (UserDefaults(suiteName: identity.defaultsDomain) ?? .standard)
        self.init(defaults: defaults)
    }

    /// Ayarları okur, düzeltmeleri uygular; bir şey düzeldiyse hemen geri yazar.
    public func load(preferredLanguages: [String] = Locale.preferredLanguages) -> MacSettings {
        lock.lock(); defer { lock.unlock() }
        guard let data = defaults.data(forKey: DefaultsKey.settings), var settings = MacSettings.decode(data) else {
            var fresh = MacSettings.fresh(preferredLanguages: preferredLanguages)
            fresh.normalize()
            return fresh
        }
        if settings.normalize() { defaults.set(settings.encoded(), forKey: DefaultsKey.settings) }
        return settings
    }

    public func save(_ settings: MacSettings) {
        lock.lock(); defer { lock.unlock() }
        defaults.set(settings.encoded(), forKey: DefaultsKey.settings)
    }

    public var adminMode: Bool { defaults.bool(forKey: DefaultsKey.adminMode) }

    public var lastGamePoolFirst: Bool {
        get { defaults.bool(forKey: DefaultsKey.lastGamePoolFirst) }
        set { defaults.set(newValue, forKey: DefaultsKey.lastGamePoolFirst) }
    }

    public var captureCardID: String? {
        get { defaults.string(forKey: DefaultsKey.captureCardID) }
        set { defaults.set(newValue, forKey: DefaultsKey.captureCardID) }
    }

    public var downloadTotal: Int {
        get { defaults.integer(forKey: DefaultsKey.downloadTotal) }
        set { defaults.set(newValue, forKey: DefaultsKey.downloadTotal) }
    }
}
