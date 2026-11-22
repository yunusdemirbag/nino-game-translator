// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// Gömülü yardımcının (`nino-tv-helper`, tv-kurulumu.md §8) uygulamanın içinde, ayrı süreç olmadan çalışan
/// karşılığı. `TVHelperClient` süreci `TVProcessRunning.start` ile başlatır; bu koşucu yardımcının yeri olarak
/// `executableURL` verildiğinde komutu kendi içinde çalıştırır ve aynı JSON satırlarını üretir. Başka her yürütülebilir
/// dosya (LG'nin `ssh`/`ssh-keygen`'i) olduğu gibi `fallback`'e gider.
public struct InProcessTVHelper: Sendable {
    /// Yardımcının "yeri": gerçek bir dosya değil, yalnız bu koşucunun tanıdığı işaret.
    public static let executableURL = URL(fileURLWithPath: "/nino-in-process/\(TVHelperClient.executableName)")

    /// Samsung (`samsung-install`, tv-kurulumu.md §9) uygulamanın içinde yazıldı (`Helper/Samsung/`). Kart yine
    /// yalnız uygulamanın `tv-app` klasöründe bir `.wgt` varsa görünür (`TVAppPackages.scan`).
    public static let supportsSamsung = true

    let connector: ADBConnecting
    let ports: TVPortProbe
    let network: NetworkInterfaceListing
    let androidTiming: AndroidTVInstaller.Timing
    let samsungPorts: SamsungTVInstaller.Ports
    let samsungTiming: SamsungTVInstaller.Timing

    public init(connector: ADBConnecting = NWADBConnector(), ports: TVPortProbe = NWPortProbe(),
                network: NetworkInterfaceListing = SystemNetworkInterfaces(),
                androidTiming: AndroidTVInstaller.Timing = AndroidTVInstaller.Timing(),
                samsungPorts: SamsungTVInstaller.Ports? = nil,
                samsungTiming: SamsungTVInstaller.Timing = SamsungTVInstaller.Timing()) {
        self.connector = connector
        self.ports = ports
        self.network = network
        self.androidTiming = androidTiming
        self.samsungPorts = samsungPorts
            ?? SamsungTVInstaller.Ports(connector: connector, http: URLSessionTVHTTP(), network: network)
        self.samsungTiming = samsungTiming
    }

    /// Bilinmeyen komutta kullanım metni; çıkış 2.
    static let usage = "usage: android-scan | android-install --host IP --package APK --version V --key-dir DIR [--keep-legacy 1] | samsung-install …"

    /// Komutu çalıştırır; her olay tek satırlık JSON olarak `emit`'e verilir. Dönen: çıkış kodu.
    public func run(_ arguments: [String], emit: @escaping @Sendable (String) -> Void,
                    log: @escaping @Sendable (String) -> Void) async -> Int32 {
        let args = arguments.filter { $0 != "--exit-with-input" }
        let options = Self.options(args.dropFirst())
        switch args.first ?? "" {
        case "android-scan":
            let hosts = await AndroidTVScanner(ports: ports, network: network).scan()
            emit(Self.json(["event": "found", "hosts": hosts]))
            return 0
        case "android-install":
            guard let host = options["host"], let pkg = options["package"], let version = options["version"],
                  let keyDir = options["key-dir"] else {
                emit(Self.error("InstallFailed", "android-install: missing arguments"))
                return 1
            }
            let installer = AndroidTVInstaller(connector: connector, timing: androidTiming, log: log)
            do {
                let r = try await installer.install(host: host, package: URL(fileURLWithPath: pkg), version: version,
                                                    keyDir: URL(fileURLWithPath: keyDir, isDirectory: true),
                                                    keepLegacy: options["keep-legacy"] == "1",
                                                    onApprove: { emit(Self.json(["event": "approve"])) })
                emit(Self.result(r))
                return 0
            } catch let f as AndroidTVInstaller.Failure {
                emit(Self.error(f.code, f.message))
                return 1
            } catch {
                emit(Self.error("InstallFailed", "\(type(of: error)): \(error)"))
                return 1
            }
        case "samsung-install":
            return await samsungInstall(options, emit: emit, log: log)
        case "self-test":
            do {
                let key = try ADBKey.generate()
                _ = try key.sign(token: Data(repeating: 7, count: 20))
                _ = try key.androidPublicKey()
                emit(Self.json(["event": "done", "version": "", "installed": false]))
                return 0
            } catch {
                emit(Self.error("InstallFailed", "self-test: \(error)"))
                return 1
            }
        default:
            log(Self.usage)
            return 2
        }
    }

