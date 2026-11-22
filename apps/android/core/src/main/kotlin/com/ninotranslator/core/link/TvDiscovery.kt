// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.link

/** Elle yazılan TV (ve PS5) adresinin temizlenmesi (tv.md 2.4). */
object ManualAddress {
    /** Temiz adres (IPv4 ya da küçük harfli ağ adı); geçersizse null (arayüz `address_invalid` gösterir). */
    fun clean(input: String): String? = cleanWithPort(input)?.first

    /** [clean] gibi; yazılmışsa portu da döner (Android TV ekranı portu ayrıca okur). */
    fun cleanWithPort(input: String): Pair<String, Int?>? {
        var s = input.trim().replace(',', '.')
        val scheme = s.indexOf("://")
        if (scheme >= 0) s = s.substring(scheme + 3)
        val cut = s.indexOfFirst { it == '/' || it == '?' || it == '#' }
        if (cut >= 0) s = s.substring(0, cut)
        var port: Int? = null
        when (s.count { it == ':' }) {
            0 -> Unit
            1 -> {
                val p = s.substringAfter(':')
                if (p.isEmpty() || !p.all { it.isDigit() }) return null
                port = p.toIntOrNull()?.takeIf { it in 1..65535 }
                s = s.substringBefore(':')
            }
            else -> return null
        }
        if (s.endsWith('.')) s = s.dropLast(1)
        if (s.isEmpty()) return null
        if (s.all { it.isDigit() || it == '.' }) {
            val parts = s.split('.')
            if (parts.size != 4) return null
            val n = parts.map { part ->
                if (part.isEmpty() || part.length > 3) return null
                part.toInt().takeIf { it in 0..255 } ?: return null
            }
            return n.joinToString(".") to port
        }
        if (s.length > 253 || s.none { it.isLetter() }) return null
        for (label in s.split('.')) {
            if (label.isEmpty() || label.length > 63) return null
            if (label.startsWith('-') || label.endsWith('-')) return null
            if (!label.all { it in 'a'..'z' || it in 'A'..'Z' || it in '0'..'9' || it == '-' }) return null
        }
        return s.lowercase() to port
    }
}

/** SSDP ile görülen TV markası. */
enum class SsdpBrand { LG, SAMSUNG, ANDROID_TV }

/** SSDP yanıtından çıkan TV. */
data class SsdpHit(val address: String, val brand: SsdpBrand, val location: String)

/** SSDP araması (tv.md 2.1): istek metni, yanıt ayrıştırma, aygıt adı. */
object Ssdp {
    const val ADDRESS = "239.255.255.250"
    const val PORT = 1900

    val TARGETS = linkedMapOf(
        "urn:lge-com:service:webos-second-screen:1" to SsdpBrand.LG,
        "urn:samsung.com:device:RemoteControlReceiver:1" to SsdpBrand.SAMSUNG,
        "urn:dial-multiscreen-org:service:dial:1" to SsdpBrand.ANDROID_TV,
    )

    fun search(st: String): String =
        "M-SEARCH * HTTP/1.1\r\nHOST: $ADDRESS:$PORT\r\nMAN: \"ssdp:discover\"\r\nMX: 2\r\nST: $st\r\n\r\n"

    /** Yanıtı ayrıştırır; aranan hedeflerden değilse null. */
    fun parse(response: String): SsdpHit? {
        val headers = HashMap<String, String>()
        for (line in response.split("\r\n", "\n")) {
            val colon = line.indexOf(':')
            if (colon > 0) headers[line.substring(0, colon).trim().lowercase()] = line.substring(colon + 1).trim()
        }
        val target = headers["st"] ?: headers["nt"] ?: return null
        val brand = TARGETS.entries.firstOrNull { it.key.equals(target, ignoreCase = true) }?.value ?: return null
        val location = headers["location"] ?: return null
        val host = runCatching { java.net.URI(location).host }.getOrNull()?.trim('[', ']') ?: return null
        return SsdpHit(host, brand, location)
    }

    /** Aynı adresten birden çok yanıt: LG/Samsung, DIAL'a üstün gelir. Sıra ilk görülene göre. */
    fun merge(hits: List<SsdpHit>): List<SsdpHit> {
        val out = LinkedHashMap<String, SsdpHit>()
        for (h in hits) {
            val old = out[h.address]
            if (old == null || (old.brand == SsdpBrand.ANDROID_TV && h.brand != SsdpBrand.ANDROID_TV)) out[h.address] = h
        }
        return out.values.toList()
    }

    /** Aygıt tanımındaki `<friendlyName>`; yoksa null. */
    fun friendlyName(xml: String): String? {
        val m = Regex("<friendlyName>([^<]*)</friendlyName>", RegexOption.IGNORE_CASE).find(xml) ?: return null
        return m.groupValues[1].trim().replace("&amp;", "&").replace("&lt;", "<").replace("&gt;", ">")
            .replace("&quot;", "\"").replace("&apos;", "'").ifEmpty { null }
    }

    fun fallbackName(brand: SsdpBrand): String = when (brand) {
        SsdpBrand.LG -> "LG TV"
        SsdpBrand.SAMSUNG -> "Samsung TV"
        SsdpBrand.ANDROID_TV -> "Android TV"
    }
}
