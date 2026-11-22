// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.reading.live

import kotlin.math.abs

/** Telefondaki bir mesaj. [box] telefon ekranına göre (0–1). [color] balonun rengi (bilinmiyorsa null). */
data class PhoneMessage(val text: String, val box: LiveBox, val outgoing: Boolean, val color: Int? = null)

/** Telefon ekranında okunan (okuma.md 9). */
sealed interface PhoneScreen {
    /** Sohbet: başlıkta ad, altında mesajlar. [translatable] çevrilecek mesajların sırası. */
    data class Chat(val title: String, val messages: List<PhoneMessage>, val translatable: List<Int>) : PhoneScreen
    /** Sohbet listesi: çevrilmez. */
    data object ChatList : PhoneScreen
    /** Telefon uygulaması (BuckMe, Ryde, fitness): satır satır. */
    data class App(val name: String, val lines: List<PhoneMessage>) : PhoneScreen
    /** Harita tuşları görüldü: panel kalkar. */
    data object MapScreen : PhoneScreen
    data object Nothing : PhoneScreen
}

/** Telefon yazılarının kuralları (saf). */
object PhoneText {
    const val HEADER = 0.07
    private val BUTTONS = setOf("back", "done", "edit", "cancel", "close", "next", "menu", "select", "ok", "send")
    private val LABELS = listOf("new message", "typing", "delivered", "read", "seen", "today", "yesterday", "sent", "now")
    private val TIME = Regex("^\\d{1,2}[:.]\\d{2}(\\s?[ap]m)?$", RegexOption.IGNORE_CASE)
    /** Telefon uygulamalarına özgü yazılar (altyazıdan da atılır). */
    val APP_WORDS = listOf("buckme", "ryde", "rydeme", "change destination", "book ryde", "steps today", "calories", "workout")
    private val ENTITY = Regex("&[a-z]+;|&#\\d+;", RegexOption.IGNORE_CASE)

    private fun lower(s: String) = s.lowercase().trim()

    fun isButton(s: String) = lower(s).trim { !it.isLetter() } in BUTTONS
    fun isLabel(s: String): Boolean { val l = lower(s).trim { !it.isLetterOrDigit() }; return TIME.matches(l) || LABELS.any { l == it || l.startsWith("$it ") && l.length < it.length + 8 } }
    fun isAppText(s: String): Boolean { val l = lower(s); return APP_WORDS.any { l.contains(it) } }

    /**
     * Telefon uygulamalarının bilinen düğme ve başlıkları; satırın tamamı bunlardan biriyse (fiyat eki "($82)" hariç)
     * oyun bilinmese ve telefon görülmese de altyazı değildir. Yalnız tam eşleşme: içinde geçen cümle atılmaz.
     */
    val APP_LINES = setOf("change destination", "book ryde", "choose ryde", "standard ryde", "trip details", "buckme", "rydeme")
    private val PRICE = Regex("\\(\\s*\\$?\\s*[\\d.,]+\\s*\\)")
    private val NON_WORD = Regex("[^\\p{L}\\p{N}]+")

    fun isExactAppLine(s: String): Boolean {
        val l = NON_WORD.replace(PRICE.replace(lower(s), " "), " ").trim()
        return l in APP_LINES
    }
    fun appName(lines: List<String>): String? = lines.map(::lower).firstNotNullOfOrNull { l ->
        when { l.contains("buckme") -> "BuckMe"; l.contains("ryde") -> "Ryde"; else -> null }
    }

    /** Bir mesajın cümle olup olmadığı. */
    fun isSentence(s: String) = LiveText.tokens(s).size >= 3 || LiveText.endsSentence(s)

    /** Art arda tekrar eden sözcükler teke iner; simgeler ve HTML varlıkları atılır. */
    fun clean(s: String): String {
        val noEntity = ENTITY.replace(s, " ")
        val kept = noEntity.filter { it.isLetterOrDigit() || it.isWhitespace() || it in ".,!?;:'\"-()$%&/" || it == '’' || it == '…' }
        val out = ArrayList<String>()
        for (t in LiveText.tokens(kept)) if (out.isEmpty() || !out.last().equals(t, ignoreCase = true)) out += t
        return out.joinToString(" ")
    }

