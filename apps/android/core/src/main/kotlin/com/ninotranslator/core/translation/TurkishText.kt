// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.translation

import java.util.Locale

/** Türkçe metin kuralları: büyük harf düzeni, deyimler, son düzeltme, hitap birliği, ek kurma (ceviri.md 3.1, 4, 5.2). */
object TurkishText {
    val TR: Locale = Locale.forLanguageTag("tr-TR")

    // ---- büyük harf düzeni ----

    /** Tümü büyük harfli satır (en az 2 harf ve bir boşluk) cümle düzenine çevrilir; cümle başı, "I" ve adlar büyük kalır. */
    fun sentenceCase(text: String, names: Set<String> = emptySet()): String {
        val letters = text.count { it.isLetter() }
        if (letters < 2 || !text.contains(' ') || text.any { it.isLowerCase() }) return text
        val lowerNames = names.associateBy { it.lowercase(Locale.ROOT) }
        val out = StringBuilder()
        var startOfSentence = true
        val words = Regex("(\\p{L}[\\p{L}'’]*)|([^\\p{L}]+)").findAll(text)
        for (m in words) {
            val w = m.value
            if (!w[0].isLetter()) {
                out.append(w)
                if (w.any { it in ".!?…" }) startOfSentence = true
                continue
            }
            val low = w.lowercase(Locale.ROOT)
            val base = low.substringBefore('\'').substringBefore('’')
            val shaped = when {
                lowerNames.containsKey(low) -> lowerNames[low]!!
                lowerNames.containsKey(base) -> lowerNames[base]!! + low.substring(base.length)
                base == "i" -> "I" + low.substring(1)
                startOfSentence -> low.replaceFirstChar { it.uppercaseChar() }
                else -> low
            }
            out.append(if (startOfSentence) shaped.replaceFirstChar { it.uppercaseChar() } else shaped)
            startOfSentence = false
        }
        return out.toString()
    }

    // ---- oyun deyimleri ----

    /** Kodda sabit 9 oyun deyimi → düz İngilizce. */
    val IDIOMS: List<Pair<java.util.regex.Pattern, String>> = listOf(
        "friendlies" to "allies", "I've got your six" to "I've got your back", "check your six" to "watch behind you",
        "heads up" to "watch out", "took you long enough" to "you're late", "we've got company" to "enemies are coming",
        "lock and load" to "get ready", "sitting ducks" to "easy targets", "moving in" to "going in",
    ).map { (a, b) ->
        java.util.regex.Pattern.compile("(?<![\\p{L}\\p{N}])" + java.util.regex.Pattern.quote(a).replace("'", "\\E['’]\\Q") + "(?![\\p{L}\\p{N}])",
            java.util.regex.Pattern.CASE_INSENSITIVE or java.util.regex.Pattern.UNICODE_CASE) to b
    }

    fun applyIdioms(text: String): String {
        var s = text
        for ((p, rep) in IDIOMS) s = Glossary.replaceKeepingCase(p, s, rep)
        return s
    }

    // ---- son düzeltme (bölüm 4) ----

    private val SPACE_BEFORE_PUNCT = Regex("[ \\t\\u00A0]+(?=[,.!?;:…])")
    private val SPACES = Regex("[ \\t\\u00A0]{2,}")

    fun postProcess(translated: String, source: String): String {
        if (translated.none { it.isLetter() }) return translated
        var s = matchQuotes(translated, source)
        s = SPACE_BEFORE_PUNCT.replace(s, "")
        s = SPACES.replace(s, " ").trim()
        return keepEndMark(s, source)
    }

    private fun matchQuotes(t: String, source: String): String {
        var s = t
        s = if (source.contains('“') || source.contains('”')) curl(s, '"', '“', '”') else s.replace('“', '"').replace('”', '"')
        s = if (source.contains('‘') || source.contains('’')) curl(s, '\'', '‘', '’') else s.replace('‘', '\'').replace('’', '\'')
        return s
    }

