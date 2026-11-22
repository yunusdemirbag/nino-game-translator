// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.data

import com.ninotranslator.core.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.time.ZoneId
import java.time.ZoneOffset

class FileStoresTest {
    private val dir = tempDir()
    private var now = 1795370645000L

    @Test fun historyWritesExactFormatAndCaps() {
        val f = File(dir, "history.json")
        val h = HistoryStore(f) { now }
        repeat(205) { h.add("line $it", "satır $it", if (it % 2 == 0) HistoryOrigin.PACK else HistoryOrigin.ENGINE); now += 1500 }
        assertEquals(200, h.entries.value.size)
        assertEquals(205, h.entries.value.first().id)
        assertFalse(File(dir, "history.json.tmp").exists())
        val root = Json.parseObject(f.readText())
        assertEquals(1L, root["version"])
        @Suppress("UNCHECKED_CAST")
        val first = (root["entries"] as List<Map<String, Any?>>).first()
        assertEquals(listOf("id", "date", "source", "translation", "origin"), first.keys.toList())
        assertTrue((first["date"] as String).matches(Regex("""\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ""")))
        assertEquals("pack", first["origin"])
        assertEquals(h.entries.value, HistoryStore(f).entries.value)
        h.add("x".repeat(900), "y", HistoryOrigin.ENGINE)
        assertEquals(500, h.entries.value.first().source.length)
        h.clear()
        assertTrue(HistoryStore(f).entries.value.isEmpty())
    }

    @Test fun brokenHistoryIsEmpty() {
        val f = File(dir, "history.json").apply { writeText("{bozuk") }
        assertTrue(HistoryStore(f).entries.value.isEmpty())
    }

    @Test fun healthLogMax40SkipsUnknownKind() {
        val f = File(dir, HealthLog.PATH)
        val log = HealthLog(f)
        repeat(45) { log.add(HealthIssue(dateMs = it.toLong(), kind = HealthIssueKind.NETWORK_LOST, network = "Wi-Fi", streamedMinutes = 1.5)) }
        assertEquals(40, log.issues.value.size)
        assertEquals(44L, log.newestFirst().first().dateMs)
        val text = "[{\"id\":\"1\",\"date\":5,\"kind\":\"ps5Dropped\",\"network\":\"w\",\"game\":\"rdr2\",\"framesPerSecond\":59.9}," +
            "{\"id\":\"2\",\"date\":6,\"kind\":\"yeni\",\"network\":\"w\"}]"
        val parsed = HealthLog.parse(text)
        assertEquals(1, parsed.size)
        assertEquals(HealthIssueKind.PS5_DROPPED, parsed[0].kind)
        assertEquals(59.9, parsed[0].framesPerSecond!!, 0.0)
        assertEquals("rdr2", parsed[0].game)
        assertNull(parsed[0].reason)
    }

    @Test fun autoReportCounterPerDay() {
        val c = AutoReportCounter(File(dir, AutoReportCounter.PATH), { now }, { ZoneOffset.UTC })
        repeat(3) { assertTrue(c.canSendToday()); c.recordSent() }
        assertFalse(c.canSendToday())
        c.setPending("{\"a\":1}")
        assertEquals("{\"a\":1}", c.pending)
        val raw = Json.parseObject(File(dir, AutoReportCounter.PATH).readText())
        assertEquals("2026-11-22", raw["day"])
        assertEquals(3L, raw["sent"])
        now += 24 * 3600_000L
        assertTrue(c.canSendToday())
        c.setPending(null)
        assertNull(c.pending)
    }

    @Test fun subtitleLayoutKeeps60Newest() {
        val f = File(dir, SubtitleLayoutStore.FILE)
        val s = SubtitleLayoutStore(f)
        repeat(65) { s.record("rdr2", SubtitleBand(it / 100.0, 0.9)) }
        s.record(SubtitleLayoutStore.GENERIC, SubtitleBand(0.8, 0.95))
        val again = SubtitleLayoutStore(f)
        assertEquals(60, again.samples("rdr2").size)
        assertEquals(0.64, again.samples("rdr2").last().top, 1e-9)
        assertEquals(SubtitleBand(0.8, 0.95), again.samples("genel").single())
        assertEquals(mapOf("gta-6" to listOf(SubtitleBand(0.7, 0.9))), SubtitleLayoutStore.parse("{\"gta-6\":[[0.7,0.9],[1]]}"))
        // Eski anahtarlar (havuz paketi, tam ad) asıl kimlikte birleşir; yeni kayıt da oraya gider.
        val merged = SubtitleLayoutStore.parse("{\"pool-gta-6\":[[0.7,0.9]],\"grand-theft-auto-vi\":[[0.8,0.95]],\"genel\":[[0.1,0.2]]}")
        assertEquals(mapOf("gta-6" to listOf(SubtitleBand(0.7, 0.9), SubtitleBand(0.8, 0.95)), "genel" to listOf(SubtitleBand(0.1, 0.2))), merged)
        assertEquals("gta-6", SubtitleLayoutStore.key("pool-gta-6"))
    }

