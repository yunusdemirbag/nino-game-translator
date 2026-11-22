// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.tv

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.util.Log
import com.ninotranslator.core.link.NinoLink
import com.ninotranslator.core.link.Ssdp
import com.ninotranslator.core.link.SsdpBrand
import com.ninotranslator.core.link.SsdpHit
import com.ninotranslator.mobile.data.TvBrand
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.Inet4Address
import java.net.InetAddress
import java.net.HttpURLConnection
import java.net.SocketTimeoutException
import java.net.URL
import kotlin.coroutines.resume

/**
 * Ağdaki TV'ler: mDNS `_nino._tcp` (Nino açık Android TV'ler) ve SSDP (LG, Samsung, DIAL ile Android TV; tv.md 2.1).
 * Arama süresince çoklu yayın kilidi tutulur (bazı telefonlar kilitsiz çoklu yayın paketlerini atar).
 */
class NetworkTvFinder(context: Context) : TvFinder {
    private val app = context.applicationContext

    override suspend fun search(timeoutMs: Long): List<FoundTv> = withContext(Dispatchers.IO) {
        val wifi = app.getSystemService(Context.WIFI_SERVICE) as? WifiManager
        val lock = wifi?.createMulticastLock("nino-tv-search")?.apply { setReferenceCounted(false) }
        runCatching { lock?.acquire() }
        try {
            coroutineScope {
                val mdns = async { runCatching { searchMdns(timeoutMs) }.getOrElse { log("mDNS", it); emptyList() } }
                val ssdp = async { runCatching { searchSsdp(timeoutMs) }.getOrElse { log("SSDP", it); emptyList() } }
                merge(mdns.await(), ssdp.await())
            }
        } finally {
            runCatching { if (lock?.isHeld == true) lock.release() }
        }
    }

    // --- mDNS ---

    private suspend fun searchMdns(timeoutMs: Long): List<FoundTv> = coroutineScope {
        val nsd = app.getSystemService(Context.NSD_SERVICE) as? NsdManager ?: return@coroutineScope emptyList()
        val found = Channel<NsdServiceInfo>(Channel.UNLIMITED)
        val listener = object : NsdManager.DiscoveryListener {
            override fun onDiscoveryStarted(serviceType: String) = Unit
            override fun onDiscoveryStopped(serviceType: String) = Unit
            override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) { Log.w(TAG, "mDNS başlamadı: $errorCode") }
            override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) = Unit
            override fun onServiceFound(info: NsdServiceInfo) { found.trySend(info) }
            override fun onServiceLost(info: NsdServiceInfo) = Unit
        }
        nsd.discoverServices(NinoLink.SERVICE_TYPE, NsdManager.PROTOCOL_DNS_SD, listener)
        val results = LinkedHashMap<String, FoundTv>()
        val seen = HashSet<String>()
        // Çözümler tek tek: eski Android'de aynı anda iki çözüm hata verir.
        val resolver = launch {
            for (info in found) {
                if (!seen.add(info.serviceName)) continue
                val r = withTimeoutOrNull(2_000) { resolve(nsd, info) } ?: continue
                val host = hostOf(r) ?: continue
                results[host] = FoundTv(r.serviceName, host, TvBrand.ANDROID_TV, r.port.takeIf { it > 0 } ?: NinoLink.DEFAULT_PORT, hasNino = true)
            }
        }
        delay(timeoutMs)
        runCatching { nsd.stopServiceDiscovery(listener) }
        found.close()
        // Son çözüm biraz daha sürebilir.
        withTimeoutOrNull(1_500) { resolver.join() }
        resolver.cancel()
        results.values.toList()
    }

    @Suppress("DEPRECATION")
    private suspend fun resolve(nsd: NsdManager, info: NsdServiceInfo): NsdServiceInfo? = suspendCancellableCoroutine { c ->
        nsd.resolveService(info, object : NsdManager.ResolveListener {
            override fun onResolveFailed(serviceInfo: NsdServiceInfo, errorCode: Int) { if (c.isActive) c.resume(null) }
            override fun onServiceResolved(serviceInfo: NsdServiceInfo) { if (c.isActive) c.resume(serviceInfo) }
        })
    }

    @Suppress("DEPRECATION")
    private fun hostOf(info: NsdServiceInfo): String? {
        val addresses: List<InetAddress> = if (Build.VERSION.SDK_INT >= 34) info.hostAddresses else listOfNotNull(info.host)
        val pick = addresses.firstOrNull { it is Inet4Address } ?: addresses.firstOrNull() ?: return null
        return pick.hostAddress?.substringBefore('%')
    }

    // --- SSDP ---

    private suspend fun searchSsdp(timeoutMs: Long): List<FoundTv> {
        val hits = ArrayList<SsdpHit>()
        DatagramSocket().use { socket ->
            socket.soTimeout = 300
            val group = InetAddress.getByName(Ssdp.ADDRESS)
            repeat(2) {
                for (st in Ssdp.TARGETS.keys) {
                    val bytes = Ssdp.search(st).toByteArray(Charsets.US_ASCII)
                    runCatching { socket.send(DatagramPacket(bytes, bytes.size, group, Ssdp.PORT)) }
                }
            }
            val end = System.currentTimeMillis() + minOf(timeoutMs, 3_000)
            val buf = ByteArray(4096)
            while (System.currentTimeMillis() < end) {
                val p = DatagramPacket(buf, buf.size)
                try { socket.receive(p) } catch (_: SocketTimeoutException) { continue }
                Ssdp.parse(String(p.data, 0, p.length, Charsets.UTF_8))?.let { hits += it }
            }
        }
        return coroutineScope {
            Ssdp.merge(hits).map { h -> async { FoundTv(friendlyName(h.location) ?: Ssdp.fallbackName(h.brand), h.address, brandOf(h.brand)) } }.awaitAll()
        }
    }

    private fun friendlyName(location: String): String? = runCatching {
        val c = URL(location).openConnection() as HttpURLConnection
        c.connectTimeout = 1_500; c.readTimeout = 1_500
        try {
            if (c.responseCode !in 200..299) return null
            Ssdp.friendlyName(c.inputStream.use { it.readBytes().toString(Charsets.UTF_8) })
        } finally { c.disconnect() }
    }.getOrNull()

    private fun brandOf(b: SsdpBrand) = when (b) {
        SsdpBrand.LG -> TvBrand.LG
        SsdpBrand.SAMSUNG -> TvBrand.SAMSUNG
        SsdpBrand.ANDROID_TV -> TvBrand.ANDROID_TV
    }

    private fun log(what: String, e: Throwable) = Log.w(TAG, "$what araması olmadı: ${e.message}")

    companion object {
        private const val TAG = "NinoTv"

        /** mDNS (Nino açık) önce; aynı adres SSDP'de de varsa mDNS kaydı kalır. Sonra LG/Samsung, en son DIAL. */
        internal fun merge(mdns: List<FoundTv>, ssdp: List<FoundTv>): List<FoundTv> {
            val out = LinkedHashMap<String, FoundTv>()
            mdns.forEach { out[it.address] = it }
            ssdp.sortedBy { if (it.brand == TvBrand.ANDROID_TV) 1 else 0 }.forEach { out.putIfAbsent(it.address, it) }
            return out.values.toList()
        }
    }
}
