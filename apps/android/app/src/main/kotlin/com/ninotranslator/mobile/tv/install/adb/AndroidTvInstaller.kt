// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.tv.install.adb

import com.ninotranslator.mobile.tv.install.techDetail
import com.ninotranslator.mobile.data.TvBrand
import com.ninotranslator.mobile.tv.install.TvAppIds
import com.ninotranslator.mobile.tv.install.TvInstallEnv
import com.ninotranslator.mobile.tv.install.TvInstallError
import com.ninotranslator.mobile.tv.install.TvInstallException
import com.ninotranslator.mobile.tv.install.TvInstallRequest
import com.ninotranslator.mobile.tv.install.TvInstallResult
import com.ninotranslator.mobile.tv.install.TvInstallStep
import com.ninotranslator.mobile.tv.install.TvVersions
import java.io.File
import java.io.IOException

/** Android TV / Google TV: ADB (ağ hata ayıklama ya da kablosuz hata ayıklama + eşleme kodu) (tv.md 3.1). */
class AndroidTvInstaller(private val env: TvInstallEnv) {
    private val log = env.log
    val key: AdbKey by lazy { AdbKey.loadOrCreate(env.file("adb", "adbkey")) }

    data class Installed(val version: String?, val fromPlay: Boolean)

    /** "ip:port" ayrıştırması: son `:`'dan sonrası 1–65535. */
    fun parseHostPort(s: String?): Pair<String, Int>? {
        val t = s?.trim()?.replace(',', '.') ?: return null
        val i = t.lastIndexOf(':')
        if (i <= 0) return null
        val port = t.substring(i + 1).filter { it.isDigit() }.toIntOrNull()?.takeIf { it in 1..65535 } ?: return null
        val host = t.substring(0, i).substringAfter("://").trim()
        return if (host.isEmpty()) null else host to port
    }

    /** Bağlanır; [quiet] ise TV onay isterse vazgeçilir ([AdbFailure.NEEDS_APPROVAL]). */
    fun connect(host: String, port: Int, quiet: Boolean = false, onApprove: () -> Unit = {}): AdbConnection {
        val t = try { AdbTransport.socket(host, port, 5_000, 10_000) } catch (e: IOException) {
            throw AdbException(AdbFailure.UNREACHABLE, "bağlantı: ${e.message}", e)
        }
        val c = AdbConnection(t, AdbDialect.ADB, key, log)
        try {
            c.handshake(AdbTls.upgrade(key), approvalWaitMs = if (quiet) 0 else 90_000, onApprove = onApprove)
        } catch (e: Exception) { c.close(); throw e }
        return c
    }

    fun readInstalled(c: AdbConnection): Installed = parseDumpsys(c.shell("dumpsys package ${TvAppIds.ANDROID_PACKAGE}"))

    fun install(request: TvInstallRequest, onStep: (TvInstallStep) -> Unit): TvInstallResult {
        val (host, port) = parseHostPort(request.address) ?: (request.address.trim() to 5555)
        val (apk, pkg) = env.packages.extract(TvBrand.ANDROID_TV, env.cacheDir, "nino-androidtv.apk")
        log("Android TV: $host:$port, paket ${pkg.fileName}, kablosuz=${request.wireless}")
        if (request.wireless && !request.pairCode.isNullOrEmpty()) {
            val code = request.pairCode.filter { it.isDigit() }
            val (ph, pp) = parseHostPort(request.pairAddress) ?: throw TvInstallException(TvInstallError.ANDROID_NEED_PAIR_PORT)
            onStep(TvInstallStep.PAIRING)
            try { AdbPairing.pair(ph, pp, code, key, log) } catch (e: IOException) {
                log("eşleme olmadı: ${e.message}")
                throw TvInstallException(TvInstallError.ANDROID_PAIRING, techDetail(e), note = e.message)
            }
        }
        onStep(TvInstallStep.CONNECTING)
        val c = try {
            connect(host, port, onApprove = { onStep(TvInstallStep.APPROVE) })
        } catch (e: AdbException) {
            throw when (e.failure) {
                AdbFailure.NOT_APPROVED -> TvInstallException(TvInstallError.ANDROID_NOT_APPROVED, techDetail(e), note = e.message)
                AdbFailure.NOT_PAIRED -> TvInstallException(TvInstallError.ANDROID_NOT_PAIRED, techDetail(e), note = e.message)
                else -> TvInstallException(TvInstallError.ANDROID_UNREACHABLE, techDetail(e), note = e.message)
            }
        }
        c.use {
            try {
                onStep(TvInstallStep.READING)
                val tv = readInstalled(c)
                log("Android TV'deki sürüm: ${tv.version ?: "yok"} (Play: ${tv.fromPlay}), telefondaki ${pkg.version}")
                if (!TvVersions.phoneIsNewer(pkg.version, tv.version)) {
                    grantOverlay(c)
                    onStep(TvInstallStep.LAUNCHING)
                    launch(c)
                    return TvInstallResult(tv.version ?: pkg.version, alreadyInstalled = true, host = host, port = port)
                }
                if (request.replaceExisting && tv.version != null) {
                    onStep(TvInstallStep.UNINSTALLING)
                    log("kaldırma: ${c.shell("pm uninstall ${TvAppIds.ANDROID_PACKAGE}").trim().take(300)}")
                }
                onStep(TvInstallStep.INSTALLING)
                val out = installApk(c, apk)
                log("kurulum çıktısı: ${out.take(2000)}")
                checkInstallOutput(out, tv.fromPlay, request.replaceExisting)
                grantOverlay(c)
                onStep(TvInstallStep.LAUNCHING)
                launch(c)
                val now = runCatching { readInstalled(c).version }.getOrNull() ?: pkg.version
                return TvInstallResult(now, alreadyInstalled = false, host = host, port = port)
            } catch (e: IOException) {
                throw TvInstallException(TvInstallError.CONNECTION, techDetail(e), note = e.message)
            }
        }
    }

