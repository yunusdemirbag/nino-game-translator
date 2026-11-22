// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.tv.install.adb

import org.bouncycastle.crypto.digests.SHA1Digest
import org.bouncycastle.crypto.encodings.PKCS1Encoding
import org.bouncycastle.crypto.engines.RSABlindedEngine
import org.bouncycastle.crypto.params.RSAPrivateCrtKeyParameters
import org.bouncycastle.crypto.signers.RSADigestSigner
import org.bouncycastle.crypto.util.PrivateKeyFactory
import java.io.File
import java.math.BigInteger
import java.security.KeyFactory
import java.security.KeyPairGenerator
import java.security.PublicKey
import java.security.SecureRandom
import java.security.interfaces.RSAPrivateCrtKey
import java.security.spec.PKCS8EncodedKeySpec
import java.security.spec.RSAPublicKeySpec
import java.util.Base64

/**
 * Telefonun ADB/SDB anahtarı: 2048 bit RSA, PKCS#8 DER olarak yedeklenmeyen klasörde (`no_backup/adb/adbkey`,
 * `no_backup/sdb/adbkey`). TV bu anahtarı bir kez onaylar.
 */
class AdbKey(val privateKey: RSAPrivateCrtKey) {
    val publicKey: PublicKey = KeyFactory.getInstance("RSA").generatePublic(RSAPublicKeySpec(privateKey.modulus, privateKey.publicExponent))

    private val bcPrivate: RSAPrivateCrtKeyParameters =
        PrivateKeyFactory.createKey(privateKey.encoded) as RSAPrivateCrtKeyParameters

    /**
     * adb imzası: jeton yeniden özetlenmez. 20 baytlık jeton SHA-1 DigestInfo önekiyle doğrudan PKCS#1 v1.5 (tür 1)
     * dolgusuna konup RSA ile imzalanır (OpenSSL `RSA_sign(NID_sha1, …)` ile aynı).
     */
    fun signAdbToken(token: ByteArray): ByteArray {
        val enc = PKCS1Encoding(RSABlindedEngine())
        enc.init(true, bcPrivate)
        val block = SHA1_DIGEST_INFO + token
        return enc.processBlock(block, 0, block.size)
    }

    /** sdb imzası: jeton SHA1withRSA ile özetlenerek imzalanır. */
    fun signSha1WithRsa(token: ByteArray): ByteArray {
        val s = RSADigestSigner(SHA1Digest())
        s.init(true, bcPrivate)
        s.update(token, 0, token.size)
        return s.generateSignature()
    }

    /** adb açık anahtar satırı: base64(RSAPublicKey yapısı) + " " + [name]. */
    fun publicKeyLine(name: String): String = Base64.getEncoder().encodeToString(androidPublicKey(privateKey.modulus, privateKey.publicExponent)) + " " + name

    companion object {
        private val SHA1_DIGEST_INFO = byteArrayOf(
            0x30, 0x21, 0x30, 0x09, 0x06, 0x05, 0x2b, 0x0e, 0x03, 0x02, 0x1a, 0x05, 0x00, 0x04, 0x14,
        )
        private const val WORDS = 64 // 2048 bit

        /**
         * Android `RSAPublicKey` yapısı (küçük-endian): sözcük sayısı (64), n0inv = -1/n mod 2^32, modül (256 bayt),
         * R² mod n (R = 2^2048, 256 bayt), üs.
         */
        fun androidPublicKey(n: BigInteger, e: BigInteger): ByteArray {
            require(n.bitLength() <= WORDS * 32) { "anahtar 2048 bitten büyük" }
            val out = ByteArray(4 + 4 + WORDS * 4 + WORDS * 4 + 4)
            val r32 = BigInteger.ONE.shiftLeft(32)
            val n0inv = r32.subtract(n.mod(r32).modInverse(r32)).toLong().toInt()
            val rr = BigInteger.ONE.shiftLeft(WORDS * 32 * 2).mod(n)
            AdbMessage.putLe(out, 0, WORDS)
            AdbMessage.putLe(out, 4, n0inv)
            littleEndian(n, out, 8)
            littleEndian(rr, out, 8 + WORDS * 4)
            AdbMessage.putLe(out, 8 + WORDS * 8, e.toInt())
            return out
        }

        private fun littleEndian(v: BigInteger, out: ByteArray, off: Int) {
            val be = v.toByteArray()
            for (i in 0 until WORDS * 4) {
                val j = be.size - 1 - i
                out[off + i] = if (j >= 0) be[j] else 0
            }
        }

        fun generate(random: SecureRandom = SecureRandom()): AdbKey {
            val g = KeyPairGenerator.getInstance("RSA")
            g.initialize(2048, random)
            return AdbKey(g.generateKeyPair().private as RSAPrivateCrtKey)
        }

        fun fromPkcs8(der: ByteArray): AdbKey =
            AdbKey(KeyFactory.getInstance("RSA").generatePrivate(PKCS8EncodedKeySpec(der)) as RSAPrivateCrtKey)

        /** PEM ("BEGIN PRIVATE KEY") ya da ham PKCS#8 DER. */
        fun fromPem(text: String): AdbKey {
            val b64 = text.lineSequence().filter { !it.startsWith("-----") }.joinToString("").trim()
            return fromPkcs8(Base64.getMimeDecoder().decode(b64))
        }

        /** Dosyadan okur; yoksa ya da bozuksa üretip yazar. */
        fun loadOrCreate(file: File): AdbKey {
            runCatching { if (file.isFile) return fromPkcs8(file.readBytes()) }
            val k = generate()
            file.parentFile?.mkdirs()
            val tmp = File(file.parentFile, file.name + ".tmp")
            tmp.writeBytes(k.privateKey.encoded)
            if (!tmp.renameTo(file)) { file.delete(); tmp.renameTo(file) }
            return k
        }
    }
}
