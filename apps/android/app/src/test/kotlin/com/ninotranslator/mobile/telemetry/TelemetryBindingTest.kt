// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.telemetry

import com.ninotranslator.core.link.ConnectFailure
import com.ninotranslator.core.link.ConnectedDisplay
import com.ninotranslator.core.link.DisplayEvent
import com.ninotranslator.core.link.DisplayKind
import com.ninotranslator.core.link.DropReason
import com.ninotranslator.core.telemetry.PreviousExit
import com.ninotranslator.core.telemetry.TelemetryEvent
import com.ninotranslator.core.telemetry.TelemetryEvent.Kind
import com.ninotranslator.mobile.service.SourceState
import com.ninotranslator.mobile.service.tvEventLine
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class TelemetryBindingTest {
    @Test fun ps5ConnectOkThenDropThenReconnect() {
        val p = Ps5Tracker()
        assertTrue(p.onState(SourceState.Preparing, 0).isEmpty())
        assertTrue(p.onState(SourceState.Connecting, 500).isEmpty())
        val ok = p.onState(SourceState.Streaming, 2_840).single()
        assertEquals(Kind.PS5_CONNECT, ok.kind)
        assertEquals(mapOf("r" to "ok", "ms" to 2_840L, "via" to "lan"), ok.fields)

        val drop = p.onState(SourceState.Reconnecting("phase_network", "ayrıntı 192.168.0.5"), 62_840).single()
        assertEquals(mapOf("code" to "network_lost", "after" to 60L), drop.fields)
        // Ayrıntı (adres) hiçbir alana girmez.
        assertTrue(drop.fields.values.none { it.toString().contains("192") })

        p.onState(SourceState.Connecting, 70_000)
        val failed = p.onState(SourceState.Reconnecting("phase_asleep"), 85_000).single()
        assertEquals(mapOf("r" to "ps5.session.standby", "ms" to 15_000L, "via" to "lan"), failed.fields)
        p.onState(SourceState.Connecting, 90_000)
        assertEquals(1_000L, p.onState(SourceState.Streaming, 91_000).single().fields["ms"])
    }

    @Test fun ps5FailuresAreCappedAndUnknownKeysAreOther() {
        val p = Ps5Tracker(maxFailures = 2)
        var n = 0
        repeat(5) { i ->
            p.onState(SourceState.Connecting, i * 10L)
            n += p.onState(SourceState.Reconnecting("phase_something_new"), i * 10L + 5).size
        }
        assertEquals(2, n)
        assertEquals("ps5.other", Ps5Tracker.connectCode("phase_something_new"))
        assertEquals("other", Ps5Tracker.dropCode("phase_reconnecting"))
        assertEquals("ps5.discover.none", Ps5Tracker.connectCode("phase_not_found_host"))
        assertEquals("ps5.auth.passcode", Ps5Tracker.connectCode("phase_passcode_incorrect"))
        assertNull(Ps5Tracker.failureCode("error_not_paired"))
        assertEquals("app.native.missing", Ps5Tracker.failureCode("error_native"))
    }

    @Test fun tvTrackerReportsConnectAndDropWithBrandAndProtocol() {
        val t = TvTracker { TelemetryEvent.TvBrand.LG }
        t.start(0)
        val atv = ConnectedDisplay("a", "Salon TV", "10.0.0.2", DisplayKind.ANDROID_TV)
        val old = ConnectedDisplay("b", "Eski", "10.0.0.3", DisplayKind.LEGACY)
        val c = t.onEvent(DisplayEvent.Connected(atv), 420).single()
        assertEquals(mapOf("r" to "ok", "ms" to 420L, "brand" to "androidtv", "proto" to "nino"), c.fields)
        // Abonelikte gelen liste ve tekrar eden olay iki kez sayılmaz.
        val c2 = t.seed(listOf(atv, old), 1_000).single()
        assertEquals(mapOf("r" to "ok", "ms" to 1_000L, "brand" to "lg", "proto" to "legacy"), c2.fields)
        assertTrue(t.onEvent(DisplayEvent.Connected(atv), 1_100).isEmpty())
        val d = t.onEvent(DisplayEvent.Dropped(atv, DropReason.TIMEOUT, 0), 3_050_420).single()
        assertEquals(Kind.TV_DROP, d.kind)
        assertEquals(mapOf("code" to "timeout", "brand" to "androidtv", "after" to 3_050L), d.fields)
        assertTrue(t.onEvent(DisplayEvent.Dropped(atv, DropReason.CLOSED, 0), 3_060_000).isEmpty())
        // TV adı ve adresi gitmez.
        assertTrue((listOf(c, c2, d)).flatMap { it.fields.values }.none { it.toString().contains("10.0.0") || it.toString().contains("TV ") })
    }

    @Test fun tvDropReasonsMapToTarifCodes() {
        val t = TvTracker { null }
        t.start(0)
        val web = ConnectedDisplay("w", "LG", "10.0.0.4", DisplayKind.WEB_TV)
        val codes = listOf(DropReason.CLOSED, DropReason.WRITE_ERROR, DropReason.NETWORK_LOST, DropReason.REPLACED, DropReason.OTHER).map { r ->
            t.onEvent(DisplayEvent.Connected(web), 0)
            t.onEvent(DisplayEvent.Dropped(web, r, 0), 5_000).single().fields["code"]
        }
        assertEquals(listOf("closed", "write_error", "network_lost", "other", "other"), codes)
        // Uygulamanın durdurması kopma değildir; bağlantı yine de listeden çıkar.
        t.onEvent(DisplayEvent.Connected(web), 0)
        assertTrue(t.onEvent(DisplayEvent.Dropped(web, DropReason.STOPPED, 0), 5_000).isEmpty())
        assertFalse(t.connected)
        assertNull(TvTracker.dropCode(DropReason.STOPPED))
    }

    @Test fun tvConnectFailuresAreCodedAndCapped() {
        val t = TvTracker(maxFailures = 2) { null }
        val f = t.onEvent(DisplayEvent.ConnectFailed("10.0.0.2", ConnectFailure.REFUSED), 0).single()
        assertEquals(Kind.TV_CONNECT, f.kind)
        assertEquals(mapOf("r" to "tv.connect.refused", "brand" to "androidtv", "proto" to "nino"), f.fields)
        assertEquals(1, t.onEvent(DisplayEvent.ConnectFailed("10.0.0.2", ConnectFailure.PROTOCOL), 0).size)
        assertTrue(t.onEvent(DisplayEvent.ConnectFailed("10.0.0.2", ConnectFailure.TIMEOUT), 0).isEmpty())
        assertEquals("tv.protocol.mismatch", TvTracker.connectCode(ConnectFailure.PROTOCOL))
        assertEquals("tv.connect.timeout", TvTracker.connectCode(ConnectFailure.NETWORK))
        assertEquals("tv.other", TvTracker.connectCode(ConnectFailure.OTHER))
    }

    @Test fun tvEventLogLinesCarryReasonWithoutNameOrAddress() {
        val d = ConnectedDisplay("a", "Salon TV", "10.0.0.2", DisplayKind.WEB_TV)
        assertEquals("TV bağlandı: web_tv", tvEventLine(DisplayEvent.Connected(d)))
        val drop = tvEventLine(DisplayEvent.Dropped(d, DropReason.WRITE_ERROR, 61_500))
        assertEquals("TV koptu: web_tv, neden write_error, 61 sn bağlı kaldı", drop)
        assertEquals("Android TV'ye bağlanılamadı: timeout", tvEventLine(DisplayEvent.ConnectFailed("10.0.0.2", ConnectFailure.TIMEOUT)))
        assertFalse(drop.contains("10.0.0") || drop.contains("Salon"))
    }

    @Test fun exitReasonsDecideCrashes() {
        // ApplicationExitInfo sabitleri: CRASH 4, CRASH_NATIVE 5, ANR 6, LOW_MEMORY 3, USER_REQUESTED 10.
        assertEquals(PreviousExit.Crash("SIGSEGV"), AppTelemetry.exitOf(5, 11, background = true))
        assertEquals(PreviousExit.Crash("native_crash"), AppTelemetry.exitOf(5, 0, background = false))
        assertEquals(PreviousExit.Crash("anr"), AppTelemetry.exitOf(6, 0, background = true))
        assertEquals(PreviousExit.Crash("oom"), AppTelemetry.exitOf(3, 0, background = false))
        assertEquals(PreviousExit.Clean, AppTelemetry.exitOf(3, 0, background = true))
        assertEquals(PreviousExit.Clean, AppTelemetry.exitOf(10, 0, background = false))
        assertEquals(PreviousExit.Crash("unclean_exit"), AppTelemetry.exitOf(4, 0, background = false))
    }

    @Test fun channelAndProviderNames() {
        assertEquals("dev", AppTelemetry.channel(true, "1.0.0"))
        assertEquals("beta", AppTelemetry.channel(false, "0.1.0-beta.37"))
        assertEquals("release", AppTelemetry.channel(false, "4.0.0"))
        assertEquals("deepl", SessionTelemetry.providerName("deepl"))
        assertEquals("gemini", SessionTelemetry.providerName("gemini:gemini-2.5-flash"))
        assertEquals("online", SessionTelemetry.providerName(null))
        assertEquals("gta-6", SessionTelemetry.gameId("gta-6"))
        assertEquals("gta-6", SessionTelemetry.gameId("Grand Theft Auto VI"))
        assertEquals("gta-v", SessionTelemetry.gameId("Grand Theft Auto V"))
        assertEquals("benim-gizli-oyunum", SessionTelemetry.gameId("Benim Gizli Oyunum"))
        assertNull(SessionTelemetry.gameId("!!!"))
    }
}
