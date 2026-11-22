// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import AppKit
import SwiftUI
import XCTest
@testable import NinoMacKit

/// Sayfaların ekran görüntüleri (`apps/mac/snapshots/sheet-*.png`). Yalnız üretir; ağa ve kullanıcının verisine dokunmaz.
@MainActor
final class SheetsSnapshotTests: XCTestCase {
    override func setUp() async throws {
        NinoFonts.registerBundledFonts()
    }

    private func sampleState() -> AppState {
        let state = PreviewEngine.sampleState()
        state.version = AppVersionInfo(short: "V4.1", full: "4.1.0")
        state.sheetsStatus.deviceFacts = DeviceFacts(appVersion: "4.1.0", build: nil, model: "Mac15,6",
                                                     systemVersion: "macOS 27.0", processor: "Apple M3 Pro",
                                                     memoryGB: 18)
        return state
    }

    private static let calendarBase = Date(timeIntervalSince1970: 1_763_800_000)

    func testHistory() throws {
        let state = sampleState()
        let lines = [("Come here, now.", "Buraya gel, hemen.", HistoryOrigin.pack),
                     ("Leave the engine on, I won't be long.",
                      "Motoru kapatma, çok sürmez.", .engine),
                     ("Lucia, wait!", "Lucia, bekle!", .pack),
                     ("Where's the money?", "Para nerede?", .engine)]
        state.history = lines.enumerated().map { index, line in
            HistoryEntry(date: Self.calendarBase.addingTimeInterval(Double(-index * 37)), source: line.0,
                         translated: line.1, origin: line.2)
        }
        try render(HistorySheet(state: state), size: CGSize(width: 640, height: 672), scheme: .light,
                   name: "sheet-history-light")
        state.history = []
        try render(HistorySheet(state: state), size: CGSize(width: 640, height: 672), scheme: .dark,
                   name: "sheet-history-empty-dark")
    }

    func testAbout() throws {
        let state = sampleState()
        XCTAssertEqual(AboutContent.versionLine(state.version), "V4.1 (4.1.0)")
        let sheet = CGSize(width: 520, height: AboutSheet.height)
        try render(AboutSheet(state: state), size: sheet, scheme: .light, name: "sheet-about-light")
        try render(AboutSheet(state: state), size: sheet, scheme: .dark, locale: "en", name: "sheet-about-dark-en")
        // Kaydırılan içeriğin tamamı (sayfada ScrollView ile görünür); tr: güncel, ar: yeni sürüm var.
        state.update = .upToDate
        try render(AboutContent(state: state).padding(32).frame(maxHeight: .infinity, alignment: .top).ninoScreen(), size: CGSize(width: 520, height: 860),
                   scheme: .light, name: "sheet-about-full-light")
        let ar = sampleState()
        ar.update = .available(version: "V4.2")
        try render(AboutContent(state: ar).padding(32).frame(maxHeight: .infinity, alignment: .top).ninoScreen()
                       .environment(\.layoutDirection, .rightToLeft),
                   size: CGSize(width: 520, height: 860), scheme: .dark, locale: "ar", name: "sheet-about-full-dark-ar")
    }

    func testHealth() throws {
        let state = sampleState()
        state.translation = .on
        state.source = .ps5(.dropped(.asleep))
        var m = HealthMetrics()
        m.hasMeasurements = true
        m.translating = true
        m.network = .wifi
        m.connectAttempts = 2
        m.connections = 1
        m.dropsWhileStreaming = 1
        m.ps5DownSince = Date().addingTimeInterval(-240)
        m.lastDropReason = .asleep
        m.lossPerMinute = 24
        m.stallsPerMinute = 1.2
        m.subtitleLines = 48
        m.translatedLines = 20
        m.medianTranslationMs = 1800
        m.subtitlesOnTV = true
        m.connectedTVs = 0
        m.localNetworkSuspect = true
        state.sheetsStatus.healthMetrics = m
        state.sheetsStatus.tvApp = .waitingForApproval
        state.sheetsStatus.problems = [
            ProblemRecord(date: Self.calendarBase, kind: .ps5Dropped, network: "wifi"),
            ProblemRecord(date: Self.calendarBase.addingTimeInterval(-3600), kind: .tvDropped, network: "wifi"),
        ]
        try render(HealthContent(state: state).padding(24).ninoScreen(), size: CGSize(width: 640, height: 1290),
                   scheme: .light, name: "sheet-health-problems-light")

        let fine = sampleState()
        var good = HealthMetrics()
        good.hasMeasurements = true
        good.translating = true
        good.receivingVideo = true
        good.network = .wired
        good.connections = 1
        good.connectAttempts = 1
        good.lossPerMinute = 0
        good.stallsPerMinute = 0
        good.subtitleLines = 12
        good.translatedLines = 4
        good.medianTranslationMs = 420
        good.connectedTVs = 1
        fine.translation = .on
        fine.connectedDisplays = 1
        fine.sheetsStatus.healthMetrics = good
        try render(HealthSheet(state: fine), size: CGSize(width: 640, height: 672), scheme: .dark,
                   name: "sheet-health-good-dark")
    }

