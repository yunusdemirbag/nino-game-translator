// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import XCTest
@testable import Nino

/// Android TV kurulumu, 127.0.0.1'deki sahte adbd ile (gerçek TV'ye dokunulmaz).
final class AndroidTVInstallTests: XCTestCase {
    private var dir: URL!
    private var identity: AdbIdentity!

    override func setUpWithError() throws {
        dir = TVTestFiles.scratch()
        identity = try AdbIdentity.stored(in: dir)
    }

    private func makeDevice(installed: LockedValue<String?>, installOutput: String = "Success") -> FakeWireDevice {
        let device = FakeWireDevice(verifySum: false, banner: "device::ro.product.name=tv;")
        device.requireAuth = true
        device.expectedKeyLine = identity.publicKeyLine
        device.services = [
            .init(prefix: "shell:dumpsys package") { _, _ in
                installed.get().map { "Packages:\n  Package [com.ninotranslator.tv]\n    versionName=\($0)\n" }
                    ?? "Unable to find package: com.ninotranslator.tv\n"
            },
            .init(prefix: "exec:cmd package install", inputLength: { name in
                Int(name.split(separator: " ").last ?? "0") ?? 0
            }) { _, input in
                if installOutput == "Success" { installed.set("4.0.5") }
                return installOutput + "\n"
            },
            .init(prefix: "shell:appops set") { _, _ in "" },
            .init(prefix: "shell:pm uninstall") { _, _ in installed.set(nil); return "Success\n" },
            .init(prefix: "shell:am start") { _, _ in "Starting: Intent { cmp=com.ninotranslator.tv/.MainActivity }\n" },
        ]
        return device
    }

    private func installer(port: UInt16, stages: LockedValue<[InstallStage]>) -> AndroidTVInstaller {
        let id = identity!
        var i = AndroidTVInstaller(host: "127.0.0.1", port: port, identity: { id },
                                   log: TVInstallLog(file: dir.appendingPathComponent("tvinstall.log")))
        i.playListed = { false }
        i.approvalTimeout = 5
        i.stage = { s in stages.set(stages.get() + [s]) }
        return i
    }

    func testFreshInstallAsksApprovalStreamsAPKAndLaunches() throws {
        let installed = LockedValue<String?>(nil)
        let device = makeDevice(installed: installed)
        let server = try LoopbackServer { device.serve($0) }
        defer { server.stop() }
        let stages = LockedValue<[InstallStage]>([])
        let apk = Bytes((0..<10_000).map { UInt8($0 & 0xFF) })
        let outcome = try installer(port: server.port, stages: stages).install(package: { TVPackage(bytes: apk, version: "4.0.5", origin: "t") })
        XCTAssertEqual(outcome, TVInstallOutcome(version: "4.0.5", installed: true))
        XCTAssertEqual(device.approvals.get(), 1, "ilk bağlantıda TV onay sormalı")
        XCTAssertTrue(stages.get().contains(.approveOnTV))
        XCTAssertTrue(stages.get().contains(.launching))
        let services = device.seenServices.get()
        XCTAssertTrue(services.contains("exec:cmd package install -r -S 10000"), "\(services)")
        XCTAssertTrue(services.contains { $0.hasPrefix("shell:appops set com.ninotranslator.tv SYSTEM_ALERT_WINDOW allow") })
        XCTAssertTrue(services.contains("shell:am start -n com.ninotranslator.tv/.MainActivity"))
        let log = try String(contentsOf: dir.appendingPathComponent("tvinstall.log"), encoding: .utf8)
        XCTAssertTrue(log.contains("Installed 4.0.5."), log)
    }

    func testUpToDateTVOnlyLaunches() throws {
        let installed = LockedValue<String?>("4.0.5")
        let device = makeDevice(installed: installed)
        device.trustedKey.set(identity.key.publicRef)
        let server = try LoopbackServer { device.serve($0) }
        defer { server.stop() }
        let stages = LockedValue<[InstallStage]>([])
        let outcome = try installer(port: server.port, stages: stages).install(package: { TVPackage(bytes: [], version: "4.0.5", origin: "t") })
        XCTAssertEqual(outcome, TVInstallOutcome(version: "4.0.5", installed: false))
        XCTAssertEqual(device.approvals.get(), 0, "güvenilen anahtarla onay sorulmamalı")
        XCTAssertFalse(device.seenServices.get().contains { $0.hasPrefix("exec:") })
    }

