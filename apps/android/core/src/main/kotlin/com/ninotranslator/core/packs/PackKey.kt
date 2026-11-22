// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.packs

import java.security.MessageDigest
import java.text.Normalizer

/**
 * Paket ve havuz anahtarı (ceviri.md 8.2): sadeleştirilmiş satırın SHA-256 özetinin ilk 8 baytı, 16 haneli hex.
 * Mac, Windows ve havuzun paket üreticisiyle birebir aynı olmalı (deneme verisi: test/resources/packs/key-vectors.json).
 */
object PackKey {
    private val TAG = Regex("<[^<>]{0,40}>")

    /** Sadeleştirilmiş metin; harf/rakam yoksa boş. */
    fun canonical(text: String): String {
        var s = TAG.replace(text, " ")
        s = Normalizer.normalize(s, Normalizer.Form.NFKC)
        s = s.lowercase()
        s = Normalizer.normalize(s, Normalizer.Form.NFD)
        val out = StringBuilder(s.length)
        var space = true
        var i = 0
        while (i < s.length) {
            val cp = s.codePointAt(i)
            i += Character.charCount(cp)
            val type = Character.getType(cp)
            if (type == Character.NON_SPACING_MARK.toInt() || type == Character.ENCLOSING_MARK.toInt() || type == Character.COMBINING_SPACING_MARK.toInt()) continue
            if (Character.isLetterOrDigit(cp)) { out.appendCodePoint(cp); space = false }
            else if (!space) { out.append(' '); space = true }
        }
        if (out.isNotEmpty() && out[out.length - 1] == ' ') out.setLength(out.length - 1)
        return out.toString()
    }

    /** 16 haneli anahtar; satırda harf/rakam yoksa null. */
    fun of(text: String): String? = canonical(text).takeIf { it.isNotEmpty() }?.let(::ofCanonical)

    fun ofCanonical(canonical: String): String = hex(longOfCanonical(canonical))

    fun longOf(text: String): Long? = canonical(text).takeIf { it.isNotEmpty() }?.let(::longOfCanonical)

    fun longOfCanonical(canonical: String): Long {
        val d = MessageDigest.getInstance("SHA-256").digest(canonical.toByteArray(Charsets.UTF_8))
        var v = 0L
        for (i in 0 until 8) v = (v shl 8) or (d[i].toLong() and 0xff)
        return v
    }

    fun hex(key: Long): String = java.lang.Long.toHexString(key).padStart(16, '0')

    /** 16 haneli hex anahtarı sayıya çevirir (büyük harf kabul); geçersizse null. */
    fun parse(hex: String): Long? {
        if (hex.length != 16) return null
        var v = 0L
        for (c in hex) {
            val d = Character.digit(c, 16)
            if (d < 0) return null
            v = (v shl 4) or d.toLong()
        }
        return v
    }
}
