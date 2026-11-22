// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.pool

import com.ninotranslator.core.http.HttpResponse
import com.ninotranslator.core.json.Json
import com.ninotranslator.core.packs.TestFiles
import com.ninotranslator.core.translation.FakeClock
import com.ninotranslator.core.translation.FakeHttp
import com.ninotranslator.core.translation.bodyText
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.io.IOException
import kotlin.random.Random

class LineQueueTest {
    private val clock = FakeClock(1_700_000_000_000)
    private var respond: (String) -> HttpResponse = { body -> FakeHttp.json(200, """{"ok":true,"batch":"${Json.parseObject(body)["batch"]}"}""") }
    private val http = FakeHttp { r -> respond(r.bodyText) }

    private fun queue(files: File, app: String = "1.0") = LineQueue(files, http, app, "http://pool", clock.now, Random(7), session = "oturum")

    @Test fun pendingFreezeAndSend() {
        val files = TestFiles.tempDir()
        val q = queue(files)
        assertTrue(q.offer("Climb the wall!", "rdr2"))
        assertTrue(q.offer("Climb the wall!", "rdr2"))
        assertFalse(q.offer("Kapıyı aç", "rdr2"))
        assertEquals(2, q.pending)
        val first = Json.parseObject(File(files, "pool/pending.jsonl").readLines()[0])
        assertEquals(1L, first["s"]); assertEquals("Climb the wall!", first["t"]); assertEquals("rdr2", first["g"]); assertEquals("oturum", first["e"])
        assertEquals(0, q.tick()) // henüz 200 satır yok, 120 sn geçmedi
        clock.advance(120_000)
        assertEquals(1, q.tick())
        val body = Json.parseObject(http.requests.single().bodyText)
        assertEquals(2L, body["upTo"]); assertEquals("android", body["platform"])
        val line = (body["lines"] as List<*>).single() as Map<*, *>
        assertEquals(2L, line["count"]); assertEquals("Climb the wall!", line["text"])
        assertTrue(q.outboxFiles().isEmpty())
        assertEquals(2L, q.state.frozenThrough)
    }

    @Test fun serverResponses() {
        val files = TestFiles.tempDir()
        val q = queue(files)
        for (i in 0 until 3) q.offer("Line number $i here", null)
        q.freeze()
        // Kimlik tutmuyor: silinmez, bekleme başlar.
        respond = { FakeHttp.json(200, """{"ok":true,"batch":"baska"}""") }
        assertEquals(0, q.send()); assertEquals(1, q.outboxFiles().size); assertEquals(1, q.state.failures)
        val wait = q.state.nextAttempt - clock.ms
        assertTrue(wait in 24_000..36_000)
        assertEquals(0, q.send()) // beklemede
        clock.advance(40_000)
        // 413: ikiye bölünür.
        respond = { FakeHttp.json(413, "") }
        q.send()
        assertEquals(2, q.outboxFiles().size)
        // 429: Retry-After kadar.
        respond = { FakeHttp.json(429, "", mapOf("Retry-After" to "5")) }
        q.send(); assertEquals(clock.ms + 5_000, q.state.serverRetryAt)
        clock.advance(5_000)
        // 400: kenara alınır; sürüm değişince geri gelir.
        respond = { FakeHttp.json(400, "") }
        q.send()
        assertEquals(0, q.outboxFiles().size); assertEquals(2, q.parkedDir.listFiles()!!.size)
        val q2 = queue(files, app = "1.1")
        assertEquals(2, q2.outboxFiles().size)
        respond = { body -> FakeHttp.json(200, """{"ok":true,"batch":"${Json.parseObject(body)["batch"]}"}""") }
        assertEquals(2, q2.send())
        // Ağ hatası: artan bekleme, ağ gelince sıfırlanır.
        q2.offer("Another fine line", null); q2.freeze()
        respond = { throw IOException("ağ yok") }
        q2.send(); assertEquals(1, q2.state.failures)
        q2.networkRestored(); assertEquals(0L, q2.state.nextAttempt)
    }

