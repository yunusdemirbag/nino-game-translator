// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.tv.install.adb

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assume
import org.junit.Test
import java.io.File
import java.io.InputStream
import java.io.OutputStream
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.concurrent.TimeUnit

class Spake2PairingTest {
    private fun hex(b: ByteArray) = b.joinToString("") { "%02x".format(it) }
    private fun unhex(s: String) = ByteArray(s.length / 2) { s.substring(2 * it, 2 * it + 2).toInt(16).toByte() }

    /** Sabit rastgelelik: test vektörleri tekrarlanabilir olsun. */
    private class FixedRandom(private val bytes: ByteArray) : SecureRandom() {
        override fun nextBytes(out: ByteArray) { for (i in out.indices) out[i] = bytes[i % bytes.size] }
    }

    /** BoringSSL spake25519.c'deki M ve N noktalarının sıkıştırılmış biçimi. */
    @Test fun constantsMatchBoringSsl() {
        assertEquals("5ada7e4bf6ddd9adb6626d32131c6b5c51a1e347a3478f53cfcf441b88eed12e", hex(Ed25519.encode(Spake2.M)))
        assertEquals("10e3df0ae37d8e7a99b5fe74b44672103dbddcbd06af680d71329a11693bc778", hex(Ed25519.encode(Spake2.N)))
        // Taban noktasının bilinen kodlaması (RFC 8032).
        assertEquals("5866666666666666666666666666666666666666666666666666666666666666", hex(Ed25519.encode(Ed25519.BASE)))
        // l·B = birim.
        assertEquals(hex(Ed25519.encode(Ed25519.IDENTITY)), hex(Ed25519.encode(Ed25519.multiply(Ed25519.L, Ed25519.BASE))))
    }

    @Test fun passwordScalarHackClearsLowBitsAndKeepsResidue() {
        repeat(50) { i ->
            val h = MessageDigest.getInstance("SHA-512").digest(byteArrayOf(i.toByte()))
            val s = Spake2.passwordScalar(h)
            assertEquals(0, s.toInt() and 7)
            assertEquals(Ed25519.fromLe(h).mod(Ed25519.L), s.mod(Ed25519.L))
            assertTrue(s < Ed25519.L.shiftLeft(3))
        }
    }

    @Test fun aliceAndBobAgreeOnlyWithSamePassword() {
        val pw = "123456".toByteArray()
        val a = Spake2(true, AdbPairing.CLIENT_NAME, AdbPairing.SERVER_NAME, FixedRandom(byteArrayOf(1, 2, 3)))
        val b = Spake2(false, AdbPairing.SERVER_NAME, AdbPairing.CLIENT_NAME, FixedRandom(byteArrayOf(9, 8, 7)))
        val ma = a.generateMessage(pw); val mb = b.generateMessage(pw)
        val ka = a.processMessage(mb)!!; val kb = b.processMessage(ma)!!
        assertArrayEquals(ka, kb)
        assertEquals(64, ka.size)
        val c = Spake2(false, AdbPairing.SERVER_NAME, AdbPairing.CLIENT_NAME, FixedRandom(byteArrayOf(9, 8, 7)))
        val mc = c.generateMessage("654321".toByteArray())
        val a2 = Spake2(true, AdbPairing.CLIENT_NAME, AdbPairing.SERVER_NAME, FixedRandom(byteArrayOf(1, 2, 3)))
        a2.generateMessage(pw)
        assertFalse(a2.processMessage(mc)!!.contentEquals(c.processMessage(ma)!!))
        // Eğride olmayan mesaj reddedilir.
        assertNull(a.processMessage(unhex("02" + "00".repeat(31))))
    }

    /**
     * Sabit vektör (bu uygulamanın kendi çıktısı; yukarıdaki BoringSSL sabitleri ve gerçek `adb pair` denemesiyle
     * doğrulandı). Herhangi bir adımın baytı değişirse bu test kırılır.
     */
    @Test fun fixedVector() {
        val pw = "123456".toByteArray() + ByteArray(64) { it.toByte() }
        val a = Spake2(true, AdbPairing.CLIENT_NAME, AdbPairing.SERVER_NAME, FixedRandom(byteArrayOf(0x11, 0x22)))
        val b = Spake2(false, AdbPairing.SERVER_NAME, AdbPairing.CLIENT_NAME, FixedRandom(byteArrayOf(0x33)))
        val ma = a.generateMessage(pw); val mb = b.generateMessage(pw)
        val k = a.processMessage(mb)!!
        val key = AdbPairing.cipherKey(k)
        assertEquals(VECTOR_MA, hex(ma))
        assertEquals(VECTOR_MB, hex(mb))
        assertEquals(VECTOR_KEY, hex(k))
        assertEquals(VECTOR_AES, hex(key))
    }

    @Test fun aeadNonceIsLittleEndianSequence() {
        val key = ByteArray(16) { 1 }
        val enc = AdbPairing.Aead(key); val dec = AdbPairing.Aead(key)
        val c1 = enc.encrypt("bir".toByteArray()); val c2 = enc.encrypt("bir".toByteArray())
        assertFalse(c1.contentEquals(c2))
        assertEquals(3 + 16, c1.size)
        assertArrayEquals("bir".toByteArray(), dec.decrypt(c1))
        assertArrayEquals("bir".toByteArray(), dec.decrypt(c2))
        assertNull(AdbPairing.Aead(ByteArray(16)).decrypt(c1))
        // Nonce 0 ile JCA'nın AES/GCM'i aynı çıktıyı verir.
        val jca = javax.crypto.Cipher.getInstance("AES/GCM/NoPadding")
        jca.init(javax.crypto.Cipher.ENCRYPT_MODE, javax.crypto.spec.SecretKeySpec(key, "AES"), javax.crypto.spec.GCMParameterSpec(128, ByteArray(12)))
        assertArrayEquals(jca.doFinal("bir".toByteArray()), c1)
    }

