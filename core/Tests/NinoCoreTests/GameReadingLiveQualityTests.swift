// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import CoreGraphics
import ImageIO
import XCTest
@testable import NinoCore

/// GTA 6 canlı okuma kalitesi (22 Kasım, `altyazi.log` 17:11 ve 17:20): solarken bozulan okuma, kırpılmış
/// ikinci satır, tabela yazısı, madde imi, `l`/`I` karışıklığı.
final class GameReadingLiveQualityTests: XCTestCase {
    typealias F = GR.Filters

    // MARK: l / I

    func testPronounIReadings() {
        XCTAssertEqual(F.cleanJunk("the best lcan."), "the best I can.")
        XCTAssertEqual(F.cleanJunk("i'm doing"), "I'm doing")
        XCTAssertEqual(F.cleanJunk("Hey, uh, I- I forgot my wallet, III- I'II be right back."),
                       "Hey, uh, I- I forgot my wallet, I'll- I'll be right back.")
        XCTAssertEqual(F.cleanJunk("lm here, ldon't care."), "I'm here, I don't care.")
        XCTAssertEqual(F.cleanJunk("Yeah, i know."), "Yeah, I know.")
        XCTAssertEqual(F.cleanJunk("you'II see."), "you'll see.")
        XCTAssertEqual(F.cleanJunk("- I'm doing the best Ican."), "- I'm doing the best I can.")
        // Değişmeyenler.
        for s in ["He looks ill.", "Pull the lever now.", "Part III of the story.", "A lone wolf.", "Ill take it.", "Ido is a language.",
                  "I can do it.", "Look, I only stopped by.", "Lucas can help."] {
            XCTAssertEqual(F.cleanJunk(s), s)
        }
    }

    // MARK: Madde imi

    func testLeadingBullets() {
        XCTAssertEqual(F.stripLeadingBullets("• And shut the damn dog up."), "And shut the damn dog up.")
        XCTAssertEqual(F.stripLeadingBullets("«Shut the damn dog up,. man!"), "Shut the damn dog up,. man!")
        XCTAssertEqual(F.stripLeadingBullets("/shut the capin dog up. man"), "shut the capin dog up. man")
        XCTAssertEqual(F.stripLeadingBullets("* Hey, what's goin' on, why is everyone so jumpy today?"),
                       "Hey, what's goin' on, why is everyone so jumpy today?")
        XCTAssertEqual(F.stripLeadingBullets("· Go!"), "Go!")
        for s in ["- Now? - Later.", "«Go» she said.", "No!", "OK.", "...and then it rained.", "\"Mira!\" he shouted."] {
            XCTAssertEqual(F.stripLeadingBullets(s), s)
        }
        // Telefon oyununda tek tireli satır göstergenin iğnesidir; tireli konuşma (iki satır ya da ` - `) kalır.
        let one = F.stripLoneDialogueDash([gline("- Shut the damn dog up, man!")])
        XCTAssertEqual(one.map(\.text), ["Shut the damn dog up, man!"])
        XCTAssertEqual(F.stripLoneDialogueDash([gline("- Now?"), gline("- Later.")]).map(\.text), ["- Now?", "- Later."])
        XCTAssertEqual(F.stripLoneDialogueDash([gline("- Now? - Later.")]).map(\.text), ["- Now? - Later."])
        XCTAssertEqual(GR.FilterChain.chain([gline("- Now? - Later.", gbox(0.3, 0.5, 0.7, 0.6))], area: .full, labels: true).map(\.text), ["- Now? - Later."])
        // Zincirde: `., And shut,` (Vision) ve `• And…` aynı satıra iner.
        let a = GR.FilterChain.chain([gline("• And shut the damn dog up.", gbox(0.3, 0.5, 0.7, 0.6))], area: .full, labels: true)
        XCTAssertEqual(a.map(\.text), ["And shut the damn dog up."])
    }

    // MARK: Solarken bozulan okuma