    /** Benzer mesaj: aynı, biri ötekinin başı ya da sonu, ya da %75 benzer. */
    fun similar(a: String, b: String): Boolean {
        val x = LiveText.key(a); val y = LiveText.key(b)
        if (x == y) return true
        if (x.isNotEmpty() && y.isNotEmpty() && (x.startsWith(y) || y.startsWith(x) || x.endsWith(y) || y.endsWith(x))) return true
        return LiveText.similarity(a, b) >= 0.75
    }

    /**
     * Telefon ekranının okunan satırları (kutular telefona göre) → ekran türü. [colorAt] kutunun ortalama rengi
     * (giden mavi balonu tanımak için); bilinmiyorsa null döner.
     */
    fun parse(lines: List<LiveLine>, colorAt: (LiveBox) -> Int? = { null }): PhoneScreen {
        val ls = lines.filter { it.box != null && it.text.isNotBlank() }.sortedBy { it.box!!.top }
        if (ls.isEmpty()) return PhoneScreen.Nothing
        val texts = ls.map { it.text }
        if (texts.any { lower(it).contains("recenter") }) return PhoneScreen.MapScreen
        // Liste önce: önizlemede "BuckMe" geçen sohbet listesi uygulama sanılmaz.
        if (isList(ls)) return PhoneScreen.ChatList
        appName(texts)?.let { name ->
            return PhoneScreen.App(name, ls.filter { !isLabel(it.text) && !isButton(it.text) }.map { PhoneMessage(clean(it.text), it.box!!, false, colorAt(it.box)) })
        }
        // Başlık: en üstte, ortada (0.12 payla), düğme değil; altında aynı hizada satır yok.
        val head = ls.first()
        val hb = head.box!!
        if (abs(hb.midX - 0.5) > 0.12 || isButton(head.text) || hb.top > 0.20) return PhoneScreen.Nothing
        val next = ls.getOrNull(1)?.box
        if (next != null && abs(next.midX - hb.midX) < 0.03 && next.top - hb.bottom < hb.height * 0.8 && abs(next.width - hb.width) < 0.05) return PhoneScreen.Nothing
        val cut = maxOf(HEADER, hb.bottom) + 0.012
        val body = ls.drop(1).filter { l ->
            val b = l.box!!
            b.top >= cut && b.bottom <= 0.985 && !isLabel(l.text) && !isButton(l.text)
        }
        val messages = group(body, colorAt)
        if (messages.none { isSentence(it.text) }) return PhoneScreen.Nothing
        val translatable = messages.indices.filter { i ->
            val m = messages[i]
            val lastUnfinished = i == messages.lastIndex && m.box.bottom > 0.93 && !LiveText.endsSentence(m.text) && m.box.height > 0.06
            val topCut = i == 0 && m.box.top < cut + 0.02 && m.text.firstOrNull { it.isLetter() }?.isLowerCase() == true
            !lastUnfinished && !topCut
        }
        return PhoneScreen.Chat(clean(head.text), messages, translatable)
    }

    /** Sohbet listesi: en az 3 kez "ad + hemen altında önizleme" ya da en az 2 "…" ile kesilmiş önizleme. */
    fun isList(ls: List<LiveLine>): Boolean {
        val ellipsis = ls.count { it.text.trimEnd().endsWith("…") || it.text.trimEnd().endsWith("...") }
        if (ellipsis >= 2) return true
        var pairs = 0
        for (i in 0 until ls.size - 1) {
            val a = ls[i].box!!; val b = ls[i + 1].box!!
            val name = LiveText.tokens(ls[i].text).size <= 3 && !LiveText.endsSentence(ls[i].text)
            if (name && abs(a.left - b.left) < 0.03 && b.top - a.bottom in -0.005..(a.height * 0.6) && a.left < 0.45) pairs++
        }
        return pairs >= 3
    }

