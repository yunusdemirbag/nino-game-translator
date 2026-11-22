// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.tv.install.adb

import com.ninotranslator.mobile.tv.install.LocalIoException
import org.bouncycastle.crypto.digests.SHA256Digest
import org.bouncycastle.crypto.engines.AESEngine
import org.bouncycastle.crypto.generators.HKDFBytesGenerator
import org.bouncycastle.crypto.modes.GCMBlockCipher
import org.bouncycastle.crypto.params.AEADParameters
import org.bouncycastle.crypto.params.HKDFParameters
import org.bouncycastle.crypto.params.KeyParameter
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.security.SecureRandom

/**
 * Kablosuz hata ayıklama eşlemesi (AOSP `pairing_connection`, `pairing_auth`): TLS 1.3 → dışa aktarılan anahtar
 * malzemesi → SPAKE2 → AES-128-GCM ile eş bilgisi alışverişi.
 */
object AdbPairing {
    const val EXPORT_LABEL = "adb-label\u0000"
    const val EXPORT_LENGTH = 64
    val CLIENT_NAME = "adb pair client\u0000".toByteArray(Charsets.US_ASCII)
    val SERVER_NAME = "adb pair server\u0000".toByteArray(Charsets.US_ASCII)
    private val HKDF_INFO = "adb pairing_auth aes-128-gcm key".toByteArray(Charsets.US_ASCII)
    const val PEER_INFO_SIZE = 8192
    const val TYPE_SPAKE2 = 0
    const val TYPE_PEER_INFO = 1
    const val PEER_RSA_PUB_KEY = 0
    private const val MAX_PAYLOAD = 2 * PEER_INFO_SIZE

    class PairingException(message: String, cause: Throwable? = null) : LocalIoException(message, cause)

    /** Paket: sürüm (1), tür, 4 bayt büyük-endian uzunluk, veri. */
    fun writePacket(out: OutputStream, type: Int, payload: ByteArray) {
        val h = byteArrayOf(1, type.toByte(), (payload.size ushr 24).toByte(), (payload.size ushr 16).toByte(),
            (payload.size ushr 8).toByte(), payload.size.toByte())
        out.write(h + payload)
        out.flush()
    }

    fun readPacket(input: InputStream, expectedType: Int): ByteArray {
        val h = AdbMessage.readFully(input, 6)
        if (h[0].toInt() != 1) throw PairingException("eşleme paketi sürümü ${h[0]}")
        if (h[1].toInt() != expectedType) throw PairingException("beklenmeyen eşleme paketi türü ${h[1]}")
        val len = ((h[2].toInt() and 0xFF) shl 24) or ((h[3].toInt() and 0xFF) shl 16) or ((h[4].toInt() and 0xFF) shl 8) or (h[5].toInt() and 0xFF)
        if (len <= 0 || len > MAX_PAYLOAD) throw PairingException("eşleme paketi uzunluğu $len")
        return AdbMessage.readFully(input, len)
    }

    /** SPAKE2 anahtarından AES-128-GCM anahtarı (HKDF-SHA256, tuzsuz). */
    fun cipherKey(spakeKey: ByteArray): ByteArray {
        val g = HKDFBytesGenerator(SHA256Digest())
        g.init(HKDFParameters(spakeKey, null, HKDF_INFO))
        return ByteArray(16).also { g.generateBytes(it, 0, it.size) }
    }

    /** Bir yöndeki şifreleme: nonce'un ilk 8 baytı 0'dan sayan küçük-endian sıra numarası. */
    class Aead(private val key: ByteArray) {
        private var encSeq = 0L
        private var decSeq = 0L

        private fun nonce(seq: Long) = ByteArray(12).also { var s = seq; for (i in 0 until 8) { it[i] = s.toByte(); s = s ushr 8 } }

