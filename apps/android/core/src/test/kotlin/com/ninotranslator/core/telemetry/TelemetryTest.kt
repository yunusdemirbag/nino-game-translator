// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.telemetry

import com.ninotranslator.core.http.HttpRequest
import com.ninotranslator.core.http.HttpResponse
import com.ninotranslator.core.http.HttpTransport
import com.ninotranslator.core.json.Json
import com.ninotranslator.core.telemetry.SessionTimings.Metric
import com.ninotranslator.core.telemetry.TelemetryEvent.Ps5Route
import com.ninotranslator.core.telemetry.TelemetryEvent.SessionSource
import com.ninotranslator.core.telemetry.TelemetryEvent.TvBrand
import com.ninotranslator.core.telemetry.TelemetryEvent.TvProtocol
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.io.File
import java.io.IOException
import java.nio.file.Files
import java.util.zip.GZIPInputStream

/** Sahte ağ: her istek kaydedilir, cevabı [reply] verir. */
private class FakeHttp(var reply: (HttpRequest, Map<String, Any?>?) -> HttpResponse = { _, _ -> ok() }) : HttpTransport {
    val requests = ArrayList<HttpRequest>()
    val bodies = ArrayList<Map<String, Any?>>()

    override fun send(request: HttpRequest): HttpResponse {
        requests += request
        val body = request.body?.let { b -> Json.parseObject(GZIPInputStream(b.inputStream()).readBytes().toString(Charsets.UTF_8)) }
        body?.let { bodies += it }
        return reply(request, body)
    }

    companion object {
        fun ok(extra: String = "") = HttpResponse(200, body = """{"ok":true,"accepted":1,"dropped":0$extra}""".toByteArray())
    }
}

private class Clock(var ms: Long) { fun s(v: Long) { ms = v * 1000 } }

class TelemetryTest {
    private val install = "8d0f5c9e-3b1a-4c2d-9e8f-7a6b5c4d3e2f"
    private val macCtx = TelemetryContext("mac", "4.0.0", "macOS 27.0", "Mac16,1", "androidtv", "release")
    private fun dir(): File = Files.createTempDirectory("nino-telemetry").toFile()

    private fun client(
        http: HttpTransport, clock: Clock, directory: File = dir(), ids: Iterator<String> = generateSequence(1) { it + 1 }.map { "00000000-0000-4000-8000-%012d".format(it) }.iterator(),
        maxQueued: Int = 2000, threshold: Int = 100, installId: String = install, online: () -> Boolean = { true },
    ) = Telemetry(
        Telemetry.Options("https://pool.test", installId, macCtx, directory, maxQueued = maxQueued, flushThreshold = threshold),
        http, clock = { clock.ms }, newBatchId = { ids.next() }, isOnline = online, zoneOffsetMs = { 0 },
    )

    // ---- gövde: events-v1.json ile alan alan ----

    @Test fun bodyMatchesFixtureFieldByField() {
        val fixture = Json.parseObject(javaClass.getResource("/telemetry/events-v1.json")!!.readText())
        val http = FakeHttp()
        val clock = Clock(0)
        val ids = listOf("2f6c1c8e-8a43-4b9b-9a3e-1e5f0c7d9a10").iterator()
        val t = client(http, clock, ids = ids)

        clock.s(1763300000)
        t.record(TelemetryEvent.launch(640))
        t.reportPreviousRun(CrashMarker.Record("3.9.0", started = 1763000000, alive = 1763001820, code = "SIGSEGV", place = "ReadingPipeline.process"),
            PreviousExit.Unknown)
        clock.s(1763300012); t.record(TelemetryEvent.ps5Connect(TelemetryCode.PS5_SESSION_TIMEOUT, 15000, Ps5Route.LAN))
        clock.s(1763300040); t.record(TelemetryEvent.ps5Connect("ok", 2840, Ps5Route.LAN))
        clock.s(1763300045); t.record(TelemetryEvent.tvConnect("ok", 420, TvBrand.ANDROID_TV, TvProtocol.NINO))
        clock.s(1763300300); repeat(3) { t.recordError(TelemetryCode.PROVIDER_HTTP, 429) }
        clock.s(1763303000); t.record(TelemetryEvent.ps5Drop(TelemetryCode.Drop.NETWORK_LOST, 2950))
        clock.s(1763303100); t.record(TelemetryEvent.tvDrop(TelemetryCode.Drop.TIMEOUT, TvBrand.ANDROID_TV, 3050))

        val timings = SessionTimings()
        listOf(35L, 45, 50, 65, 75, 140).forEach { timings.record(Metric.OCR, it) }
        listOf(0L, 1, 2).forEach { timings.record(Metric.CACHE, it) }
        listOf(380L, 600).forEach { timings.record(Metric.provider("DeepL"), it) }
        listOf(200L, 400, 600, 900).forEach { timings.record(Metric.TOTAL, it) }
        timings.record(Metric.FIRST_FRAME, 1900)
        clock.s(1763303600)
        t.record(TelemetryEvent.session(3580, "gta-vi", SessionSource.REMOTE_PLAY, 412, timings))

        assertEquals(Telemetry.FlushResult.Sent(9), t.flush())
        val sent = http.bodies.single()
        assertSameJson("", fixture, sent)
        // Başlıklar: gzip'li JSON, doğru adres.
        val r = http.requests.single()
        assertEquals("https://pool.test/v1/events", r.url)
        assertEquals("POST", r.method)
        assertEquals("gzip", r.headers["Content-Encoding"])
        assertEquals("application/json", r.headers["Content-Type"])
        assertEquals(0, t.queuedCount)
    }

