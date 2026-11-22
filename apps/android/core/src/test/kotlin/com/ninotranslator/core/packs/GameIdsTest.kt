// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.packs

import com.ninotranslator.core.json.Json
import com.ninotranslator.core.pool.LineQueue
import com.ninotranslator.core.pool.PoolConfig
import com.ninotranslator.core.reading.live.GameAskCard
import com.ninotranslator.core.reading.live.GameNames
import com.ninotranslator.core.telemetry.TelemetryEvent.SessionSource
import com.ninotranslator.core.telemetry.TelemetryEvent
import com.ninotranslator.core.translation.FakeClock
import com.ninotranslator.core.translation.FakeHttp
import com.ninotranslator.core.translation.bodyText
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import kotlin.random.Random

class GameIdsTest {
    // ---- havuz sunucusunun tablosuyla aynı vakalar ----

    @Test fun aliasesBecomeCanonical() {
        for (id in listOf("grand-theft-auto-vi", "GTA-VI", "gta6", "gtavi", "pool-gta-6", "gta--6")) assertEquals(id, "gta-6", GameIds.canonical(id))
        assertEquals("gta-v", GameIds.canonical("grand-theft-auto-v"))
        assertEquals("gta-v", GameIds.canonical("gta-v"))
        assertEquals("", GameIds.canonical(""))
        assertEquals(listOf("grand-theft-auto-vi", "gta-vi", "gta6", "gtavi", "pool-gta-6"), GameIds.aliasesOf("gta-6").sorted())
        assertFalse("grand-theft-auto-vi" in GameIds.aliasesOf("gta-v"))
    }

    @Test fun readableNamesAndMerge() {
        assertEquals("GTA 6", GameIds.name("grand-theft-auto-vi"))
        assertEquals("GTA 5", GameIds.name("grand-theft-auto-v"))
        assertEquals("Call of Duty: Modern Warfare (2019)", GameIds.name("call-of-duty--modern-warfare--2019"))
        assertEquals("Assassin's Creed Shadows", GameIds.name("assassin-s-creed-shadows"))
        assertEquals("Some New Game II", GameIds.name("some-new-game-ii"))
        assertEquals("", GameIds.name(""))
        assertEquals(
            listOf(GameIds.Count("gta-6", 224, "GTA 6"), GameIds.Count("gta-v", 7, "GTA 5")),
            GameIds.mergeCounts(listOf("gta-6" to 113L, "grand-theft-auto-vi" to 111L, "gta-v" to 5L, "grand-theft-auto-v" to 2L)),
        )
    }

    // ---- NinoCore GameIDsTests / LineKeyTests.testGameNameID ile aynı vakalar (aynı girdi → aynı çıktı) ----

    @Test fun idMatchesNinoCore() {
        for (raw in listOf("grand-theft-auto-vi", "GTA-VI", "gta6", "gtavi", "pool-gta-6", "gta--6", "gta-6",
                           "Grand Theft Auto VI", "GTA VI", "GTA 6")) assertEquals(raw, "gta-6", GameIds.id(raw))
        for (raw in listOf("grand-theft-auto-v", "gta-5", "gta5", "gtav", "pool-gta-5", "pool-gta-v", "gta-v",
                           "Grand Theft Auto V", "GTA 5", "GTA V")) assertEquals(raw, "gta-v", GameIds.id(raw))
        for ((alias, target) in GameIds.ALIASES) assertEquals(alias, target, GameIds.id(alias))
        assertEquals("death-stranding-2", GameIds.id("Death Stranding 2: On the Beach"))
        assertEquals("mafia-the-old-country", GameIds.id("Mafia: The Old Country"))
        assertNull(GameIds.id("!!!"))
        assertNull(GameIds.id(""))
        assertNull(GameIds.id(null))
        // GameName.id (paket kimliği üretimi): takma ad uygulanmaz.
        assertEquals("grand-theft-auto-vi", GameIds.slug("Grand Theft Auto VI"))
        assertEquals("mafia-the-old-country", GameIds.slug("Mafia: The Old Country"))
        assertEquals("grand-theft-auto-vi", GameIds.slug("  --Grand Theft Auto VI.. "))
        assertNull(GameIds.slug("!!!"))
        assertEquals(64, GameIds.slug("a".repeat(70))?.length)
    }

