// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation
import XCTest
@testable import NinoCore

final class TranslationKeyTests: XCTestCase {
    func testNormalizes() {
        XCTAssertEqual(TranslationKey.make("  “Come   HERE…” "), "\"come here...\"")
        XCTAssertEqual(TranslationKey.make("It’s fine"), "it's fine")
    }

    func testKeepsPunctuation() {
        XCTAssertNotEqual(TranslationKey.make("Run."), TranslationKey.make("Run?"))
    }
}

final class TranslationCacheTests: XCTestCase {
    func testStoreAndLookupByKey() async {
        let cache = TranslationCache()
        await cache.store(source: "Come here.", text: "Buraya gel.", origin: "p1")
        let hit = await cache.lookup("  come   HERE. ")
        XCTAssertEqual(hit, "Buraya gel.")
        let miss = await cache.lookup("Come here?")
        XCTAssertNil(miss)
    }

    func testEvictsLeastRecentlyUsed() async {
        let cache = TranslationCache(capacity: 2)
        await cache.store(source: "a1", text: "A", origin: "p")
        await cache.store(source: "b1", text: "B", origin: "p")
        _ = await cache.lookup("a1")
        await cache.store(source: "c1", text: "C", origin: "p")
        let a = await cache.lookup("a1"), b = await cache.lookup("b1"), c = await cache.lookup("c1")
        XCTAssertEqual(a, "A")
        XCTAssertNil(b)
        XCTAssertEqual(c, "C")
    }

    func testPersistsToDisk() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("nino-cache-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("cache.json")
        let first = TranslationCache(fileURL: url)
        await first.store(source: "Come here.", text: "Buraya gel.", origin: "p1")
        try await first.save()

        let second = TranslationCache(fileURL: url)
        let hit = await second.lookup("Come here.")
        XCTAssertEqual(hit, "Buraya gel.")
        let count = await second.count
        XCTAssertEqual(count, 1)
    }
}

final class TermProtectorTests: XCTestCase {
    func testProtectsLongestFirstCaseInsensitive() {
        let p = TermProtector(terms: [Term("Vale"), Term("Vale Harbor", "Vale Limanı")])
        let protected = p.protect("Meet me at vale harbor, Vale.")
        XCTAssertEqual(protected.text, "Meet me at ⟦0⟧, ⟦1⟧.")
        XCTAssertEqual(protected.replacements, ["Vale Limanı", "Vale"])
    }

    func testRespectsWordBoundaries() {
        let p = TermProtector(terms: [Term("Osk")])
        XCTAssertEqual(p.protect("Oskar met Osk.").text, "Oskar met ⟦0⟧.")
    }

    func testRestoreWithSuffixAndSpaces() {
        let p = TermProtector(terms: [Term("Osk")])
        let protected = p.protect("Give it to Osk.")
        XCTAssertEqual(p.restore("Onu ⟦ 0 ⟧'a ver.", protected), "Onu Osk'a ver.")
    }

    func testRestoreFailsWhenPlaceholderLost() {
        let p = TermProtector(terms: [Term("Osk")])
        let protected = p.protect("Give it to Osk.")
        XCTAssertNil(p.restore("Onu ver.", protected))
    }

    func testNoTerms() {
        let p = TermProtector(terms: [])
        let protected = p.protect("Hello.")
        XCTAssertEqual(protected.text, "Hello.")
        XCTAssertEqual(p.restore("Merhaba.", protected), "Merhaba.")
    }
}

final class TurkishPostProcessorTests: XCTestCase {
    private let p = TurkishPostProcessor()

    func testSpacing() {
        XCTAssertEqual(p.process("Tamam ,  gidelim !", source: "Okay, let's go!"), "Tamam, gidelim!")
        XCTAssertEqual(p.process("Evet,hayır", source: "Yes, no"), "Evet, hayır")
    }

