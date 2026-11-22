// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.translation

import com.ninotranslator.core.json.Json
import java.io.File
import java.io.RandomAccessFile
import java.security.MessageDigest

/**
 * Çevirmen başına önbellek dosyası (ceviri.md 8, veri-ve-ayarlar.md `Translations/`):
 * her satır `["anahtar","çeviri"]`, sonuna eklenir. Bellekte en çok [capacity] kayıt (en uzun süre kullanılmayan atılır).
 * Dosya satırı sınırın 2 katına ulaşınca, açılışta da kayıt sayısı + sınırın yarısını geçiyorsa yeniden yazılır.
 * Disk hatası çeviriyi durdurmaz. Aynı dosya uygulama içinde tek kez açılır ([open]).
 */
class LineCache private constructor(val file: File?, val capacity: Int) {
    private val map = object : LinkedHashMap<String, String>(1024, 0.75f, true) {}
    private var fileLines = 0
    @Volatile var diskFailed = false
        private set

    init { file?.let(::load) }

    @get:Synchronized val size: Int get() = map.size

    @Synchronized fun get(key: String): String? = map[key]

    @Synchronized fun put(key: String, value: String) {
        if (map[key] == value) return
        map[key] = value
        trim()
        append(key, value)
        if (fileLines >= capacity * 2) rewrite()
    }

    @Synchronized fun clear() {
        map.clear()
        rewrite()
    }

    private fun trim() {
        if (map.size <= capacity) return
        var drop = map.size - capacity + capacity / 10
        val it = map.entries.iterator()
        while (drop-- > 0 && it.hasNext()) { it.next(); it.remove() }
    }

    private fun load(f: File) {
        if (!f.isFile) return
        try {
            repairTornTail(f)
            f.bufferedReader(Charsets.UTF_8).useLines { lines ->
                for (line in lines) {
                    if (line.isBlank()) continue
                    fileLines++
                    val arr = runCatching { Json.parse(line) }.getOrNull() as? List<*> ?: continue
                    val k = arr.getOrNull(0) as? String ?: continue
                    val v = arr.getOrNull(1) as? String ?: continue
                    map.remove(k)
                    map[k] = v
                }
            }
            trim()
            if (fileLines > map.size + capacity / 2) rewrite()
        } catch (e: Exception) {
            diskFailed = true
        }
    }

    /** Yarım kalmış son satırı keser (sonraki kayıt çöpe karışmasın). */
    private fun repairTornTail(f: File) {
        RandomAccessFile(f, "rw").use { raf ->
            val len = raf.length()
            if (len == 0L) return
            raf.seek(len - 1)
            if (raf.read() == '\n'.code) return
            var pos = len - 1
            val buf = ByteArray(4096)
            while (pos > 0) {
                val start = maxOf(0L, pos - buf.size)
                raf.seek(start)
                val n = (pos - start).toInt()
                raf.readFully(buf, 0, n)
                for (i in n - 1 downTo 0) if (buf[i] == '\n'.code.toByte()) { raf.setLength(start + i + 1); return }
                pos = start
            }
            raf.setLength(0)
        }
    }

    private fun append(key: String, value: String) {
        val f = file ?: return
        try {
            f.parentFile?.mkdirs()
            f.appendText(Json.write(listOf(key, value)) + "\n", Charsets.UTF_8)
            fileLines++
        } catch (e: Exception) { diskFailed = true }
    }

    private fun rewrite() {
        val f = file ?: return
        try {
            f.parentFile?.mkdirs()
            val tmp = File(f.parentFile, f.name + ".tmp")
            tmp.bufferedWriter(Charsets.UTF_8).use { w -> for ((k, v) in map) { w.write(Json.write(listOf(k, v))); w.write("\n") } }
            java.nio.file.Files.move(tmp.toPath(), f.toPath(), java.nio.file.StandardCopyOption.REPLACE_EXISTING, java.nio.file.StandardCopyOption.ATOMIC_MOVE)
            fileLines = map.size
        } catch (e: Exception) { diskFailed = true }
    }

    companion object {
        const val CAPACITY = 20_000
        /** Anahtar parçaları arasındaki ayırıcı. */
        const val SEPARATOR = '\u001F'

        private val open = HashMap<String, LineCache>()

        /** `Translations/` altındaki dosya adı. */
        fun fileName(engine: String, source: String, target: String): String {
            val simple = Regex("[a-z0-9-]+")
            return if (simple.matches(engine) && simple.matches(source) && simple.matches(target)) {
                fun part(s: String) = s.map { if (it.isLetterOrDigit() || it == '_') it else '_' }.joinToString("")
                "v1-${part(engine)}-${part(source)}-${part(target)}.jsonl"
            } else {
                val d = MessageDigest.getInstance("SHA-256").digest("$engine\u0000$source\u0000$target".toByteArray(Charsets.UTF_8))
                "v1h-" + d.joinToString("") { "%02x".format(java.util.Locale.ROOT, it) } + ".jsonl"
            }
        }

        /** Aynı dosya için hep aynı nesne. [dir] = `files/Translations`. */
        fun open(dir: File, engine: String, target: String, source: String = "en", capacity: Int = CAPACITY): LineCache = synchronized(open) {
            val f = File(dir, fileName(engine, source, target))
            open.getOrPut(f.absolutePath) { LineCache(f, capacity) }
        }

        /** Yalnız bellekte (testler, disk yokken). */
        fun memory(capacity: Int = CAPACITY) = LineCache(null, capacity)

        /** Testler için: açık dosyaları unut. */
        fun forgetOpenFiles() = synchronized(open) { open.clear() }
    }
}
