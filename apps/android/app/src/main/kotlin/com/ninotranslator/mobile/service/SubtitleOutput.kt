// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.service

import com.ninotranslator.core.link.DisplayHub
import com.ninotranslator.core.link.ShowPayload
import com.ninotranslator.core.link.SubtitlePosition
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.launch

/** TV'ye gönderim. Gerçeği [HubTvOutput] (DisplayHub); testlerde sahtesi. */
interface TvOutput {
    val connectedCount: StateFlow<Int>
    /** Açılamayan portlar (altyazı sunucusu). */
    val portProblems: StateFlow<Set<Int>>
    /** false iken altyazı olayları TV'ye gitmez (hedef "bu telefon"); style/started/stopped yine gider. */
    var subtitlesToTv: Boolean
    fun start()
    fun close()
    suspend fun show(payload: ShowPayload)
    suspend fun clear(id: Int)
    fun setStyle(style: Map<String, Any?>)
    suspend fun started()
    suspend fun stopped()
    /** "Ekranı çevir" ve yan çeviriler (tv.md `screen`). [overlay] true ise TV altyazıyı silmez. */
    suspend fun screen(items: List<Map<String, Any?>>, durationMs: Int, overlay: Boolean) {}
    suspend fun screenClear() {}
    /** Ek alan kutusu; [text] boşsa kutu kalkar (tv.md `region`). */
    suspend fun region(id: String, text: String, box: Map<String, Double>?, lineHeight: Double?) {}
    suspend fun regionClearAll() {}
}

/** DisplayHub üstünde TV çıkışı. */
class HubTvOutput(private val hub: DisplayHub, scope: CoroutineScope) : TvOutput {
    override val connectedCount: StateFlow<Int> = hub.displays.map { it.size }.stateIn(scope, SharingStarted.Eagerly, 0)
    override val portProblems: StateFlow<Set<Int>> get() = hub.portProblems
    override var subtitlesToTv: Boolean
        get() = hub.tvSubtitlesEnabled
        set(v) { hub.tvSubtitlesEnabled = v }
    override fun start() = hub.start()
    override fun close() = hub.close()
    override suspend fun show(payload: ShowPayload) = hub.show(payload)
    override suspend fun clear(id: Int) = hub.clear(id)
    override fun setStyle(style: Map<String, Any?>) = hub.setStyle(style)
    override suspend fun started() = hub.started()
    override suspend fun stopped() = hub.stopped()
    override suspend fun screen(items: List<Map<String, Any?>>, durationMs: Int, overlay: Boolean) = hub.screen(items, durationMs, overlay)
    override suspend fun screenClear() = hub.screenClear()
    override suspend fun region(id: String, text: String, box: Map<String, Double>?, lineHeight: Double?) = hub.region(id, text, box, lineHeight)
    override suspend fun regionClearAll() = hub.regionClearAll()
}

/** TV'siz çıkış (testler ve TV katmanı yokken). */
class NoTvOutput : TvOutput {
    override val connectedCount = MutableStateFlow(0)
    override val portProblems = MutableStateFlow<Set<Int>>(emptySet())
    override var subtitlesToTv = true
    override fun start() {}
    override fun close() {}
    override suspend fun show(payload: ShowPayload) {}
    override suspend fun clear(id: Int) {}
    override fun setStyle(style: Map<String, Any?>) {}
    override suspend fun started() {}
    override suspend fun stopped() {}
}

/**
 * Gösterilen satırı TV'ye (hedef TV ise) ve telefon ekranına dağıtır (servis.md 3.3–3.4, tv.md 1.5).
 * Telefon ekranının durumu [phone]'dadır; [onPhone] her değişiklikte çağrılır.
 */
class SubtitleRouter(
    private val scope: CoroutineScope,
    private val tv: TvOutput,
    private val wallClock: () -> Long,
    private val monoClock: () -> Long,
    private val onPhone: (PhoneLines.State, Int) -> Unit,
) {
    val phone = PhoneLines()
    private var phoneId = 0

    fun show(line: ShownLine) {
        val extras = LinkedHashMap<String, Any?>()
        line.box?.let { b -> extras["box"] = mapOf("left" to b.left, "top" to b.top, "right" to b.right, "bottom" to b.bottom) }
        if (line.replacesPrevious) extras["replace"] = true
        extras["at"] = wallClock()
        val payload = ShowPayload(
            id = line.id, text = line.text, source = line.source, position = SubtitlePosition.BOTTOM,
            durationMs = line.durationMs.toInt(), extras = extras,
        )
        scope.launch { runCatching { tv.show(payload) } }
        val st = phone.show(line.source, line.text, line.replacesPrevious, line.durationMs, monoClock())
        onPhone(st, ++phoneId)
    }

    fun clear(id: Int) {
        scope.launch { runCatching { tv.clear(id) } }
        onPhone(phone.clear(), ++phoneId)
    }

    /** Düzenli çağrılır: telefondaki satırın süresi doldu mu. */
    fun tick() { phone.expire(monoClock())?.let { onPhone(it, ++phoneId) } }
}
