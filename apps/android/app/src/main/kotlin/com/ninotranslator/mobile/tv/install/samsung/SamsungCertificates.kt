// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.tv.install.samsung

import com.ninotranslator.mobile.tv.install.techDetail
import com.ninotranslator.mobile.tv.install.TvInstallEnv
import com.ninotranslator.mobile.tv.install.TvInstallError
import com.ninotranslator.mobile.tv.install.TvInstallException
import org.bouncycastle.asn1.pkcs.PKCSObjectIdentifiers
import org.bouncycastle.asn1.x500.X500Name
import org.bouncycastle.asn1.x500.X500NameBuilder
import org.bouncycastle.asn1.x500.style.BCStyle
import org.bouncycastle.asn1.x509.Extension
import org.bouncycastle.asn1.x509.ExtensionsGenerator
import org.bouncycastle.asn1.x509.GeneralName
import org.bouncycastle.asn1.x509.GeneralNames
import org.bouncycastle.asn1.x509.SubjectPublicKeyInfo
import org.bouncycastle.cert.X509CertificateHolder
import org.bouncycastle.crypto.util.PrivateKeyFactory
import org.bouncycastle.operator.DefaultDigestAlgorithmIdentifierFinder
import org.bouncycastle.operator.DefaultSignatureAlgorithmIdentifierFinder
import org.bouncycastle.operator.bc.BcRSAContentSignerBuilder
import org.bouncycastle.operator.bc.BcRSAContentVerifierProviderBuilder
import org.bouncycastle.pkcs.PKCS10CertificationRequestBuilder
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.security.KeyFactory
import java.security.KeyPairGenerator
import java.security.interfaces.RSAPrivateCrtKey
import java.security.spec.PKCS8EncodedKeySpec
import java.text.SimpleDateFormat
import java.util.Base64
import java.util.Date
import java.util.Locale
import java.util.UUID

/** Samsung'un TV'ye özel sertifikası (tv.md 3.3 adım 5): istekler, ara sertifikalar, saklanan profil. */
object SamsungCertificates {
    const val AUTHORS_URL = "https://svdca.samsungqbe.com/apis/v3/authors"
    const val DEVICE_PROFILE_URL = "https://svdca.samsungqbe.com/apis/v1/distributors"
    const val DISTRIBUTORS_URL = "https://svdca.samsungqbe.com/apis/v3/distributors"

    // --- İstekler ---

    fun pem(type: String, der: ByteArray): String = buildString {
        append("-----BEGIN ").append(type).append("-----\n")
        Base64.getEncoder().encodeToString(der).chunked(64).forEach { append(it).append('\n') }
        append("-----END ").append(type).append("-----\n")
    }

    /** PKCS#10, SHA256withRSA. Dağıtıcı isteğinde SAN olarak iki URI: paket kimliği (boş) ve TV'nin DUID'i. */
    fun csr(key: RSAPrivateCrtKey, subject: X500Name, duid: String?): ByteArray {
        val pub = KeyFactory.getInstance("RSA").generatePublic(java.security.spec.RSAPublicKeySpec(key.modulus, key.publicExponent))
        val b = PKCS10CertificationRequestBuilder(subject, SubjectPublicKeyInfo.getInstance(pub.encoded))
        if (duid != null) {
            val san = GeneralNames(arrayOf(
                GeneralName(GeneralName.uniformResourceIdentifier, "URN:tizen:packageid="),
                GeneralName(GeneralName.uniformResourceIdentifier, "URN:tizen:deviceid=$duid"),
            ))
            val ext = ExtensionsGenerator().apply { addExtension(Extension.subjectAlternativeName, false, san) }
            b.addAttribute(PKCSObjectIdentifiers.pkcs_9_at_extensionRequest, ext.generate())
        }
        val sigAlg = DefaultSignatureAlgorithmIdentifierFinder().find("SHA256withRSA")
        val signer = BcRSAContentSignerBuilder(sigAlg, DefaultDigestAlgorithmIdentifierFinder().find(sigAlg))
            .build(PrivateKeyFactory.createKey(key.encoded))
        return b.build(signer).encoded
    }

    fun authorSubject(): X500Name = X500Name("CN=Nino")

    fun distributorSubject(email: String?): X500Name = X500NameBuilder(BCStyle.INSTANCE).apply {
        addRDN(BCStyle.CN, "TizenSDK")
        if (!email.isNullOrBlank()) addRDN(BCStyle.EmailAddress, email)
    }.build()