    /// Telefonda paket yokken (indirme başarısız, gömülü yok) TV'deki Nino'ya izin verilip açılır.
    func testMissingPackageStillLaunchesInstalledApp() throws {
        let installed = LockedValue<String?>("4.0.3")
        let device = makeDevice(installed: installed)
        device.trustedKey.set(identity.key.publicRef)
        let server = try LoopbackServer { device.serve($0) }
        defer { server.stop() }
        let outcome = try installer(port: server.port, stages: .init([])).install(package: {
            throw TVPackageMissing(description: "offline")
        })
        XCTAssertEqual(outcome, TVInstallOutcome(version: "4.0.3", installed: false))
        XCTAssertTrue(device.seenServices.get().contains { $0.hasPrefix("shell:appops set") })
        XCTAssertTrue(device.seenServices.get().contains("shell:am start -n com.ninotranslator.tv/.MainActivity"))
        // TV'de de yoksa "paket yok".
        installed.set(nil)
        XCTAssertThrowsError(try installer(port: server.port, stages: .init([])).install(package: {
            throw TVPackageMissing(description: "offline")
        })) { XCTAssertEqual(($0 as? AndroidTVFailure)?.problem, .packageMissing) }
    }

    func testIncompatibleCopyNeedsConsentThenReplaces() throws {
        let installed = LockedValue<String?>("0.9.18")
        let device = makeDevice(installed: installed, installOutput: "Failure [INSTALL_FAILED_UPDATE_INCOMPATIBLE: signatures do not match]")
        device.trustedKey.set(identity.key.publicRef)
        let server = try LoopbackServer { device.serve($0) }
        defer { server.stop() }
        let stages = LockedValue<[InstallStage]>([])
        XCTAssertThrowsError(try installer(port: server.port, stages: stages).install(package: { TVPackage(bytes: [1, 2, 3], version: "4.0.5", origin: "t") })) {
            XCTAssertEqual(($0 as? AndroidTVFailure)?.problem, .replaceNeeded)
        }
        // Kullanıcı onaylar: kopya kaldırılır; sahte TV ikinci kurulumu da reddeder → "kurulamadı".
        XCTAssertThrowsError(try installer(port: server.port, stages: stages).install(package: { TVPackage(bytes: [1, 2, 3], version: "4.0.5", origin: "t") },
                                                                                       allowReplace: true)) {
            XCTAssertEqual(($0 as? AndroidTVFailure)?.problem, .installFailed)
        }
        XCTAssertTrue(device.seenServices.get().contains("shell:pm uninstall com.ninotranslator.tv"))
    }

    func testSilentVersionCheckDoesNotTriggerApproval() throws {
        let installed = LockedValue<String?>("4.0.1")
        let device = makeDevice(installed: installed)
        let server = try LoopbackServer { device.serve($0) }
        defer { server.stop() }
        XCTAssertThrowsError(try installer(port: server.port, stages: .init([])).installedVersion()) {
            XCTAssertEqual(($0 as? AndroidTVFailure)?.problem, .notApproved)
        }
        XCTAssertEqual(device.approvals.get(), 0)
        device.trustedKey.set(identity.key.publicRef)
        XCTAssertEqual(try installer(port: server.port, stages: .init([])).installedVersion(), "4.0.1")
    }

    func testClosedPortIsUnreachable() throws {
        let server = try LoopbackServer { _ in }
        let port = server.port
        server.stop()
        XCTAssertThrowsError(try installer(port: port, stages: .init([])).install(package: { TVPackage(bytes: [], version: "1", origin: "t") })) {
            XCTAssertEqual(($0 as? AndroidTVFailure)?.problem, .unreachable)
        }
    }

    func testParsers() {
        XCTAssertEqual(AndroidTVInstaller.version(fromDumpsys: "  versionCode=40 minSdk=24\n    versionName=4.0.3\n"), "4.0.3")
        XCTAssertTrue(AndroidTVInstaller.installedFromPlay("installerPackageName=com.android.vending\n"))
        XCTAssertTrue(AndroidTVInstaller.needsReplace("Failure [INSTALL_FAILED_VERSION_DOWNGRADE]"))
        XCTAssertTrue(AndroidTVInstaller.isStorageProblem("Failure [INSTALL_FAILED_INSUFFICIENT_STORAGE]"))
        XCTAssertTrue(AndroidTVInstaller.streamingUnsupported("/system/bin/sh: cmd: not found"))
        XCTAssertFalse(AndroidTVInstaller.streamingUnsupported("Success"))
        XCTAssertEqual(AndroidTVInstaller.split("192.168.1.5")?.port, 5555)
        XCTAssertEqual(AndroidTVInstaller.split("192.168.1.5:37123")?.port, 37123)
        XCTAssertNil(AndroidTVInstaller.split("192.168.1.5", defaultPort: 0))
        XCTAssertEqual(AndroidTVInstaller.split("١٩٢.١٦٨.١.٥:٥٥٥٥")?.host, "192.168.1.5")
    }
}
