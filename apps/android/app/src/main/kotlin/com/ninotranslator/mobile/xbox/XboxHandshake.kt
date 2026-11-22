// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.xbox

/** Oturum kurulumunun WebRTC tarafı; gerçeği libwebrtc, testte sahtesi. Her adım engelleyicidir. */
interface XboxPeerSide {
    /** Teklif üretir (yerel tanım henüz konmaz). */
    fun makeOffer(): String
    fun applyLocal(sdp: String)
    fun applyAnswer(sdp: String)
    /** Yerel adaylar; en çok [maxWaitMs] toplanır. */
    fun collectCandidates(maxWaitMs: Long): List<XboxIceCandidate>
    fun addRemote(candidate: XboxIceCandidate)
}

/**
 * Yayın oturumunu açan durum makinesi (servis.md 10.4 madde 1–3): oturum aç → saniyede bir durum sor (en çok 90;
 * ReadyToConnect'te bir kez bağlan) → SDP ve ICE değiş-tokuşu (250 ms arayla en çok 30 soru). Engelleyicidir;
 * [sleep] durdurulunca [InterruptedException] atmalıdır.
 */
class XboxHandshake(
    private val api: XboxStreamApi,
    private val transferToken: () -> String,
    private val sleep: (Long) -> Unit = Thread::sleep,
) {
    /** Oturumu açar, kimliğini döndürür. */
    fun open(serverId: String): String = api.play(serverId)

    /** Konsol hazırlanana kadar bekler. */
    fun awaitProvisioned(id: String) {
        var connected = false
        repeat(STATE_POLLS) {
            val s = api.state(id)
            when {
                s.state == "Provisioned" -> return
                s.state == "Failed" || hasError(s.errorDetails) -> throw XboxStreamException(rejectReason(s.errorDetails), rejected = true,
                    detail = describe(s.errorDetails) ?: s.state)
                s.state == "ReadyToConnect" && !connected -> {
                    api.connect(id, transferToken())
                    connected = true
                }
            }
            sleep(STATE_INTERVAL_MS)
        }
        throw XboxStreamException(XboxProblem.TIMEOUT, detail = "durum hazır olmadı")
    }

    /** SDP teklifi/yanıtı ve ICE aday değişimi. */
    fun negotiate(id: String, peer: XboxPeerSide) {
        val offer = XboxSdp.withVideoBitrate(XboxSdp.withStereo(peer.makeOffer()), api.profile.maxBitrateKbps)
        peer.applyLocal(offer)
        val sdpExchange = exchange(id, "sdp", api.postOffer(id, offer))
        val answer = XboxStreamApi.answerSdp(sdpExchange) ?: throw XboxStreamException(XboxProblem.SERVICE, detail = "SDP yanıtı yok")
        peer.applyAnswer(answer)
        val local = peer.collectCandidates(GATHER_MS)
        val iceExchange = exchange(id, "ice", api.postIce(id, local))
        XboxSdp.expandRemote(XboxStreamApi.remoteCandidates(iceExchange)).forEach(peer::addRemote)
    }

    private fun exchange(id: String, kind: String, posted: String): String {
        XboxStreamApi.exchangeOf(posted)?.let { return it }
        repeat(EXCHANGE_POLLS) {
            sleep(EXCHANGE_INTERVAL_MS)
            api.exchange(id, kind)?.let { return it }
        }
        throw XboxStreamException(XboxProblem.TIMEOUT, detail = "$kind yanıtı gelmedi")
    }

    companion object {
        const val STATE_POLLS = 90
        const val STATE_INTERVAL_MS = 1_000L
        const val EXCHANGE_POLLS = 30
        const val EXCHANGE_INTERVAL_MS = 250L
        const val GATHER_MS = 5_000L

        /** Boş nesne ya da bütün alanları boş/null nesne hata değildir. */
        fun hasError(details: Map<String, Any?>?): Boolean = details != null && details.values.any(::filled)

        private fun filled(v: Any?): Boolean = when (v) {
            null -> false
            is String -> v.isNotBlank()
            is Map<*, *> -> v.values.any(::filled)
            is Collection<*> -> v.any(::filled)
            else -> true
        }

        fun rejectReason(details: Map<String, Any?>?): XboxProblem {
            val text = details?.values?.joinToString(" ").orEmpty()
            return when {
                listOf("InUse", "Busy", "AlreadyStreaming").any { text.contains(it, ignoreCase = true) } -> XboxProblem.BUSY
                isStartFailure(text) -> XboxProblem.START_FAILED
                else -> XboxProblem.UNREACHABLE
            }
        }

        /** "StartStreamingSession failed" ve benzeri: Xbox yayını başlatamadı. */
        fun isStartFailure(text: String): Boolean = text.contains("StartStreamingSession", ignoreCase = true) ||
            text.contains("StartStreamFailed", ignoreCase = true) || text.contains("StreamingSessionFailed", ignoreCase = true)

        private fun describe(details: Map<String, Any?>?): String? =
            details?.values?.filter(::filled)?.joinToString(": ")?.takeIf { it.isNotBlank() }
    }
}

