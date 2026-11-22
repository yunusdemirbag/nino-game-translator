// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation
import XCTest
@testable import NinoCore

final class ProvidersSuffixTests: XCTestCase {
    func testSuffixTable() {
        let cases: [(String, String, String)] = [
            ("Orrin", "da", "Orrin'de"), ("Orrin", "nın", "Orrin'in"),
            ("Nadia", "u", "Nadia'yı"), ("Nadia", "un", "Nadia'nın"), ("Nadia", "la", "Nadia'yla"),
            ("Westport", "daki", "Westport'taki"), ("Elif", "ya", "Elif'e"),
            ("Ejder Kılıcı", "u", "Ejder Kılıcı'nı"), ("Ejder Kılıcı", "da", "Ejder Kılıcı'nda"),
            ("ateş oku", "u", "ateş okunu"),
            ("ağaç", "u", "ağacı"), ("dolap", "u", "dolabı"), ("yaprak", "u", "yaprağı"),
            ("çelenk", "u", "çelengi"), ("ip", "u", "ipi"),
            ("kapı", "u", "kapıyı"), ("zırh", "la", "zırhla"),
            ("NPC", "u", "NPC'yi"), ("Westport", "A", "Westport'a"),
        ]
        for (term, suffix, expected) in cases {
            XCTAssertEqual(TurkishSuffix.attach(term, suffix: suffix), expected, "\(term) + \(suffix)")
        }
        XCTAssertEqual(TurkishSuffix.attach("Orrin", suffix: "un", apostrophe: "’"), "Orrin’in")
        XCTAssertEqual(TurkishSuffix.attach("Orrin", suffix: "x1"), "Orrin'x1")
    }
}

final class ProvidersNameShieldTests: XCTestCase {
    var glossary: Glossary {
        var g = Glossary()
        g.addTerm("Ashford", "Ashford")
        g.addTerm("stamina tonic", "dayanıklılık iksiri")
        return g
    }

    func testSkipsNamesInSourceAndRebuildsSuffix() {
        let shield = NameShield(glossary: glossary)
        let s = shield.shield("Torvek, go to Ashford.")
        XCTAssertEqual(s.text, "Torvek, go to Mirdal.")
        XCTAssertEqual(shield.restore("Mirdal'a git.", s), "Ashford'a git.")
    }

    func testSentenceStartCapitalAndPlainName() {
        let shield = NameShield(glossary: glossary)
        let s = shield.shield("Drink the stamina tonic. First the stamina tonic!")
        XCTAssertEqual(s.own, ["Torvek": "dayanıklılık iksiri"])
        XCTAssertEqual(shield.restore("Torvek'i iç. Önce Torvek!", s), "Dayanıklılık iksirini iç. Önce dayanıklılık iksiri!")
        XCTAssertNil(shield.restore("Yola çıkıyoruz.", s))
    }

    func testQuotedName() {
        let shield = NameShield(glossary: glossary)
        let s = shield.shield("She whispered 'Ashford' twice.")
        XCTAssertEqual(shield.restore("İki kez 'Torvek' diye fısıldadı.", s), "İki kez 'Ashford' diye fısıldadı.")
        XCTAssertEqual(shield.restore("Torveke dön.", s), "Ashford'a dön.")
    }

    func testForeignContextNameInvalidates() {
        let shield = NameShield(glossary: glossary)
        let s = shield.shield("Move quickly.", context: "Ashford is burning.")
        XCTAssertEqual(s.foreign, ["Torvek"])
        XCTAssertNil(shield.restore("Torvek yanıyor *** Çabuk ilerle.", s))
        XCTAssertEqual(shield.restore("Çabuk ilerle.", s), "Çabuk ilerle.")
    }
}

final class ProvidersGlossaryTests: XCTestCase {
    func testEmptyFingerprint() {
        XCTAssertEqual(Glossary().fingerprint, "g811c9dc5")
    }

    func testFingerprintMatchesManualFNV() {
        var g = Glossary()
        g.addTerm("Echo", "Echo", exact: true)
        var h: UInt32 = 2_166_136_261
        for b in "echo\u{1}Echo\u{3}\u{2}".utf8 { h ^= UInt32(b); h = h &* 16_777_619 }
        XCTAssertEqual(g.fingerprint, "g" + String(format: "%08x", h))
    }

