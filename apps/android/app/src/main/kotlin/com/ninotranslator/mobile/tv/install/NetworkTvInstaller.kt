// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.tv.install

import android.content.Context
import com.ninotranslator.core.json.Json
import com.ninotranslator.mobile.data.InstalledTv
import com.ninotranslator.mobile.data.Nino
import com.ninotranslator.mobile.data.TvBrand
import com.ninotranslator.mobile.remoteplay.NetworkAddresses
import com.ninotranslator.mobile.tv.TvFinders
import com.ninotranslator.mobile.tv.install.adb.AdbFailure
import com.ninotranslator.mobile.tv.install.adb.AdbException
import com.ninotranslator.mobile.tv.install.adb.AndroidTvInstaller
import com.ninotranslator.mobile.tv.install.lg.LgInstaller
import com.ninotranslator.mobile.tv.install.samsung.SamsungInstaller
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import kotlinx.coroutines.withContext
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.InetSocketAddress
import java.net.Socket
import java.net.URL

/** Uygulamanın assets'indeki TV paketleri. */
class AssetTvPackages(private val context: Context) : TvPackageSource {
    override val index: TvPackageIndex by lazy {
        TvPackageIndex.parse(open("tv/index.txt")?.use { it.readBytes().toString(Charsets.UTF_8) }.orEmpty())
    }
    override fun open(path: String): InputStream? = runCatching { context.assets.open(path) }.getOrNull()
}

/** Samsung 8001 bilgi sayfasının okunan kısmı. */
data class SamsungTvInfo(val name: String?, val model: String?, val developerMode: Boolean?, val developerIp: String?)

/** Asıl kurulum katmanı (Samsung, LG, Android TV) ve TV arama (tv.md 2.2, 3). */
class NetworkTvInstaller(private val env: TvInstallEnv) : TvInstaller {
    val android = AndroidTvInstaller(env)
    val lg = LgInstaller(env)
    val samsung = SamsungInstaller(env)

    override val samsungSignInUrl: StateFlow<String?> get() = samsung.signInUrl
    override fun cancelSamsungSignIn() = samsung.cancelSignIn()
    override fun hasLgKey(address: String): Boolean = lg.hasKey(address)

    override suspend fun install(request: TvInstallRequest, onStep: (TvInstallStep) -> Unit): TvInstallResult = withContext(Dispatchers.IO) {
        env.log("kurulum başladı: ${request.brand} ${request.address}")
        val r = when (request.brand) {
            TvBrand.ANDROID_TV -> android.install(request, onStep)
            TvBrand.LG -> lg.install(request, onStep)
            TvBrand.SAMSUNG -> samsung.install(request, onStep)
        }
        env.log("kurulum bitti: ${r.version}${if (r.alreadyInstalled) " (zaten kuruluydu)" else ""}")
        // Güncellendi: ana ekran kartı kalkar.
        com.ninotranslator.mobile.tv.TvAppVersions.notice.value?.takeIf { it.host == r.host }?.let { com.ninotranslator.mobile.tv.TvAppVersions.notice.value = null }
        r
    }

    // --- Arama ---

    override suspend fun discover(brand: TvBrand): List<TvCandidate> = withContext(Dispatchers.IO) {
        val found = runCatching { TvFinders.current.search() }.getOrDefault(emptyList()).filter { it.brand == brand }
        val phone = NetworkAddresses.pickLocalAddress(NetworkAddresses.systemInterfaces())
        when (brand) {
            TvBrand.SAMSUNG -> {
                val ssdp = found.map { it.address to it.name }
                val targets = ssdp.ifEmpty { phone?.let { p -> NetworkAddresses.subnetTargets(p).map { it to null } }.orEmpty() }
                val fromScan = ssdp.isEmpty()
                parallel(targets) { (ip, name) ->
                    val info = samsungInfo(ip, if (fromScan) 700 else 1_500, if (fromScan) 1 else 2)
                    if (info == null && fromScan) null
                    else TvCandidate(info?.name ?: name ?: "Samsung TV", ip, TvBrand.SAMSUNG, info?.model, samsungStatus(info, phone))
                }
            }
            TvBrand.LG -> parallel(found) { tv ->
                TvCandidate(tv.name, tv.address, TvBrand.LG, status = if (portOpen(tv.address, 9922, 1_500)) TvCandidateStatus.DevOn else TvCandidateStatus.DevOff)
            }
            TvBrand.ANDROID_TV -> {
                val scanned = phone?.let { p -> parallel(NetworkAddresses.subnetTargets(p)) { ip -> ip.takeIf { portOpen(it, 5555, 700) } } }.orEmpty().toSet()
                val names = found.associate { it.address to it.name }
                val all = LinkedHashSet<String>().apply { addAll(scanned); addAll(names.keys) }
                all.map { ip ->
                    TvCandidate(names[ip] ?: "Android TV", ip, TvBrand.ANDROID_TV,
                        status = if (ip in scanned) TvCandidateStatus.DebugOn else TvCandidateStatus.DebugOff)
                }.sortedBy { if (it.status == TvCandidateStatus.DebugOn) 0 else 1 }
            }
        }
    }

