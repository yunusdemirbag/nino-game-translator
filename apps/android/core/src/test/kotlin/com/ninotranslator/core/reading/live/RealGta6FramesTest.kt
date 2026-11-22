// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.reading.live

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * GTA 6'nın gerçek kareleriyle okuma (okuma.md 3, 9–11, 13). Görüntü işleme (telefon bulma, kart çerçevesi, renk, iz)
 * gerçek piksellerle sınanır. JVM'de OCR olmadığı için okunan satırlar karedeki yazıdan elle yazıldı; kutular 800×450
 * önizlemedeki piksellerdir.
 */
class RealGta6FramesTest {
    private fun px(x0: Int, y0: Int, x1: Int, y1: Int) = LiveBox(x0 / 800.0, y0 / 450.0, x1 / 800.0, y1 / 450.0)

    private fun find(name: String, viaYuv: Boolean = false): PhoneRect? =
        PhoneLocator.find(if (viaYuv) RealFrames.rgbViaYuv("gta6-$name.jpg") else RealFrames.rgb("gta6-$name.jpg"))

    private fun phone(name: String): PhoneRect = find(name) ?: throw AssertionError("telefon bulunamadı: $name")

    /** Kare kutusunu telefon ekranına göre kutuya çevirir (telefon kırpmasının OCR'ı gibi). */
    private fun onPhone(p: LiveBox, b: LiveBox) = LiveRegion(p.top, p.bottom, p.left, p.right).fromFrame(b)

    private fun phoneLines(p: PhoneRect, vararg ls: Pair<String, LiveBox>) =
        ls.filter { (_, b) -> b.midY in p.box.top..p.box.bottom }.map { (t, b) -> LiveLine(t, onPhone(p.box, b)) }

    // ---- telefonu bulma ----

    private data class Expect(val left: Double? = null, val right: Double? = null, val top: Double? = null, val bottom: Double? = null,
                              val mid: Double? = null, val tol: Double = 0.03, val dark: Boolean = false)

    private val phones = mapOf(
        // Gümüş telefon, gündüz ve koyu oda: ekran x ≈ 0.59–0.79, y ≈ 0.20–0.82.
        "telefon-donnie" to Expect(0.59, 0.79, 0.20, 0.82),
        "telefon-kenton" to Expect(0.59, 0.79, 0.20, 0.82),
        "telefon-shirley" to Expect(0.59, 0.79, 0.20, 0.82),
        "telefon-liste" to Expect(0.59, 0.79, 0.20, 0.82),
        "telefon-brian-parlama" to Expect(mid = 0.70, top = 0.19, bottom = 0.82, tol = 0.045),
        // Eğik ve ekranın altından taşan.
        "telefon-egik-alt" to Expect(mid = 0.52, top = 0.58),
        "telefon-egik-mavi" to Expect(mid = 0.48, top = 0.19, bottom = 0.79, tol = 0.04),
        // Karanlık sahnede kararmış ekran.
        "telefon-karanlik" to Expect(0.36, 0.60),
        "telefon-yakin-alt" to Expect(0.36, 0.60),
        // Gölgede, açık zeminin önünde.
        "telefon-altin-kapi" to Expect(0.44, 0.71),
        "telefon-jason-haber-karti" to Expect(mid = 0.58, top = 0.14, bottom = 0.79, tol = 0.04),
        "telefon-kat-kucuk-harf" to Expect(mid = 0.58, top = 0.14, bottom = 0.79, tol = 0.04),
        "telefon-sohbet-listesi" to Expect(mid = 0.59, top = 0.14, bottom = 0.79, tol = 0.04),
        "telefon-lucia-foto" to Expect(mid = 0.47, tol = 0.04),
        // Koyu temalı uygulama (Rydeme).
        "telefon-koyu-rydeme" to Expect(mid = 0.69, top = 0.24, bottom = 0.79, dark = true),
    )

    private fun checkPhone(name: String, e: Expect, viaYuv: Boolean) {
        val p = find(name, viaYuv) ?: throw AssertionError("telefon bulunamadı: $name (yuv=$viaYuv)")
        val b = p.box
        e.left?.let { assertEquals("$name sol", it, b.left, e.tol) }
        e.right?.let { assertEquals("$name sağ", it, b.right, e.tol) }
        e.top?.let { assertEquals("$name üst", it, b.top, e.tol) }
        e.bottom?.let { assertEquals("$name alt", it, b.bottom, e.tol) }
        e.mid?.let { assertEquals("$name orta", it, b.midX, e.tol) }
        assertEquals("$name koyu tema", e.dark, p.dark)
    }

