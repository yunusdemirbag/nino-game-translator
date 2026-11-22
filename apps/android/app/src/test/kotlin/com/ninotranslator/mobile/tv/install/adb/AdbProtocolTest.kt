// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.tv.install.adb

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.math.BigInteger
import java.security.Signature
import java.util.Base64
import javax.crypto.Cipher

class AdbProtocolTest {
    private fun resource(name: String) = javaClass.getResourceAsStream("/tvinstall/$name")!!.readBytes()
    private val key: AdbKey by lazy { AdbKey.fromPem(String(resource("adbkey.pem"))) }

    @Test fun frameRoundTripAndHeader() {
        val m = AdbMessage(AdbMessage.WRTE, 7, 9, "merhaba".toByteArray())
        val b = m.encode()
        assertEquals(24 + 7, b.size)
        assertEquals("WRTE", String(b, 0, 4, Charsets.US_ASCII))
        assertEquals(7, AdbMessage.getLe(b, 4))
        assertEquals(9, AdbMessage.getLe(b, 8))
        assertEquals(7, AdbMessage.getLe(b, 12))
        assertEquals("merhaba".sumOf { it.code }, AdbMessage.getLe(b, 16))
        assertEquals(AdbMessage.WRTE xor -1, AdbMessage.getLe(b, 20))
        val back = AdbMessage.read(ByteArrayInputStream(b), 1024, verifyChecksum = true)
        assertEquals("WRTE", back.name)
        assertArrayEquals("merhaba".toByteArray(), back.data)
    }

    @Test fun frameChecksAndAdbAcceptsZeroChecksum() {
        val b = AdbMessage(AdbMessage.OKAY, 1, 2, byteArrayOf(1, 2, 3)).encode()
        AdbMessage.putLe(b, 16, 0) // yeni adbd toplamı 0 gönderir
        AdbMessage.read(ByteArrayInputStream(b), 1024, verifyChecksum = false)
        expectIo { AdbMessage.read(ByteArrayInputStream(b), 1024, verifyChecksum = true) }
        val bad = AdbMessage(AdbMessage.OKAY, 1, 2).encode().also { AdbMessage.putLe(it, 20, 0) }
        expectIo { AdbMessage.read(ByteArrayInputStream(bad), 1024, verifyChecksum = false) }
        val big = AdbMessage(AdbMessage.WRTE, 1, 2, ByteArray(2000)).encode()
        expectIo { AdbMessage.read(ByteArrayInputStream(big), 1024, verifyChecksum = false) }
    }

    /** Doğruluk kaynağı: platform-tools'un `adb keygen` çıktısı (aynı özel anahtardan açık anahtar satırı). */
    @Test fun publicKeyMatchesAdbKeygen() {
        val expected = String(resource("adbkey.pub")).trim().substringBefore(' ')
        assertEquals(expected, key.publicKeyLine("nino@phone").substringBefore(' '))
        assertTrue(key.publicKeyLine("nino@phone").endsWith(" nino@phone"))
        assertEquals(524, Base64.getDecoder().decode(expected).size)
    }

    @Test fun adbTokenSignatureIsRawDigestInfo() {
        val token = ByteArray(20) { (it * 7).toByte() }
        val sig = key.signAdbToken(token)
        // Açık anahtarla açılan blok: 00 01 FF… 00 + SHA-1 DigestInfo + jeton (yeniden özetlenmemiş).
        val c = Cipher.getInstance("RSA/ECB/NoPadding")
        c.init(Cipher.DECRYPT_MODE, key.publicKey)
        val block = c.doFinal(sig)
        val tail = block.copyOfRange(block.size - 35, block.size)
        assertArrayEquals(token, tail.copyOfRange(15, 35))
        assertEquals(0x30, tail[0].toInt())
        assertEquals(1, block[0].toInt() + block[1].toInt()) // 00 01
        // sdb: jeton SHA1withRSA ile özetlenir.
        val v = Signature.getInstance("SHA1withRSA")
        v.initVerify(key.publicKey); v.update(token)
        assertTrue(v.verify(key.signSha1WithRsa(token)))
    }

