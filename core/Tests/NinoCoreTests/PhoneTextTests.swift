// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import XCTest
@testable import NinoCore

/// Telefon ve harita tarifinin metin kuralları (tablolar).
final class PhoneTextTests: XCTestCase {
    // MARK: §1.1

    func testPhoneGameDecision() {
        typealias P = GR.PhoneGame
        XCTAssertTrue(P.isPoolPriority("Grand Theft Auto VI"))
        XCTAssertTrue(P.isPoolPriority("GTA 6"))
        XCTAssertFalse(P.isPoolPriority("God of War"))

        var d = P.decide(cornersEnabled: true, sourceLanguage: "en", targetLanguage: "tr", game: .certain("GTA 6"), lastGameWasPoolPriority: false)
        XCTAssertEqual(d, .init(on: true, rememberPoolPriority: true))
        // Kesin bilinen başka oyun: Türkçe hedef olsa da kapalı.
        d = P.decide(cornersEnabled: true, sourceLanguage: "en", targetLanguage: "tr", game: .certain("God of War"), lastGameWasPoolPriority: true)
        XCTAssertEqual(d, .init(on: false, rememberPoolPriority: false))
        // Paketten tahmin: Türkçe hedef açar.
        XCTAssertTrue(P.decide(cornersEnabled: true, sourceLanguage: "en", targetLanguage: "tr", game: .packGuess("God of War"), lastGameWasPoolPriority: false).on)
        XCTAssertFalse(P.decide(cornersEnabled: true, sourceLanguage: "en", targetLanguage: "de", game: .packGuess("God of War"), lastGameWasPoolPriority: false).on)
        // Bilinmiyor: son oturum.
        XCTAssertTrue(P.decide(cornersEnabled: true, sourceLanguage: "en", targetLanguage: "de", game: .unknown, lastGameWasPoolPriority: true).on)
        // Köşeler kapalı ya da kaynak İngilizce değil.
        XCTAssertFalse(P.decide(cornersEnabled: false, sourceLanguage: "en", targetLanguage: "tr", game: .certain("GTA 6"), lastGameWasPoolPriority: true).on)
        XCTAssertFalse(P.decide(cornersEnabled: true, sourceLanguage: "ja", targetLanguage: "tr", game: .certain("GTA 6"), lastGameWasPoolPriority: true).on)
    }

    // MARK: §2

    func testScreenGameTable() {
        XCTAssertEqual(GR.ScreenGame.detect(["Recenter", "2D View", "Add Marker"]), "GTA 6")
        XCTAssertEqual(GR.ScreenGame.detect(["JASON & LUCIA", "MAP", "BRIEF", "PROGRESS"]), "GTA 6")
        XCTAssertEqual(GR.ScreenGame.detect(["MAP", "BRIEF", "PROGRESS"]), "GTA 6")
        XCTAssertEqual(GR.ScreenGame.detect(["Reminders", "7 Notifications", "WhatUp"]), "GTA 6")
        XCTAssertNil(GR.ScreenGame.detect(["Options", "Map", "Progress", "Quit Game"]))
        XCTAssertNil(GR.ScreenGame.detect(["Jason, wait for me!"]))
    }

    func testGameSenseDoesNotOverrideReported() {
        var s = GR.GameSense(reported: "God of War")
        XCTAssertFalse(s.observeScreen(["MAP", "BRIEF", "PROGRESS"]))
        XCTAssertEqual(s.current, "God of War")
        var u = GR.GameSense()
        XCTAssertTrue(u.observeScreen(["MAP", "BRIEF", "PROGRESS"]))
        XCTAssertFalse(u.notePhoneRead(), "aynı oyun bir şey yapmaz")
        XCTAssertEqual(u.current, "GTA 6")
        var r = GR.GameSense(reported: "Grand Theft Auto VI")
        XCTAssertFalse(r.notePhoneRead())
    }

    func testGTA6RulesListAndConfig() {
        XCTAssertEqual(GR.GTA6Rules.all.map(\.number), Array(1...12))
        var cfg = GR.Reader.Configuration()
        GR.GTA6Rules.apply(true, packGame: "x", to: &cfg)
        XCTAssertEqual(cfg.gameKey, "gta-6")
        XCTAssertTrue(cfg.poolPriority)
        GR.GTA6Rules.apply(false, packGame: "x", to: &cfg)
        XCTAssertEqual(cfg.gameKey, "x")
    }