    @Test fun idSlugRules() {
        // Yeni oyun: tabloda yok, slug'ın kendisi; `pool-` öneki atılmaz (yalnız tablodaki takma adlar).
        assertEquals("yeni-oyun", GameIds.id("Yeni Oyun"))
        assertEquals("pool-yeni-oyun", GameIds.id("pool-yeni-oyun"))
        assertEquals("pool-elden-ring", GameIds.id("pool-elden-ring"))
        // Nokta ve alt çizgi kalır; aksan atılmaz (harf tire olur), Roma rakamı çevrilmez.
        assertEquals("final-fantasy.vii-remake", GameIds.id("final-fantasy.vii-remake"))
        assertEquals("my_game.2", GameIds.id("My_Game.2"))
        assertEquals("ghost-of-yotei", GameIds.id("Ghost of Yōtei"))
        assertEquals("p-k-mon", GameIds.id("Pókémon"))
        assertEquals("final-fantasy-vii", GameIds.id("Final Fantasy VII"))
        assertEquals("marvels-spider-man-2", GameIds.id("Marvel's Spider-Man 2"))
        assertEquals("gta-6", GameIds.id("gta-6."))
        // 64'te kesilir; kesim tireye düşerse tire atılır.
        assertEquals("a".repeat(63), GameIds.id("a".repeat(63) + " b"))
        assertEquals("a".repeat(64), GameIds.id("a".repeat(64) + "bbb"))
        for (raw in listOf(" ", "-._", "™®©", "ğüşıöç", "😀")) assertNull(raw, GameIds.id(raw))
    }

    // ---- uygulamanın kendi girişleri: ad, paket kimliği, ekran ----

    @Test fun namesAndPackIds() {
        for (n in listOf("Grand Theft Auto VI", "GTA 6", "GTA VI", "gta6", "pool-gta-6", " GTA-6 ")) assertEquals(n, "gta-6", GameIds.fromAny(n))
        for (n in listOf("Grand Theft Auto V", "GTA V", "GTA 5", "pool-gta-v")) assertEquals(n, "gta-v", GameIds.fromAny(n))
        assertEquals("marvels-spider-man-2", GameIds.fromAny("Marvel's Spider-Man 2"))
        assertEquals("ghost-of-yotei", GameIds.fromAny("Ghost of Yōtei"))
        assertEquals("call-of-duty-modern-warfare-2019", GameIds.fromAny("Call of Duty: Modern Warfare (2019)"))
        assertEquals("red-dead-redemption-2", GameIds.fromAny("red-dead-redemption-2"))
        assertEquals("elden-ring", GameIds.fromAny("pool-elden-ring"))
        assertNull(GameIds.fromAny("")); assertNull(GameIds.fromAny("  ")); assertNull(GameIds.fromAny(null)); assertNull(GameIds.fromAny("!!"))
        assertEquals("gta-6", GameIds.ofPack("pool-gta-6"))
        assertEquals("gta-6", GameIds.ofPack("pool-grand-theft-auto-vi"))
        assertEquals("elden-ring", GameIds.ofPack("pool-elden-ring"))
        assertEquals("genel", GameIds.ofPack("genel"))
        assertEquals("gta-6", GameIds.upgradeStored("grand-theft-auto-vi"))
        assertEquals("GTA 6", GameIds.upgradeStored("GTA 6"))
        assertNull(GameIds.upgradeStored(null))
        assertTrue(GameNames.sameGame("pool-gta-6", "GTA 6"))
        assertTrue(GameNames.sameGame("grand-theft-auto-vi", "Grand Theft Auto VI"))
        assertFalse(GameNames.sameGame("pool-gta-v", "GTA 6"))
    }

    // ---- sunucuya giden alanlar ----

    @Test fun queueSendsCanonicalGame() {
        val files = TestFiles.tempDir()
        val clock = FakeClock(1_700_000_000_000)
        val http = FakeHttp { r -> FakeHttp.json(200, """{"ok":true,"batch":"${Json.parseObject(r.bodyText)["batch"]}"}""") }
        val q = LineQueue(files, http, "1.0", "http://pool", clock.now, Random(3), session = "o")
        assertTrue(q.offer("Get in the car, Lucia!", "Grand Theft Auto VI"))
        assertEquals("gta-6", Json.parseObject(File(files, "pool/pending.jsonl").readLines()[0])["g"])
        // Eski sürümün kuyrukta bıraktığı takma ad da aynı oyunda birleşir.
        File(files, "pool/pending.jsonl").appendText("""{"s":2,"t":"Get in the car, Lucia!","g":"grand-theft-auto-vi","e":"o","a":1700000000.0}""" + "\n")
        assertTrue(q.offer("Get in the car, Lucia!", "pool-gta-6"))
        assertTrue(q.offer("Climb the wall now!", null))
        assertTrue(q.offer("Climb the wall now!", "pool-elden-ring"))
        // Yeni oyun (tabloda yok): NinoCore PoolQueue gibi slug'la; kimliğe dönmeyen ad alansız.
        assertTrue(q.offer("Climb the wall now!", "Yeni Oyun"))
        assertTrue(q.offer("Climb the wall now!", "GTA 6"))
        assertTrue(q.offer("Hold the line, soldier!", "!!!"))
        assertEquals("yeni-oyun", Json.parseObject(File(files, "pool/pending.jsonl").readLines()[5])["g"])
        q.freeze(); q.send()
        val lines = (Json.parseObject(http.requests.single().bodyText)["lines"] as List<*>).map { it as Map<*, *> }
        assertEquals(
            listOf("Get in the car, Lucia!" to "gta-6", "Climb the wall now!" to null, "Climb the wall now!" to "pool-elden-ring",
                   "Climb the wall now!" to "yeni-oyun", "Climb the wall now!" to "gta-6", "Hold the line, soldier!" to null).sortedBy { "${it.first}${it.second}" },
            lines.map { it["text"] to it["game"] }.sortedBy { "${it.first}${it.second}" },
        )
        assertEquals(3L, lines.single { it["text"] == "Get in the car, Lucia!" }["count"])
    }