    /** Android 7+: `exec:cmd package install -r -S`; çıktıda Success/Failure yoksa `sync:` + `pm install`. */
    private fun installApk(c: AdbConnection, apk: File): String {
        val out = String(apk.inputStream().use { c.serviceStreaming("exec:cmd package install -r -S ${apk.length()}", it) }, Charsets.UTF_8)
        if ("Success" in out || "Failure" in out) return out
        log("cmd package yok gibi (${out.take(200)}); sync ile gönderiliyor")
        val remote = "/data/local/tmp/nino-tv.apk"
        apk.inputStream().use { c.push(remote, 0x8000 or 0x1A4, it) }
        val pm = c.shell("pm install -r $remote")
        runCatching { c.shell("rm -f $remote") }
        return pm
    }

    private fun grantOverlay(c: AdbConnection) {
        runCatching {
            val o = c.shell("appops set ${TvAppIds.ANDROID_PACKAGE} SYSTEM_ALERT_WINDOW allow")
            if (overlayFailed(o)) {
                val g = c.shell("pm grant ${TvAppIds.ANDROID_PACKAGE} android.permission.SYSTEM_ALERT_WINDOW")
                log("katman izni appops ile verilemedi (${o.trim().take(200)}); pm grant: ${g.trim().take(200)}")
            } else log("katman izni verildi")
        }.onFailure { log("katman izni verilemedi: ${it.message}") }
    }

    private fun launch(c: AdbConnection) {
        runCatching { log("açma: ${c.shell("am start -n ${TvAppIds.ANDROID_PACKAGE}/.MainActivity").trim().take(300)}") }
            .onFailure { log("uygulama açılamadı: ${it.message}") }
    }

    companion object {
        fun parseDumpsys(out: String): Installed {
            val version = Regex("versionName=(\\S+)").find(out)?.groupValues?.get(1)
            val installer = Regex("installerPackageName=(\\S+)").find(out)?.groupValues?.get(1)
            return Installed(version, installer == "com.android.vending")
        }

        fun overlayFailed(out: String): Boolean = listOf("Error", "Exception", "Unknown", "not allowed").any { it in out }

        /** Kurulum çıktısının hatası (tv.md 3.1 hata tablosu); başarıysa dönmez. */
        fun checkInstallOutput(out: String, fromPlay: Boolean, replaced: Boolean) {
            if ("Success" in out) return
            if ("INSTALL_FAILED_UPDATE_INCOMPATIBLE" in out || "INSTALL_FAILED_VERSION_DOWNGRADE" in out) {
                throw TvInstallException(when {
                    replaced -> TvInstallError.ANDROID_REMOVE_MANUALLY
                    fromPlay -> TvInstallError.ANDROID_PLAY_COPY
                    else -> TvInstallError.ANDROID_OTHER_COPY
                }, out.trim().take(400))
            }
            if ("INSTALL_FAILED_INSUFFICIENT_STORAGE" in out || "No space left" in out) throw TvInstallException(TvInstallError.SPACE, out.trim().take(400))
            throw TvInstallException(TvInstallError.FAILED, out.trim().takeIf { it.isNotEmpty() }?.take(400), note = "TV yanıt vermedi".takeIf { out.isBlank() })
        }
    }
}
