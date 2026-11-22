// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.support

import android.os.Build
import com.ninotranslator.mobile.BuildConfig
import com.ninotranslator.mobile.data.ConsoleKind
import com.ninotranslator.mobile.data.Nino
import com.ninotranslator.mobile.data.TvBrand
import com.ninotranslator.mobile.data.VideoSource
import com.ninotranslator.mobile.service.LiveStatus
import com.ninotranslator.mobile.service.TvHub

/**
 * Cihaz özeti (servis.md §8), tek kaynak: sistem sağlığı, Sorun Bildir, otomatik bildirim ve Nino'ya Sor bunu
 * kullanır. `id: değer | id: değer`, en çok 600 karakter. Telefonun adı, kimliği, IP adresi ve cihazlara verilen
 * adlar okunmaz. Her gönderimde yeniden okunur. Değerler çevrilmez (destek için Türkçe).
 */
object DeviceSummary {
    const val MAX = 600

    /** Sıralı alanlar (id → değer); boş değerler yok. */
    fun fields(): List<Pair<String, String>> {
        val settings = Nino.settings
        val live = LiveStatus.state.value
        val out = ArrayList<Pair<String, String>>()
        out += "app" to "${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})"
        out += "device" to listOfNotNull(Build.MANUFACTURER, Build.MODEL).joinToString(" ").trim()
        out += "system" to "Android ${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT})"
        // TV uygulamasının kurulduğu TV + bağlanan TV uygulamasının bildirdiği model.
        val model = tvModel(runCatching { TvHub.connectedModel() }.getOrNull())
        val tv = settings.installedTv?.let { listOfNotNull(brandName(it.brand), it.version, model).joinToString(" ") } ?: model
        tv?.let { out += "tv" to it }
        out += "console" to when {
            settings.videoSource == VideoSource.CAPTURE_CARD -> "Yakalama kartı"
            settings.effectiveConsoleKind == ConsoleKind.XBOX ->
                listOfNotNull("Xbox", settings.xboxConsole?.model).joinToString(" ") + " · Remote Play"
            else -> "PS5 · Remote Play"
        }
        val names = listOfNotNull(Nino.secrets.console?.name, Nino.secrets.console?.host, settings.xboxConsole?.name,
            settings.tvName, settings.installedTv?.host)
        val status = live.errorText ?: if (live.running) {
            listOfNotNull(live.phaseText).joinToString("") + ", oyun: " + (live.game ?: "tanınmadı")
        } else null
        status?.let { out += "status" to scrub(it, names) }
        return out.filter { it.second.isNotBlank() }
    }

    fun line(): String = join(fields())

    /** Satır sonu boşluğa, `|` `/`'ye; boş değer yazılmaz; 600'de kesilir. */
    fun join(fields: List<Pair<String, String?>>): String = fields
        .map { (k, v) -> k to (v ?: "").replace('\n', ' ').replace('\r', ' ').replace('|', '/').trim() }
        .filter { it.second.isNotEmpty() }
        .joinToString(" | ") { "${it.first}: ${it.second}" }
        .let { clip(it, MAX) }

    /** IP adresleri ve verilen adlar "…" ile silinir. */
    fun scrub(text: String, names: List<String>): String {
        var s = text.replace(Regex("""\b\d{1,3}(\.\d{1,3}){3}(:\d+)?\b"""), "…")
        for (n in names) if (n.length >= 2) s = s.replace(n, "…")
        return s
    }

    /** TV'nin bildirdiği model: tehlikeli işaretler atılır, en çok 60 karakter. */
    fun tvModel(raw: String?): String? = raw?.filter { it.isLetterOrDigit() || it in " -_.()/+" }?.trim()?.take(60)?.takeIf { it.isNotEmpty() }

    fun brandName(b: TvBrand): String = when (b) { TvBrand.LG -> "LG"; TvBrand.SAMSUNG -> "Samsung"; TvBrand.ANDROID_TV -> "Android TV" }

    /** [max] karakterde keser; yarım vekil çift bırakmaz. */
    fun clip(s: String, max: Int): String {
        if (s.length <= max) return s
        var end = max
        if (end > 0 && Character.isHighSurrogate(s[end - 1])) end--
        return s.substring(0, end)
    }
}