    /** Yanıttan sertifika (PEM, base64 ya da DER); değilse null. */
    fun parseCertificate(body: ByteArray): ByteArray? {
        val text = String(body, Charsets.ISO_8859_1)
        val der: ByteArray? = when {
            "BEGIN CERTIFICATE" in text -> runCatching {
                val b64 = text.substringAfter("-----BEGIN CERTIFICATE-----").substringBefore("-----END CERTIFICATE-----")
                Base64.getMimeDecoder().decode(b64.trim())
            }.getOrNull()
            body.isNotEmpty() && body[0].toInt() == 0x30 -> body
            else -> runCatching { Base64.getMimeDecoder().decode(text.trim().trim('"')) }.getOrNull()
        }
        return der?.takeIf { runCatching { X509CertificateHolder(it) }.isSuccess }
    }

    // --- Ara sertifikalar (uygulamayla gelen dört PEM) ---

    fun parsePemCertificates(text: String): List<ByteArray> = Regex("-----BEGIN CERTIFICATE-----([\\s\\S]*?)-----END CERTIFICATE-----")
        .findAll(text).mapNotNull { runCatching { Base64.getMimeDecoder().decode(it.groupValues[1].trim()) }.getOrNull() }.toList()

    /** Yaprak + onu veren ara sertifika (ad kanonik karşılaştırılır, imza doğrulanır); bulunamazsa yalnız yaprak. */
    fun chain(leaf: ByteArray, cas: List<ByteArray>): List<ByteArray> {
        val l = X509CertificateHolder(leaf)
        val issuer = cas.firstOrNull { ca ->
            runCatching {
                val c = X509CertificateHolder(ca)
                c.subject == l.issuer && l.isSignatureValid(BcRSAContentVerifierProviderBuilder(DefaultDigestAlgorithmIdentifierFinder()).build(c))
            }.getOrDefault(false)
        }
        return listOfNotNull(leaf, issuer)
    }

    // --- Saklanan profil (`no_backup/samsung/<DUID>/`) ---

    class Profile(val dir: File, val key: RSAPrivateCrtKey, val author: ByteArray, val distributor: ByteArray, val deviceProfile: ByteArray?, val duid: String?)

    fun profileDir(env: TvInstallEnv, duid: String): File = env.file("samsung", TvInstallEnv.safeName(duid, allowDot = false))

    /** Geçerli profil: üç ana dosya, iki sertifika da yarın için geçerli ve DUID tutuyor. */
    fun loadProfile(env: TvInstallEnv, duid: String): Profile? {
        val dir = profileDir(env, duid)
        val keyF = File(dir, "key.pk8"); val a = File(dir, "author.cer"); val d = File(dir, "distributor.cer")
        if (!keyF.isFile || !a.isFile || !d.isFile) return null
        return runCatching {
            val key = KeyFactory.getInstance("RSA").generatePrivate(PKCS8EncodedKeySpec(keyF.readBytes())) as RSAPrivateCrtKey
            val p = Profile(dir, key, a.readBytes(), d.readBytes(), File(dir, "device-profile.xml").takeIf { it.isFile }?.readBytes(),
                File(dir, "duid.txt").takeIf { it.isFile }?.readText()?.trim())
            val tomorrow = Date(env.now() + 24 * 3600 * 1000L)
            val ok = listOf(p.author, p.distributor).all { X509CertificateHolder(it).isValidOn(tomorrow) } && (p.duid == null || p.duid == duid)
            if (ok) p else null
        }.getOrNull()
    }

    fun saveProfile(env: TvInstallEnv, duid: String, key: RSAPrivateCrtKey, author: ByteArray, distributor: ByteArray, deviceProfile: ByteArray?): Profile {
        val dir = profileDir(env, duid)
        dir.mkdirs()
        File(dir, "key.pk8").writeBytes(key.encoded)
        File(dir, "author.cer").writeBytes(author)
        File(dir, "distributor.cer").writeBytes(distributor)
        if (deviceProfile != null) File(dir, "device-profile.xml").writeBytes(deviceProfile)
        File(dir, "duid.txt").writeText(duid)
        return Profile(dir, key, author, distributor, deviceProfile, duid)
    }

    /** TV'nin reddettiği profil kenara konur: `<DUID>.rejected-<zaman>`. */
    fun rejectProfile(env: TvInstallEnv, duid: String) {
        val dir = profileDir(env, duid)
        if (!dir.isDirectory) return
        val stamp = SimpleDateFormat("yyyyMMddHHmmss", Locale.ROOT).format(Date(env.now()))
        dir.renameTo(File(dir.parentFile, dir.name + ".rejected-" + stamp))
    }