    // MARK: §5.4

    func testSentenceTable() {
        XCTAssertFalse(GR.PhoneScreen.isSentence("Book Ryde ($82)"))
        XCTAssertFalse(GR.PhoneScreen.isSentence("Righto Cash & Carry"))
        XCTAssertFalse(GR.PhoneScreen.isSentence("1.74 mi"))
        XCTAssertTrue(GR.PhoneScreen.isSentence("Thx amigo! U find anything else"))
        XCTAssertTrue(GR.PhoneScreen.isSentence("Are you high right now?"))
        XCTAssertTrue(GR.PhoneScreen.isSentence("Dropped off scuba to yuh boat man"))
    }

    // MARK: §5 ekran türü

    let phone = GR.PhoneLocation(box: gbox(0.40, 0.15, 0.60, 0.85))

    func testChatParagraphMerges() {
        let lines = [
            gline("Brian", gbox(0.47, 0.16, 0.53, 0.185)),
            gline("Here r the spots man.", gbox(0.41, 0.30, 0.55, 0.32)),
            gline("These wrecks should be a good place", gbox(0.41, 0.325, 0.58, 0.345)),
        ]
        guard case let .screen(r) = GR.PhoneScreen.classify(lines, phone: phone) else { return XCTFail() }
        XCTAssertEqual(r.kind, .chat)
        XCTAssertEqual(r.header, "Brian")
        XCTAssertEqual(r.messages.map(\.text), ["Here r the spots man. These wrecks should be a good place"])
        XCTAssertEqual(r.messages[0].lineHeight, 0.025 * 0.85, accuracy: 1e-9)
    }

    func testChatDropsStatusAttachmentAndSender() {
        let lines = [
            gline("< Back", gbox(0.41, 0.16, 0.45, 0.18)),
            gline("Cal", gbox(0.48, 0.16, 0.52, 0.18)),
            gline("Today", gbox(0.48, 0.25, 0.52, 0.27)),
            gline("Dave", gbox(0.41, 0.30, 0.45, 0.315)),
            gline("Are you coming tonight?", gbox(0.41, 0.32, 0.56, 0.34)),
            gline("Righto Cash & Carry", gbox(0.41, 0.40, 0.55, 0.42)),
            gline("Delivered", gbox(0.52, 0.50, 0.58, 0.52)),
        ]
        guard case let .screen(r) = GR.PhoneScreen.classify(lines, phone: phone) else { return XCTFail() }
        XCTAssertEqual(r.header, "Cal")
        XCTAssertEqual(r.messages.map(\.text), ["Are you coming tonight?"])
    }

    func testChatListIsNotTranslated() {
        var lines: [GR.Line] = []
        for (i, n) in ["Brian Johnson", "Cal", "Lucia", "Boobie"].enumerated() {
            let t = 0.25 + Double(i) * 0.08
            lines.append(gline(n, gbox(0.42, t, 0.50, t + 0.02)))
            lines.append(gline("See you there...", gbox(0.42, t + 0.022, 0.56, t + 0.04)))
        }
        XCTAssertEqual(GR.PhoneScreen.classify(lines, phone: phone), .list)
    }

    func testAppLinesAndUpperLabels() {
        let lines = [
            gline("◆ Checking Account", gbox(0.42, 0.30, 0.55, 0.32)),
            gline("$4,900 to next goal", gbox(0.42, 0.33, 0.56, 0.35)),
        ]
        guard case let .screen(r) = GR.PhoneScreen.classify(lines, phone: phone) else { return XCTFail() }
        XCTAssertEqual(r.kind, .app)
        XCTAssertEqual(r.messages.map(\.text), ["Checking Account", "$4,900 to next goal"])
        XCTAssertEqual(GR.PhoneScreen.classify([gline("△ CLOSE", gbox(0.45, 0.5, 0.55, 0.52))], phone: phone), .notPhone)
        // Yalnız şekille bulunan telefon sohbet değilse telefon değildir.
        var shape = phone; shape.shapeOnly = true
        XCTAssertEqual(GR.PhoneScreen.classify(lines, phone: shape), .notPhone)
        XCTAssertEqual(GR.PhoneScreen.classify([], phone: phone), .empty)
    }

