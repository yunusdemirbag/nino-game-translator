// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.tv.install.lg

import com.ninotranslator.mobile.tv.install.techDetail
import com.jcraft.jsch.ChannelExec
import com.jcraft.jsch.JSch
import com.jcraft.jsch.JSchException
import com.jcraft.jsch.KeyPair
import com.jcraft.jsch.Session
import com.ninotranslator.mobile.data.TvBrand
import com.ninotranslator.mobile.tv.install.TvInstallEnv
import com.ninotranslator.mobile.tv.install.TvInstallError
import com.ninotranslator.mobile.tv.install.TvInstallException
import com.ninotranslator.mobile.tv.install.TvInstallRequest
import com.ninotranslator.mobile.tv.install.TvInstallResult
import com.ninotranslator.mobile.tv.install.TvInstallStep
import com.ninotranslator.mobile.tv.install.TvVersions
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.IOException
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.InetSocketAddress
import java.net.Socket
import java.net.URL

/** LG webOS: Developer Mode, Key Server (9991), SSH 9922 (tv.md 3.2). */
class LgInstaller(private val env: TvInstallEnv) {
    private val log = env.log

    fun keyFile(address: String): File = env.file("lg", TvInstallEnv.safeName(address.lowercase()) + ".key")
    fun hasKey(address: String): Boolean = keyFile(address).isFile

    class Shell(private val session: Session) : AutoCloseable {
        data class Output(val exit: Int, val text: String)

        /** Komutu ayrı `exec` kanalında çalıştırır (5 dk). stdout + stderr birlikte. */
        fun run(command: String, stdin: InputStream? = null, timeoutMs: Long = 5 * 60_000): Output {
            val ch = session.openChannel("exec") as ChannelExec
            val out = ByteArrayOutputStream()
            try {
                ch.setCommand(command)
                ch.setErrStream(out, true)
                ch.outputStream.let { os ->
                    val input = ch.inputStream
                    ch.connect(15_000)
                    if (stdin != null) {
                        stdin.copyTo(os, 32 * 1024)
                    }
                    os.close()
                    val end = System.currentTimeMillis() + timeoutMs
                    val buf = ByteArray(8192)
                    while (true) {
                        while (input.available() > 0) {
                            val n = input.read(buf)
                            if (n < 0) break
                            synchronized(out) { out.write(buf, 0, n) }
                        }
                        if (ch.isClosed) {
                            if (input.available() > 0) continue
                            break
                        }
                        if (System.currentTimeMillis() > end) throw TvInstallException(TvInstallError.CONNECTION, note = "komut 5 dk'da bitmedi")
                        Thread.sleep(100)
                    }
                }
                return Output(ch.exitStatus, synchronized(out) { out.toString(Charsets.UTF_8.name()) })
            } catch (e: JSchException) {
                throw TvInstallException(TvInstallError.CONNECTION, techDetail(e), note = "SSH kanalı: ${e.message}")
            } catch (e: IOException) {
                throw TvInstallException(TvInstallError.CONNECTION, techDetail(e), note = "SSH kanalı: ${e.message}")
            } finally {
                ch.disconnect()
            }
        }

        override fun close() = session.disconnect()
    }

    /** SSH oturumu: kullanıcı `prisoner`, yalnız açık anahtar, ana makine anahtarı denetlenmez, eski algoritmalar açık. */
    fun connect(host: String, key: ByteArray): Shell {
        val jsch = JSch()
        try {
            jsch.addIdentity("nino-lg", key, null, null)
        } catch (e: JSchException) {
            throw TvInstallException(TvInstallError.LG_KEY_REFUSED, techDetail(e), note = "anahtar okunamadı: ${e.message}")
        }
        val s = jsch.getSession("prisoner", host, 9922)
        s.setConfig("StrictHostKeyChecking", "no")
        s.setConfig("PreferredAuthentications", "publickey")
        s.setConfig("server_host_key", append(s.getConfig("server_host_key"), "ssh-rsa"))
        s.setConfig("PubkeyAcceptedAlgorithms", append(s.getConfig("PubkeyAcceptedAlgorithms"), "rsa-sha2-256,rsa-sha2-512,ssh-rsa"))
        s.setConfig("kex", append(s.getConfig("kex"), "diffie-hellman-group14-sha1,diffie-hellman-group1-sha1"))
        try {
            s.connect(8_000)
        } catch (e: JSchException) {
            val m = e.message.orEmpty()
            throw when {
                m.contains("Auth fail", ignoreCase = true) || m.contains("Auth cancel", ignoreCase = true) ->
                    TvInstallException(TvInstallError.LG_KEY_REFUSED, m)
                else -> TvInstallException(TvInstallError.LG_UNREACHABLE, m)
            }
        }
        return Shell(s)
    }

