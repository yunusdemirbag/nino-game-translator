// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.service

import com.ninotranslator.core.packs.PackKey
import com.ninotranslator.core.pool.PoolLineFilter
import com.ninotranslator.core.pool.SharedPool
import com.ninotranslator.core.reading.live.FrameTrace
import com.ninotranslator.core.reading.live.Gta6Hints
import com.ninotranslator.core.reading.live.Gta6SubtitleRules
import com.ninotranslator.core.reading.live.LiveBox
import com.ninotranslator.core.reading.live.LiveClock
import com.ninotranslator.core.reading.live.LiveRegion
import com.ninotranslator.core.reading.live.LumaPlane
import com.ninotranslator.core.reading.live.MapCardKeeper
import com.ninotranslator.core.reading.live.MapCardText
import com.ninotranslator.core.reading.live.MapCards
import com.ninotranslator.core.reading.live.MapState
import com.ninotranslator.core.reading.live.PhoneFixedTurkish
import com.ninotranslator.core.reading.live.PhoneLayout
import com.ninotranslator.core.reading.live.PhoneKeeper
import com.ninotranslator.core.reading.live.PhoneLocator
import com.ninotranslator.core.reading.live.PhoneMessage
import com.ninotranslator.core.reading.live.PhoneMessageMemory
import com.ninotranslator.core.reading.live.PhoneRect
import com.ninotranslator.core.reading.live.PhoneScreen
import com.ninotranslator.core.reading.live.PhoneText
import com.ninotranslator.core.reading.live.RgbImage
import com.ninotranslator.core.reading.live.ScreenItemBoard
import com.ninotranslator.core.translation.TargetLanguage
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import kotlinx.coroutines.withTimeoutOrNull
import java.io.File
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean

/**
 * GTA 6 oyun içi telefon ve harita kartı (okuma.md 9–10, servis.md 3.6). Yalnız [active] iken (havuz öncelikli oyun
 * ya da oyun henüz bilinmiyorken havuz dilinde) ve "Ekranı çevir" sonuçları ekranda değilken çalışır. Çeviriler TV'ye
 * tek liste olarak, altyazıyı silmeden 120 sn süreli katman olarak gider ([ScreenChannel]). Telefon paneli ve harita
 * kartının kalkması ortak histerezisle ([ScreenItemBoard]): 3 kaçırılan okuma + 4 sn + bölge görüntüsel değişimi.
 */
