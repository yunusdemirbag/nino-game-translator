// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.service

import com.ninotranslator.core.link.ShowPayload
import com.ninotranslator.mobile.data.HealthIssue
import com.ninotranslator.mobile.data.HealthIssueKind
import com.ninotranslator.mobile.data.TvBrand
import com.ninotranslator.mobile.support.AutoReport
import com.ninotranslator.mobile.support.DeviceSummary
import com.ninotranslator.mobile.support.Findings
import com.ninotranslator.mobile.support.HealthCause
import com.ninotranslator.mobile.support.HealthEval
import com.ninotranslator.mobile.support.HealthInput
import com.ninotranslator.mobile.support.HealthInputs
import com.ninotranslator.mobile.support.HealthLevel
import com.ninotranslator.mobile.support.NetKind
import com.ninotranslator.mobile.support.ReportSender
import com.ninotranslator.mobile.tv.FoundTv
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.MutableStateFlow
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.nio.ByteBuffer
import java.time.ZoneOffset

class SideServiceTest {
    private var now = 1_000_000L
    private fun meter() = HealthMeter { now }

    // --- Sağlık ölçümü (servis.md 5): ölçüm hizmette, değerlendirme tek yerde (HealthEval) ---
    private fun eval(m: HealthMeter) = HealthInputs.of(m.snapshot(), now)

    @Test fun healthLevelsAndCounts() {
        val m = meter()
        m.onStreaming() // oturum dışı: yok sayılır
        assertFalse(m.snapshot().everStreamed)
        m.start(); m.network = NetKind.WIFI
        // İki bağlanamama: bağlantı "sorun".
        m.onLost("NOT_FOUND"); m.onConnecting(); m.onLost("NOT_FOUND")
        assertEquals(2, m.snapshot().connectFails)
        assertEquals(HealthLevel.PROBLEM, HealthEval.ps5Level(eval(m)))
        assertEquals(listOf(HealthCause.PS5_NEVER), HealthEval.causes(eval(m)))
        m.onStreaming()
        m.onFrames(100)
        now += 10_000; m.onFrames(400)
        assertNull(m.snapshot().framesPerSecond) // 20 sn görüntü gelmeden hesaplanmaz
        now += 10_000; m.onFrames(600)
        assertEquals(30.0, m.snapshot().framesPerSecond!!, 0.01)
        assertEquals(HealthLevel.GOOD, HealthEval.pictureLevel(eval(m)))
        assertEquals(HealthLevel.GOOD, HealthEval.networkLevel(eval(m)))
        // Kaynak yeniden başladı: sayaç kaybolmaz.
        now += 1_000; m.onFrames(10)
        assertEquals(610, m.snapshot().frames)
        assertTrue(m.onLost("NETWORK"))
        val s = m.snapshot()
        assertEquals(1, s.drops); assertEquals("NETWORK", s.lastDropReason)
        assertEquals(HealthLevel.PROBLEM, HealthEval.ps5Level(eval(m)))
        assertEquals(HealthCause.PS5_LOST, HealthEval.causes(eval(m)).first())
        // Kopukken gelen kare sayılmaz.
        m.onFrames(500); assertEquals(610, m.snapshot().frames)
        m.onStreaming(); assertEquals(HealthLevel.GOOD, HealthEval.ps5Level(eval(m)))
        repeat(50) { m.onLine(1_000) }; m.onLine(null); m.onLine(5_000)
        assertEquals(52, m.snapshot().lines)
        assertEquals(1_000L, m.snapshot().medianMs); assertEquals(5_000L, m.snapshot().maxMs)
        m.network = NetKind.OFFLINE
        assertEquals(HealthLevel.PROBLEM, HealthEval.networkLevel(eval(m)))
        assertEquals(HealthCause.OFFLINE, HealthEval.causes(eval(m)).first())
        m.network = NetKind.WIRED
        assertTrue(HealthEval.summaryLine(eval(m)).startsWith("ağ kablolu · ağ kopması 0 · TV kopması 0 · görüntü 0 dk · 29 kare/sn · kopma 1 · bağlanamama 2 · son kopma NETWORK · satır 52 · çeviri ortanca 1.0 sn · en uzun 5.0 sn"))
        m.stop(); assertFalse(m.snapshot().sessionRunning)
    }

