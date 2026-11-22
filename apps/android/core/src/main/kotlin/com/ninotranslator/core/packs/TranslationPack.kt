// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.packs

import com.ninotranslator.core.json.Json
import com.ninotranslator.core.json.int
import com.ninotranslator.core.json.list
import com.ninotranslator.core.json.obj
import com.ninotranslator.core.json.str
import com.ninotranslator.core.reading.TextSimilarity
import com.ninotranslator.core.translation.PhraseLookup
import com.ninotranslator.core.translation.Term
import com.ninotranslator.core.translation.TranslationKey
import java.io.File

/** Oyuna özel hazır çeviri paketi (NinoCore docs/tarif/paket.md). Değişmez; oluşturulunca dizinlenir. */
class TranslationPack(
    val game: Game,
    val languages: Languages = Languages(),
    override val terms: List<Term> = emptyList(),
    lines: List<Line>,
) : PhraseLookup {
    data class Game(val id: String, val title: String? = null, val version: String? = null)
    data class Languages(val source: String = "en", val target: String = "tr")
    data class Line(val source: String, val target: String, val speaker: String? = null)

    sealed class LoadException(message: String) : Exception(message) {
        class UnsupportedVersion(val version: Int) : LoadException("unsupportedVersion($version)")
        class BadGameId(val id: String) : LoadException("badGameID($id)")
        class InvalidJson(reason: String) : LoadException("invalidJSON($reason)")
    }

    val lines: List<Line>
    /** Yüklemede atlanan satır sayısı. */
    val warnings: Int
    private val exact = HashMap<String, Int>()
    private val fuzzyKeys: List<String>
    private val wordIndex = HashMap<String, MutableList<Int>>()

    init {
        if (!isValidGameId(game.id)) throw LoadException.BadGameId(game.id)
        val kept = ArrayList<Line>(lines.size)
        var warn = 0
        for (line in lines) {
            val s = line.source.trim()
            val t = line.target.trim()
            if (s.isEmpty() || t.isEmpty()) { warn++; continue }
            val key = TranslationKey.make(s)
            if (exact.containsKey(key)) { warn++; continue }
            exact[key] = kept.size
            kept += Line(s, t, line.speaker)
        }
        this.lines = kept
        warnings = warn
        fuzzyKeys = kept.map { TextSimilarity.key(it.source) }
        fuzzyKeys.forEachIndexed { i, k -> for (w in k.split(' ').toSet()) if (w.isNotEmpty()) wordIndex.getOrPut(w) { ArrayList() } += i }
    }

    override fun lookup(sentence: String): String? = match(sentence)?.target

    /** Önce tam, sonra bulanık eşleme. */
    fun match(sentence: String): Line? = exact[TranslationKey.make(sentence)]?.let { lines[it] } ?: fuzzyMatch(sentence)

    internal fun fuzzyMatch(sentence: String): Line? {
        val key = TextSimilarity.key(sentence)
        if (key.length < FUZZY_MIN_LENGTH) return null
        val words = key.split(' ').filter { it.isNotEmpty() }.toSet()
        val question = isQuestion(sentence)
        val shared = sortedMapOf<Int, Int>()
        for (w in words) for (i in wordIndex[w].orEmpty()) shared[i] = (shared[i] ?: 0) + 1
        var best = -1
        var bestScore = 0.0
        for ((i, count) in shared) {
            val candidate = fuzzyKeys[i]
            val candidateWords = candidate.split(' ').size
            if (count * 2 < maxOf(words.size, candidateWords)) continue
            val ratio = candidate.length.toDouble() / key.length
            if (ratio < 0.8 || ratio > 1.25) continue
            if (isQuestion(lines[i].source) != question) continue
            val score = TextSimilarity.ratioOfKeys(key, candidate)
            if (score < FUZZY_THRESHOLD) continue
            if (best < 0 || score > bestScore) { best = i; bestScore = score }
        }
        return if (best >= 0) lines[best] else null
    }

    fun encode(): String = Json.write(sortedMapOf<String, Any?>(
        "nino" to FORMAT_VERSION,
        "game" to sortedMapOf<String, Any?>("id" to game.id).apply { game.title?.let { put("title", it) }; game.version?.let { put("version", it) } },
        "languages" to sortedMapOf("source" to languages.source, "target" to languages.target),
        "terms" to terms.map { t -> sortedMapOf<String, Any?>("source" to t.source).apply { t.target?.let { put("target", it) } } },
        "lines" to lines.map { l -> sortedMapOf<String, Any?>("source" to l.source, "target" to l.target).apply { l.speaker?.let { put("speaker", it) } } },
    ), pretty = true)

    companion object {
        const val FORMAT_VERSION = 1
        const val FILE_EXTENSION = "ninopack.json"
        const val FUZZY_MIN_LENGTH = 12
        const val FUZZY_THRESHOLD = 0.90

        fun isValidGameId(id: String) = id.isNotEmpty() && id.all { it in 'a'..'z' || it in '0'..'9' || it == '-' || it == '.' }

        private fun isQuestion(s: String) = s.trim().trimEnd('"', '\'', '”', '’', ')', ']').trimEnd().endsWith("?")

        fun parse(text: String): TranslationPack {
            val root = try { Json.parseObject(text) } catch (e: Exception) { throw LoadException.InvalidJson(e.message ?: "json") }
            val version = root.int("nino") ?: throw LoadException.InvalidJson("nino yok")
            if (version != FORMAT_VERSION) throw LoadException.UnsupportedVersion(version)
            val g = root.obj("game") ?: throw LoadException.InvalidJson("game yok")
            val game = Game(g.str("id") ?: throw LoadException.InvalidJson("game.id yok"), g.str("title"), g.str("version"))
            val langs = root.obj("languages")?.let { Languages(it.str("source") ?: "en", it.str("target") ?: "tr") } ?: Languages()
            @Suppress("UNCHECKED_CAST")
            val terms = root.list("terms").orEmpty().mapNotNull { (it as? Map<String, Any?>)?.let { m -> m.str("source")?.let { s -> Term(s, m.str("target")) } } }
            val rawLines = root.list("lines") ?: throw LoadException.InvalidJson("lines yok")
            @Suppress("UNCHECKED_CAST")
            val lines = rawLines.map { item ->
                val m = item as? Map<String, Any?> ?: throw LoadException.InvalidJson("satır nesne değil")
                Line(m.str("source") ?: throw LoadException.InvalidJson("source yok"), m.str("target") ?: throw LoadException.InvalidJson("target yok"), m.str("speaker"))
            }
            return TranslationPack(game, langs, terms, lines)
        }

        fun load(file: File) = parse(file.readText())
    }
}

