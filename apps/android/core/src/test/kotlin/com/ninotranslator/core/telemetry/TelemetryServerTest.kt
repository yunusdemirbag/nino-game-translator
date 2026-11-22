// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.telemetry

import com.ninotranslator.core.http.HttpRequest
import com.ninotranslator.core.http.UrlConnectionTransport
import com.ninotranslator.core.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import java.nio.file.Files
import java.util.UUID

/**
 * Yerel havuz sunucusuyla uçtan uca (yalnız `NINO_TELEMETRY_E2E=http://127.0.0.1:8799` verilince çalışır; 8787 değil).
 * Gerçek sunucuya hiç gitmez.
 */
class TelemetryServerTest {
    private val base = System.getenv("NINO_TELEMETRY_E2E")?.trimEnd('/')

    private fun client(channel: String) = Telemetry(
        Telemetry.Options(base!!, UUID.randomUUID().toString(),
            TelemetryContext("android", "0.0.0-test", "Android 14", "SM-S918B", "androidtv", channel),
            Files.createTempDirectory("nino-e2e").toFile()),
        UrlConnectionTransport,
    )

    @Test fun localServerAcceptsOurBody() {
        assumeTrue(base != null && (base.startsWith("http://127.0.0.1") || base.startsWith("http://localhost")))
        val t = client("release")
        assertTrue("config", t.refreshRemoteConfig())
        t.recordLaunch(640)
        t.reportPreviousRun(CrashMarker.Record("0.0.0-old", 1, 61, code = "java.lang.IllegalStateException", place = "Foo.bar"), PreviousExit.Unknown)
        t.record(TelemetryEvent.ps5Connect("ok", 2840, TelemetryEvent.Ps5Route.LAN))
        t.record(TelemetryEvent.tvConnect("ok", 420, TelemetryEvent.TvBrand.ANDROID_TV, TelemetryEvent.TvProtocol.NINO))
        repeat(3) { t.recordError(TelemetryCode.PROVIDER_HTTP, 429) }
        t.record(TelemetryEvent.ps5Drop(TelemetryCode.Drop.NETWORK_LOST, 2950))
        val timings = SessionTimings().apply { record(SessionTimings.Metric.OCR, 40); recordProvider("mlkit", 120); record(SessionTimings.Metric.TOTAL, 300) }
        t.record(TelemetryEvent.session(3580, "gta-6", TelemetryEvent.SessionSource.REMOTE_PLAY, 12, timings))
        assertEquals(Telemetry.FlushResult.Sent(7), t.flush())
        assertEquals(0, t.queuedCount)

        // Geliştirici kanalı: alınır, sayılmaz.
        val dev = client("dev")
        dev.recordLaunch()
        assertEquals(Telemetry.FlushResult.Sent(1), dev.flush())

        // Ham cevap: hepsi kabul edildi mi.
        val body = dev.encode(Telemetry.Pending(UUID.randomUUID().toString(), listOf(TelemetryEvent.launch().copy(time = System.currentTimeMillis() / 1000))))
            .replace("\"dev\"", "\"release\"")
        val r = UrlConnectionTransport.send(HttpRequest.json("$base/v1/events", body))
        assertEquals(200, r.status)
        assertEquals(1L, Json.parseObject(r.text)["accepted"])
    }
}
