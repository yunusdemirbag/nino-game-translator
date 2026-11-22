// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.tv.install.adb

import org.bouncycastle.tls.Certificate
import org.bouncycastle.tls.CertificateEntry
import org.bouncycastle.tls.CertificateRequest
import org.bouncycastle.tls.DefaultTlsServer
import org.bouncycastle.tls.ProtocolVersion
import org.bouncycastle.tls.SignatureAndHashAlgorithm
import org.bouncycastle.tls.TlsCredentials
import org.bouncycastle.tls.TlsServerProtocol
import org.bouncycastle.tls.TlsUtils
import org.bouncycastle.tls.crypto.TlsCryptoParameters
import org.bouncycastle.tls.crypto.impl.bc.BcDefaultTlsCredentialedSigner
import org.bouncycastle.tls.crypto.impl.bc.BcTlsCertificate
import org.bouncycastle.tls.crypto.impl.bc.BcTlsCrypto
import java.io.InputStream
import java.io.OutputStream
import java.security.SecureRandom
import java.util.Vector

/** Testlerde TV'nin TLS 1.3 sunucusu (istemci sertifikası ister, ilk sertifikayı saklar). */
class TestTlsServer(private val bc: BcTlsCrypto, private val key: AdbKey, private val certDer: ByteArray,
                    private val rejectClient: Boolean = false) : DefaultTlsServer(bc) {
    var clientCert: ByteArray? = null

    override fun getSupportedVersions(): Array<ProtocolVersion> = ProtocolVersion.TLSv13.only()

    override fun getCredentials(): TlsCredentials {
        val cert = Certificate(TlsUtils.EMPTY_BYTES, arrayOf(CertificateEntry(BcTlsCertificate(bc, certDer), null)))
        return BcDefaultTlsCredentialedSigner(TlsCryptoParameters(context), bc, AdbTls.privateParams(key), cert,
            SignatureAndHashAlgorithm.rsa_pss_rsae_sha256)
    }

    override fun getCertificateRequest(): CertificateRequest {
        val algs = Vector<SignatureAndHashAlgorithm>().apply { add(SignatureAndHashAlgorithm.rsa_pss_rsae_sha256) }
        return CertificateRequest(TlsUtils.EMPTY_BYTES, algs, null, null)
    }

    override fun notifyClientCertificate(clientCertificate: Certificate) {
        clientCert = clientCertificate.getCertificateAt(0)?.encoded
        if (rejectClient) throw org.bouncycastle.tls.TlsFatalAlert(org.bouncycastle.tls.AlertDescription.certificate_unknown)
    }

    /** El sıkışma biterken alınan adb eşleme dışa aktarıcısı. */
    @Volatile var exported: ByteArray? = null

    override fun notifyHandshakeComplete() {
        super.notifyHandshakeComplete()
        exported = context.exportKeyingMaterial(AdbPairing.EXPORT_LABEL, null, AdbPairing.EXPORT_LENGTH)
    }

    fun export(@Suppress("UNUSED_PARAMETER") label: String, @Suppress("UNUSED_PARAMETER") n: Int): ByteArray = exported!!

    companion object {
        fun accept(input: InputStream, output: OutputStream, key: AdbKey, rejectClient: Boolean = false): Pair<TlsServerProtocol, TestTlsServer> {
            val bc = BcTlsCrypto(SecureRandom())
            val server = TestTlsServer(bc, key, AdbTls.selfSignedCertificate(key), rejectClient)
            val p = TlsServerProtocol(input, output)
            p.accept(server)
            return p to server
        }
    }
}

/** Yerel döngü soketiyle sahte TV: [serve] ayrı iş parçacığında sunucu ucunda çalışır. */
class Loopback(serve: (java.net.Socket) -> Unit) : AutoCloseable {
    private val server = java.net.ServerSocket(0, 1, java.net.InetAddress.getLoopbackAddress())
    val port: Int get() = server.localPort
    @Volatile var failure: Throwable? = null
    private val thread = Thread {
        try { server.accept().use { s -> s.soTimeout = 20_000; serve(s) } } catch (e: Throwable) { failure = e }
    }.apply { isDaemon = true; start() }

    fun client(): AdbTransport = AdbTransport.socket("127.0.0.1", port, 2_000, 20_000)
    fun join() { thread.join(20_000) }
    override fun close() { runCatching { server.close() } }
}
