// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.telemetry.diag

import com.ninotranslator.core.http.HttpRequest
import com.ninotranslator.core.http.HttpResponse
import com.ninotranslator.core.http.HttpTransport
import com.ninotranslator.core.json.Json
import com.ninotranslator.core.telemetry.Telemetry
import com.ninotranslator.core.telemetry.TelemetryContext
import com.ninotranslator.core.telemetry.TelemetryEvent
import com.ninotranslator.core.telemetry.TelemetryEvent.DiagStep
import com.ninotranslator.core.telemetry.TelemetryEvent.Severity
import com.ninotranslator.core.telemetry.TelemetryEvent.TvBrand
import com.ninotranslator.core.telemetry.TelemetryRemoteConfig
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.nio.file.Files

class DiagWatchTest {
    private data class Expect(val at: Long, val rule: String, val cause: String, val sev: String)

    private class Run(start: Long = 0) {
        var now = start * 1000
        val events = ArrayList<TelemetryEvent>()
        val watch = DiagWatch({ now }, { events += it })
        fun at(s: Long) { now = s * 1000 }
        fun got() = events.map { Expect(it.time, it.fields["rule"] as String, it.fields["cause"] as String, it.fields["sev"] as String) }
    }

    /** Senaryo: her saniye önce o anın adımları, sonra tick; son adımda durur ve bekleyeni gönderir. */
    private fun play(s: Map<*, *>): Run {
        val r = Run()
        (s["state"] as? Map<*, *>)?.forEach { (k, v) -> r.watch.set(k as String, v) }
        val drops = (s["dropCodes"] as? List<*>)?.map { it as String }?.iterator()
        val timeline = (s["timeline"] as List<*>).map { it as List<*> }
        val byTime = timeline.groupBy { (it[0] as Number).toLong() }
        val last = byTime.keys.max()
        for (t in 0..last) {
            r.at(t)
            byTime[t]?.forEach { st ->
                val code = st[1] as String
                val n = (st.getOrNull(2) as? Number)?.toLong()
                val reason = if (code == "tv.drop" && drops != null && drops.hasNext()) drops.next() else null
                r.watch.step(code, n, reason)
            }
            r.watch.tick()
        }
        r.watch.flush()
        return r
    }

    @Test fun scenariosFromFixture() {
        val fixture = Json.parseObject(javaClass.getResource("/diag/diag-scenarios.json")!!.readText())
        val scenarios = fixture["scenarios"] as List<*>
        assertEquals(9, scenarios.size)
        for (s in scenarios.map { it as Map<*, *> }) {
            val expect = (s["expect"] as List<*>).map { e ->
                e as Map<*, *>
                Expect((e["at"] as Number).toLong(), e["rule"] as String, e["cause"] as String, e["sev"] as String)
            }
            assertEquals(s["name"] as String, expect, play(s).got())
        }
    }

    @Test fun trailCarriesOnlyCodesAndRelativeSeconds() {
        val fixture = Json.parseObject(javaClass.getResource("/diag/diag-scenarios.json")!!.readText())
        val first = (fixture["scenarios"] as List<*>).first() as Map<*, *>
        val e = play(first).events.single()
        assertEquals(listOf(listOf(-181L, "net.down"), listOf(-180L, "ps5.drop"), listOf(-141L, "ps5.retry", 1L), listOf(-81L, "ps5.retry", 2L)),
            e.fields["trail"])
        val state = e.fields["state"] as Map<*, *>
        assertEquals("down", state["ps5"])
        assertEquals("none", state["net"])
        assertEquals(2L, state["retries"])
        assertEquals(13L, state["sessionMin"])
    }

    @Test fun singleRootKeepsHighestPriorityAndListsTheOther() {
        val r = Run()
        r.watch.step("session.start")
        r.at(100); r.watch.step("ps5.drop")
        // 200'de çeviri hataları (tr.errors), 280'de PS5 (öncelik yüksek): yalnız PS5 gider, tr.errors izinde.
        for (i in 0 until 10) { r.at(200L + i); r.watch.step("tr.error", 503) }
        for (t in 210L..290L) { r.at(t); r.watch.tick() }
        r.watch.flush()
        assertEquals(listOf(Expect(280, "ps5.no_return", "timeout", "error")), r.got())
        val trail = r.events.single().fields["trail"] as List<*>
        assertTrue(trail.any { (it as List<*>)[1] == "tr.errors" })
    }

    @Test fun mutesFirstMinuteAfterLaunchAndRemoteOff() {
        val r = Run()
        r.watch.step("session.start")
        for (i in 0 until 12) { r.at(10L + i); r.watch.step("tr.error", 429) }
        r.watch.flush()
        assertTrue(r.events.isEmpty())

        var now = 0L
        val out = ArrayList<TelemetryEvent>()
        val off = DiagWatch({ now }, { out += it }, config = { DiagConfig(off = setOf("tr.errors")) })
        now = 100_000; off.step("session.start")
        for (i in 0 until 12) { now = 200_000L + i * 1000; off.step("tr.error", 429) }
        off.flush()
        assertTrue(out.isEmpty())
    }