    private fun curl(s: String, plain: Char, open: Char, close: Char): String {
        val out = StringBuilder(s.length)
        for (i in s.indices) {
            val c = s[i]
            if (c != plain) { out.append(c); continue }
            val prev = if (i > 0) s[i - 1] else ' '
            // Sözcük içindeki kesme kapanış biçimidir (Kratos’un).
            out.append(if (prev.isWhitespace() || prev in "([{—–-") open else close)
        }
        return out.toString()
    }

    private val CLOSING = "\"'”’»)]"

    private fun splitEnd(s: String): Triple<String, String, String> {
        // gövde, son işaret, kapanış işaretleri
        var e = s.length
        while (e > 0 && s[e - 1] in CLOSING) e--
        val closers = s.substring(e)
        var m = e
        while (m > 0 && s[m - 1] in ".!?…") m--
        return Triple(s.substring(0, m), s.substring(m, e), closers)
    }

    /** Kaynak `! ? … ...` ile bitiyor, çeviri işaretsiz ya da `.` ile bitiyorsa sonu kaynağınkiyle değiştirilir. */
    private fun keepEndMark(t: String, source: String): String {
        val (_, srcMark, srcClose) = splitEnd(source.trim())
        if (srcMark.isEmpty() || srcMark == "." || srcMark.none { it in "!?…" } && srcMark != "...") return t
        if (!(srcMark.contains('!') || srcMark.contains('?') || srcMark.contains('…') || srcMark == "...")) return t
        val (body, mark, close) = splitEnd(t)
        if ((srcClose.isEmpty()) != (close.isEmpty())) return t // işaret tırnağın içinde/dışında farklı
        if (mark.isNotEmpty() && mark != ".") return t
        return body + srcMark + close
    }

    // ---- hitap birliği (3.1/8) ----

    private val SEN = Regex("(?<![\\p{L}])(sen|seni|sana|senin|sende|senden|seninle|senle)(?![\\p{L}])", RegexOption.IGNORE_CASE)
    private val SIZ = Regex("(?<![\\p{L}])(siz|sizi|size|sizin|sizde|sizden|sizinle|sizle)(?![\\p{L}])", RegexOption.IGNORE_CASE)

    /** "siz"li emir → "sen"li emir (33 emir; çoğul da olabilen emirler yok). */
    val IMPERATIVES: List<Pair<String, String>> = listOf(
        "bekleyin" to "bekle", "durun" to "dur", "dikkat edin" to "dikkat et", "koşun" to "koş", "saklanın" to "saklan",
        "eğilin" to "eğil", "ateş edin" to "ateş et", "yardım edin" to "yardım et", "bakın" to "bak", "dinleyin" to "dinle",
        "susun" to "sus", "sakin olun" to "sakin ol", "acele edin" to "acele et", "takip edin" to "takip et",
        "söyleyin" to "söyle", "bırakın" to "bırak", "tutun" to "tut", "kaçın" to "kaç", "atlayın" to "atla",
        "gizlenin" to "gizlen", "yaklaşın" to "yaklaş", "uzaklaşın" to "uzaklaş", "nefes alın" to "nefes al",
        "dikkatli olun" to "dikkatli ol", "hazır olun" to "hazır ol", "devam edin" to "devam et",
        "endişelenmeyin" to "endişelenme", "korkmayın" to "korkma", "merak etmeyin" to "merak etme",
        "sessiz olun" to "sessiz ol", "beni takip edin" to "beni takip et", "buraya gelin" to "buraya gel",
        "ayağa kalkın" to "ayağa kalk",
    ).sortedByDescending { it.first.length }

    /** Satırın bir cümlesinde "sen" geçiyorsa "siz"li sözcük geçmeyen öbür cümlelerdeki bilinen emirler "sen"li olur. */
    fun unifyAddress(sentences: List<String>): List<String> {
        if (sentences.size < 2 || sentences.none { SEN.containsMatchIn(it) }) return sentences
        return sentences.map { s ->
            if (SEN.containsMatchIn(s) || SIZ.containsMatchIn(s)) s else {
                var r = s
                for ((from, to) in IMPERATIVES) {
                    r = Regex("(?<![\\p{L}])" + Regex.escape(from) + "(?![\\p{L}])", RegexOption.IGNORE_CASE).replace(r) { m ->
                        if (m.value[0].isUpperCase()) to.replaceFirstChar { it.uppercase(TR) } else to
                    }
                }
                r
            }
        }
    }

