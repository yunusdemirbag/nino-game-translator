// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.remoteplay

import java.util.Base64

/** PSN hesap kimliği: 8 ham bayt (little-endian). Saklarken base64 (satır kırmasız, 12 karakter). */
object PsnAccountId {
    const val SIZE = 8

    /** PSN'in `user_id` değeri (ondalık, işaretsiz 64 bit) → 8 bayt little-endian. Geçersizse null. */
    fun fromUserId(userId: String): ByteArray? {
        val text = userId.trim()
        if (text.isEmpty() || !text.all { it in '0'..'9' }) return null
        val value = runCatching { java.lang.Long.parseUnsignedLong(text) }.getOrNull() ?: return null
        return ByteArray(SIZE) { i -> (value ushr (8 * i)).toByte() }
    }

    fun toBase64(id: ByteArray): String = Base64.getEncoder().encodeToString(id)

    /** Base64 metni → 8 bayt. Çözülemezse ya da 8 bayt değilse null. */
    fun fromBase64(text: String?): ByteArray? {
        if (text.isNullOrBlank()) return null
        val bytes = runCatching { Base64.getDecoder().decode(text.trim()) }.getOrNull() ?: return null
        return bytes.takeIf { it.size == SIZE }
    }

    fun isValid(id: ByteArray?): Boolean = id != null && id.size == SIZE
}

/** Uyandırma kimliği: kayıt anahtarı ilk sıfır bayta kadar ASCII onaltılık işaretsiz 64 bit sayıdır. */
object WakeCredential {
    fun fromRegistKey(registKey: ByteArray): Long? {
        val end = registKey.indexOf(0.toByte()).let { if (it < 0) registKey.size else it }
        if (end == 0) return null
        val text = String(registKey, 0, end, Charsets.US_ASCII)
        if (!text.all { it in '0'..'9' || it in 'a'..'f' || it in 'A'..'F' }) return null
        return runCatching { java.lang.Long.parseUnsignedLong(text, 16) }.getOrNull()
    }
}

/** PS5 giriş şifresi: tam 4 ASCII rakam; boşluklar atılır, başka değer "yok" sayılır. */
object LoginPasscode {
    fun normalize(text: String?): String? {
        val t = text?.filterNot { it.isWhitespace() } ?: return null
        return t.takeIf { it.length == 4 && it.all { c -> c in '0'..'9' } }
    }
}