    func testParseRelaxedAndRules() throws {
        let json = #"""
        { // yorum
          "game": "Ember Saga",
          "terms": { "Frost  Lance": "Ayaz Mızrağı", "": "x", "Blank": "" },
          "keep": ["Orrin", "Nadia",],
          "keepExact": ["Echo"],
          "phrases": { "(?:pop|light) (?:a )?flares?(?! gun)": "fire a flare", "aggro": "provoke", "(bad": "x" },
          "lines": { "taking fire": "Ateş altındayım", },
        }
        """#
        let g = try XCTUnwrap(Glossary.parse(Data(json.utf8)))
        XCTAssertEqual(g.game, "Ember Saga")
        XCTAssertEqual(g.terms.count, 4)
        XCTAssertEqual(g.phrases.count, 2)
        XCTAssertEqual(g.matches(in: "Echo answered the call.").map(\.term.english), ["Echo"])
        XCTAssertTrue(g.matches(in: "a faint echo").isEmpty)
        XCTAssertEqual(g.matches(in: "Grab the frost lance, Orrin").map(\.term.turkish), ["Ayaz Mızrağı", "Orrin"])
        XCTAssertTrue(g.matches(in: "Orrinx").isEmpty)
        XCTAssertEqual(g.applyPhrases("Aggro the guards"), "Provoke the guards")
        XCTAssertEqual(g.applyPhrases("light flares now"), "fire a flare now")
        XCTAssertEqual(g.readyLine(for: "Taking fire!"), "Ateş altındayım!")
        XCTAssertEqual(g.readyLine(for: "  TAKING FIRE... "), "Ateş altındayım...")
        XCTAssertNil(g.readyLine(for: "Taking"))
        XCTAssertTrue(g.capitalizedWords.contains("Frost"))
        XCTAssertFalse(g.capitalizedWords.contains("Echo"))
    }

    func testLongestFirstAndMerge() {
        var a = Glossary()
        a.addTerm("lance", "mızrak")
        a.addTerm("Frost Lance", "Ayaz Mızrağı")
        XCTAssertEqual(a.matches(in: "the Frost Lance").map(\.term.turkish), ["Ayaz Mızrağı"])
        var b = Glossary()
        b.addTerm("Lance", "kargı")
        XCTAssertEqual(a.merged(with: b).terms["lance"]?.turkish, "kargı")
        a.addTerm(String(repeating: "a", count: 81), "x")
        XCTAssertEqual(a.terms.count, 2)
    }

    func testBuiltinLoads() {
        let g = BuiltinGlossary.enTr
        XCTAssertFalse(g.terms.isEmpty)
        XCTAssertEqual(g.readyLine(for: "Taking fire!"), "Ateş altındayım!")
        XCTAssertEqual(g.applyPhrases("Ten-four, moving."), "Understood, moving.")
        XCTAssertEqual(g.terms["ghost\u{3}"], nil)
        XCTAssertEqual(g.terms["Ghost\u{3}"]?.exact, true)
    }

    func testFolderOverridesAndThrottles() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("nino-gl-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data(#"{"terms":{"mana flask":"mana şişesi"}}"#.utf8).write(to: dir.appendingPathComponent("b.json"))
        try Data("bozuk".utf8).write(to: dir.appendingPathComponent("a.json"))
        let clock = ProvidersClock()
        let folder = GlossaryFolder(directory: dir, now: { clock.now })
        var g = await folder.current()
        XCTAssertEqual(g.terms["mana flask"]?.turkish, "mana şişesi")
        try Data(#"{"terms":{"mana flask":"büyü matarası"}}"#.utf8).write(to: dir.appendingPathComponent("c.json"))
        g = await folder.current()
        XCTAssertEqual(g.terms["mana flask"]?.turkish, "mana şişesi")
        clock.advance(5)
        g = await folder.current()
        XCTAssertEqual(g.terms["mana flask"]?.turkish, "büyü matarası")
    }
}

/// Testlerde elle ilerletilen saat.
final class ProvidersClock: @unchecked Sendable {
    private let lock = NSLock()
    private var t = Date(timeIntervalSince1970: 1_000_000)
    var now: Date { lock.withLock { t } }
    func advance(_ s: TimeInterval) { lock.withLock { t = t.addingTimeInterval(s) } }
}

final class ProvidersIdiomTests: XCTestCase {
    func testIdioms() {
        XCTAssertEqual(GameIdioms.apply("Haul tail, the drone is out of juice!"), "Run fast, the drone is out of power!")
        XCTAssertEqual(GameIdioms.apply("We’re toast."), "We are finished.")
        XCTAssertEqual(GameIdioms.apply("Hit the deck now"), "Lie flat now")
        XCTAssertEqual(GameIdioms.apply("haultail"), "haultail")
        XCTAssertEqual(GameIdioms.apply("Radio silences everywhere"), "Radio silences everywhere")
        XCTAssertEqual(GameIdioms.apply("Waste ’em all."), "Kill them all.")
    }
}

final class ProvidersShortLineTests: XCTestCase {
    func testExtractTable() {
        XCTAssertEqual(ShortLineContext.extract("Ben değil. *** Sen değil.", source: "Not you."), "Sen değil.")
        XCTAssertNil(ShortLineContext.extract("Ben değil. Sen değil.", source: "Not you."))
        XCTAssertNil(ShortLineContext.extract("A *** B *** C", source: "Not you."))
        XCTAssertNil(ShortLineContext.extract("**** Sen değil.", source: "Not you."))
        XCTAssertNil(ShortLineContext.extract("Ben *** " + String(repeating: "a", count: 45), source: "Not you."))
    }

    func testShortAndMemory() {
        XCTAssertTrue(ShortLineContext.isShort("Boy!"))
        XCTAssertTrue(ShortLineContext.isShort("Do it now."))
        XCTAssertFalse(ShortLineContext.isShort("We must go now."))
        XCTAssertFalse(ShortLineContext.isShort("..."))
        XCTAssertEqual(ShortLineContext.join(previous: "I said no.", short: "Not you."), "I said no. *** Not you.")
        var m = ShortLineMemory()
        let t0 = Date(timeIntervalSince1970: 0)
        m.shown(["We go.", "Stay close."], at: t0)
        XCTAssertEqual(m.previous(for: ["Boy!"], index: 0, now: t0.addingTimeInterval(10)), "Stay close.")
        XCTAssertNil(m.previous(for: ["Boy!"], index: 0, now: t0.addingTimeInterval(21)))
        XCTAssertEqual(m.previous(for: ["Run.", "Boy!"], index: 1, now: t0), "Run.")
    }
}

struct ProvidersFixedGuesser: LanguageGuesser {
    let value: [String: Double]
    func probability(_ text: String, is language: String, among languages: [String]) -> Double { value[language] ?? 0 }
}

final class ProvidersTargetCheckTests: XCTestCase {
    func testTurkishLettersAndException() {
        let english = TargetLanguageCheck(guesser: ProvidersFixedGuesser(value: ["en": 0.95, "tr": 0.05]))
        XCTAssertTrue(english.isAlreadyTarget("Ayarlar ışık", target: "tr"))
        XCTAssertFalse(english.isAlreadyTarget("Sure beats jailsır if you ask", target: "tr"))
        let unsure = TargetLanguageCheck(guesser: ProvidersFixedGuesser(value: ["en": 0.5]))
        XCTAssertTrue(unsure.isAlreadyTarget("Sure beats jailsır if you ask", target: "tr"))
    }

    func testScriptsAndGuesser() {
        let none = TargetLanguageCheck(guesser: ProvidersFixedGuesser(value: [:]))
        XCTAssertTrue(none.isAlreadyTarget("مرحبا", target: "ar"))
        XCTAssertTrue(none.isAlreadyTarget("สวัสดี", target: "th"))
        XCTAssertFalse(none.isAlreadyTarget("Hello there friend", target: "th"))
        let turkish = TargetLanguageCheck(guesser: ProvidersFixedGuesser(value: ["tr": 0.95]))
        XCTAssertTrue(turkish.isAlreadyTarget("Oyuna devam et lütfen", target: "tr"))
        XCTAssertFalse(turkish.isAlreadyTarget("Devam et", target: "tr"))
    }

    func testAfterTranslation() {
        XCTAssertTrue(TargetLanguageCheck.shouldHide(source: "Orrin!", translation: "Orrin!", fromPack: false))
        XCTAssertFalse(TargetLanguageCheck.shouldHide(source: "Orrin!", translation: "Orrin!", fromPack: true))
        XCTAssertTrue(TargetLanguageCheck.shouldHide(source: "Devam ışık", translation: "Devam ışık", fromPack: true))
        XCTAssertFalse(TargetLanguageCheck.shouldHide(source: "Run!", translation: "Koş!", fromPack: false))
    }
}

final class ProvidersLanguageTests: XCTestCase {
    func testList() {
        XCTAssertEqual(TargetLanguage.all.count, 11)
        XCTAssertEqual(TargetLanguage.find("fil-PH")?.code, "tl")
        XCTAssertEqual(TargetLanguage.find("tl")?.interfaceCode, "fil")
        XCTAssertEqual(TargetLanguage.find("TR-tr")?.promptName, "Turkish")
        XCTAssertEqual(TargetLanguage.all.filter(\.deepLSupported).map(\.code).sorted(), ["ar", "id", "nl", "th", "tr", "vi"])
        XCTAssertEqual(TargetLanguage.initial(preferred: ["de-DE"]).code, "tr")
        XCTAssertEqual(TargetLanguage.initial(preferred: ["vi-VN"]).code, "vi")
        XCTAssertTrue(TargetLanguage.isRightToLeft("ur"))
        XCTAssertEqual(TargetLanguage.markRightToLeft("NADIA: مرحبا\nhi"), "\u{200F}NADIA: مرحبا\nhi")
        XCTAssertEqual(TargetLanguage.markRightToLeft("\u{200F}مرحبا"), "\u{200F}مرحبا")
    }
}

final class ProvidersClassicTurkishTests: XCTestCase {
    func testPolishTable() {
        let r = ClassicTurkishRules()
        let cases: [(String, String, String)] = [
            ("Run!", "Koş.", "Koş!"), ("Run!", "Koş", "Koş!"), ("What?!", "Ne?", "Ne?!"),
            ("Wait…", "Bekle.", "Bekle…"), ("Where is he?", "O nerede.", "O nerede?"),
            ("He said \"Run!\"", "\"Koş.\" dedi.", "\"Koş.\" dedi."), ("\"Run!\"", "\"Koş.\"", "\"Koş!\""),
            ("We go.", "Gidiyoruz!", "Gidiyoruz!"), ("Okay. Go.", "Dur , bekle !", "Dur, bekle!"),
            ("Okay. Go.", "Peki ... gidelim .", "Peki... gidelim."),
            ("She said \"hide\", Orrin's sister.", "“Saklan” dedi, Orrin’in kız kardeşi.", "\"Saklan\" dedi, Orrin'in kız kardeşi."),
            ("He said “run”.", "\"Koş\" dedi.", "“Koş” dedi."),
            ("Hm.", "...", "..."),
        ]
        for (src, tr, expected) in cases {
            XCTAssertEqual(r.polish(tr, source: src), expected, "\(src) | \(tr)")
        }
    }

    func testAddressTable() {
        let r = ClassicTurkishRules()
        XCTAssertEqual(r.applyAddress(["Seni gördüm.", "Koşun!", "Sakin olun, dostum."]),
                       ["Seni gördüm.", "Koş!", "Sakin ol, dostum."])
        XCTAssertEqual(r.applyAddress(["Seni buldum. Çabuk saklanın!"]), ["Seni buldum. Çabuk saklan!"])
        XCTAssertEqual(r.applyAddress(["Bekleyin!"]), ["Bekleyin!"])
        XCTAssertEqual(r.applyAddress(["Siz saklanın, seni sonra ararım!"]), ["Siz saklanın, seni sonra ararım!"])
        XCTAssertEqual(r.applyAddress(["Sen gelin misin?"]), ["Sen gelin misin?"])
    }
}

final class ProvidersEngineCacheTests: XCTestCase {
    func testFileNames() {
        XCTAssertEqual(EngineCache.fileName(engine: "apple-p3", source: "en", target: "tr"), "v1-apple-p3-en-tr.jsonl")
        XCTAssertEqual(EngineCache.fileName(engine: "gemini:gemini-3.5-flash-lite", source: "en", target: "tr"),
                       "v1h-1aa82a53a8896bbdf8841c6a44e31bc0ec2a382935938bda14071a3444e0ca98.jsonl")
        XCTAssertEqual(EngineName.local(baseURL: URL(string: "http://localhost:11434/v1")!, model: "translategemma:4b"),
                       "local:localhost:11434/translategemma:4b")
        XCTAssertEqual(EngineCacheKey.ai("Hi.", game: "Ember Saga"), "Ember Saga\u{1F}Hi.")
        XCTAssertEqual(EngineCacheKey.device("Boy!", context: "Run.", fingerprint: "g1"), "g1\u{1F}Run.\u{1F}Boy!")
    }

    func testJSONLRoundTripAndSeparateEngines() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("nino-ec-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = EngineCacheStore(directory: dir)
        let a = await store.cache(engine: "deepl", source: "en", target: "tr")
        let same = await store.cache(engine: "deepl", source: "en", target: "tr")
        XCTAssertTrue(a === same)
        await a.store("run.", "Koş.")
        await a.store("run.", "Koş.")
        await a.store("", "x")
        let b = await store.cache(engine: "apple-p3", source: "en", target: "tr")
        let missing = await b.lookup("run.")
        XCTAssertNil(missing)
        let file = dir.appendingPathComponent("v1-deepl-en-tr.jsonl")
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "[\"run.\",\"Koş.\"]\n")
        // Bozuk satır atlanır, sonraki kayıt kazanır.
        try Data("[\"run.\",\"Koş.\"]\nbozuk\n[\"run.\",\"Kaç.\"]\n".utf8).write(to: file)
        let reopened = EngineCache(fileURL: file)
        let v = await reopened.lookup("run.")
        XCTAssertEqual(v, "Kaç.")
    }

    func testEvictionAndRewrite() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("nino-ec-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("x.jsonl")
        let c = EngineCache(fileURL: file, capacity: 10)
        for i in 0..<10 { await c.store("k\(i)", "v\(i)") }
        _ = await c.lookup("k0")
        await c.store("k10", "v10")
        let n = await c.count
        XCTAssertEqual(n, 9)  // 11 - (1 + 1)
        let k0 = await c.lookup("k0"), k1 = await c.lookup("k1")
        XCTAssertEqual(k0, "v0")
        XCTAssertNil(k1)
        for i in 11..<20 { await c.store("k\(i)", "v\(i)") }
        let lines = try String(contentsOf: file, encoding: .utf8).split(separator: "\n").count
        XCTAssertLessThan(lines, 20)
    }

    func testDiskFailureKeepsMemory() async {
        let c = EngineCache(fileURL: URL(fileURLWithPath: "/dev/null/nope/x.jsonl"))
        await c.store("a", "b")
        let v = await c.lookup("a")
        XCTAssertEqual(v, "b")
    }
}

final class ProvidersBudgetTests: XCTestCase {
    func testSlidingWindow() async {
        let clock = ProvidersClock()
        let b = RequestBudget(now: { clock.now })
        var ok = await b.acquire("m", limit: 2); XCTAssertTrue(ok)
        clock.advance(10)
        ok = await b.acquire("m", limit: 2); XCTAssertTrue(ok)
        clock.advance(10)
        ok = await b.acquire("m", limit: 2); XCTAssertFalse(ok)
        clock.advance(40)
        ok = await b.acquire("m", limit: 2); XCTAssertTrue(ok)
        ok = await b.acquire("free", limit: nil); XCTAssertTrue(ok)
    }

    func testLowerOnlyLowers() async {
        let b = RequestBudget()
        await b.lower("m", to: 5)
        var l = await b.effectiveLimit("m", 10); XCTAssertEqual(l, 5)
        await b.lower("m", to: 8)
        l = await b.effectiveLimit("m", 10); XCTAssertEqual(l, 5)
        l = await b.effectiveLimit("m", 3); XCTAssertEqual(l, 3)
    }
}
