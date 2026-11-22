// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.remoteplay

import java.net.Inet4Address
import java.net.NetworkInterface

/** Ağ arayüzünün aramaya gereken özeti (testte elle kurulur). */
data class NetInterface(
    val name: String,
    val isUp: Boolean,
    val isLoopback: Boolean,
    val ipv4: List<String>,
)

/** PS5 aramasının hedef adresleri: telefonun özel ağının /24'ü ya da elle verilen tek adres. */
object NetworkAddresses {

    fun isPrivateIpv4(address: String): Boolean {
        val p = octets(address) ?: return false
        return p[0] == 10 || (p[0] == 172 && p[1] in 16..31) || (p[0] == 192 && p[1] == 168)
    }

    /**
     * Telefonun adresi: açık, geri döngü olmayan arayüzler; `rmnet*` (hücresel) ve `tun*` (VPN) atlanır; `wlan*`
     * önce gelir; ilk özel IPv4 adresi seçilir.
     */
    fun pickLocalAddress(interfaces: List<NetInterface>): String? =
        interfaces.asSequence()
            .filter { it.isUp && !it.isLoopback && !it.name.startsWith("rmnet") && !it.name.startsWith("tun") }
            .sortedBy { if (it.name.startsWith("wlan")) 0 else 1 }
            .flatMap { it.ipv4.asSequence() }
            .firstOrNull { isPrivateIpv4(it) }

    /** Yerel adresin /24 ağında 1–254 arası bütün adresler, kendisi hariç. */
    fun subnetTargets(localAddress: String): List<String> {
        val p = octets(localAddress) ?: return emptyList()
        val prefix = "${p[0]}.${p[1]}.${p[2]}."
        return (1..254).filter { it != p[3] }.map { prefix + it }
    }

    /** Arama hedefleri: adres verilmişse yalnız o; değilse telefonun /24 ağı (yoksa boş). */
    fun searchTargets(address: String?, interfaces: List<NetInterface>): List<String> {
        if (!address.isNullOrBlank()) return listOfNotNull(cleanManualAddress(address))
        val local = pickLocalAddress(interfaces) ?: return emptyList()
        return subnetTargets(local)
    }

    /**
     * Elle yazılan adresi temizler: `http://` gibi önek, yol, port ve virgüllü yazım ayıklanır.
     * Geçerli bir IPv4 değilse null (arayüz `address_invalid` gösterir).
     */
    fun cleanManualAddress(input: String): String? {
        var s = input.trim()
        val scheme = s.indexOf("://")
        if (scheme >= 0) s = s.substring(scheme + 3)
        s = s.substringBefore('/').substringBefore('?').trim()
        if (s.count { it == ',' } == 3 && '.' !in s) s = s.replace(',', '.')
        s = s.substringBefore(':').trim()
        val p = octets(s) ?: return null
        return p.joinToString(".")
    }

    /** Cihazın gerçek arayüzleri (yalnız uygulamada; testler elle liste kurar). */
    fun systemInterfaces(): List<NetInterface> = runCatching {
        NetworkInterface.getNetworkInterfaces()?.toList().orEmpty().map { ni ->
            NetInterface(
                name = ni.name.orEmpty(),
                isUp = runCatching { ni.isUp }.getOrDefault(false),
                isLoopback = runCatching { ni.isLoopback }.getOrDefault(false),
                ipv4 = ni.inetAddresses.toList().filterIsInstance<Inet4Address>().mapNotNull { it.hostAddress },
            )
        }
    }.getOrDefault(emptyList())

    private fun octets(address: String): IntArray? {
        val parts = address.trim().split('.')
        if (parts.size != 4) return null
        val out = IntArray(4)
        for (i in 0 until 4) {
            val t = parts[i]
            if (t.isEmpty() || t.length > 3 || !t.all { it in '0'..'9' }) return null
            val v = t.toInt()
            if (v > 255) return null
            out[i] = v
        }
        return out
    }
}