    @Test fun androidPublicKeyStructure() {
        val n = key.privateKey.modulus
        val s = AdbKey.androidPublicKey(n, BigInteger.valueOf(65537))
        assertEquals(64, AdbMessage.getLe(s, 0))
        val n0inv = AdbMessage.getLe(s, 4).toLong() and 0xFFFFFFFFL
        assertEquals(0L, (n.mod(BigInteger.ONE.shiftLeft(32)).toLong() * n0inv + 1) and 0xFFFFFFFFL)
        assertEquals(65537, AdbMessage.getLe(s, 520))
    }

    // --- Sahte adbd ile tam el sıkışma ---

    /** adbd gibi davranan sunucu ucu. */
    private class FakeAdbd(var input: InputStream, var output: OutputStream, val dialect: AdbDialect = AdbDialect.ADB) {
        fun read() = AdbMessage.read(input, 1 shl 20, dialect.verifyChecksum)
        fun send(m: AdbMessage) = AdbMessage.write(output, m)
        val files = HashMap<String, ByteArray>()
        val commands = ArrayList<String>()

        /** Kanal isteklerini karşılar; kapanana kadar. */
        fun serveChannels(shell: (String, ByteArray) -> String) {
            var remoteId = 100
            while (true) {
                val open = try { read() } catch (_: IOException) { return }
                if (open.command != AdbMessage.OPEN) continue
                val service = String(open.data, Charsets.UTF_8).trimEnd('\u0000')
                val local = ++remoteId
                send(AdbMessage(AdbMessage.OKAY, local, open.arg0))
                commands += service
                val input = ByteArrayOutputStream()
                if (service == "sync:") { serveSync(local, open.arg0); continue }
                // Gelen veriyi topla (kurulum), sonra çıktı ver ve kapat.
                val expect = Regex("-S (\\d+)").find(service)?.groupValues?.get(1)?.toInt() ?: 0
                while (input.size() < expect) {
                    val w = read()
                    if (w.command == AdbMessage.WRTE) { input.write(w.data); send(AdbMessage(AdbMessage.OKAY, local, open.arg0)) }
                }
                val out = shell(service, input.toByteArray()).toByteArray()
                if (out.isNotEmpty()) {
                    send(AdbMessage(AdbMessage.WRTE, local, open.arg0, out))
                    while (read().command != AdbMessage.OKAY) Unit // önceki kanalların CLSE'leri atlanır
                }
                send(AdbMessage(AdbMessage.CLSE, local, open.arg0))
            }
        }

        private fun serveSync(local: Int, remote: Int) {
            val buf = ByteArrayOutputStream()
            var consumed = 0
            fun need(n: Int): ByteArray {
                while (buf.size() - consumed < n) {
                    val w = read(); check(w.command == AdbMessage.WRTE) { "sync'te ${w.name}" }
                    buf.write(w.data); send(AdbMessage(AdbMessage.OKAY, local, remote))
                }
                return buf.toByteArray().copyOfRange(consumed, consumed + n).also { consumed += n }
            }
            var path = ""
            val content = ByteArrayOutputStream()
            while (true) {
                val h = need(8)
                val id = String(h, 0, 4, Charsets.US_ASCII); val len = AdbMessage.getLe(h, 4)
                when (id) {
                    "SEND" -> path = String(need(len), Charsets.UTF_8)
                    "DATA" -> content.write(need(len))
                    "DONE" -> {
                        files[path] = content.toByteArray()
                        send(AdbMessage(AdbMessage.WRTE, local, remote, AdbConnection.syncHeader("OKAY", 0)))
                        check(read().command == AdbMessage.OKAY)
                    }
                    "QUIT" -> {
                        send(AdbMessage(AdbMessage.CLSE, local, remote))
                        return
                    }
                }
            }
        }
    }

    private fun verifyAdbSignature(token: ByteArray, sig: ByteArray, k: AdbKey): Boolean {
        val c = Cipher.getInstance("RSA/ECB/NoPadding"); c.init(Cipher.DECRYPT_MODE, k.publicKey)
        val block = c.doFinal(sig)
        return block.copyOfRange(block.size - 20, block.size).contentEquals(token)
    }

