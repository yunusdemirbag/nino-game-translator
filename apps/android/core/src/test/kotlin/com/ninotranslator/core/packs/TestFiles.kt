// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.packs

import com.ninotranslator.core.json.Json
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.Base64
import java.util.zip.GZIPOutputStream

/**
 * Testlerin okuduğu dosyalar: Nino'nun kendi paket deneme verisi (`src/test/resources/packs`, make_fixtures.py ile
 * üretilir) ve uygulamanın varlıkları (`nino.assets`: sözlük, model listesi).
 */
object TestFiles {
    val assets: File get() = File(System.getProperty("nino.assets") ?: error("nino.assets yok"))

    fun fixture(name: String): Any? = Json.parse(resource(name).readText())

    private fun resource(name: String) = TestFiles::class.java.getResource("/packs/$name") ?: error("deneme verisi yok: $name")

    private val cache = HashMap<String, LegacyPack>()
    @Synchronized fun pack(id: String): LegacyPack = cache.getOrPut(id) { resource("$id.json.gz").openStream().use { LegacyPack.load(it, id) } }

    fun packBytes(id: String): ByteArray = resource("$id.json.gz").readBytes()

    fun tempDir(): File = kotlin.io.path.createTempDirectory("nino-test").toFile().also { it.deleteOnExit() }

    fun gz(s: String): ByteArray = ByteArrayOutputStream().also { o -> GZIPOutputStream(o).use { it.write(s.toByteArray()) } }.toByteArray()

    /** Büyük deneme paketi (hız testi): satırlar + bulanık imzalar, biçim 2. */
    fun bigPack(id: String, lines: List<Pair<String, String>>): ByteArray {
        val byKey = java.util.TreeMap<Long, String>(java.lang.Long::compareUnsigned)
        val entries = LinkedHashMap<String, String>()
        for ((en, tr) in lines) { val k = PackKey.longOf(en) ?: continue; byKey[k] = en; entries[PackKey.hex(k)] = tr }
        val mask = ByteArray((byKey.size + 7) / 8)
        val lengths = ByteArrayOutputStream(); val blooms = ByteArrayOutputStream()
        byKey.values.forEachIndexed { i, en ->
            val f = FuzzySignature.fold(en)
            val n = FuzzySignature.lengthOf(f)
            if (n < FuzzySignature.MIN_LENGTH) return@forEachIndexed
            mask[i ushr 3] = (mask[i ushr 3].toInt() or (1 shl (i and 7))).toByte()
            lengths.write(n); blooms.write(FuzzySignature.toBytes(FuzzySignature.bloom(f)))
        }
        val b64 = Base64.getEncoder()
        val json = Json.write(linkedMapOf(
            "format" to 2, "id" to id, "title" to id, "entries" to entries,
            "fuzzy" to linkedMapOf("version" to 1, "count" to byKey.size, "mask" to b64.encodeToString(mask),
                "lengths" to b64.encodeToString(lengths.toByteArray()), "blooms" to b64.encodeToString(blooms.toByteArray())),
        ))
        return gz(json)
    }
}