    /** Aynı hizada ve yakın satırlar tek mesaj; gruptaki gönderen adı (tek sözcük, büyük harfle) atılır. */
    fun group(lines: List<LiveLine>, colorAt: (LiveBox) -> Int?): List<PhoneMessage> {
        val groups = ArrayList<ArrayList<LiveLine>>()
        for (l in lines) {
            val g = groups.lastOrNull()
            val p = g?.last()?.box
            val b = l.box!!
            val near = p != null && b.top - p.bottom < 0.6 * maxOf(p.height, b.height) && (abs(b.left - p.left) < 0.03 || abs(b.right - p.right) < 0.03)
            if (near) g!! += l else groups += arrayListOf(l)
        }
        val out = ArrayList<PhoneMessage>()
        for ((i, g) in groups.withIndex()) {
            val only = g.size == 1 && LiveText.tokens(g[0].text).size == 1 && g[0].text.first().isUpperCase() && !LiveText.endsSentence(g[0].text)
            if (only && i + 1 < groups.size) continue // gönderen adı
            val box = g.map { it.box!! }.reduce(LiveBox::union)
            val color = colorAt(box)
            val outgoing = box.left > 0.2 || (color != null && RgbImage.isBlue(color))
            out += PhoneMessage(clean(g.joinToString(" ") { it.text.trim() }), box, outgoing, color)
        }
        return out.filter { it.text.isNotBlank() }
    }
}

/**
 * Paneldeki mesajların değişme kuralları (okuma.md 9): sohbet başlığı değişirse panel hemen kalkar; aynı ya da
 * benzer mesajlar paneli değiştirmez; yeni mesajlar ancak iki okumada görülünce paneli değiştirir; mesajlar
 * 0.02'den fazla kaydıysa panel silinir. Telefon görülmeyince kalkması [PhoneKeeper]'da (ortak histerezis).
 */
class PhonePanel {
    sealed interface Change {
        data object None : Change
        data object Clear : Change
        /** Panel bu mesajlarla gösterilmeli. */
        data class Show(val title: String, val messages: List<PhoneMessage>) : Change
    }

    @Volatile var title: String? = null; private set
    @Volatile var shown: List<PhoneMessage> = emptyList(); private set
    private var candidate: List<PhoneMessage>? = null

    @Synchronized fun onChat(chat: PhoneScreen.Chat, @Suppress("UNUSED_PARAMETER") nowMs: Long): Change {
        val msgs = chat.translatable.map { chat.messages[it] }
        if (title != null && title != chat.title) { reset(); candidate = msgs; title = chat.title; return Change.Clear }
        title = chat.title
        if (shown.isNotEmpty() && sameTexts(shown, msgs)) {
            if (moved(shown, msgs) > 0.02) { shown = emptyList(); candidate = msgs; return Change.Clear }
            return Change.None
        }
        val c = candidate
        candidate = msgs
        if (c != null && sameTexts(c, msgs) && msgs.isNotEmpty()) { shown = msgs; return Change.Show(chat.title, msgs) }
        return Change.None
    }

    @Synchronized fun reset() { title = null; shown = emptyList(); candidate = null }

    private fun sameTexts(a: List<PhoneMessage>, b: List<PhoneMessage>) = a.size == b.size && a.indices.all { PhoneText.similar(a[it].text, b[it].text) }
    private fun moved(a: List<PhoneMessage>, b: List<PhoneMessage>) = a.indices.maxOfOrNull { abs(a[it].box.top - b[it].box.top) } ?: 0.0
}

/**
 * Telefon panelinin TV'deki öğeleri (okuma.md 9). Kalkması bütün ekran öğeleriyle ortak histerezisle
 * ([ScreenItemBoard], bölge = telefonun son bulunduğu ekran dikdörtgeni): telefon bulunamadı ya da ekranı okunamadı
 * ([missed]) art arda 3 okuma + en az 4 sn + bölge görüntüsel değişti olunca kalkar; tek kaçırılan okuma silmez.
 * Hemen kaldıranlar ([drop] ya da [onChat]): sohbet başlığı değişti, mesajlar kaydı, sohbet listesine dönüldü, harita
 * ya da menü açıldı. Uygulama ekranının (BuckMe, Ryde) satırları da aynı türdendir.
 */
