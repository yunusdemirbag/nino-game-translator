// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import NinoCore
import UIKit
import XCTest
@testable import Nino

/// Uçtan uca: oyun karesi → okuma (Vision) → çeviri → TV (Nino Bağlantı Protokolü) ve telefon geçmişi.
@MainActor
final class FlowTests: XCTestCase {
    private struct FakeProvider: TranslationProvider {
        let name = "deneme"
        func translate(_ text: String, from source: String, to target: String) async throws -> String {
            let t = text.lowercased()
            return t.contains("rooftop") ? "Çatıya çık." : t.contains("now") ? "Hemen!" : "?"
        }
    }

    /// 1280×720 oyun karesi; altta beyaz altyazı.
    private func frame(_ text: String?) -> CGImage {
        let size = CGSize(width: 1280, height: 720)
        let image = UIGraphicsImageRenderer(size: size, format: { let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f }()).image { ctx in
            UIColor(white: 0.15, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            guard let text else { return }
            let style = NSMutableParagraphStyle()
            style.alignment = .center
            (text as NSString).draw(in: CGRect(x: 100, y: 590, width: 1080, height: 60), withAttributes: [
                .font: UIFont.systemFont(ofSize: 40, weight: .semibold), .foregroundColor: UIColor.white, .paragraphStyle: style,
            ])
        }
        return image.cgImage!
    }

    private func model() -> AppModel {
        let suite = "nino-flow-\(UUID())"
        let model = AppModel(store: MemoryStore(), defaults: UserDefaults(suiteName: suite)!,
                             folders: AppFolders(support: FileManager.default.temporaryDirectory, logs: FileManager.default.temporaryDirectory),
                             ephemeral: true)
        model.providerOverride = [FakeProvider()]
        return model
    }

    func testFrameToTV() async throws {
        let shown = LatestBox<ShowPayload>()
        let tv = NinoDisplayServer(options: .init(name: "Deneme TV", port: 0, advertise: false))
        tv.onChange = { p in if let p { shown.set(p) } }
        let port = try await tv.start()
        defer { tv.stop() }
        let sender = try await Displays.connect(host: "127.0.0.1", port: port)

        let model = model()
        let line = frame("Get to the rooftop. Now!")
        let empty = frame(nil)
        let source = StaticFrameSource(images: Array(repeating: line, count: 6) + Array(repeating: empty, count: 4))
        let task = await model.start(with: source, tv: sender)
        await task?.value

        let deadline = Date().addingTimeInterval(5)
        while shown.get() == nil && Date() < deadline { try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertEqual(shown.get()?.text, "Çatıya çık. Hemen!")
        XCTAssertEqual(shown.get()?.source?.lowercased().contains("rooftop"), true)
        let histDeadline = Date().addingTimeInterval(2)
        while model.history.entries.isEmpty && Date() < histDeadline { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertEqual(model.history.entries.first?.translation, "Çatıya çık. Hemen!")
        XCTAssertEqual(model.sessionLines, 1)
        model.stop()
        await sender.disconnect()
    }

    /// Gerçek başlatma yolu: Remote Play oturumu açılır (yönlendirilemeyen deneme adresine; ağdaki hiçbir cihaza
    /// dokunmaz), ana iş parçacığı kilitlenmez, durdurunca her şey kapanır.
    func testRealStartPathWithUnreachableConsole() async throws {
        let model = model()
        model.store.save(Data(repeating: 1, count: 8), for: Keys.accountID)
        let console = PairedConsole(host: "192.0.2.1", name: "Deneme PS5", registKey: Data("1a2b3c4d".utf8) + Data(count: 8),
                                    morning: Data(repeating: 7, count: 16))
        model.store.save(console, for: Keys.console)
        let restarted = AppModel(store: model.store, defaults: model.defaults, folders: model.folders, ephemeral: true)
        restarted.providerOverride = [FakeProvider()]
        restarted.useOutput(.computer)
        XCTAssertTrue(restarted.canStart)
        await restarted.start()
        XCTAssertTrue(restarted.isRunning)
        XCTAssertNotEqual(restarted.link, .streaming)

        // Ana iş parçacığı serbest mi: kısa bir ana görev hemen çalışmalı.
        let began = Date()
        await Task { @MainActor in }.value
        XCTAssertLessThan(Date().timeIntervalSince(began), 0.5)

        try await Task.sleep(for: .seconds(3))
        XCTAssertTrue(restarted.isRunning, "kopma çeviriyi durdurmaz, yeniden denenir")
        let stopBegan = Date()
        restarted.stop()
        XCTAssertLessThan(Date().timeIntervalSince(stopBegan), 0.5)
        XCTAssertFalse(restarted.isRunning)
        XCTAssertEqual(restarted.link, .disconnected(.stopped))
    }

    /// Kapalı yerel bağlantı noktası hemen reddeder: neden ekrana yazılır, oturum yeniden denenir.
    func testRetryAfterRefusedConnection() async throws {
        let model = model()
        model.store.save(Data(repeating: 1, count: 8), for: Keys.accountID)
        model.store.save(PairedConsole(host: "127.0.0.1", name: "Deneme PS5", registKey: Data("1a2b3c4d".utf8) + Data(count: 8),
                                       morning: Data(repeating: 7, count: 16)), for: Keys.console)
        let m = AppModel(store: model.store, defaults: model.defaults, folders: model.folders, ephemeral: true)
        m.providerOverride = [FakeProvider()]
        m.useOutput(.computer)
        await m.start()
        let deadline = Date().addingTimeInterval(20)
        while m.sessionAttempts < 2 && Date() < deadline { try await Task.sleep(for: .milliseconds(200)) }
        XCTAssertGreaterThanOrEqual(m.sessionAttempts, 2, "oturum yeniden denenmeli")
        XCTAssertNotNil(m.lastFailure)
        XCTAssertNotNil(m.problemText)
        XCTAssertTrue(m.isRunning)
        m.stop()
        XCTAssertNil(m.problemText)
    }

    func testQuitReasons() {
        XCTAssertEqual(AppModel.reason(fromQuit: "Stopped", host: "h"), .stopped)
        XCTAssertEqual(AppModel.reason(fromQuit: "Remote Play on Console is already in use", host: "h"), .inUse)
        XCTAssertEqual(AppModel.reason(fromQuit: "Ctrl failed to connect", host: "1.2.3.4"), .notFound("1.2.3.4"))
        XCTAssertEqual(AppModel.reason(fromQuit: "The Console Registration using PSN has failed", host: "h"), .refused)
        XCTAssertTrue(AppModel.isPermanent(.refused))
        XCTAssertFalse(AppModel.isPermanent(.network))
    }

    func testDemoLoopShowsSampleLine() async throws {
        let model = model()
        model.startDemo()
        XCTAssertTrue(model.isDemo)
        try await Task.sleep(for: .milliseconds(900))
        XCTAssertEqual(model.demoLine?.translation, "Beni dinliyor musun?")
        model.stopDemo()
        XCTAssertFalse(model.isDemo)
        XCTAssertNil(model.demoLine)
    }

    func testSetupSteps() {
        let model = model()
        XCTAssertEqual(model.step, .welcome)
        model.finishWelcome()
        XCTAssertEqual(model.step, .psnLogin)
        model.advance()
        XCTAssertEqual(model.step, .psnLogin, "hesap kimliği yokken ilerlemez")
        model.skipSetup()
        XCTAssertEqual(model.step, .output)
        model.useOutput(.computer)
        model.advance()
        XCTAssertEqual(model.step, .done)
        XCTAssertEqual(model.store.load(Bool.self, for: Keys.setupComplete), true)
    }
}

final class LogicTests: XCTestCase {
    /// Kendi küçük paketimizle: kütüphane okunur, satır anahtarla bulunur.
    func testPackLibraryAndLookup() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("packs-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let key = try XCTUnwrap(GamePack.key("Stay close to me."))
        let pack = #"{"format":1,"id":"deneme-oyun","title":"Deneme Oyun","entries":{"\#(key)":"Yanımda kal."}}"#
        try Data(pack.utf8).write(to: dir.appendingPathComponent("deneme-oyun.json"))
        let library = LegacyLibrary(directories: [dir])
        XCTAssertEqual(library.infos.map(\.title), ["Deneme Oyun"])
        let hits = LatestBox<String>()
        let lookup = PackLookup(library: library) { hits.set($0) }
        XCTAssertEqual(lookup.lookup("Stay close to me."), "Yanımda kal.")
        XCTAssertEqual(hits.get(), "Deneme Oyun")
        XCTAssertNil(lookup.lookup("Something else entirely."))
        XCTAssertEqual(key.count, 16)
    }

    func testMonogram() {
        XCTAssertEqual(GamePack(id: "a", title: "Grand Theft Auto V", lineCount: 0).monogram, "GTA")
        XCTAssertEqual(GamePack(id: "a", title: "Minecraft", lineCount: 0).monogram, "MIN")
        XCTAssertEqual(GamePack(id: "a", title: "Mafia: The Old Country", lineCount: 0).monogram, "MTO")
    }

    func testPINAndAddress() {
        XCTAssertEqual(Consoles.parsePIN("1234 5678"), 12345678)
        XCTAssertEqual(Consoles.parsePIN("١٢٣٤٥٦٧٨"), 12345678)
        XCTAssertNil(Consoles.parsePIN("1234567"))
        XCTAssertEqual(Displays.cleanAddress(" http://192.168.001.20:8080/x "), "192.168.1.20")
        XCTAssertEqual(Displays.cleanAddress("192,168,1,5"), "192.168.1.5")
        XCTAssertNil(Displays.cleanAddress("300.1.1.1"))
        XCTAssertEqual(Displays.cleanAddress("Salon-TV.local"), "salon-tv.local")
    }

    func testPSNAccountID() {
        XCTAssertEqual(PSNLogin.accountID(fromUserID: "1"), Data([1, 0, 0, 0, 0, 0, 0, 0]))
        XCTAssertTrue(PSNLogin.isRedirect(URL(string: "https://remoteplay.dl.playstation.net/remoteplay/redirect?code=abc")!))
        XCTAssertFalse(PSNLogin.isRedirect(URL(string: "https://remoteplay.dl.playstation.net/remoteplay/redirect?code=")!))
        XCTAssertThrowsError(try PSNLogin.code(from: URL(string: "https://x/?error=rate%20limit")!)) { e in
            XCTAssertEqual(e as? PSNLogin.Failure, .tooManyAttempts)
        }
    }

    func testStackTiming() {
        var stack = SubtitleStack()
        let t0 = Date()
        stack.show(id: 1, text: "Bir", source: nil, now: t0)
        stack.show(id: 2, text: "İki", source: nil, now: t0.addingTimeInterval(1))
        XCTAssertEqual(stack.lines.map(\.id), [1, 2])
        stack.tick(now: t0.addingTimeInterval(1 + 1.6))
        XCTAssertTrue(stack.lines.first?.fading == true)
        stack.tick(now: t0.addingTimeInterval(1 + 2.0))
        XCTAssertEqual(stack.lines.map(\.id), [2])
        stack.show(id: 3, text: "Üç", source: nil, now: t0.addingTimeInterval(10))
        XCTAssertEqual(stack.lines.map(\.id), [3])
    }

    func testBalancedWrap() {
        let text = "ARTHUR: We need to get out of here right now before they find us all"
        let wrapped = BalancedWrap.wrap(text)
        XCTAssertTrue(wrapped.contains("\n"))
        XCTAssertTrue(wrapped.hasPrefix("ARTHUR: We"))
        XCTAssertLessThanOrEqual(wrapped.split(separator: "\n").count, 3)
    }

    func testLanguages() {
        XCTAssertEqual(Languages.preferred(["fil-PH"]), "tl")
        XCTAssertEqual(Languages.interfaceCode(for: "tl"), "fil")
        XCTAssertEqual(Languages.preferred(["de-DE"]), "tr")
        XCTAssertTrue(Languages.isRightToLeft("ur"))
    }
}