    /** Key Server'dan anahtar alır, parolayla çözer ve TV adresine göre saklar. */
    fun fetchKey(host: String, passphrase: String): ByteArray {
        val text = try {
            val c = URL("http://$host:9991/webos_rsa").openConnection() as HttpURLConnection
            c.connectTimeout = 5_000; c.readTimeout = 5_000
            try {
                if (c.responseCode != 200) throw TvInstallException(TvInstallError.LG_KEY_SERVER, "Key Server ${c.responseCode}")
                c.inputStream.use { it.readBytes() }.toString(Charsets.UTF_8)
            } finally { c.disconnect() }
        } catch (e: TvInstallException) { throw e } catch (e: IOException) {
            throw TvInstallException(TvInstallError.LG_KEY_SERVER, techDetail(e), note = "Key Server: ${e.message}")
        }
        val pem = decodeKey(text, passphrase)
        val f = keyFile(host)
        f.parentFile?.mkdirs()
        f.writeBytes(pem)
        log("LG anahtarı alındı ve saklandı")
        return pem
    }

    fun decodeKey(text: String, passphrase: String): ByteArray {
        if (!LgKey.looksLikeKey(text)) throw TvInstallException(TvInstallError.LG_KEY_SERVER, note = "Key Server anahtar yerine başka bir şey döndü")
        return when (val r = LgKey.decrypt(text, passphrase)) {
            is LgKey.Result.Decrypted -> r.pem
            LgKey.Result.WrongPassphrase -> throw TvInstallException(TvInstallError.LG_PASSPHRASE)
            LgKey.Result.NotAKey -> throw TvInstallException(TvInstallError.LG_KEY_SERVER, note = "anahtar okunamadı")
            LgKey.Result.OtherFormat -> {
                // OpenSSH gibi biçimler: SSH kütüphanesi çözer.
                val kp = try { KeyPair.load(JSch(), text.toByteArray(), null) } catch (e: JSchException) {
                    throw TvInstallException(TvInstallError.LG_KEY_SERVER, techDetail(e), note = "anahtar okunamadı: ${e.message}")
                }
                try {
                    if (kp.isEncrypted && LgKey.candidates(passphrase).none { kp.decrypt(it) }) throw TvInstallException(TvInstallError.LG_PASSPHRASE)
                    ByteArrayOutputStream().also { kp.writePrivateKey(it) }.toByteArray()
                } finally { kp.dispose() }
            }
        }
    }

    /** Kurulu sürüm (yoksa null). */
    fun readVersion(shell: Shell): String? = LgProtocol.versionFromAppInfo(shell.run(LgProtocol.appInfoCommand()).text)

    /** Kayıtlı anahtarla bağlanır; reddedilirse anahtar silinir ve parola varsa yenisi alınır (bir kez). */
    fun open(host: String, passphrase: String?, onStep: (TvInstallStep) -> Unit): Shell {
        val saved = keyFile(host).takeIf { it.isFile }?.readBytes()
        if (saved != null) {
            try { return connect(host, saved) } catch (e: TvInstallException) {
                if (e.error != TvInstallError.LG_KEY_REFUSED) throw e
                log("kayıtlı LG anahtarı reddedildi; siliniyor")
                keyFile(host).delete()
            }
        }
        if (passphrase.isNullOrBlank()) {
            if (!portOpen(host, 9922, 1_500)) throw TvInstallException(TvInstallError.LG_UNREACHABLE)
            throw TvInstallException(TvInstallError.LG_KEY_REFUSED, note = "parola yazılmadı")
        }
        onStep(TvInstallStep.KEY)
        val key = fetchKey(host, passphrase)
        onStep(TvInstallStep.CONNECTING)
        return connect(host, key)
    }