    /// 17:20:44–48: `And shut the damn dog up.` gösterildi; solarken `/shut the capin dog up. man` yeni satır olup
    /// çevrildi ve 9 ms sonra kalktı; asıl sonraki satır `Shut the damn dog up, man!` ise hiç çevrilmedi.
    func testFadingMisreadIsNotANewLine() {
        var s = GR.Stabilizer()
        var t = 0
        func see(_ text: String?) -> GR.Stabilizer.Reaction { t += 100; return s.observe(text, now: t) }
        XCTAssertEqual(see("And shut the damn dog up."), .translate("And shut the damn dog up."))
        XCTAssertEqual(see("/shut the capin dog up. man"), .none)
        XCTAssertEqual(see("/shut the capin dog up. man"), .none)
        XCTAssertEqual(see("shut the capin dog up. man"), .none)
        XCTAssertEqual(see("shut the capin dog up. man"), .none)
        // Temiz okunan yeni satır çevrilir.
        XCTAssertEqual(see("Shut the damn dog up, man!"), .translate("Shut the damn dog up, man!"))
        XCTAssertEqual(see("Shut the damn dog up, man!"), .none)
        XCTAssertEqual(see("/shut the capin dog up. man"), .none)
        XCTAssertEqual(see("/shut the capin dog up. man"), .none)
        XCTAssertEqual(see("Shut up, dog!"), .translate("Shut up, dog!"))
        XCTAssertEqual(see("Why are you being weird?"), .translate("Why are you being weird?"))
    }

    /// Okuyucu üzerinden (GTA 6 kuralları): #20 temiz, bozuk okuma, `Shut… man!` temiz → 2 gösterilen satır,
    /// ikincisi ekrandakinin yerine konur (TV çeviriyi günceller).
    func testFadingMisreadThroughReader() async {
        let clock = GR.ManualClock(0)
        var cfg = GR.Reader.Configuration()
        GR.GTA6Rules.apply(true, packGame: "gta-6", to: &cfg)
        let box = gbox(0.37, 0.4, 0.63, 0.6)
        let script = ["• And shut the damn dog up.", "/shut the capin dog up. man", "/shut the capin dog up. man",
                      "Shut the damn dog up, man!", "Shut the damn dog up, man!", "/shut the capin dog up. man"]
        let ocr = ScriptedReader(script.map { [gline($0, box)] })
        let reader = GR.Reader(textReader: ocr, clock: clock, configuration: cfg)
        var shown: [String] = []
        var replaced = 0
        for i in script.indices {
            clock.nowMs += 300
            for e in await reader.process(FakeFrame(i)).events {
                switch e {
                case let .subtitleStarted(s): shown.append(s.text)
                case let .subtitleUpdated(s), let .subtitleCorrected(s): shown.append(s.text); replaced += 1
                default: break
                }
            }
        }
        XCTAssertEqual(shown, ["And shut the damn dog up.", "Shut the damn dog up, man!"])
        XCTAssertEqual(replaced, 1, "ikinci satır ekrandakinin yerine konur")
    }

    /// Satır bandındaki 2 harfli gerçek cevaplar çevrilir; noktalamasız etiket atılır.
    func testShortAnswersInBand() async {
        for t in ["OK.", "No.", "Go!", "NO!", "Hi?"] {
            var s = GR.Stabilizer()
            XCTAssertEqual(s.observe(t, now: 0), .translate(t), t)
            XCTAssertFalse(F.isItemLabel(t), t)
        }
        var s = GR.Stabilizer()
        XCTAssertEqual(s.observe("OK", now: 0), .none, "noktalamasız 2 harf boş sayılır")
        XCTAssertEqual(s.observe("ok.", now: 100), .none)
        for t in ["BREAD", "LEATHER BOOTS", "CAR WASH", "FRESH FISH, BEST PRICE", "GET YOURS TODAY ONLY!"] { XCTAssertTrue(F.isItemLabel(t), t) }
        // Okuyucu üzerinden (GTA 6 zinciri).
        let clock = GR.ManualClock(0)
        var cfg = GR.Reader.Configuration()
        GR.GTA6Rules.apply(true, packGame: "gta-6", to: &cfg)
        let ocr = ScriptedReader([[gline("OK.", gbox(0.47, 0.5, 0.53, 0.6))], [], [], [], [], [], [gline("Go!", gbox(0.47, 0.5, 0.53, 0.6))]])
        let reader = GR.Reader(textReader: ocr, clock: clock, configuration: cfg)
        var shown: [String] = []
        for i in 0..<7 {
            clock.nowMs += 300
            for e in await reader.process(FakeFrame(i)).events { if case let .subtitleStarted(x) = e { shown.append(x.text) } }
        }
        XCTAssertEqual(shown, ["OK.", "Go!"])
    }

    /// Son okunuşa benzeyen ama gönderilenle ilgisi olmayan satır yeni satırdır.
    func testUnrelatedLineAfterRereadStillTranslates() {
        var s = GR.Stabilizer()
        XCTAssertEqual(s.observe("We have to reach the ferry now.", now: 0), .translate("We have to reach the ferry now."))
        XCTAssertEqual(s.observe("We have to reach the ferry now!", now: 100), .none)
        XCTAssertEqual(s.observe("Then we sail east before dawn.", now: 200), .translate("Then we sail east before dawn."))
    }

