// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.xbox

import com.ninotranslator.core.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.IOException
import java.nio.ByteBuffer
import java.nio.ByteOrder

class XboxChannelTest {
    @Test fun channelOrderAndProtocols() {
        assertEquals(listOf("input" to "1.0", "chat" to "chatV1", "control" to "controlV1", "message" to "messageV1"),
            XboxChannelMessages.CHANNELS.map { it.label to it.protocol })
    }

    @Test fun textMessages() {
        val h = Json.parseObject(XboxChannelMessages.handshake())
        assertEquals("Handshake", h["type"]); assertEquals("messageV1", h["version"]); assertEquals("0", h["cv"])
        assertEquals(36, (h["id"] as String).length)
        assertTrue(XboxChannelMessages.isHandshakeAck("""{"type":"HandshakeAck","version":"messageV1"}"""))
        assertFalse(XboxChannelMessages.isHandshakeAck("""{"type":"Message"}"""))
        assertFalse(XboxChannelMessages.isHandshakeAck("bozuk"))
        val a = Json.parseObject(XboxChannelMessages.authorization())
        assertEquals("authorizationRequest", a["message"]); assertEquals(36, (a["accessKey"] as String).length)
        assertEquals("""{"message":"gamepadChanged","gamepadIndex":0,"wasAdded":true}""", XboxChannelMessages.gamepadAdded())
    }

    @Test fun configurationMessages() {
        var n = 0
        val list = XboxChannelMessages.configuration(newId = { "id-${n++}" }).map(Json::parseObject)
        assertEquals(listOf(
            "/streaming/systemUi/configuration", "/streaming/properties/clientappinstallidchanged",
            "/streaming/characteristics/orientationchanged", "/streaming/characteristics/touchinputenabledchanged",
            "/streaming/characteristics/clientdevicecapabilities", "/streaming/characteristics/dimensionschanged",
        ), list.map { it["target"] })
        assertTrue(list.all { it["type"] == "Message" && it["cv"] == "" })
        assertEquals("id-0", list[0]["id"]); assertEquals("id-5", list[5]["id"])
        val dims = Json.parseObject(list[5]["content"] as String)
        assertEquals(1920L, (dims["horizontal"] as Number).toLong()); assertEquals(1080L, (dims["safeAreaBottom"] as Number).toLong())
        assertEquals(true, dims["supportsCustomResolution"])
        assertEquals(false, Json.parseObject(list[3]["content"] as String)["touchInputEnabled"])
        assertEquals(0L, (Json.parseObject(list[2]["content"] as String)["orientation"] as Number).toLong())
    }

    @Test fun clientInfoPacket() {
        val b = XboxChannelMessages.clientInfo(1234.5, maxTouchPoints = 5)
        assertEquals(15, b.size)
        val bb = ByteBuffer.wrap(b).order(ByteOrder.LITTLE_ENDIAN)
        assertEquals(8, bb.short.toInt()); assertEquals(0, bb.int); assertEquals(1234.5, bb.double, 0.0); assertEquals(2, bb.get().toInt())
        assertEquals(1, XboxChannelMessages.clientInfo(0.0, 0)[14].toInt())
    }

    @Test fun frameAckPacket() {
        val frames = listOf(FrameTiming(XboxChannelMessages.rtpKey(100_000_000L), 10, 12), FrameTiming(7, 20, 25))
        val b = XboxChannelMessages.frameAcks(3, 99.0, frames)
        assertEquals(14 + 1 + 28 * 2, b.size)
        val bb = ByteBuffer.wrap(b).order(ByteOrder.LITTLE_ENDIAN)
        assertEquals(1, bb.short.toInt()); assertEquals(3, bb.int); assertEquals(99.0, bb.double, 0.0); assertEquals(2, bb.get().toInt())
        val first = IntArray(7) { bb.int }
        assertEquals((100_000_000L * 90 and 0xFFFFFFFFL).toInt(), first[0])
        assertEquals(listOf(10, 10, 12, 12, 99, 99), first.drop(1))
        assertEquals(listOf(7, 20, 20, 25, 25, 99, 99), IntArray(7) { bb.int }.toList())
        assertEquals(1 shl 7, XboxChannelMessages.REPORT_VIBRATION)
        assertEquals(128, XboxChannelMessages.reportType(byteArrayOf(128.toByte(), 0, 1)))
    }

