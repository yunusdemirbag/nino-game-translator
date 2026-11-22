// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.service

import android.content.Context
import com.ninotranslator.mobile.data.Nino
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** Örnek satırlar: İngilizce kaynak ve çeviri (servis.md 16.1). */
object DemoLines {
    val ENGLISH = listOf(
        "We ride at dawn. Get some rest.",
        "Where did you hide the map?",
        "Stay close to me, it's not safe here.",
        "ARTHUR: I warned you it would end like this.",
        "If we hurry, we can still catch the train.",
    )
    private val TURKISH = listOf(
        "Şafakta yola çıkıyoruz. Biraz dinlen.",
        "Haritayı nereye sakladın?",
        "Yanımdan ayrılma, burası güvenli değil.",
        "ARTHUR: Böyle biteceği konusunda seni uyarmıştım.",
        "Acele edersek treni hâlâ yakalayabiliriz.",
    )
    private val ARABIC = listOf(
        "سننطلق عند الفجر. خذ قسطًا من الراحة.",
        "أين خبأت الخريطة؟",
        "ابقَ قريبًا مني، المكان هنا غير آمن.",
        "ARTHUR: حذّرتك من أن الأمر سينتهي هكذا.",
        "إن أسرعنا، فما زال بإمكاننا اللحاق بالقطار.",
    )

    /** Çeviri dilinin hazır satırları; yoksa Arapçada Arapça, öbür dillerde Türkçe. */
    fun forLanguage(code: String): List<String> = if (code.startsWith("ar")) ARABIC else TURKISH

    const val START_DELAY_MS = 1_200L
    const val SHOW_MS = 3_600L
    const val GAP_MS = 900L
}

/**
 * Kullanıcı demosu (servis.md 16.1): hizmet, ağ ve konsol kullanılmaz; yalnız canlı durum beslenir. Ana ekran, telefon
 * tam ekranı ve yan çevirme gerçekteki gibi çalışır.
 */
object DemoSession {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var job: Job? = null

    val isRunning: Boolean get() = job?.isActive == true

    fun start(context: Context) {
        stop()
        val code = Nino.settingsOrNull()?.targetLanguage ?: "tr"
        val lines = DemoLines.forLanguage(code)
        val texts = ServiceStrings(context.applicationContext)
        LiveStatus.update {
            LiveSnapshot(running = true, demo = true, streaming = true, phaseText = texts.get(TextRef(ServiceTexts.STREAMING)),
                startedAtMs = System.currentTimeMillis(), engineName = texts.get(ENGINE_FREE_KEY))
        }
        job = scope.launch {
            delay(DemoLines.START_DELAY_MS)
            var i = 0
            var id = 0
            val phone = PhoneLines()
            while (true) {
                val k = i % lines.size
                val st = phone.show(DemoLines.ENGLISH[k], lines[k], false, DemoLines.SHOW_MS, System.currentTimeMillis())
                id++
                val item = RecentTranslation(id, DemoLines.ENGLISH[k], lines[k], TranslationOrigin.ENGINE)
                LiveStatus.update {
                    StatusBook.withPhone(it, st, id).copy(
                        lastLine = lines[k], shownLines = it.shownLines + 1,
                        recent = (listOf(item) + it.recent).take(StatusBook.MAX_RECENT),
                    )
                }
                delay(DemoLines.SHOW_MS)
                // Boşlukta satır kalkar; önceki satır soluk durur.
                LiveStatus.update { it.copy(currentLine = null, previousLine = lines[k], currentLineId = ++id) }
                delay(DemoLines.GAP_MS)
                i++
            }
        }
    }

    fun stop() {
        val j = job ?: return
        job = null
        j.cancel()
        LiveStatus.reset()
    }

    /** Ücretsiz motorun görünen adının strings anahtarı. */
    const val ENGINE_FREE_KEY = "engine_free_short"
}