    @Test fun tvInstallLogLinesAndRollover() {
        val f = File(dir, TvInstallLog.FILE)
        val log = TvInstallLog(f, { now }, { ZoneId.of("UTC") })
        log.append("ADB bağlandı")
        assertEquals("2026-11-22 18:04:05 ADB bağlandı\n", log.read())
        f.writeText("x".repeat(600 * 1024))
        log.append("yeni")
        assertEquals("2026-11-22 18:04:05 yeni\n", log.read())
    }

    @Test fun installIdOrder() {
        val state = File(dir, "pool/state.json")
        val report = FakePrefs()
        val idn = InstallIdentity(dir, report)
        val generated = idn.id
        assertEquals(36, generated.length)
        assertEquals(generated, report.raw()["install"])
        assertEquals(generated, File(dir, "translation-pool/install").readText())
        assertEquals(generated, idn.id)
        // Süreçte tek kimlik; UUID olmayan havuz kimliği yeni açılışta da yerini korumaz.
        state.parentFile.mkdirs()
        state.writeText("{\"install\":\"havuz-kimligi-1234\",\"failures\":1}")
        assertEquals(generated, idn.id)
        assertEquals(generated, InstallIdentity(dir, report).id)
        assertTrue(state.readText().contains(generated))
        // Havuzdaki geçerli UUID önce gelir.
        val pool = "6e1d2c3b-4a59-4876-9a5b-4c3d2e1f0a9b"
        state.writeText("{\"install\":\"$pool\"}")
        assertEquals(pool, InstallIdentity(dir, report).id)
        assertEquals(pool, report.raw()["install"])
    }

    @Test fun appUpdateRules() {
        val p = FakePrefs(mapOf("dismissed" to "0.2.5"))
        val u = AppUpdateStore(p)
        assertTrue(u.shouldCheck(now))
        u.recordCheck(now, "v0.2.6")
        assertEquals("0.2.6", u.latest)
        assertFalse(u.shouldCheck(now + 3600_000L))
        assertTrue(u.shouldCheck(now + 3 * 3600_000L))
        assertTrue(u.shouldCheck(now - 1))
        u.recordCheck(now + 1, null)
        assertEquals("0.2.6", u.latest)
        u.removeLegacyDismissed()
        assertFalse(p.contains("dismissed"))
    }

    @Test fun atomicWriteIgnoresStaleTmp() {
        val f = File(dir, "a.json")
        File(dir, "a.json.tmp").writeText("yarım")
        assertNull(AtomicFiles.read(f))
        AtomicFiles.write(f, "{}")
        assertEquals("{}", AtomicFiles.read(f))
        assertFalse(File(dir, "a.json.tmp").exists())
    }
}

class AppLanguageTest {
    @Test fun uiTags() {
        assertEquals("fil", AppLanguage.uiTag("tl"))
        assertEquals("tr", AppLanguage.uiTag("tr"))
        assertEquals("en", AppLanguage.uiTag("de"))
        assertEquals("en", AppLanguage.uiTag(null))
        assertTrue(AppLanguage.isRtl("ar") && AppLanguage.isRtl("ur"))
        assertFalse(AppLanguage.isRtl("tr"))
        assertEquals("id", AppLanguage.fromDevice("in"))
        assertEquals("tl", AppLanguage.fromDevice("fil"))
        assertEquals("nl", AppLanguage.normalizeForSave("NL-be"))
        for (l in AppLanguage.TARGET_LANGUAGES) assertTrue(AppLanguage.uiTag(l) in AppLanguage.UI_TAGS)
    }
}