    /** "Muhtemel sebep" sırası (servis.md 5.2). */
    @Test fun causeOrder() {
        val base = HealthInput(measured = true, everStreamed = true, network = NetKind.WIFI, streamedMs = 60_000, fps = 30.0)
        assertEquals(listOf(HealthCause.NETWORK_DROPPED, HealthCause.PICTURE_WIFI), HealthEval.causes(base.copy(networkLosses = 1, fps = 5.0)))
        assertEquals(listOf(HealthCause.PICTURE_WIFI), HealthEval.causes(base.copy(fps = 20.0, drops = 4)))
        assertEquals(listOf(HealthCause.DROPS), HealthEval.causes(base.copy(drops = 3)))
        assertEquals(listOf(HealthCause.SLOW, HealthCause.TV), HealthEval.causes(base.copy(medianTranslateMs = 3_500, tvDrops = 1)))
        assertEquals(listOf(HealthCause.TV), HealthEval.causes(base.copy(tvDrops = 1)))
        assertEquals(emptyList<HealthCause>(), HealthEval.causes(base.copy(tvDrops = 1, targetTv = false)))
        assertEquals(emptyList<HealthCause>(), HealthEval.causes(HealthInput(network = NetKind.WIFI)))
        assertEquals(HealthCause.PS5_AFTER_NETWORK, HealthEval.causes(base.copy(disconnectedSinceMs = 1, networkLosses = 1, networkLostBeforeDrop = true)).first())
        assertEquals(HealthCause.PS5_ASLEEP, HealthEval.causes(base.copy(disconnectedSinceMs = 1, lastDropReason = "CONSOLE_ASLEEP")).first())
    }

    @Test fun dropReasonNames() {
        assertEquals("NOT_FOUND", DropReasons.of("phase_not_found_host"))
        assertEquals("CONSOLE_ASLEEP", DropReasons.of("phase_asleep"))
        assertEquals("BLACK", DropReasons.of("capture_black"))
    }

    @Test fun issueLineFormat() {
        val i = HealthIssue(dateMs = 1_795_381_440_000L, kind = HealthIssueKind.PS5_DROPPED, network = "wifi", reason = "NOT_FOUND",
            streamedMinutes = 31.2, framesPerSecond = 28.4, game = "GTA 6")
        assertEquals("22.11 21:04 PS5 bağlantısı koptu (NOT_FOUND) · 31 dk oynandı · ağ wifi · 28 kare/sn · GTA 6", Findings.supportLine(i, ZoneOffset.UTC))
    }

    // --- Sorun kayıtları (servis.md 6.1) ---
    @Test fun issueRules() {
        val r = IssueRules(ps5Rules = true)
        assertEquals(listOf(IssueRules.Out.Issue(HealthIssueKind.PS5_DROPPED, "NETWORK")), r.onDrop("NETWORK", 0))
        assertTrue(r.tick(179_999).isEmpty())
        assertEquals(listOf(IssueRules.Out.Issue(HealthIssueKind.PS5_UNREACHABLE), IssueRules.Out.ReportNow), r.tick(180_000))
        assertTrue(r.tick(400_000).isEmpty())
        r.onDrop(null, 500_000); r.onStreaming()
        assertTrue(r.tick(900_000).isEmpty())
        // TV: altyazı TV'ye giderken 20 sn sıfırda kalırsa.
        r.onTvCount(1, true, 0); r.onTvCount(0, true, 1_000)
        assertTrue(r.tick(20_999).isEmpty())
        assertEquals(listOf(IssueRules.Out.Issue(HealthIssueKind.TV_DROPPED), IssueRules.Out.TvDropped), r.tick(21_000))
        r.onTvCount(1, true, 30_000); r.onTvCount(0, true, 31_000); r.onTvCount(1, true, 33_000)
        assertTrue(r.tick(60_000).isEmpty())
        r.onTvCount(0, false, 70_000); assertTrue(r.tick(100_000).isEmpty())
        // Ağ: ardışık çevrimdışılar bir kez.
        assertEquals(1, r.onNetwork(NetKind.OFFLINE).size)
        assertTrue(r.onNetwork(NetKind.OFFLINE).isEmpty())
        r.onNetwork(NetKind.WIFI); assertEquals(1, r.onNetwork(NetKind.OFFLINE).size)
        assertEquals(6, r.issues)
        // Yakalama kartında PS5 kuralları yok.
        assertTrue(IssueRules(ps5Rules = false).onDrop("NETWORK", 0).isEmpty())
    }

