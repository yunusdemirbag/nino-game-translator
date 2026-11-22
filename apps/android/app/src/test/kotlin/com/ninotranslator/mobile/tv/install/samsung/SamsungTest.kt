// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.tv.install.samsung

import com.ninotranslator.mobile.tv.install.adb.AdbKey
import com.ninotranslator.mobile.tv.install.adb.AdbTls
import org.bouncycastle.asn1.pkcs.PKCSObjectIdentifiers
import org.bouncycastle.asn1.x500.X500Name
import org.bouncycastle.asn1.x509.Extension
import org.bouncycastle.asn1.x509.GeneralName
import org.bouncycastle.asn1.x509.GeneralNames
import org.bouncycastle.asn1.x509.SubjectPublicKeyInfo
import org.bouncycastle.cert.X509CertificateHolder
import org.bouncycastle.cert.X509v3CertificateBuilder
import org.bouncycastle.crypto.digests.SHA512Digest
import org.bouncycastle.crypto.params.RSAKeyParameters
import org.bouncycastle.crypto.signers.RSADigestSigner
import org.bouncycastle.operator.DefaultDigestAlgorithmIdentifierFinder
import org.bouncycastle.operator.DefaultSignatureAlgorithmIdentifierFinder
import org.bouncycastle.operator.bc.BcRSAContentSignerBuilder
import org.bouncycastle.operator.bc.BcRSAContentVerifierProviderBuilder
import org.bouncycastle.pkcs.PKCS10CertificationRequest
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assume
import org.junit.Test
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.math.BigInteger
import java.security.MessageDigest
import java.util.Base64
import java.util.Date
import java.util.zip.ZipEntry
import java.util.zip.ZipInputStream
import java.util.zip.ZipOutputStream

class SamsungTest {
    // --- sdb yanıtları ---

    @Test fun capabilityAppListDuid() {
        val body = "secure_protocol:disabled\nplatform_version:5.5\nsdk_toolpath:/home/owner/share/tmp/sdk_tools\n"
        val raw = byteArrayOf(0, body.length.toByte()) + body.toByteArray()
        val caps = SamsungProtocol.parseCapability(raw)
        assertEquals("5.5", caps["platform_version"]); assertEquals("/home/owner/share/tmp/sdk_tools", caps["sdk_toolpath"])
        assertEquals(5.5, SamsungProtocol.platformVersion("5.5")!!, 0.0)
        assertEquals(2.4, SamsungProtocol.platformVersion("2.4.0")!!, 0.0)
        val list = """
            ------------------------------------
            ---- app_title = YouTube ----
            ---- app_tizen_id = 111299001912 ----
            ---- app_version = 1.0 ----
            ------------------------------------
            ---- app_title = Nino ----
            ---- app_tizen_id = NinoTVApps.Nino ----
            ---- app_version = 4.0.1 ----
            ------------------------------------
        """.trimIndent()
        assertEquals("4.0.1", SamsungProtocol.installedVersion(list))
        assertNull(SamsungProtocol.installedVersion(list.replace("NinoTVApps.Nino", "Baska.App")))
        assertEquals("4.0.1", SamsungProtocol.installedVersion(list.replace("app_tizen_id = NinoTVApps.Nino", "app_id = NinoTVApps")))
        assertEquals("ABCD-1234+xy=/", SamsungProtocol.parseDuid("\nABCD-1234+xy=/\nfazla"))
        assertNull(SamsungProtocol.parseDuid("short"))
        assertNull(SamsungProtocol.parseDuid("error: closed bad"))
    }

