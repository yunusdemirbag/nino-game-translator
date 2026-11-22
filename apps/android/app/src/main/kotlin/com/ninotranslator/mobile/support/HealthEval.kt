// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.support

import com.ninotranslator.mobile.service.HealthSnapshot
import java.util.Locale

/** Sağlık göstergesinin düzeyi (servis.md §5.1). */
enum class HealthLevel { GOOD, WARNING, PROBLEM, UNKNOWN }

/** Telefonun ağ türü; [wire] sorun kayıtlarına ve özet satırına yazılan ad. */
enum class NetKind(val wire: String) { WIFI("wifi"), WIRED("kablolu"), CELLULAR("mobil"), OFFLINE("çevrimdışı"), OTHER("bilinmiyor") }

/** Oturumun ölçümleri. Saf veri; arayüz ve sorun bildirimi aynı hesabı kullanır. */
data class HealthInput(
    val running: Boolean = false,
    val streaming: Boolean = false,
    val targetTv: Boolean = true,
    val network: NetKind = NetKind.OTHER,
    /** Bu oturumda ölçüm var mı (oturum en az bir kez başladı). */
    val measured: Boolean = false,
    /** Görüntünün geldiği toplam süre (ms). */
    val streamedMs: Long = 0,
    val everStreamed: Boolean = false,
    /** Görüntü gelirken kopma sayısı. */
    val drops: Int = 0,
    /** Hiç görüntü gelmeden biten bağlanma denemesi. */
    val failedConnects: Int = 0,
    /** Şu an kopuksa kopuşun anı (ms). */
    val disconnectedSinceMs: Long? = null,
    val nowMs: Long = 0,
    /** Son pencerede kare/sn; yoksa null. */
    val fps: Double? = null,
    /** Paket dışı son çevirilerin ortanca ve en uzun süresi (ms). */
    val medianTranslateMs: Long? = null,
    val maxTranslateMs: Long? = null,
    val lines: Int = 0,
    val packLines: Int = 0,
    /** Oturumda telefonun ağı kaç kez gitti. */
    val networkLosses: Int = 0,
    /** Oturumda TV kaç kez koptu. */
    val tvDrops: Int = 0,
    val tvConnected: Int = 0,
    /** Son kopma nedeninin adı (ör. CONSOLE_ASLEEP), yoksa null. */
    val lastDropReason: String? = null,
    /** Son PS5 kopmasından önce telefonun ağı gitti mi. */
    val networkLostBeforeDrop: Boolean = false,
)

/** "Muhtemel sebep" (servis.md §5.2), önem sırasıyla. */
enum class HealthCause {
    OFFLINE, PS5_AFTER_NETWORK, PS5_ASLEEP, PS5_IN_USE, PS5_LOST, PS5_NEVER, NETWORK_DROPPED, PICTURE_WIFI, PICTURE,
    DROPS, SLOW, TV,
}

/** Hizmetin ölçümünden ([HealthSnapshot]) değerlendirme girdisi: arayüz, elle ve otomatik bildirim aynısını kullanır. */
object HealthInputs {
    fun of(
        h: HealthSnapshot, nowMs: Long, running: Boolean = h.sessionRunning, streaming: Boolean = false, targetTv: Boolean = true,
        tvConnected: Int = 0, packLines: Int = 0,
    ) = HealthInput(
        running = running || h.sessionRunning, streaming = streaming, targetTv = targetTv, network = h.network,
        measured = h.sessionRunning || h.everStreamed || h.connectFails > 0 || h.lines > 0,
        streamedMs = h.streamedMs, everStreamed = h.everStreamed, drops = h.drops, failedConnects = h.connectFails,
        disconnectedSinceMs = h.disconnectedSinceMs, nowMs = nowMs, fps = h.framesPerSecond, medianTranslateMs = h.medianMs,
        maxTranslateMs = h.maxMs, lines = h.lines, packLines = packLines, networkLosses = h.networkLosses,
        tvDrops = h.tvDrops, tvConnected = tvConnected, lastDropReason = h.lastDropReason,
        networkLostBeforeDrop = h.disconnectedSinceMs != null && h.networkLosses > 0,
    )
}

/** Eşikler ve sebep sırası. */
object HealthEval {
    /** Bu süre görüntü gelmeden kare/sn hesaplanmaz. */
    const val MIN_STREAM_FOR_FPS_MS = 20_000L

    fun fpsShown(i: HealthInput): Double? = i.fps?.takeIf { i.streamedMs >= MIN_STREAM_FOR_FPS_MS }

    fun pictureLevel(i: HealthInput): HealthLevel {
        val fps = fpsShown(i) ?: return HealthLevel.UNKNOWN
        return when {
            fps < 12 -> HealthLevel.PROBLEM
            fps < 24 -> HealthLevel.WARNING
            else -> HealthLevel.GOOD
        }
    }

    fun translationLevel(i: HealthInput): HealthLevel {
        val m = i.medianTranslateMs ?: return HealthLevel.UNKNOWN
        return when {
            m > 3000 -> HealthLevel.PROBLEM
            m > 1500 -> HealthLevel.WARNING
            else -> HealthLevel.GOOD
        }
    }

