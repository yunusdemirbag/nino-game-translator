// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// Gömülü yardımcının (`nino-tv-helper`) bir çıktı satırı (tv-kurulumu.md §8).
public enum TVHelperEvent: Equatable, Sendable {
    case progress(step: String)
    case login(url: URL)
    case approve
    case done(version: String, installed: Bool)
    /// Yeni uygulama yok, eski kimlikli uygulama kurulu (kurulmadı; `--keep-legacy 1` ile).
    case legacy(version: String)
    case found(hosts: [String])
    case error(code: String, message: String)

    /// Tek satırı ayrıştırır; JSON değilse ya da olay tanınmıyorsa nil.
    public static func parse(_ line: String) -> TVHelperEvent? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let o = (try? JSONSerialization.jsonObject(with: Data(trimmed.utf8))) as? [String: Any],
              let event = o["event"] as? String else { return nil }
        switch event {
        case "progress":
            return .progress(step: o["step"] as? String ?? "")
        case "login":
            guard let s = o["url"] as? String, let url = URL(string: s) else { return nil }
            return .login(url: url)
        case "approve":
            return .approve
        case "done":
            let version: String
            switch o["version"] {
            case let s as String: version = s
            case let n as NSNumber: version = n.stringValue
            default: version = ""
            }
            return .done(version: version, installed: (o["installed"] as? Bool) ?? false)
        case "legacy":
            switch o["version"] {
            case let s as String: return .legacy(version: s)
            case let n as NSNumber: return .legacy(version: n.stringValue)
            default: return .legacy(version: "")
            }
        case "found":
            return .found(hosts: (o["hosts"] as? [Any])?.compactMap { $0 as? String } ?? [])
        case "error":
            return .error(code: o["code"] as? String ?? "", message: o["message"] as? String ?? "")
        default:
            return nil
        }
    }

    /// Kartı "çalışıyor"a geçiren adımlar (sessiz sürüm denetimi gerçek kuruluma döndü).
    public static let workingSteps: Set<String> = ["signin", "certificate", "signing", "installing", "uninstalling", "play"]
}

/// Yardımcı komutunun sonucu.
public enum TVHelperOutcome: Equatable, Sendable {
    case done(version: String, installed: Bool)
    case legacy(version: String)
    case found(hosts: [String])
}

/// Yardımcıyı süreç olarak çalıştırır ve olaylarını okur.
public struct TVHelperClient: Sendable {
    public static let executableName = "nino-tv-helper"

    /// Yardımcının yeri; yoksa kurulum "kurulamadı", Samsung kurulumu gizli.
    public let executable: URL?
    let processes: TVProcessRunning
    let log: TVInstallLog
    let exitWait: TimeInterval

    public init(executable: URL?, processes: TVProcessRunning, log: TVInstallLog, exitWait: TimeInterval = 5) {
        self.executable = executable
        self.processes = processes
        self.log = log
        self.exitWait = exitWait
    }

    public var isAvailable: Bool { executable != nil }

    /// Uygulama paketinde yardımcıyı arar (MacOS, Helpers, Resources).
    public static func locate(in bundle: Bundle) -> URL? {
        let fm = FileManager.default
        var candidates: [URL] = []
        if let u = bundle.url(forAuxiliaryExecutable: executableName) { candidates.append(u) }
        let contents = bundle.bundleURL.appendingPathComponent("Contents")
        candidates.append(contents.appendingPathComponent("Helpers/\(executableName)"))
        candidates.append(contents.appendingPathComponent("MacOS/\(executableName)"))
        if let r = bundle.resourceURL { candidates.append(r.appendingPathComponent(executableName)) }
        return candidates.first { fm.isExecutableFile(atPath: $0.path) }
    }

    // MARK: Komutlar

    public static func androidScanArguments() -> [String] { ["android-scan"] }