class GtaReader(
    private val scope: CoroutineScope,
    private val clock: LiveClock,
    private val reader: SharedReader,
    private val channel: ScreenChannel,
    private val pool: SharedPool?,
    private val target: TargetLanguage,
    filesDir: File,
    private val active: () -> Boolean,
    /** Oyun GTA 6 olarak biliniyor (havuz öncelikli): "her zaman atılan" satır kuralları ve havuza zorla sorma. */
    private val poolFirst: () -> Boolean,
    private val blocked: () -> Boolean,
    private val game: () -> String?,
    private val sharePool: () -> Boolean,
    /** Cihaz çevirmeni (her mesaj en çok 60 sn). */
    private val deviceTranslate: suspend (String) -> String?,
    /** Telefon ya da GTA 6'ya özgü yazı görüldü: oyun GTA 6 sayılır. */
    private val onGta6Seen: () -> Unit,
    /** Altyazı kuralları değişti (telefon yeri): okuma döngüsü ayarı yenilensin. */
    private val onRulesChanged: () -> Unit,
) {
    val rules = Gta6SubtitleRules()
    val mapState = MapState()
    private val locator = PhoneLocator()
    /** Bütün ekran öğeleri (telefon, harita kartı) ve kalkma histerezisleri. */
    private val board = ScreenItemBoard()
    private val phoneKeeper = PhoneKeeper(board)
    private val panel get() = phoneKeeper.panel
    private val motion get() = phoneKeeper.motion
    private val memory = PhoneMessageMemory(File(filesDir, PhoneMessageMemory.DIR), target.code)
    private val session = ConcurrentHashMap<String, String>()
    private val cards = MapCardKeeper(board = board)
    private val deviceSlots = Semaphore(2)

    private val phoneBusy = AtomicBoolean(false)
    private val mapBusy = AtomicBoolean(false)
    @Volatile private var lastLocateAt = Long.MIN_VALUE / 2
    @Volatile private var lastPhoneReadAt = Long.MIN_VALUE / 2
    @Volatile private var lastMapAt = Long.MIN_VALUE / 2
    @Volatile private var phone: PhoneRect? = null
    @Volatile private var lastRgb: RgbImage? = null
    @Volatile private var lastBlackout: LiveBox? = null
    @Volatile private var stopped = false

    /** Okuma döngüsünün GTA 6 satır süzgeci (kutu kareye göre). */
    val dropLine: (String, LiveBox?) -> Boolean = { text, box -> active() && rules.drop(text, box, clock.nowMs(), darkOnLight(box), gta6 = poolFirst()) }

    /** Okumadan önce siyaha boyanacak telefon kısmı. */
    fun blackout(): List<LiveBox> = if (active()) listOfNotNull(rules.blackout(clock.nowMs())) else emptyList()

    /** Altyazı okunmasın mı (harita açık). */
    fun subtitlesSuppressed(): Boolean = active() && mapState.mapOpen(clock.nowMs())

    fun offer(frame: VideoFrame) {
        if (stopped) return
        if (!active() || blocked()) {
            if (!board.isEmpty() || phoneKeeper.area != null || cards.hold.showing) { phoneKeeper.drop(); board.reset(); publish() }
            return
        }
        val now = clock.nowMs()
        offerMap(frame, now)
        val c = frame.chroma ?: return // renk yoksa telefon aranmaz
        // Harita ya da menü açık: telefon paneli hemen kalkar.
        if (mapState.phoneBlocked(now)) { if (phoneKeeper.drop()) publish(); return }
        if (now - lastLocateAt < LOCATE_MS) return
        lastLocateAt = now
        val rgb = RgbImage.fromYuv(frame.luma, frame.stride, frame.width, frame.height, c.u, c.v, c.rowStride, c.pixelStride)
        lastRgb = rgb
        val p = locator.locate(rgb, now)
        phone = p
        rules.onPhone(p?.box, now)
        val bo = rules.blackout(now)
        if (bo != lastBlackout) { lastBlackout = bo; onRulesChanged() }
        if (p == null) { phoneMissing(frame, now); return }
        motion.onPhone(p.box)
        val interval = if (panel.shown.isEmpty()) READ_EMPTY_MS else READ_SHOWN_MS
        if (now - lastPhoneReadAt < interval || !phoneBusy.compareAndSet(false, true)) return
        lastPhoneReadAt = now
        val crop = frame.copyRegion(LiveRegion(p.box.top, p.box.bottom, p.box.left, p.box.right))
        if (crop == null) { phoneBusy.set(false); return }
        scope.launch { try { readPhone(p, crop, rgb, now) } finally { phoneBusy.set(false) } }
    }

    /**
     * Telefon bu karede bulunamadı: tutulan panel varsa okuma sıklığında bir kaçırma sayılır; iz telefonun son
     * dikdörtgeninden alınır (kare yalnız bu çağrıda geçerli).
     */
    private fun phoneMissing(frame: VideoFrame, now: Long) {
        val area = phoneKeeper.area ?: return
        if (now - lastPhoneReadAt < READ_SHOWN_MS) return
        lastPhoneReadAt = now
        val trace = frame.copyRegion(LiveRegion(area.top, area.bottom, area.left, area.right))?.let { FrameTrace.grid(it) }
        if (phoneKeeper.missed(trace, now)) publish()
    }

    private suspend fun readPhone(p: PhoneRect, crop: LumaPlane, rgb: RgbImage, now: Long) {
        val lines = reader.read(crop) ?: return
        val trace = FrameTrace.grid(crop)
        val screen = PhoneText.parse(lines) { b -> rgb.bubble(PhoneLayout.toFrame(p.box, b)) }
        // Yalnız gerçekten telefon ekranı okunduysa oyun GTA 6 sayılır (beyaz bir dikdörtgen yetmez).
        if (screen is PhoneScreen.Chat || screen is PhoneScreen.ChatList || screen is PhoneScreen.App) onGta6Seen()
        when (screen) {
            // Harita ekranı ya da sohbet listesi (ekran türü değişti): panel hemen kalkar.
            PhoneScreen.MapScreen -> { mapState.onMapSeen(now); phoneKeeper.drop(); publish() }
            PhoneScreen.ChatList -> if (phoneKeeper.drop()) publish()
            // Okunamadı: kaçırma (ortak histerezis), tek kaçırılan okuma silmez.
            PhoneScreen.Nothing -> if (phoneKeeper.missed(trace, now)) publish()
            is PhoneScreen.App -> {
                val tr = translateAll(screen.lines.map { it.text })
                rules.onMessages(screen.lines.map { it.text }, now)
                phoneKeeper.show(p.box, trace, PhoneLayout.app(p.box, screen.lines.zip(tr).mapNotNull { (m, t) -> t?.let { m to it } }))
                publish()
            }
            is PhoneScreen.Chat -> {
                rules.onMessages(screen.messages.map { it.text }, now)
                when (val step = phoneKeeper.onChat(screen, p.box, trace, now)) {
                    PhoneKeeper.Step.None -> Unit
                    PhoneKeeper.Step.Cleared -> publish()
                    is PhoneKeeper.Step.Show -> showChat(p, trace, step.title, step.messages)
                }
            }
        }
    }

    private suspend fun showChat(p: PhoneRect, trace: com.ninotranslator.core.reading.live.RegionTrace, title: String, msgs: List<PhoneMessage>) {
        val tr = translateAll(msgs.map { it.text })
        val pairs = msgs.zip(tr).mapNotNull { (m, t) -> t?.let { m to it } }
        phoneKeeper.show(p.box, trace, PhoneLayout.chat(p.box, title, pairs, motion.offsetX, motion.offsetY))
        publish()
    }

    /**
     * Mesaj çevirisi sırası: sabit sözlük (Türkçe) → havuz → kalıcı hafıza → oturum hafızası → havuz sunucusu (bilinmeyenler
     * tek istekte, ilk bilinmeyenden önceki 4 mesaj bağlam) → cihaz çevirmeni (aynı anda en çok 2, her biri 60 sn).
     */
    private suspend fun translateAll(texts: List<String>): List<String?> {
        val out = arrayOfNulls<String>(texts.size)
        val g = game()
        for ((i, t) in texts.withIndex()) out[i] = known(t)
        val unknown = texts.indices.filter { out[it] == null }
        if (unknown.isEmpty()) return out.toList()
        if (target.isTurkish && sharePool()) unknown.forEach { pool?.offer(texts[it], g) }
        val p = pool
        if (p != null) {
            val first = unknown.first()
            val ctx = texts.subList(maxOf(0, first - 4), first)
            val answers = runCatching { p.askMany(unknown.map { texts[it] }, target.code, g, ctx, force = poolFirst()) }.getOrNull()
            answers?.forEachIndexed { j, a -> if (!a.isNullOrBlank()) { out[unknown[j]] = a; remember(texts[unknown[j]], a) } }
        }
        val rest = unknown.filter { out[it] == null }
        rest.map { i ->
            scope.async {
                deviceSlots.withPermit {
                    withTimeoutOrNull(DEVICE_MS) { runCatching { deviceTranslate(texts[i]) }.getOrNull() }
                }?.let { out[i] = it; remember(texts[i], it) }
            }
        }.awaitAll()
        return out.toList()
    }

    private fun known(t: String): String? {
        if (target.isTurkish) PhoneFixedTurkish.get(t)?.let { return it }
        PackKey.of(PoolLineFilter.clean(t))?.let { k -> pool?.lookup(target.code, k)?.let { return it } }
        memory.get(t)?.let { return it }
        return session[t]
    }

    private fun remember(t: String, tr: String) { session[t] = tr; memory.put(t, tr) }

    // ---- harita kartı ----

    private fun offerMap(frame: VideoFrame, now: Long) {
        if (now - lastMapAt < mapState.cardIntervalMs(now) || !mapBusy.compareAndSet(false, true)) return
        lastMapAt = now
        val crop = frame.copyRegion(MapCards.READ_REGION)
        if (crop == null) { mapBusy.set(false); return }
        scope.launch { try { readMap(crop, now) } finally { mapBusy.set(false) } }
    }

    private suspend fun readMap(crop: LumaPlane, now: Long) {
        val lines = reader.read(crop) ?: return
        val r = MapCards.READ_REGION
        val all = lines.map { it.copy(box = it.box?.let(r::toFrame)) }
        val texts = all.map { it.text }
        // Açık telefonun içindeki yazı harita kartı değildir.
        val frameLines = all.filterNot { l -> l.box?.let { rules.insidePhone(it, clock.nowMs()) } == true }
        if (Gta6Hints.looksLikeGta6(texts)) onGta6Seen()
        if (Gta6Hints.isMapScreen(texts)) mapState.onMapSeen(now)
        val card = MapCards.find(frameLines)
        if (card == null) {
            // Kalkma histerezisi: tek kaçırılan okuma kartı silmez; görüntü değişmeden kart durur.
            if (cards.missing(crop, r, now)) publish()
            return
        }
        val tr = cards.seen(card, crop, r, ::translateCard) ?: return
        val (frameTop, frameBottom) = MapCards.frame(crop, r, card.box)
        val (box, lh) = MapCards.place(card.box, card.sentences.size + if (card.title != null) 1 else 0, frameTop, frameBottom)
        board.show(ScreenItemBoard.Kind.MAP, listOf(MapCards.item(box, lh, tr)))
        publish()
    }

    private suspend fun translateCard(c: MapCardText): String? {
        val title = c.title
        val parts = listOfNotNull(title?.takeIf { !MapCards.isPlaceName(it) }) + c.sentences
        val got = translateAll(parts)
        if (got.any { it == null }) return null
        var i = 0
        val titleOut = title?.let { t -> if (MapCards.isPlaceName(t)) t else MapCards.upper(got[i++]!!, target.code) }
        val body = got.drop(i).joinToString(" ") { MapCards.fix(it!!) }
        return listOfNotNull(titleOut, body).joinToString("\n")
    }

    private fun publish() {
        val list = board.list()
        channel.setOverlay(list)
        LiveStatus.update { val on = list.isNotEmpty(); if (it.gameOverlayActive == on) it else it.copy(gameOverlayActive = on) }
    }

    /** Açık zeminde koyu yazı (mesaj balonu): yalnız telefon açıkken bakılır. */
    private fun darkOnLight(box: LiveBox?): Boolean {
        if (box == null || !rules.phoneActive(clock.nowMs())) return false
        val avg = lastRgb?.average(box) ?: return false
        val l = (((avg shr 16) and 0xFF) * 299 + ((avg shr 8) and 0xFF) * 587 + (avg and 0xFF) * 114) / 1000
        return l >= 170
    }

    fun stop() {
        stopped = true
        phoneKeeper.drop(); board.reset()
        channel.setOverlay(emptyList())
    }

    companion object {
        const val LOCATE_MS = 150L
        const val READ_EMPTY_MS = 600L
        const val READ_SHOWN_MS = 1_000L
        const val DEVICE_MS = 60_000L
    }
}