    /** Yapısal karşılaştırma; ilk farkın yolunu söyler. */
    private fun assertSameJson(path: String, expected: Any?, actual: Any?) {
        when (expected) {
            is Map<*, *> -> {
                if (actual !is Map<*, *>) fail("$path: nesne bekleniyordu, $actual geldi")
                actual as Map<*, *>
                assertEquals("$path: alanlar", expected.keys.map { it.toString() }.toSortedSet(), actual.keys.map { it.toString() }.toSortedSet())
                for ((k, v) in expected) assertSameJson("$path.$k", v, actual[k])
            }
            is List<*> -> {
                if (actual !is List<*>) fail("$path: dizi bekleniyordu, $actual geldi")
                actual as List<*>
                assertEquals("$path: boy", expected.size, actual.size)
                expected.forEachIndexed { i, v -> assertSameJson("$path[$i]", v, actual[i]) }
            }
            else -> assertEquals(path, expected, actual)
        }
    }

    // ---- kovalar ----

    @Test fun histogramBucketsMatchRecipe() {
        assertEquals(18, LatencyHistogram.EDGES.size) // + sonsuz = 19 kova
        assertEquals(0, LatencyHistogram.bucketOf(0))
        assertEquals(0, LatencyHistogram.bucketOf(5))
        assertEquals(1, LatencyHistogram.bucketOf(6))
        assertEquals(17, LatencyHistogram.bucketOf(10000))
        assertEquals(18, LatencyHistogram.bucketOf(10001))
        val h = LatencyHistogram().apply { record(3); record(20_000); record(-5) }
        val w = h.toWire()
        assertEquals(3L, w["n"]); assertEquals(20_003L, w["sum"]); assertEquals(20_000L, w["max"])
        val counts = w["h"] as List<*>
        assertEquals(19, counts.size)
        assertEquals(3L, counts.sumOf { (it as Long) })
    }

    @Test fun timingsIgnoreBadNamesAndCapAt24() {
        val t = SessionTimings()
        t.record("Bad Name", 5)
        assertTrue(t.isEmpty)
        repeat(30) { t.record("m$it", 1) }
        assertEquals(24, t.toWire().size)
        val p = SessionTimings().apply { recordProvider("mlkit", 40); recordProvider("bad name!", 10) }
        assertEquals(2L, p.count(Metric.PROVIDER))
        assertEquals(1L, p.count("tr.provider:mlkit"))
    }

    // ---- kuyruk ve sınırlar ----

    @Test fun queueKeepsAtMostMaxAndDropsOldestNonCrash() {
        val clock = Clock(1_763_300_000_000)
        val t = client(FakeHttp(), clock, maxQueued = 5)
        t.record(TelemetryEvent.crash("SIGSEGV", null, "1.0.0", 10))
        repeat(10) { t.record(TelemetryEvent.error("code.$it")!!) }
        val q = t.queued
        assertEquals(5, q.size)
        assertEquals(TelemetryEvent.Kind.CRASH, q.first().kind)
        assertEquals(listOf("code.6", "code.7", "code.8", "code.9"), q.drop(1).map { it.fields["code"] })
    }