    func testTurkishCapitalization() {
        XCTAssertEqual(p.process("iyi misin?", source: "Are you okay?"), "İyi misin?")
        XCTAssertEqual(p.process("ılık su.", source: "Warm water."), "Ilık su.")
        XCTAssertEqual(p.process("iyi.", source: "...fine."), "iyi.")
    }

    func testEndPunctuationFollowsSource() {
        XCTAssertEqual(p.process("Neden", source: "Why?"), "Neden?")
        XCTAssertEqual(p.process("Bekle", source: "Wait..."), "Bekle...")
        XCTAssertEqual(p.process("Bekle", source: "Wait…"), "Bekle...")
        XCTAssertEqual(p.process("Tamam", source: "Okay"), "Tamam")
    }

    func testDots() {
        XCTAssertEqual(p.process("Bitti..", source: "Done."), "Bitti.")
        XCTAssertEqual(p.process("Peki…", source: "Well..."), "Peki...")
        XCTAssertEqual(p.process("Peki....", source: "Well..."), "Peki...")
    }
}

final class ProviderChainTests: XCTestCase {
    func testFallsThroughFailures() async {
        let a = FakeProvider("a", .fail), b = FakeProvider("b", .empty), c = FakeProvider("c", .echo)
        let d = FakeProvider("d", .dictionary(["Hi.": "Selam."]))
        let chain = ProviderChain(providers: [a, b, c, d])
        let result = await chain.translate("Hi.", from: "en", to: "tr")
        XCTAssertEqual(result?.text, "Selam.")
        XCTAssertEqual(result?.provider, "d")
        XCTAssertEqual(a.calls.count + b.calls.count + c.calls.count, 3)
    }

    func testTimeout() async {
        let slow = FakeProvider("slow", .slow(.seconds(5)))
        let ok = FakeProvider("ok", .dictionary(["Hi.": "Selam."]))
        let chain = ProviderChain(providers: [slow, ok], timeout: .milliseconds(50))
        let started = Date()
        let result = await chain.translate("Hi.", from: "en", to: "tr")
        XCTAssertEqual(result?.provider, "ok")
        XCTAssertLessThan(Date().timeIntervalSince(started), 2)
    }

    func testRejectedByAcceptGoesToNext() async {
        let a = FakeProvider("a", .dictionary(["Hi ⟦0⟧.": "Selam."]))
        let b = FakeProvider("b", .dictionary(["Hi ⟦0⟧.": "Selam ⟦0⟧."]))
        let chain = ProviderChain(providers: [a, b])
        let result = await chain.translate("Hi ⟦0⟧.", from: "en", to: "tr") { $0.contains("⟦0⟧") }
        XCTAssertEqual(result?.provider, "b")
    }

    func testRestsAfterRepeatedFailuresThenReturns() async {
        final class Clock: @unchecked Sendable { var t = Date(timeIntervalSince1970: 0) }
        let clock = Clock()
        let bad = FakeProvider("bad", .fail)
        let ok = FakeProvider("ok", .transform { _ in "tamam" })
        let chain = ProviderChain(providers: [bad, ok], failureLimit: 3, cooldown: 60, now: { clock.t })
        for _ in 0..<3 { _ = await chain.translate("x", from: "en", to: "tr") }
        let resting = await chain.resting()
        XCTAssertEqual(resting, ["bad"])
        _ = await chain.translate("x", from: "en", to: "tr")
        XCTAssertEqual(bad.calls.count, 3)

        clock.t = clock.t.addingTimeInterval(61)
        _ = await chain.translate("x", from: "en", to: "tr")
        XCTAssertEqual(bad.calls.count, 4)
    }

    func testEchoDoesNotBenchProvider() async {
        let p = FakeProvider("p", .transform { $0 == "Go." ? "Git." : $0 })
        let chain = ProviderChain(providers: [p], failureLimit: 3)
        for line in ["Hmm.", "Ha!", "Osk"] { _ = await chain.translate(line, from: "en", to: "tr") }
        let resting = await chain.resting()
        XCTAssertEqual(resting, [])
        let r = await chain.translate("Go.", from: "en", to: "tr")
        XCTAssertEqual(r?.text, "Git.")
    }