/** Klasördeki paketleri yükler ve oyun kimliğine göre verir. */
class PackLibrary(packs: List<TranslationPack> = emptyList()) {
    data class Failure(val file: String, val reason: String)

    private val byGame = HashMap<String, TranslationPack>()
    val failures = ArrayList<Failure>()

    init { packs.forEach(::add) }

    val gameIds: List<String> get() = byGame.keys.sorted()
    fun pack(gameId: String): TranslationPack? = byGame[gameId]

    fun add(pack: TranslationPack) {
        val existing = byGame[pack.game.id]
        if (existing != null && compareVersions(existing.game.version, pack.game.version) >= 0) return
        byGame[pack.game.id] = pack
    }

    companion object {
        fun fromDirectory(dir: File): PackLibrary {
            val lib = PackLibrary()
            dir.listFiles().orEmpty().filter { it.name.endsWith("." + TranslationPack.FILE_EXTENSION) }.sortedBy { it.name }.forEach { f ->
                try { lib.add(TranslationPack.load(f)) } catch (e: Exception) { lib.failures += Failure(f.name, e.message ?: e.javaClass.simpleName) }
            }
            return lib
        }

        fun compareVersions(a: String?, b: String?): Int {
            val x = (a ?: "0").split('.').map { it.toIntOrNull() ?: 0 }
            val y = (b ?: "0").split('.').map { it.toIntOrNull() ?: 0 }
            for (i in 0 until maxOf(x.size, y.size)) {
                val l = x.getOrElse(i) { 0 }
                val r = y.getOrElse(i) { 0 }
                if (l != r) return l.compareTo(r)
            }
            return 0
        }
    }
}
