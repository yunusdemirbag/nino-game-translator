// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.reading.live

import java.util.Locale
import kotlin.math.abs

/** Harita kartı (okuma.md 10; yalnız GTA 6). Kutular kareye göre (0–1). */
data class MapCardText(val title: String?, val sentences: List<String>, val box: LiveBox) {
    /** Kart hafızası anahtarı. */
    val key: String get() = LiveText.key((listOfNotNull(title) + sentences).joinToString(" "))
}

object MapCards {
    /** Okunan kısım: karenin üst 0.03'ünden alt 0.95'ine. */
    val READ_REGION = LiveRegion(0.03, 0.95, 0.0, 1.0)
    const val NORMAL_INTERVAL_MS = 2_000L
    const val MAP_INTERVAL_MS = 1_500L
    const val MAP_FAST_AFTER_MS = 10_000L
    const val MEMORY = 200

    private val DISTANCE = Regex("\\b\\d+(?:[.,]\\d+)?\\s?(?:km|mi|m|ft|yd)\\b", RegexOption.IGNORE_CASE)
    private val PLACE = listOf("customs", "store", "shop", "bar", "club", "motel", "hotel", "diner", "garage", "ammu", "station",
        "market", "liquor", "pawn", "salon", "tattoo", "barber", "bank", "casino", "restaurant", "cafe", "gym", "dealership",
        "autos", "motors", "pharmacy", "clinic", "hospital", "boutique", "mart", "burger", "pizza", "taco")
    private val FIXES = listOf("işaretli fatura" to "işaretli banknot", "narkotik" to "uyuşturucu", "Narkotik" to "Uyuşturucu")

    /** Uzaklık etiketleri ve baştaki simgeler temizlenir. */
    fun cleanLine(s: String): String = DISTANCE.replace(s, " ").trimStart { !it.isLetterOrDigit() && it != '"' && it != '\'' }
        .replace(Regex("\\s+"), " ").trim()

    private fun isSentence(s: String) = LiveText.tokens(s).size >= 3 && s.count { it.isLowerCase() } >= 6
    private fun isUpperTitle(s: String) = s.any { it.isLetter() } && s.filter { it.isLetter() }.all { it.isUpperCase() }

    /** Kartı bulur; gösterilmeyecekse null. */
    fun find(lines: List<LiveLine>): MapCardText? {
        val ls = lines.filter { it.box != null && it.box.left >= 0.30 }
            .map { it.copy(text = cleanLine(it.text)) }.filter { it.text.isNotEmpty() }.sortedBy { it.box!!.top }
        val startIdx = ls.indexOfFirst { isSentence(it.text) }
        if (startIdx < 0) return null
        val first = ls[startIdx]
        val fb = first.box!!
        val body = arrayListOf(first)
        for (l in ls.drop(startIdx + 1)) {
            val p = body.last().box!!; val b = l.box!!
            if (b.top - p.bottom > 1.2 * p.height || kotlin.math.abs(b.left - fb.left) > 0.03 || !isSentence(l.text) && l.text.count { it.isLowerCase() } < 3) break
            body += l
        }
        val above = ls.getOrNull(startIdx - 1)?.takeIf { a ->
            val b = a.box!!
            isUpperTitle(a.text) && fb.top - b.bottom < 1.5 * fb.height && kotlin.math.abs(b.left - fb.left) < 0.05
        }
        val box = (listOfNotNull(above) + body).map { it.box!! }.reduce(LiveBox::union)
        val sentences = body.map { it.text }
        val card = MapCardText(above?.text, sentences, box)
        return card.takeIf { shows(it) }
    }

    /** Gösterilmeyen kartlar: Türkçe harf (PS5 bildirimi); başlıksız ve 6 sözcükten kısa; başlıksız sağ üstte; üstü 0.1'den yukarıda. */
    fun shows(c: MapCardText): Boolean {
        val all = (listOfNotNull(c.title) + c.sentences).joinToString(" ")
        if (LiveText.hasTurkishLetters(all)) return false
        if (c.title == null && LiveText.tokens(c.sentences.joinToString(" ")).size < 6) return false
        if (c.title == null && c.box.left > 0.6 && c.box.top < 0.32) return false
        if (c.box.top < 0.1) return false
        return true
    }

    /** Dükkân ya da mekân adı olan başlık çevrilmez. */
    fun isPlaceName(title: String): Boolean { val l = title.lowercase(); return PLACE.any { Regex("\\b$it\\b").containsMatchIn(l) } }

    /** Başlık hedef dilin büyük harfiyle. */
    fun upper(title: String, languageCode: String): String = title.uppercase(Locale.forLanguageTag(languageCode))