    // --- Samsung'dan sertifika alma ---

    data class Account(val accessToken: String, val userId: String, val email: String?)

    /** Yeni anahtar, iki istek ve üç POST. Hata [TvInstallError.SAMSUNG_CERTIFICATE]. */
    fun request(env: TvInstallEnv, account: Account, duid: String, http: Multipart = Multipart()): Profile {
        val key = KeyPairGenerator.getInstance("RSA").apply { initialize(2048) }.generateKeyPair().private as RSAPrivateCrtKey
        val authorCsr = pem("CERTIFICATE REQUEST", csr(key, authorSubject(), null))
        val distCsr = pem("CERTIFICATE REQUEST", csr(key, distributorSubject(account.email), duid))
        val base = listOf("access_token" to account.accessToken, "user_id" to account.userId, "platform" to "VD")
        val dist = base + listOf("privilege_level" to "public", "developer_type" to "Individual")
        val authorBody = post(env, http, AUTHORS_URL, base, "author.csr", authorCsr)
        val author = parseCertificate(authorBody) ?: fail(env, "yazar sertifikası yerine", authorBody)
        val profileBody = runCatching { post(env, http, DEVICE_PROFILE_URL, dist, "distributor.csr", distCsr) }
            .onFailure { env.log("cihaz profili alınamadı: ${it.message}") }.getOrNull()
        val distBody = post(env, http, DISTRIBUTORS_URL, dist, "distributor.csr", distCsr)
        val distributor = parseCertificate(distBody) ?: fail(env, "dağıtıcı sertifikası yerine", distBody)
        env.log("Samsung sertifikaları alındı")
        return saveProfile(env, duid, key, author, distributor, profileBody?.takeIf { String(it, Charsets.UTF_8).contains("<") })
    }

    private fun fail(env: TvInstallEnv, what: String, body: ByteArray): Nothing {
        val text = String(body, Charsets.UTF_8)
        val fields = SamsungProtocol.errorFields(text)
        env.log("Samsung $what: ${fields ?: text.take(300)}")
        throw TvInstallException(TvInstallError.SAMSUNG_CERTIFICATE, fields ?: text.take(200))
    }

    private fun post(env: TvInstallEnv, http: Multipart, url: String, fields: List<Pair<String, String>>, fileName: String, file: String): ByteArray {
        val (code, body) = try { http.post(url, fields, fileName, file.toByteArray(Charsets.US_ASCII)) } catch (e: IOException) {
            throw TvInstallException(TvInstallError.SAMSUNG_CERTIFICATE, "${url.substringAfterLast('/')}: ${techDetail(e)}", note = e.message)
        }
        if (code !in 200..299) {
            val text = String(body, Charsets.UTF_8)
            env.log("Samsung ${url.substringAfter("apis/")} $code: ${SamsungProtocol.errorFields(text) ?: text.take(300)}")
            throw TvInstallException(TvInstallError.SAMSUNG_CERTIFICATE, "HTTP $code ${SamsungProtocol.errorFields(text).orEmpty()}".trim())
        }
        return body
    }

    /** multipart/form-data POST (20 sn bağlantı, 60 sn okuma). */
    open class Multipart {
        open fun post(url: String, fields: List<Pair<String, String>>, fileName: String, file: ByteArray): Pair<Int, ByteArray> {
            val boundary = "----nino" + UUID.randomUUID().toString().replace("-", "")
            val body = ByteArrayOutputStream()
            fun w(s: String) = body.write(s.toByteArray(Charsets.UTF_8))
            for ((k, v) in fields) {
                w("--$boundary\r\nContent-Disposition: form-data; name=\"$k\"\r\n\r\n$v\r\n")
            }
            w("--$boundary\r\nContent-Disposition: form-data; name=\"csr\"; filename=\"$fileName\"\r\nContent-Type: application/octet-stream\r\n\r\n")
            body.write(file)
            w("\r\n--$boundary--\r\n")
            val c = URL(url).openConnection() as HttpURLConnection
            c.connectTimeout = 20_000; c.readTimeout = 60_000
            c.requestMethod = "POST"; c.doOutput = true
            c.setRequestProperty("Content-Type", "multipart/form-data; boundary=$boundary")
            try {
                c.outputStream.use { it.write(body.toByteArray()) }
                val code = c.responseCode
                val bytes = (if (code in 200..299) c.inputStream else c.errorStream)?.use { it.readBytes() } ?: ByteArray(0)
                return code to bytes
            } finally { c.disconnect() }
        }
    }
}
