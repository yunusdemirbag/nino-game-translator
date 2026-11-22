// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.pool

import com.ninotranslator.core.json.Json
import com.ninotranslator.core.translation.LineText
import java.io.File
import java.net.URLEncoder
import java.text.Normalizer
import java.util.UUID

/** Havuz sunucusunun adresi ve tanıtım başlığı (ceviri.md 6). */
object PoolEndpoint {
    const val DEFAULT = "https://nino-pool.y-demirbag2506.workers.dev"

    /** `files/pool/endpoint.txt` `http://` ya da `https://` ile başlayan bir adres içeriyorsa o (deneme sunucusu). */
    fun resolve(filesDir: File): String {
        val f = File(filesDir, "pool/endpoint.txt")
        val v = runCatching { f.readText().trim() }.getOrNull()
        return if (v != null && (v.startsWith("http://") || v.startsWith("https://"))) v.trimEnd('/') else DEFAULT
    }

    fun userAgent(appVersion: String) = "nino-pool/1 (android; $appVersion)"

    fun query(vararg pairs: Pair<String, String?>): String = pairs.filter { it.second != null }
        .joinToString("&") { (k, v) -> k + "=" + URLEncoder.encode(v, "UTF-8").replace("+", "%20") }
}

/**
 * Tek kurulum kimliği (veri-ve-ayarlar.md §1.3): havuz, satır kuyruğu, sorun bildirimi ve ölçüm aynı UUID'yi kullanır.
 * Seçim sırası: `pool/state.json`'daki `install`, eski yedek ([resolve]'un `legacy`'si, `report` ayarı),
 * `translation-pool/install`; ilk geçerli UUID (büyük harfliyse küçültülür). Hiçbiri UUID değilse yenisi üretilir.
 * Seçilen kimlik `translation-pool/install`'a ve (varsa) `pool/state.json`'a yazılır; dosyanın öteki alanları korunur.
 */
object PoolInstall {
    private val lock = Any()

    fun resolve(filesDir: File, legacy: String? = null): String = synchronized(lock) {
        val stateFile = File(filesDir, "pool/state.json")
        val state = runCatching { Json.parseObject(stateFile.readText()) }.getOrNull()
        val installFile = File(filesDir, "translation-pool/install")
        val fromFile = runCatching { installFile.readText().trim() }.getOrNull()
        val id = sequenceOf(state?.get("install") as? String, legacy, fromFile).firstNotNullOfOrNull(::normalize)
            ?: UUID.randomUUID().toString()
        if (fromFile != id) runCatching { installFile.parentFile?.mkdirs(); installFile.writeText(id) }
        if (state != null && state["install"] != id) runCatching {
            val m = LinkedHashMap<String, Any?>()
            state.forEach { (k, v) -> m[k.toString()] = v }
            m["install"] = id
            val tmp = File(stateFile.parentFile, stateFile.name + ".tmp")
            tmp.writeText(Json.write(m))
            java.nio.file.Files.move(tmp.toPath(), stateFile.toPath(), java.nio.file.StandardCopyOption.REPLACE_EXISTING,
                java.nio.file.StandardCopyOption.ATOMIC_MOVE)
        }
        id
    }

    /** Eski adı; [resolve] ile aynı. */
    fun read(filesDir: File): String = resolve(filesDir)

    /** Geçerli UUID ise küçük harfli hali, değilse null. */
    fun normalize(v: String?): String? = v?.trim()?.lowercase()?.takeIf(::isUuid)

    fun isUuid(v: String) = v.length == 36 && v == v.lowercase() && runCatching { UUID.fromString(v) }.isSuccess
}

/** Havuza gidecek satırın temizliği ve süzgeci (ceviri.md 6.6; çalışan gevşek süzgeç). */
object PoolLineFilter {
    const val MAX_CODE_POINTS = 500

    val SYSTEM_TEXT = listOf(
        "signed in", "signed out", "earned a trophy", "trophy unlocked", "screenshot saved", "video clip saved",
        "joined the party", "left the party", "is now online", "remote play", "controller disconnected", "press the ps button",
        "playstation network", "download complete", "update available", "oturum acti", "oturum kapatti", "lutfen bekleyin",
        "yeniden baslat",
    )

    /** Denetim ve sıfır genişlikli karakterler, satır/paragraf ayırıcıları boşluk olur; boşluklar teklenir. */
    fun clean(text: String): String {
        val b = StringBuilder(text.length)
        var space = false
        var i = 0
        while (i < text.length) {
            val cp = text.codePointAt(i)
            i += Character.charCount(cp)
            val blank = Character.isISOControl(cp) || Character.isWhitespace(cp) || Character.isSpaceChar(cp) ||
                cp == 0x200B || cp == 0x200C || cp == 0x200D || cp == 0x2060 || cp == 0xFEFF || cp == 0x2028 || cp == 0x2029
            if (blank) { space = b.isNotEmpty() } else {
                if (space) { b.append(' '); space = false }
                b.appendCodePoint(cp)
            }
        }
        return b.toString()
    }

    /** Temizlenmiş satır havuza uygun mu. */
    fun accepts(cleaned: String): Boolean {
        if (cleaned.none { it.isLetter() }) return false
        if (cleaned.codePointCount(0, cleaned.length) > MAX_CODE_POINTS) return false
        if (isJunk(cleaned)) return false
        if (LineText.hasTurkishLetters(cleaned)) return false
        if (isSystemText(cleaned)) return false
        return true
    }

    /** OCR çöpü: harf sayısı × 2 görünür karakter sayısından az. */
    fun isJunk(s: String): Boolean {
        val visible = s.count { !it.isWhitespace() }
        val letters = s.count { it.isLetter() }
        return letters * 2 < visible
    }

    fun isSystemText(s: String): Boolean {
        val plain = Normalizer.normalize(s.lowercase(), Normalizer.Form.NFD).replace(Regex("\\p{M}"), "").replace('ı', 'i')
        return SYSTEM_TEXT.any { Regex("(?<![\\p{L}\\p{N}])" + Regex.escape(it) + "(?![\\p{L}\\p{N}])").containsMatchIn(plain) }
    }
}
