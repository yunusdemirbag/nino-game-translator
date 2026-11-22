// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.tv.install.lg

import com.jcraft.jsch.JSch
import com.jcraft.jsch.KeyPair
import com.ninotranslator.mobile.tv.install.TvInstallEnv
import com.ninotranslator.mobile.tv.install.TvInstallError
import com.ninotranslator.mobile.tv.install.TvInstallException
import com.ninotranslator.mobile.tv.install.TvPackageIndex
import com.ninotranslator.mobile.tv.install.TvPackageSource
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.ByteArrayOutputStream
import java.nio.file.Files
import java.util.Base64

/** Şifreli anahtarlar `openssl rsa -traditional -des3/-aes128/-aes256 -passout pass:AB12CD` ile üretildi. */
class LgTest {
    private fun res(n: String) = javaClass.getResourceAsStream("/tvinstall/$n")!!.readBytes()
    private val plainDer by lazy { res("lg-plain.der") }

    private fun derOf(pem: ByteArray): ByteArray {
        val t = String(pem, Charsets.US_ASCII)
        return Base64.getMimeDecoder().decode(t.lines().filter { !it.startsWith("-----") && ':' !in it }.joinToString(""))
    }

    @Test fun decryptsLegacyPemWithAllCiphers() {
        for (name in listOf("lg-des3.pem", "lg-aes128.pem", "lg-aes256.pem")) {
            val r = LgKey.decrypt(String(res(name)), "AB12CD")
            assertTrue(name, r is LgKey.Result.Decrypted)
            val pem = (r as LgKey.Result.Decrypted).pem
            assertTrue(String(pem).startsWith("-----BEGIN RSA PRIVATE KEY-----"))
            assertArrayEquals(name, plainDer, derOf(pem))
        }
    }

    @Test fun lowercasePassphraseIsRetriedUppercase() {
        assertTrue(LgKey.decrypt(String(res("lg-des3.pem")), "ab12cd") is LgKey.Result.Decrypted)
        assertEquals(listOf("ab12cd", "AB12CD"), LgKey.candidates(" ab12cd "))
    }

    @Test fun wrongPassphraseAndNonKeys() {
        assertEquals(LgKey.Result.WrongPassphrase, LgKey.decrypt(String(res("lg-aes256.pem")), "XXXXXX"))
        assertEquals(LgKey.Result.NotAKey, LgKey.decrypt("<html>Key Server kapalı</html>", "AB12CD"))
        assertTrue(LgKey.decrypt(String(res("lg-plain.pem")), "") is LgKey.Result.Decrypted)
        assertEquals(LgKey.Result.OtherFormat, LgKey.decrypt("-----BEGIN OPENSSH PRIVATE KEY-----\nAAAA\n-----END OPENSSH PRIVATE KEY-----", "x"))
    }

    @Test fun evpBytesToKeyMatchesOpenSsl() {
        // `openssl enc -des-ede3-cbc -P -S 0102030405060708 -pass pass:AB12CD -md md5` çıktısındaki anahtar.
        val k = LgKey.bytesToKey("AB12CD".toByteArray(), byteArrayOf(1, 2, 3, 4, 5, 6, 7, 8), 24)
        assertEquals(EVP_KEY, k.joinToString("") { "%02X".format(it) })
    }

    @Test fun asn1SequenceCheck() {
        assertTrue(LgKey.isAsn1Sequence(plainDer))
        assertFalse(LgKey.isAsn1Sequence(plainDer.copyOf(plainDer.size - 1)))
        assertFalse(LgKey.isAsn1Sequence(byteArrayOf(0x31, 0)))
        assertTrue(LgKey.isAsn1Sequence(byteArrayOf(0x30, 0)))
    }

    @Test fun decryptedKeyLoadsInSsh() {
        val pem = (LgKey.decrypt(String(res("lg-aes128.pem")), "AB12CD") as LgKey.Result.Decrypted).pem
        val kp = KeyPair.load(JSch(), pem, null)
        assertFalse(kp.isEncrypted)
        assertEquals(KeyPair.RSA, kp.keyType)
        JSch().addIdentity("t", pem, null, null)
    }

