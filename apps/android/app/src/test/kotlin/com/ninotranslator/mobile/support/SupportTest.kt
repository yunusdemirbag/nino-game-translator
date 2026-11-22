// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.support

import com.ninotranslator.mobile.update.AppUpdateChecker
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SupportTest {
    @Test fun redactsSecrets() {
        val log = "Authorization: Bearer abc.def-123\nkey=AIzaSyA1234567890abcdef token=\"xyz\" sk-proj-abcdefghij1234 " +
            "hash 0123456789abcdef0123456789abcdef ok"
        val r = LogRedactor.redact(log)
        assertFalse(r.contains("abc.def-123"))
        assertFalse(r.contains("AIzaSy"))
        assertFalse(r.contains("xyz"))
        assertFalse(r.contains("sk-proj"))
        assertFalse(r.contains("0123456789abcdef0123456789abcdef"))
        assertTrue(r.endsWith("ok"))
    }

    @Test fun replyBlocks() {
        val b = ReplyParser.parse("Merhaba.\nİkinci satır.\n\n1. Birinci\n   devamı\n2) İkinci\n- madde\n• nokta")
        assertEquals(ReplyBlock.Paragraph("Merhaba.\nİkinci satır."), b[0])
        assertEquals(ReplyBlock.Step(1, "Birinci\ndevamı"), b[1])
        assertEquals(ReplyBlock.Step(2, "İkinci"), b[2])
        assertEquals(ReplyBlock.Bullet("madde"), b[3])
        assertEquals(ReplyBlock.Bullet("nokta"), b[4])
    }

    @Test fun linksDropTrailingPunctuation() {
        val t = "Bak: https://nino.example/a?b=1."
        val r = ReplyParser.links(t).single()
        assertEquals("https://nino.example/a?b=1", t.substring(r.first, r.last + 1))
    }

    @Test fun assistantResponses() {
        assertEquals(AssistantOutcome.Reply("Selam", true), AssistantRequest.parse(200 to """{"ok":true,"reply":"Selam","report":"r1"}"""))
        assertEquals(AssistantOutcome.Failed(AssistantWarning.DISABLED), AssistantRequest.parse(503 to """{"error":"assistant_disabled"}"""))
        assertEquals(AssistantOutcome.Failed(AssistantWarning.BUSY), AssistantRequest.parse(429 to """{"error":"busy"}"""))
        assertEquals(AssistantOutcome.Failed(AssistantWarning.RATE_LIMITED), AssistantRequest.parse(429 to """{"error":"limit"}"""))
        assertEquals(AssistantOutcome.Failed(AssistantWarning.TOO_LARGE), AssistantRequest.parse(413 to ""))
        assertEquals(AssistantOutcome.Failed(AssistantWarning.INVALID), AssistantRequest.parse(400 to ""))
        assertEquals(AssistantOutcome.Failed(AssistantWarning.NETWORK), AssistantRequest.parse(502 to ""))
        assertTrue(AssistantWarning.BUSY.retryable && !AssistantWarning.RATE_LIMITED.retryable)
    }

    @Test fun reportTextAndStatus() {
        val t = ReportSender.composeText("", "— Nino'nun tespitleri —")
        assertTrue(t.startsWith(ReportSender.NO_TEXT))
        assertEquals(ReportSender.MAX_TEXT, ReportSender.composeText("x".repeat(5000), "y").length)
        // Yarım vekil çift bırakılmaz.
        val emoji = "a".repeat(3999) + "😀"
        assertEquals(3999, DeviceSummary.clip(emoji, 4000).length)
        assertEquals(ReportSender.Result.SENT, ReportSender.resultOf(201))
        assertEquals(ReportSender.Result.RATE_LIMITED, ReportSender.resultOf(429))
        assertEquals(ReportSender.Result.FAILED, ReportSender.resultOf(500))
    }

    @Test fun deviceSummaryJoinAndScrub() {
        assertEquals("app: 1 (2) | status: a / b c", DeviceSummary.join(listOf("app" to "1 (2)", "tv" to " ", "status" to "a | b\nc")))
        assertEquals("bağlanılıyor … …", DeviceSummary.scrub("bağlanılıyor 192.168.0.5:9295 Salon PS5", listOf("Salon PS5")))
    }

    @Test fun healthThresholdsAndCauses() {
        val base = HealthInput(running = true, streaming = true, measured = true, everStreamed = true, network = NetKind.WIFI,
            streamedMs = 30_000, fps = 30.0, medianTranslateMs = 800)
        assertEquals(HealthLevel.GOOD, HealthEval.pictureLevel(base))
        assertEquals(HealthLevel.WARNING, HealthEval.pictureLevel(base.copy(fps = 20.0)))
        assertEquals(HealthLevel.PROBLEM, HealthEval.pictureLevel(base.copy(fps = 10.0)))
        assertEquals(HealthLevel.UNKNOWN, HealthEval.pictureLevel(base.copy(streamedMs = 10_000)))
        assertEquals(HealthLevel.WARNING, HealthEval.translationLevel(base.copy(medianTranslateMs = 2000)))
        assertEquals(HealthLevel.PROBLEM, HealthEval.translationLevel(base.copy(medianTranslateMs = 3500)))
        assertEquals(HealthLevel.GOOD, HealthEval.networkLevel(base.copy(network = NetKind.WIRED, fps = 5.0)))
        assertEquals(emptyList<HealthCause>(), HealthEval.causes(base))
        assertEquals(listOf(HealthCause.PICTURE_WIFI), HealthEval.causes(base.copy(fps = 10.0)))
        assertEquals(listOf(HealthCause.DROPS), HealthEval.causes(base.copy(drops = 3)))
        val lost = base.copy(streaming = false, disconnectedSinceMs = 1, drops = 1, networkLosses = 1, networkLostBeforeDrop = true)
        assertEquals(HealthCause.PS5_AFTER_NETWORK, HealthEval.causes(lost).first())
        assertEquals(listOf(HealthCause.OFFLINE), HealthEval.causes(HealthInput(network = NetKind.OFFLINE)))
        assertEquals(1000L, HealthEval.median(listOf(500L, 1500L)))
    }

    @Test fun updateTagParsing() {
        assertEquals("0.2.6", AppUpdateChecker.latestOf("""{"tag_name":"v0.2.6","draft":false,"prerelease":false}"""))
        assertNull(AppUpdateChecker.latestOf("""{"tag_name":"v0.3.0","prerelease":true}"""))
        assertEquals("1.0.0", AppUpdateChecker.latestOf("""{"tag_name":"1.0.0+5"}"""))
    }
}
