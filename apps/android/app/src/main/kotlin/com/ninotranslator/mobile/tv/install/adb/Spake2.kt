// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.tv.install.adb

import java.math.BigInteger
import java.security.MessageDigest
import java.security.SecureRandom

/**
 * edwards25519 noktaları (genişletilmiş koordinatlar, BigInteger). Yalnız eşlemede birkaç çarpım için; hız ve sabit
 * zaman hedeflenmez.
 */
internal object Ed25519 {
    val P: BigInteger = BigInteger.ONE.shiftLeft(255).subtract(BigInteger.valueOf(19))
    val L: BigInteger = BigInteger.ONE.shiftLeft(252).add(BigInteger("27742317777372353535851937790883648493"))
    private val D: BigInteger = BigInteger.valueOf(-121665).multiply(BigInteger.valueOf(121666).modInverse(P)).mod(P)
    private val D2: BigInteger = D.shiftLeft(1).mod(P)
    private val SQRT_M1: BigInteger = BigInteger.valueOf(2).modPow(P.subtract(BigInteger.ONE).shiftRight(2), P)

    class Point(val x: BigInteger, val y: BigInteger, val z: BigInteger, val t: BigInteger)

    val IDENTITY = Point(BigInteger.ZERO, BigInteger.ONE, BigInteger.ONE, BigInteger.ZERO)
    val BASE: Point = run {
        val y = BigInteger.valueOf(4).multiply(BigInteger.valueOf(5).modInverse(P)).mod(P)
        val x = recoverX(y, 0) ?: error("taban noktası")
        Point(x, y, BigInteger.ONE, x.multiply(y).mod(P))
    }

    private fun recoverX(y: BigInteger, sign: Int): BigInteger? {
        val yy = y.multiply(y).mod(P)
        val u = yy.subtract(BigInteger.ONE).mod(P)
        val v = D.multiply(yy).add(BigInteger.ONE).mod(P)
        val xx = u.multiply(v.modInverse(P)).mod(P)
        var x = xx.modPow(P.add(BigInteger.valueOf(3)).shiftRight(3), P)
        if (x.multiply(x).subtract(xx).mod(P).signum() != 0) x = x.multiply(SQRT_M1).mod(P)
        if (x.multiply(x).subtract(xx).mod(P).signum() != 0) return null
        if (x.testBit(0) != (sign == 1)) x = P.subtract(x).mod(P)
        return x
    }

    fun add(a: Point, b: Point): Point {
        val aa = a.y.subtract(a.x).multiply(b.y.subtract(b.x)).mod(P)
        val bb = a.y.add(a.x).multiply(b.y.add(b.x)).mod(P)
        val cc = a.t.multiply(D2).multiply(b.t).mod(P)
        val dd = a.z.shiftLeft(1).multiply(b.z).mod(P)
        val e = bb.subtract(aa); val f = dd.subtract(cc); val g = dd.add(cc); val h = bb.add(aa)
        return Point(e.multiply(f).mod(P), g.multiply(h).mod(P), f.multiply(g).mod(P), e.multiply(h).mod(P))
    }

    fun negate(a: Point) = Point(P.subtract(a.x).mod(P), a.y, a.z, P.subtract(a.t).mod(P))

    fun multiply(k: BigInteger, a: Point): Point {
        var r = IDENTITY
        for (i in k.bitLength() - 1 downTo 0) {
            r = add(r, r)
            if (k.testBit(i)) r = add(r, a)
        }
        return r
    }

    fun encode(a: Point): ByteArray {
        val zi = a.z.modInverse(P)
        val x = a.x.multiply(zi).mod(P)
        val y = a.y.multiply(zi).mod(P)
        val out = toLe(y, 32)
        if (x.testBit(0)) out[31] = (out[31].toInt() or 0x80).toByte()
        return out
    }

    /** Sıkıştırılmış noktayı açar; eğride değilse null. */
    fun decode(b: ByteArray): Point? {
        if (b.size != 32) return null
        val c = b.copyOf()
        val sign = (c[31].toInt() ushr 7) and 1
        c[31] = (c[31].toInt() and 0x7F).toByte()
        val y = fromLe(c)
        if (y >= P) return null
        val x = recoverX(y, sign) ?: return null
        return Point(x, y, BigInteger.ONE, x.multiply(y).mod(P))
    }

