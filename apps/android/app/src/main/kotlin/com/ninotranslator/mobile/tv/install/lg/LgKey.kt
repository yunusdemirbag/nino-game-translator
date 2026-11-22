// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.tv.install.lg

import org.bouncycastle.crypto.BufferedBlockCipher
import org.bouncycastle.crypto.engines.AESEngine
import org.bouncycastle.crypto.engines.DESedeEngine
import org.bouncycastle.crypto.modes.CBCBlockCipher
import org.bouncycastle.crypto.paddings.PaddedBufferedBlockCipher
import org.bouncycastle.crypto.params.KeyParameter
import org.bouncycastle.crypto.params.ParametersWithIV
import java.security.MessageDigest
import java.util.Base64

/**
 * LG Key Server'ın verdiği anahtar (tv.md 3.2). Eski PEM şifrelemesi (`Proc-Type: 4,ENCRYPTED`, `DEK-Info`) burada
 * çözülür: DES-EDE3-CBC ya da AES-128/192/256-CBC, anahtar OpenSSL EVP_BytesToKey (MD5, tek tur, tuz = IV'nin ilk 8
 * baytı). Başka biçimleri (OpenSSH) SSH kütüphanesi çözer.
 */
object LgKey {
    sealed interface Result {
        /** Parolasız anahtar (PEM metni baytları). */
        class Decrypted(val pem: ByteArray) : Result
        data object WrongPassphrase : Result
        /** Eski PEM şifrelemesi değil; SSH kütüphanesine bırakılır. */
        data object OtherFormat : Result
        data object NotAKey : Result
    }

    fun looksLikeKey(text: String): Boolean = text.contains("PRIVATE KEY")

    /** Denenecek parolalar: yazılan, ve küçük harf varsa büyük harflisi (TV büyük harfle gösterir). */
    fun candidates(passphrase: String): List<String> {
        val p = passphrase.trim()
        return listOf(p, p.uppercase()).distinct().filter { it.isNotEmpty() }
    }

    fun decrypt(text: String, passphrase: String): Result {
        if (!looksLikeKey(text)) return Result.NotAKey
        val lines = text.lines().map { it.trim() }
        val begin = lines.indexOfFirst { it.startsWith("-----BEGIN ") && it.endsWith("PRIVATE KEY-----") }
        if (begin < 0) return Result.NotAKey
        val end = lines.indexOfFirst { it.startsWith("-----END ") }
        if (end <= begin) return Result.NotAKey
        val header = lines[begin]
        val body = lines.subList(begin + 1, end)
        val headers = body.takeWhile { it.contains(':') }.associate { it.substringBefore(':').trim() to it.substringAfter(':').trim() }
        val b64 = body.drop(headers.size).filter { it.isNotEmpty() }.joinToString("")
        val der = runCatching { Base64.getMimeDecoder().decode(b64) }.getOrNull() ?: return Result.NotAKey
        if (!headers["Proc-Type"].orEmpty().contains("ENCRYPTED")) {
            return if (header.contains("OPENSSH") || header.contains("ENCRYPTED PRIVATE KEY")) Result.OtherFormat
            else Result.Decrypted(text.trim().toByteArray(Charsets.US_ASCII))
        }
        val dek = headers["DEK-Info"] ?: return Result.OtherFormat
        val cipherName = dek.substringBefore(',').trim().uppercase()
        val iv = runCatching { hex(dek.substringAfter(',').trim()) }.getOrNull() ?: return Result.NotAKey
        val keyLen = when (cipherName) {
            "DES-EDE3-CBC" -> 24
            "AES-128-CBC" -> 16
            "AES-192-CBC" -> 24
            "AES-256-CBC" -> 32
            else -> return Result.OtherFormat
        }
        if (iv.size < 8) return Result.NotAKey
        for (p in candidates(passphrase)) {
            val key = bytesToKey(p.toByteArray(Charsets.UTF_8), iv.copyOf(8), keyLen)
            val plain = runCatching {
                val engine = if (cipherName.startsWith("DES")) DESedeEngine() else AESEngine.newInstance()
                val c: BufferedBlockCipher = PaddedBufferedBlockCipher(CBCBlockCipher.newInstance(engine))
                c.init(false, ParametersWithIV(KeyParameter(key), iv))
                val out = ByteArray(c.getOutputSize(der.size))
                val n = c.processBytes(der, 0, der.size, out, 0)
                out.copyOf(n + c.doFinal(out, n))
            }.getOrNull() ?: continue
            if (!isAsn1Sequence(plain)) continue
            val type = header.removePrefix("-----BEGIN ").removeSuffix("-----")
            val pem = buildString {
                append("-----BEGIN ").append(type).append("-----\n")
                Base64.getEncoder().encodeToString(plain).chunked(64).forEach { append(it).append('\n') }
                append("-----END ").append(type).append("-----\n")
            }
            return Result.Decrypted(pem.toByteArray(Charsets.US_ASCII))
        }
        return Result.WrongPassphrase
    }

    /** OpenSSL EVP_BytesToKey(MD5, tek tur). */
    fun bytesToKey(password: ByteArray, salt: ByteArray, keyLen: Int): ByteArray {
        val md5 = MessageDigest.getInstance("MD5")
        val out = ArrayList<Byte>()
        var prev = ByteArray(0)
        while (out.size < keyLen) {
            md5.reset(); md5.update(prev); md5.update(password); md5.update(salt)
            prev = md5.digest()
            prev.forEach { out += it }
        }
        return out.take(keyLen).toByteArray()
    }

    /** 0x30 + tutan DER uzunluğu. */
    fun isAsn1Sequence(b: ByteArray): Boolean {
        if (b.size < 2 || b[0].toInt() != 0x30) return false
        val first = b[1].toInt() and 0xFF
        val (len, header) = if (first < 0x80) first to 2 else {
            val n = first and 0x7F
            if (n == 0 || n > 4 || b.size < 2 + n) return false
            var l = 0
            for (i in 0 until n) l = (l shl 8) or (b[2 + i].toInt() and 0xFF)
            l to 2 + n
        }
        return header + len == b.size
    }

    private fun hex(s: String): ByteArray {
        require(s.length % 2 == 0)
        return ByteArray(s.length / 2) { s.substring(2 * it, 2 * it + 2).toInt(16).toByte() }
    }
}