    @Test fun peerInfoLayout() {
        val p = AdbPairing.peerInfo("QUFB nino@phone")
        assertEquals(8192, p.size)
        assertEquals(0, p[0].toInt())
        assertEquals("QUFB nino@phone", String(p, 1, 15, Charsets.US_ASCII))
        assertEquals(0, p[16].toInt())
    }

    /** TV'nin eşleme sunucusu (bob): bu test ve gerçek `adb pair` denemesi için. */
    private fun servePairing(input: InputStream, output: OutputStream, code: String, exported: ByteArray): ByteArray? {
        val spake = Spake2(false, AdbPairing.SERVER_NAME, AdbPairing.CLIENT_NAME)
        val theirs = AdbPairing.readPacket(input, AdbPairing.TYPE_SPAKE2)
        AdbPairing.writePacket(output, AdbPairing.TYPE_SPAKE2, spake.generateMessage(code.toByteArray() + exported))
        val key = spake.processMessage(theirs) ?: return null
        val aead = AdbPairing.Aead(AdbPairing.cipherKey(key))
        val info = AdbPairing.readPacket(input, AdbPairing.TYPE_PEER_INFO)
        val plain = aead.decrypt(info) ?: return null
        val mine = ByteArray(8192).also { it[0] = 1; "guid-tv".toByteArray().copyInto(it, 1) }
        AdbPairing.writePacket(output, AdbPairing.TYPE_PEER_INFO, aead.encrypt(mine))
        return plain
    }

    private fun pairOverLoopback(phoneCode: String, tvCode: String): Pair<Throwable?, ByteArray?> {
        val phone = AdbKey.generate()
        var received: ByteArray? = null
        val tv = Loopback { s ->
            val (p, server) = TestTlsServer.accept(s.getInputStream(), s.getOutputStream(), AdbKey.generate())
            received = servePairing(p.inputStream, p.outputStream, tvCode, server.export(AdbPairing.EXPORT_LABEL, 64))
            if (received == null) s.close()
        }
        val err = tv.use { runCatching { AdbPairing.pair("127.0.0.1", tv.port, phoneCode, phone) }.exceptionOrNull() }
        tv.join()
        return err to received
    }

    @Test fun pairingOverTlsWithRightCode() {
        val (err, info) = pairOverLoopback("482913", "482913")
        assertNull(err)
        assertNotNull(info)
        assertEquals(0, info!![0].toInt())
        assertTrue(String(info, 1, 900, Charsets.US_ASCII).contains(" nino@phone"))
    }

    @Test fun pairingWithWrongCodeFails() {
        val (err, _) = pairOverLoopback("482913", "111111")
        assertTrue(err is AdbPairing.PairingException)
    }

    /**
     * Gerçek eş: platform-tools'un `adb pair` istemcisi bu testin bob sunucusuyla eşleşir. Yalnız `-Dnino.realAdb=<adb
     * yolu>` verilince çalışır; adb ayrı bir sunucu portu ve geçici HOME ile açılır, kullanıcının adb'sine dokunmaz.
     */
    @Test fun realAdbPairClientAcceptsOurServer() {
        val adb = System.getProperty("nino.realAdb")?.takeIf { File(it).canExecute() }
        Assume.assumeTrue("gerçek adb verilmedi", adb != null)
        val home = File(System.getProperty("java.io.tmpdir"), "nino-adb-home-" + System.nanoTime()).apply { mkdirs() }
        val serverPort = 15037 + (System.nanoTime() % 500).toInt()
        val code = "246810"
        var received: ByteArray? = null
        val tv = Loopback { s ->
            val (p, server) = TestTlsServer.accept(s.getInputStream(), s.getOutputStream(), AdbKey.generate())
            received = servePairing(p.inputStream, p.outputStream, code, server.export(AdbPairing.EXPORT_LABEL, 64))
            Thread.sleep(500)
        }
        try {
            val pb = ProcessBuilder(adb, "-P", serverPort.toString(), "pair", "127.0.0.1:${tv.port}", code).redirectErrorStream(true)
            pb.environment()["HOME"] = home.absolutePath
            pb.environment()["ANDROID_ADB_SERVER_PORT"] = serverPort.toString()
            val proc = pb.start()
            val out = proc.inputStream.bufferedReader().readText()
            proc.waitFor(30, TimeUnit.SECONDS)
            tv.join()
            println("adb pair: $out")
            assertNotNull("adb eş bilgisi gelmedi: $out ${tv.failure}", received)
            assertEquals(0, received!![0].toInt())
            assertTrue(out, out.contains("Successfully paired"))
        } finally {
            tv.close()
            runCatching {
                val k = ProcessBuilder(adb, "-P", serverPort.toString(), "kill-server")
                k.environment()["HOME"] = home.absolutePath
                k.start().waitFor(10, TimeUnit.SECONDS)
            }
            home.deleteRecursively()
        }
    }

    companion object {
        const val VECTOR_MA = "313761abdbe0b0bce02f3f0f2380a49fa678dc5b061348ddd88d2387103cdb79"
        const val VECTOR_MB = "5716719a3cb190d0256d3dc494f54724840ab561638367264f067abfd6c983e6"
        const val VECTOR_KEY = "67d5f5ea262aa8d4dddfb4aa4425ea37858cffb3de239efe9e8b4d38b76d0d0ac01b8c18f3278e87bf723331fbfc998ee6fce4cb3a3b96bb6ba18e0101abdbea"
        const val VECTOR_AES = "b9618eb9f65b6b7235bb572862eed79c"
    }
}
