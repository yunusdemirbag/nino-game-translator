// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.support

import android.os.Process

/** Gizli değerleri günlükten siler (servis.md §7). Saf; birim testi var. */
object LogRedactor {
    const val MASK = "[gizlendi]"

    private val rules: List<Pair<Regex, (MatchResult) -> String>> = listOf(
        Regex("""(?i)\bBearer\s+[A-Za-z0-9._~+/=\-]+""") to { _ -> "Bearer $MASK" },
        Regex("""(?i)("?[A-Za-z0-9_.\-]*(?:key|token|secret|password|passcode|auth|authorization|cookie)[A-Za-z0-9_.\-]*"?\s*[:=]\s*)("[^"]*"|[^\s,;&}]+)""") to
            { m -> m.groupValues[1] + MASK },
        Regex("""AIza[0-9A-Za-z_\-]{10,}""") to { _ -> MASK },
        Regex("""sk-[A-Za-z0-9_\-]{10,}""") to { _ -> MASK },
        Regex("""\b[0-9a-fA-F]{32,}\b""") to { _ -> MASK },
        Regex("""[A-Za-z0-9+/_\-]{40,}={0,2}""") to { _ -> MASK },
    )

    fun redact(text: String): String {
        var s = text
        for ((re, f) in rules) s = re.replace(s, f)
        return s
    }
}

/** Uygulamanın kendi sistem günlüğü: son 3000 satır, son 60 000 karakter, gizli değerler silinmiş. */
object AppLog {
    const val MAX_CHARS = 60_000

    fun collect(): String? = runCatching {
        val p = ProcessBuilder("logcat", "-d", "-t", "3000", "--pid", Process.myPid().toString())
            .redirectErrorStream(true).start()
        val text = p.inputStream.bufferedReader().use { it.readText() }
        p.waitFor()
        LogRedactor.redact(text.takeLast(MAX_CHARS)).takeIf { it.isNotBlank() }
    }.getOrNull()
}
