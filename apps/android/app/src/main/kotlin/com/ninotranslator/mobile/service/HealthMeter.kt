// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.service

import com.ninotranslator.mobile.support.HealthEval
import com.ninotranslator.mobile.support.NetKind
import java.util.Locale

/**
 * Bir oturumun ham ölçümleri (servis.md 5). Oturum bitince son değerler kalır. Düzeyler, sebepler ve özet tek yerde:
 * [HealthEval] (girdi [com.ninotranslator.mobile.support.HealthInputs]).
 */
data class HealthSnapshot(
    val streamedMs: Long = 0,
    val everStreamed: Boolean = false,
    val drops: Int = 0,
    val connectFails: Int = 0,
    val lastDropReason: String? = null,
    val frames: Long = 0,
    val framesPerSecond: Double? = null,
    val lines: Int = 0,
    val medianMs: Long? = null,
    val maxMs: Long? = null,
    /** Şu an kopuk ve ne zamandan beri (System.currentTimeMillis). */
    val disconnectedSinceMs: Long? = null,
    val networkLosses: Int = 0,
    val tvDrops: Int = 0,
    val network: NetKind = NetKind.OTHER,
    val sessionRunning: Boolean = false,
)

/**
 * Bir oturumun sağlık ölçümü (servis.md 5). Saat dışarıdan verilir; oturum dışında gelen sayımlar yok sayılır.
 * Kare sayısı yalnız görüntü gelirken artar; kaynağın sayacı sıfırlanırsa toplam kaybolmaz.
 */
class HealthMeter(private val clock: () -> Long) {
    private var running = false
    private var streamingSince: Long? = null
    private var streamedMs = 0L
    private var everStreamed = false
    private var attemptStreamed = false
    private var drops = 0
    private var connectFails = 0
    private var lastReason: String? = null
    private var frames = 0L
    private var lastSourceFrames = 0L
    private var lines = 0
    private val times = ArrayDeque<Long>()
    private var disconnectedSince: Long? = null
    private var networkLosses = 0
    private var tvDrops = 0
    @Volatile var network = NetKind.OTHER

    val isRunning get() = running

    @Synchronized fun start() {
        running = true; streamingSince = null; streamedMs = 0; everStreamed = false; attemptStreamed = false
        drops = 0; connectFails = 0; lastReason = null; frames = 0; lastSourceFrames = 0; lines = 0; times.clear()
        disconnectedSince = null; networkLosses = 0; tvDrops = 0
    }

    @Synchronized fun stop() {
        if (!running) return
        streamingSince?.let { streamedMs += clock() - it }
        streamingSince = null
        running = false
    }

    /** Görüntü gelmeye başladı. */
    @Synchronized fun onStreaming() {
        if (!running || streamingSince != null) return
        streamingSince = clock(); everStreamed = true; attemptStreamed = true; disconnectedSince = null
    }

    /** Bağlanmaya çalışıyor (yeni deneme). */
    @Synchronized fun onConnecting() {
        if (!running) return
        if (streamingSince != null) onLost(null)
    }

    /** Görüntü kesildi ya da deneme bitti; [reason] tür adı (`NOT_FOUND` gibi). Kopma mı bağlanamama mı döner. */
    @Synchronized fun onLost(reason: String?): Boolean {
        if (!running) return false
        val wasStreaming = streamingSince != null
        streamingSince?.let { streamedMs += clock() - it }
        streamingSince = null
        if (reason != null) lastReason = reason
        if (wasStreaming) { drops++; disconnectedSince = clock() } else if (!attemptStreamed) connectFails++
        attemptStreamed = false
        return wasStreaming
    }

    /** Kaynağın toplam kare sayacı. */
    @Synchronized fun onFrames(sourceTotal: Long) {
        if (!running) return
        val delta = if (sourceTotal >= lastSourceFrames) sourceTotal - lastSourceFrames else sourceTotal
        lastSourceFrames = sourceTotal
        if (streamingSince != null) frames += delta
    }

    /** Gösterilen satır; paket satırında [translateMs] null (süreye girmez). */
    @Synchronized fun onLine(translateMs: Long?) {
        if (!running) return
        lines++
        if (translateMs != null) { times.addLast(translateMs); while (times.size > 50) times.removeFirst() }
    }

    @Synchronized fun onNetworkLost() { if (running) networkLosses++ }
    @Synchronized fun onTvDrop() { if (running) tvDrops++ }

    @Synchronized fun snapshot(): HealthSnapshot {
        val now = clock()
        val streamed = streamedMs + (streamingSince?.let { now - it } ?: 0)
        val fps = if (streamed >= HealthEval.MIN_STREAM_FOR_FPS_MS) frames * 1000.0 / streamed else null
        val down = disconnectedSince != null && streamingSince == null
        return HealthSnapshot(
            streamedMs = streamed, everStreamed = everStreamed, drops = drops, connectFails = connectFails,
            lastDropReason = lastReason, frames = frames, framesPerSecond = fps, lines = lines,
            medianMs = HealthEval.median(times.toList()), maxMs = times.maxOrNull(),
            disconnectedSinceMs = if (down) disconnectedSince else null, networkLosses = networkLosses, tvDrops = tvDrops,
            network = network, sessionRunning = running,
        )
    }
}

/** Kopma nedeninin adı (sorun kayıtları ve özet; adres yok). */
object DropReasons {
    /** Aşama anahtarından kopma türünün adı (adres yok). */
    fun of(key: String?): String? = when {
        key == null -> null
        key.startsWith("phase_not_found") -> "NOT_FOUND"
        key == "phase_network" -> "NETWORK"
        key == "phase_in_use" -> "IN_USE"
        key == "phase_asleep" -> "CONSOLE_ASLEEP"
        key == "phase_no_picture" -> "NO_PICTURE"
        key == "phase_refused" -> "REFUSED"
        key.startsWith("phase_rejected") -> "REJECTED"
        key == "phase_registration_invalid" -> "REGISTRATION_INVALID"
        key == "phase_remote_play_disabled" -> "REMOTE_PLAY_DISABLED"
        key.startsWith("phase_passcode") -> "PASSCODE"
        key.startsWith("capture_") -> key.removePrefix("capture_").uppercase(Locale.ROOT)
        else -> "OTHER"
    }
}