class PhoneKeeper(val board: ScreenItemBoard = ScreenItemBoard()) {
    sealed interface Step {
        data object None : Step
        /** Panel hemen kalktı (liste yeniden gönderilmeli). */
        data object Cleared : Step
        /** Bu mesajlar çevrilip [show] ile gösterilmeli. */
        data class Show(val title: String, val messages: List<PhoneMessage>) : Step
    }

    val panel = PhonePanel()
    val motion = PhoneMotion()
    private val kind = ScreenItemBoard.Kind.PHONE

    /** TV'de telefon öğesi var. */
    val showing: Boolean get() = board.items(kind).isNotEmpty()

    /** Telefonun son görüldüğü ekran dikdörtgeni (öğe tutuluyorsa). */
    val area: LiveBox? get() = board.area(kind)

    /** Sohbet okundu. [phone]: telefonun ekranı (kare), [trace]: onun şimdiki izi. */
    fun onChat(chat: PhoneScreen.Chat, phone: LiveBox, trace: RegionTrace?, nowMs: Long): Step = when (val ch = panel.onChat(chat, nowMs)) {
        PhonePanel.Change.Clear -> { board.drop(kind); Step.Cleared }
        PhonePanel.Change.None -> {
            if (showing) board.seen(kind, phone, trace)
            if (showing && !motion.panelStays) Step.Show(panel.title ?: "", panel.shown) else Step.None
        }
        is PhonePanel.Change.Show -> Step.Show(ch.title, ch.messages)
    }

    /** Telefonun öğeleri (sohbet paneli ya da uygulama satırları); boşsa panel kalkar. */
    fun show(phone: LiveBox, trace: RegionTrace?, items: List<Map<String, Any?>>) {
        if (items.isEmpty()) board.drop(kind) else board.seen(kind, phone, trace, items)
    }

    /** Telefon bulunamadı ya da ekranı okunamadı ([trace]: [area] bölgesinin şimdiki izi). true: panel kalktı. */
    fun missed(trace: RegionTrace?, nowMs: Long): Boolean {
        if (!board.missing(kind, trace, nowMs)) return false
        panel.reset(); motion.reset()
        return true
    }

    /** Hemen kalkar (sohbet listesi, harita, menü, Ekranı çevir). true: bir şey vardı. */
    fun drop(): Boolean {
        panel.reset(); motion.reset()
        return board.drop(kind)
    }
}

/**
 * Telefon elde sallanınca (okuma.md 9): yer en sık 150 ms'de bir bulunur; kayma 0.08'den küçük ve yatayda 0.009,
 * dikeyde 0.012'den büyükse ve aynı yönde iki ölçüm geldiyse balonlar kaydırılır. 0.05'ten az kayınca panel yerinde.
 */
class PhoneMotion {
    private var anchor: LiveBox? = null
    private var lastDir: Pair<Int, Int>? = null
    var offsetX = 0.0; private set
    var offsetY = 0.0; private set

    fun onPhone(box: LiveBox) {
        val a = anchor ?: run { anchor = box; return }
        val dx = box.left - a.left; val dy = box.top - a.top
        if (abs(dx) >= 0.08 || abs(dy) >= 0.08) { anchor = box; offsetX = 0.0; offsetY = 0.0; lastDir = null; return }
        val dir = (if (abs(dx) > 0.009) sign(dx) else 0) to (if (abs(dy) > 0.012) sign(dy) else 0)
        if (dir == 0 to 0) { lastDir = null; return }
        if (dir == lastDir) { offsetX = dx; offsetY = dy }
        lastDir = dir
    }

    /** Panel yerinde kalsın mı (telefon 0.05'ten az kaydı). */
    val panelStays: Boolean get() = abs(offsetX) < 0.05 && abs(offsetY) < 0.05

    fun reset() { anchor = null; lastDir = null; offsetX = 0.0; offsetY = 0.0 }
    private fun sign(d: Double) = if (d > 0) 1 else -1
}

/** Telefon çevirilerinin TV öğeleri (tv.md `screen`, `overlay`). Kutular kareye göre. */
object PhoneLayout {
    const val PANEL_W = 0.27
    const val PANEL_GAP = 0.035

