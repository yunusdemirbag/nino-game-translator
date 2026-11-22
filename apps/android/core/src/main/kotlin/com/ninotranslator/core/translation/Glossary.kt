// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.translation

import com.ninotranslator.core.json.Json
import java.io.File
import java.util.Locale
import java.util.regex.Pattern

/**
 * Terim sözlüğü (ceviri.md 5.1): `terms`, `keep`, `keepExact`, `phrases`, `lines`. Yalnız hedef Türkçeyken kullanılır.
 * Uygulamayla gelen `glossary-en-tr.json` (Nino'nun kendi dosyası) + `files/glossary` içindeki JSON dosyaları (ada göre); aynı terimde sonraki dosya kazanır.
 */
class Glossary private constructor(
    /** küçük harfli terim → (yazıldığı hâl, Türkçe) */
    private val terms: Map<String, Pair<String, String>>,
    private val keep: Set<String>,
    private val keepExact: Set<String>,
    private val phraseRules: List<Pair<String, String>>,
    private val lineMap: Map<String, String>,
) {
    /** Metinde bulunan terim. [target] Türkçe karşılık (korunan adda kendisi). */
    data class Hit(val start: Int, val end: Int, val source: String, val target: String, val kept: Boolean)

    val isEmpty: Boolean get() = terms.isEmpty() && keep.isEmpty() && keepExact.isEmpty() && phraseRules.isEmpty() && lineMap.isEmpty()
    val termCount: Int get() = terms.size
    val lineCount: Int get() = lineMap.size

    private val compiled: List<Pair<Pattern, String>> = phraseRules.mapNotNull { (re, rep) ->
        runCatching { Pattern.compile("(?<![\\p{L}\\p{N}])(?:$re)(?![\\p{L}\\p{N}])", Pattern.CASE_INSENSITIVE or Pattern.UNICODE_CASE) to rep }.getOrNull()
    }

    private val matchers: List<Triple<String, String, Int>> = run {
        // (terim, Türkçe, tür: 0 terim, 1 keep, 2 keepExact) uzun önce
        val all = ArrayList<Triple<String, String, Int>>()
        for ((_, v) in terms) all += Triple(v.first, v.second, 0)
        for (k in keep) all += Triple(k, k, 1)
        for (k in keepExact) all += Triple(k, k, 2)
        all.sortedByDescending { it.first.length }
    }

    /** Sözlüğün izi: FNV-1a 32, "g" + 8 hex. Sözlük değişince terimli satırlar yeniden çevrilir. */
    val fingerprint: String = run {
        var h = 0x811c9dc5.toInt()
        fun feed(s: String) { for (b in s.toByteArray(Charsets.UTF_8)) { h = h xor (b.toInt() and 0xff); h *= 0x01000193 }; h = h xor 0; h *= 0x01000193 }
        for (k in terms.keys.sorted()) { feed(k); feed(terms[k]!!.second) }
        for (k in keep.sorted()) feed("k:$k")
        for (k in keepExact.sorted()) feed("K:$k")
        for ((a, b) in phraseRules) { feed("p:$a"); feed(b) }
        for (k in lineMap.keys.sorted()) { feed("l:$k"); feed(lineMap[k]!!) }
        "g" + Integer.toHexString(h).padStart(8, '0')
    }

    /** Metindeki terimler: tam sözcükte, uzun önce, çakışan kısa alınmaz; büyük/küçük harfe bakmaz (keepExact hariç). */
    fun find(text: String): List<Hit> {
        val taken = BooleanArray(text.length)
        val hits = ArrayList<Hit>()
        for ((term, target, kind) in matchers) {
            var from = 0
            while (from <= text.length - term.length) {
                val at = indexOf(text, term, from, ignoreCase = kind != 2)
                if (at < 0) break
                val end = at + term.length
                if (boundary(text, at, end) && (at until end).none { taken[it] }) {
                    for (i in at until end) taken[i] = true
                    val src = text.substring(at, end)
                    hits += Hit(at, end, src, if (kind == 0) target else src, kind != 0)
                }
                from = at + 1
            }
        }
        return hits.sortedBy { it.start }
    }

    private fun indexOf(text: String, term: String, from: Int, ignoreCase: Boolean): Int {
        for (i in from..text.length - term.length) if (text.regionMatches(i, term, 0, term.length, ignoreCase)) return i
        return -1
    }

    private fun boundary(s: String, start: Int, end: Int): Boolean =
        (start == 0 || !s[start - 1].isLetterOrDigit()) && (end >= s.length || !s[end].isLetterOrDigit())

    /** Argo düzeltmeleri (düzenli ifade → düz İngilizce); eşleşmenin baş harfi büyükse karşılığınınki de büyük. */
    fun applyPhrases(text: String): String {
        var s = text
        for ((p, rep) in compiled) s = replaceKeepingCase(p, s, rep)
        return s
    }

    /** Büyük harfle kalacak adlar: büyük harfli terimlerin sözcükleri. */
    val properWords: Set<String> = run {
        val out = HashSet<String>()
        for ((_, v) in terms) if (v.first.firstOrNull()?.isUpperCase() == true) v.first.split(' ').forEach { out += it }
        for (k in keep + keepExact) k.split(' ').filter { it.firstOrNull()?.isUpperCase() == true }.forEach { out += it }
        out
    }

    /** Kısa satırın hazır Türkçesi; Türkçede son işaret yoksa kaynağınki eklenir. */
    fun line(text: String): String? {
        val tr = lineMap[lineKey(text)] ?: return null
        val end = text.trimEnd().let { t -> Regex("[.!?…]+$").find(t)?.value }
        return if (end != null && tr.trimEnd().lastOrNull()?.let { it in ".!?…" } != true) tr.trimEnd() + end else tr
    }

    companion object {
        val EMPTY = Glossary(emptyMap(), emptySet(), emptySet(), emptyList(), emptyMap())
        private val SPACES = Regex("\\s+")

        fun lineKey(text: String): String {
            val s = SPACES.replace(text.lowercase(Locale.ROOT).replace('’', '\'').replace('‘', '\''), " ").trim()
            var a = 0; var b = s.length
            while (a < b && !s[a].isLetterOrDigit()) a++
            while (b > a && !s[b - 1].isLetterOrDigit()) b--
            return s.substring(a, b)
        }

        internal fun replaceKeepingCase(p: Pattern, s: String, rep: String): String {
            val m = p.matcher(s)
            if (!m.find()) return s
            val out = StringBuilder()
            var last = 0
            do {
                out.append(s, last, m.start())
                val first = m.group().firstOrNull()
                out.append(if (first != null && first.isUpperCase() && rep.isNotEmpty()) rep[0].uppercaseChar() + rep.substring(1) else rep)
                last = m.end()
            } while (m.find())
            out.append(s, last, s.length)
            return out.toString()
        }

        private class Parts {
            val terms = LinkedHashMap<String, Pair<String, String>>()
            val keep = LinkedHashSet<String>(); val keepExact = LinkedHashSet<String>()
            val phrases = LinkedHashMap<String, String>(); val lines = LinkedHashMap<String, String>()
        }

        private fun mergeInto(p: Parts, text: String) {
            val root = Json.parseObject(text)
            (root["terms"] as? Map<*, *>)?.forEach { (k, v) ->
                val en = (k as? String)?.let { SPACES.replace(it, " ").trim() } ?: return@forEach
                val tr = (v as? String)?.trim() ?: return@forEach
                if (en.none { it.isLetter() } || en.length > 80 || tr.isEmpty()) return@forEach
                p.terms[en.lowercase(Locale.ROOT)] = en to tr
            }
            fun names(key: String, into: MutableSet<String>) = (root[key] as? List<*>)?.forEach { v ->
                (v as? String)?.let { SPACES.replace(it, " ").trim() }?.takeIf { n -> n.any { it.isLetter() } && n.length <= 80 }?.let { into += it }
            }
            names("keep", p.keep); names("keepExact", p.keepExact)
            (root["phrases"] as? Map<*, *>)?.forEach { (k, v) -> if (k is String && v is String && k.isNotEmpty()) p.phrases[k] = v }
            (root["lines"] as? Map<*, *>)?.forEach { (k, v) -> if (k is String && v is String && v.isNotBlank()) lineKey(k).takeIf { it.isNotEmpty() }?.let { p.lines[it] = v.trim() } }
        }

        private fun build(p: Parts) = Glossary(
            p.terms, p.keep, p.keepExact,
            // Bayt sırasıyla.
            p.phrases.entries.sortedWith { a, b -> compareBytes(a.key, b.key) }.map { it.key to it.value },
            p.lines,
        )

        private fun compareBytes(a: String, b: String): Int {
            val x = a.toByteArray(Charsets.UTF_8); val y = b.toByteArray(Charsets.UTF_8)
            for (i in 0 until minOf(x.size, y.size)) { val c = (x[i].toInt() and 0xff) - (y[i].toInt() and 0xff); if (c != 0) return c }
            return x.size - y.size
        }

        fun parse(text: String): Glossary = Parts().also { mergeInto(it, text) }.let(::build)

        /** Gömülü metin + klasördeki JSON dosyaları (ada göre); bozuk dosya atlanır. */
        fun load(embedded: String?, userDir: File?): Glossary {
            val p = Parts()
            embedded?.let { runCatching { mergeInto(p, it) } }
            userDir?.listFiles().orEmpty().filter { it.isFile && it.name.endsWith(".json") }.sortedBy { it.name }
                .forEach { f -> runCatching { mergeInto(p, f.readText()) } }
            return build(p)
        }
    }
}
