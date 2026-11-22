// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.tv.install.samsung

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
import com.ninotranslator.mobile.tv.install.adb.AdbConnection
import com.ninotranslator.mobile.tv.install.adb.AdbDialect
import com.ninotranslator.mobile.tv.install.adb.AdbException
import com.ninotranslator.mobile.tv.install.adb.AdbFailure
import com.ninotranslator.mobile.tv.install.adb.AdbKey
import com.ninotranslator.mobile.tv.install.adb.AdbTransport
import kotlinx.coroutines.flow.MutableStateFlow
import org.bouncycastle.crypto.util.PrivateKeyFactory
import java.io.ByteArrayInputStream
import java.io.IOException
import java.security.SecureRandom

/** Samsung Tizen: sdb (26101), Samsung hesabı ve TV'ye özel sertifika, W3C imzası, `vd_appinstall` (tv.md 3.3). */
class SamsungInstaller(private val env: TvInstallEnv, private val port: Int = SamsungProtocol.SDB_PORT) {
    private val log = env.log
    val signInUrl = MutableStateFlow<String?>(null)
    @Volatile private var signInCancelled = false

    fun cancelSignIn() { signInCancelled = true; signInUrl.value = null }

    private val key: AdbKey by lazy { AdbKey.loadOrCreate(env.file("sdb", "adbkey")) }

    /** sdbd yeni bağlantıyı el sıkışma ortasında bazen kapatır: üç deneme, aralarda 400 ms. */
    fun connect(host: String, quiet: Boolean = false): AdbConnection {
        var last: Exception? = null
        repeat(3) { attempt ->
            if (attempt > 0) Thread.sleep(400)
            try {
                val c = AdbConnection(AdbTransport.socket(host, port, 10_000, 120_000), AdbDialect.SDB, key, log)
                try {
                    c.handshake(tls = null, approvalWaitMs = if (quiet) 0 else 90_000)
                    return c
                } catch (e: Exception) { c.close(); throw e }
            } catch (e: AdbException) {
                if (e.failure == AdbFailure.NEEDS_APPROVAL) throw e
                last = e
            } catch (e: IOException) { last = e }
            log("sdb denemesi ${attempt + 1} olmadı: ${last?.message}")
        }
        throw TvInstallException(TvInstallError.SAMSUNG_UNREACHABLE, techDetail(last), note = last?.message)
    }

    fun readVersion(c: AdbConnection): String? = SamsungProtocol.installedVersion(c.shell("0 vd_applist"))

    fun readDuid(c: AdbConnection): String? {
        repeat(3) { i ->
            if (i > 0) Thread.sleep(500)
            SamsungProtocol.parseDuid(c.shell("0 getduid"))?.let { return it }
        }
        return null
    }

    private fun intermediateCas(): List<ByteArray> = listOf("author_ca.pem", "vd_tizen_dev_author_ca.pem", "public2.pem", "vd_tizen_dev_public2.pem")
        .flatMap { n -> env.packages.open("tv/samsung-ca/$n")?.use { SamsungCertificates.parsePemCertificates(it.readBytes().toString(Charsets.US_ASCII)) }.orEmpty() }

    private fun signIn(onStep: (TvInstallStep) -> Unit): SamsungCertificates.Account {
        onStep(TvInstallStep.SIGNIN)
        signInCancelled = false
        val listener = try { SamsungSignIn.Listener(log = log) } catch (e: IOException) {
            throw TvInstallException(TvInstallError.SAMSUNG_LOGIN, techDetail(e), note = "4794 açılamadı: ${e.message}")
        }
        listener.use {
            signInUrl.value = SamsungSignIn.URL
            try {
                return it.await(SamsungSignIn.TIMEOUT_MS) { signInCancelled }
                    ?: throw TvInstallException(TvInstallError.SAMSUNG_LOGIN, note = if (signInCancelled) "giriş kapatıldı" else "10 dk doldu")
            } finally { signInUrl.value = null }
        }
    }