    @Test fun installOutputClassification() {
        fun c(s: String) = SamsungProtocol.classify(s)
        assertEquals(SamsungProtocol.InstallClass.OK, c("spend time for wascmd is [1200]ms\ninstalled[100] package... failed to remove tmp"))
        assertEquals(SamsungProtocol.InstallClass.CONNECTION, c("error: transport connection closed"))
        assertEquals(SamsungProtocol.InstallClass.INCOMPATIBLE, c("install failed[118, -4], reason: wrong config"))
        assertEquals(SamsungProtocol.InstallClass.SPACE, c("download failed[116] not enough space"))
        assertEquals(SamsungProtocol.InstallClass.CLOCK, c("install failed[118, -12] Check certificate error : cert not valid yet"))
        assertEquals(SamsungProtocol.InstallClass.CERT_REJECTED, c("install failed[118012] Check certificate error : invalid"))
        assertEquals(SamsungProtocol.InstallClass.OTHER_CERT_COPY, c("install failed[118, -12] Check certificate error : same id and different certificate"))
        assertEquals(SamsungProtocol.InstallClass.OTHER_CERT_COPY, c("install failed[118, -11] Author certificate not match"))
        assertEquals(SamsungProtocol.InstallClass.BLOCKED, c("install failed[118, -22]"))
        assertEquals(SamsungProtocol.InstallClass.OTHER, c("val[fail] something odd"))
        assertTrue(SamsungProtocol.retryAfterUninstall(SamsungProtocol.InstallClass.OTHER))
        assertFalse(SamsungProtocol.retryAfterUninstall(SamsungProtocol.InstallClass.CLOCK))
        assertEquals("install failed[118, -4] | reason: wrong", SamsungProtocol.detail("start\ninstall failed[118, -4]\nreason: wrong\ninstall failed[118, -4]\nend"))
        assertEquals("a | b | c", SamsungProtocol.detail("x\na\nb\nc"))
        assertEquals("code=401, message=bad token", SamsungProtocol.errorFields("""{"code":401,"message":"bad token","x":1}"""))
    }

    // --- Samsung girişi ---

    @Test fun signInCallbackDecodingKeepsPlus() {
        assertEquals("a+b c/", SamsungSignIn.percentDecode("a+b%20c%2F"))
        val code = """{"access_token":"tok+en","userId":"u1","inputEmailID":"a@b.c"}"""
        val body = "code=" + code.replace("\"", "%22").replace("{", "%7B").replace("}", "%7D").replace(":", "%3A").replace(",", "%2C") +
            "&state=${SamsungSignIn.STATE}"
        val r = SamsungSignIn.parseCallback(body) as SamsungSignIn.Callback.Ok
        assertEquals("tok+en", r.account.accessToken); assertEquals("u1", r.account.userId); assertEquals("a@b.c", r.account.email)
        assertTrue(SamsungSignIn.parseCallback(body.replace(SamsungSignIn.STATE, "baska")) is SamsungSignIn.Callback.NoAccount)
        assertTrue(SamsungSignIn.parseCallback("code=%7B%22error%22%3A%22x%22%7D&state=${SamsungSignIn.STATE}") is SamsungSignIn.Callback.NoAccount)
    }

    @Test fun signInListenerAnswersCallback() {
        SamsungSignIn.Listener(port = 0).use { l ->
            var account: SamsungCertificates.Account? = null
            val t = Thread { account = l.await(10_000) { false } }.apply { start() }
            fun post(path: String, body: String): String = java.net.Socket("127.0.0.1", l.localPort).use { s ->
                s.getOutputStream().write(("POST $path HTTP/1.1\r\nHost: localhost\r\nContent-Type: application/x-www-form-urlencoded\r\n" +
                    "Content-Length: ${body.toByteArray().size}\r\n\r\n$body").toByteArray())
                s.getInputStream().bufferedReader().readLine()
            }
            assertTrue(post("/baska", "").contains("404"))
            assertTrue(post("/signin/callback", "state=${SamsungSignIn.STATE}").contains("400"))
            assertTrue(post("/signin/callback", "code=%7B%22access_token%22%3A%22T%22%2C%22userId%22%3A%22U%22%7D&state=${SamsungSignIn.STATE}").contains("200"))
            t.join(5_000)
            assertEquals("T", account?.accessToken)
        }
    }

    // --- Sertifikalar ---

    private val key by lazy { AdbKey.generate() }