/** SDP ve aday düzeltmeleri (10.4 madde 3). Saf. */
object XboxSdp {
    /**
     * Görüntü bölümüne (`m=video`) `b=AS:<kbps>` yazar (varsa eskisinin yerine); [kbps] null ise SDP değişmez.
     * SDP kuralı gereği `c=` satırından sonra, yoksa `m=` satırından sonra.
     */
    fun withVideoBitrate(sdp: String, kbps: Int?): String {
        if (kbps == null || kbps <= 0) return sdp
        val eol = if (sdp.contains("\r\n")) "\r\n" else "\n"
        val lines = sdp.split(eol).toMutableList()
        val start = lines.indexOfFirst { it.startsWith("m=video") }
        if (start < 0) return sdp
        var end = (start + 1 until lines.size).firstOrNull { lines[it].startsWith("m=") } ?: lines.size
        for (i in end - 1 downTo start + 1) if (lines[i].startsWith("b=AS:")) { lines.removeAt(i); end-- }
        val c = (start + 1 until end).firstOrNull { lines[it].startsWith("c=") }
        lines.add((c ?: start) + 1, "b=AS:$kbps")
        return lines.joinToString(eol)
    }

    /** İlk `useinbandfec=1` → `useinbandfec=1; stereo=1`. */
    fun withStereo(sdp: String): String {
        val i = sdp.indexOf("useinbandfec=1")
        if (i < 0) return sdp
        val end = i + "useinbandfec=1".length
        return sdp.substring(0, end) + "; stereo=1" + sdp.substring(end)
    }

    /**
     * Xbox'un adayları: `end-of-candidates` atlanır; adresi `2001` ile başlayan (Teredo) adayın önüne adresten çıkan
     * IPv4 ile iki aday (port 9002 ve Teredo portu) eklenir.
     */
    fun expandRemote(list: List<XboxIceCandidate>): List<XboxIceCandidate> = buildList {
        for (c in list) {
            if (c.candidate.contains("end-of-candidates")) continue
            val address = c.candidate.trim().split(' ').getOrNull(4)
            val decoded = address?.takeIf { it.startsWith("2001") }?.let(::teredo)
            if (decoded != null) {
                add(c.copy(candidate = "a=candidate:10 1 UDP 1 ${decoded.first} 9002 typ host "))
                add(c.copy(candidate = "a=candidate:11 1 UDP 1 ${decoded.first} ${decoded.second} typ host "))
            }
            add(c)
        }
    }

    /** Teredo adresinden (2001:0:sunucu:sunucu:bayrak:port^:ip^:ip^) istemcinin IPv4'ü ve portu; değilse null. */
    fun teredo(address: String): Pair<String, Int>? {
        val g = groups(address.substringBefore('%')) ?: return null
        if (g[0] != 0x2001 || g[1] != 0) return null
        val port = g[5] xor 0xFFFF
        val hi = g[6] xor 0xFFFF
        val lo = g[7] xor 0xFFFF
        return "${hi shr 8}.${hi and 0xFF}.${lo shr 8}.${lo and 0xFF}" to port
    }

    private fun groups(text: String): IntArray? {
        if (':' !in text) return null
        val parts = text.split("::")
        if (parts.size > 2) return null
        val head = parts[0].split(':').filter { it.isNotEmpty() }
        val tail = if (parts.size == 2) parts[1].split(':').filter { it.isNotEmpty() } else emptyList()
        val fill = 8 - head.size - tail.size
        if (fill < 0 || (parts.size == 1 && fill != 0)) return null
        val all = head + List(fill) { "0" } + tail
        return IntArray(8) { i -> all[i].toIntOrNull(16)?.takeIf { it in 0..0xFFFF } ?: return null }
    }
}