    @Test fun findsThePhoneInEveryPhoneFrame() { phones.forEach { (n, e) -> checkPhone(n, e, viaYuv = false) } }

    /** Cihazdaki gibi YUV 4:2:0 üzerinden de aynı yer bulunur. */
    @Test fun findsThePhoneThroughYuvLikeTheDevice() { phones.forEach { (n, e) -> checkPhone(n, e, viaYuv = true) } }

    @Test fun tiltedPhoneCutByTheBottomEdgeReachesTheEdge() {
        val p = phone("telefon-egik-alt")
        assertTrue(p.box.bottom > 0.96)
        assertTrue(p.slope > 0.1)
    }

    @Test fun noPhoneWhereThereIsNone() {
        for (n in listOf("harita-buckme", "harita-balik", "isaretci-motel", "menu-kapusonlu", "gorev-pembe")) {
            assertNull(n, find(n)); assertNull("$n (yuv)", find(n, viaYuv = true))
        }
    }

    /**
     * Alt pencere açılınca telefon baştan bulunamaz. Son yerde tutma için koyu ekranın en az %50'si koyu kalmalı
     * (tarif); bu karede ancak ~%42'si koyu (alt pencere morumsu), bu yüzden tutulmaz. Aynı kare tekrar gelince ise
     * (Rydeme ekranı duruyorsa) 3 sn tutulur.
     */
    @Test fun darkPhoneHoldFollowsTheFiftyPercentRule() {
        assertNull(find("telefon-koyu-altpencere"))
        val loc = PhoneLocator()
        val rydeme = RealFrames.rgb("gta6-telefon-koyu-rydeme.jpg")
        val first = loc.locate(rydeme, 0)!!
        assertTrue(PhoneLocator.stillThere(rydeme, first))
        assertFalse(PhoneLocator.stillThere(RealFrames.rgb("gta6-telefon-koyu-altpencere.jpg"), first))
        assertFalse(PhoneLocator.stillThere(RealFrames.rgb("gta6-menu-kapusonlu.jpg"), first))
        assertNull(loc.locate(RealFrames.rgb("gta6-menu-kapusonlu.jpg"), 1_000))
    }

    /** Telefon bulma her 150 ms'de bir çalışır; bir kare bunun çok altında bitmeli. */
    @Test fun findIsFastEnough() {
        val imgs = RealFrames.names.map { RealFrames.rgb(it) }
        imgs.forEach { PhoneLocator.find(it) }
        val t0 = System.nanoTime()
        imgs.forEach { PhoneLocator.find(it) }
        val perFrameMs = (System.nanoTime() - t0) / 1e6 / imgs.size
        assertTrue("kare başına $perFrameMs ms", perFrameMs < 60)
    }

    // ---- telefonun ekranı: sohbet, liste, uygulama, renk ----

    @Test fun donnieChatIsReadAsAChatWithTheBlueReplyOutgoing() {
        val p = phone("telefon-donnie")
        val img = RealFrames.rgb("gta6-telefon-donnie.jpg")
        val lines = phoneLines(p,
            "Donnie" to px(535, 94, 563, 103),
            "BUT dropoff is to me NOT Brian" to px(487, 125, 597, 135),
            "TO MY TRAILER! Comprendo?" to px(487, 151, 581, 160),
            "Casa De Donnie" to px(511, 173, 561, 182),
            "Dropped that stuff off for you" to px(500, 208, 608, 218),
            "Thx amigo! U find anything else" to px(487, 232, 591, 242),
            "AND I MEAN ANYTHING u bring" to px(487, 245, 591, 255),
            "it 2 me" to px(487, 257, 525, 267),
            "Thank you thank you. \$\$\$ in" to px(487, 280, 589, 290),
            "your mailbox." to px(487, 292, 535, 302),
            "You got my plane?! You better" to px(487, 314, 598, 324),
            "be good to her! Brian wants me" to px(487, 326, 602, 336),
            "to pick her up in the AM." to px(487, 338, 575, 348),
        )
        val screen = PhoneText.parse(lines) { b -> img.bubble(PhoneLayout.toFrame(p.box, b)) }
        assertTrue("$screen", screen is PhoneScreen.Chat)
        val chat = screen as PhoneScreen.Chat
        assertEquals("Donnie", chat.title)
        val last = chat.messages.last()
        assertTrue(last.text, last.text.startsWith("You got my plane?! You better be good to her!"))
        assertTrue("son mesaj çevrilir", chat.messages.lastIndex in chat.translatable)
        val dropped = chat.messages.first { it.text.startsWith("Dropped that stuff") }
        assertTrue("mavi balon giden mesaj: ${dropped.color?.let(RgbImage::hex)}", dropped.outgoing)
        assertFalse("beyaz balon gelen mesaj", chat.messages.first { it.text.startsWith("Thank you") }.outgoing)
    }