    func testReportProblem() async throws {
        let empty = sampleState()
        try render(ReportProblemSheet(state: empty), size: CGSize(width: 640, height: 672), scheme: .light,
                   name: "sheet-report-empty-light")

        let state = sampleState()
        state.sheetsStatus.report.description = "Ghost of Yōtei'de altyazı geç geliyor, TV'de bazen hiç çıkmıyor."
        state.sheetsStatus.report.add([
            ReportAttachment(name: "ekran-1.png", content: .image(Self.samplePhoto(.systemTeal))),
            ReportAttachment(name: "ekran-2.png", content: .image(Self.samplePhoto(.systemOrange))),
            ReportAttachment(name: "oyun-notlari.txt", content: .text("satır")),
        ])
        try render(ReportProblemSheet(state: state), size: CGSize(width: 640, height: 672), scheme: .dark,
                   name: "sheet-report-files-dark")

        let sent = sampleState()
        sent.sheetsStatus.report.description = "x"
        let task = Task { @MainActor in
            await sent.sheetsStatus.report.send(build: { ProblemReport(kind: .user, description: "x", findings: "",
                                                                        device: "") },
                                                using: { _ in .success(()) }, thanksDuration: .seconds(30))
        }
        while sent.sheetsStatus.report.phase != .sent { await Task.yield() }
        try render(ReportProblemSheet(state: sent), size: CGSize(width: 640, height: 672), scheme: .light,
                   name: "sheet-report-sent-light")
        task.cancel()
    }

    func testAskNino() async throws {
        let state = sampleState()
        try render(AskNinoSheet(state: state), size: CGSize(width: 540, height: 660), scheme: .light,
                   name: "sheet-ask-empty-light")

        let chat = sampleState()
        let c = chat.sheetsStatus.chat
        c.addPhotos([Self.samplePhoto(.systemPurple)])
        c.send(text: "PS5 + TV + telefon") { _ in
            .success(AssistantReply(text: """
            Harika! Şöyle yapalım:

            1. PS5'te Ayarlar › Sistem › Uzaktan Oynatma'yı açın.
            2. TV'de Nino uygulamasını kurun.
               Kurulum için https://nino.test/tv adresine bakın.
            - Telefon ile TV aynı Wi-Fi'de olmalı.
            """, reportID: "r1"))
        }
        await c.waitForReply()
        c.send(text: "TV bulunamadı diyor") { _ in .failure(.offline) }
        await c.waitForReply()
        try render(AskNinoSheet(state: chat), size: CGSize(width: 540, height: 660), scheme: .dark,
                   name: "sheet-ask-chat-dark")

        let limited = sampleState()
        limited.sheetsStatus.chat.send(text: "Bir soru daha") { _ in .failure(.dailyLimit) }
        await limited.sheetsStatus.chat.waitForReply()
        try render(AskNinoSheet(state: limited), size: CGSize(width: 540, height: 660), scheme: .light,
                   name: "sheet-ask-limit-light")
    }

    /// Oyun kendiliğinden tanınır: ana ekranda soru kartı ya da seçim yok.
    func testGameHomeHasNoQuestionCard() throws {
        let state = sampleState()
        state.translation = .on
        state.source = .ps5(.streaming)
        state.connectedDisplays = 1
        state.game = RecognizedGame(id: "gta-6", name: "GTA 6", poolFirst: true, evidence: .lastPlayed)
        state.sheetsStatus.lastPlayedGame = "GTA 6"
        state.sheetsStatus.packGames = ["Mafia: The Old Country", "Red Dead Redemption 2"]
        try render(MainWindowView(state: state, ui: HomeUIState(skipIntro: true)),
                   size: CGSize(width: 1040, height: 720), scheme: .dark, name: "sheet-game-home-dark")
    }

    // MARK: Yardımcılar

    static func samplePhoto(_ color: NSColor) -> PhotoAttachment {
        let image = NSImage(size: NSSize(width: 320, height: 240))
        image.lockFocus()
        color.setFill()
        NSRect(x: 0, y: 0, width: 320, height: 240).fill()
        NSColor.white.setFill()
        NSRect(x: 40, y: 40, width: 120, height: 60).fill()
        image.unlockFocus()
        let png = NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
        return try! PhotoAttachment.prepare(data: png)
    }

    func render<V: View>(_ view: V, size: CGSize, scheme: ColorScheme, locale: String = "tr", name: String) throws {
        let content = view
            .frame(width: size.width, height: size.height)
            .environment(\.colorScheme, scheme)
            .environment(\.locale, Locale(identifier: locale))
            .environment(\.ninoStaticRendering, true)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        renderer.proposedSize = ProposedViewSize(size)
        let image: NSImage = try XCTUnwrap(renderer.nsImage, "\(name) çizilemedi")
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let png = try XCTUnwrap(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
        let folder = HomeSnapshotTests.snapshotFolder
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try png.write(to: folder.appendingPathComponent(name + ".png"))
    }
}
