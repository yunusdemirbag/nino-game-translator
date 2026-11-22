// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.tv.install.samsung

import org.bouncycastle.crypto.digests.SHA512Digest
import org.bouncycastle.crypto.params.AsymmetricKeyParameter
import org.bouncycastle.crypto.signers.RSADigestSigner
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.net.URLEncoder
import java.security.MessageDigest
import java.util.Base64
import java.util.zip.ZipEntry
import java.util.zip.ZipInputStream
import java.util.zip.ZipOutputStream

/**
 * Tizen `.wgt` imzası (W3C Widget Signature, tv.md 3.3 adım 7): yazar imzası (`author-signature.xml`) ve dağıtıcı
 * imzası (`signature1.xml`). Özet SHA-512, imza RSA-SHA512. SignedInfo exclusive C14N, `#prop` nesnesi C14N 1.1 ile
 * kanonikleştirilir; XML bildirim ve boşluksuz, öğeler açık kapanışlı yazıldığı için dosyadaki metin kanonik biçimle
 * aynıdır (yalnız üstten gelen ad alanı bildirimi kanonik biçime eklenir).
 */
object WidgetSigner {
    const val AUTHOR_FILE = "author-signature.xml"
    const val DISTRIBUTOR_FILE = "signature1.xml"
    private const val DSIG = "http://www.w3.org/2000/09/xmldsig#"
    private const val EXC_C14N = "http://www.w3.org/2001/10/xml-exc-c14n#"
    private const val C14N11 = "http://www.w3.org/2006/12/xml-c14n11"
    private const val RSA_SHA512 = "http://www.w3.org/2001/04/xmldsig-more#rsa-sha512"
    private const val SHA512 = "http://www.w3.org/2001/04/xmlenc#sha512"
    private const val DSP = "http://www.w3.org/2009/xmldsig-properties"
    private const val PROFILE = "http://www.w3.org/ns/widgets-digsig#profile"
    private const val ROLE_AUTHOR = "http://www.w3.org/ns/widgets-digsig#role-author"
    private const val ROLE_DISTRIBUTOR = "http://www.w3.org/ns/widgets-digsig#role-distributor"

    class Entry(val name: String, val data: ByteArray)

    /** Paketin dosyaları: klasör girdileri ve eski imzalar atılır, sıra korunur. */
    fun readEntries(wgt: ByteArray): List<Entry> {
        val out = ArrayList<Entry>()
        ZipInputStream(ByteArrayInputStream(wgt)).use { z ->
            while (true) {
                val e = z.nextEntry ?: break
                if (e.isDirectory || e.name.endsWith("/") || isSignatureFile(e.name)) continue
                out += Entry(e.name, z.readBytes())
            }
        }
        return out
    }

    fun isSignatureFile(name: String) = name == AUTHOR_FILE || Regex("signature\\d+\\.xml").matches(name)

    /** Dosya adından Reference URI'si (yüzde kodlu, `/` korunur). */
    fun uri(name: String): String = name.split('/').joinToString("/") { URLEncoder.encode(it, "UTF-8").replace("+", "%20") }

    private fun digest(b: ByteArray): String = Base64.getEncoder().encodeToString(MessageDigest.getInstance("SHA-512").digest(b))

    private fun escAttr(s: String) = s.replace("&", "&amp;").replace("<", "&lt;").replace("\"", "&quot;")

    /** `#prop` nesnesi; [withNs] true ise kanonik biçim (üstten gelen ad alanı bildirimiyle). */
    fun propObject(signatureId: String, role: String, withNs: Boolean): String {
        val ns = if (withNs) " xmlns=\"$DSIG\"" else ""
        return "<Object$ns Id=\"prop\"><SignatureProperties xmlns:dsp=\"$DSP\">" +
            "<SignatureProperty Id=\"profile\" Target=\"#$signatureId\"><dsp:Profile URI=\"$PROFILE\"></dsp:Profile></SignatureProperty>" +
            "<SignatureProperty Id=\"role\" Target=\"#$signatureId\"><dsp:Role URI=\"$role\"></dsp:Role></SignatureProperty>" +
            "<SignatureProperty Id=\"identifier\" Target=\"#$signatureId\"><dsp:Identifier></dsp:Identifier></SignatureProperty>" +
            "</SignatureProperties></Object>"
    }

