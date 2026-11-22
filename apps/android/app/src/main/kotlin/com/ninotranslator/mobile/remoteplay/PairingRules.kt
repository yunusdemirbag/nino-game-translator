// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.remoteplay

/** PS5'teki "Cihaz bağla" ekranının 8 haneli kodu. */
object PairingPin {
    private val SKIP = setOf(' ', '-', '–', '.', '_')

    /** Boşluk, `-`, `–`, `.`, `_` atlanır; Unicode rakamlar kabul edilir; tam 8 hane değilse null. */
    fun parse(input: String): Int? {
        val sb = StringBuilder()
        for (c in input) {
            if (c in SKIP || c.isWhitespace()) continue
            if (!Character.isDigit(c)) return null
            sb.append(Character.digit(c, 10))
        }
        if (sb.length != 8) return null
        return sb.toString().toInt()
    }
}

/** Eşleme hatası: kullanıcıya gösterilecek anahtar (`pair_failed` içinde) ve ayrıntı. */
data class RegistFailure(val reasonKey: String, val detail: String?, val retryable: Boolean)

object RegistReasons {
    private val NO_ANSWER = listOf(
        "search response", "connect for search", "send search", "Regist search failed",
        "connect for request", "Regist connect failed",
    )
    private val NO_REPLY = listOf("response HTTP header", "receiving response content", "receive response content")

    /** Önce PS5 kodu, sonra günlük satırları. Yeniden deneme yalnız "PS5 yanıt vermedi" (arama aşaması). */
    fun classify(code: Int, appReason: Long, lines: List<String>): RegistFailure {
        if (appReason != 0L) {
            val key = when (appReason) {
                0x80108b02L -> "regist_wrong_account"
                0x80108b09L -> "regist_wrong_code"
                0x80108b10L -> "regist_in_use"
                0x80108b11L -> "regist_version"
                0x80108b15L -> "regist_crashed"
                else -> "regist_failed"
            }
            return RegistFailure(key, String.format("0x%08x", appReason), false)
        }
        val first = lines.firstOrNull()
        val key = when {
            lines.any { it.contains("getaddrinfo") } -> "regist_bad_address"
            lines.any { l -> NO_ANSWER.any { l.contains(it) } } -> "regist_no_answer"
            lines.any { l -> NO_REPLY.any { l.contains(it) } } || code == NativeRegistResult.NO_REPLY -> "regist_no_reply"
            else -> "regist_failed"
        }
        return RegistFailure(key, first, key == "regist_no_answer")
    }

    const val MAX_ATTEMPTS = 3
    const val RETRY_DELAY_MS = 500L
}