    @Test fun handshakeWithKnownKeyThenShellAndPush() {
        val token = ByteArray(20) { 3 }
        val apk = ByteArray(300_000) { (it % 251).toByte() }
        lateinit var adbd: FakeAdbd
        val tv = Loopback { s ->
            adbd = FakeAdbd(s.getInputStream(), s.getOutputStream())
            val cnxn = adbd.read()
            check(cnxn.command == AdbMessage.CNXN && cnxn.arg0 == 0x01000001 && cnxn.arg1 == 256 * 1024)
            check(String(cnxn.data) == "host::\u0000")
            adbd.send(AdbMessage(AdbMessage.AUTH, AdbMessage.AUTH_TOKEN, 0, token))
            val sig = adbd.read()
            check(sig.command == AdbMessage.AUTH && sig.arg0 == AdbMessage.AUTH_SIGNATURE && verifyAdbSignature(token, sig.data, key))
            adbd.send(AdbMessage(AdbMessage.CNXN, 0x01000001, 4096, "device::ro.product.model=Test;\u0000".toByteArray()))
            adbd.serveChannels { service, input ->
                when {
                    service.startsWith("shell:dumpsys") -> "  versionName=4.0.1\n  installerPackageName=null\n"
                    service.startsWith("exec:cmd package install") -> if (input.contentEquals(apk)) "Success\n" else "Failure [boyut]\n"
                    else -> ""
                }
            }
        }
        tv.use {
            AdbConnection(tv.client(), AdbDialect.ADB, key).use { c ->
                c.handshake(tls = null)
                assertEquals(4096, c.maxData)
                assertTrue(c.banner.contains("model=Test"))
                assertTrue(c.shell("dumpsys package com.ninotranslator.tv").contains("versionName=4.0.1"))
                val out = String(c.serviceStreaming("exec:cmd package install -r -S ${apk.size}", ByteArrayInputStream(apk)))
                assertEquals("Success\n", out)
                c.push("/data/local/tmp/nino-tv.apk", 0x81A4, ByteArrayInputStream(apk))
            }
            tv.join()
        }
        tv.failure?.let { if (it !is IOException) throw it }
        assertArrayEquals(apk, adbd.files["/data/local/tmp/nino-tv.apk,33188"])
    }

    @Test fun unknownKeySendsPublicKeyAndWaitsForApproval() {
        var approveShown = false
        val tv = Loopback { s ->
            val d = FakeAdbd(s.getInputStream(), s.getOutputStream())
            d.read()
            d.send(AdbMessage(AdbMessage.AUTH, AdbMessage.AUTH_TOKEN, 0, ByteArray(20)))
            check(d.read().arg0 == AdbMessage.AUTH_SIGNATURE)
            d.send(AdbMessage(AdbMessage.AUTH, AdbMessage.AUTH_TOKEN, 0, ByteArray(20) { 1 }))
            val pub = d.read()
            check(pub.arg0 == AdbMessage.AUTH_RSAPUBLICKEY)
            check(String(pub.data, Charsets.US_ASCII) == key.publicKeyLine("nino@phone") + "\u0000")
            d.send(AdbMessage(AdbMessage.CNXN, 0x01000001, 0, ByteArray(0)))
        }
        tv.use {
            AdbConnection(tv.client(), AdbDialect.ADB, key).use { c ->
                c.handshake(tls = null, onApprove = { approveShown = true })
                assertEquals(4096, c.maxData) // TV 0 bildirdi
            }
        }
        assertTrue(approveShown)
    }

    @Test fun silentCheckGivesUpWhenApprovalNeededAndRepeatTokenIsNotApproved() {
        fun run(wait: Int): AdbFailure {
            val tv = Loopback { s ->
                val d = FakeAdbd(s.getInputStream(), s.getOutputStream())
                d.read()
                repeat(3) {
                    d.send(AdbMessage(AdbMessage.AUTH, AdbMessage.AUTH_TOKEN, 0, ByteArray(20)))
                    runCatching { d.read() }
                }
            }
            tv.use {
                AdbConnection(tv.client(), AdbDialect.ADB, key).use { c ->
                    try { c.handshake(tls = null, approvalWaitMs = wait); fail("bağlanmamalıydı") } catch (e: AdbException) { return e.failure }
                }
            }
            error("ulaşılmaz")
        }
        assertEquals(AdbFailure.NEEDS_APPROVAL, run(0))
        assertEquals(AdbFailure.NOT_APPROVED, run(5_000))
    }

