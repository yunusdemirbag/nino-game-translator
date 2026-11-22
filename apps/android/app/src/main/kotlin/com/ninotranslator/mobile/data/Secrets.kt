// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.data

import android.content.SharedPreferences
import com.ninotranslator.core.json.Json
import com.ninotranslator.core.json.str
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import java.time.Instant
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.util.Base64
import java.util.Locale

/** Kayıtlı PS5 (`secrets/console`). */
class Ps5Registration(val host: String, val name: String, val registKey: ByteArray, val morning: ByteArray) {
    fun withHost(newHost: String) = Ps5Registration(newHost, name, registKey, morning)

    override fun equals(other: Any?) = other is Ps5Registration && host == other.host && name == other.name &&
        registKey.contentEquals(other.registKey) && morning.contentEquals(other.morning)

    override fun hashCode() = (host.hashCode() * 31 + name.hashCode()) * 31 + registKey.contentHashCode()
    override fun toString() = "Ps5Registration(host=$host, name=$name)"
}

/** Microsoft kullanıcı jetonu. [raw] yanıtın tamamıdır (bilinmeyen alanlar korunur). */
class XboxToken(val raw: Map<String, Any?>) {
    val accessToken: String? get() = raw.str("access_token")
    val refreshToken: String get() = raw.str("refresh_token").orEmpty()

    /** ISO 8601 UTC an. */
    val expiresOn: String? get() = raw.str("expires_on")
    val expiresAtMs: Long? get() = expiresOn?.let { runCatching { Instant.parse(it).toEpochMilli() }.getOrNull() }
}

/**
 * `secrets` dosyası (§1.2): her değer [SecretCipher] ile şifrelenmiş, base64 (standart, satır sonu yok).
 * Boş/null yazmak anahtarı siler. Çözülemeyen değer "yok" sayılır (silinmez).
 */
class Secrets(prefs: SharedPreferences, private val cipher: SecretCipher) {
    val store = PrefStore(prefs)
    val changes: SharedFlow<String> get() = store.changes
    val revision: StateFlow<Long> get() = store.revision

    fun getString(key: String): String? {
        val stored = store.string(key)?.takeIf { it.isNotEmpty() } ?: return null
        val blob = decodeBase64(stored) ?: return null
        return cipher.decrypt(blob)?.toString(Charsets.UTF_8)
    }

    /** Şifreleyemezse yazmaz ve false döner. */
    fun putString(key: String, value: String?): Boolean {
        if (value.isNullOrEmpty()) {
            store.remove(key)
            return true
        }
        val blob = cipher.encrypt(value.toByteArray(Charsets.UTF_8)) ?: return false
        store.putString(key, Base64.getEncoder().encodeToString(blob))
        return true
    }

    // --- PSN hesap kimliği: 8 bayt ---
    val accountId: ByteArray?
        get() = getString(K.ACCOUNT_ID)?.let { decodeBase64(it) }?.takeIf { it.size == 8 }

    fun setAccountId(bytes: ByteArray?): Boolean {
        if (bytes != null) require(bytes.size == 8) { "hesap kimliği 8 bayt olmalı" }
        return putString(K.ACCOUNT_ID, bytes?.let { Base64.getEncoder().encodeToString(it) })
    }

    // --- PS5 kaydı ---
    val console: Ps5Registration?
        get() {
            val m = getString(K.CONSOLE)?.let { runCatching { Json.parseObject(it) }.getOrNull() } ?: return null
            val host = m.str("host")?.takeIf { it.isNotBlank() } ?: return null
            val name = m.str("name") ?: return null
            val regist = m.str("registKey")?.let { decodeBase64(it) }?.takeIf { it.isNotEmpty() } ?: return null
            val morning = m.str("morning")?.let { decodeBase64(it) }?.takeIf { it.isNotEmpty() } ?: return null
            return Ps5Registration(host, name, regist, morning)
        }

    fun setConsole(reg: Ps5Registration?): Boolean = putString(K.CONSOLE, reg?.let {
        val b64 = Base64.getEncoder()
        Json.write(linkedMapOf("host" to it.host, "name" to it.name,
            "registKey" to b64.encodeToString(it.registKey), "morning" to b64.encodeToString(it.morning)))
    })

    /** PS5 ağda adres değiştirdi. */
    fun updateConsoleHost(host: String): Boolean {
        val c = console ?: return false
        return if (c.host == host) true else setConsole(c.withHost(host))
    }

    // --- PS5 giriş şifresi: 4 rakam ---
    val loginPasscode: String?
        get() = getString(K.LOGIN_PASSCODE)?.filterNot { it.isWhitespace() }?.takeIf { isPasscode(it) }

    /** Boşluklar atılır; 4 rakam değilse silinir. */
    fun setLoginPasscode(value: String?): Boolean {
        val v = value?.filterNot { it.isWhitespace() }
        return putString(K.LOGIN_PASSCODE, v?.takeIf { isPasscode(it) })
    }

    // --- Xbox jetonu ---
    /** `refresh_token` boşsa null (yeniden giriş). */
    val xboxToken: XboxToken?
        get() {
            val m = getString(K.XBOX_USER_TOKEN)?.let { runCatching { Json.parseObject(it) }.getOrNull() } ?: return null
            return XboxToken(m).takeIf { it.refreshToken.isNotBlank() }
        }

    /**
     * Microsoft jeton yanıtını yazar: alanlar olduğu gibi + `expires_on` = şimdi + `expires_in`.
     * Yanıtta `refresh_token` yoksa öncekini korur.
     */
    fun saveXboxTokenResponse(response: Map<String, Any?>, nowMs: Long = System.currentTimeMillis()): Boolean {
        val m = LinkedHashMap(response)
        if ((m["refresh_token"] as? String).isNullOrBlank()) {
            val old = xboxToken?.refreshToken
            if (!old.isNullOrBlank()) m["refresh_token"] = old
        }
        (m["expires_in"] as? Number)?.let { m["expires_on"] = isoUtc(nowMs + it.toLong() * 1000) }
        return putString(K.XBOX_USER_TOKEN, Json.write(m))
    }

    fun clearXboxToken() = putString(K.XBOX_USER_TOKEN, null)

    // --- Çeviri motoru anahtarları ---
    fun apiKey(engine: Engine): String? =
        if (engine == Engine.FREE) null else getString(K.keyFor(engine))?.trim()?.takeIf { it.isNotEmpty() }

    fun setApiKey(engine: Engine, key: String?): Boolean =
        if (engine == Engine.FREE) true else putString(K.keyFor(engine), key?.trim())

    /** `secrets` dosyasını boşaltır ve iki Keystore takma adını siler. */
    fun clearAll() {
        store.clear()
        cipher.destroyKeys()
    }

    object K {
        const val ACCOUNT_ID = "accountId"
        const val CONSOLE = "console"
        const val LOGIN_PASSCODE = "loginPasscode"
        const val XBOX_USER_TOKEN = "xboxUserToken"
        fun keyFor(engine: Engine) = "key." + engine.name
    }

    companion object {
        const val FILE = "secrets"

        private val ISO = DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.ROOT).withZone(ZoneOffset.UTC)

        fun isoUtc(ms: Long): String = ISO.format(Instant.ofEpochMilli(ms))

        private fun isPasscode(s: String) = s.length == 4 && s.all { it in '0'..'9' }

        internal fun decodeBase64(s: String): ByteArray? =
            runCatching { Base64.getDecoder().decode(s.filterNot { it.isWhitespace() }) }.getOrNull()
    }
}
