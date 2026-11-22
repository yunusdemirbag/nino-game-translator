// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.tv.install.adb

import org.bouncycastle.asn1.x500.X500Name
import org.bouncycastle.asn1.x509.AlgorithmIdentifier
import org.bouncycastle.asn1.x509.SubjectPublicKeyInfo
import org.bouncycastle.cert.X509v3CertificateBuilder
import org.bouncycastle.crypto.params.AsymmetricKeyParameter
import org.bouncycastle.crypto.util.PrivateKeyFactory
import org.bouncycastle.operator.DefaultDigestAlgorithmIdentifierFinder
import org.bouncycastle.operator.DefaultSignatureAlgorithmIdentifierFinder
import org.bouncycastle.operator.bc.BcRSAContentSignerBuilder
import org.bouncycastle.tls.Certificate
import org.bouncycastle.tls.CertificateEntry
import org.bouncycastle.tls.CertificateRequest
import org.bouncycastle.tls.DefaultTlsClient
import org.bouncycastle.tls.ProtocolVersion
import org.bouncycastle.tls.SignatureAndHashAlgorithm
import org.bouncycastle.tls.TlsAuthentication
import org.bouncycastle.tls.TlsClientProtocol
import org.bouncycastle.tls.TlsCredentials
import org.bouncycastle.tls.TlsServerCertificate
import org.bouncycastle.tls.crypto.TlsCryptoParameters
import org.bouncycastle.tls.crypto.impl.bc.BcDefaultTlsCredentialedSigner
import org.bouncycastle.tls.crypto.impl.bc.BcTlsCertificate
import org.bouncycastle.tls.crypto.impl.bc.BcTlsCrypto
import java.io.InputStream
import java.io.OutputStream
import java.math.BigInteger
import java.security.SecureRandom
import java.util.Date

/**
 * Kablosuz hata ayıklamanın TLS 1.3'ü (BouncyCastle'ın hafif TLS'i; Android'in kendi kırpılmış sağlayıcısına
 * dokunmaz). Telefon adb anahtarından üretilmiş kendinden imzalı sertifikayla kendini tanıtır; TV'nin sertifikası
 * denetlenmez (adb de denetlemez).
 */
object AdbTls {
    private const val TEN_YEARS_MS = 10L * 365 * 24 * 3600 * 1000

    /** CN=Nino, 10 yıl, SHA256withRSA, kendinden imzalı. DER. */
    fun selfSignedCertificate(key: AdbKey, now: Long = System.currentTimeMillis()): ByteArray {
        val name = X500Name("CN=Nino")
        val spki = SubjectPublicKeyInfo.getInstance(key.publicKey.encoded)
        val builder = X509v3CertificateBuilder(name, BigInteger.ONE, Date(now - 24 * 3600 * 1000), Date(now + TEN_YEARS_MS), name, spki)
        val sigAlg: AlgorithmIdentifier = DefaultSignatureAlgorithmIdentifierFinder().find("SHA256withRSA")
        val digAlg = DefaultDigestAlgorithmIdentifierFinder().find(sigAlg)
        val signer = BcRSAContentSignerBuilder(sigAlg, digAlg).build(privateParams(key))
        return builder.build(signer).encoded
    }

    fun privateParams(key: AdbKey): AsymmetricKeyParameter = PrivateKeyFactory.createKey(key.privateKey.encoded)

    /** TLS'i kurulmuş bağlantı. */
    class Session(val protocol: TlsClientProtocol, private val client: Client) {
        val input: InputStream get() = protocol.inputStream
        val output: OutputStream get() = protocol.outputStream

        /** El sıkışma biterken alınan RFC 8446 dışa aktarıcı çıktısı (istenmişse). */
        val exported: ByteArray? get() = client.exported
    }

    /** [export] verilirse el sıkışma biterken (BouncyCastle yalnız orada izin verir) dışa aktarıcı çalışır. */
    class Client(
        private val bc: BcTlsCrypto, private val key: AdbKey, private val certDer: ByteArray,
        private val export: Pair<String, Int>? = null,
    ) : DefaultTlsClient(bc) {
        @Volatile var exported: ByteArray? = null
            private set

        override fun notifyHandshakeComplete() {
            super.notifyHandshakeComplete()
            export?.let { (label, n) -> exported = context.exportKeyingMaterial(label, null, n) }
        }

        override fun getSupportedVersions(): Array<ProtocolVersion> = ProtocolVersion.TLSv13.only()

        override fun getAuthentication(): TlsAuthentication = object : TlsAuthentication {
            override fun notifyServerCertificate(serverCertificate: TlsServerCertificate) = Unit
            override fun getClientCredentials(request: CertificateRequest): TlsCredentials {
                val cert = Certificate(request.certificateRequestContext, arrayOf(CertificateEntry(BcTlsCertificate(bc, certDer), null)))
                return BcDefaultTlsCredentialedSigner(TlsCryptoParameters(context), bc, privateParams(key), cert,
                    SignatureAndHashAlgorithm.rsa_pss_rsae_sha256)
            }
        }
    }

    /** Verilen akışlar üstünde TLS 1.3 istemci el sıkışması. */
    fun connect(input: InputStream, output: OutputStream, key: AdbKey, export: Pair<String, Int>? = null,
                random: SecureRandom = SecureRandom()): Session {
        val bc = BcTlsCrypto(random)
        val client = Client(bc, key, selfSignedCertificate(key), export)
        val protocol = TlsClientProtocol(input, output)
        protocol.connect(client)
        return Session(protocol, client)
    }

    /** `STLS` için yükseltici. */
    fun upgrade(key: AdbKey): AdbTlsUpgrade = AdbTlsUpgrade { i, o ->
        val s = connect(i, o, key)
        s.input to s.output
    }
}