    @Test fun oldSyncCursorsMoveToCanonicalId() {
        val dir = TestFiles.tempDir()
        File(dir, "translations-tr.json").writeText("""{"language":"tr","texts":{},"cursors":{"Grand Theft Auto VI":{"since":100},"gta-6":{"since":40},"*":{"since":7}}}""")
        val t = com.ninotranslator.core.pool.PoolTranslations(dir, "tr")
        assertEquals(100L, t.cursor("gta-6").since)
        assertEquals(7L, t.cursor("*").since)
    }

    @Test fun poolFirstAndTelemetry() {
        val c = PoolConfig()
        for (g in listOf("gta-6", "GTA 6", "Grand Theft Auto VI", "pool-gta-6")) assertTrue(g, c.isPoolFirst(g, "tr"))
        assertFalse(c.isPoolFirst("gta-v", "tr"))
        // Sunucu listesi yalnız eski adı taşısa da asıl kimlik eşleşir.
        assertTrue(PoolConfig(poolFirstGames = listOf("grand-theft-auto-vi")).isPoolFirst("gta-6", "tr"))
        assertEquals("gta-6", TelemetryEvent.session(1, "grand-theft-auto-vi", SessionSource.CAPTURE, 0).fields["game"])
        assertEquals("gta-6", TelemetryEvent.session(1, "Grand Theft Auto VI", SessionSource.CAPTURE, 0).fields["game"])
        assertEquals("some-unknown-game", TelemetryEvent.session(1, "Some Unknown Game", SessionSource.CAPTURE, 0).fields["game"])
        assertNull(TelemetryEvent.session(1, "!!!", SessionSource.CAPTURE, 0).fields["game"])
        assertTrue(PoolConfig(poolFirstGames = listOf("yeni-oyun")).isPoolFirst("Yeni Oyun", "tr"))
    }

    // ---- paket listeleri ----

    private fun pack(id: String, title: String) = LegacyPack.parse("""{"format":2,"id":"$id","title":"$title","entries":{"${PackKey.of("Get in the car.")}":"Arabaya bin."}}""", id)

    @Test fun libraryKeepsOneGame() {
        val lib = LegacyPackLibrary(listOf(pack("gta-6", "Grand Theft Auto VI"), pack("pool-gta-6", "GTA 6"), pack("rdr2", "Red Dead Redemption 2")))
        assertEquals(listOf("pool-gta-6", "rdr2"), lib.packs.map { it.id })
        assertEquals(listOf("gta-6"), lib.shadowed.map { it.id })
        assertEquals("pool-gta-6", lib.packForGame("gta-6")?.id)
        assertEquals("pool-gta-6", lib.packForGame("Grand Theft Auto VI")?.id)
        // Başlıkları farklı olsa da kimlikten: eski kimlikli paket de aynı oyun.
        val old = LegacyPackLibrary(listOf(pack("grand-theft-auto-vi", "Vice City"), pack("pool-gta-6", "GTA 6")))
        assertEquals(listOf("pool-gta-6"), old.packs.map { it.id })
        assertEquals(listOf("gta-6", "Red Dead Redemption 2"), GameAskCard.suggestions("gta-6", lib.packs.map { it.title }))
    }

    @Test fun groupPacksPrefersPool() {
        data class P(val id: String, val title: String)
        val groups = GameIds.groupPacks(listOf(P("gta-6", "Grand Theft Auto VI"), P("elden", "Elden Ring"), P("pool-gta-6", "GTA 6"), P("gta-v", "GTA 5")), { it.id }, { it.title })
        assertEquals(listOf(listOf("pool-gta-6", "gta-6"), listOf("elden"), listOf("gta-v")), groups.map { g -> g.map { it.id } })
        // Yeni oyun: havuz paketi `pool-yeni-oyun` ile addan gelen paket tek kart; kütüphanede de tek oyun.
        val fresh = GameIds.groupPacks(listOf(P("community-yeni-oyun", "Yeni Oyun"), P("pool-yeni-oyun", "Yeni Oyun")), { it.id }, { it.title })
        assertEquals(listOf(listOf("pool-yeni-oyun", "community-yeni-oyun")), fresh.map { g -> g.map { it.id } })
        val lib = LegacyPackLibrary(listOf(pack("yeni-oyun", "Yeni Oyun"), pack("pool-yeni-oyun", "Yeni Oyun")))
        assertEquals(listOf("pool-yeni-oyun"), lib.packs.map { it.id })
        assertEquals("pool-yeni-oyun", lib.packForGame("Yeni Oyun")?.id)
        assertEquals("pool-yeni-oyun", lib.packForGame(GameIds.id("Yeni Oyun")!!)?.id)
        assertTrue(GameIds.same("pool-yeni-oyun", "Yeni Oyun"))
    }
}