    @Test fun legacyImportTornTailAndClear() {
        val files = TestFiles.tempDir()
        File(files, "line-pool.json").writeText("""{"queue":[{"text":"Old line one","firstSeen":"2026-01-02T03:04:05Z"},{"text":"Türkçe ğ"}]}""")
        File(files, "pool").mkdirs()
        File(files, "pool/pending.jsonl").writeText("""{"s":5,"t":"Kept line","g":null,"e":null,"a":1.0}""" + "\n" + """{"s":6,"t":"yar""")
        File(files, "pool/state.json").writeText("bozuk")
        val q = queue(files)
        assertTrue(files.resolve("pool").listFiles()!!.any { it.name.startsWith("state.broken-") })
        assertEquals(1, q.pending)
        assertEquals(1, q.importLegacy())
        assertTrue(File(files, "line-pool.json.imported").isFile); assertFalse(File(files, "line-pool.json").exists())
        val lines = File(files, "pool/pending.jsonl").readLines()
        assertEquals(2, lines.size)
        val imported = Json.parseObject(lines[1])
        assertEquals(6L, imported["s"]); assertEquals(1767323045L, (imported["a"] as Number).toLong()); assertEquals(null, imported["g"])
        q.freeze()
        q.clearAll()
        assertTrue(q.outboxFiles().isEmpty()); assertEquals(0, q.pending)
    }
    // ---- tek kurulum kimliği (veri-ve-ayarlar.md §1.3) ----

    @Test fun freshInstallUsesOneIdEverywhere() {
        val files = TestFiles.tempDir()
        val id = PoolInstall.resolve(files)
        assertTrue(PoolInstall.isUuid(id))
        assertEquals(id, File(files, "translation-pool/install").readText())
        val q = queue(files)
        assertEquals(id, q.state.install)
        assertEquals(id, Json.parseObject(File(files, "pool/state.json").readText())["install"])
        assertEquals(id, PoolInstall.resolve(files))
    }

    @Test fun existingIdIsKeptAndCopiedToTheOtherFiles() {
        val files = TestFiles.tempDir()
        val old = "0b9d5c3e-58a2-4c1e-9a77-3f2d1e6b8c40"
        File(files, "pool").mkdirs()
        File(files, "pool/state.json").writeText("""{"install":"${old.uppercase()}","frozenThrough":12,"failures":2,"app":"0.9"}""")
        File(files, "translation-pool").mkdirs()
        File(files, "translation-pool/install").writeText("ffffffff-1111-4222-8333-444444444444")
        assertEquals(old, PoolInstall.resolve(files, legacy = "5555"))
        assertEquals(old, File(files, "translation-pool/install").readText())
        val st = Json.parseObject(File(files, "pool/state.json").readText())
        assertEquals(old, st["install"]); assertEquals(12L, (st["frozenThrough"] as Number).toLong()); assertEquals("0.9", st["app"])
        assertEquals(old, queue(files).state.install)
    }

    @Test fun nonUuidIdsAreReplacedEverywhere() {
        val files = TestFiles.tempDir()
        File(files, "pool").mkdirs()
        File(files, "pool/state.json").writeText("""{"install":"kisa-kimlik-123","frozenThrough":3}""")
        File(files, "translation-pool").mkdirs()
        File(files, "translation-pool/install").writeText("yok")
        val id = PoolInstall.resolve(files, legacy = "eski-rapor-kimligi")
        assertTrue(PoolInstall.isUuid(id))
        assertEquals(id, File(files, "translation-pool/install").readText())
        assertEquals(id, Json.parseObject(File(files, "pool/state.json").readText())["install"])
        // Yalnız eski yedekte UUID varsa o kullanılır.
        val other = TestFiles.tempDir()
        val legacy = "7d0c6a3b-1e2f-4a5b-8c9d-0e1f2a3b4c5d"
        assertEquals(legacy, PoolInstall.resolve(other, legacy = legacy))
        // Kuyruğa verilen kimlik dosyadakinin üstüne yazılır.
        assertEquals(legacy, LineQueue(files, http, "1.0", "http://pool", clock.now, Random(7), install = legacy).state.install)
        assertEquals(legacy, Json.parseObject(File(files, "pool/state.json").readText())["install"])
    }
}