    @Test fun autoReportBody() {
        val day = 86_400_000L
        val issues = (0 until 20).map { HealthIssue(dateMs = 10 * day + it * 1000L, kind = HealthIssueKind.TV_DROPPED, network = "wifi") }.reversed() +
            HealthIssue(dateMs = 1 * day, kind = HealthIssueKind.TV_DROPPED, network = "wifi")
        val input = HealthInput(measured = true, everStreamed = true, network = NetKind.WIFI, medianTranslateMs = 4_000)
        val findings = Findings.section(input, 11 * day, issues)
        val text = AutoReport.text(findings)
        assertTrue(text.startsWith("[Otomatik] Bu bildirimi Nino kendisi gönderdi, kullanıcı metni yok.\n\n— Nino'nun tespitleri —"))
        assertTrue(text, text.contains("Muhtemel sebep: Çeviri yavaş"))
        assertEquals(12, text.lines().count { it.startsWith("• ") })
        assertTrue(text.contains("ağ wifi"))
        assertEquals(ReportSender.MAX_TEXT, AutoReport.text("x".repeat(5000)).length)
        val body = com.ninotranslator.core.json.Json.parseObject(AutoReport.bodyOf("inst", "1.0", "tr", "t", ""))
        assertEquals("auto", body["kind"]); assertFalse(body.containsKey("device")); assertEquals("android", body["platform"])
        assertEquals("inst", body["install"])
        assertTrue(AutoReport.retryable(null)); assertTrue(AutoReport.retryable(500))
        assertFalse(AutoReport.retryable(429)); assertFalse(AutoReport.retryable(413)); assertFalse(AutoReport.retryable(200))
    }

    @Test fun deviceSummary() {
        val s = DeviceSummary.join(listOf("app" to "1.0 (7)", "device" to "Acme X|1", "tv" to null, "status" to "PS5 192.168.0.5\nbağlanıyor"))
        assertEquals("app: 1.0 (7) | device: Acme X/1 | status: PS5 192.168.0.5 bağlanıyor", s)
        assertEquals("PS5 … salonda …", DeviceSummary.scrub("PS5 10.0.0.2 salonda Oturma", listOf("Oturma")))
        assertEquals(600, DeviceSummary.join(listOf("a" to "x".repeat(700))).length)
        assertEquals("Model 55", DeviceSummary.tvModel("<Model 55>"))
    }

    // --- Yakalama kartı (remote-play.md 16) ---
    @Test fun captureSizeChoice() {
        assertEquals(1920 to 1080, CaptureSizes.choose(listOf(1280 to 720, 1920 to 1080, 3840 to 2160)))
        assertEquals(1280 to 720, CaptureSizes.choose(listOf(640 to 480, 1280 to 720, 3840 to 2160)))
        assertEquals(1600 to 1200, CaptureSizes.choose(listOf(640 to 480, 1600 to 1200)))
        assertNull(CaptureSizes.choose(emptyList()))
    }