    @Test fun chatListIsNotTranslated() {
        val p = phone("telefon-sohbet-listesi")
        val lines = phoneLines(p,
            "Cal" to px(437, 91, 450, 100), "If anyone asks me anythin..." to px(435, 106, 537, 116),
            "Mia" to px(431, 128, 445, 137), "CALL ME." to px(431, 143, 459, 152),
            "Linda" to px(425, 166, 447, 175), "Okay. Thanks." to px(425, 180, 477, 190),
            "Parole Officer" to px(420, 205, 475, 214), "Last chance. You will be in..." to px(420, 220, 526, 230),
            "Yolanda" to px(415, 242, 445, 251),
            "Kat" to px(409, 279, 421, 288), "next time I see u it's ON SI..." to px(408, 295, 516, 305),
            "Mattia" to px(403, 317, 427, 327), "Your house. We're on our ..." to px(401, 331, 510, 341),
        )
        assertEquals(PhoneScreen.ChatList, PhoneText.parse(lines))
    }

    @Test fun messagesListIsNotTranslated() {
        val p = phone("telefon-liste")
        val lines = phoneLines(p,
            "Suggested" to px(490, 98, 530, 107),
            "Donnie" to px(512, 116, 537, 125), "You got my plane?! You be..." to px(512, 128, 610, 137),
            "Messages" to px(480, 146, 516, 155),
            "Brian" to px(512, 164, 532, 173), "Remember, you get your h..." to px(512, 176, 608, 185),
            "Lucia" to px(512, 196, 532, 205), "You got this!" to px(512, 208, 558, 217),
            "Cal" to px(512, 230, 524, 239), "And 2 here. Have fun" to px(512, 242, 588, 251),
            "BuckMe" to px(512, 264, 540, 273), "Welcome to BuckMe, the ..." to px(512, 276, 612, 285),
        )
        // Önizlemede "BuckMe" geçse de liste uygulama ekranı sayılmaz (emülatörde 15 baloncuk çevriliyordu).
        assertEquals(PhoneScreen.ChatList, PhoneText.parse(lines))
    }

    @Test fun rydemeIsAnAppScreen() {
        val p = phone("telefon-koyu-rydeme")
        val lines = phoneLines(p,
            "Trip Details" to px(517, 98, 562, 107),
            "Righto Cash & Carry" to px(493, 128, 585, 138),
            "Hamlet" to px(480, 147, 507, 156), "1.74 mi" to px(580, 147, 610, 156),
            "Standard Ryde" to px(496, 175, 551, 184),
            "Cost" to px(480, 203, 498, 212), "\$82" to px(480, 222, 497, 231),
            "Book Ryde (\$82)" to px(483, 298, 547, 308),
            "Choose Ryde" to px(483, 321, 534, 330),
            "Change Destination" to px(493, 344, 569, 354),
        )
        val s = PhoneText.parse(lines)
        assertTrue("$s", s is PhoneScreen.App && s.name == "Ryde")
    }

    // ---- altyazı: telefon açıkken alt bölgedeki telefon yazısı atılır, altyazı kalır ----

    /** Okuma döngüsünün yolu: GTA 6 kuralları (oyun bilinmiyor: gta6=false) → gürültü süzgeci. */
    private fun subtitle(rules: Gta6SubtitleRules, now: Long, frameLines: List<Pair<String, LiveBox>>, gta6: Boolean = false): String {
        val region = LiveRegion.BOTTOM
        val inRegion = frameLines.filter { (_, b) -> b.midY in region.top..region.bottom && b.midX in region.left..region.right }
        val kept = inRegion.filterNot { (t, b) -> rules.drop(t, b, now, gta6 = gta6) }
        return LiveNoiseFilter().filter(kept.map { (t, b) -> LiveLine(t, region.fromFrame(b)) }, region, now, TaskStripLine.compute(null, emptyList(), gta6)).text
    }

