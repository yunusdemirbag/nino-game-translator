// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.tv.install.samsung

import com.ninotranslator.core.json.Json
import com.ninotranslator.mobile.tv.install.TvAppIds

/** Samsung sdb yanıtlarının okunması ve `vd_appinstall` çıktısının sınıflandırılması (tv.md 3.3). Saf mantık. */
object SamsungProtocol {
    const val SDB_PORT = 26101
    const val DEFAULT_TOOLPATH = "/opt/usr/apps/tmp"

    /** `capability:` yanıtı: ilk 2 bayt uzunluk, sonra `anahtar:değer` satırları. */
    fun parseCapability(raw: ByteArray): Map<String, String> {
        val body = if (raw.size >= 2) String(raw, 2, raw.size - 2, Charsets.UTF_8) else ""
        return body.split('\n', '\r').mapNotNull { line ->
            val i = line.indexOf(':')
            if (i <= 0) null else line.substring(0, i).trim() to line.substring(i + 1).trim()
        }.toMap()
    }

    /** `0 vd_applist`: `---- anahtar = değer ----` satırları; `=` içermeyen ve `----` içeren satır kayıt ayırıcıdır. */
    fun parseAppList(text: String): List<Map<String, String>> {
        val out = ArrayList<Map<String, String>>()
        var cur = LinkedHashMap<String, String>()
        fun flush() { if (cur.isNotEmpty()) out += cur; cur = LinkedHashMap() }
        for (raw in text.lines()) {
            val line = raw.trim()
            if (line.isEmpty()) continue
            if ('=' !in line) { if ("----" in line) flush(); continue }
            val s = line.trim('-', ' ')
            val i = s.indexOf('=')
            if (i <= 0) continue
            cur[s.substring(0, i).trim()] = s.substring(i + 1).trim()
        }
        flush()
        return out
    }

    /** Nino'nun kurulu sürümü (`app_tizen_id` ya da `app_id` `NinoTVApps.Nino` veya `NinoTVApps`). */
    fun installedVersion(appList: String): String? = parseAppList(appList).firstOrNull { r ->
        val id = r["app_tizen_id"] ?: r["app_id"]
        id == TvAppIds.SAMSUNG_APP || id == TvAppIds.SAMSUNG_PACKAGE
    }?.get("app_version")?.takeIf { it.isNotBlank() }

    /** `0 getduid`: ilk satır en az 8 karakter, yalnız harf, rakam ve `_-+=/`. */
    fun parseDuid(text: String): String? {
        val first = text.lineSequence().map { it.trim() }.firstOrNull { it.isNotEmpty() } ?: return null
        return first.takeIf { it.length >= 8 && it.all { c -> (c.isLetterOrDigit() && c.code < 128) || c in "_-+=/" } }
    }

    /** "2.4", "5.5" → sayısal; okunamazsa null. */
    fun platformVersion(v: String?): Double? = v?.trim()?.split('.')?.take(2)?.joinToString(".")?.toDoubleOrNull()

    enum class InstallClass { OK, CONNECTION, INCOMPATIBLE, SPACE, CLOCK, CERT_REJECTED, OTHER_CERT_COPY, BLOCKED, OTHER }

    /**
     * `vd_appinstall` çıktısı. TV başarısızlıkta da komutu başarıyla bitirir. Büyük/küçük harf duyarsız; yalın "failed"
     * aranmaz.
     */
    fun classify(output: String): InstallClass {
        val t = output.lowercase()
        val connection = "transport connection" in t || "connection reset by peer" in t || "broken pipe" in t
        val failed = "install failed" in t || "val[fail]" in t || "not enough space" in t || "download failed[116]" in t || connection
        if (!failed) return InstallClass.OK
        if (connection) return InstallClass.CONNECTION
        fun code(vararg c: String) = c.any { it in t.replace(" ", "") }
        return when {
            code("[118,-4]", "[118,-19]", "[118019]") -> InstallClass.INCOMPATIBLE
            "download failed[116]" in t || "not enough space" in t -> InstallClass.SPACE
            code("[118,-12]", "[118012]", "[118,-11]", "[118011]") -> {
                if ("check certificate error" in t && "same id and different certificate" !in t && "author certificate not match" !in t) {
                    if ("not valid yet" in t) InstallClass.CLOCK else InstallClass.CERT_REJECTED
                } else InstallClass.OTHER_CERT_COPY
            }
            code("[118,-22]", "[118022]") -> InstallClass.BLOCKED
            else -> InstallClass.OTHER
        }
    }

    /** Eski kopyayı kaldırıp yeniden denemek işe yarayabilir mi. */
    fun retryAfterUninstall(c: InstallClass) = c == InstallClass.OTHER_CERT_COPY || c == InstallClass.BLOCKED || c == InstallClass.OTHER

    /** Kullanıcıya gösterilen ayrıntı: ilgili ilk 3 farklı satır, yoksa son 3 satır; en çok 400 karakter. */
    fun detail(output: String): String {
        val lines = output.lines().map { it.trim() }.filter { it.isNotEmpty() }
        val keys = listOf("fail", "error", "reason", "not match", "space")
        val hit = lines.filter { l -> keys.any { it in l.lowercase() } }.distinct().take(3)
        return (hit.ifEmpty { lines.takeLast(3) }).joinToString(" | ").take(400)
    }

    /** Samsung'un JSON hata alanları. */
    fun errorFields(body: String): String? = runCatching {
        val m = Json.parse(body.trim()) as? Map<*, *> ?: return null
        listOf("code", "errorCode", "error", "message", "errorMessage", "error_description")
            .mapNotNull { k -> m[k]?.let { "$k=$it" } }.joinToString(", ").ifEmpty { null }
    }.getOrNull()
}
