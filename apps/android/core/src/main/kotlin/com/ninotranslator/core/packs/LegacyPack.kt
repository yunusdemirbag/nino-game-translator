// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.packs

import com.ninotranslator.core.json.JsonReader
import java.io.BufferedInputStream
import java.io.File
import java.io.InputStream
import java.io.InputStreamReader
import java.util.Base64
import java.util.zip.GZIPInputStream

/**
 * Eski gömülü paket biçimi (ceviri.md 9.1): `.json.gz` ya da `.json`, anahtarlar 16 haneli özet.
 * Akış hâlinde okunur; anahtarlar sıralı ilkel dizilerde tutulur (büyük paketler ~200 bin satır).
 */
class LegacyPack private constructor(
    val id: String,
    val title: String,
    val format: Int?,
    private val entries: Table,
    private val segments: Table,
    val fuzzy: FuzzyIndex?,
) {
    /** Sıralı (işaretsiz) anahtar → metin tablosu. */
    class Table internal constructor(private val keys: LongArray, private val values: Array<String>) {
        val size: Int get() = keys.size
        fun get(key: Long): String? {
            var lo = 0; var hi = keys.size - 1
            while (lo <= hi) {
                val mid = (lo + hi) ushr 1
                val c = java.lang.Long.compareUnsigned(keys[mid], key)
                when { c < 0 -> lo = mid + 1; c > 0 -> hi = mid - 1; else -> return values[mid] }
            }
            return null
        }
    }

    class LoadException(message: String) : Exception(message)

    val entryCount: Int get() = entries.size
    val segmentCount: Int get() = segments.size

    fun entry(key: Long): String? = entries.get(key)
    fun segment(key: Long): String? = segments.get(key)
    fun anyLine(key: Long): String? = entries.get(key) ?: segments.get(key)

    companion object {
        private val TAG = Regex("<[^<>]*>")
        private val SPACES = Regex("\\s+")

        fun cleanTurkish(s: String): String = SPACES.replace(TAG.replace(s, ""), " ").trim()

        fun load(file: File): LegacyPack = file.inputStream().use { load(it, file.name.substringBefore('.')) }

        /** Akıştan yükler; gzip baştaki `1f 8b` baytlarından anlaşılır. [fallbackId] dosya adından. */
        fun load(input: InputStream, fallbackId: String): LegacyPack {
            val buffered = BufferedInputStream(input, 65_536)
            buffered.mark(2)
            val b0 = buffered.read(); val b1 = buffered.read()
            buffered.reset()
            val stream = if (b0 == 0x1f && b1 == 0x8b) GZIPInputStream(buffered, 65_536) else buffered
            return parse(JsonReader(InputStreamReader(stream, Charsets.UTF_8)), fallbackId)
        }

        fun parse(text: String, fallbackId: String): LegacyPack = parse(JsonReader(text.reader()), fallbackId)

        private class Builder {
            var keys = LongArray(1024); var values = arrayOfNulls<String>(1024); var n = 0
            fun add(k: Long, v: String?) {
                if (n == keys.size) { keys = keys.copyOf(n * 2); values = values.copyOf(n * 2) }
                keys[n] = k; values[n] = v; n++
            }
            /** Sıralar; aynı anahtarda sonraki kazanır; boş metinler atılır. */
            fun build(): Table {
                val idx = (0 until n).sortedWith { a, b -> java.lang.Long.compareUnsigned(keys[a], keys[b]).takeIf { it != 0 } ?: a.compareTo(b) }
                val k = ArrayList<Long>(n); val v = ArrayList<String>(n)
                var i = 0
                while (i < idx.size) {
                    var j = i
                    while (j + 1 < idx.size && keys[idx[j + 1]] == keys[idx[i]]) j++
                    val value = values[idx[j]]
                    if (!value.isNullOrEmpty()) { k += keys[idx[j]]; v += value }
                    i = j + 1
                }
                return Table(k.toLongArray(), v.toTypedArray())
            }
        }

        private fun parse(r: JsonReader, fallbackId: String): LegacyPack {
            var id: String? = null; var title: String? = null; var format: Int? = null
            val entries = Builder(); val segments = Builder(); val flat = Builder()
            var hasEntries = false
            var fuzzyRaw: Map<*, *>? = null
            val allKeys = Builder() // bulanık imza sırası için bütün anahtarlar (boşlar ve yinelenenler dahil)
            try {
                r.beginObject()
                while (r.hasNext()) {
                    val name = r.nextName()
                    when (name) {
                        "format" -> if (r.peek() == JsonReader.Token.NUMBER) format = r.nextLong().toInt() else r.skipValue()
                        "id" -> if (r.peek() == JsonReader.Token.STRING) id = r.nextString() else r.skipValue()
                        "title" -> if (r.peek() == JsonReader.Token.STRING) title = r.nextString() else r.skipValue()
                        "entries", "segments" -> {
                            if (name == "entries") hasEntries = true
                            if (r.peek() != JsonReader.Token.BEGIN_OBJECT) { r.skipValue(); continue }
                            val target = if (name == "entries") entries else segments
                            r.beginObject()
                            while (r.hasNext()) {
                                val k = PackKey.parse(r.nextName())
                                if (r.peek() != JsonReader.Token.STRING) { r.skipValue(); continue }
                                val v = cleanTurkish(r.nextString())
                                if (k == null) continue
                                allKeys.add(k, null)
                                target.add(k, v)
                            }
                            r.endObject()
                        }
                        "fuzzy" -> fuzzyRaw = r.nextValue() as? Map<*, *>
                        else -> {
                            // Düz biçim: kökteki dize alanları anahtar → Türkçe.
                            if (r.peek() == JsonReader.Token.STRING) {
                                val v = r.nextString()
                                PackKey.parse(name)?.let { flat.add(it, cleanTurkish(v)) }
                            } else r.skipValue()
                        }
                    }
                }
                r.endObject()
            } catch (e: com.ninotranslator.core.json.Json.ParseException) {
                throw LoadException("bozuk JSON: ${e.message}")
            }
            if (format != null && format != 1 && format != 2) throw LoadException("desteklenmeyen biçim $format")
            val packId: String; val packTitle: String; val table: Table
            if (hasEntries) {
                packId = id ?: fallbackId
                packTitle = title ?: packId
                table = entries.build()
            } else {
                packId = fallbackId; packTitle = fallbackId
                table = flat.build()
            }
            if (table.size == 0) throw LoadException("geçerli satır yok")
            val segTable = if (hasEntries) segments.build() else Table(LongArray(0), emptyArray())
            val fuzzy = if (hasEntries) fuzzyRaw?.let { runCatching { FuzzyIndex.decode(it, allKeys) }.getOrNull() } else null
            return LegacyPack(packId, packTitle, format, table, segTable, fuzzy)
        }

        private fun FuzzyIndex.Companion.decode(raw: Map<*, *>, all: Builder): FuzzyIndex? {
            if ((raw["version"] as? Number)?.toInt() != 1) return null
            val count = (raw["count"] as? Number)?.toInt() ?: return null
            if (count != all.n) return null
            val dec = Base64.getDecoder()
            val mask = dec.decode(raw["mask"] as? String ?: return null)
            val lengths = dec.decode(raw["lengths"] as? String ?: return null)
            val blooms = dec.decode(raw["blooms"] as? String ?: return null)
            val sorted = all.keys.copyOf(all.n).also { arr ->
                // İşaretsiz sıralama: işaret bitini çevirip sırala, geri çevir.
                for (i in arr.indices) arr[i] = arr[i] xor Long.MIN_VALUE
                arr.sort()
                for (i in arr.indices) arr[i] = arr[i] xor Long.MIN_VALUE
            }
            return build(sorted, mask, lengths, blooms)
        }
    }
}