    /// `keepLegacy`: yeni uygulama yokken eski kimlikli uygulama kuruluysa kurmaz, onu açar (`legacy` olayı).
    public static func androidInstallArguments(host: String, package: URL, version: String, keyDir: URL,
                                               keepLegacy: Bool = false) -> [String] {
        var a = ["android-install", "--host", host, "--package", package.path, "--version", version, "--key-dir", keyDir.path]
        if keepLegacy { a += ["--keep-legacy", "1"] }
        return a
    }

    public static func samsungInstallArguments(host: String, package: URL, version: String, profiles: URL,
                                               log: URL?, keepLegacy: Bool = false) -> [String] {
        var a = ["samsung-install", "--host", host, "--package", package.path, "--version", version,
                 "--profiles", profiles.path]
        if let log { a += ["--log", log.path] }
        if keepLegacy { a += ["--keep-legacy", "1"] }
        return a
    }

    /// `android-scan`: TCP 5555'i açık adresler. Hata olursa boş liste.
    public func androidScan() async -> [String] {
        do {
            if case let .found(hosts) = try await run(Self.androidScanArguments(), onEvent: { _ in }) { return hosts }
            return []
        } catch {
            return []
        }
    }

    /// Komutu çalıştırır. `onEvent` ilerleme, giriş ve onay olaylarını alır (sonuçtan sonra gelenler verilmez).
    /// Her çağrıya `--exit-with-input` eklenir; iş iptal edilince giriş kapatılır, süreç sonlandırılır.
    public func run(_ arguments: [String], onEvent: @escaping @Sendable (TVHelperEvent) -> Void) async throws -> TVHelperOutcome {
        let command = arguments.first ?? ""
        guard let executable else {
            log.write("\(command): \(TVInstallError.Problem.installFailed.rawValue): \(TVSetupText.helperMissing())")
            throw TVInstallError(.installFailed, reason: TVSetupText.helperMissing())
        }
        let process: TVRunningProcess
        do {
            process = try processes.start(executable, arguments: arguments + ["--exit-with-input"])
        } catch {
            log.write("\(command): start failed: \(error)")
            throw TVInstallError(.installFailed, reason: "\(error)")
        }
        return try await withTaskCancellationHandler {
            var outcome: Result<TVHelperOutcome, TVInstallError>?
            for await line in process.lines {
                guard outcome == nil, let event = TVHelperEvent.parse(line) else { continue }
                switch event {
                case let .done(v, installed): outcome = .success(.done(version: v, installed: installed))
                case let .legacy(v): outcome = .success(.legacy(version: v))
                case let .found(hosts): outcome = .success(.found(hosts: hosts))
                case let .error(code, message):
                    let problem = TVInstallError.problem(forHelperCode: code)
                    log.write("\(command): \(code.isEmpty ? problem.rawValue : code): \(message)")
                    outcome = .failure(TVInstallError(problem, reason: message.isEmpty ? code : message))
                default:
                    onEvent(event)
                }
            }
            let exit = await process.waitForExit(timeout: exitWait)
            let tail = process.errorTail()
            if !tail.isEmpty { log.write("\(command) stderr:\n" + String(tail.suffix(16 * 1024))) }
            if exit == nil { process.terminate() }
            switch outcome {
            case let .success(v)?: return v
            case let .failure(e)?: throw e
            case nil:
                let detail = TVSetupText.helperEndedWithoutResult(exitCode: exit, stderrTail: Self.lastLines(tail))
                log.write("\(command): \(TVInstallError.Problem.installFailed.rawValue): \(detail)")
                throw TVInstallError(.installFailed, reason: detail)
            }
        } onCancel: {
            process.closeInput()
            process.terminate()
        }
    }

    /// Hata çıktısının son 3 satırı, en çok 400 karakter.
    static func lastLines(_ text: String) -> String {
        let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let joined = lines.suffix(3).joined(separator: " | ")
        return joined.count > 400 ? String(joined.suffix(400)) : joined
    }
}