    private fun cert(subject: String, issuer: String, signKey: AdbKey, subjectKey: AdbKey, notAfter: Long = System.currentTimeMillis() + 86_400_000L * 365): ByteArray {
        val b = X509v3CertificateBuilder(X500Name(issuer), BigInteger.valueOf(System.nanoTime()), Date(System.currentTimeMillis() - 60_000), Date(notAfter),
            X500Name(subject), SubjectPublicKeyInfo.getInstance(subjectKey.publicKey.encoded))
        val alg = DefaultSignatureAlgorithmIdentifierFinder().find("SHA256withRSA")
        return b.build(BcRSAContentSignerBuilder(alg, DefaultDigestAlgorithmIdentifierFinder().find(alg)).build(AdbTls.privateParams(signKey))).encoded
    }

    @Test fun csrHasTizenSubjectAltNames() {
        val der = SamsungCertificates.csr(key.privateKey, SamsungCertificates.distributorSubject("a@b.c"), "DUID12345")
        val req = PKCS10CertificationRequest(der)
        assertTrue(req.isSignatureValid(BcRSAContentVerifierProviderBuilder(DefaultDigestAlgorithmIdentifierFinder()).build(org.bouncycastle.crypto.util.PublicKeyFactory.createKey(req.subjectPublicKeyInfo))))
        assertTrue(req.subject.toString().contains("CN=TizenSDK"))
        assertTrue(req.subject.toString().contains("a@b.c"))
        val ext = req.getAttributes(PKCSObjectIdentifiers.pkcs_9_at_extensionRequest)[0].attrValues.getObjectAt(0)
        val san = GeneralNames.fromExtensions(org.bouncycastle.asn1.x509.Extensions.getInstance(ext), Extension.subjectAlternativeName)
        assertEquals(listOf("URN:tizen:packageid=", "URN:tizen:deviceid=DUID12345"), san.names.map { it.name.toString() })
        assertTrue(san.names.all { it.tagNo == GeneralName.uniformResourceIdentifier })
        val author = PKCS10CertificationRequest(SamsungCertificates.csr(key.privateKey, SamsungCertificates.authorSubject(), null))
        assertEquals("CN=Nino", author.subject.toString())
        assertEquals(0, author.getAttributes(PKCSObjectIdentifiers.pkcs_9_at_extensionRequest).size)
        assertTrue(SamsungCertificates.pem("CERTIFICATE REQUEST", der).startsWith("-----BEGIN CERTIFICATE REQUEST-----\n"))
    }

    @Test fun certificateResponsesAndChainSelection() {
        val caKey = AdbKey.generate(); val otherKey = AdbKey.generate()
        val ca = cert("CN=VD DEVELOPER Public CA Class", "CN=Root", caKey, caKey)
        val impostor = cert("CN=VD DEVELOPER Public CA Class", "CN=Root", otherKey, otherKey) // aynı ad, başka anahtar
        val leaf = cert("CN=TizenSDK", "CN=VD DEVELOPER Public CA Class", caKey, key)
        assertArrayEquals(leaf, SamsungCertificates.parseCertificate(SamsungCertificates.pem("CERTIFICATE", leaf).toByteArray()))
        assertArrayEquals(leaf, SamsungCertificates.parseCertificate(leaf))
        assertArrayEquals(leaf, SamsungCertificates.parseCertificate(Base64.getEncoder().encode(leaf)))
        assertNull(SamsungCertificates.parseCertificate("""{"code":"401","message":"invalid token"}""".toByteArray()))
        val chain = SamsungCertificates.chain(leaf, listOf(impostor, ca))
        assertEquals(2, chain.size); assertArrayEquals(ca, chain[1])
        assertEquals(1, SamsungCertificates.chain(leaf, listOf(impostor)).size)
    }