    /** Bilinen yanlış çeviriler düzeltilir. */
    fun fix(text: String): String = FIXES.fold(text) { t, (a, b) -> t.replace(a, b) }

    /**
     * Türkçenin yeri: kartın çerçevesinin hemen altı, yer yoksa üstü; o da yetmezse yazı küçülür.
     * [frameBottom]/[frameTop] çerçeve (parlaklığı 130'dan düşük kenar) biliniyorsa.
     */
    fun place(card: LiveBox, lines: Int, frameTop: Double? = null, frameBottom: Double? = null): Pair<LiveBox, Double> {
        val lineH = (card.height / maxOf(1, lines)).coerceIn(0.02, 0.05)
        val need = lineH * (lines + 1)
        val below = (frameBottom ?: card.bottom) + 0.008
        val above = (frameTop ?: card.top) - 0.008
        return when {
            below + need <= 0.98 -> LiveBox(card.left, below, card.right, below + need) to lineH
            above - need >= 0.02 -> LiveBox(card.left, above - need, card.right, above) to lineH
            else -> {
                val space = maxOf(0.98 - below, above - 0.02)
                val small = (space / (lines + 1)).coerceAtLeast(0.012)
                (if (0.98 - below >= above - 0.02) LiveBox(card.left, below, card.right, 0.98) else LiveBox(card.left, 0.02, card.right, above)) to small
            }
        }
    }

    /**
     * Kartın koyu çerçevesi (parlaklığı 130'dan düşük noktalar): yazıların kutusundan aşağı ve yukarı, satırın en az
     * %60'ı koyu kaldıkça ilerlenir. [crop] [region] bölgesinin gri kopyası; [card] kareye göre. Sonuç kareye göre
     * (üst, alt); yazının hemen altı ya da üstü koyu değilse o yan null.
     */
    fun frame(crop: LumaPlane, region: LiveRegion, card: LiveBox): Pair<Double?, Double?> {
        val b = region.fromFrame(card)
        val x0 = (b.left * crop.width).toInt().coerceIn(0, crop.width - 1); val x1 = (b.right * crop.width).toInt().coerceIn(x0, crop.width - 1)
        fun median(y: Int): Int { val v = (x0..x1 step 2).map { crop.at(it, y) }.sorted(); return v[v.size / 2] }
        // Kartın zemini düzdür: koyu kalan ve zeminin parlaklığından (başlangıç satırının ortancası) en çok 20 ayrılan
        // satırlar karttır. Kartın altındaki koyu ama farklı sahne (işaretçi görünümü) çerçeveye katılmaz.
        var ref = 0
        fun dark(y: Int): Boolean {
            var n = 0; var d = 0
            var x = x0
            while (x <= x1) { n++; val l = crop.at(x, y); if (l < FRAME_DARK && abs(l - ref) <= FRAME_SAME) d++; x += 2 }
            return n > 0 && d >= n * 0.6
        }
        fun walk(start: Int, step: Int): Int? {
            var y = start
            if (y !in 0 until crop.height) return null
            ref = median(y)
            if (!dark(y)) return null
            while (y + step in 0 until crop.height && dark(y + step)) y += step
            return y
        }
        val top = walk((b.top * crop.height).toInt() - 2, -1)?.let { region.top + it.toDouble() / crop.height * region.height }
        val bottom = walk((b.bottom * crop.height).toInt() + 2, 1)?.let { region.top + (it + 1).toDouble() / crop.height * region.height }
        return top to bottom
    }

    const val FRAME_DARK = 130
    private const val FRAME_SAME = 20

    fun item(box: LiveBox, lineHeight: Double, text: String): Map<String, Any?> =
        linkedMapOf("text" to text, "box" to ScreenPlan.box(box), "line" to lineHeight, "card" to true, "paragraphs" to true)
}

/** Kart hafızası: en çok 200; aynı kartın yarım okuması tam okumanın yerine geçmez. */
class MapCardMemory(private val max: Int = MapCards.MEMORY) {
    private val map = LinkedHashMap<String, String>()

    @Synchronized fun get(c: MapCardText): String? = map[c.key] ?: map.entries.firstOrNull { (k, _) -> k.startsWith(c.key) && c.key.length >= 12 }?.value

    @Synchronized fun put(c: MapCardText, translation: String) {
        // Yarım okuma (daha kısa anahtar) tam okumanın üstüne yazılmaz.
        if (map.keys.any { it != c.key && it.startsWith(c.key) }) return
        map.remove(c.key); map[c.key] = translation
        while (map.size > max) map.remove(map.keys.first())
    }
}

/**
 * Harita ve telefon zamanlaması (okuma.md 9–10): harita ekranı görüldükten sonra 5 sn açık sayılır (altyazı
 * okunmaz); harita açıkken ve kapandıktan sonra 8 sn telefon aranmaz; harita kartı açıkken ve kapandıktan 10 sn
 * sonrasına kadar 1.5 sn'de, yoksa 2 sn'de bir okunur.
 */
