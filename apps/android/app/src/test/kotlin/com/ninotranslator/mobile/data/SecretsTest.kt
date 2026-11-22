// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.data

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Base64
import javax.crypto.Cipher
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

class SecretsTest {
    private val prefs = FakePrefs()
    private val keys = FixedKeySource()
    private val secrets = Secrets(prefs, AesGcmCipher(keys))

    @Test fun storedFormatIsIvCiphertextTagBase64NoWrap() {
        secrets.putString("key.OPENAI", "sk-deneme")
        val stored = prefs.raw()["key.OPENAI"] as String
        assertFalse(stored.contains('\n'))
        val blob = Base64.getDecoder().decode(stored)
        assertEquals(12 + "sk-deneme".length + 16, blob.size)
        // Bağımsız çözme: ilk 12 bayt IV, etiket 128 bit.
        val c = Cipher.getInstance("AES/GCM/NoPadding")
        c.init(Cipher.DECRYPT_MODE, keys.key, GCMParameterSpec(128, blob, 0, 12))
        assertEquals("sk-deneme", String(c.doFinal(blob, 12, blob.size - 12), Charsets.UTF_8))
    }

    @Test fun ivDiffersEachTime() {
        secrets.putString("a", "x")
        val one = prefs.raw()["a"]
        secrets.putString("a", "x")
        assertTrue(one != prefs.raw()["a"])
    }

    @Test fun emptyRemoves() {
        secrets.putString("key.DEEPL", "abc")
        secrets.setApiKey(Engine.DEEPL, "   ")
        assertFalse(prefs.contains("key.DEEPL"))
        secrets.setApiKey(Engine.FREE, "x")
        assertFalse(prefs.contains("key.FREE"))
    }

    @Test fun corruptValuesAreMissingNotDeleted() {
        prefs.edit().putString("console", "!!!").putString("accountId", "AAAA").apply()
        assertNull(secrets.console)
        assertNull(secrets.accountId)
        assertTrue(prefs.contains("console") && prefs.contains("accountId"))
    }

    @Test fun accountIdMustBeEightBytes() {
        secrets.setAccountId(ByteArray(8) { 9 })
        assertArrayEquals(ByteArray(8) { 9 }, secrets.accountId)
        secrets.putString("accountId", Base64.getEncoder().encodeToString(ByteArray(7)))
        assertNull(secrets.accountId)
    }

    @Test fun consoleRoundTripAndHostUpdate() {
        val reg = Ps5Registration("10.0.0.2", "PS5", "abc\u0000".toByteArray(), ByteArray(16) { 1 })
        secrets.setConsole(reg)
        assertEquals(reg, secrets.console)
        assertTrue(secrets.updateConsoleHost("10.0.0.9"))
        assertEquals("10.0.0.9", secrets.console!!.host)
        secrets.putString("console", "{\"host\":\"1.1.1.1\",\"name\":\"x\",\"registKey\":\"YQ==\"}")
        assertNull(secrets.console)
    }

    @Test fun passcode() {
        secrets.setLoginPasscode(" 12 34 ")
        assertEquals("1234", secrets.loginPasscode)
        secrets.setLoginPasscode("12a4")
        assertFalse(prefs.contains("loginPasscode"))
    }

    @Test fun xboxTokenKeepsFieldsAndRefresh() {
        val now = 1795370645123L - 3600_000L
        secrets.saveXboxTokenResponse(mapOf("access_token" to "A1", "refresh_token" to "R1", "expires_in" to 3600L, "scope" to "s"), now)
        val t = secrets.xboxToken!!
        assertEquals("2026-11-22T18:04:05.123Z", t.expiresOn)
        assertEquals("s", t.raw["scope"])
        secrets.saveXboxTokenResponse(mapOf("access_token" to "A2", "expires_in" to 60L), now)
        assertEquals("R1", secrets.xboxToken!!.refreshToken)
        assertEquals("A2", secrets.xboxToken!!.accessToken)
        secrets.putString("xboxUserToken", "{\"access_token\":\"A\",\"refresh_token\":\"\"}")
        assertNull(secrets.xboxToken)
    }

    @Test fun clearAllEmptiesAndDestroysKeys() {
        secrets.setLoginPasscode("1234")
        secrets.clearAll()
        assertTrue(prefs.raw().isEmpty())
        assertTrue(keys.destroyed)
    }

    @Test fun failedEncryptWritesNothing() {
        val s = Secrets(prefs, AesGcmCipher(FixedKeySource(null)))
        assertFalse(s.putString("key.GEMINI", "x"))
        assertFalse(prefs.contains("key.GEMINI"))
    }

    @Test fun changesObservable() {
        val keysSeen = mutableListOf<String>()
        secrets.store.addListener { keysSeen += it }
        secrets.setAccountId(ByteArray(8))
        assertEquals(listOf("accountId"), keysSeen)
    }
}

class KeystoreKeySourceTest {
    private class FakeAliases(vararg present: String) : KeyAliasStore {
        val keys = present.associateWith { SecretKeySpec(ByteArray(32) { 3 }, "AES") as SecretKey }.toMutableMap()
        var created = mutableListOf<String>()
        var fail = false
        override fun contains(alias: String): Boolean { if (fail) error("keystore bozuk"); return alias in keys }
        override fun get(alias: String) = keys[alias]
        override fun create(alias: String): SecretKey = SecretKeySpec(ByteArray(32) { 5 }, "AES").also { keys[alias] = it; created += alias }
        override fun delete(alias: String) { keys.remove(alias) }
    }

    private val legacy = LegacyNames.secretsKeyAlias

    @Test fun currentAliasPreferred() {
        val a = FakeAliases("nino-secrets", legacy)
        assertEquals("nino-secrets", KeystoreKeySource(a).selectAlias())
    }

    @Test fun legacyAliasUsedAsIsAndNoNewKey() {
        val a = FakeAliases(legacy)
        val src = KeystoreKeySource(a)
        assertEquals(legacy, src.selectAlias())
        assertTrue(src.keyForWrite() === a.keys[legacy])
        assertTrue(a.created.isEmpty())
    }

    @Test fun readNeverCreates() {
        val a = FakeAliases()
        assertNull(KeystoreKeySource(a).keyForRead())
        assertTrue(a.created.isEmpty())
        assertTrue(KeystoreKeySource(a).keyForWrite() != null)
        assertEquals(listOf("nino-secrets"), a.created)
    }

    @Test fun keystoreErrorCreatesNothing() {
        val a = FakeAliases().apply { fail = true }
        val src = KeystoreKeySource(a)
        assertNull(src.keyForWrite())
        assertNull(src.keyForRead())
        assertTrue(a.created.isEmpty())
    }

    @Test fun destroyDeletesBothAliases() {
        val a = FakeAliases("nino-secrets", legacy)
        KeystoreKeySource(a).destroy()
        assertTrue(a.keys.isEmpty())
    }

    @Test fun legacyNameStoredEncoded() {
        assertEquals("Y291Y2hzdWJzLXNlY3JldHM=", Base64.getEncoder().encodeToString(legacy.toByteArray()))
        assertTrue(legacy != KeystoreKeySource.CURRENT_ALIAS)
    }
}