    /** Uygulamayla gelen dört Samsung ara sertifikası okunur. */
    @Test fun bundledIntermediatesParse() {
        val dir = listOf(File("../../../windows/src/Nino.TvInstall/Samsung/ca"), File("../../windows/src/Nino.TvInstall/Samsung/ca")).firstOrNull { it.isDirectory }
        Assume.assumeTrue(dir != null)
        val certs = dir!!.listFiles()!!.filter { it.name.endsWith(".pem") }.flatMap { SamsungCertificates.parsePemCertificates(it.readText()) }
        assertEquals(4, certs.size)
        assertTrue(certs.map { X509CertificateHolder(it).subject.toString() }.any { "VD DEVELOPER Public CA Class" in it })
    }

    @Test fun profileStorageAndRejection() {
        val env = com.ninotranslator.mobile.tv.install.TvInstallEnv(java.nio.file.Files.createTempDirectory("s").toFile(),
            java.nio.file.Files.createTempDirectory("c").toFile(),
            object : com.ninotranslator.mobile.tv.install.TvPackageSource {
                override val index = com.ninotranslator.mobile.tv.install.TvPackageIndex.parse(""); override fun open(path: String) = null
            }, {})
        val caKey = AdbKey.generate()
        val a = cert("CN=Nino", "CN=CA", caKey, key); val d = cert("CN=TizenSDK", "CN=CA", caKey, key)
        assertNull(SamsungCertificates.loadProfile(env, "DUID/1"))
        SamsungCertificates.saveProfile(env, "DUID/1", key.privateKey, a, d, null)
        assertTrue(File(env.noBackupDir, "samsung/DUID_1/key.pk8").isFile)
        assertEquals("DUID/1", File(env.noBackupDir, "samsung/DUID_1/duid.txt").readText())
        val p = SamsungCertificates.loadProfile(env, "DUID/1")!!
        assertEquals(key.privateKey.modulus, p.key.modulus)
        // Yarın geçersiz olacak sertifika profili geçersiz kılar.
        SamsungCertificates.saveProfile(env, "DUID2", key.privateKey, cert("CN=Nino", "CN=CA", caKey, key, System.currentTimeMillis() + 3_600_000), d, null)
        assertNull(SamsungCertificates.loadProfile(env, "DUID2"))
        SamsungCertificates.rejectProfile(env, "DUID/1")
        assertNull(SamsungCertificates.loadProfile(env, "DUID/1"))
        assertTrue(File(env.noBackupDir, "samsung").list()!!.any { it.startsWith("DUID_1.rejected-") })
    }

    // --- İmza XML'i ---

    private fun wgt(): ByteArray {
        val out = ByteArrayOutputStream()
        ZipOutputStream(out).use { z ->
            fun put(n: String, s: String) { z.putNextEntry(ZipEntry(n)); z.write(s.toByteArray()); z.closeEntry() }
            put("config.xml", "<widget version=\"4.0.3\"/>")
            z.putNextEntry(ZipEntry("js/")); z.closeEntry()
            put("js/app.js", "console.log('merhaba');")
            put("index.html", "<html></html>")
            put("signature1.xml", "<eski/>")
            put("fonts/Bir Yazı.ttf", "ttf")
        }
        return out.toByteArray()
    }

    private fun unzip(b: ByteArray): LinkedHashMap<String, ByteArray> {
        val m = LinkedHashMap<String, ByteArray>()
        ZipInputStream(ByteArrayInputStream(b)).use { z -> while (true) { val e = z.nextEntry ?: break; m[e.name] = z.readBytes() } }
        return m
    }

    /** JDK'nin XML imza doğrulayıcısı ayrı bir `java` sürecinde (birim testleri android.jar ile derlenir, javax.xml.crypto yok). */
    private fun jdkVerify(files: Map<String, ByteArray>, name: String): String {
        val dir = java.nio.file.Files.createTempDirectory("wgt").toFile()
        files.forEach { (n, b) -> File(dir, n).apply { parentFile.mkdirs(); writeBytes(b) } }
        val pub = File(dir, "pub.der").apply { writeBytes(key.publicKey.encoded) }
        val src = File(dir, "VerifyWidgetSignature.java").apply { writeBytes(SamsungTest::class.java.getResourceAsStream("/tvinstall/VerifyWidgetSignature.java.txt")!!.readBytes()) }
        val java = File(System.getProperty("java.home"), "bin/java").path
        val p = ProcessBuilder(java, src.path, dir.path, name, pub.path).redirectErrorStream(true).start()
        val out = p.inputStream.bufferedReader().readText().trim()
        p.waitFor()
        dir.deleteRecursively()
        return out.lines().last()
    }