    fun install(request: TvInstallRequest, onStep: (TvInstallStep) -> Unit): TvInstallResult {
        val host = request.address
        val (ipk, pkg) = env.packages.bytes(TvBrand.LG)
        onStep(TvInstallStep.CONNECTING)
        log("LG: $host, paket ${pkg.fileName}")
        open(host, request.passphrase, onStep).use { sh ->
            onStep(TvInstallStep.READING)
            val tvVersion = readVersion(sh)
            log("LG TV'deki sürüm: ${tvVersion ?: "yok"}, telefondaki ${pkg.version}")
            if (!TvVersions.phoneIsNewer(pkg.version, tvVersion)) {
                onStep(TvInstallStep.LAUNCHING)
                launch(sh)
                renewSession(host, sh)
                return TvInstallResult(tvVersion ?: pkg.version, alreadyInstalled = true, host = host)
            }
            onStep(TvInstallStep.INSTALLING)
            val path = LgProtocol.ipkPath(pkg.fileName)
            sh.run(LgProtocol.cleanupCommand())
            val up = sh.run("cat > ${LgProtocol.quote(path)}", ByteArrayInputStream(ipk))
            if (up.exit != 0) throwInstall("yükleme: ${up.text}")
            val size = sh.run(LgProtocol.sizeCommand(path)).text.trim()
            if (size.toLongOrNull() != null && size.toLong() != ipk.size.toLong()) throwInstall("TV'ye giden paketin boyutu tutmuyor ($size / ${ipk.size})")
            val raw = sh.run(LgProtocol.installScript(path, java.lang.Long.toHexString(env.now()))).text
            log("LG kurulum yanıtı: ${raw.take(2000)}")
            val outcome = LgProtocol.parseInstall(raw)
            if (outcome is LgProtocol.InstallOutcome.Failure) throwInstall(outcome.reason)
            // Doğrulama: sürüm görünene kadar 2 sn'de bir.
            val waitMs = if (outcome == LgProtocol.InstallOutcome.Success) 30_000 else 60_000
            val end = env.now() + waitMs
            var seen: String? = null
            while (env.now() < end) {
                seen = readVersion(sh)
                if (seen != null && TvVersions.compare(seen, pkg.version) >= 0) break
                Thread.sleep(2_000)
            }
            if (seen == null || TvVersions.compare(seen, pkg.version) < 0) {
                throwInstall(if (outcome == LgProtocol.InstallOutcome.Unknown) raw.ifBlank { "TV yanıt vermedi" } else "TV'de sürüm görünmedi (${seen ?: "yok"})")
            }
            sh.run("rm -f ${LgProtocol.quote(path)}")
            onStep(TvInstallStep.LAUNCHING)
            launch(sh)
            renewSession(host, sh)
            return TvInstallResult(seen, alreadyInstalled = false, host = host)
        }
    }

    private fun throwInstall(text: String): Nothing {
        if (LgProtocol.isNoSpace(text)) throw TvInstallException(TvInstallError.SPACE, tvSays = text.take(500))
        throw TvInstallException(TvInstallError.FAILED, tvSays = text.trim().take(500))
    }

    private fun launch(sh: Shell) {
        runCatching { log("LG açma: ${sh.run(LgProtocol.launchCommand(), timeoutMs = 30_000).text.take(300)}") }
            .onFailure { log("LG uygulaması açılamadı: ${it.message}") }
    }

    /** Geliştirici modu oturumunu uzatır (en çok 20 saatte bir, TV başına). Hata kullanıcıya gösterilmez. */
    fun renewSession(host: String, sh: Shell) {
        val last = env.lgRenewedAt(host)
        if (last != null && env.now() - last < LgProtocol.RENEW_INTERVAL_MS) return
        runCatching {
            val token = LgProtocol.sessionToken(sh.run(LgProtocol.SESSION_TOKEN_COMMAND, timeoutMs = 20_000).text)
                ?: run { log("LG oturum jetonu yok; uzatılmadı"); return }
            val reset = httpGet(LgProtocol.resetSessionUrl(token))
            if (!reset.contains("success", ignoreCase = true)) { log("LG oturumu uzatılamadı: ${reset.take(200)}"); return }
            val left = LgProtocol.remaining(httpGet(LgProtocol.checkSessionUrl(token)))
            env.setLgRenewedAt(host, env.now())
            log("LG geliştirici oturumu uzatıldı; kalan ${left ?: "?"}")
        }.onFailure { log("LG oturumu uzatılamadı: ${it.message}") }
    }

    private fun httpGet(url: String): String {
        val c = URL(url).openConnection() as HttpURLConnection
        c.connectTimeout = 10_000; c.readTimeout = 10_000
        try { return (if (c.responseCode in 200..299) c.inputStream else c.errorStream)?.use { it.readBytes() }?.toString(Charsets.UTF_8).orEmpty() }
        finally { c.disconnect() }
    }

    companion object {
        fun append(current: String?, extra: String): String {
            val have = current.orEmpty().split(',').filter { it.isNotBlank() }
            return (have + extra.split(',').filter { it !in have }).joinToString(",")
        }

        fun portOpen(host: String, port: Int, timeoutMs: Int): Boolean = runCatching {
            Socket().use { it.connect(InetSocketAddress(host, port), timeoutMs) }
            true
        }.getOrDefault(false)
    }
}