    func testAppLineContinuationAndAuthor() {
        let lines = [
            gline("Local man finds alligator in his", gbox(0.42, 0.30, 0.58, 0.32)),
            gline("swimming pool again", gbox(0.42, 0.325, 0.55, 0.345)),
            gline("By Jane Doe", gbox(0.42, 0.35, 0.50, 0.37)),
        ]
        guard case let .screen(r) = GR.PhoneScreen.classify(lines, phone: phone) else { return XCTFail() }
        XCTAssertEqual(r.messages.map(\.text), ["Local man finds alligator in his swimming pool again", "By Jane Doe"])
    }

    func testMapButtonInPhone() {
        XCTAssertTrue(GR.PhoneScreen.containsMapButton([gline("▲ Set Destination", nil)]))
        XCTAssertFalse(GR.PhoneScreen.containsMapButton([gline("Destination reached", nil)]))
    }

    // MARK: §6.5, §6.6, §7

    func testCleanTable() {
        XCTAssertEqual(GR.PhoneText.clean("Tamam &amp; ✕ geliyorum"), "Tamam & geliyorum")
        XCTAssertEqual(GR.PhoneText.clean("Don&#39;t"), "Don't")
        XCTAssertEqual(GR.PhoneText.clean("TAMAMEN YENİDEN YENİDEN YENİDEN"), "TAMAMEN YENİDEN")
    }

    func testDictionaryTable() {
        let d = GR.PhoneDictionary.turkish
        XCTAssertEqual(d("Checking Account"), "Cari Hesap")
        XCTAssertEqual(d("Family Savings"), "Aile Tasarrufu")
        XCTAssertEqual(d("$4,900 to next goal"), "Sonraki hedefe $4.900")
        XCTAssertNil(d("Are you high right now?"))
        XCTAssertEqual(d("Book Ryde ($82)"), "Ryde Çağır ($82)")
        XCTAssertEqual(d("Trip Details"), "Yolculuk Ayrıntıları")
        XCTAssertEqual(d("Level 3/4"), "Seviye 3/4")
        XCTAssertEqual(d("Cardio Workout"), "Kardiyo Çalışması")
        XCTAssertEqual(d("Muscle - High"), "Kas - Yüksek")
        XCTAssertEqual(d("Body Fat - Low"), "Vücut Yağı - Düşük")
        XCTAssertEqual(d("Ripped"), "Kaslı")
        XCTAssertEqual(d("Muscle High"), "Kas - Yüksek")
        XCTAssertEqual(d("Vice City Horn"), "Vice City Horn")
        XCTAssertEqual(d("Stamina - Very Low"), "Dayanıklılık - Çok Düşük")
    }

    func testAppText() {
        let a = GR.PhoneDictionary.isAppText
        XCTAssertTrue(a("Body Fat Low"))
        XCTAssertTrue(a("Trip Detail"), "OCR son harfi kaçırsa da kök tutar")
        XCTAssertTrue(a("Change Destinaton"))
        XCTAssertTrue(a("Book with Ryde"))
        XCTAssertTrue(a("Family Savings Video"))
        XCTAssertTrue(a("Book Ryde ($82)"))
        XCTAssertFalse(a("Focus"))
        XCTAssertFalse(a("Cost"))
        XCTAssertFalse(a("Are you high right now?"))
        XCTAssertFalse(a("Ride with me"))
    }

    // MARK: §9.1–9.2

    func testMapScreen() {
        XCTAssertTrue(GR.MapScreen.isMapScreen(["Recenter", "△ 3D View", "Close Menu"]))
        XCTAssertFalse(GR.MapScreen.isMapScreen(["Keep the engine running."]))
        XCTAssertFalse(GR.MapScreen.isMapScreen(["Recenter"]))
    }

    func testFlowerCard() throws {
        let lines = [
            gline("BUY FLOWERS", gbox(0.70, 0.40, 0.80, 0.42)),
            gline("Lucia will appreciate this", gbox(0.70, 0.43, 0.83, 0.45)),
            gline("Have some flowers delivered to the", gbox(0.70, 0.455, 0.90, 0.475)),
            gline("house for Lucia.", gbox(0.70, 0.48, 0.78, 0.50)),
        ]
        let c = try XCTUnwrap(GR.MapCardFinder.find(lines))
        XCTAssertEqual(c.title, "BUY FLOWERS")
        XCTAssertEqual(c.sentences, ["Lucia will appreciate this", "Have some flowers delivered to the house for Lucia."])
        XCTAssertEqual(c.box, gbox(0.70, 0.40, 0.90, 0.50))
    }