    @Test fun dailyLimitKeepsCrashesAndCoalescingDoesNotCount() {
        val clock = Clock(1_763_300_000_000)
        val t = client(FakeHttp(), clock)
        t.applyRemoteConfig(TelemetryRemoteConfig(maxPerDay = 3))
        t.recordError("tr.provider.http", 500)
        repeat(4) { t.recordError("tr.provider.http", 500) } // birleşir, sınırı yemez
        t.record(TelemetryEvent.launch())
        t.record(TelemetryEvent.launch())
        t.record(TelemetryEvent.launch()) // 4. olay: atılır
        t.record(TelemetryEvent.crash(null, null, "1.0.0"))
        assertEquals(4, t.queuedCount)
        assertEquals(1, t.droppedToday)
        assertEquals(5L, t.queued.first().fields["n"])
        // Ertesi gün sayaç sıfırlanır.
        clock.ms += 86_400_000
        t.record(TelemetryEvent.launch())
        assertEquals(5, t.queuedCount)
    }

    @Test fun sameErrorCoalescesOnlyWithSameHttp() {
        val t = client(FakeHttp(), Clock(1_763_300_000_000))
        t.recordError("tr.provider.http", 429)
        t.recordError("tr.provider.http", 429)
        t.recordError("tr.provider.http", 500)
        t.recordError("ocr.failed")
        t.recordError("bad code with spaces") // serbest yazı: atılır
        t.recordError("ocr.failed")
        val q = t.queued
        assertEquals(3, q.size)
        assertEquals(2L, q[0].fields["n"])
        assertNull(q[1].fields["n"])
        assertEquals(2L, q[2].fields["n"])
    }

    @Test fun queueSurvivesRestart() {
        val d = dir()
        val clock = Clock(1_763_300_000_000)
        val http = FakeHttp { _, _ -> HttpResponse(503) }
        val a = client(http, clock, directory = d)
        a.record(TelemetryEvent.launch(100))
        a.record(TelemetryEvent.ps5Connect("ok", 900, Ps5Route.LAN))
        assertTrue(a.flush() is Telemetry.FlushResult.RetryLater)
        a.record(TelemetryEvent.launch())
        val b = client(http, clock, directory = d)
        assertEquals(3, b.queuedCount)
        assertEquals(a.queued, b.queued)
    }

    // ---- örnekleme ----

    @Test fun fnv1aMatchesReferenceValues() {
        // Değerler bağımsız bir Python hesabından.
        assertEquals(2223483191L, TelemetryRemoteConfig.fnv1a32(install))
        assertEquals(440920331L, TelemetryRemoteConfig.fnv1a32("abc"))
        assertEquals(2166136261L, TelemetryRemoteConfig.fnv1a32(""))
        assertEquals(3497017141L, TelemetryRemoteConfig.fnv1a32("00000000-0000-4000-8000-000000000000"))
        // % 10000 = 3191
        assertTrue(TelemetryRemoteConfig.isSampled(install, 0.32))
        assertFalse(TelemetryRemoteConfig.isSampled(install, 0.319))
        assertTrue(TelemetryRemoteConfig.isSampled(install.uppercase(), 0.32))
        assertTrue(TelemetryRemoteConfig.isSampled(install, 1.0))
        assertFalse(TelemetryRemoteConfig.isSampled(install, 0.0))
    }

    @Test fun samplingStripsOnlySessionTimings() {
        val t = client(FakeHttp(), Clock(1_763_300_000_000))
        t.applyRemoteConfig(TelemetryRemoteConfig(sample = 0.3)) // 3191 ≥ 3000: örneklem dışı
        val timings = SessionTimings().apply { record(Metric.OCR, 40) }
        t.record(TelemetryEvent.session(60, "gta-vi", SessionSource.REMOTE_PLAY, 5, timings))
        t.record(TelemetryEvent.ps5Connect("ok", 900, Ps5Route.LAN))
        val (session, connect) = t.queued
        assertNull(session.fields["h"])
        assertEquals(60L, session.fields["dur"])
        assertEquals(900L, connect.fields["ms"])
        t.applyRemoteConfig(TelemetryRemoteConfig(sample = 0.4))
        t.record(TelemetryEvent.session(60, null, SessionSource.REMOTE_PLAY, 5, timings))
        assertTrue(t.queued.last().fields["h"] is Map<*, *>)
    }

    // ---- gönderim ----