    // ---- ek kurma (5.2) ----

    private const val VOWELS = "aeıioöuüAEIİOÖUÜ"
    private const val BACK = "aıouAIOU"
    private const val ROUND = "oöuüOÖUÜ"
    private const val VOICELESS = "çfhkpsştÇFHKPSŞT"

    private fun lastVowel(word: String): Char? = word.lastOrNull { it in VOWELS }?.lowercaseChar()?.let { if (it == 'i' && word.lastOrNull { c -> c in VOWELS } == 'I') 'ı' else it }

    private fun syllables(word: String) = word.count { it in VOWELS }

    /**
     * Çevirmenin uydurma ada koyduğu eki Türkçe terime göre yeniden kurar.
     * [suffix] çevirmenin eki (kesmesiz); [proper] özel ad mı (kesmeyle ayrılır); [apostrophe] kullanılacak kesme.
     */
    fun attachSuffix(term: String, suffix: String, proper: Boolean, apostrophe: Char = '\''): String {
        if (suffix.isEmpty()) return term
        if (suffix.length > 12 || suffix.any { !it.isLetter() }) return term + apostrophe + suffix
        val lastWord = term.substringAfterLast(' ')
        val v = lastVowel(lastWord)
        // Ünlüsüz kısaltma (XP, HP) ince ünlüyle biter sayılır.
        val back = v != null && v in BACK
        val round = v != null && v in ROUND
        val endsVowel = lastWord.lastOrNull()?.let { it in VOWELS } == true || v == null
        val endsVoiceless = lastWord.lastOrNull()?.let { it in VOICELESS } == true && v != null
        val compound = term.contains(' ') && lastWord.lastOrNull()?.lowercaseChar()?.let { it in "ıiuü" } == true
        val s = suffix.lowercase(TR)

        val out = StringBuilder()
        for ((i, c) in s.withIndex()) {
            val r = when (c) {
                'a', 'e' -> if (back) 'a' else 'e'
                'ı', 'i', 'u', 'ü' -> when { back && round -> 'u'; back -> 'ı'; round -> 'ü'; else -> 'i' }
                'd', 't' -> if (i == 0) (if (endsVoiceless && !compound) 't' else 'd') else c
                else -> c
            }
            out.append(r)
        }
        var rebuilt = out.toString()
        val startsVowel = rebuilt.first() in VOWELS
        if (startsVowel && (endsVowel || compound)) {
            val genitive = rebuilt.length >= 2 && rebuilt[1] == 'n' && rebuilt[0] in "ıiuü"
            rebuilt = (if (compound || genitive) "n" else "y") + rebuilt
        } else if (compound && rebuilt.first() == 'd') {
            rebuilt = "n$rebuilt"
        } else if (endsVowel && rebuilt.startsWith("l") && rebuilt.length >= 2 && rebuilt[1] in "ae") {
            rebuilt = "y$rebuilt" // "-la" → "-yla"
        }
        if (proper) return term + apostrophe + rebuilt
        // Cins adda bitişik yazım ve yumuşama (tek heceli sözcük yumuşamaz).
        var base = term
        if (rebuilt.first() in VOWELS && !endsVowel && syllables(lastWord) > 1) {
            base = when {
                base.endsWith("nk") -> base.dropLast(1) + "g"
                base.endsWith("p") -> base.dropLast(1) + "b"
                base.endsWith("ç") -> base.dropLast(1) + "c"
                base.endsWith("k") -> base.dropLast(1) + "ğ"
                else -> base
            }
        }
        return base + rebuilt
    }

    fun capitalize(s: String): String = s.replaceFirstChar { it.uppercase(TR) }
}
