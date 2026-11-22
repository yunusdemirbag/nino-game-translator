// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.xbox

import com.ninotranslator.core.json.Json
import com.ninotranslator.core.json.str
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.ArrayDeque
import java.util.UUID

/** Veri kanalı: ad ve alt protokol. */
data class XboxChannelSpec(val label: String, val protocol: String)

/**
 * Veri kanallarının iletileri (servis.md 10.4 madde 4). Sabitler açık kaynak (MIT) Xbox web oynatıcısının herkese açık
 * değerleridir. Nino kumanda/dokunma girdisi göndermez; yalnız yayının sürmesi için gereken iletiler.
 */
object XboxChannelMessages {
    const val INPUT = "input"
    const val CHAT = "chat"
    const val CONTROL = "control"
    const val MESSAGE = "message"

    /** Açılış sırası. */
    val CHANNELS = listOf(
        XboxChannelSpec(INPUT, "1.0"), XboxChannelSpec(CHAT, "chatV1"),
        XboxChannelSpec(CONTROL, "controlV1"), XboxChannelSpec(MESSAGE, "messageV1"),
    )

    private const val HANDSHAKE_ID = "be0bfc6d-1e83-4c8a-90ed-fa8601c5a179"
    private const val ACCESS_KEY = "4BDB3609-C1F1-4195-9B37-FEFF45DA8B8E"
    private const val CLIENT_APP_INSTALL_ID = "c97d7ee0-73b2-4239-bf1d-9d805a338429"

    /** `input` paket türleri. */
    const val REPORT_FRAMES = 1
    const val REPORT_CLIENT_INFO = 8
    const val REPORT_VIBRATION = 128

    const val HEADER_BYTES = 14
    const val FRAME_BYTES = 28
    const val MAX_FRAMES_PER_PACKET = 29

    fun handshake(): String = Json.write(linkedMapOf("type" to "Handshake", "version" to "messageV1", "id" to HANDSHAKE_ID, "cv" to "0"))

    fun isHandshakeAck(text: String): Boolean = runCatching { Json.parseObject(text).str("type") == "HandshakeAck" }.getOrDefault(false)

    fun authorization(): String = Json.write(linkedMapOf("message" to "authorizationRequest", "accessKey" to ACCESS_KEY))

    fun gamepadAdded(index: Int = 0): String =
        Json.write(linkedMapOf("message" to "gamepadChanged", "gamepadIndex" to index, "wasAdded" to true))

    /** El sıkışmadan sonraki altı yapılandırma iletisi. [newId]: her iletinin kimliği. */
    fun configuration(width: Int = XboxStreamApi.WIDTH, height: Int = XboxStreamApi.HEIGHT,
                      newId: () -> String = { UUID.randomUUID().toString() }): List<String> = listOf(
        message("/streaming/systemUi/configuration", linkedMapOf("version" to listOf(0, 2, 0), "systemUis" to emptyList<Int>()), newId),
        message("/streaming/properties/clientappinstallidchanged", linkedMapOf("clientAppInstallId" to CLIENT_APP_INSTALL_ID), newId),
        message("/streaming/characteristics/orientationchanged", linkedMapOf("orientation" to 0), newId),
        message("/streaming/characteristics/touchinputenabledchanged", linkedMapOf("touchInputEnabled" to false), newId),
        message("/streaming/characteristics/clientdevicecapabilities", linkedMapOf<String, Any?>(), newId),
        message("/streaming/characteristics/dimensionschanged", linkedMapOf(
            "horizontal" to width, "vertical" to height, "preferredWidth" to width, "preferredHeight" to height,
            "safeAreaLeft" to 0, "safeAreaTop" to 0, "safeAreaRight" to width, "safeAreaBottom" to height,
            "supportsCustomResolution" to true,
        ), newId),
    )

    private fun message(target: String, content: Map<String, Any?>, newId: () -> String) = Json.write(linkedMapOf(
        "type" to "Message", "content" to Json.write(content), "id" to newId(), "target" to target, "cv" to "",
    ))

    private fun header(size: Int, type: Int, sequence: Long, timestampMs: Double): ByteBuffer =
        ByteBuffer.allocate(size).order(ByteOrder.LITTLE_ENDIAN).apply {
            putShort(type.toShort()); putInt(sequence.toInt()); putDouble(timestampMs)
        }

    /** İstemci bilgisi: 15 bayt (tür 8, sıra 0, zaman, en çok dokunma noktası 1–2). */
    fun clientInfo(timestampMs: Double, maxTouchPoints: Int = 2): ByteArray =
        header(HEADER_BYTES + 1, REPORT_CLIENT_INFO, 0, timestampMs).put(maxTouchPoints.coerceIn(1, 2).toByte()).array()

    /**
     * Kare onayı paketi: tür 1, sıra, zaman, kare sayısı (u8), her kare için yedi u32: RTP anahtarı, varış, varış,
     * çözülme, çözülme, şimdi, şimdi.
     */
    fun frameAcks(sequence: Long, nowMs: Double, frames: List<FrameTiming>): ByteArray {
        require(frames.size <= MAX_FRAMES_PER_PACKET)
        val b = header(HEADER_BYTES + 1 + FRAME_BYTES * frames.size, REPORT_FRAMES, sequence, nowMs)
        b.put(frames.size.toByte())
        val now = nowMs.toLong()
        for (f in frames) {
            u32(b, f.rtpKey); u32(b, f.arrivalMs); u32(b, f.arrivalMs)
            u32(b, f.decodedMs); u32(b, f.decodedMs); u32(b, now); u32(b, now)
        }
        return b.array()
    }

    private fun u32(b: ByteBuffer, v: Long) { b.putInt((v and 0xFFFFFFFFL).toInt()) }

    /** Karenin RTP anahtarı: yakalama ms × 90, alt 32 bit. */
    fun rtpKey(captureMs: Long): Long = (captureMs * 90) and 0xFFFFFFFFL

    /** Gelen ikili iletinin türü (ilk iki bayt, little endian). */
    fun reportType(bytes: ByteArray): Int = if (bytes.size < 2) -1 else (bytes[0].toInt() and 0xFF) or ((bytes[1].toInt() and 0xFF) shl 8)
}

/** Çözülen bir karenin anları (oturum saatinin sıfırından ms). */
data class FrameTiming(val rtpKey: Long, val arrivalMs: Long, val decodedMs: Long)

/** Onay bekleyen kareler: en çok [capacity]; taşarsa eskiler atılır. İş parçacığı güvenli. */
class FrameAckQueue(private val capacity: Int = 600) {
    private val q = ArrayDeque<FrameTiming>()
    var dropped = 0L; private set

    @Synchronized fun add(f: FrameTiming) {
        if (q.size >= capacity) { q.removeFirst(); dropped++ }
        q.addLast(f)
    }

    @Synchronized fun take(max: Int = XboxChannelMessages.MAX_FRAMES_PER_PACKET): List<FrameTiming> {
        val out = ArrayList<FrameTiming>(minOf(max, q.size))
        while (out.size < max && q.isNotEmpty()) out += q.removeFirst()
        return out
    }

    @Synchronized fun size() = q.size
    @Synchronized fun clear() = q.clear()
}