        fun encrypt(plain: ByteArray): ByteArray {
            val c = GCMBlockCipher.newInstance(AESEngine.newInstance())
            c.init(true, AEADParameters(KeyParameter(key), 128, nonce(encSeq++)))
            val out = ByteArray(c.getOutputSize(plain.size))
            val n = c.processBytes(plain, 0, plain.size, out, 0)
            c.doFinal(out, n)
            return out
        }

        /** Çözülemezse null (kod yanlış). */
        fun decrypt(data: ByteArray): ByteArray? = runCatching {
            val c = GCMBlockCipher.newInstance(AESEngine.newInstance())
            c.init(false, AEADParameters(KeyParameter(key), 128, nonce(decSeq++)))
            val out = ByteArray(c.getOutputSize(data.size))
            val n = c.processBytes(data, 0, data.size, out, 0)
            c.doFinal(out, n)
            out
        }.getOrNull()
    }

    /** Telefonun eş bilgisi: ilk bayt 0 (RSA açık anahtar), ardından anahtar satırı; 8192 bayta sıfırla doldurulur. */
    fun peerInfo(keyLine: String): ByteArray {
        val b = ByteArray(PEER_INFO_SIZE)
        b[0] = PEER_RSA_PUB_KEY.toByte()
        val k = keyLine.toByteArray(Charsets.US_ASCII)
        k.copyInto(b, 1, 0, minOf(k.size, PEER_INFO_SIZE - 2))
        return b
    }

    /**
     * Eşleme TLS'i kurulmuş akış üstünde yürür. [exported] TLS dışa aktarıcısının 64 baytı. Kod yanlışsa ya da TV
     * bağlantıyı kapatırsa [PairingException]. TV'nin eş bilgisini döner.
     */
    fun exchange(
        input: InputStream, output: OutputStream, code: String, exported: ByteArray, keyLine: String,
        random: SecureRandom = SecureRandom(),
    ): ByteArray {
        val password = code.toByteArray(Charsets.US_ASCII) + exported
        val spake = Spake2(alice = true, myName = CLIENT_NAME, theirName = SERVER_NAME, random = random)
        writePacket(output, TYPE_SPAKE2, spake.generateMessage(password))
        val theirMsg = try { readPacket(input, TYPE_SPAKE2) } catch (e: IOException) { throw PairingException("TV SPAKE2 mesajı göndermedi: ${e.message}", e) }
        val key = spake.processMessage(theirMsg) ?: throw PairingException("TV'nin SPAKE2 mesajı eğride değil")
        val aead = Aead(cipherKey(key))
        writePacket(output, TYPE_PEER_INFO, aead.encrypt(peerInfo(keyLine)))
        val theirs = try { readPacket(input, TYPE_PEER_INFO) } catch (e: IOException) { throw PairingException("TV eş bilgisini göndermedi (kod yanlış olabilir): ${e.message}", e) }
        return aead.decrypt(theirs) ?: throw PairingException("TV'nin eş bilgisi çözülemedi (kod yanlış)")
    }

    /** Eşleme portuna bağlanıp eşler (5 sn bağlantı, 15 sn okuma). */
    fun pair(host: String, port: Int, code: String, key: AdbKey, log: (String) -> Unit = {}) {
        AdbTransport.socket(host, port, 5_000, 15_000).use { t ->
            val tls = try { AdbTls.connect(t.input, t.output, key, EXPORT_LABEL to EXPORT_LENGTH) } catch (e: Exception) { throw PairingException("eşleme TLS'i kurulamadı: ${e.message}", e) }
            val exported = tls.exported ?: throw PairingException("TLS anahtar malzemesi alınamadı")
            log("eşleme TLS'i kuruldu; SPAKE2")
            val info = exchange(tls.input, tls.output, code, exported, key.publicKeyLine(AdbDialect.ADB.keyName))
            log("eşlendi (TV eş bilgisi türü ${info.firstOrNull()})")
            runCatching { tls.protocol.close() }
        }
    }
}