    // MARK: Kırpılmış ikinci satır

    func testClippedSecondLineIsDropped() {
        let head = "I'm not! You've got a gun pointed at Peaches' head."
        let a = GR.FilterChain.chain([gline(head, gbox(0.2, 0.30, 0.8, 0.40)),
                                      gline("the best lcan.", gbox(0.47, 0.42, 0.6, 0.52))], area: .full, labels: true)
        XCTAssertEqual(a.map(\.text), [head])
        // İki parçası okunursa satır birleşir, l/I düzelir.
        let b = GR.FilterChain.chain([gline(head, gbox(0.2, 0.30, 0.8, 0.40)),
                                      gline("i'm doing", gbox(0.38, 0.40, 0.49, 0.55)),
                                      gline("the best lcan.", gbox(0.478, 0.42, 0.6, 0.52))], area: .full, labels: true)
        XCTAssertEqual(b.map(\.text), [head, "I'm doing the best I can."])
        // Küçük harfle süren gerçek devam satırları kalır.
        let c = GR.FilterChain.chain([gline("Uh, h-how about Guy,", gbox(0.35, 0.30, 0.65, 0.40)),
                                      gline("is Guy here?", gbox(0.42, 0.42, 0.58, 0.52))], area: .full, labels: true)
        XCTAssertEqual(c.map(\.text), ["Uh, h-how about Guy,", "is Guy here?"])
        let d = GR.FilterChain.chain([gline("I was going to...", gbox(0.35, 0.30, 0.65, 0.40)),
                                      gline("but then it rained.", gbox(0.38, 0.42, 0.62, 0.52))], area: .full, labels: true)
        XCTAssertEqual(d.count, 2)
    }

    /// Kartın ikinci bakışı (etiket süzgeci kapalı) altyazı temizliğinden geçmez: küçük harfle süren gövde kalır.
    func testCardSecondLookKeepsLowercaseBody() {
        let a = GR.FilterChain.chain([gline("Brian", gbox(0.40, 0.30, 0.60, 0.38)),
                                      gline("See you there.", gbox(0.40, 0.40, 0.60, 0.48)),
                                      gline("bring the car keys", gbox(0.40, 0.50, 0.60, 0.58))], area: .full, labels: false, phoneGame: true)
        XCTAssertEqual(a.map(\.text), ["Brian", "See you there.", "bring the car keys"])
    }

    // MARK: Tabela yazısı

    func testSignTextBesideSubtitle() {
        let sub = "Hey, uh, I- I forgot my wallet, I'll- I'll be right back."
        // Ayrı parça: ne OCR birleştirmesinde ne aynı sıra birleştirmesinde katılır.
        let sign = gline("NO ALCOHOL ToWAr", gbox(0.10, 0.50, 0.26, 0.58))
        let line = gline(sub, gbox(0.28, 0.52, 0.72, 0.58))
        let merged = GR.OCR.mergeFragments([sign, line], aspect: 3.6) { _ in nil }
        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(F.mergeSameRow([sign, line]).count, 2)
        XCTAssertEqual(F.mergeSameRow([gline("FRATE PHYS", gbox(0.20, 0.52, 0.26, 0.58)), line]).count, 2)
        // Telefon oyunu zinciri: yalnız altyazı.
        var chain = GR.FilterChain()
        var ctx = GR.FilterChain.Context(now: 0, area: gbox(0.14, 0.62, 0.86, 0.97))
        ctx.phoneGame = true; ctx.cardsEnabled = true; ctx.questLine = nil
        let r = chain.run([sign, line], ctx)
        XCTAssertEqual(r.text, sub)
        // Vision tek parça okuduysa baştaki tabela kısmı atılır.
        XCTAssertEqual(F.stripSignPrefix("FRATE PHYS " + sub), sub)
        XCTAssertEqual(F.stripSignPrefix("NO ALCOHOL ToWAr " + sub), sub)
        let r2 = chain.run([gline("FRATE PHYS Hey, uh, I- I forgot my wallet, III- I'II be right back.", gbox(0.28, 0.52, 0.72, 0.58))], ctx)
        XCTAssertEqual(r2.text, sub)
        // Simge yerinde bölünen satır yine birleşir.
        let hold = GR.OCR.mergeFragments([gline("Hold", gbox(0.30, 0.80, 0.36, 0.85)), gline("to continue", gbox(0.42, 0.805, 0.60, 0.85))],
                                         aspect: 1) { _ in nil }
        XCTAssertEqual(hold.count, 1)
        for (key, rest) in [("OPTIONS", "to pause the game"), ("HOLD", "to open the map"), ("TOUCHPAD", "to view your phone")] {
            let m = GR.OCR.mergeFragments([gline(key, gbox(0.30, 0.80, 0.38, 0.85)), gline(rest, gbox(0.40, 0.80, 0.60, 0.85))], aspect: 1) { _ in nil }
            XCTAssertEqual(m.count, 1, key)
        }
        XCTAssertEqual(F.mergeSameRow([gline("Brenna:", gbox(0.30, 0.80, 0.36, 0.85)), gline("Hold the line.", gbox(0.37, 0.80, 0.60, 0.85))]).count, 1)
    }

