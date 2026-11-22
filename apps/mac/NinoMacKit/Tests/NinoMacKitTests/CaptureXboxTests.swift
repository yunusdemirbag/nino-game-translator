// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import CryptoKit
import Foundation
import XCTest
@testable import NinoMacKit

/// Xbox: Greenlight girişi, sürüm yanıtı, kurulum (sahte taşıyıcı, GERÇEK İNDİRME YOK), bağlantı listesi ve
/// koordinatörün durum yazımı. Geçici klasör ve geçici UserDefaults kullanılır.
final class CaptureXboxTests: XCTestCase {
    var temp: URL!

    override func setUpWithError() throws {
        temp = FileManager.default.temporaryDirectory.appendingPathComponent("nino-capture-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temp)
    }

    // MARK: Giriş ve sürüm

    func testSignedIn() {
        func check(_ json: String) -> Bool { GreenlightFacts.isSignedIn(configData: Data(json.utf8)) }
        XCTAssertTrue(check(#"{"user":{"tokenstore":"{\"a\":1}"}}"#))
        XCTAssertTrue(check(#"{"user":{"tokenstore":{"a":1}}}"#))
        XCTAssertTrue(check(#"{"user.tokenstore":"abc"}"#))
        XCTAssertFalse(check(#"{"user":{"tokenstore":"{}"}}"#))
        XCTAssertFalse(check(#"{"user":{"tokenstore":"  "}}"#))
        XCTAssertFalse(check(#"{"user":{}}"#))
        XCTAssertFalse(check("not json"))
    }

    static func release(name: String = "Greenlight-2.4.1-universal.dmg", digest: String? = nil, size: Int = 1000) -> Data {
        var asset: [String: Any] = ["name": name, "browser_download_url": "https://example.invalid/\(name)", "size": size]
        if let digest { asset["digest"] = digest }
        let other: [String: Any] = ["name": "Greenlight-2.4.1-arm64.dmg", "browser_download_url": "https://example.invalid/a"]
        return try! JSONSerialization.data(withJSONObject: ["tag_name": "v2.4.1", "assets": [other, asset]])
    }

    func testReleaseAsset() {
        let a = GreenlightAsset.fromRelease(Self.release(digest: "sha256:ABCDEF"))
        XCTAssertEqual(a?.name, "Greenlight-2.4.1-universal.dmg")
        XCTAssertEqual(a?.sha256, "abcdef")
        XCTAssertEqual(a?.size, 1000)
        XCTAssertNil(GreenlightAsset.fromRelease(Self.release(name: "Greenlight.zip")))
        XCTAssertNil(GreenlightAsset.fromRelease(Data("{}".utf8)))
    }

    func testDownloadProgress() {
        XCTAssertEqual(GreenlightInstaller.downloadProgress(received: 50, total: 100)!, 0.475, accuracy: 1e-9)
        XCTAssertEqual(GreenlightInstaller.downloadProgress(received: 200, total: 100), 0.95, "en çok %95")
        XCTAssertNil(GreenlightInstaller.downloadProgress(received: 5, total: nil))
    }

    func testXboxStepMapping() {
        XCTAssertEqual(GreenlightFacts.xboxStep(XboxLink()), .notStarted)
        XCTAssertEqual(GreenlightFacts.xboxStep(XboxLink(greenlightInstalled: true)), .notStarted)
        XCTAssertEqual(GreenlightFacts.xboxStep(XboxLink(greenlightInstalled: true, signedIn: true)), .waitingForWindow)
        XCTAssertEqual(GreenlightFacts.xboxStep(XboxLink(greenlightInstalled: true, signedIn: true, streaming: true)), .ready)
        XCTAssertEqual(GreenlightFacts.xboxStep(XboxLink(installProgress: 0.3)), .installing(progress: 0.3))
    }

    // MARK: Kurulum

    /// Ağa ve hdiutil'e çıkmayan taşıyıcı: "kalıp" bir klasördür.
    final class FakeCarrier: GreenlightCarrier, @unchecked Sendable {
        var status = 200
        var body: Data
        var payload = Data("dmg".utf8)
        var downloadFails = false
        let root: URL
        private(set) var detached = false

        init(root: URL, body: Data) {
            self.root = root
            self.body = body
        }

        func latestRelease() async throws -> (status: Int, body: Data) { (status, body) }

        func download(_ url: URL, progress: @escaping @Sendable (Int64, Int64?) -> Void) async throws -> URL {
            if downloadFails { throw URLError(.notConnectedToInternet) }
            progress(500, 1000)
            progress(1000, 1000)
            let file = root.appendingPathComponent("dl-\(UUID().uuidString).dmg")
            try payload.write(to: file)
            return file
        }

        func attach(_ image: URL) async throws -> URL {
            let mount = root.appendingPathComponent("mount-\(UUID().uuidString)")
            let app = mount.appendingPathComponent("Greenlight.app/Contents")
            try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
            try Data("plist".utf8).write(to: app.appendingPathComponent("Info.plist"))
            return mount
        }

        func detach(_ mountPoint: URL) async { detached = true }
    }

    final class Progress: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [Double?] = []
        func add(_ p: Double?) { lock.lock(); items.append(p); lock.unlock() }
        var all: [Double?] { lock.lock(); defer { lock.unlock() }; return items }
    }

    func testInstallSuccessWithChecksum() async throws {
        let payload = Data("dmg".utf8)
        let digest = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
        let carrier = FakeCarrier(root: temp, body: Self.release(digest: "sha256:" + digest))
        let blocked = temp.appendingPathComponent("blocked")
        try Data().write(to: blocked) // klasör yerine dosya: buraya kopyalanamaz
        let fallback = temp.appendingPathComponent("home-apps")
        let installer = GreenlightInstaller(carrier: carrier, destinations: [blocked, fallback])
        let progress = Progress()
        let app = try await installer.install { progress.add($0) }
        XCTAssertEqual(app.standardizedFileURL.path, fallback.appendingPathComponent("Greenlight.app").standardizedFileURL.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: app.appendingPathComponent("Contents/Info.plist").path))
        XCTAssertTrue(carrier.detached)
        XCTAssertEqual(progress.all.compactMap { $0 }, [0, 0.475, 0.95, 1])
    }

    func testInstallReplacesOldCopy() async throws {
        let dest = temp.appendingPathComponent("apps")
        let old = dest.appendingPathComponent("Greenlight.app/old.txt")
        try FileManager.default.createDirectory(at: old.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: old)
        let installer = GreenlightInstaller(carrier: FakeCarrier(root: temp, body: Self.release()), destinations: [dest])
        _ = try await installer.install { _ in }
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path))
    }

    func testInstallErrors() async {
        func run(_ setup: (FakeCarrier) -> Void) async -> GreenlightInstallError? {
            let carrier = FakeCarrier(root: temp, body: Self.release())
            setup(carrier)
            let installer = GreenlightInstaller(carrier: carrier, destinations: [temp.appendingPathComponent("apps")])
            do {
                _ = try await installer.install { _ in }
                return nil
            } catch {
                return error as? GreenlightInstallError
            }
        }
        let notFound = await run { $0.status = 404 }
        XCTAssertEqual(notFound, .latestNotFound)
        let noUniversal = await run { $0.body = Self.release(name: "Greenlight.zip") }
        XCTAssertEqual(noUniversal, .latestNotFound)
        let offline = await run { $0.downloadFails = true }
        XCTAssertEqual(offline, .downloadFailed)
        let damaged = await run { $0.body = Self.release(digest: "sha256:00") }
        XCTAssertEqual(damaged, .damaged)
    }

    func testErrorMessagesAreLocalized() {
        for e in [GreenlightInstallError.latestNotFound, .downloadFailed, .damaged, .copyFailed] {
            XCTAssertFalse(e.message.hasPrefix("capture."), "\(e)")
        }
    }

    // MARK: Bağlantı listesi ve koordinatör

    final class FakeWorld: @unchecked Sendable {
        var installed = false
        var running = false
        var config: Data?
        var titles: [(owner: String, title: String)] = []
        var opened = 0
        var apps: Set<String> = []
    }

    func probe(_ world: FakeWorld) -> XboxProbe {
        XboxProbe(appExists: { world.installed }, isRunning: { world.running }, configData: { world.config },
                  windowTitles: { world.titles })
    }

    func testProbeSteps() {
        let world = FakeWorld()
        let p = probe(world)
        XCTAssertEqual(p.read(keeping: XboxLink()).step, .install)
        world.installed = true
        XCTAssertEqual(p.read(keeping: XboxLink()).step, .signIn)
        world.config = Data(#"{"user":{"tokenstore":"x"}}"#.utf8)
        XCTAssertEqual(p.read(keeping: XboxLink()).step, .start)
        world.titles = [("Greenlight", "Greenlight - My consoles")]
        world.running = true
        XCTAssertEqual(p.read(keeping: XboxLink()).step, .start)
        world.titles.append(("Greenlight", "Greenlight - Streaming F4001234ABCD"))
        XCTAssertEqual(p.read(keeping: XboxLink()).step, .done)
        world.running = false
        XCTAssertEqual(p.read(keeping: XboxLink()).step, .start, "kapalıysa yayın yok")
        let kept = p.read(keeping: XboxLink(installProgress: 0.5, installError: "e"))
        XCTAssertEqual(kept.installProgress, 0.5)
        XCTAssertEqual(kept.installError, "e")
    }

    @MainActor
    func makeCoordinator(_ world: FakeWorld, carrier: FakeCarrier? = nil) -> (CaptureCoordinator, AppState, SettingsStore) {
        let suite = "nino-capture-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let store = SettingsStore(defaults: defaults)
        let state = AppState()
        let env = CaptureEnvironment(
            xboxProbe: probe(world),
            greenlight: GreenlightInstaller(carrier: carrier ?? FakeCarrier(root: temp, body: Self.release()),
                                            destinations: [temp.appendingPathComponent("apps")]),
            isAppInstalled: { world.apps.contains($0) },
            openGreenlight: { world.opened += 1 })
        let c = CaptureCoordinator(state: state, settingsStore: store, environment: env, log: { _ in }, hub: CardPreviewHub())
        return (c, state, store)
    }

    @MainActor
    func testCoordinatorXboxAndInstall() async {
        let world = FakeWorld()
        let (c, state, _) = makeCoordinator(world)
        XCTAssertEqual(state.xboxStep, .notStarted)
        XCTAssertFalse(state.setup.xbox.greenlightInstalled)
        c.installGreenlight()
        XCTAssertEqual(state.setup.xbox.installProgress, 0)
        if case .installing = state.xboxStep {} else { XCTFail("kuruluyor bekleniyordu") }
        world.installed = true
        await c.greenlightInstall?.value
        XCTAssertNil(state.setup.xbox.installProgress)
        XCTAssertNil(state.setup.xbox.installError)
        XCTAssertTrue(state.setup.xbox.greenlightInstalled)
        XCTAssertEqual(state.xboxStep, .notStarted, "kurulu ama giriş yok")
        XCTAssertEqual(world.opened, 1, "kurulunca açılır")
        world.config = Data(#"{"user":{"tokenstore":"x"}}"#.utf8)
        c.refreshXbox()
        XCTAssertEqual(state.xboxStep, .waitingForWindow)
    }

    @MainActor
    func testCoordinatorInstallFailureShowsMessage() async {
        let world = FakeWorld()
        let carrier = FakeCarrier(root: temp, body: Self.release())
        carrier.status = 403
        let (c, state, _) = makeCoordinator(world, carrier: carrier)
        c.installGreenlight()
        await c.greenlightInstall?.value
        XCTAssertNil(state.setup.xbox.installProgress)
        XCTAssertEqual(state.setup.xbox.installError, GreenlightInstallError.latestNotFound.message)
        XCTAssertEqual(world.opened, 0)
    }

    @MainActor
    func testCoordinatorRemotePlayAppMissing() async {
        let world = FakeWorld()
        let (c, state, _) = makeCoordinator(world)
        XCTAssertFalse(state.setup.remotePlayAppInstalled)
        state.settings.videoSource = .window
        state.source = .window(.idle)
        c.refreshRemotePlayApps()
        XCTAssertEqual(state.source, .window(.appMissing))
        world.apps = [RemotePlayApps.sonyBundleID]
        c.refreshRemotePlayApps()
        XCTAssertTrue(state.setup.remotePlayAppInstalled)
        XCTAssertEqual(state.source, .window(.idle))
        state.settings.remotePlayApp = .chiaki
        // Seçim değişince yeniden bakılır (gözlem bir sonraki turda çalışır).
        for _ in 0..<20 where state.setup.remotePlayAppInstalled { await Task.yield() }
        XCTAssertFalse(state.setup.remotePlayAppInstalled)
        XCTAssertEqual(state.source, .window(.appMissing))
        // Xbox yolunda bu durum yok.
        state.settings.gameConsole = .xbox
        state.source = .window(.idle)
        c.refreshRemotePlayApps()
        XCTAssertEqual(state.source, .window(.idle))
    }

    @MainActor
    func testSelectCaptureDeviceIsSaved() {
        let (c, state, store) = makeCoordinator(FakeWorld())
        c.selectCaptureDevice("card-1")
        XCTAssertEqual(store.captureCardID, "card-1")
        XCTAssertEqual(state.setup.captureCard.selectedDeviceID, "card-1")
        c.selectCaptureDevice(nil)
        XCTAssertNil(store.captureCardID)
    }
}
