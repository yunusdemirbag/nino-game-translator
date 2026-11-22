// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.data

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** `secrets` değerlerinin şifrelenmesi. Çıktı: IV[12] || şifreli metin || etiket[16] (base64'ü [Secrets] yapar). */
interface SecretCipher {
    /** Başarısızsa null. */
    fun encrypt(plain: ByteArray): ByteArray?

    /** Bozuk veri, kayıp anahtar ya da etiket hatası → null. */
    fun decrypt(blob: ByteArray): ByteArray?

    /** Bütün anahtarları siler (iki takma ad). */
    fun destroyKeys()
}

/** Anahtar kaynağı: okuma ve yazma için anahtar seçimi ayrı (okuma asla yeni anahtar üretmez). */
interface SecretKeySource {
    fun keyForRead(): SecretKey?
    fun keyForWrite(): SecretKey?
    fun destroy()
}

/** AES/GCM/NoPadding çerçevesi; IV şifreleyici tarafından üretilir, AAD yok. */
class AesGcmCipher(private val keys: SecretKeySource) : SecretCipher {
    override fun encrypt(plain: ByteArray): ByteArray? = try {
        val key = keys.keyForWrite() ?: return null
        val c = Cipher.getInstance(TRANSFORMATION)
        c.init(Cipher.ENCRYPT_MODE, key)
        val iv = c.iv
        if (iv == null || iv.size != IV_BYTES) null else iv + c.doFinal(plain)
    } catch (_: Exception) {
        null
    }

    override fun decrypt(blob: ByteArray): ByteArray? {
        if (blob.size < IV_BYTES + TAG_BITS / 8) return null
        return try {
            val key = keys.keyForRead() ?: return null
            val c = Cipher.getInstance(TRANSFORMATION)
            c.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(TAG_BITS, blob, 0, IV_BYTES))
            c.doFinal(blob, IV_BYTES, blob.size - IV_BYTES)
        } catch (_: Exception) {
            null
        }
    }

    override fun destroyKeys() = keys.destroy()

    companion object {
        const val TRANSFORMATION = "AES/GCM/NoPadding"
        const val IV_BYTES = 12
        const val TAG_BITS = 128
    }
}

/** Keystore'a ince erişim (JVM testinde sahtesi kullanılır). Hata atarsa "bilinmiyor" sayılır. */
interface KeyAliasStore {
    fun contains(alias: String): Boolean
    fun get(alias: String): SecretKey?
    fun create(alias: String): SecretKey
    fun delete(alias: String)
}

/**
 * Takma ad seçimi (§2): önce `nino-secrets`, yoksa eski takma ad (olduğu gibi kullanılır), ikisi de **kesin** yoksa
 * yalnız yazarken `nino-secrets` üretilir. Keystore hata verirse hiçbir şey üretilmez.
 */
class KeystoreKeySource(private val store: KeyAliasStore) : SecretKeySource {
    @Volatile private var cached: SecretKey? = null

    /** Şu an kullanılacak takma ad; ikisi de yoksa null. Keystore hatası dışarı atılır. */
    fun selectAlias(): String? = when {
        store.contains(CURRENT_ALIAS) -> CURRENT_ALIAS
        store.contains(LegacyNames.secretsKeyAlias) -> LegacyNames.secretsKeyAlias
        else -> null
    }

    override fun keyForRead(): SecretKey? {
        cached?.let { return it }
        return try {
            val alias = selectAlias() ?: return null
            store.get(alias)?.also { cached = it }
        } catch (_: Exception) {
            null
        }
    }

    @Synchronized
    override fun keyForWrite(): SecretKey? {
        cached?.let { return it }
        return try {
            val alias = selectAlias()
            val key = if (alias != null) store.get(alias) else store.create(CURRENT_ALIAS)
            key?.also { cached = it }
        } catch (_: Exception) {
            null
        }
    }

    @Synchronized
    override fun destroy() {
        cached = null
        runCatching { store.delete(CURRENT_ALIAS) }
        runCatching { store.delete(LegacyNames.secretsKeyAlias) }
    }

    companion object {
        const val CURRENT_ALIAS = "nino-secrets"
    }
}

/** Android Keystore: AES-256, GCM, dolgu yok; kullanıcı doğrulaması ve StrongBox istenmez. */
class AndroidKeyAliasStore : KeyAliasStore {
    private val ks: KeyStore by lazy { KeyStore.getInstance(PROVIDER).apply { load(null) } }

    override fun contains(alias: String) = ks.containsAlias(alias)

    override fun get(alias: String): SecretKey? = (ks.getEntry(alias, null) as? KeyStore.SecretKeyEntry)?.secretKey

    override fun create(alias: String): SecretKey {
        val gen = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, PROVIDER)
        gen.init(
            KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build(),
        )
        return gen.generateKey()
    }

    override fun delete(alias: String) {
        if (ks.containsAlias(alias)) ks.deleteEntry(alias)
    }

    companion object {
        const val PROVIDER = "AndroidKeyStore"

        fun cipher(): SecretCipher = AesGcmCipher(KeystoreKeySource(AndroidKeyAliasStore()))
    }
}