    @Test fun stlsUpgradesToTls13WithClientCertificate() {
        val tvKey = AdbKey.generate()
        var seenCert: ByteArray? = null
        val tv = Loopback { s ->
            val raw = FakeAdbd(s.getInputStream(), s.getOutputStream())
            raw.read()
            raw.send(AdbMessage(AdbMessage.STLS, 0x01000000, 0))
            check(raw.read().command == AdbMessage.STLS)
            val (p, server) = TestTlsServer.accept(s.getInputStream(), s.getOutputStream(), tvKey)
            seenCert = server.clientCert
            val d = FakeAdbd(p.inputStream, p.outputStream)
            d.send(AdbMessage(AdbMessage.CNXN, 0x01000001, 256 * 1024, "device::\u0000".toByteArray()))
            d.serveChannels { _, _ -> "ok" }
        }
        tv.use {
            AdbConnection(tv.client(), AdbDialect.ADB, key).use { c ->
                c.handshake(tls = AdbTls.upgrade(key))
                assertTrue(c.tlsUsed)
                assertEquals("ok", c.shell("echo"))
            }
        }
        val cert = java.security.cert.CertificateFactory.getInstance("X.509")
            .generateCertificate(ByteArrayInputStream(seenCert!!)) as java.security.cert.X509Certificate
        assertEquals("CN=Nino", cert.subjectX500Principal.name)
        assertEquals(key.publicKey, cert.publicKey)
        cert.verify(key.publicKey)
        assertEquals("SHA256withRSA", cert.sigAlgName)
    }

    @Test fun rejectedTlsMeansNotPaired() {
        val tv = Loopback { s ->
            val raw = FakeAdbd(s.getInputStream(), s.getOutputStream())
            raw.read()
            raw.send(AdbMessage(AdbMessage.STLS, 0x01000000, 0))
            raw.read()
            runCatching { TestTlsServer.accept(s.getInputStream(), s.getOutputStream(), AdbKey.generate(), rejectClient = true) }
        }
        tv.use {
            AdbConnection(tv.client(), AdbDialect.ADB, key).use { c ->
                try { c.handshake(tls = AdbTls.upgrade(key)); fail() } catch (e: AdbException) { assertEquals(AdbFailure.NOT_PAIRED, e.failure) }
            }
        }
    }

    @Test fun sdbDialectHandshakeAndPushWithoutMode() {
        val token = ByteArray(20) { 9 }
        lateinit var d: FakeAdbd
        val tv = Loopback { s ->
            d = FakeAdbd(s.getInputStream(), s.getOutputStream(), AdbDialect.SDB)
            val cnxn = d.read()
            check(cnxn.arg0 == 0x01000000 && cnxn.arg1 == 4096 && String(cnxn.data) == "host::sdb-net-client")
            d.send(AdbMessage(AdbMessage.AUTH, AdbMessage.AUTH_TOKEN, 0, token))
            val sig = d.read()
            val v = Signature.getInstance("SHA1withRSA"); v.initVerify(key.publicKey); v.update(token)
            check(v.verify(sig.data))
            d.send(AdbMessage(AdbMessage.CNXN, 0x01000000, 1 shl 20, "device::\u0000".toByteArray()))
            // TV kendiliğinden kanal açar: istemci CLSE dönmeli.
            d.send(AdbMessage(AdbMessage.OPEN, 55, 0, "x\u0000".toByteArray()))
            d.serveChannels { service, _ -> if (service.contains("getduid")) "ABCDEFGH1234\n" else "" }
        }
        tv.use {
            try {
                AdbConnection(tv.client(), AdbDialect.SDB, key).use { c ->
                    c.handshake(tls = null)
                    assertEquals(4096, c.maxData)
                    assertEquals("ABCDEFGH1234\n", c.shell("0 getduid"))
                    c.push("/opt/usr/apps/tmp/nino.wgt", null, ByteArrayInputStream(ByteArray(10_000) { 5 }))
                }
            } catch (e: IOException) { tv.join(); throw AssertionError("istemci: $e; sahte TV: ${tv.failure}", tv.failure ?: e) }
            tv.join()
        }
        assertEquals(10_000, d.files["/opt/usr/apps/tmp/nino.wgt"]?.size)
    }

    private fun expectIo(block: () -> Unit) {
        try { block(); fail("IOException bekleniyordu") } catch (_: IOException) {}
    }
}