    @Test fun subtitleStaysAndPhoneTextGoesWhenTheGameIsUnknown() {
        val p = phone("altyazi-beyaz")
        val rules = Gta6SubtitleRules()
        rules.onPhone(p.box, 0)
        val lines = listOf(
            "Remember, you get your hands" to px(553, 323, 672, 334),
            "on anything I might be" to px(553, 337, 640, 348),
            "interested in you bring it to my" to px(553, 349, 674, 360),
            "lockups. I'll cut you a little" to px(553, 360, 660, 371),
            "finder's fee. Door code is 7700." to px(553, 371, 676, 383),
            "Yeah, okay. Just wait, you're gonna love it, we're gonna have fun." to px(185, 397, 613, 411),
        )
        assertEquals("Yeah, okay. Just wait, you're gonna love it, we're gonna have fun.", subtitle(rules, 100, lines))
        // Harita kartı okuyucusu telefonun içindeki yazıyı kart sanmaz.
        assertTrue(rules.insidePhone(px(553, 323, 672, 334), 100))
        assertTrue("telefonun dibindeki satır", rules.insidePhone(px(553, 371, 676, 383), 100))
        assertFalse(rules.insidePhone(px(185, 397, 613, 411), 100))
        // Boyanan kısım altyazıya değmez.
        val black = rules.blackout(100)!!
        assertTrue("boyama ${black.bottom}", black.bottom <= 397 / 450.0)
    }

    /**
     * Alt pencere açık koyu Rydeme karesi: telefon bulunamaz ve oyun bilinmiyor; yine de bilinen uygulama satırları
     * ("Change Destination", "Book Ryde ($82)", "Choose Ryde") altyazıya kaçmaz (okuma.md 9).
     */
    @Test fun knownAppLinesAreNotSubtitlesEvenWithoutAPhone() {
        assertNull(find("telefon-koyu-altpencere"))
        val rules = Gta6SubtitleRules()
        val lines = listOf(
            "Book Ryde (\$82)" to px(483, 300, 548, 311),
            "Choose Ryde" to px(484, 322, 535, 333),
            "Change Destination" to px(493, 346, 570, 357),
        )
        assertEquals("", subtitle(rules, 100, lines))
        assertTrue(rules.drop("Change Destination", px(493, 346, 570, 357), 100, gta6 = false))
        // Yalnız tam eşleşme: bu sözcükleri içeren gerçek altyazı kalır.
        assertFalse(rules.drop("I told you to change destination, Jason.", px(250, 395, 550, 410), 100, gta6 = false))
        assertFalse(rules.drop("Did you book Ryde for tonight?", px(250, 395, 550, 410), 100, gta6 = false))
        assertFalse(rules.drop("Workout first, then calories.", px(250, 395, 550, 410), 100, gta6 = false))
    }

    @Test fun donniePhoneMessageIsNotASubtitle() {
        val p = phone("telefon-donnie")
        val rules = Gta6SubtitleRules()
        rules.onPhone(p.box, 0)
        val lines = listOf(
            "Thank you thank you. \$\$\$ in" to px(487, 280, 589, 290),
            "your mailbox." to px(487, 292, 535, 302),
            "You got my planeM You better" to px(487, 314, 598, 324),
            "be good to hert Brian wants me" to px(487, 326, 602, 336),
            "to pick her up in the AM." to px(487, 338, 575, 348),
        )
        assertEquals("", subtitle(rules, 100, lines))
        // Telefon kalktıktan 5 sn sonra kural da kalkar.
        assertFalse(rules.phoneActive(5_101))
    }

    @Test fun closeDarkPhoneMessageIsNotASubtitle() {
        val p = phone("telefon-yakin-alt")
        val rules = Gta6SubtitleRules()
        rules.onPhone(p.box, 0)
        val lines = listOf(
            "You got my plane?! You better" to px(305, 310, 410, 320),
            "be good to her! Brian wants me" to px(305, 322, 412, 332),
            "to pick her up in the AM." to px(305, 334, 393, 344),
        )
        assertEquals("", subtitle(rules, 100, lines))
    }

    @Test fun glarePhoneFrameKeepsTheSubtitle() {
        val p = phone("telefon-brian-parlama")
        val rules = Gta6SubtitleRules()
        rules.onPhone(p.box, 0)
        val lines = listOf(
            "Remember, you get your hands" to px(483, 293, 604, 303),
            "lockups. I'll cut you a little" to px(483, 329, 590, 339),
            "finder's fee. Door code is 7700." to px(483, 340, 596, 350),
            "Oh, yeah, yeah. Definitely." to px(318, 397, 485, 411),
        )
        assertEquals("Oh, yeah, yeah. Definitely.", subtitle(rules, 100, lines))
    }