class MapState {
    private var seenAt = Long.MIN_VALUE / 2

    fun onMapSeen(nowMs: Long) { seenAt = nowMs }
    fun mapOpen(nowMs: Long) = nowMs - seenAt <= OPEN_MS
    fun phoneBlocked(nowMs: Long) = nowMs - seenAt <= OPEN_MS + PHONE_AFTER_MS
    fun cardIntervalMs(nowMs: Long) = if (nowMs - seenAt <= OPEN_MS + MapCards.MAP_FAST_AFTER_MS) MapCards.MAP_INTERVAL_MS else MapCards.NORMAL_INTERVAL_MS

    companion object {
        const val OPEN_MS = 5_000L
        const val PHONE_AFTER_MS = 8_000L
    }
}

/**
 * GTA 6'da altyazıdan atılanlar (okuma.md 9). Kutular kareye göre. Telefon açıkken ya da son 5 sn içinde
 * görüldüyse telefonun içindeki ve 0.8 çizgisinin üstündeki satırlar ve telefonda son 30 sn'de görülen mesajların
 * 3+ sözcüklü parçaları; yalnız oyun GTA 6 olarak biliniyorsa ([gta6]) her zaman sağ alt mesaj kartı, ortadan uzak
 * satırlar, açık zeminde koyu yazı ve telefon uygulaması yazıları. Birden çok iş parçacığından çağrılır.
 */
class Gta6SubtitleRules {
    private var phone: LiveBox? = null
    private var phoneAt = Long.MIN_VALUE / 2
    private val recent = ArrayDeque<Pair<String, Long>>()

    @Synchronized fun onPhone(box: LiveBox?, nowMs: Long) { if (box != null) { phone = box; phoneAt = nowMs } }

    @Synchronized fun onMessages(texts: List<String>, nowMs: Long) {
        for (t in texts) recent.addLast(LiveText.key(t) to nowMs)
        while (recent.size > 200) recent.removeFirst()
    }

    @Synchronized fun phoneActive(nowMs: Long) = phone != null && nowMs - phoneAt <= PHONE_RECENT_MS

    /**
     * Satır açık telefonun içinde mi (0.02 payla, alt kenar boyamadaki gibi uzatılmış); harita kartı telefon
     * yazısından çıkarılmaz.
     */
    @Synchronized fun insidePhone(box: LiveBox, nowMs: Long): Boolean {
        val p = blackout(nowMs) ?: return false
        return box.left >= p.left - 0.02 && box.right <= p.right + 0.02 && box.top >= p.top - 0.02 && box.bottom <= p.bottom + 0.02
    }

    /** Telefonun altyazı bölgesine giren kısmı (okumadan önce siyaha boyanır): alt kenar en çok 0.15 uzar, 0.84'ün altına inmez. */
    @Synchronized fun blackout(nowMs: Long): LiveBox? {
        val p = phone?.takeIf { phoneActive(nowMs) } ?: return null
        return p.copy(bottom = maxOf(p.bottom, minOf(p.bottom + 0.15, 0.84).coerceAtLeast(p.bottom)))
    }

    /** true: satır altyazı değil. [darkOnLight] açık zeminde koyu yazı (mesaj balonu). */
    @Synchronized fun drop(text: String, box: LiveBox?, nowMs: Long, darkOnLight: Boolean = false, gta6: Boolean = true): Boolean {
        // Bilinen uygulama satırı (tam eşleşme) oyun bilinmese ve telefon görülmese de atılır.
        if (PhoneText.isExactAppLine(text)) return true
        if (gta6 && (PhoneText.isAppText(text) || darkOnLight)) return true
        if (box != null) {
            if (gta6 && box.left >= 0.66 && box.top >= 0.74) return true
            if (gta6 && kotlin.math.abs(box.midX - 0.5) > 0.12) return true
            val p = phone
            if (p != null && phoneActive(nowMs)) {
                if (box.left >= p.left - 0.02 && box.right <= p.right + 0.02 && box.top >= p.top - 0.02 && box.bottom <= p.bottom + 0.02) return true
                if (box.top < 0.8) return true
            }
        }
        if (LiveText.tokens(text).size >= 3) {
            val k = LiveText.key(text)
            while (recent.isNotEmpty() && nowMs - recent.first().second > MESSAGE_MS) recent.removeFirst()
            if (k.isNotEmpty() && recent.any { it.first.contains(k) }) return true
        }
        return false
    }

    companion object {
        const val PHONE_RECENT_MS = 5_000L
        const val MESSAGE_MS = 30_000L
    }
}
