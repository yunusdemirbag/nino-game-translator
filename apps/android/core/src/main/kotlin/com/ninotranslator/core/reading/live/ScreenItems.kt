// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.reading.live

/**
 * Oyun içi ekran öğelerinin (harita kartı, telefon paneli) TV'ye gönderimi: liste değişince hemen gider; değişmeden
 * ekranda durdukça aynı liste [REFRESH_MS]'de bir yeniden gönderilir (TV'deki [DURATION_MS] sayacı sıfırlansın);
 * liste boşalınca `screen-clear`. Elle "Ekranı çevir" kanalı alınca [pause], bırakınca [resume]. Zaman ms.
 */
class ScreenRefresh(private val refreshMs: Long = REFRESH_MS) {
    sealed interface Action {
        data object None : Action
        data object Clear : Action
        data class Send(val items: List<Map<String, Any?>>, val durationMs: Int = DURATION_MS) : Action
    }

    var items: List<Map<String, Any?>> = emptyList(); private set
    /** Son liste TV'de (gönderildi ve elle sonuçla örtülmedi). */
    var sent = false; private set
    private var sentAt = Long.MIN_VALUE / 2
    private var paused = false

    @Synchronized fun set(list: List<Map<String, Any?>>, nowMs: Long): Action {
        if (list == items && (list.isEmpty() || sent || paused)) return Action.None
        items = list
        if (paused) return Action.None
        return send(nowMs)
    }

    /** Düzenli çağrılır: süre dolduysa aynı liste yeniden. */
    @Synchronized fun tick(nowMs: Long): Action {
        if (paused || !sent || items.isEmpty() || nowMs - sentAt < refreshMs) return Action.None
        sentAt = nowMs
        return Action.Send(items)
    }

    /** Elle sonuçlar kanalı aldı (TV'deki liste onunla değişti). */
    @Synchronized fun pause() { paused = true; sent = false }

    /** Elle sonuçlar kalktı (TV temizlendi): liste varsa yeniden gider. */
    @Synchronized fun resume(nowMs: Long): Action {
        paused = false
        return if (items.isEmpty()) Action.None else send(nowMs)
    }

    private fun send(nowMs: Long): Action {
        if (items.isEmpty()) { val was = sent; sent = false; return if (was) Action.Clear else Action.None }
        sent = true; sentAt = nowMs
        return Action.Send(items)
    }

    companion object {
        const val REFRESH_MS = 60_000L
        const val DURATION_MS = 120_000
    }
}

/**
 * Kalkma histerezisi: görülen öğe ancak art arda en az [minMisses] okumada ve ilk kaçırmadan beri en az [minGoneMs]
 * bulunmazsa VE bölgesi son görüldüğü hâlinden görüntüsel olarak değiştiyse kalkar. Tek kaçırılan okuma (yazı
 * tanıma hatası) öğeyi silmez; görüntü aynı kaldıkça öğe durur. İz yoksa (bölge çok küçük) değişmiş sayılır.
 */
class ScreenItemHold(
    private val minMisses: Int = MIN_MISSES,
    private val minGoneMs: Long = MIN_GONE_MS,
    private val minChangedShare: Double = MIN_CHANGED_SHARE,
) {
    /** Öğenin yeri (iz alınan bölge); görünmüyorsa null. */
    var area: LiveBox? = null; private set
    private var reference: RegionTrace? = null
    private var misses = 0
    private var firstMissAt = 0L

    val showing: Boolean get() = area != null

    @Synchronized fun onSeen(area: LiveBox, trace: RegionTrace?) {
        this.area = area; reference = trace; misses = 0
    }

    /** Öğe bu okumada yok; true dönerse kaldırılmalı. [trace]: aynı bölgenin şimdiki izi. */
    @Synchronized fun onMissing(trace: RegionTrace?, nowMs: Long): Boolean {
        if (area == null) return false
        if (misses == 0) firstMissAt = nowMs
        misses++
        if (misses < minMisses || nowMs - firstMissAt < minGoneMs) return false
        val ref = reference
        val changed = ref == null || trace == null || ref.changedShare(trace) >= minChangedShare
        if (!changed) return false
        reset(); return true
    }

    @Synchronized fun reset() { area = null; reference = null; misses = 0 }

    companion object {
        const val MIN_MISSES = 3
        const val MIN_GONE_MS = 4_000L
        /** İz örneklerinin en az bu kadarı değişmeli (video gürültüsü tek tük örneği oynatır). */
        const val MIN_CHANGED_SHARE = 0.05
    }
}

/**
 * TV'ye giden oyun içi ekran öğelerinin ortak tahtası (NinoCore `ScreenItemSender` gibi): her tür (telefon paneli,
 * harita kartı) kendi öğe listesini ve kalkma histerezisini ([ScreenItemHold]) taşır. Bütün türlerde aynı kural:
 * öğe görülünce bölgesi ve izi kaydedilir; kaçırılan okumada ([missing]) tür ancak art arda 3 okuma + en az 4 sn +
 * bölgenin görüntüsel değişimiyle kalkar, tek kaçırılan okuma silmez. Aynı türden yeni öğeler gelince hemen değişir
 * ([seen]/[show]); türün "hemen kaldır" kuralları (sohbet başlığı değişti, telefon kaydı, harita açıldı, Ekranı çevir)
 * [drop] ile. TV listesi ([list]) türlerin sırasıyladır: telefon, harita. İş parçacığı güvenli.
 */