    @Test fun retryKeepsBatchIdAndBacksOff() {
        val clock = Clock(1_763_300_000_000)
        var status = 503
        var fail = false
        val http = FakeHttp { _, _ -> if (fail) throw IOException("ağ yok") else if (status == 200) FakeHttp.ok() else HttpResponse(status) }
        val t = client(http, clock)
        t.record(TelemetryEvent.launch())
        assertEquals(Telemetry.FlushResult.RetryLater(60), t.flush())
        assertEquals(Telemetry.FlushResult.Waiting, t.flush()) // süre dolmadı
        clock.ms += 60_000
        status = 404 // sunucu henüz yayında değil: saklanır
        assertEquals(Telemetry.FlushResult.RetryLater(120), t.flush())
        clock.ms += 120_000
        fail = true
        assertEquals(Telemetry.FlushResult.RetryLater(240), t.flush())
        clock.ms += 240_000
        fail = false; status = 200
        t.record(TelemetryEvent.launch()) // gönderilen parçaya eklenmez
        assertEquals(Telemetry.FlushResult.Sent(1), t.flush())
        assertEquals(4, http.requests.size)
        assertEquals(1, http.bodies.map { it["batch"] }.toSet().size)
        assertEquals(1, t.queuedCount)
        assertEquals(Telemetry.FlushResult.Sent(1), t.flush())
        assertNotEquals(http.bodies.first()["batch"], http.bodies.last()["batch"])
    }

    @Test fun backoffCapsAtOneHourAndHonorsRetryAfter() {
        val clock = Clock(1_763_300_000_000)
        var retryAfter: String? = null
        val http = FakeHttp { _, _ -> HttpResponse(if (retryAfter != null) 429 else 500, retryAfter?.let { mapOf("retry-after" to it) }.orEmpty()) }
        val t = client(http, clock)
        t.record(TelemetryEvent.launch())
        val waits = (1..8).map { (t.flush(force = true) as Telemetry.FlushResult.RetryLater).seconds }
        assertEquals(listOf(60L, 120, 240, 480, 960, 1920, 3600, 3600), waits)
        retryAfter = "7200"
        assertEquals(Telemetry.FlushResult.RetryLater(7200), t.flush(force = true))
        assertEquals(1, t.queuedCount)
    }

    @Test fun tooLargeSplitsInHalfAndSingleTooLargeIsDropped() {
        val clock = Clock(1_763_300_000_000)
        val http = FakeHttp { _, body -> if (((body?.get("events") as List<*>).size) > 2) HttpResponse(413) else FakeHttp.ok() }
        val t = client(http, clock)
        repeat(4) { t.record(TelemetryEvent.error("e.$it")!!) }
        assertEquals(Telemetry.FlushResult.Split, t.flush())
        assertEquals(4, t.queuedCount)
        assertEquals(Telemetry.FlushResult.Sent(2), t.flush())
        assertEquals(Telemetry.FlushResult.Sent(2), t.flush())
        assertEquals(0, t.queuedCount)
        // Sıra korunur; her yarı kendi kimliğiyle.
        val sentCodes = http.bodies.drop(1).flatMap { b -> (b["events"] as List<*>).map { (it as Map<*, *>)["code"] } }
        assertEquals(listOf("e.0", "e.1", "e.2", "e.3"), sentCodes)
        assertEquals(3, http.bodies.map { it["batch"] }.toSet().size)

        http.reply = { _, _ -> HttpResponse(413) }
        t.record(TelemetryEvent.launch())
        assertEquals(Telemetry.FlushResult.Dropped(1), t.flush())
        assertEquals(0, t.queuedCount)
    }

    @Test fun badRequestDropsBatch() {
        val t = client(FakeHttp { _, _ -> HttpResponse(400) }, Clock(1_763_300_000_000))
        t.record(TelemetryEvent.launch()); t.record(TelemetryEvent.launch())
        assertEquals(Telemetry.FlushResult.Dropped(2), t.flush())
        assertEquals(0, t.queuedCount)
    }

    @Test fun duplicateReplyClearsBatch() {
        val t = client(FakeHttp { _, _ -> FakeHttp.ok(""","duplicate":true""") }, Clock(1_763_300_000_000))
        t.record(TelemetryEvent.launch())
        assertEquals(Telemetry.FlushResult.Duplicate, t.flush())
        assertEquals(0, t.queuedCount)
    }

