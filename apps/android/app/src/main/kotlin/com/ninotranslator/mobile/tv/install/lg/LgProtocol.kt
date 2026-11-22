// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.tv.install.lg

import com.ninotranslator.core.json.Json
import com.ninotranslator.mobile.tv.install.TvAppIds

/** LG geliştirici modunun komutları ve yanıtlarının okunması (tv.md 3.2). Saf mantık. */
object LgProtocol {
    const val APP_DIR = "/media/developer/apps/usr/palm/applications/${TvAppIds.LG_APP}"
    const val TEMP_DIR = "/media/developer/temp"
    const val INSTALL_TIMEOUT_SEC = 180

    fun appInfoCommand() = "cat $APP_DIR/appinfo.json"

    /** `appinfo.json`'daki `version`; dosya yoksa ya da okunamazsa null. */
    fun versionFromAppInfo(output: String): String? = runCatching {
        val start = output.indexOf('{')
        if (start < 0) return null
        (Json.parse(output.substring(start)) as? Map<*, *>)?.get("version")?.toString()?.takeIf { it.isNotBlank() }
    }.getOrNull()

    fun ipkPath(fileName: String) = "$TEMP_DIR/$fileName"

    fun cleanupCommand() = "mkdir -p $TEMP_DIR && rm -f $TEMP_DIR/${TvAppIds.LG_APP}_*.ipk $TEMP_DIR/nino-install-*.log"

    fun sizeCommand(path: String) = "wc -c < ${quote(path)}"

    /**
     * Kurulum: ares-install gibi `luna-send-pub -i` ile `dev/install`. Abonelik, girişi bir `sleep`'ten gelen arka plan
     * sürecinde açık tutulur; yanıtlar geçici günlüğe yazılır. TV "installed"/"success" deyince, hata verince, süreç
     * bitince ya da süre dolunca günlük basılır ve süreç kapatılır.
     */
    fun installScript(ipkPath: String, tag: String): String {
        val log = "$TEMP_DIR/nino-install-$tag.log"
        val params = "{\"id\":\"com.ares.defaultName\",\"ipkUrl\":\"$ipkPath\",\"subscribe\":true}"
        return """
            L=${quote(log)}; rm -f "${'$'}L"
            ( sleep ${INSTALL_TIMEOUT_SEC + 20} | luna-send-pub -i 'luna://com.webos.appInstallService/dev/install' '$params' > "${'$'}L" 2>&1 ) &
            P=${'$'}!; i=0
            while [ ${'$'}i -lt $INSTALL_TIMEOUT_SEC ]; do
              sleep 1; i=${'$'}((i+1))
              if grep -qiE 'installed|success|failed|"returnValue": *false' "${'$'}L" 2>/dev/null; then sleep 1; break; fi
              kill -0 ${'$'}P 2>/dev/null || break
            done
            cat "${'$'}L"; kill ${'$'}P 2>/dev/null; pkill -f 'appInstallService/dev/install' 2>/dev/null; rm -f "${'$'}L"
        """.trimIndent()
    }

    fun launchCommand() = "luna-send-pub -n 1 luna://com.webos.applicationManager/launch '{\"id\":\"${TvAppIds.LG_APP}\"}'"

    const val SESSION_TOKEN_COMMAND = "cat /var/luna/preferences/devmode_enabled"

    sealed interface InstallOutcome {
        data object Success : InstallOutcome
        data class Failure(val reason: String) : InstallOutcome
        /** Ne başarı ne hata (süre doldu, yanıt yok). */
        data object Unknown : InstallOutcome
    }

    /**
     * Yanıtlar satır satır JSON; yarım satırlar birleştirilir. `returnValue: false` ya da `details.state` içinde
     * "failed" hata; `details.state` "installed" ya da "success…" başarı.
     */
    fun parseInstall(output: String): InstallOutcome {
        var success = false
        for (obj in jsonObjects(output)) {
            val details = obj["details"] as? Map<*, *>
            val state = details?.get("state")?.toString().orEmpty().lowercase()
            val code = (obj["errorCode"] ?: details?.get("errorCode"))?.toString()
            fun reason(vararg texts: Any?) = listOfNotNull(texts.firstOrNull { it != null && it.toString().isNotBlank() }?.toString(),
                code?.let { "($it)" }).joinToString(" ").ifBlank { "bilinmeyen hata" }
            if (obj["returnValue"] == false) return InstallOutcome.Failure(reason(obj["errorText"], obj["errorMessage"]))
            if ("failed" in state) return InstallOutcome.Failure(reason(details?.get("reason"), obj["errorText"], details?.get("errorText")))
            if (state == "installed" || state.startsWith("success")) success = true
        }
        return if (success) InstallOutcome.Success else InstallOutcome.Unknown
    }

    /** Metindeki üst düzey JSON nesneleri (satır kırılmış olsa da). */
    fun jsonObjects(text: String): List<Map<*, *>> {
        val out = ArrayList<Map<*, *>>()
        var depth = 0; var start = -1; var inString = false; var escape = false
        for (i in text.indices) {
            val c = text[i]
            if (inString) {
                if (escape) escape = false else if (c == '\\') escape = true else if (c == '"') inString = false
                continue
            }
            when (c) {
                '"' -> if (depth > 0) inString = true
                '{' -> { if (depth == 0) start = i; depth++ }
                '}' -> if (depth > 0) {
                    depth--
                    if (depth == 0 && start >= 0) {
                        runCatching { Json.parse(text.substring(start, i + 1).replace("\n", " ").replace("\r", " ")) as? Map<*, *> }
                            .getOrNull()?.let { out += it }
                        start = -1
                    }
                }
            }
        }
        return out
    }

    private val SPACE_MARKERS = listOf(
        "no space", "not enough space", "not enough storage", "insufficient", "out of space", "storage full",
        "disk full", "enospc", "lack of space",
    )

    fun isNoSpace(text: String): Boolean { val t = text.lowercase(); return SPACE_MARKERS.any { it in t } }

    /** Oturum jetonu: boşsa ya da boşluk içeriyorsa kullanılmaz. */
    fun sessionToken(output: String): String? = output.trim().takeIf { it.isNotEmpty() && it.none { c -> c.isWhitespace() } }

    fun resetSessionUrl(token: String) = "https://developer.lge.com/secure/ResetDevModeSession.dev?sessionToken=$token"
    fun checkSessionUrl(token: String) = "https://developer.lge.com/secure/CheckDevModeSession.dev?sessionToken=$token"

    /** CheckDevModeSession yanıtındaki kalan süre (`ss:dd:sn`). */
    fun remaining(text: String): String? = Regex("\\d{1,4}:\\d{2}:\\d{2}").find(text)?.value

    const val RENEW_INTERVAL_MS = 20L * 3600 * 1000

    fun quote(s: String) = "'" + s.replace("'", "'\\''") + "'"
}