class ScreenItemBoard(newHold: () -> ScreenItemHold = { ScreenItemHold() }) {
    enum class Kind { PHONE, MAP }

    private val holds: Map<Kind, ScreenItemHold> = Kind.entries.associateWith { newHold() }
    private val items = java.util.EnumMap<Kind, List<Map<String, Any?>>>(Kind::class.java)

    fun hold(kind: Kind): ScreenItemHold = holds.getValue(kind)

    /** Türün son görüldüğü bölge (iz alınan); tutulmuyorsa null. */
    fun area(kind: Kind): LiveBox? = hold(kind).area

    /** Tür görüldü: bölge ve iz yenilenir, kaçırma sayacı sıfırlanır; [list] verilirse öğeler de değişir. */
    @Synchronized fun seen(kind: Kind, area: LiveBox, trace: RegionTrace?, list: List<Map<String, Any?>>? = null) {
        hold(kind).onSeen(area, trace)
        if (list != null) items[kind] = list
    }

    /** Öğeler değişir; histerezis durumu olduğu gibi kalır. */
    @Synchronized fun show(kind: Kind, list: List<Map<String, Any?>>) { items[kind] = list }

    /** Bu okumada tür yok ([trace]: aynı bölgenin şimdiki izi). true: tür kalktı (liste yeniden gönderilmeli). */
    @Synchronized fun missing(kind: Kind, trace: RegionTrace?, nowMs: Long): Boolean {
        if (!hold(kind).onMissing(trace, nowMs)) return false
        items.remove(kind)
        return true
    }

    /** Tür hemen kalkar. true: TV'de ya da tutmada bir şey vardı. */
    @Synchronized fun drop(kind: Kind): Boolean {
        val had = hold(kind).showing || !items[kind].isNullOrEmpty()
        hold(kind).reset(); items.remove(kind)
        return had
    }

    @Synchronized fun items(kind: Kind): List<Map<String, Any?>> = items[kind].orEmpty()

    /** TV'ye gidecek liste. */
    @Synchronized fun list(): List<Map<String, Any?>> = Kind.entries.flatMap { items[it].orEmpty() }

    @Synchronized fun isEmpty(): Boolean = items.values.all { it.isEmpty() }

    @Synchronized fun reset() { holds.values.forEach { it.reset() }; items.clear() }

    companion object {
        /** [plane] karesindeki [area] kutusunun 64×12 izi (cihazda kırpmanın izi `FrameTrace.grid(crop)` ile aynı). */
        fun trace(plane: LumaPlane, area: LiveBox): RegionTrace? {
            val rect = FrameTrace.crop(LiveRegion(area.top, area.bottom, area.left, area.right).clamped(), plane.width, plane.height) ?: return null
            return FrameTrace.grid(plane, rect)
        }
    }
}

/**
 * Harita kartı: kalkma histerezisi [ScreenItemBoard]'da ([ScreenItemBoard.Kind.MAP]), çeviri önbelleği
 * [MapCardMemory]'de. Kutular okunan kırpmaya ([MapCards.READ_REGION] gibi) göre değil kareye göredir; iz kırpmadan
 * alınır.
 */
class MapCardKeeper(
    private val memory: MapCardMemory = MapCardMemory(),
    val board: ScreenItemBoard = ScreenItemBoard(),
) {
    val hold: ScreenItemHold get() = board.hold(ScreenItemBoard.Kind.MAP)

    /** Kart okundu: çevirisi önbellekten, yoksa [translate] ile (başarılıysa önbelleğe). */
    suspend fun seen(card: MapCardText, crop: LumaPlane, region: LiveRegion, translate: suspend (MapCardText) -> String?): String? {
        board.seen(ScreenItemBoard.Kind.MAP, card.box, trace(crop, region, card.box))
        memory.get(card)?.let { return it }
        val t = translate(card) ?: return null
        memory.put(card, t)
        return t
    }

    /** Bu okumada kart yok; true: kart kaldırıldı. */
    fun missing(crop: LumaPlane, region: LiveRegion, nowMs: Long): Boolean {
        val area = board.area(ScreenItemBoard.Kind.MAP) ?: return false
        return board.missing(ScreenItemBoard.Kind.MAP, trace(crop, region, area), nowMs)
    }

    fun reset() { board.drop(ScreenItemBoard.Kind.MAP) }

    companion object {
        /** Kare kutusunun [crop] içindeki 64×12 izi; kutu çok küçükse null. */
        fun trace(crop: LumaPlane, region: LiveRegion, box: LiveBox): RegionTrace? {
            val b = region.fromFrame(box)
            val rect = FrameTrace.crop(LiveRegion(b.top, b.bottom, b.left, b.right), crop.width, crop.height) ?: return null
            return FrameTrace.grid(crop, rect)
        }
    }
}