    @Test fun ackQueueCapsAndBatches() {
        val q = FrameAckQueue(capacity = 600)
        repeat(650) { q.add(FrameTiming(it.toLong(), 0, 0)) }
        assertEquals(600, q.size()); assertEquals(50L, q.dropped)
        val batch = q.take()
        assertEquals(29, batch.size)
        assertEquals(50L, batch.first().rtpKey)
        assertEquals(571, q.size())
        assertTrue(FrameAckQueue().take().isEmpty())
    }

    @Test fun retryDelaysAndGiveUp() {
        val p = XboxRetryPolicy()
        assertEquals(XboxNext.Retry(5_000, XboxProblem.NETWORK), p.onEnded(XboxProblem.NETWORK, false, 0))
        assertEquals(XboxNext.Retry(15_000, XboxProblem.TIMEOUT), p.onEnded(XboxProblem.TIMEOUT, false, 0))
        assertEquals(XboxNext.Retry(45_000, XboxProblem.UNREACHABLE), p.onEnded(XboxProblem.UNREACHABLE, false, 0))
        assertEquals(XboxNext.GiveUp(XboxProblem.NETWORK), p.onEnded(XboxProblem.NETWORK, false, 0))
    }

    @Test fun retryResetsAfterSixtySecondsOfStreaming() {
        val p = XboxRetryPolicy()
        p.onEnded(XboxProblem.NETWORK, false, 0); p.onEnded(XboxProblem.NETWORK, false, 0)
        p.onStreaming(1_000)
        assertEquals(45_000L, (p.onEnded(XboxProblem.NETWORK, false, 30_000) as XboxNext.Retry).delayMs)
        p.onStreaming(100_000)
        assertEquals(5_000L, (p.onEnded(XboxProblem.NETWORK, false, 160_000) as XboxNext.Retry).delayMs)
    }

    @Test fun neverRetried() {
        val p = XboxRetryPolicy()
        assertEquals(XboxNext.Stop(XboxProblem.SIGN_IN), p.onEnded(XboxProblem.SIGN_IN, false, 0))
        assertEquals(XboxNext.Stop(XboxProblem.NO_PROFILE), p.onEnded(XboxProblem.NO_PROFILE, false, 0))
        assertEquals(XboxNext.GiveUp(XboxProblem.BUSY), p.onEnded(XboxProblem.BUSY, true, 0))
    }

    @Test fun problemMappingAndKeys() {
        assertEquals(XboxProblem.SIGN_IN to false, XboxTexts.problemOf(XboxException(XboxErrorKind.EXPIRED)))
        assertEquals(XboxProblem.NO_PROFILE to false, XboxTexts.problemOf(XboxException(XboxErrorKind.NO_ACCOUNT)))
        assertEquals(XboxProblem.NETWORK to false, XboxTexts.problemOf(XboxException(XboxErrorKind.OFFLINE)))
        assertEquals(XboxProblem.NETWORK to false, XboxTexts.problemOf(IOException()))
        assertEquals(XboxProblem.BUSY to true, XboxTexts.problemOf(XboxStreamException(XboxProblem.BUSY, rejected = true)))
        assertEquals("xbox_error_sign_in", XboxTexts.retryKey(XboxProblem.SIGN_IN))
        assertEquals("xbox_phase_busy", XboxTexts.retryKey(XboxProblem.BUSY))
        assertEquals("xbox_reason_timeout", XboxTexts.reasonKey(XboxProblem.TIMEOUT))
    }
}