    /// `samsung-install --host IP --package WGT --version V --profiles DİZİN [--log DOSYA] [--key-dir DİZİN]`.
    /// sdb anahtarı `--key-dir`'de, verilmezse `profiles`'ın yanındaki `sdb/` klasöründe kalıcıdır.
    func samsungInstall(_ options: [String: String], emit: @escaping @Sendable (String) -> Void,
                        log: @escaping @Sendable (String) -> Void) async -> Int32 {
        guard let host = options["host"], let pkg = options["package"], let version = options["version"],
              let profilesPath = options["profiles"] else {
            emit(Self.error("InstallFailed", "samsung-install: missing arguments"))
            return 1
        }
        let profiles = URL(fileURLWithPath: profilesPath, isDirectory: true)
        let keyDir = options["key-dir"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? profiles.deletingLastPathComponent().appendingPathComponent("sdb", isDirectory: true)
        // --log varsa günlük doğrudan dosyaya; yoksa hata çıktısına (istemci onu günlüğe ekler). İkisi birden değil.
        let sink: @Sendable (String) -> Void
        if let file = options["log"], !file.isEmpty {
            let fileLog = TVInstallLog.file(URL(fileURLWithPath: file))
            sink = { fileLog.write($0) }
        } else {
            sink = log
        }
        let installer = SamsungTVInstaller(ports: samsungPorts, timing: samsungTiming, log: sink)
        do {
            let r = try await installer.install(host: host, package: URL(fileURLWithPath: pkg), version: version,
                                                profiles: profiles, keyDir: keyDir,
                                                keepLegacy: options["keep-legacy"] == "1") { event in
                switch event {
                case let .progress(step): emit(Self.json(["event": "progress", "step": step]))
                case let .login(url): emit(Self.json(["event": "login", "url": url.absoluteString]))
                }
            }
            emit(Self.result(r))
            return 0
        } catch let f as SamsungTVInstaller.Failure {
            emit(Self.error(f.code, f.message))
            return 1
        } catch {
            // İptal: hata olayı yok.
            return 143
        }
    }

    static func options(_ args: ArraySlice<String>) -> [String: String] {
        var out: [String: String] = [:]
        var it = args.makeIterator()
        while let a = it.next() {
            guard a.hasPrefix("--") else { continue }
            if let v = it.next() { out[String(a.dropFirst(2))] = v }
        }
        return out
    }

    static func json(_ o: [String: Any]) -> String {
        guard let d = try? JSONSerialization.data(withJSONObject: o, options: [.sortedKeys, .withoutEscapingSlashes]) else {
            return "{}"
        }
        return String(decoding: d, as: UTF8.self)
    }

    /// Sonuç olayı: yeni uygulama `done`, yalnız eski uygulama varsa `legacy`.
    static func result(_ r: (version: String, installed: Bool, legacy: Bool)) -> String {
        r.legacy ? json(["event": "legacy", "version": r.version])
            : json(["event": "done", "version": r.version, "installed": r.installed])
    }

    static func error(_ code: String, _ message: String) -> String {
        json(["event": "error", "code": code, "message": message])
    }
}

/// `InProcessTVHelper.executableURL` için uygulama içi yardımcıyı, öbürleri için `fallback`'i çalıştırır.
public struct InProcessHelperProcessRunner: TVProcessRunning {
    let helper: InProcessTVHelper
    let fallback: TVProcessRunning

    public init(helper: InProcessTVHelper = InProcessTVHelper(), fallback: TVProcessRunning = FoundationProcessRunner()) {
        self.helper = helper
        self.fallback = fallback
    }

    public func run(_ executable: URL, arguments: [String], input: Data?, timeout: TimeInterval) async throws -> TVProcessResult {
        try await fallback.run(executable, arguments: arguments, input: input, timeout: timeout)
    }

    public func start(_ executable: URL, arguments: [String]) throws -> TVRunningProcess {
        guard executable == InProcessTVHelper.executableURL else { return try fallback.start(executable, arguments: arguments) }
        return InProcessRunningHelper(helper: helper, arguments: arguments)
    }
}

/// Uygulama içi yardımcının "süreci": iş bir Task'ta çalışır; giriş kapanınca ya da sonlandırılınca iptal olur.
final class InProcessRunningHelper: TVRunningProcess, @unchecked Sendable {
    let lines: AsyncStream<String>
    private let lock = NSLock()
    private var task: Task<Void, Never>?
    private var exitCode: Int32?
    private var stderr = ""
    private let finished = AsyncStream<Int32>.makeStream()

    init(helper: InProcessTVHelper, arguments: [String]) {
        let (stream, cont) = AsyncStream<String>.makeStream()
        lines = stream
        let done = finished.continuation
        let box = WeakHelperBox()
        task = Task {
            let code = await helper.run(arguments, emit: { cont.yield($0) }, log: { line in box.value?.appendError(line) })
            let final: Int32 = Task.isCancelled ? 143 : code
            box.value?.setExit(final)
            cont.finish()
            done.yield(final)
            done.finish()
        }
        box.value = self
    }

    private func appendError(_ line: String) {
        lock.withLock {
            stderr += line + "\n"
            if stderr.utf8.count > 16 * 1024 { stderr = String(stderr.suffix(16 * 1024)) }
        }
    }

    private func setExit(_ c: Int32) {
        lock.withLock { exitCode = c }
    }

    func errorTail() -> String { lock.withLock { stderr } }

    func closeInput() { terminate() }

    func terminate() {
        lock.withLock { task }?.cancel()
    }

    func waitForExit(timeout: TimeInterval) async -> Int32? {
        if let known = lock.withLock({ exitCode }) { return known }
        let stream = finished.stream
        return await withTaskGroup(of: Int32?.self) { group in
            group.addTask { for await c in stream { return c }; return nil }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(max(0, timeout) * 1_000_000_000))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            if let first { return first }
            return lock.withLock { exitCode }
        }
    }
}

private final class WeakHelperBox: @unchecked Sendable {
    weak var value: InProcessRunningHelper?
}