    /** Telefona göre kutuyu kareye çevirir. */
    fun toFrame(phone: LiveBox, b: LiveBox) = LiveBox(
        phone.left + b.left * phone.width, phone.top + b.top * phone.height,
        phone.left + b.right * phone.width, phone.top + b.bottom * phone.height,
    )

    /**
     * Sohbet paneli: telefonun boş yanında dikey panel (genişlik 0.27, uzaklık 0.035); gelenler solda, gidenler
     * sağda; balonlar mesaj renginde, saydamlık 0.95; zemin 0.6; üstte gönderenin adı.
     */
    fun chat(phone: LiveBox, title: String, messages: List<Pair<PhoneMessage, String>>, dx: Double = 0.0, dy: Double = 0.0): List<Map<String, Any?>> {
        if (messages.isEmpty()) return emptyList()
        val right = phone.midX < 0.5
        val left = if (right) phone.right + PANEL_GAP else phone.left - PANEL_GAP - PANEL_W
        val pl = left.coerceIn(0.0, 1.0 - PANEL_W) + dx
        val top = (phone.top + dy).coerceIn(0.0, 0.9)
        val bottom = (phone.bottom + dy).coerceIn(top + 0.1, 1.0)
        val items = ArrayList<Map<String, Any?>>()
        items += linkedMapOf("text" to "", "box" to ScreenPlan.box(LiveBox(pl, top, pl + PANEL_W, bottom)), "backdrop" to true, "alpha" to 0.6)
        val titleH = 0.045
        items += linkedMapOf("text" to title, "box" to ScreenPlan.box(LiveBox(pl + 0.01, top + 0.01, pl + PANEL_W - 0.01, top + 0.01 + titleH)), "plain" to true, "line" to 0.03)
        // Balonlar alttan yukarı dizilir (en yeni altta); sığmayan eskiler atılır.
        val lineH = 0.028
        var y = bottom - 0.01
        val bubbles = ArrayList<Map<String, Any?>>()
        for ((m, tr) in messages.asReversed()) {
            val chars = tr.length
            val perLine = 26
            val rows = (chars + perLine - 1) / perLine
            val h = rows.coerceAtLeast(1) * lineH + 0.016
            val top0 = y - h
            if (top0 < top + 0.02 + titleH) break
            val w = (minOf(chars, perLine) / perLine.toDouble() * (PANEL_W - 0.04)).coerceIn(0.08, PANEL_W - 0.04)
            val bl = if (m.outgoing) pl + PANEL_W - 0.01 - w else pl + 0.01
            val fill = m.color ?: if (m.outgoing) 0x2f7cf6 else 0xe9e9eb
            val ink = if (m.color?.let(::lum)?.let { it < 140 } ?: m.outgoing) 0xffffff else 0x111111
            bubbles += linkedMapOf("text" to tr, "box" to ScreenPlan.box(LiveBox(bl, top0, bl + w, y)), "line" to lineH,
                "fill" to RgbImage.hex(fill), "ink" to RgbImage.hex(ink), "alpha" to 0.95, "side" to true)
            y = top0 - 0.008
        }
        return items + bubbles.asReversed()
    }

    /** Uygulama (BuckMe, Ryde): her satırın çevirisi uygulamanın renginde, satırın hizasında. */
    fun app(phone: LiveBox, lines: List<Pair<PhoneMessage, String>>): List<Map<String, Any?>> = lines.map { (m, tr) ->
        val b = toFrame(phone, m.box)
        val fill = m.color ?: 0xffffff
        linkedMapOf("text" to tr, "box" to ScreenPlan.box(b), "line" to b.height, "fill" to RgbImage.hex(fill),
            "ink" to RgbImage.hex(if (lum(fill) < 140) 0xffffff else 0x111111), "alpha" to 0.95)
    }

    private fun lum(rgb: Int) = (((rgb shr 16) and 0xFF) * 299 + ((rgb shr 8) and 0xFF) * 587 + (rgb and 0xFF) * 114) / 1000
}