    @Test fun flushIfDueWaitsForIntervalOrThreshold() {
        val clock = Clock(1_763_300_000_000)
        val http = FakeHttp()
        val t = client(http, clock, threshold = 3)
        t.record(TelemetryEvent.launch())
        assertEquals(Telemetry.FlushResult.Sent(1), t.flushIfDue()) // ilk gönderim hemen
        t.record(TelemetryEvent.launch())
        assertEquals(Telemetry.FlushResult.Waiting, t.flushIfDue())
        clock.ms += 600_000
        assertEquals(Telemetry.FlushResult.Sent(1), t.flushIfDue())
        repeat(3) { t.record(TelemetryEvent.error("e.$it")!!) }
        assertEquals(Telemetry.FlushResult.Sent(3), t.flushIfDue())
    }

    @Test fun offlineDoesNotTry() {
        val http = FakeHttp()
        val t = client(http, Clock(1_763_300_000_000), online = { false })
        t.record(TelemetryEvent.launch())
        assertEquals(Telemetry.FlushResult.Waiting, t.flush())
        assertFalse(t.refreshRemoteConfig())
        assertTrue(http.requests.isEmpty())
        assertEquals(1, t.queuedCount)
    }

    // ---- uzak ayar ----

    @Test fun serverDisableClearsQueueAndMarkerAndConfigCanReenable() {
        val d = dir()
        val clock = Clock(1_763_300_000_000)
        val http = FakeHttp { _, _ -> FakeHttp.ok(""","config":{"enabled":false,"sample":1,"maxPerDay":1000,"flushSeconds":600}""") }
        val t = client(http, clock, directory = d)
        t.marker.begin("1.0.0", 1, 1)
        t.record(TelemetryEvent.launch())
        t.record(TelemetryEvent.launch())
        assertEquals(Telemetry.FlushResult.Sent(2), t.flush())
        assertFalse(t.isActive)
        t.record(TelemetryEvent.launch())
        assertEquals(0, t.queuedCount)
        assertFalse(t.marker.file.exists())
        assertEquals(Telemetry.FlushResult.Disabled, t.flush())
        // Yeniden açılışta da kapalı kalır.
        assertFalse(client(http, clock, directory = d).isActive)

        http.reply = { r, _ ->
            assertEquals("https://pool.test/v1/config", r.url)
            HttpResponse(200, body = """{"translate":{},"telemetry":{"enabled":true,"sample":0.5,"maxPerDay":20,"flushSeconds":120}}""".toByteArray())
        }
        assertTrue(t.refreshRemoteConfig())
        assertTrue(t.isActive)
        assertEquals(TelemetryRemoteConfig(true, 0.5, 20, 120), t.remoteConfig)
    }

    @Test fun remoteConfigParsesDefaultsAndClamps() {
        assertEquals(TelemetryRemoteConfig(), TelemetryRemoteConfig.parse(null))
        assertEquals(TelemetryRemoteConfig(true, 1.0, 0, 60), TelemetryRemoteConfig.parse(mapOf("sample" to 3.0, "maxPerDay" to -1L, "flushSeconds" to 1L)))
    }

    @Test fun invalidInstallIdNeverSends() {
        val http = FakeHttp()
        val t = client(http, Clock(1_763_300_000_000), installId = "kisa-kimlik")
        t.record(TelemetryEvent.launch())
        assertFalse(t.isActive)
        assertEquals(Telemetry.FlushResult.Disabled, t.flush())
        assertTrue(http.requests.isEmpty())
    }

    // ---- gizlilik: ctx ve kodlar ----

    @Test fun contextKeepsOnlyModelLikeValues() {
        val c = TelemetryContext("android", "0.1.0-beta.37", "Android 14", "Yunus'un telefonu", "", "dev").cleaned()
        assertEquals("", c.device)
        assertEquals("Android 14", c.os)
        assertEquals("SM-S918B", TelemetryContext("android", "1", "Android 14", "SM-S918B").cleaned().device)
        assertEquals("", TelemetryContext("tv", "1", "x", "y").cleaned().platform)
    }

