// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import AppKit
import Foundation

/// Kullanıcı verisinin klasörleri (docs/yeni/mac/veri-uyumu.md §3, §4) ve içlerindeki dosyaların yolları.
public struct DataFolder: Equatable, Sendable {
    /// `Application Support/Nino` (ya da bu açılışta kullanılan eski klasör).
    public let support: URL
    /// `Logs/Nino` (ya da eski günlük klasörü).
    public let logs: URL

    public init(support: URL, logs: URL) {
        self.support = support
        self.logs = logs
    }

    // MARK: Veri klasöründeki dosyalar

    public var historyFile: URL { support.appendingPathComponent("history.json") }
    public var subtitleLayoutFile: URL { support.appendingPathComponent("subtitle-layout.json") }
    public func phoneMemoryFile(language: String) -> URL {
        support.appendingPathComponent("phone-memory-\(language).json")
    }
    public var incidentsFile: URL { support.appendingPathComponent("sorunlar.json") }
    public var poolFolder: URL { support.appendingPathComponent("pool", isDirectory: true) }
    public var poolStateFile: URL { poolFolder.appendingPathComponent("state.json") }
    public var translationsFolder: URL { support.appendingPathComponent("Translations", isDirectory: true) }
    public var packsFolder: URL { support.appendingPathComponent("packs", isDirectory: true) }
    public var glossaryFolder: URL { support.appendingPathComponent("Glossary", isDirectory: true) }
    public var coversFolder: URL { support.appendingPathComponent("Covers", isDirectory: true) }
    /// Android TV yardımcısının anahtarı. Yalnız yol: bu katman okumaz, silmez (silinirse TV yeniden izin sorar).
    public var adbFolder: URL { support.appendingPathComponent("adb", isDirectory: true) }
    public var adbKeyFile: URL { adbFolder.appendingPathComponent("adbkey") }
    public var samsungFolder: URL { support.appendingPathComponent("samsung", isDirectory: true) }

    // MARK: Günlükler

    public var subtitleLog: URL { logs.appendingPathComponent("altyazi.log") }
    public var remotePlayLog: URL { logs.appendingPathComponent("remoteplay.log") }
    public var tvInstallLog: URL { logs.appendingPathComponent("tvinstall.log") }
    public var framesFolder: URL { logs.appendingPathComponent("frames", isDirectory: true) }
}

// MARK: - Karar

/// Bu Mac'te olan bitenler (testte elle verilir).
public struct LegacyEnvironment: Sendable {
    /// Eski uygulama kurulu ya da açık mı.
    public var legacyAppPresent: @Sendable () -> Bool
    /// Nino'nun başka bir kopyası açık mı.
    public var otherInstanceRunning: @Sendable () -> Bool

    public init(legacyAppPresent: @escaping @Sendable () -> Bool,
                otherInstanceRunning: @escaping @Sendable () -> Bool) {
        self.legacyAppPresent = legacyAppPresent
        self.otherInstanceRunning = otherInstanceRunning
    }

    /// Gerçek Mac: eski uygulama paket kimliğiyle ve olağan kurulum yerlerinde aranır.
    public static func live(home: URL, ownBundleID: String?) -> LegacyEnvironment {
        LegacyEnvironment(
            legacyAppPresent: {
                let id = LegacyNames.bundleID
                if !NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty { return true }
                if NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) != nil { return true }
                let fm = FileManager.default
                return fm.fileExists(atPath: LegacyNames.systemInstallPath)
                    || fm.fileExists(atPath: home.appendingPathComponent(LegacyNames.userInstallPath).path)
            },
            otherInstanceRunning: {
                guard let ownBundleID else { return false }
                let me = ProcessInfo.processInfo.processIdentifier
                return NSRunningApplication.runningApplications(withBundleIdentifier: ownBundleID)
                    .contains { $0.processIdentifier != me }
            })
    }
}