    func testAllFailReturnsNil() async {
        let chain = ProviderChain(providers: [FakeProvider("a", .fail)])
        let result = await chain.translate("Hi.", from: "en", to: "tr")
        XCTAssertNil(result)
    }
}

struct FakePack: PhraseLookup {
    var lines: [String: String]
    var terms: [Term]
    func lookup(_ sentence: String) -> String? { lines[TranslationKey.make(sentence)] }
}

final class TranslatorTests: XCTestCase {
    func testOrderCacheThenPackThenChain() async {
        let provider = FakeProvider("p", .dictionary(["Come here.": "buraya gel."]))
        let cache = TranslationCache()
        await cache.store(source: "Hello.", text: "Merhaba (önbellek).", origin: "p")
        let pack = FakePack(lines: ["hello.": "Merhaba (paket).", "bye.": "Hoşça kal (paket)."], terms: [])
        let t = Translator(cache: cache, chain: ProviderChain(providers: [provider]), pack: pack)

        let a = await t.translate("Hello.")
        XCTAssertEqual(a, Translation(source: "Hello.", text: "Merhaba (önbellek).", origin: .cache))
        let b = await t.translate("Bye.")
        XCTAssertEqual(b.origin, .pack)
        let c = await t.translate("Come here.")
        XCTAssertEqual(c, Translation(source: "Come here.", text: "Buraya gel.", origin: .provider("p")))
        XCTAssertEqual(provider.calls, ["Come here."])

        // İkinci kez çevirmene gitmez.
        let again = await t.translate("Come here.")
        XCTAssertEqual(again.origin, .cache)
        XCTAssertEqual(provider.calls.count, 1)
        // Paketten gelen önbelleğe yazılmaz.
        let packCached = await cache.lookup("Bye.")
        XCTAssertNil(packCached)
    }

    func testTermsProtectedAndUserTermsWin() async {
        let provider = FakeProvider("p", .transform { $0.replacingOccurrences(of: "Give it to", with: "Onu ver:") })
        let pack = FakePack(lines: [:], terms: [Term("Osk", "Osk (paket)")])
        let t = Translator(chain: ProviderChain(providers: [provider]), pack: pack, userTerms: [Term("Osk", "Osko")])
        let r = await t.translate("Give it to Osk.")
        XCTAssertEqual(provider.calls, ["Give it to ⟦0⟧."])
        XCTAssertEqual(r.text, "Onu ver: Osko.")
    }

    func testLostPlaceholderFallsToNextProvider() async {
        let a = FakeProvider("a", .transform { _ in "Onu ver." })
        let b = FakeProvider("b", .transform { $0.replacingOccurrences(of: "Give it to", with: "Onu ver:") })
        let t = Translator(chain: ProviderChain(providers: [a, b]), userTerms: [Term("Osk")])
        let r = await t.translate("Give it to Osk.")
        XCTAssertEqual(r.origin, .provider("b"))
        XCTAssertEqual(r.text, "Onu ver: Osk.")
    }

    func testTermOnlySentenceSkipsProviders() async {
        let p = FakeProvider("p", .fail)
        let t = Translator(chain: ProviderChain(providers: [p]), userTerms: [Term("Osk")])
        let r = await t.translate("Osk!")
        XCTAssertEqual(r.text, "Osk!")
        XCTAssertTrue(p.calls.isEmpty)
    }

    func testAllFailReturnsSourceMarkedFailed() async {
        let t = Translator(chain: ProviderChain(providers: [FakeProvider("a", .fail)]))
        let r = await t.translate("Come here.")
        XCTAssertEqual(r.text, "Come here.")
        XCTAssertTrue(r.failed)
    }
}