    @Test fun codesRejectFreeTextAndPaths() {
        assertNull(TelemetryCode.clean("Bağlantı reddedildi 192.168.0.10"))
        assertNull(TelemetryCode.cleanWhere("/data/app/Foo.kt"))
        assertNull(TelemetryEvent.error("a b"))
        assertEquals("ps5.other", TelemetryEvent.ps5Connect("hata: zaman aşımı", 10, Ps5Route.LAN).fields["r"])
        val e = IllegalStateException("gizli /yol 10.0.0.1")
        assertEquals("java.lang.IllegalStateException", TelemetryCode.ofThrowable(e))
        assertEquals("oom", TelemetryCode.ofThrowable(OutOfMemoryError()))
        assertEquals("TelemetryTest.codesRejectFreeTextAndPaths", TelemetryCode.whereOf(e))
        // NinoCore GameIDs.id: bilinen ad → asıl kimlik; yeni oyun → slug; kimliğe dönmeyen metin → alan yok.
        assertEquals("gta-6", TelemetryEvent.session(1, "Grand Theft Auto VI", SessionSource.CAPTURE, 0).fields["game"])
        assertEquals("gta-v", TelemetryEvent.session(1, "GTA 5", SessionSource.CAPTURE, 0).fields["game"])
        assertEquals("benim-gizli-oyunum-3", TelemetryEvent.session(1, "Benim Gizli Oyunum 3", SessionSource.CAPTURE, 0).fields["game"])
        assertEquals("pool-yeni-oyun", TelemetryEvent.session(1, "pool-yeni-oyun", SessionSource.CAPTURE, 0).fields["game"])
        assertEquals("gta-6", TelemetryEvent.session(1, "pool-gta-6", SessionSource.CAPTURE, 0).fields["game"])
        for (raw in listOf("", "  ", "!!!", "™ — ©", "ğüşıöç")) assertFalse(raw, "game" in TelemetryEvent.session(1, raw, SessionSource.CAPTURE, 0).fields)
        assertEquals("a".repeat(64), TelemetryEvent.session(1, "a".repeat(200), SessionSource.CAPTURE, 0).fields["game"])
        assertEquals("gta-6", TelemetryEvent.diag("tv.dead", "x", game = "Grand Theft Auto VI")!!.fields["game"])
        assertEquals("benim-gizli-oyunum-3", TelemetryEvent.diag("tv.dead", "x", game = "Benim Gizli Oyunum 3")!!.fields["game"])
        assertEquals("gta-v", TelemetryEvent.diag("tv.dead", "x", game = "pool-gta-v")!!.fields["game"])
        assertFalse("game" in TelemetryEvent.diag("tv.dead", "x", game = "???")!!.fields)
    }

    // ---- çökme işareti ----

    @Test fun crashMarkerDecidesFromMarkerAndExitInfo() {
        val m = CrashMarker(dir())
        assertNull(m.begin("1.0.0", 100, 42)) // ilk açılış
        m.touch(160)
        m.noteCrash("java.lang.IllegalStateException", "Foo.bar")
        val prev = m.begin("1.0.1", 200, 43)!!
        assertEquals(42, prev.pid)
        val crash = CrashMarker.crashEvent(prev, PreviousExit.Clean)!!
        assertEquals(mapOf("code" to "java.lang.IllegalStateException", "where" to "Foo.bar", "ver" to "1.0.0", "up" to 60L), crash.fields)

        // Kod yok: önde kaldıysa ve bilgi yoksa unclean_exit; arka planda kaldıysa çökme sayılmaz.
        val fg = CrashMarker.Record("1.0.0", 100, 130)
        assertEquals("unclean_exit", CrashMarker.crashEvent(fg, PreviousExit.Unknown)!!.fields["code"])
        assertNull(CrashMarker.crashEvent(fg.copy(background = true), PreviousExit.Unknown))
        assertNull(CrashMarker.crashEvent(fg, PreviousExit.Clean))
        assertEquals("anr", CrashMarker.crashEvent(fg.copy(background = true), PreviousExit.Crash("anr"))!!.fields["code"])
        assertNull(CrashMarker.crashEvent(null, PreviousExit.Crash("anr")))

        m.setBackground(true, 250)
        val bg = m.begin("1.0.1", 300, 44)!!
        assertTrue(bg.background)
        assertEquals(50L, bg.alive - bg.started)
    }

    @Test fun crashIsReportedWithCrashedVersion() {
        val t = client(FakeHttp(), Clock(1_763_300_000_000))
        t.reportPreviousRun(CrashMarker.Record("3.9.0", 1, 11, code = "SIGABRT"), PreviousExit.Unknown)
        t.recordLaunch(500)
        val (crash, launch) = t.queued
        assertEquals("3.9.0", crash.fields["ver"])
        assertEquals(10L, crash.fields["up"])
        assertEquals(500L, launch.fields["ms"])
    }
}