/** Bir paketin bulanık imzaları: imzalı her satırın anahtarı, harf sayısı ve Bloom'u. */
class FuzzyIndex private constructor(
    val keys: LongArray,
    val lengths: IntArray,
    private val blooms: ByteArray,
    private val offsets: IntArray,
) {
    val size: Int get() = keys.size

    fun bits(i: Int): Int = FuzzySignature.bitsFor(lengths[i])
    fun bloom(i: Int): LongArray = FuzzySignature.fromBytes(blooms, offsets[i], bits(i))

    /** Anahtarın sırası; imzası yoksa -1. */
    fun indexOf(key: Long): Int {
        var lo = 0; var hi = keys.size - 1
        while (lo <= hi) {
            val mid = (lo + hi) ushr 1
            val c = java.lang.Long.compareUnsigned(keys[mid], key)
            when { c < 0 -> lo = mid + 1; c > 0 -> hi = mid - 1; else -> return mid }
        }
        return -1
    }

    companion object {
        /** [sortedKeys] işaretsiz sıralı bütün anahtarlar; [mask] imzalıların bit maskesi (bayt içinde düşük bit önce). */
        fun build(sortedKeys: LongArray, mask: ByteArray, lengths: ByteArray, blooms: ByteArray): FuzzyIndex? {
            if (mask.size * 8 < sortedKeys.size) return null
            val keys = ArrayList<Long>()
            for (i in sortedKeys.indices) if ((mask[i ushr 3].toInt() shr (i and 7)) and 1 == 1) keys += sortedKeys[i]
            if (keys.size != lengths.size) return null
            val lens = IntArray(lengths.size) { lengths[it].toInt() and 0xff }
            val offsets = IntArray(lens.size)
            var off = 0
            for (i in lens.indices) { offsets[i] = off; off += FuzzySignature.bitsFor(lens[i]) / 8 }
            if (off != blooms.size) return null
            return FuzzyIndex(keys.toLongArray(), lens, blooms, offsets)
        }
    }
}

/** Bloom'u [bits] boyuna katlanmış hâliyle verir (bellek ayırmadan). */
internal fun FuzzyIndex.bloomInto(i: Int, bits: Int, out: LongArray) {
    val b = bloom(i)
    java.util.Arrays.fill(out, 0, bits / 64, 0L)
    val n = bits / 64
    for (k in b.indices) out[k % n] = out[k % n] or b[k]
}