/// Klasör kararını verir; dosya sistemi kökleri dışarıdan gelir, testte geçici klasör verilir.
public struct DataFolderResolver {
    public enum Outcome: Equatable, Sendable {
        /// Yeni klasör zaten doluydu.
        case existing
        /// Hiçbiri yoktu (ya da taşıma yapılmaz); yenisi açıldı.
        case created
        /// Eski klasör yeniden adlandırıldı.
        case moved
        /// Eski klasör kopyalandı (eski uygulama hâlâ burada).
        case copied
        /// Günlükler eski uygulamayla ortak; yeni günlük klasörü boş açıldı.
        case freshBesideLegacy
        /// Bu açılışta eski klasör kullanılıyor (iş sonraki açılışa kaldı ya da hata).
        case usingLegacy(reason: String)
    }

    public struct Result: Equatable, Sendable {
        public var folder: DataFolder
        public var support: Outcome
        public var logs: Outcome
        /// `remoteplay.log`'a yazılacak açılış notları.
        public var notes: [String]
    }

    public let folderName: String
    public let applicationSupportRoot: URL
    public let logsRoot: URL
    /// Yalnız yayın kimliğinde ve kapsız (App Store dışı) yapıda açılır.
    public let migrationAllowed: Bool
    public let environment: LegacyEnvironment
    public let copyNote: String

    public init(folderName: String, applicationSupportRoot: URL, logsRoot: URL, migrationAllowed: Bool,
                environment: LegacyEnvironment,
                copyNote: String = "Bu klasörün verisi eski klasörden kopyalandı.\n") {
        self.folderName = folderName
        self.applicationSupportRoot = applicationSupportRoot
        self.logsRoot = logsRoot
        self.migrationAllowed = migrationAllowed
        self.environment = environment
        self.copyNote = copyNote
    }

    public func resolve() -> Result {
        var notes: [String] = []
        let fm = FileManager.default
        // Eski uygulamanın varlığı bir kez sorulur, iki klasörde de aynı cevap kullanılır.
        let legacyPresent = migrationAllowed ? environment.legacyAppPresent() : false
        let otherRunning = migrationAllowed ? environment.otherInstanceRunning() : false

        let (support, supportOutcome) = decide(root: applicationSupportRoot, kind: .support, legacyPresent: legacyPresent,
                                               otherRunning: otherRunning, fm: fm, notes: &notes)
        let (logs, logsOutcome) = decide(root: logsRoot, kind: .logs, legacyPresent: legacyPresent,
                                         otherRunning: otherRunning, fm: fm, notes: &notes)
        return Result(folder: DataFolder(support: support, logs: logs), support: supportOutcome, logs: logsOutcome,
                      notes: notes)
    }

    private enum Kind: String { case support = "veri", logs = "günlük" }

    private func decide(root: URL, kind: Kind, legacyPresent: Bool, otherRunning: Bool, fm: FileManager,
                        notes: inout [String]) -> (URL, Outcome) {
        let target = root.appendingPathComponent(folderName, isDirectory: true)
        let legacyName = LegacyNames.folderName
        let legacy = URL(fileURLWithPath: legacyName, isDirectory: true, relativeTo: root).absoluteURL

        if migrationAllowed { removeStaleCopies(in: root, fm: fm) }

        let targetExists = isDirectory(target, fm)
        if targetExists, !isEmptyFolder(target, fm) { return (target, .existing) }

        guard migrationAllowed, !legacyName.isEmpty, isDirectory(legacy, fm) else {
            return ensure(target, fm: fm, notes: &notes, kind: kind)
        }

        if otherRunning {
            notes.append("\(kind.rawValue) klasörü: Nino'nun başka bir kopyası açık, taşıma sonraki açılışa kaldı")
            return (legacy, .usingLegacy(reason: "otherInstance"))
        }

        // Boş yeni klasör taşımadan önce silinir.
        if targetExists {
            do { try fm.removeItem(at: target) } catch {
                notes.append("\(kind.rawValue) klasörü: boş yeni klasör silinemedi (\(error.localizedDescription)); eski klasör kullanılıyor")
                return (legacy, .usingLegacy(reason: "emptyTargetStuck"))
            }
        }

        if legacyPresent {
            if kind == .logs {
                // Günlükler eski uygulamayla ortaksa kopyalanmaz.
                let (url, outcome) = ensure(target, fm: fm, notes: &notes, kind: kind)
                if outcome == .created {
                    notes.append("günlük klasörü: eski uygulama burada, günlükler kopyalanmadı; yeni klasör boş açıldı")
                    return (url, .freshBesideLegacy)
                }
                return (url, outcome)
            }
            return copy(legacy, to: target, root: root, fm: fm, notes: &notes, kind: kind)
        }

        do {
            try fm.moveItem(at: legacy, to: target)
            notes.append("\(kind.rawValue) klasörü eski addan taşındı")
            return (target, .moved)
        } catch {
            // Yeni klasör açılmaz: yoksa sonraki açılış boş klasörü seçerdi.
            notes.append("\(kind.rawValue) klasörü taşınamadı (\(error.localizedDescription)); eski klasör kullanılıyor")
            return (legacy, .usingLegacy(reason: "moveFailed"))
        }
    }