    fun signedInfo(refs: List<Pair<String, ByteArray>>, propDigest: String, withNs: Boolean): String {
        val sb = StringBuilder()
        sb.append("<SignedInfo").append(if (withNs) " xmlns=\"$DSIG\"" else "").append(">")
        sb.append("<CanonicalizationMethod Algorithm=\"$EXC_C14N\"></CanonicalizationMethod>")
        sb.append("<SignatureMethod Algorithm=\"$RSA_SHA512\"></SignatureMethod>")
        for ((name, data) in refs) {
            sb.append("<Reference URI=\"").append(escAttr(uri(name))).append("\">")
            sb.append("<DigestMethod Algorithm=\"$SHA512\"></DigestMethod><DigestValue>").append(digest(data)).append("</DigestValue></Reference>")
        }
        sb.append("<Reference URI=\"#prop\"><Transforms><Transform Algorithm=\"$C14N11\"></Transform></Transforms>")
        sb.append("<DigestMethod Algorithm=\"$SHA512\"></DigestMethod><DigestValue>").append(propDigest).append("</DigestValue></Reference>")
        sb.append("</SignedInfo>")
        return sb.toString()
    }

    /** Tek imza dosyası. [chain] yaprak sertifika ve onu veren ara sertifika (DER). */
    fun signatureXml(id: String, role: String, refs: List<Pair<String, ByteArray>>, key: AsymmetricKeyParameter, chain: List<ByteArray>): String {
        val propDigest = digest(propObject(id, role, withNs = true).toByteArray(Charsets.UTF_8))
        val canonical = signedInfo(refs, propDigest, withNs = true).toByteArray(Charsets.UTF_8)
        val signer = RSADigestSigner(SHA512Digest())
        signer.init(true, key)
        signer.update(canonical, 0, canonical.size)
        val sig = Base64.getEncoder().encodeToString(signer.generateSignature())
        val certs = chain.joinToString("") { "<X509Certificate>" + Base64.getEncoder().encodeToString(it) + "</X509Certificate>" }
        return "<Signature xmlns=\"$DSIG\" Id=\"$id\">" + signedInfo(refs, propDigest, withNs = false) +
            "<SignatureValue>$sig</SignatureValue><KeyInfo><X509Data>$certs</X509Data></KeyInfo>" +
            propObject(id, role, withNs = false) + "</Signature>"
    }

    /**
     * İmzalı yeni paket: önce yazar imzası, sonra dağıtıcı imzası, sonra dosyalar. Yazar imzası her dosyayı, dağıtıcı
     * imzası yazar imzasını ve her dosyayı kapsar.
     */
    fun sign(wgt: ByteArray, key: AsymmetricKeyParameter, authorChain: List<ByteArray>, distributorChain: List<ByteArray>): ByteArray {
        val entries = readEntries(wgt)
        val files = entries.map { it.name to it.data }
        val author = signatureXml("AuthorSignature", ROLE_AUTHOR, files, key, authorChain).toByteArray(Charsets.UTF_8)
        val distributor = signatureXml("DistributorSignature", ROLE_DISTRIBUTOR, listOf(AUTHOR_FILE to author) + files, key, distributorChain)
            .toByteArray(Charsets.UTF_8)
        val out = ByteArrayOutputStream()
        ZipOutputStream(out).use { z ->
            fun put(name: String, data: ByteArray) { z.putNextEntry(ZipEntry(name)); z.write(data); z.closeEntry() }
            put(AUTHOR_FILE, author)
            put(DISTRIBUTOR_FILE, distributor)
            entries.forEach { put(it.name, it.data) }
        }
        return out.toByteArray()
    }
}