    func testDepositCardWithGoal() throws {
        let lines = [
            gline("Map", gbox(0.05, 0.05, 0.10, 0.07)),
            gline("DEPOSIT CASH INTO BUCKME", gbox(0.66, 0.50, 0.84, 0.52)),
            gline("Deposit your cash into BuckMe at one of the", gbox(0.66, 0.53, 0.92, 0.55)),
            gline("nearby ATMs.", gbox(0.66, 0.555, 0.73, 0.575)),
            gline("Cash is safe once it is in your", gbox(0.66, 0.58, 0.86, 0.60)),
            gline("checking account at an ATM.", gbox(0.66, 0.605, 0.83, 0.625)),
            gline("GOAL $100 / $5,000", gbox(0.66, 0.64, 0.78, 0.66)),
        ]
        let c = try XCTUnwrap(GR.MapCardFinder.find(lines))
        XCTAssertEqual(c.title, "DEPOSIT CASH INTO BUCKME")
        XCTAssertEqual(c.sentences.count, 2)
        XCTAssertTrue(c.sentences[0].hasSuffix("nearby ATMs."))
        XCTAssertTrue(c.sentences[1].contains("checking account at an ATM"))
        XCTAssertEqual(c.box.bottom, 0.66, accuracy: 1e-9)
    }

    func testFishCardIconAndDistance() throws {
        let lines = [
            gline("STOPLIGHT PARROTFISH", gbox(0.68, 0.30, 0.85, 0.32)),
            gline("(43) Cal challenged you to catch a 1.53 km", gbox(0.66, 0.33, 0.95, 0.35)),
            gline("stoplight parrotfish larger than 0.9 kg.", gbox(0.68, 0.355, 0.90, 0.375)),
        ]
        let c = try XCTUnwrap(GR.MapCardFinder.find(lines))
        XCTAssertEqual(c.sentences, ["Cal challenged you to catch a stoplight parrotfish larger than 0.9 kg."])
        XCTAssertEqual(c.title, "STOPLIGHT PARROTFISH")
    }

    func testHyphenAndLeadIcon() throws {
        let lines = [
            gline("● Help a burned-", gbox(0.66, 0.43, 0.80, 0.45)),
            gline("out friend get back on his feet", gbox(0.66, 0.455, 0.85, 0.475)),
        ]
        let c = try XCTUnwrap(GR.MapCardFinder.find(lines))
        XCTAssertEqual(c.sentences, ["Help a burned-out friend get back on his feet"])
        XCTAssertNil(c.title)
    }

    // MARK: §9.4

    func testTermsAndVenues() {
        XCTAssertEqual(GR.MapCardText.fixTerms("NAKİT KAPALI TUTULMASI"), "NAKİT DEPOSU")
        XCTAssertEqual(GR.MapCardText.fixTerms("işaretli faturaların izini sür"), "işaretli paraların izini sür")
        XCTAssertEqual(GR.MapCardText.fixTerms("narkotik"), "uyuşturucu")
        XCTAssertEqual(GR.MapCardText.fixTerms("bir trafik ışığı papağan balığı yakala"), "bir stoplight papağanbalığı yakala")
        XCTAssertTrue(GR.MapCardText.isVenue(title: "RIDEOUT CUSTOMS", description: nil))
        XCTAssertFalse(GR.MapCardText.isVenue(title: "JASON'S MAILBOX", description: nil))
        XCTAssertTrue(GR.MapCardText.isVenue(title: "SKIPPERS", description: "Mod shop for boats and jet skis."))
        XCTAssertFalse(GR.MapCardText.isVenue(title: "JUST MOVED IN", description: "Pick up some supplies from the Alpha convenience store near the motel."))
        XCTAssertFalse(GR.MapCardText.isVenue(title: "TAKE CARE OF JASON", description: "Keep checking in on Jason at the motel."))
        XCTAssertTrue(GR.MapCardText.isVenue(title: "THE PINK FLAMINGO", description: nil))
        XCTAssertEqual(GR.MapCardText.titleCase("BUY FLOWERS"), "Buy Flowers")
        XCTAssertEqual(GR.MapCardText.turkishUpper("çiçek al"), "ÇİÇEK AL")
    }
}
