// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.data

import android.content.SharedPreferences
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import java.util.concurrent.CopyOnWriteArrayList

/**
 * SharedPreferences sarmalayıcısı: tür hatasına dayanıklı okuma ve değişiklik bildirimi.
 * Bütün yazmalar buradan geçer; dinleyiciler ve akışlar yazma anında (aynı iş parçacığında) haber alır.
 * Not: SharedPreferences'a dışarıdan doğrudan yazılanlar bildirilmez.
 */
class PrefStore(val prefs: SharedPreferences) {
    private val _changes = MutableSharedFlow<String>(extraBufferCapacity = 64, onBufferOverflow = BufferOverflow.DROP_OLDEST)
    private val _revision = MutableStateFlow(0L)
    private val listeners = CopyOnWriteArrayList<(String) -> Unit>()

    /** Değişen anahtar adları. */
    val changes: SharedFlow<String> = _changes.asSharedFlow()

    /** Her yazmada bir artar; "bir şey değişti, yeniden oku" için. */
    val revision: StateFlow<Long> = _revision.asStateFlow()

    /** Eşzamanlı dinleyici (yazan iş parçacığında çağrılır). Kapatınca kalkar. */
    fun addListener(listener: (String) -> Unit): AutoCloseable {
        listeners += listener
        return AutoCloseable { listeners -= listener }
    }

    fun has(key: String): Boolean = prefs.contains(key)

    // Gerçek SharedPreferences tür uyuşmazlığında ClassCastException atar; varsayılana düşülür.
    fun bool(key: String, def: Boolean): Boolean = safe(def) { prefs.getBoolean(key, def) }
    fun int(key: String, def: Int): Int = safe(def) { prefs.getInt(key, def) }
    fun long(key: String, def: Long): Long = safe(def) { prefs.getLong(key, def) }
    fun float(key: String, def: Float): Float = safe(def) { prefs.getFloat(key, def) }
    fun string(key: String): String? = safe(null) { prefs.getString(key, null) }
    fun stringSet(key: String): Set<String> = safe(emptySet()) { prefs.getStringSet(key, null)?.toSet() ?: emptySet() }
    fun keys(): Set<String> = prefs.all.keys

    /** Birlikte yazılması gereken anahtarlar tek işlemde yazılır; sonra her anahtar bildirilir. */
    fun edit(keys: Collection<String>, block: SharedPreferences.Editor.() -> Unit) {
        prefs.edit().apply(block).apply()
        notify(keys)
    }

    fun edit(vararg keys: String, block: SharedPreferences.Editor.() -> Unit) = edit(keys.asList(), block)

    /** Diske hemen yazılması gereken durumlar için (ör. açılıştaki `translating`). */
    fun editNow(keys: Collection<String>, block: SharedPreferences.Editor.() -> Unit): Boolean {
        val ok = prefs.edit().apply(block).commit()
        notify(keys)
        return ok
    }

    fun putString(key: String, value: String?) = edit(key) { if (value == null) remove(key) else putString(key, value) }
    fun putBool(key: String, value: Boolean) = edit(key) { putBoolean(key, value) }
    fun putInt(key: String, value: Int) = edit(key) { putInt(key, value) }
    fun putLong(key: String, value: Long) = edit(key) { putLong(key, value) }
    fun remove(key: String) = edit(key) { remove(key) }

    fun clear() {
        val old = keys()
        edit(old) { clear() }
    }

    private fun notify(keys: Collection<String>) {
        if (keys.isEmpty()) return
        _revision.value = _revision.value + 1
        for (k in keys) {
            _changes.tryEmit(k)
            for (l in listeners) runCatching { l(k) }
        }
    }

    private inline fun <T> safe(def: T, read: () -> T): T = try {
        read()
    } catch (_: ClassCastException) {
        def
    }
}
