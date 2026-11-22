// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.reading.live

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.nio.ByteBuffer

/** Oyun içi telefon (okuma.md 9): bulma, okuma, panel, yerleşim. Kareler elle çizilir. */
class GamePhoneTest {
    private fun image(bg: Int = 20, block: RgbImage.() -> Unit = {}) = RgbImage(240, 135).apply {
        for (y in 0 until height) for (x in 0 until width) set(x, y, bg, bg, bg)
        block()
    }

    /** Ortası 0.6'da, %20 genişlikte, %60 yükseklikte beyaz telefon; içinde ince koyu "yazı" çizgileri. */
    private fun RgbImage.phone(level: Int = 235, x0: Int = 120, y0: Int = 30, w: Int = 48, h: Int = 81) {
        for (y in y0 until y0 + h) for (x in x0 until x0 + w) {
            val text = y % 6 == 0 && x % 7 in 2..3
            if (text) set(x, y, 30, 30, 30) else set(x, y, level, level, level)
        }
    }

    private fun line(t: String, l: Double, top: Double, r: Double, b: Double) = LiveLine(t, LiveBox(l, top, r, b))

    @Test fun findsWhitePhone() {
        val p = PhoneLocator.find(image { phone() })!!
        assertEquals(0.5, p.box.left, 0.01); assertEquals(0.7, p.box.right, 0.01)
        assertEquals(30 / 135.0, p.box.top, 0.01); assertEquals(111 / 135.0, p.box.bottom, 0.01)
        assertFalse(p.dark)
    }

    @Test fun rejectsWhiteWallsAndWrongShapes() {
        assertNull(PhoneLocator.find(image(bg = 230)))
        // Çok kısa: telefon değil.
        assertNull(PhoneLocator.find(image { phone(h = 30) }))
        // Ortası kenarda.
        assertNull(PhoneLocator.find(image { phone(x0 = 2) }))
    }

    @Test fun brightensDarkFrames() {
        val img = image(bg = 15) { phone(level = 100) }
        assertEquals(100, PhoneLocator.brightPercentile(img))
        assertNotNull(PhoneLocator.find(img))
    }

    @Test fun holdsLastPlaceAndGuesses() {
        val loc = PhoneLocator()
        assertNotNull(loc.locate(image { phone() }, 0))
        // Açık gri zemin: şerit yok ama son yerde hâlâ beyaz ekran duruyor.
        val gray = image(bg = 200)
        assertNotNull(loc.locate(gray, 3_000))
        assertNull(loc.locate(gray, 3_001))
        val guess = PhoneLocator().locate(image(), 0, appWordsSeen = true)!!
        assertTrue(guess.guessed); assertEquals(0.21, guess.box.width, 1e-9); assertEquals(0.20, guess.box.top, 1e-9)
    }

    @Test fun yuvConversion() {
        val w = 32; val h = 18
        val y = ByteBuffer.allocate(w * h).apply { for (i in 0 until w * h) put(i, 235.toByte()) }
        val uv = ByteBuffer.allocate(w * h / 2).apply { for (i in 0 until w * h / 2) put(i, 128.toByte()) }
        val img = RgbImage.fromYuv(y, w, w, h, uv, uv.duplicate().apply { position(1) }.slice(), w, 2, 16, 9)
        assertTrue(img.minChannel(5, 5) >= 250)
        assertTrue(img.spread(5, 5) <= 2)
    }

    @Test fun parsesChat() {
        val lines = listOf(
            line("Cal", 0.42, 0.02, 0.58, 0.06),
            line("Delivered", 0.7, 0.32, 0.9, 0.34),
            line("Hey, are you coming tonight?", 0.05, 0.15, 0.6, 0.2),
            line("On my way now.", 0.45, 0.25, 0.95, 0.3),
        )
        val chat = PhoneText.parse(lines) as PhoneScreen.Chat
        assertEquals("Cal", chat.title)
        assertEquals(listOf("Hey, are you coming tonight?", "On my way now."), chat.messages.map { it.text })
        assertEquals(listOf(false, true), chat.messages.map { it.outgoing })
        assertEquals(listOf(0, 1), chat.translatable)
        // Mavi balon sağa yaslı olmasa da gidendir.
        val blue = PhoneText.parse(lines.take(3)) { 0x2f7cf6 } as PhoneScreen.Chat
        assertTrue(blue.messages[0].outgoing)
    }

    @Test fun recognisesListsMapsAndApps() {
        val list = listOf(
            line("Cal", 0.1, 0.10, 0.2, 0.14), line("See you soon", 0.1, 0.145, 0.5, 0.18),
            line("Jason", 0.1, 0.22, 0.25, 0.26), line("Where are you", 0.1, 0.265, 0.5, 0.30),
            line("Lucia", 0.1, 0.34, 0.25, 0.38), line("Call me back", 0.1, 0.385, 0.5, 0.42),
        )
        assertEquals(PhoneScreen.ChatList, PhoneText.parse(list))
        assertEquals(PhoneScreen.MapScreen, PhoneText.parse(listOf(line("RECENTER", 0.4, 0.9, 0.6, 0.95))))
        assertTrue(PhoneText.parse(listOf(line("BuckMe", 0.4, 0.02, 0.6, 0.06), line("Send money", 0.1, 0.3, 0.5, 0.35))) is PhoneScreen.App)
        // Başlık ortada değilse sohbet değil.
        assertEquals(PhoneScreen.Nothing, PhoneText.parse(listOf(line("Back", 0.42, 0.02, 0.58, 0.06), line("Hey, are you coming tonight?", 0.05, 0.15, 0.6, 0.2))))
    }