    fun ps5Level(i: HealthInput): HealthLevel = when {
        !i.measured -> HealthLevel.UNKNOWN
        i.disconnectedSinceMs != null && i.everStreamed -> HealthLevel.PROBLEM
        !i.everStreamed && i.failedConnects >= 2 -> HealthLevel.PROBLEM
        i.drops >= 3 -> HealthLevel.WARNING
        i.everStreamed -> HealthLevel.GOOD
        else -> HealthLevel.UNKNOWN
    }

    /** Kablo hep iyi, çevrimdışı sorun; diğerleri görüntünün rengini alır (ölçülmeden yeşil olmaz). */
    fun networkLevel(i: HealthInput): HealthLevel = when (i.network) {
        NetKind.WIRED -> HealthLevel.GOOD
        NetKind.OFFLINE -> HealthLevel.PROBLEM
        else -> pictureLevel(i)
    }

    fun tvLevel(i: HealthInput): HealthLevel = when {
        i.tvConnected > 0 -> HealthLevel.GOOD
        i.running && i.everStreamed -> HealthLevel.WARNING
        else -> HealthLevel.UNKNOWN
    }

    /** Satırlardaki en kötü düzey; hiç ölçüm yoksa UNKNOWN. */
    fun overall(levels: List<HealthLevel>): HealthLevel = when {
        HealthLevel.PROBLEM in levels -> HealthLevel.PROBLEM
        HealthLevel.WARNING in levels -> HealthLevel.WARNING
        HealthLevel.GOOD in levels -> HealthLevel.GOOD
        else -> HealthLevel.UNKNOWN
    }

    /** Muhtemel sebepler, önemliden önemsize. Hiç ölçüm yoksa yalnız çevrimdışılık. */
    fun causes(i: HealthInput): List<HealthCause> {
        val out = ArrayList<HealthCause>()
        if (i.network == NetKind.OFFLINE) out += HealthCause.OFFLINE
        if (!i.measured) return out
        val lost = i.disconnectedSinceMs != null && i.everStreamed
        if (lost) {
            out += when {
                i.networkLostBeforeDrop -> HealthCause.PS5_AFTER_NETWORK
                i.lastDropReason == "CONSOLE_ASLEEP" -> HealthCause.PS5_ASLEEP
                i.lastDropReason == "IN_USE" || i.lastDropReason == "REMOTE_PLAY_IN_USE" -> HealthCause.PS5_IN_USE
                else -> HealthCause.PS5_LOST
            }
        } else if (!i.everStreamed && i.failedConnects >= 2) {
            out += HealthCause.PS5_NEVER
        }
        if (i.networkLosses > 0 && HealthCause.PS5_AFTER_NETWORK !in out) out += HealthCause.NETWORK_DROPPED
        val pic = pictureLevel(i)
        if (pic == HealthLevel.WARNING || pic == HealthLevel.PROBLEM) {
            out += if (i.network == NetKind.WIFI) HealthCause.PICTURE_WIFI else HealthCause.PICTURE
        } else if (i.drops >= 3 && i.networkLosses == 0 && !lost) {
            out += HealthCause.DROPS
        }
        if (translationLevel(i) == HealthLevel.PROBLEM) out += HealthCause.SLOW
        if (i.targetTv && i.tvDrops > 0) out += HealthCause.TV
        return out
    }

    /** Bildirimlere giden tek satırlık Türkçe özet (servis.md §5.3). */
    fun summaryLine(i: HealthInput): String {
        val parts = ArrayList<String>()
        parts += "ağ ${i.network.wire}"
        parts += "ağ kopması ${i.networkLosses}"
        parts += "TV kopması ${i.tvDrops}"
        i.disconnectedSinceMs?.let { parts += "PS5 ${((i.nowMs - it) / 1000).coerceAtLeast(0)} sn'dir kopuk" }
        parts += "görüntü ${i.streamedMs / 60_000} dk"
        fpsShown(i)?.let { parts += "${it.toInt()} kare/sn" }
        parts += "kopma ${i.drops}"
        parts += "bağlanamama ${i.failedConnects}"
        i.lastDropReason?.let { parts += "son kopma $it" }
        parts += "satır ${i.lines}"
        i.medianTranslateMs?.let { parts += "çeviri ortanca ${seconds(it)} sn" }
        i.maxTranslateMs?.let { parts += "en uzun ${seconds(it)} sn" }
        return parts.joinToString(" · ")
    }

    /** Bir ondalıklı saniye (nokta ile; yerel biçim arayüzde yapılır). */
    fun seconds(ms: Long): String = String.format(Locale.ROOT, "%.1f", ms / 1000.0)

    /** Ortanca (çift sayıda ortadaki iki değerin ortalaması). */
    fun median(values: List<Long>): Long? {
        if (values.isEmpty()) return null
        val s = values.sorted()
        val n = s.size
        return if (n % 2 == 1) s[n / 2] else (s[n / 2 - 1] + s[n / 2]) / 2
    }
}