    fun install(request: TvInstallRequest, onStep: (TvInstallStep) -> Unit): TvInstallResult {
        val host = request.address
        val (wgt, pkg) = env.packages.bytes(TvBrand.SAMSUNG)
        onStep(TvInstallStep.CONNECTING)
        log("Samsung: $host, paket ${pkg.fileName}")
        var c = connect(host)
        try {
            onStep(TvInstallStep.READING)
            val caps = SamsungProtocol.parseCapability(c.service("capability:"))
            val platform = SamsungProtocol.platformVersion(caps["platform_version"])
            val toolPath = caps["sdk_toolpath"]?.takeIf { it.isNotBlank() } ?: SamsungProtocol.DEFAULT_TOOLPATH
            log("Tizen ${caps["platform_version"]}, araç klasörü $toolPath")
            if (platform != null && platform < 2.4) throw TvInstallException(TvInstallError.SAMSUNG_TOO_OLD, "Tizen $platform")
            if (platform != null && platform < 5.0) log("Tizen 5.0'dan eski: deneysel")
            val tvVersion = readVersion(c)
            log("Samsung TV'deki sürüm: ${tvVersion ?: "yok"}, telefondaki ${pkg.version}")
            if (!TvVersions.phoneIsNewer(pkg.version, tvVersion)) {
                launch(c)
                return TvInstallResult(tvVersion ?: pkg.version, alreadyInstalled = true, host = host)
            }
            val duid = readDuid(c) ?: throw TvInstallException(TvInstallError.SAMSUNG_UNREACHABLE, "DUID", note = "DUID okunamadı")
            var profile = SamsungCertificates.loadProfile(env, duid)
            if (profile == null) {
                // Giriş uzun sürebilir: sdb bağlantısı kapatılır, sonra yeniden açılır.
                c.close()
                val account = signIn(onStep)
                onStep(TvInstallStep.CERTIFICATE)
                profile = SamsungCertificates.request(env, account, duid)
                onStep(TvInstallStep.CONNECTING)
                c = connect(host)
            }
            if (platform != null && platform > 2.4 && platform <= 4.0 && profile.deviceProfile != null) {
                runCatching { c.push("$toolPath/device-profile.xml", null, ByteArrayInputStream(profile.deviceProfile)) }
                    .onFailure { log("cihaz profili gönderilemedi: ${it.message}") }
            }
            onStep(TvInstallStep.SIGNING)
            val cas = intermediateCas()
            val signed = WidgetSigner.sign(wgt, PrivateKeyFactory.createKey(profile.key.encoded),
                SamsungCertificates.chain(profile.author, cas), SamsungCertificates.chain(profile.distributor, cas))
            onStep(TvInstallStep.INSTALLING)
            var cls = installOnce(c, toolPath, signed)
            if (SamsungProtocol.retryAfterUninstall(cls.first)) {
                onStep(TvInstallStep.UNINSTALLING)
                for (id in listOf(TvAppIds.SAMSUNG_PACKAGE, TvAppIds.SAMSUNG_APP)) {
                    runCatching { log("kaldırma $id: ${c.shell("0 vd_appuninstall $id").take(300)}") }
                }
                onStep(TvInstallStep.INSTALLING)
                cls = installOnce(c, toolPath, signed)
            }
            val (kind, output) = cls
            val detail = SamsungProtocol.detail(output)
            when (kind) {
                SamsungProtocol.InstallClass.OK -> {}
                SamsungProtocol.InstallClass.CONNECTION -> throw TvInstallException(TvInstallError.CONNECTION, detail)
                SamsungProtocol.InstallClass.SPACE -> throw TvInstallException(TvInstallError.SPACE, detail)
                SamsungProtocol.InstallClass.CLOCK -> throw TvInstallException(TvInstallError.SAMSUNG_CLOCK, detail)
                SamsungProtocol.InstallClass.CERT_REJECTED -> {
                    SamsungCertificates.rejectProfile(env, duid)
                    throw TvInstallException(TvInstallError.SAMSUNG_REJECTED, detail, maintenanceHint = true)
                }
                SamsungProtocol.InstallClass.OTHER_CERT_COPY -> throw TvInstallException(TvInstallError.SAMSUNG_MISMATCH, detail)
                SamsungProtocol.InstallClass.BLOCKED -> throw TvInstallException(TvInstallError.SAMSUNG_BLOCKED, detail)
                SamsungProtocol.InstallClass.INCOMPATIBLE, SamsungProtocol.InstallClass.OTHER ->
                    throw TvInstallException(TvInstallError.FAILED, detail, maintenanceHint = true)
            }
            val now = readVersion(c)
            if (now == null || TvVersions.compare(now, pkg.version) < 0) {
                throw TvInstallException(TvInstallError.FAILED, now, note = "kurulum tamamlanmış göründü, fakat TV'deki sürüm hâlâ ${now ?: "eski sürüm"}")
            }
            launch(c)
            return TvInstallResult(now, alreadyInstalled = false, host = host)
        } catch (e: IOException) {
            throw TvInstallException(TvInstallError.CONNECTION, techDetail(e), note = e.message)
        } finally {
            c.close()
        }
    }

    private fun installOnce(c: AdbConnection, toolPath: String, signed: ByteArray): Pair<SamsungProtocol.InstallClass, String> {
        val name = "nino-" + ByteArray(4).also { SecureRandom().nextBytes(it) }.joinToString("") { "%02x".format(it) } + ".wgt"
        val path = "$toolPath/$name"
        c.push(path, null, ByteArrayInputStream(signed))
        val out = c.shell("0 vd_appinstall ${TvAppIds.SAMSUNG_APP} $path")
        log("vd_appinstall: ${out.take(3000)}")
        return SamsungProtocol.classify(out) to out
    }

    private fun launch(c: AdbConnection) {
        runCatching { log("açma: ${c.shell("0 was_execute ${TvAppIds.SAMSUNG_APP}").take(300)}") }
            .onFailure { log("Samsung uygulaması açılamadı: ${it.message}") }
    }
}