    fun fromLe(b: ByteArray): BigInteger = BigInteger(1, b.reversedArray())

    fun toLe(v: BigInteger, n: Int): ByteArray {
        val be = v.toByteArray()
        return ByteArray(n) { i -> val j = be.size - 1 - i; if (j >= 0) be[j] else 0 }
    }

    /**
     * Sabit noktaların üretimi: tohumun SHA-256'sı nokta olarak açılana kadar yeniden özetlenir (BoringSSL'in M ve N
     * noktalarının tarifi).
     */
    fun pointFromSeed(seed: String): Point {
        val sha = MessageDigest.getInstance("SHA-256")
        var v = sha.digest(seed.toByteArray(Charsets.US_ASCII))
        while (true) {
            decode(v)?.let { return it }
            v = sha.digest(v)
        }
    }
}

/**
 * SPAKE2, BoringSSL'in edwards25519 SPAKE2'siyle bayt bayt aynı (adb eşlemesi, AOSP `pairing_auth`).
 * Telefon "alice"tir.
 */
class Spake2(
    private val alice: Boolean,
    private val myName: ByteArray,
    private val theirName: ByteArray,
    private val random: SecureRandom = SecureRandom(),
) {
    private lateinit var privateScalar: BigInteger
    private lateinit var passwordScalar: BigInteger
    private lateinit var passwordHash: ByteArray
    private lateinit var myMessage: ByteArray

    /** 32 baytlık SPAKE2 mesajı. */
    fun generateMessage(password: ByteArray): ByteArray {
        val r = ByteArray(64).also { random.nextBytes(it) }
        // Özel skaler: 64 rastgele bayt l'ye indirgenir ve 8 ile çarpılır (eş noktasının kofaktörü temizlensin).
        privateScalar = Ed25519.fromLe(r).mod(Ed25519.L).shiftLeft(3)
        passwordHash = MessageDigest.getInstance("SHA-512").digest(password)
        passwordScalar = passwordScalar(passwordHash)
        val p = Ed25519.multiply(privateScalar, Ed25519.BASE)
        val mask = Ed25519.multiply(passwordScalar, if (alice) M else N)
        myMessage = Ed25519.encode(Ed25519.add(p, mask))
        return myMessage.copyOf()
    }

    /** Eşin mesajından 64 baytlık anahtar; mesaj eğride değilse null. */
    fun processMessage(their: ByteArray): ByteArray? {
        val q = Ed25519.decode(their) ?: return null
        val peerMask = Ed25519.multiply(passwordScalar, if (alice) N else M)
        val k = Ed25519.multiply(privateScalar, Ed25519.add(q, Ed25519.negate(peerMask)))
        val dh = Ed25519.encode(k)
        val sha = MessageDigest.getInstance("SHA-512")
        fun put(b: ByteArray) {
            val len = ByteArray(8); var n = b.size.toLong()
            for (i in 0 until 8) { len[i] = n.toByte(); n = n ushr 8 }
            sha.update(len); sha.update(b)
        }
        if (alice) { put(myName); put(theirName); put(myMessage); put(their) }
        else { put(theirName); put(myName); put(their); put(myMessage) }
        put(dh)
        put(passwordHash)
        return sha.digest()
    }

    companion object {
        internal val M: Ed25519.Point by lazy { Ed25519.pointFromSeed("edwards25519 point generation seed (M)") }
        internal val N: Ed25519.Point by lazy { Ed25519.pointFromSeed("edwards25519 point generation seed (N)") }

        /**
         * Şifre skaleri: SHA-512 özeti l'ye indirgenir; BoringSSL'in "password scalar hack"i ile alt üç bit sıfır
         * olacak biçimde sırayla l, 2l, 4l eklenir.
         */
        internal fun passwordScalar(hash: ByteArray): BigInteger {
            var s = Ed25519.fromLe(hash).mod(Ed25519.L)
            var order = Ed25519.L
            for (bit in 0..2) {
                if (s.testBit(bit)) s = s.add(order)
                order = order.shiftLeft(1)
            }
            return s
        }
    }
}
