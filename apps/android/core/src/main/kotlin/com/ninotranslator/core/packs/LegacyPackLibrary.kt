// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.packs

import com.ninotranslator.core.translation.LineText

/**
 * Yüklü eski paketler ve satır araması (ceviri.md 9.2, 9.3).
 * [packs] yükleme sırasında; aynı kimlik sonra gelirse öncekinin yerine geçer. Arama sondan başa.
 */
class LegacyPackLibrary(packs: List<LegacyPack>) {
    private val split: Pair<List<LegacyPack>, List<LegacyPack>> = run {
        val byId = LinkedHashMap<String, LegacyPack>()
        for (p in packs) { byId.remove(p.id); byId[p.id] = p }
        // Aynı oyunun havuz paketi (pool-…) varsa eski/gömülü paket devre dışı kalır (dosyası silinmez). Aynı oyun:
        // başlık ya da asıl kimlik tutuyor ([GameIds]: "gta-6" = "pool-gta-6" = "grand-theft-auto-vi").
        val poolGames = byId.values.filter { it.id.startsWith(POOL_PREFIX) }.flatMap { GameIds.packKeys(it.id, it.title) }.toSet()
        byId.values.partition { it.id.startsWith(POOL_PREFIX) || GameIds.packKeys(it.id, it.title).none { k -> k in poolGames } }
    }

    val packs: List<LegacyPack> = split.first

    /** Havuz paketi yüzünden devre dışı kalan eski/gömülü paketler (Paketler ekranında aynı oyunun kartına bağlanır). */
    val shadowed: List<LegacyPack> = split.second

    data class Match(
        val text: String,
        val packId: String,
        val fuzzy: Boolean,
        /** Satır yalnız bu pakette bulundu (oyunu tahmin etmek için). */
        val uniquePack: Boolean,
    )

    /** Son tam eşleşmenin geldiği paket (bulanık arama yalnız onda). */
    @Volatile var playedPackId: String? = null

    /** Yalnız tek pakette bulunan son satırın paketi. */
    @Volatile var guessedPackId: String? = null
        private set

    fun pack(id: String): LegacyPack? = packs.firstOrNull { it.id == id }

    companion object {
        /** Havuzun ürettiği paketlerin kimlik öneki. */
        const val POOL_PREFIX = "pool-"
    }

    /** Elle seçilen oyunun paketi (ad ya da kimlik eşleşmesi). */
    fun packForGame(game: String): LegacyPack? {
        val g = game.trim()
        if (g.isEmpty()) return null
        return packs.lastOrNull { it.id.equals(g, true) || it.title.equals(g, true) }
            ?: PackKey.canonical(g).let { c -> packs.lastOrNull { PackKey.canonical(it.title) == c || PackKey.canonical(it.id) == c } }
            ?: GameIds.fromAny(g)?.let { c -> packs.lastOrNull { GameIds.ofPack(it.id) == c || GameIds.fromAny(it.title) == c } }
    }

    /**
     * Satırı arar. [manualGame] verildiyse yalnız o oyunun paketinde (paketi yoksa hiç aranmaz).
     * [showSpeakerNames] kapalıysa konuşan adı çeviriden atılır.
     */
    fun find(line: String, manualGame: String? = null, showSpeakerNames: Boolean = true): Match? {
        val scope: List<LegacyPack> = if (manualGame != null) listOfNotNull(packForGame(manualGame)) else packs
        if (scope.isEmpty()) return null
        val played = (if (manualGame != null) scope.first() else playedPackId?.let(::pack))
        val text = line.trim()
        if (text.isEmpty()) return null
        val search = Search(scope, played, showSpeakerNames)
        val result = search.round(text, fuzzy = false) ?: if (played != null) search.round(text, fuzzy = true) else null
        result ?: return null
        if (LineText.hasTurkishLetters(text) && PackKey.canonical(result.text) == PackKey.canonical(text)) return null
        if (!result.fuzzy) {
            playedPackId = result.packId
            if (result.uniquePack) guessedPackId = result.packId
        }
        return result
    }

    private inner class Search(val scope: List<LegacyPack>, val played: LegacyPack?, val showSpeaker: Boolean) {
        var anyFuzzy = false
        var lastPack: String? = null
        var unique = true

        fun piece(text: String, fuzzy: Boolean): String? {
            val key = PackKey.longOf(text) ?: return null
            exact(key)?.let { return it }
            if (!fuzzy || played == null) return null
            val hit = FuzzyMatcher.singleCorrection(text, played) ?: FuzzyMatcher.signature(text, played)?.text ?: return null
            anyFuzzy = true
            lastPack = played.id
            return hit
        }

        fun exact(key: Long): String? {
            // Önce bütün paketlerin tam satırları, sonra bütün paketlerin parçaları.
            var found: String? = null
            var from: LegacyPack? = null
            for (p in scope.asReversed()) { val t = p.entry(key); if (t != null) { found = t; from = p; break } }
            if (found == null) for (p in scope.asReversed()) { val t = p.segment(key); if (t != null) { found = t; from = p; break } }
            if (found == null || from == null) return null
            if (scope.count { it.anyLine(key) != null } > 1) unique = false
            lastPack = from.id
            return found
        }

        /** Satırın tamamı: etiketsiz gövde, tamamı, bozuk etiketsiz gövde. */
        fun whole(text: String, fuzzy: Boolean): String? {
            val prefix = LineText.prefix(text)
            if (prefix != null) piece(prefix.body, fuzzy)?.let { return withPrefix(prefix.prefix, it) }
            piece(text, fuzzy)?.let { return it }
            val loose = LineText.looseLabel(text)
            if (loose != null && loose.body.isNotBlank()) piece(loose.body, fuzzy)?.let { return it }
            return null
        }

        fun withPrefix(prefix: String, translation: String): String {
            val rest = prefix.trimStart('-', '–', '—', '‐', ' ', '\t')
            if (!showSpeaker && LineText.speakerLabel(rest + "x") != null) return prefix.substring(0, prefix.length - rest.length) + translation
            return prefix + translation
        }

        fun round(text: String, fuzzy: Boolean): Match? {
            anyFuzzy = false; unique = true; lastPack = null
            val joined = text.lines().map { it.trim() }.filter { it.isNotEmpty() }
            val flat = joined.joinToString(" ")
            whole(flat, fuzzy)?.let { return done(it) }
            if (joined.size > 1) {
                val out = ArrayList<String>()
                var ok = true
                for (l in joined) {
                    val t = whole(l, fuzzy) ?: bySentence(l, fuzzy)
                    if (t != null) out += t else if (!LineText.isCornerText(l)) { ok = false; break }
                }
                if (ok && out.isNotEmpty()) return done(out.joinToString("\n"))
            }
            bySentence(flat, fuzzy)?.let { return done(it) }
            return null
        }

        fun bySentence(text: String, fuzzy: Boolean): String? {
            val prefix = LineText.prefix(text)
            val body = prefix?.body ?: text
            val parts = LineText.sentences(body)
            if (parts.size < 2) return null
            val out = ArrayList<String>()
            for (p in parts) out += piece(p, fuzzy) ?: return null
            val t = out.joinToString(" ")
            return if (prefix != null) withPrefix(prefix.prefix, t) else t
        }

        fun done(text: String) = Match(text, lastPack ?: scope.last().id, anyFuzzy, unique)
    }
}