    // ---- harita ----

    @Test fun mapScreenAndCardAreFound() {
        val crop = RealFrames.luma("gta6-harita-buckme.jpg")
        val lines = listOf(
            "STORY" to px(14, 17, 57, 33), "Earn Money" to px(65, 53, 124, 64), "Deposit Cash Into BuckMe" to px(65, 80, 199, 91),
            "DEPOSIT CASH INTO BUCKME" to px(461, 185, 605, 196),
            "Use the index or BuckMe to find" to px(455, 207, 618, 219),
            "nearby ATMs" to px(455, 223, 519, 235),
            "Make a cash deposit into your BuckMe" to px(438, 244, 631, 256),
            "checking account at an ATM." to px(438, 259, 585, 271),
            "RECENTER" to px(724, 340, 767, 350), "2D VIEW" to px(735, 362, 767, 372), "ADD MARKER" to px(714, 384, 767, 394),
            "SET DESTINATION" to px(697, 405, 767, 415), "CLOSE MENU" to px(716, 427, 767, 437),
        ).map { (t, b) -> LiveLine(t, b) }
        assertTrue(Gta6Hints.isMapScreen(lines.map { it.text }))
        assertTrue(Gta6Hints.looksLikeGta6(lines.map { it.text }))
        val card = MapCards.find(lines)!!
        assertEquals("DEPOSIT CASH INTO BUCKME", card.title)
        assertEquals(listOf("Use the index or BuckMe to find", "nearby ATMs", "Make a cash deposit into your BuckMe", "checking account at an ATM."), card.sentences)
        // Çerçeve gerçek piksellerden: kartın koyu zemini y ≈ 0.38–0.61.
        val full = LiveRegion(0.0, 1.0, 0.0, 1.0)
        val (top, bottom) = MapCards.frame(crop, full, card.box)
        assertEquals(172 / 450.0, top!!, 0.02)
        assertEquals(276 / 450.0, bottom!!, 0.02)
        // Türkçe çerçevenin altına yazılır.
        val (box, _) = MapCards.place(card.box, 5, top, bottom)
        assertTrue(box.top >= bottom)
    }

    @Test fun fishCardWithDistanceLabel() {
        val crop = RealFrames.luma("gta6-harita-balik.jpg")
        val lines = listOf(
            "ACTIVITIES" to px(14, 17, 85, 33), "Catch a Bigger Fish" to px(65, 53, 164, 64),
            "1.53 km" to px(386, 236, 413, 245),
            "CATCH A BIGGER FISH" to px(461, 204, 570, 216),
            "Cal challenged you to catch a stoplight" to px(438, 224, 640, 236),
            "parrotfish larger than 0.9 kg." to px(438, 239, 584, 251),
            "RECENTER" to px(724, 340, 767, 350), "SET DESTINATION" to px(697, 405, 767, 415),
        ).map { (t, b) -> LiveLine(t, b) }
        assertTrue(Gta6Hints.isMapScreen(lines.map { it.text }))
        val card = MapCards.find(lines)!!
        assertEquals("CATCH A BIGGER FISH", card.title)
        assertEquals(2, card.sentences.size)
        val (top, bottom) = MapCards.frame(crop, LiveRegion(0.0, 1.0, 0.0, 1.0), card.box)
        assertEquals(192 / 450.0, top!!, 0.02)
        assertEquals(257 / 450.0, bottom!!, 0.02)
    }

    @Test fun markerViewCardKeepsThePlaceName() {
        val r = MapCards.READ_REGION
        val crop = RealFrames.luma("gta6-isaretci-motel.jpg").let { full ->
            val y0 = (r.top * full.height).toInt(); val y1 = (r.bottom * full.height).toInt()
            LumaPlane(full.data.copyOfRange(y0 * full.width, y1 * full.width), full.width, y1 - y0)
        }
        val lines = listOf(
            "STARLET MOTEL" to px(438, 184, 516, 196),
            "Room at a roadside motel with basic" to px(438, 204, 626, 216),
            "amenities and cheap rates. Cheap, but" to px(438, 220, 624, 232),
            "not free." to px(438, 236, 483, 248),
            "FEATURES" to px(438, 256, 475, 266),
            "VIEW ON MAP" to px(455, 281, 507, 291), "SET DESTINATION" to px(455, 299, 523, 309),
            "CINEMATIC" to px(723, 384, 767, 394), "MARKERS" to px(710, 405, 748, 415),
        ).map { (t, b) -> LiveLine(t, b) }
        assertTrue(Gta6Hints.isMapScreen(lines.map { it.text }))
        val card = MapCards.find(lines)!!
        assertEquals("STARLET MOTEL", card.title)
        assertTrue(MapCards.isPlaceName(card.title!!))
        assertEquals(3, card.sentences.size)
        val (_, bottom) = MapCards.frame(crop, r, card.box)
        assertEquals(275 / 450.0, bottom!!, 0.02)
    }