    /** JDK'nin kendi XML imza doğrulayıcısı (bağımsız kanonikleştirme) ve BouncyCastle ile doğrulanır. */
    @Test fun signedWidgetValidatesWithJdkXmlDsigAndBouncyCastle() {
        val caKey = AdbKey.generate()
        val author = cert("CN=Nino", "CN=Author CA", caKey, key); val authorCa = cert("CN=Author CA", "CN=Author CA", caKey, caKey)
        val dist = cert("CN=TizenSDK", "CN=Dist CA", caKey, key)
        val signed = WidgetSigner.sign(wgt(), AdbTls.privateParams(key), listOf(author, authorCa), listOf(dist))
        val files = unzip(signed)
        assertEquals(listOf("author-signature.xml", "signature1.xml", "config.xml", "js/app.js", "index.html", "fonts/Bir Yazı.ttf"), files.keys.toList())
        assertFalse(String(files["signature1.xml"]!!).contains("<eski/>"))

        for ((name, expectRefs) in listOf("author-signature.xml" to 5, "signature1.xml" to 6)) {
            val xml = files[name]!!
            assertFalse(String(xml).startsWith("<?xml"))
            assertFalse(String(xml).contains("\n"))
            assertEquals("$name", "OK $expectRefs", jdkVerify(files, name))

            // BouncyCastle: kanonik SignedInfo'nun RSA-SHA512 imzası ve dosya özetleri.
            val text = String(xml, Charsets.UTF_8)
            val si = "<SignedInfo xmlns=\"http://www.w3.org/2000/09/xmldsig#\">" + text.substringAfter("<SignedInfo>").substringBefore("</SignedInfo>") + "</SignedInfo>"
            val value = Base64.getDecoder().decode(text.substringAfter("<SignatureValue>").substringBefore("</SignatureValue>"))
            val v = RSADigestSigner(SHA512Digest()); v.init(false, RSAKeyParameters(false, key.privateKey.modulus, key.privateKey.publicExponent))
            val siBytes = si.toByteArray(); v.update(siBytes, 0, siBytes.size)
            assertTrue(v.verifySignature(value))
            val digest = Base64.getEncoder().encodeToString(MessageDigest.getInstance("SHA-512").digest(files["config.xml"]!!))
            assertTrue(text.contains("<Reference URI=\"config.xml\"><DigestMethod Algorithm=\"http://www.w3.org/2001/04/xmlenc#sha512\"></DigestMethod><DigestValue>$digest</DigestValue>"))
        }
        val dist0 = String(files["signature1.xml"]!!)
        assertTrue(dist0.indexOf("URI=\"author-signature.xml\"") < dist0.indexOf("URI=\"config.xml\""))
        assertTrue(dist0.contains("#role-distributor") && dist0.contains("Id=\"DistributorSignature\""))
        assertTrue(String(files["author-signature.xml"]!!).contains("#role-author"))
        assertTrue(String(files["author-signature.xml"]!!).contains("URI=\"fonts/Bir%20Yaz%C4%B1.ttf\""))
        // KeyInfo: yaprak, sonra ara sertifika.
        val certs = Regex("<X509Certificate>([^<]+)</X509Certificate>").findAll(String(files["author-signature.xml"]!!)).map { it.groupValues[1] }.toList()
        assertEquals(listOf(Base64.getEncoder().encodeToString(author), Base64.getEncoder().encodeToString(authorCa)), certs)
    }
}