    @Test fun skipsCutMessages() {
        val lines = listOf(
            line("Cal", 0.42, 0.02, 0.58, 0.06),
            line("and then we left", 0.05, 0.09, 0.6, 0.13),
            line("Are you there?", 0.05, 0.3, 0.6, 0.35),
            line("I was thinking that we could go", 0.05, 0.88, 0.6, 0.92),
            line("to the beach and maybe", 0.05, 0.925, 0.6, 0.97),
        )
        val chat = PhoneText.parse(lines) as PhoneScreen.Chat
        assertEquals(3, chat.messages.size)
        assertEquals(listOf(1), chat.translatable)
    }

    @Test fun textHelpers() {
        assertEquals("Hey you there", PhoneText.clean("Hey hey &amp; you 😀 there"))
        assertTrue(PhoneText.similar("On my way", "On my way now"))
        assertFalse(PhoneText.similar("On my way", "Where is the car"))
        assertTrue(PhoneText.isLabel("10:24")); assertTrue(PhoneText.isLabel("Typing...")); assertFalse(PhoneText.isLabel("Read the book first"))
        assertTrue(PhoneText.isAppText("Change Destination"))
    }

    @Test fun panelChangesOnlyAfterTwoReadings() {
        val p = PhonePanel()
        fun chat(title: String, top: Double = 0.2, text: String = "Hey, are you coming tonight?") =
            PhoneScreen.Chat(title, listOf(PhoneMessage(text, LiveBox(0.05, top, 0.6, top + 0.05), false)), listOf(0))
        assertEquals(PhonePanel.Change.None, p.onChat(chat("Cal"), 0))
        assertTrue(p.onChat(chat("Cal"), 600) is PhonePanel.Change.Show)
        assertEquals(PhonePanel.Change.None, p.onChat(chat("Cal", text = "Hey, are you coming tonight"), 1_200))
        assertEquals(PhonePanel.Change.Clear, p.onChat(chat("Cal", top = 0.25), 1_800))
        assertTrue(p.onChat(chat("Cal", top = 0.25), 2_400) is PhonePanel.Change.Show)
        assertEquals(PhonePanel.Change.Clear, p.onChat(chat("Jason"), 3_000))
        assertTrue(p.onChat(chat("Jason"), 3_600) is PhonePanel.Change.Show)
    }

    @Test fun motionAndLayout() {
        val m = PhoneMotion()
        val b = LiveBox(0.3, 0.2, 0.5, 0.8)
        m.onPhone(b)
        m.onPhone(b.copy(left = 0.32, right = 0.52))
        assertEquals(0.0, m.offsetX, 1e-9)
        m.onPhone(b.copy(left = 0.33, right = 0.53))
        assertEquals(0.03, m.offsetX, 1e-9); assertTrue(m.panelStays)
        m.onPhone(b.copy(left = 0.42, right = 0.62))
        assertEquals(0.0, m.offsetX, 1e-9)

        val msgs = listOf(
            PhoneMessage("Hey", LiveBox(0.05, 0.2, 0.5, 0.25), false) to "Selam",
            PhoneMessage("On my way", LiveBox(0.5, 0.3, 0.95, 0.35), true) to "Yoldayım",
        )
        val items = PhoneLayout.chat(b, "Cal", msgs)
        assertEquals(4, items.size)
        assertEquals(true, items[0]["backdrop"])
        @Suppress("UNCHECKED_CAST")
        val panel = items[0]["box"] as Map<String, Double>
        assertEquals(0.5 + PhoneLayout.PANEL_GAP, panel["left"]!!, 1e-9)
        @Suppress("UNCHECKED_CAST")
        val out = items[3]["box"] as Map<String, Double>
        assertEquals(panel["left"]!! + PhoneLayout.PANEL_W - 0.01, out["right"]!!, 1e-9)
        assertEquals("Yoldayım", items[3]["text"])
        assertEquals(true, items[3]["side"])
        // Sağdaki telefonda panel solda.
        @Suppress("UNCHECKED_CAST")
        val left = PhoneLayout.chat(LiveBox(0.6, 0.2, 0.8, 0.8), "Cal", msgs)[0]["box"] as Map<String, Double>
        assertEquals(0.6 - PhoneLayout.PANEL_GAP - PhoneLayout.PANEL_W, left["left"]!!, 1e-9)
        assertTrue(PhoneLayout.chat(b, "Cal", emptyList()).isEmpty())
        val app = PhoneLayout.app(b, listOf(PhoneMessage("Book Ryde", LiveBox(0.0, 0.5, 1.0, 0.55), false, 0x000000) to "Ryde çağır"))
        assertEquals("#ffffff", app[0]["ink"])
    }
}