    @Test fun menuIsGta6ButNotAMap() {
        val texts = listOf("JASON & LUCIA", "MAP", "BRIEF", "PROGRESS", "JASON", "LUCIA", "CRAZY IN LOVE (3/4)", "EXIT")
        assertFalse(Gta6Hints.isMapScreen(texts))
        assertTrue(Gta6Hints.looksLikeGta6(texts))
        assertNull(MapCards.find(texts.mapIndexed { i, t -> LiveLine(t, LiveBox(0.4, 0.02 + i * 0.01, 0.5, 0.03 + i * 0.01)) }))
    }

    // ---- görev: alt şeritteki hedef yazısı altyazı değildir, ek alanla okunur ----

    private val goToRoom = px(348, 426, 452, 436)

    @Test fun missionObjectiveIsBelowTheTaskLine() {
        val rules = Gta6SubtitleRules()
        assertEquals("", subtitle(rules, 0, listOf("Go to Jason's room" to goToRoom)))
    }

    @Test fun missionObjectiveIsReadByAnExtraArea() {
        val full = RealFrames.luma("gta6-gorev-pembe.jpg")
        val area = LiveRegion(0.90, 0.99, 0.30, 0.70)
        val rect = FrameTrace.crop(area, full.width, full.height)!!
        val other = RealFrames.luma("gta6-menu-kapusonlu.jpg")
        val t = ExtraAreaTracker()
        val read = listOf(LiveLine("Go to Jason's room", area.fromFrame(goToRoom)))
        // İlk tur okunur ama tek okuma kararlı değildir.
        assertTrue(t.shouldRead(FrameTrace.coarse(full, rect)))
        assertEquals(ExtraAreaTracker.Decision.Nothing, t.onRead(read, area))
        // İz aynı: yeniden okunmaz, yazı bu turda kararlı sayılır.
        assertFalse(t.shouldRead(FrameTrace.coarse(full, rect)))
        val d = t.unchangedRound()
        assertTrue("$d", d is ExtraAreaTracker.Decision.Translate && d.parts == listOf("Go to Jason's room"))
        // Başka kare: iz değişir, yeniden okunur.
        assertTrue(t.shouldRead(FrameTrace.coarse(other, FrameTrace.crop(area, other.width, other.height)!!)))
    }

    // ---- harita kartı kalkma histerezisi (gerçek piksellerle görüntü değişimi) ----

    private fun mapCrop(name: String): LumaPlane {
        val r = MapCards.READ_REGION
        val full = RealFrames.luma("gta6-$name.jpg")
        val y0 = (r.top * full.height).toInt(); val y1 = (r.bottom * full.height).toInt()
        return LumaPlane(full.data.copyOfRange(y0 * full.width, y1 * full.width), full.width, y1 - y0)
    }

    /** Kart gitmiş gibi: kartın satırlarına kartın hemen üstündeki harita satırları kopyalanır. */
    private fun withoutCard(p: LumaPlane, frameTop: Double, frameBottom: Double): LumaPlane {
        val r = MapCards.READ_REGION
        fun row(y: Double) = (((y - r.top) / r.height) * p.height).toInt()
        val a = row(frameTop); val b = row(frameBottom); val h = b - a
        val d = p.data.copyOf()
        for (y in a until b) System.arraycopy(p.data, (y - h) * p.width, d, y * p.width, p.width)
        return LumaPlane(d, p.width, p.height)
    }

    private fun noisy(p: LumaPlane, amp: Int): LumaPlane {
        val rnd = java.util.Random(7)
        return LumaPlane(ByteArray(p.data.size) { i -> ((p.data[i].toInt() and 0xFF) + rnd.nextInt(2 * amp + 1) - amp).coerceIn(0, 255).toByte() }, p.width, p.height)
    }