    private suspend fun <T, R : Any> parallel(items: List<T>, block: (T) -> R?): List<R> = coroutineScope {
        val gate = Semaphore(32)
        items.map { item -> async { gate.withPermit { runCatching { block(item) }.getOrNull() } } }.awaitAll().filterNotNull()
    }

    private fun samsungInfo(ip: String, timeoutMs: Int, tries: Int): SamsungTvInfo? {
        repeat(tries) {
            runCatching {
                val c = URL("http://$ip:8001/api/v2/").openConnection() as HttpURLConnection
                c.connectTimeout = timeoutMs; c.readTimeout = timeoutMs
                try {
                    if (c.responseCode == 200) return parseSamsungInfo(c.inputStream.use { it.readBytes() }.toString(Charsets.UTF_8))
                } finally { c.disconnect() }
            }
        }
        return null
    }

    companion object {
        fun portOpen(host: String, port: Int, timeoutMs: Int): Boolean = runCatching {
            Socket().use { it.connect(InetSocketAddress(host, port), timeoutMs) }
            true
        }.getOrDefault(false)

        /** `api/v2` yanıtının `device` nesnesi: `name`, `modelName`, `developerMode` ("1"/"true"), `developerIP`. */
        fun parseSamsungInfo(json: String): SamsungTvInfo? = runCatching {
            val root = Json.parse(json) as? Map<*, *> ?: return null
            val d = root["device"] as? Map<*, *>
            val name = (d?.get("name") ?: root["name"])?.toString()?.takeIf { it.isNotBlank() }
            val dev = d?.get("developerMode")?.toString()?.let { it == "1" || it.equals("true", true) }
            val ip = d?.get("developerIP")?.toString()?.takeIf { it.isNotBlank() && it != "0.0.0.0" }
            SamsungTvInfo(name, d?.get("modelName")?.toString()?.takeIf { it.isNotBlank() }, dev, ip)
        }.getOrNull()

        fun samsungStatus(info: SamsungTvInfo?, phoneIp: String?): TvCandidateStatus? = when {
            info?.developerMode == null -> null
            info.developerMode == false -> TvCandidateStatus.DevOff
            info.developerIp != null && phoneIp != null && info.developerIp != phoneIp -> TvCandidateStatus.DevOtherIp(info.developerIp)
            else -> TvCandidateStatus.DevOn
        }

        /** Uygulamanın asıl kurucusu (veri katmanı hazırken). */
        fun create(context: Context): NetworkTvInstaller {
            val app = context.applicationContext
            val settings = Nino.settings
            return NetworkTvInstaller(TvInstallEnv(
                noBackupDir = app.noBackupFilesDir,
                cacheDir = app.cacheDir,
                packages = AssetTvPackages(app),
                log = { Nino.tvInstallLog.append(it) },
                lgRenewedAt = { settings.lgSessionRenewedAt(it) },
                setLgRenewedAt = { a, t -> settings.setLgSessionRenewedAt(a, t) },
            ))
        }
    }

    // --- Sessiz sürüm denetimi (tv.md 3.4) ---

    /**
     * Kayıtlı TV'deki sürüm; kullanıcıdan hiçbir şey istenmez (Samsung girişi yok, Android TV onayı beklenmez, LG
     * parolası sorulmaz). Port kapalıysa ya da okunamazsa null.
     */
    fun quietVersion(tv: InstalledTv): String? {
        val host = tv.host
        return when (tv.brand) {
            TvBrand.SAMSUNG -> {
                if (!portOpen(host, 26101, 700)) return null
                runCatching { samsung.connect(host, quiet = true).use { samsung.readVersion(it) } }.getOrNull()
            }
            TvBrand.ANDROID_TV -> {
                val port = tv.port.takeIf { it > 0 } ?: 5555
                if (!portOpen(host, port, 700)) return null
                try {
                    android.connect(host, port, quiet = true).use { android.readInstalled(it).version }
                } catch (e: AdbException) {
                    if (e.failure == AdbFailure.NEEDS_APPROVAL) env.log("sessiz denetim: TV onay istiyor, vazgeçildi")
                    null
                } catch (_: Exception) { null }
            }
            TvBrand.LG -> {
                if (!lg.hasKey(host) || !portOpen(host, 9922, 700)) return null
                runCatching {
                    lg.connect(host, lg.keyFile(host).readBytes()).use { sh ->
                        val v = lg.readVersion(sh)
                        lg.renewSession(host, sh)
                        v
                    }
                }.getOrNull()
            }
        }
    }

    /** Telefondaki paketin sürümü. */
    fun phoneVersion(brand: TvBrand): String? = env.packages.index.get(brand)?.version
}