    @Test fun installerDecodesOpenSshEncryptedKeyViaSsh() {
        // SSH kütüphanesinin kendi şifreli biçimi (eski PEM değil) de çözülür.
        val kp = KeyPair.genKeyPair(JSch(), KeyPair.RSA, 1024)
        val out = ByteArrayOutputStream(); kp.writePrivateKey(out, "QWERTY".toByteArray())
        val env = TvInstallEnv(Files.createTempDirectory("lg").toFile(), Files.createTempDirectory("c").toFile(),
            object : TvPackageSource { override val index = TvPackageIndex.parse(""); override fun open(path: String) = null }, {})
        val lg = LgInstaller(env)
        val text = String(out.toByteArray())
        val dec = lg.decodeKey(text, "qwerty")
        assertFalse(KeyPair.load(JSch(), dec, null).isEncrypted)
        try { lg.decodeKey(text, "NOPE00"); error("hata bekleniyordu") } catch (e: TvInstallException) { assertEquals(TvInstallError.LG_PASSPHRASE, e.error) }
        try { lg.decodeKey("Not found", "X"); error("hata bekleniyordu") } catch (e: TvInstallException) { assertEquals(TvInstallError.LG_KEY_SERVER, e.error) }
        assertFalse(lg.hasKey("192.168.0.7"))
        assertTrue(lg.keyFile("192.168.0.7").path.endsWith("lg/192.168.0.7.key"))
    }

    @Test fun appInfoAndInstallResponses() {
        assertEquals("4.0.3", LgProtocol.versionFromAppInfo("{\n \"id\": \"com.ninotranslator.tv\",\n \"version\": \"4.0.3\"\n}"))
        assertNull(LgProtocol.versionFromAppInfo("cat: can't open '/media/…/appinfo.json': No such file or directory"))

        val ok = """
            {"subscribed":true,"returnValue":true}
            {"id":"com.ares.defaultName","details":{"packageId":"com.ninotranslator.tv","state":"installing","progress":40},"returnValue":true}
            {"id":"com.ares.defaultName","details":{"packageId":"com.ninotranslator.tv",
             "state":"installed"},"returnValue":true}
        """.trimIndent()
        assertEquals(LgProtocol.InstallOutcome.Success, LgProtocol.parseInstall(ok))
        val bad = """{"returnValue":false,"errorCode":-5,"errorText":"FAILED_IPK_PARSE"}"""
        assertEquals(LgProtocol.InstallOutcome.Failure("FAILED_IPK_PARSE (-5)"), LgProtocol.parseInstall(bad))
        val failed = """{"details":{"state":"install failed","reason":"no space left on device","errorCode":-13},"returnValue":true}"""
        val f = LgProtocol.parseInstall(failed) as LgProtocol.InstallOutcome.Failure
        assertTrue(f.reason.contains("no space")); assertTrue(LgProtocol.isNoSpace(f.reason))
        assertEquals(LgProtocol.InstallOutcome.Unknown, LgProtocol.parseInstall("luna-send: timeout"))
        assertEquals(LgProtocol.InstallOutcome.Success, LgProtocol.parseInstall("""{"details":{"state":"SUCCESS_INSTALL"}}"""))
    }

    @Test fun commandsAndSession() {
        val s = LgProtocol.installScript("/media/developer/temp/com.ninotranslator.tv_4.0.3_all.ipk", "ab")
        assertTrue(s.contains("luna-send-pub -i 'luna://com.webos.appInstallService/dev/install'"))
        assertTrue(s.contains("\"id\":\"com.ares.defaultName\",\"ipkUrl\":\"/media/developer/temp/com.ninotranslator.tv_4.0.3_all.ipk\",\"subscribe\":true"))
        assertTrue(s.contains("-lt 180"))
        assertEquals("cat /media/developer/apps/usr/palm/applications/com.ninotranslator.tv/appinfo.json", LgProtocol.appInfoCommand())
        assertEquals("'a'\\''b'", LgProtocol.quote("a'b"))
        assertEquals("ABCDEF123", LgProtocol.sessionToken(" ABCDEF123\n"))
        assertNull(LgProtocol.sessionToken("a b"))
        assertNull(LgProtocol.sessionToken("  "))
        assertEquals("998:12:04", LgProtocol.remaining("""{"result":"success","errorMsg":"998:12:04"}"""))
        assertEquals("https://developer.lge.com/secure/ResetDevModeSession.dev?sessionToken=T", LgProtocol.resetSessionUrl("T"))
        assertEquals("rsa-sha2-512,ssh-rsa,diffie", LgInstaller.append("rsa-sha2-512,ssh-rsa", "ssh-rsa,diffie"))
    }

    companion object {
        const val EVP_KEY = "620B70FC3E362528D8F7B41EDC4CDA8E9F91DBAA0B2F2EC0"
    }
}