    @Test fun hangIsSentAtOnceAndResourceStepNotRepeated() {
        val r = Run()
        r.at(100); r.watch.mainBlocked(7)
        assertEquals(listOf(Expect(100, "app.hang", "main_thread", "error")), r.got())
        for (t in 200L..500L step 10) { r.at(t); r.watch.resources(900, 10, "nominal") }
        r.watch.flush()
        assertEquals("memory_high", r.events.last().fields["cause"])
        assertEquals(1, r.watch.trailNow().count { it.code == "mem.high" })
    }

    @Test fun dailyBudgetLimitsPerRule() {
        val dir = Files.createTempDirectory("diag").toFile()
        val budget = DiagBudget(java.io.File(dir, "diag.json"), zoneOffsetMs = { 0 })
        assertTrue(budget.take("tr.slow", 0)); assertTrue(budget.take("tr.slow", 1)); assertFalse(budget.take("tr.slow", 2))
        assertTrue(budget.take("tv.flapping", 3)); assertTrue(budget.take("tv.flapping", 4)); assertTrue(budget.take("ocr.silent", 5))
        // Toplam 5: diskten okunan sayaç da sayar.
        assertFalse(DiagBudget(java.io.File(dir, "diag.json"), zoneOffsetMs = { 0 }).take("app.hang", 6))
        assertTrue(DiagBudget(java.io.File(dir, "diag.json"), zoneOffsetMs = { 0 }).take("app.hang", 86_400_000))
    }

    @Test fun eventDropsFreeTextAndBadFields() {
        val e = TelemetryEvent.diag("ps5.no_return", "network_lost", Severity.ERROR,
            state = mapOf("net" to "wifi", "memMB" to 410L, "msg" to "bağlantı reddedildi /Users/x", "bad key" to 1L),
            trail = listOf(DiagStep(-240, "net.change", 1), DiagStep(-30, "net.down"), DiagStep(5, "gelecek"), DiagStep(-10, "Hata: /Users/x")),
            tvBrand = TvBrand.ANDROID_TV, tvModel = "TCL 98U95A", tvApp = "4.0.0", game = "gta-vi", versions = mapOf("core" to "1.0.0", "a b" to "1"))!!
        assertEquals(TelemetryEvent.Kind.DIAG, e.kind)
        assertEquals(mapOf("memMB" to 410L, "net" to "wifi"), e.fields["state"])
        assertEquals(listOf(listOf(-240L, "net.change", 1L), listOf(-30L, "net.down")), e.fields["trail"])
        assertEquals(mapOf("brand" to "androidtv", "model" to "TCL 98U95A", "app" to "4.0.0"), e.fields["tv"])
        assertEquals(mapOf("core" to "1.0.0"), e.fields["ver"])
        assertNull(TelemetryEvent.diag("Kötü Kural", "x"))
        assertEquals("unknown", TelemetryEvent.diag("tr.slow", "çok yavaş!")!!.fields["cause"])
    }

    @Test fun diagIsExemptFromDailyCapAndSurvivesReload() {
        val dir = Files.createTempDirectory("diagq").toFile()
        val http = object : HttpTransport { override fun send(request: HttpRequest) = HttpResponse(500) }
        fun client() = Telemetry(Telemetry.Options("https://x.invalid", "8d0f5c9e-3b1a-4c2d-9e8f-7a6b5c4d3e2f",
            TelemetryContext("android", "4.5.0", "Android 14", "SM-S918B"), dir), http, clock = { 1_763_300_000_000 })
        val t = client()
        t.applyRemoteConfig(TelemetryRemoteConfig.parse(mapOf("maxPerDay" to 1L, "diag" to mapOf("off" to listOf("ocr.silent"), "limits" to mapOf("tr.slow.p90Ms" to 4000L)))))
        t.record(TelemetryEvent.launch())
        t.record(TelemetryEvent.launch())
        t.record(TelemetryEvent.diag("tr.slow", "pool_slow")!!)
        assertEquals(listOf(TelemetryEvent.Kind.LAUNCH, TelemetryEvent.Kind.DIAG), t.queued.map { it.kind })
        val again = client()
        assertEquals(listOf(TelemetryEvent.Kind.LAUNCH, TelemetryEvent.Kind.DIAG), again.queued.map { it.kind })
        assertTrue(again.remoteConfig.diag.isOff("ocr.silent"))
        assertEquals(4000.0, again.remoteConfig.diag.limit(DiagConfig.Limit.TR_SLOW_P90_MS), 0.0)
        assertEquals(3000.0, DiagConfig().limit(DiagConfig.Limit.TR_SLOW_P90_MS), 0.0)
    }
}
