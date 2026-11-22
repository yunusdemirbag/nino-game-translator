// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.telemetry

import com.ninotranslator.core.json.Json
import java.io.File

/**
 * Çökme tespiti: `telemetry/running.json` çalışma işareti. Açılışta yazılır; bir sonraki açılışta önceki işaret
 * okunur ([begin]). Yakalanmamış istisnada yalnız sınıf adı ve uygulama içi sembol yazılır (mesaj değil).
 *
 * Android'de uygulama düzgün "kapanmaz" (süreç öldürülür); bu yüzden işaret silinmez, [setBackground] ile
 * "arka planda" diye işaretlenir. Arka plandaki ölüm (işletim sistemi kapattı) çökme sayılmaz; yalnız işletim
 * sisteminin çıkış kaydı çökme diyorsa sayılır ([PreviousExit]).
 */
class CrashMarker(directory: File) {
    data class Record(
        /** Çalışan (çökebilecek) sürüm. */
        val version: String,
        /** Açılış (Unix sn). */
        val started: Long,
        /** Son "hâlâ çalışıyorum" zamanı. */
        val alive: Long,
        val pid: Int? = null,
        /** Ekranda etkinlik yok ve çeviri oturumu yok. */
        val background: Boolean = false,
        val code: String? = null,
        val place: String? = null,
    ) {
        fun toWire(): Map<String, Any?> = linkedMapOf<String, Any?>(
            "version" to version, "started" to started, "alive" to alive, "background" to background,
        ).apply {
            pid?.let { put("pid", it.toLong()) }
            code?.let { put("code", it) }
            place?.let { put("place", it) }
        }

        companion object {
            fun fromWire(m: Map<*, *>): Record? {
                val v = m["version"] as? String ?: return null
                val started = (m["started"] as? Number)?.toLong() ?: return null
                return Record(
                    version = v, started = started, alive = (m["alive"] as? Number)?.toLong() ?: started,
                    pid = (m["pid"] as? Number)?.toInt(), background = m["background"] as? Boolean ?: false,
                    code = m["code"] as? String, place = m["place"] as? String,
                )
            }
        }
    }

    val file = File(directory, "running.json")
    private val lock = Any()

    fun read(): Record? = synchronized(lock) {
        val text = runCatching { file.readText() }.getOrNull() ?: return null
        runCatching { (Json.parse(text) as? Map<*, *>)?.let(Record::fromWire) }.getOrNull()
    }

    /** Açılış: önceki çalışmanın işaretini döndürür (yoksa null), yenisini yazar. */
    fun begin(version: String, now: Long, pid: Int?): Record? = synchronized(lock) {
        val exists = file.exists()
        val previous = if (exists) read() ?: Record(version = "", started = now, alive = now) else null
        write(Record(version, now, now, pid))
        previous
    }

    fun touch(now: Long) = update { it.copy(alive = now) }

    fun setBackground(background: Boolean, now: Long) = update { it.copy(background = background, alive = now) }

    /** Yakalanmamış istisna: yalnız kod (sınıf adı) ve yer (sembol). */
    fun noteCrash(code: String, place: String?) = update { it.copy(code = TelemetryCode.clean(code) ?: TelemetryCode.UNCLEAN_EXIT, place = TelemetryCode.cleanWhere(place)) }

    fun clear() = synchronized(lock) { runCatching { file.delete() }; Unit }

    private fun update(change: (Record) -> Record) {
        synchronized(lock) {
            val r = read() ?: return
            write(change(r))
        }
    }

    private fun write(r: Record) {
        runCatching {
            file.parentFile?.mkdirs()
            val tmp = File(file.parentFile, file.name + ".tmp")
            tmp.writeText(Json.write(r.toWire()))
            if (!tmp.renameTo(file)) { file.delete(); tmp.renameTo(file) }
        }
    }

    companion object {
        /** Önceki çalışmanın çökme olayı ya da null (işletim sisteminin çıkış kaydıyla birlikte karar verilir). */
        fun crashEvent(previous: Record?, exit: PreviousExit): TelemetryEvent? {
            if (previous == null) return null
            val up = (previous.alive - previous.started).coerceAtLeast(0)
            if (previous.code != null) return TelemetryEvent.crash(previous.code, previous.place, previous.version, up)
            return when (exit) {
                is PreviousExit.Crash -> TelemetryEvent.crash(exit.code, null, previous.version, up)
                PreviousExit.Clean -> null
                PreviousExit.Unknown -> if (previous.background) null else TelemetryEvent.crash(null, null, previous.version, up)
            }
        }
    }
}

/** İşletim sisteminin önceki süreç için bildirdiği çıkış (Android 11+ ApplicationExitInfo). */
sealed interface PreviousExit {
    /** Çökme, ANR ya da önde bellek yetmezliği. */
    data class Crash(val code: String) : PreviousExit
    /** Kullanıcı ya da sistem düzgün kapattı (güncelleme, kaydırıp kapatma, arka planda öldürme). */
    data object Clean : PreviousExit
    /** Bilgi yok (eski Android ya da kayıt bulunamadı). */
    data object Unknown : PreviousExit
}
