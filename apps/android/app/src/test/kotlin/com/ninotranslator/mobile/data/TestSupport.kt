// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.data

import android.content.SharedPreferences
import org.w3c.dom.Element
import java.io.File
import java.io.InputStream
import javax.crypto.SecretKey
import javax.crypto.spec.SecretKeySpec
import javax.xml.parsers.DocumentBuilderFactory

/**
 * Bellek içi SharedPreferences. Gerçeği gibi: tür uyuşmazlığında ClassCastException, değerler değişmez kopya,
 * dinleyiciler commit/apply sonrası çağrılır.
 */
class FakePrefs(initial: Map<String, Any?> = emptyMap()) : SharedPreferences {
    private val map = LinkedHashMap<String, Any?>(initial)
    private val listeners = LinkedHashSet<SharedPreferences.OnSharedPreferenceChangeListener>()
    var commits = 0

    fun raw(): Map<String, Any?> = LinkedHashMap(map)

    override fun getAll(): MutableMap<String, *> = LinkedHashMap(map)
    override fun getString(key: String, defValue: String?): String? = if (key !in map) defValue else map[key] as String?
    @Suppress("UNCHECKED_CAST")
    override fun getStringSet(key: String, defValues: MutableSet<String>?): MutableSet<String>? =
        if (key !in map) defValues else (map[key] as Set<String>).toMutableSet()
    override fun getInt(key: String, defValue: Int): Int = if (key !in map) defValue else map[key] as Int
    override fun getLong(key: String, defValue: Long): Long = if (key !in map) defValue else map[key] as Long
    override fun getFloat(key: String, defValue: Float): Float = if (key !in map) defValue else map[key] as Float
    override fun getBoolean(key: String, defValue: Boolean): Boolean = if (key !in map) defValue else map[key] as Boolean
    override fun contains(key: String): Boolean = map.containsKey(key)
    override fun edit(): SharedPreferences.Editor = Ed()
    override fun registerOnSharedPreferenceChangeListener(l: SharedPreferences.OnSharedPreferenceChangeListener) { listeners += l }
    override fun unregisterOnSharedPreferenceChangeListener(l: SharedPreferences.OnSharedPreferenceChangeListener) { listeners -= l }

    private inner class Ed : SharedPreferences.Editor {
        private val puts = LinkedHashMap<String, Any?>()
        private val removes = LinkedHashSet<String>()
        private var clear = false
        override fun putString(key: String, value: String?) = apply { if (value == null) removes += key else puts[key] = value }
        override fun putStringSet(key: String, values: MutableSet<String>?) = apply { if (values == null) removes += key else puts[key] = values.toSet() }
        override fun putInt(key: String, value: Int) = apply { puts[key] = value }
        override fun putLong(key: String, value: Long) = apply { puts[key] = value }
        override fun putFloat(key: String, value: Float) = apply { puts[key] = value }
        override fun putBoolean(key: String, value: Boolean) = apply { puts[key] = value }
        override fun remove(key: String) = apply { removes += key }
        override fun clear() = apply { clear = true }
        override fun commit(): Boolean {
            if (clear) map.clear()
            removes.forEach { map.remove(it) }
            map.putAll(puts)
            commits++
            (removes + puts.keys).forEach { k -> listeners.forEach { it.onSharedPreferenceChanged(this@FakePrefs, k) } }
            return true
        }
        override fun apply() { commit() }
    }

    companion object {
        /** Android'in `shared_prefs/<ad>.xml` biçimini okur. */
        fun fromXml(input: InputStream): FakePrefs {
            val doc = DocumentBuilderFactory.newInstance().newDocumentBuilder().parse(input)
            val out = LinkedHashMap<String, Any?>()
            val nodes = doc.documentElement.childNodes
            for (i in 0 until nodes.length) {
                val e = nodes.item(i) as? Element ?: continue
                val name = e.getAttribute("name")
                out[name] = when (e.tagName) {
                    "string" -> e.textContent
                    "boolean" -> e.getAttribute("value").toBoolean()
                    "int" -> e.getAttribute("value").toInt()
                    "long" -> e.getAttribute("value").toLong()
                    "float" -> e.getAttribute("value").toFloat()
                    "set" -> (0 until e.childNodes.length).mapNotNull { (e.childNodes.item(it) as? Element)?.textContent }.toSet()
                    else -> error("bilinmeyen öğe ${e.tagName}")
                }
            }
            return FakePrefs(out)
        }

        fun fixture(name: String): FakePrefs = fromXml(resource("legacy/shared_prefs/$name.xml"))
    }
}

fun resource(path: String): InputStream =
    FakePrefs::class.java.classLoader!!.getResourceAsStream(path) ?: error("fikstür yok: $path")

fun resourceText(path: String): String = resource(path).readBytes().toString(Charsets.UTF_8)

/** Sabit yazılım anahtarı (testler için): 00..1f. */
class FixedKeySource(val key: SecretKey? = SecretKeySpec(ByteArray(32) { it.toByte() }, "AES")) : SecretKeySource {
    var destroyed = false
    override fun keyForRead() = key
    override fun keyForWrite() = key
    override fun destroy() { destroyed = true }
}

fun tempDir(): File = kotlin.io.path.createTempDirectory("nino-test").toFile().apply { deleteOnExit() }
