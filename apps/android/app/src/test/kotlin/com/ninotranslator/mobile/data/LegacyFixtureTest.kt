// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.data

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/** Eski uygulamanın bıraktığı biçimdeki prefs/secrets/history dosyaları aynen okunmalı. */
class LegacyFixtureTest {
    private val prefs = FakePrefs.fixture("settings")
    private val settings = Settings(prefs) { "en" }

    @Test fun settingsFromLegacyInstall() {
        assertTrue(settings.welcomeSeen)
        assertTrue(settings.onboarded)
        // Eski `homeStyle` okunmaz.
        assertEquals(HomeStyle.LIVING_ROOM, settings.homeStyle)
        assertEquals(SubtitleTarget.PHONE, settings.target)
        assertEquals("Salon TV", settings.tvName)
        assertEquals(Engine.DEEPL, settings.engine)
        assertEquals(setOf("pool-genel", "rdr2"), settings.disabledPacks)
        assertFalse(settings.sharePool)
        assertEquals(160, settings.subtitleScale)
        assertEquals(SubtitleFont.CONDENSED, settings.subtitleFont)
        assertEquals(TextColor.YELLOW, settings.textColor)
        assertEquals(40, settings.tvBackground)
        assertEquals(100, settings.effectiveTvBackground)
        assertEquals(85, settings.tvBottomPercent)
        assertEquals(74, settings.tvFontPx)
        // tvAutoSize yok: ölçek ≠ 100 → kapalı.
        assertFalse(settings.tvAutoSize)
        // areaPreset yok: TOP bölgesinden türetilir.
        assertEquals(Region.TOP, settings.region)
        assertEquals(AreaPreset.TOP, settings.areaPreset)
        assertEquals("Red Dead Redemption 2", settings.lastGame("PS5-Salon"))
        assertEquals(1234, settings.downloadTotal)
        assertEquals(3_600_000L, settings.lastSessionMs)
        assertEquals(1763800000000L, settings.lgSessionRenewedAt(" 192.168.0.50 "))
    }

    @Test fun extraAreasLimitAndDefaults() {
        val areas = settings.extraAreas
        assertEquals(3, areas.size)
        assertTrue(areas[0].id.length >= 32)
        assertEquals(areas[0].id, settings.extraAreas[0].id) // üretilen kimlik kalıcı
        assertEquals(Region.QUEST, areas[0].region)
        assertFalse(areas[0].enabled)
        assertEquals(Region.PHONE, areas[1].region)
        assertTrue(areas[1].enabled)
    }

    @Test fun consoleKindAndTv() {
        assertEquals(ConsoleKind.PLAYSTATION, settings.consoleKind)
        assertEquals(XboxConsole("F4000", "Xbox Salon", "XboxSeriesX", true, "On"), settings.xboxConsole)
        assertEquals(InstalledTv(TvBrand.ANDROID_TV, "192.168.0.110", 5555, "0.2.6"), settings.installedTv)
    }

    @Test fun targetLanguageMissingOnOnboardedIsTurkishAndWritten() {
        assertFalse(prefs.contains("targetLanguage"))
        assertEquals("tr", settings.targetLanguage)
        assertEquals("tr", prefs.raw()["targetLanguage"])
    }

    @Test fun translatingFlagConsumedAtStartup() {
        assertTrue(settings.consumeTranslatingFlag())
        assertEquals(false, prefs.raw()["translating"])
        assertFalse(settings.consumeTranslatingFlag())
    }

    @Test fun secretsFromLegacyInstall() {
        val secrets = Secrets(FakePrefs.fixture("secrets"), AesGcmCipher(FixedKeySource()))
        assertArrayEquals(byteArrayOf(1, 2, 3, 4, 5, 6, 7, 8), secrets.accountId)
        val c = secrets.console!!
        assertEquals("192.168.0.20", c.host)
        assertEquals("PS5-Salon", c.name)
        assertEquals("61ab1234", String(c.registKey, Charsets.US_ASCII).trimEnd('\u0000'))
        assertArrayEquals(ByteArray(16) { it.toByte() }, c.morning)
        assertEquals("1234", secrets.loginPasscode)
        assertEquals("abcd-1234:fx", secrets.apiKey(Engine.DEEPL))
        assertEquals("çşğİ-anahtar", secrets.apiKey(Engine.GEMINI))
        assertNull(secrets.apiKey(Engine.OPENAI))
        assertNull(secrets.apiKey(Engine.CLAUDE))
        val t = secrets.xboxToken!!
        assertEquals("AT", t.accessToken)
        assertEquals("RT", t.refreshToken)
        assertEquals("u1", t.raw["user_id"])
        assertEquals(java.time.Instant.parse("2026-11-22T18:04:05.123Z").toEpochMilli(), t.expiresAtMs)
    }

    @Test fun secretsWithWrongKeyAreMissingButKept() {
        val prefs = FakePrefs.fixture("secrets")
        val wrong = javax.crypto.spec.SecretKeySpec(ByteArray(32) { 7 }, "AES")
        val secrets = Secrets(prefs, AesGcmCipher(FixedKeySource(wrong)))
        assertNull(secrets.accountId)
        assertNull(secrets.console)
        assertTrue(prefs.contains("accountId"))
    }

    @Test fun setupFlowForLegacyInstallGoesHome() {
        val secrets = Secrets(FakePrefs.fixture("secrets"), AesGcmCipher(FixedKeySource()))
        assertEquals(SetupStep.HOME, SetupFlow.next(settings, secrets))
    }

    @Test fun historyFromLegacyFile() {
        val list = HistoryStore.parse(resourceText("legacy/files/history.json"))
        assertEquals(200, list.size)
        assertEquals(205, list[0].id)
        assertEquals(500, list[0].source.length)
        assertEquals("Çeviri 204", list[1].translation)
        assertEquals(HistoryOrigin.ENGINE, list[2].origin) // "pool" → engine
        assertEquals(HistoryOrigin.PACK, list.first { it.id == 204 }.origin)
        assertEquals("2026-11-09T10:24:05Z", HistoryStore.formatDate(list.first { it.id == 204 }.dateMs))
    }

    @Test fun installIdFallsBackToReport() {
        val dir = tempDir()
        val state = File(dir, "pool/state.json").apply { parentFile.mkdirs(); writeText(resourceText("legacy/files/pool/state.json")) }
        val id = InstallIdentity(dir, FakePrefs.fixture("report")).id
        assertEquals("3f2b8c1e-0d4a-4e5b-9a7c-1b2c3d4e5f60", id)
    }
}