    /// Gerçek kısa altyazılar ve büyük harfli bağırmalar atılmaz.
    func testShortAndShoutedSubtitlesSurvive() {
        for s in ["No!", "OK.", "FIND SHELTER!", "GET DOWN!", "WHY?", "NO! Get back here, now.", "OK Hey there, you made it.",
                  "FBI agents are here.", "HELP Me!", "STOP RIGHT THERE! Hands up."] {
            XCTAssertEqual(F.stripSignPrefix(s), s, s)
            XCTAssertEqual(F.stripLeadingBullets(F.cleanJunk(s)), s, s)
        }
        var chain = GR.FilterChain()
        var ctx = GR.FilterChain.Context(now: 0, area: gbox(0.14, 0.62, 0.86, 0.97))
        ctx.phoneGame = true; ctx.cardsEnabled = true; ctx.questLine = nil
        for s in ["No!", "OK.", "FIND SHELTER!", "GET DOWN!", "Go!"] {
            XCTAssertEqual(chain.run([gline(s, gbox(0.45, 0.6, 0.55, 0.68))], ctx).text, s, s)
        }
    }
}

#if canImport(Vision)
/// Kullanıcının GTA 6 kareleri (22 Kasım 17:20, 1280 genişlik; kişisel bilgi yok).
final class GameReadingLiveFramesTests: XCTestCase {
    static func image(_ name: String) throws -> CGImage {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "jpg", subdirectory: "Resources/gta6-subtitle"))
        let src = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try XCTUnwrap(CGImageSourceCreateImageAtIndex(src, 0, nil))
    }

    func testDogScene() async throws {
        let clock = GR.ManualClock(0)
        var cfg = GR.Reader.Configuration()
        GR.GTA6Rules.apply(true, packGame: "gta-6", to: &cfg)
        let reader = GR.Reader(textReader: GR.VisionTextReader(), clock: clock, configuration: cfg)
        var sent: [String] = []
        for (name, repeats) in [("sub-14-20-44-287", 2), ("sub-14-20-45-021", 3), ("sub-14-20-47-053", 3), ("sub-14-20-48-653", 3),
                                ("sub-14-20-50-057", 3), ("sub-14-20-52-065", 3), ("sub-14-20-53-746", 3)] {
            let f = GR.ImageFrame(try Self.image(name))
            for _ in 0..<repeats {
                clock.nowMs += 300
                let out = await reader.process(f)
                for e in out.events {
                    switch e {
                    case let .subtitleStarted(s), let .subtitleUpdated(s), let .subtitleCorrected(s): sent.append(s.text)
                    default: break
                    }
                }
            }
        }
        // 1280 genişlikte Vision göstergenin iğnesini `-`/`..` okur, `I can`'i `Ican`; `Shut up, dog!`'u `up, dog:-` okur (çevrilmez).
        XCTAssertEqual(sent.first, "And shut the damn dog up")
        XCTAssertFalse(sent.contains { $0.lowercased().contains("gamn") || $0.lowercased().contains("capin") }, "solarken okunan yeni satır olmadı: \(sent)")
        XCTAssertTrue(sent.contains { $0.hasSuffix("I'm doing the best I can.") }, "\(sent)")
        XCTAssertFalse(sent.contains { $0.contains("lcan") || $0.contains("Ican") || $0.contains("•") || $0.contains("«") || $0.hasPrefix("/") || $0.hasPrefix("- ") || $0.contains("\n- ") }, "\(sent)")
        XCTAssertFalse(sent.contains { $0.split(separator: "\n").contains { $0.first?.isLowercase == true } }, "\(sent)")
    }
}
#endif
