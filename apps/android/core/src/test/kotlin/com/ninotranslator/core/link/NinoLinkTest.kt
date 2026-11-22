// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.link

import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class NinoLinkTest {
    @Test fun messagesRoundTripWithStableKeys() {
        val show = NinoMessage.Show(ShowPayload(42, "Buraya gel.", "Come here.", extras = mapOf("style" to mapOf("font" to "condensed"))))
        assertEquals("""{"app":"nino","durationMs":0,"id":42,"position":"bottom","source":"Come here.","style":{"font":"condensed"},"text":"Buraya gel.","type":"show"}""", show.encode())
        assertEquals(show, NinoMessage.decode(show.encode()))
        assertEquals(NinoMessage.Clear(null), NinoMessage.decode("""{"app":"nino","type":"clear"}"""))
        assertEquals(NinoMessage.Unknown("future"), NinoMessage.decode("""{"app":"nino","type":"future","x":1}"""))
    }

    @Test(expected = NinoMessage.DecodeException::class) fun rejectsNonNino() { NinoMessage.decode("""{"app":"other","type":"show"}""") }

    @Test fun urlsAndLocalAddresses() {
        assertEquals("ws://192.168.0.110:47800/nino/ws", NinoLink.url("ws", "192.168.0.110%en0", 47800, "/nino/ws"))
        assertEquals("http://[fe80::1%25wlan0]:47800/nino/info", NinoLink.url("http", "fe80::1%wlan0", 47800, "/nino/info"))
        for (h in listOf("10.0.0.2", "172.20.1.1", "192.168.1.5", "169.254.3.3", "127.0.0.1", "::1", "fe80::2", "fd00::1"))
            assertTrue(h, NinoLink.isLocalAddress(h))
        for (h in listOf("8.8.8.8", "172.32.0.1", "2001:db8::1", "example.com")) assertFalse(h, NinoLink.isLocalAddress(h))
    }

    @Test fun backoffDoublesUpToEight() {
        val b = ReconnectBackoff()
        assertEquals(listOf(1000L, 2000L, 4000L, 8000L, 8000L), List(5) { b.next() })
        b.reset(); assertEquals(1000L, b.next())
    }

    @Test fun handshakeShowClearAndPing() = runBlocking {
        FakeDisplay("Salon TV").use { tv ->
            val sender = NinoSender("127.0.0.1", tv.port, device = "Telefon", client = "nino-android/test")
            assertEquals("Salon TV", sender.connect())
            sender.show(ShowPayload(1, "Merhaba.", "Hello."))
            sender.clear(1)
            sender.ping(2_000)
            withTimeout(2_000) { while (tv.received.size < 4) delay(10) }
            val types = tv.received.map { it.type }
            assertEquals(listOf("hello", "show", "clear", "ping"), types)
            assertEquals("nino-android/test", (tv.received[0] as NinoMessage.Hello).client)
            sender.close()
        }
    }

    @Test fun reconnectsAndResendsLastSubtitle() = runBlocking {
        FakeDisplay().use { tv ->
            val sender = NinoSender("127.0.0.1", tv.port)
            sender.connect()
            sender.show(ShowPayload(7, "Kal.", "Stay."))
            sender.startKeepAlive(intervalMs = 100, pongTimeoutMs = 300, backoff = ReconnectBackoff(50, 100))
            tv.dropAll()
            withTimeout(5_000) { while (tv.connections < 2 || tv.received.count { it is NinoMessage.Show } < 2) delay(20) }
            assertEquals(7, (tv.received.last { it is NinoMessage.Show } as NinoMessage.Show).payload.id)
            sender.close()
        }
    }

    @Test fun versionUnsupportedIsReported() = runBlocking {
        FakeDisplay(versions = listOf(2)).use { tv ->
            val sender = NinoSender("127.0.0.1", tv.port)
            val e = runCatching { sender.connect() }.exceptionOrNull()
            assertTrue(e.toString(), e is NinoSender.SenderException.VersionUnsupported)
            sender.close()
        }
    }
}