    @Test fun blackFrameWatch() {
        val w = BlackFrameWatch()
        assertTrue(w.due(0))
        assertFalse(w.onSample(10, 0)); assertFalse(w.due(400))
        assertFalse(w.onSample(10, 3_999))
        assertTrue(w.onSample(10, 4_000)); assertTrue(w.black)
        assertTrue(w.onSample(200, 4_500)); assertFalse(w.black)
        val buf = ByteBuffer.allocate(64 * 64)
        buf.put(32 * 64 + 32, 99.toByte())
        assertEquals(99, BlackFrameWatch.maxSample(buf, 64, 64, 64))
    }

    // --- Android TV bulma ---
    @Test fun tvAutoConnectPicksNinoTvs() {
        val found = listOf(
            FoundTv("Salon", "10.0.0.5", TvBrand.ANDROID_TV, 47801, hasNino = true),
            FoundTv("Yatak", "10.0.0.6", TvBrand.ANDROID_TV, hasNino = false),
            FoundTv("LG", "10.0.0.7", TvBrand.LG, hasNino = false),
            FoundTv("Eski", "10.0.0.8", TvBrand.ANDROID_TV, hasNino = true),
        )
        assertEquals(listOf("10.0.0.5"), TvAutoConnect.pick(found, setOf("10.0.0.8")).map { it.address })
    }

    // --- TV'deki screen kanalı ---
    private class ScreenTv : TvOutput {
        val events = ArrayList<String>()
        override val connectedCount = MutableStateFlow(1)
        override val portProblems = MutableStateFlow<Set<Int>>(emptySet())
        override var subtitlesToTv = true
        override fun start() {}
        override fun close() {}
        override suspend fun show(payload: ShowPayload) {}
        override suspend fun clear(id: Int) {}
        override fun setStyle(style: Map<String, Any?>) {}
        override suspend fun started() {}
        override suspend fun stopped() {}
        override suspend fun screen(items: List<Map<String, Any?>>, durationMs: Int, overlay: Boolean) { events += "screen:${items.size}:$durationMs:$overlay" }
        override suspend fun screenClear() { events += "clear" }
    }

    @Test fun screenChannelSharesManualAndOverlay() {
        val tv = ScreenTv()
        val scope = CoroutineScope(Dispatchers.Unconfined)
        val ch = ScreenChannel(scope) { tv }
        val item = listOf(mapOf<String, Any?>("text" to "Selam"))
        ch.setOverlay(item)
        ch.setOverlay(item) // aynısı yeniden gitmez
        ch.manual(item + item, 12_000)
        ch.setOverlay(item + item + item) // elle sonuç ekrandayken katman gitmez
        ch.manualClear()
        ch.setOverlay(emptyList())
        ch.setOverlay(emptyList())
        assertEquals(listOf("screen:1:120000:true", "screen:2:12000:false", "clear", "screen:3:120000:true", "clear"), tv.events)
        ch.close(); scope.cancel()
    }

    @Test fun screenChannelResendsTheUnchangedOverlayEveryMinute() {
        val tv = ScreenTv()
        val clock = com.ninotranslator.core.reading.live.ManualClock()
        val scope = CoroutineScope(Dispatchers.Unconfined)
        val ch = ScreenChannel(scope, clock) { tv }
        val card = listOf(mapOf<String, Any?>("text" to "AVERY PAWN", "card" to true))
        ch.setOverlay(card)
        repeat(130) { clock.advance(1_000); ch.setOverlay(card); ch.tick() }
        assertEquals(List(3) { "screen:1:120000:true" }, tv.events)
        ch.manual(card + card, 10_000)
        clock.advance(60_000); ch.tick() // elle sonuç ekrandayken katman yenilenmez
        ch.manualClear()
        ch.setOverlay(emptyList())
        assertEquals(List(3) { "screen:1:120000:true" } + listOf("screen:2:10000:false", "clear", "screen:1:120000:true", "clear"), tv.events)
        ch.close(); scope.cancel()
    }
}