    private val fishCard = MapCardText("CATCH A BIGGER FISH", listOf("Cal challenged you to catch a stoplight", "parrotfish larger than 0.9 kg."),
        px(438, 204, 640, 251))

    @Test fun fishCardStaysWhileThePictureIsTheSameAndGoesWhenItChanges() = kotlinx.coroutines.runBlocking {
        val r = MapCards.READ_REGION
        val seen = mapCrop("harita-balik")
        var calls = 0
        val tr: suspend (MapCardText) -> String? = { calls++; "DAHA BÜYÜK BİR BALIK TUT" }

        // OCR kartı 3+ okumada kaçırdı ama görüntü aynı (video gürültüsüyle): kart kalır.
        val keep = MapCardKeeper()
        assertEquals("DAHA BÜYÜK BİR BALIK TUT", keep.seen(fishCard, seen, r, tr))
        var t = 0L
        repeat(10) { i -> t += 2_000; assertFalse("okuma $i", keep.missing(noisy(seen, 6), r, t)) }
        assertTrue(keep.hold.showing)
        // Aynı kart yeniden okundu: çevirmene gitmez.
        assertEquals("DAHA BÜYÜK BİR BALIK TUT", keep.seen(fishCard, seen, r, tr))
        assertEquals(1, calls)

        // Kart gerçekten gitti (yerinde harita): 3 okuma ve 4 sn sonra kalkar, daha önce değil.
        val gone = withoutCard(seen, 192 / 450.0, 257 / 450.0)
        assertTrue(MapCardKeeper.trace(seen, r, fishCard.box)!!.changedShare(MapCardKeeper.trace(gone, r, fishCard.box)!!) >= ScreenItemHold.MIN_CHANGED_SHARE)
        t += 1_500; assertFalse(keep.missing(gone, r, t))
        t += 1_500; assertFalse(keep.missing(gone, r, t))
        t += 1_500; assertFalse("4 sn dolmadı", keep.missing(gone, r, t))
        t += 1_500; assertTrue(keep.missing(gone, r, t))
        assertFalse(keep.hold.showing)

        // Başka bir harita ekranına geçildi (BuckMe kartı): bölge değişti.
        val other = MapCardKeeper()
        other.seen(fishCard, seen, r, tr)
        val buck = mapCrop("harita-buckme")
        assertFalse(other.missing(buck, r, 2_000)); assertFalse(other.missing(buck, r, 4_000))
        assertTrue(other.missing(buck, r, 6_000))
    }

    // ---- telefon paneli kalkma histerezisi (ortak tahta; gerçek piksellerle bölge değişimi) ----

    private fun donnieChat(p: PhoneRect): PhoneScreen.Chat {
        val img = RealFrames.rgb("gta6-telefon-donnie.jpg")
        val lines = phoneLines(p,
            "Donnie" to px(535, 94, 563, 103),
            "Dropped that stuff off for you" to px(500, 208, 608, 218),
            "Thank you thank you. \$\$\$ in" to px(487, 280, 589, 290),
            "your mailbox." to px(487, 292, 535, 302),
            "You got my plane?! You better" to px(487, 314, 598, 324),
            "be good to her! Brian wants me" to px(487, 326, 602, 336),
            "to pick her up in the AM." to px(487, 338, 575, 348),
        )
        return PhoneText.parse(lines) { b -> img.bubble(PhoneLayout.toFrame(p.box, b)) } as PhoneScreen.Chat
    }

    /** Donnie sohbeti iki okumada görülüp panel gösterildi. */
    private fun shownDonnie(): Triple<PhoneKeeper, PhoneRect, LumaPlane> {
        val p = phone("telefon-donnie")
        val full = RealFrames.luma("gta6-telefon-donnie.jpg")
        val tr = ScreenItemBoard.trace(full, p.box)
        val k = PhoneKeeper()
        val chat = donnieChat(p)
        assertEquals(PhoneKeeper.Step.None, k.onChat(chat, p.box, tr, 0))
        val step = k.onChat(chat, p.box, tr, 600)
        assertTrue("$step", step is PhoneKeeper.Step.Show)
        val msgs = (step as PhoneKeeper.Step.Show).messages
        k.show(p.box, tr, PhoneLayout.chat(p.box, step.title, msgs.map { it to "TR ${it.text}" }))
        assertTrue(k.showing)
        return Triple(k, p, full)
    }