    private func copy(_ legacy: URL, to target: URL, root: URL, fm: FileManager, notes: inout [String],
                      kind: Kind) -> (URL, Outcome) {
        let temp = root.appendingPathComponent("\(folderName).kopya-\(UUID().uuidString)", isDirectory: true)
        do {
            try fm.copyItem(at: legacy, to: temp)
            try Data(copyNote.utf8).write(to: temp.appendingPathComponent("kopyalandi.txt"))
            try fm.moveItem(at: temp, to: target)
            notes.append("\(kind.rawValue) klasörü eski uygulama hâlâ kurulu olduğu için kopyalandı")
            return (target, .copied)
        } catch {
            try? fm.removeItem(at: temp)
            notes.append("\(kind.rawValue) klasörü kopyalanamadı (\(error.localizedDescription)); eski klasör kullanılıyor")
            return (legacy, .usingLegacy(reason: "copyFailed"))
        }
    }

    private func ensure(_ target: URL, fm: FileManager, notes: inout [String], kind: Kind) -> (URL, Outcome) {
        if isDirectory(target, fm) { return (target, .existing) }
        do {
            try fm.createDirectory(at: target, withIntermediateDirectories: true)
        } catch {
            notes.append("\(kind.rawValue) klasörü açılamadı (\(error.localizedDescription))")
        }
        return (target, .created)
    }

    /// Yarıda kalmış eski kopyalar (`Nino.kopya-*`).
    private func removeStaleCopies(in root: URL, fm: FileManager) {
        let prefix = "\(folderName).kopya-"
        guard let items = try? fm.contentsOfDirectory(atPath: root.path) else { return }
        for name in items where name.hasPrefix(prefix) {
            try? fm.removeItem(at: root.appendingPathComponent(name, isDirectory: true))
        }
    }

    private func isDirectory(_ url: URL, _ fm: FileManager) -> Bool {
        var dir: ObjCBool = false
        return fm.fileExists(atPath: url.path, isDirectory: &dir) && dir.boolValue
    }

    /// `.DS_Store` dışında bir şey yoksa boş sayılır.
    private func isEmptyFolder(_ url: URL, _ fm: FileManager) -> Bool {
        let items = (try? fm.contentsOfDirectory(atPath: url.path)) ?? []
        return items.allSatisfy { $0 == ".DS_Store" }
    }
}

// MARK: - Süreç başına bir kez

public extension DataFolder {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cached: [String: DataFolderResolver.Result] = [:]

    /// Uygulamanın klasörleri. Karar süreç başına bir kez verilir; ilk çağrıda taşıma/kopya yapılabilir.
    /// Testler bunu çağırmaz; `DataFolderResolver`'ı geçici köklerle kullanır.
    static func resolved(identity: AppIdentity) -> DataFolderResolver.Result {
        lock.lock(); defer { lock.unlock() }
        if let hit = cached[identity.folderName] { return hit }
        let fm = FileManager.default
        let sandboxed = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
        let resolver = DataFolderResolver(
            folderName: identity.folderName,
            applicationSupportRoot: fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0],
            logsRoot: fm.urls(for: .libraryDirectory, in: .userDomainMask)[0].appendingPathComponent("Logs", isDirectory: true),
            migrationAllowed: identity.flavor == .release && !sandboxed,
            environment: .live(home: fm.homeDirectoryForCurrentUser, ownBundleID: Bundle.main.bundleIdentifier))
        let result = resolver.resolve()
        cached[identity.folderName] = result
        return result
    }
}