    @Test fun oneOrTwoMissedPhoneReadsDoNotRemoveThePanel() {
        val (k, p, full) = shownDonnie()
        val same = ScreenItemBoard.trace(noisy(full, 6), p.box)
        assertFalse(k.missed(same, 1_600))
        assertTrue("tek kaçırma silmez", k.showing)
        // Yeniden okundu: sayaç sıfırlanır; sonra iki kaçırma (bölge değişse de) silmez.
        assertEquals(PhoneKeeper.Step.None, k.onChat(donnieChat(p), p.box, ScreenItemBoard.trace(full, p.box), 2_600))
        val other = ScreenItemBoard.trace(RealFrames.luma("gta6-harita-balik.jpg"), p.box)
        assertFalse(k.missed(other, 3_600))
        assertFalse(k.missed(other, 9_000))
        assertTrue("iki kaçırma silmez", k.showing)
    }

    @Test fun samePhoneRegionKeepsThePanelAfterManyMisses() {
        val (k, p, full) = shownDonnie()
        var t = 600L
        repeat(20) { i -> t += 1_000; assertFalse("okuma $i", k.missed(ScreenItemBoard.trace(noisy(full, 6), p.box), t)) }
        assertTrue(k.showing)
    }

    @Test fun phonePanelGoesAfterThreeMissesFourSecondsAndAChangedRegion() {
        val (k, p, full) = shownDonnie()
        val seen = ScreenItemBoard.trace(full, p.box)!!
        val gone = ScreenItemBoard.trace(RealFrames.luma("gta6-harita-balik.jpg"), p.box)!!
        assertTrue(seen.changedShare(gone) >= ScreenItemHold.MIN_CHANGED_SHARE)
        assertFalse(k.missed(gone, 1_600))
        assertFalse(k.missed(gone, 2_600))
        assertFalse("3 okuma ama 4 sn dolmadı", k.missed(gone, 3_600))
        assertFalse(k.missed(gone, 4_600))
        assertTrue(k.missed(gone, 5_600))
        assertFalse(k.showing)
        assertNull(k.area)
        // Panel durumu da sıfırlandı: aynı sohbet yeniden iki okumada gösterilir.
        assertEquals(PhoneKeeper.Step.None, k.onChat(donnieChat(p), p.box, seen, 7_000))
        assertTrue(k.onChat(donnieChat(p), p.box, seen, 7_600) is PhoneKeeper.Step.Show)
    }

    @Test fun titleChangeScrollAndChatListStillRemoveThePanelAtOnce() {
        val (k, p, full) = shownDonnie()
        val tr = ScreenItemBoard.trace(full, p.box)
        val chat = donnieChat(p)
        assertEquals(PhoneKeeper.Step.Cleared, k.onChat(chat.copy(title = "Kenton"), p.box, tr, 1_000))
        assertFalse("başlık değişti: hemen kalkar", k.showing)

        val (k2, _, _) = shownDonnie()
        val moved = chat.copy(messages = chat.messages.map { it.copy(box = it.box.copy(top = it.box.top + 0.03, bottom = it.box.bottom + 0.03)) })
        assertEquals(PhoneKeeper.Step.Cleared, k2.onChat(moved, p.box, tr, 1_000))
        assertFalse("mesajlar kaydı: hemen kalkar", k2.showing)

        val (k3, _, _) = shownDonnie()
        assertTrue("sohbet listesi: hemen kalkar", k3.drop())
        assertFalse(k3.showing)
    }

    @Test fun phoneAndMapCardShareOneBoard() = kotlinx.coroutines.runBlocking {
        val board = ScreenItemBoard()
        val phoneK = PhoneKeeper(board)
        val cards = MapCardKeeper(board = board)
        val r = MapCards.READ_REGION
        val crop = mapCrop("harita-balik")
        cards.seen(fishCard, crop, r) { "KART" }
        board.show(ScreenItemBoard.Kind.MAP, listOf(mapOf("text" to "KART")))
        val p = phone("telefon-donnie")
        val full = RealFrames.luma("gta6-telefon-donnie.jpg")
        phoneK.show(p.box, ScreenItemBoard.trace(full, p.box), listOf(mapOf("text" to "TR")))
        assertEquals(listOf("TR", "KART"), board.list().map { it["text"] })
        // Kart gitti: yalnız kart kalkar.
        val gone = withoutCard(crop, 192 / 450.0, 257 / 450.0)
        var t = 0L
        var removed = false
        repeat(4) { t += 1_500; removed = cards.missing(gone, r, t) || removed }
        assertTrue(removed)
        assertEquals(listOf("TR"), board.list().map { it["text"] })
    }
}
