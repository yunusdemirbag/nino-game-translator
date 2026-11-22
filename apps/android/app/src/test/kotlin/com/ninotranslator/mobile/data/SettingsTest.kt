// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.data

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.take
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Locale

class SettingsTest {
    private val prefs = FakePrefs()
    private val s = Settings(prefs) { "en" }

    @Test fun defaults() {
        assertFalse(s.welcomeSeen)
        assertEquals(VideoSource.REMOTE_PLAY, s.videoSource)
        assertEquals(SubtitleTarget.TV, s.target)
        assertEquals(HomeStyle.LIVING_ROOM, s.homeStyle)
        assertEquals(Engine.FREE, s.engine)
        assertTrue(s.packsEnabled && s.sharePool && s.askGame && s.showSpeakerNames)
        assertFalse(s.fastSubtitleDetection)
        assertEquals(100, s.subtitleScale)
        assertTrue(s.tvAutoSize)
        assertEquals(46, s.tvFontSize)
        assertEquals(34, s.phoneTextSize)
        assertEquals(TextColor.WHITE, s.textColor)
        assertEquals(SubtitleFont.CONDENSED, s.subtitleFont)
        assertEquals(72, s.tvBackground)
        assertEquals(TvBackgroundShape.FIT, s.tvBackgroundShape)
        assertTrue(s.stackPrevious && s.tvWatermark && s.keepScreenOn)
        assertEquals(TvDisplayMode.IN_APP, s.tvDisplayMode)
        assertEquals(TvPlacement.COVER, s.tvPlacement)
        assertEquals(7, s.tvBottomPercent)
        assertEquals(Region.DEFAULT, s.region)
        assertEquals(AreaPreset.BOTTOM, s.areaPreset)
        assertTrue(s.extraAreas.isEmpty())
        assertNull(s.xboxConsole)
        assertTrue(s.xboxAudioOnDevice)
        assertNull(s.installedTv)
        assertTrue(s.notifyDisconnect && s.notifyPacks && s.usageData && s.autoReport)
        assertFalse(s.translating)
        assertEquals(0, s.downloadTotal)
        assertNull(s.consoleKind)
        assertEquals(ConsoleKind.PLAYSTATION, s.effectiveConsoleKind)
    }

    @Test fun wrongStoredTypeFallsBackToDefault() {
        val p = FakePrefs(mapOf("subtitleScale" to 120L, "tvApp.port" to "x", "welcomeSeen" to "true", "translating" to 1))
        val st = Settings(p) { "en" }
        assertEquals(100, st.subtitleScale)
        assertFalse(st.welcomeSeen)
        assertFalse(st.translating)
    }

    @Test fun enumsUppercaseUnknownToDefault() {
        s.videoSource = VideoSource.CAPTURE_CARD
        assertEquals("CAPTURE_CARD", prefs.raw()["videoSource"])
        prefs.edit().putString("tvPlacement", "SOMEWHERE").apply()
        assertEquals(TvPlacement.COVER, s.tvPlacement)
        s.subtitleFont = SubtitleFont.ROUNDED
        assertEquals("rounded", prefs.raw()["subtitleFont"])
        prefs.edit().putString("subtitleFont", "MODERN").apply()
        assertEquals(SubtitleFont.MODERN, s.subtitleFont)
        prefs.edit().putString("subtitleFont", "garip").apply()
        assertEquals(SubtitleFont.CONDENSED, s.subtitleFont)
    }

    @Test fun turkishAndArabicDefaultLocaleDoNotBreakCase() {
        val old = Locale.getDefault()
        try {
            for (l in listOf(Locale("tr"), Locale("ar"))) {
                Locale.setDefault(l)
                val p = FakePrefs(mapOf("tvDisplayMode" to "overlay", "engine" to "gemini", "subtitleFont" to "SYSTEM"))
                val st = Settings(p) { "tr" }
                assertEquals(TvDisplayMode.OVERLAY, st.tvDisplayMode)
                assertEquals(Engine.GEMINI, st.engine)
                assertEquals(SubtitleFont.SYSTEM, st.subtitleFont)
                st.targetLanguage = "ID"
                assertEquals("id", p.raw()["targetLanguage"])
                assertEquals("2026-11-22T18:04:05.123Z", Secrets.isoUtc(1795370645123L))
                assertEquals("2026-11-22T18:04:05Z", HistoryStore.formatDate(1795370645999L))
            }
        } finally {
            Locale.setDefault(old)
        }
    }

    @Test fun clamps() {
        s.subtitleScale = 10
        assertEquals(40, prefs.raw()["subtitleScale"])
        s.tvBackground = 150
        assertEquals(100, s.tvBackground)
        s.tvBottomPercent = -3
        assertEquals(0, s.tvBottomPercent)
    }

    @Test fun tvAutoSizeDerivedAndUserScale() {
        prefs.edit().putInt("tvFontSize", 58).apply()
        assertFalse(s.tvAutoSize)
        s.tvAutoSize = true
        assertTrue(s.tvAutoSize)
        s.setSubtitleScaleByUser(130)
        assertFalse(s.tvAutoSize)
        assertEquals(75, s.tvFontPx) // 58 × 1,3 = 75,4
    }

    @Test fun effectiveBackground() {
        s.tvBackground = 50
        assertEquals(100, s.effectiveTvBackground)
        s.tvPlacement = TvPlacement.BELOW
        assertEquals(50, s.effectiveTvBackground)
        assertEquals(50, s.tvBackground)
    }

    @Test fun targetLanguageDerivation() {
        assertEquals("tr", Settings(FakePrefs()) { "de" }.targetLanguage)
        assertEquals("id", Settings(FakePrefs()) { "in" }.targetLanguage)
        assertEquals("tl", Settings(FakePrefs()) { "fil" }.targetLanguage)
        val p = FakePrefs()
        assertEquals("ar", Settings(p) { "ar" }.targetLanguage)
        assertEquals("ar", p.raw()["targetLanguage"])
        assertEquals("tr", Settings(FakePrefs(mapOf("onboarded" to true))) { "ar" }.targetLanguage)
        s.targetLanguage = "tl"
        assertEquals("fil", s.uiLanguageTag)
        s.targetLanguage = "fil"
        assertEquals("tl", s.targetLanguage)
    }

    @Test fun regionAndPresets() {
        prefs.edit().putString("region", "{\"top\":0.5}").apply()
        assertEquals(Region.DEFAULT, s.region)
        prefs.edit().putString("region", "bozuk").apply()
        assertEquals(Region.DEFAULT, s.region)
        prefs.edit().putString("region", "{\"top\":0,\"bottom\":1,\"left\":0.0005,\"right\":1}").apply()
        assertEquals(AreaPreset.FULL, s.areaPreset)
        s.setCustomRegion(Region(0.1, 0.2, 0.3, 0.4))
        assertEquals("CUSTOM", prefs.raw()["areaPreset"])
        s.selectAreaPreset(AreaPreset.CUSTOM)
        assertEquals(Region(0.1, 0.2, 0.3, 0.4), s.region)
        s.selectAreaPreset(AreaPreset.TOP)
        assertEquals(Region.TOP, s.region)
        assertEquals(AreaPreset.TOP, s.areaPreset)
        assertEquals(Region.TOP, Region.parse(prefs.raw()["region"] as String))
    }

    @Test fun extraAreasWriteMaxThree() {
        s.extraAreas = (1..5).map { ExtraArea("id$it", "a$it", Region.NOTIFICATION) }
        assertEquals(3, s.extraAreas.size)
        assertEquals("id3", s.extraAreas.last().id)
    }

    @Test fun consoleKindRules() {
        prefs.edit().putBoolean("consoleAsked", true).apply()
        assertEquals(ConsoleKind.PLAYSTATION, s.consoleKind)
        s.selectConsoleKind(ConsoleKind.XBOX)
        assertEquals(VideoSource.XBOX, s.videoSource)
        assertEquals("XBOX", prefs.raw()["platform"])
        assertEquals(ConsoleKind.XBOX, s.consoleKind)
        s.selectConsoleKind(ConsoleKind.PLAYSTATION)
        assertEquals(VideoSource.REMOTE_PLAY, s.videoSource)
        s.videoSource = VideoSource.CAPTURE_CARD
        s.selectConsoleKind(ConsoleKind.PLAYSTATION)
        assertEquals(VideoSource.CAPTURE_CARD, s.videoSource)
        s.selectConsoleKind(null)
        assertFalse(prefs.contains("platform"))
        assertEquals(false, prefs.raw()["consoleAsked"])
        // Eski sürümde `platform` = XBOX ama kaynak XBOX değil → PlayStation.
        val p = FakePrefs(mapOf("platform" to "XBOX"))
        assertEquals(ConsoleKind.PLAYSTATION, Settings(p) { "en" }.consoleKind)
    }

    @Test fun tvAppWrittenAndRemovedTogether() {
        s.recordTvInstall(InstalledTv(TvBrand.LG, "10.0.0.5", 0, null))
        assertEquals(InstalledTv(TvBrand.LG, "10.0.0.5", 0, null), s.installedTv)
        assertTrue(s.onboarded)
        assertEquals(SubtitleTarget.TV, s.target)
        s.installedTv = null
        assertTrue(Settings.K.TV_APP_KEYS.none { prefs.contains(it) })
        prefs.edit().putString("tvApp.brand", "SAMSUNG").putString("tvApp.host", " ").apply()
        assertNull(s.installedTv)
    }

    @Test fun completeTargetSelection() {
        s.completeTargetSelection(SubtitleTarget.PHONE, "Yatak Odası")
        assertEquals("PHONE", prefs.raw()["target"])
        assertEquals("Yatak Odası", s.tvName)
        assertTrue(s.onboarded)
    }

    @Test fun dynamicKeys() {
        s.setLastGame("PS5-Salon", "GTA 6")
        assertEquals("GTA 6", prefs.raw()["lastGame.PS5-Salon"])
        s.setLastGame("PS5-Salon", null)
        assertNull(s.lastGame("PS5-Salon"))
        // Eski kayıttaki takma ad asıl kimlikle okunur.
        s.setLastGame("PS5-Salon", "grand-theft-auto-vi")
        assertEquals("gta-6", s.lastGame("PS5-Salon"))
        s.setLastGame("PS5-Salon", null)
        s.setLgSessionRenewedAt("TV.Local ", 5L)
        assertEquals(5L, prefs.raw()["tvApp.lgSessionRenewed.tv.local"])
        assertEquals("192.168.0.20", Settings.lastGameConsoleLabel(ConsoleKind.PLAYSTATION, "", "192.168.0.20"))
        assertEquals("Xbox", Settings.lastGameConsoleLabel(ConsoleKind.XBOX, null, null))
    }

    @Test fun xboxConsoleJson() {
        s.xboxConsole = XboxConsole("ABC", "Salon", null, true, "On")
        assertEquals(XboxConsole("ABC", "Salon", null, true, "On"), s.xboxConsole)
        prefs.edit().putString("xboxConsole", "{\"name\":\"kimliksiz\"}").apply()
        assertNull(s.xboxConsole)
        s.xboxConsole = null
        assertFalse(prefs.contains("xboxConsole"))
    }

    @Test fun changesAreObservable() = runBlocking {
        val keys = mutableListOf<String>()
        s.addListener { keys += it }
        s.subtitleScale = 120
        s.selectAreaPreset(AreaPreset.FULL)
        assertEquals(listOf("subtitleScale", "region", "areaPreset"), keys)
        assertTrue("subtitleScale" in Settings.K.TV_APPEARANCE_KEYS)
        assertEquals(120, s.watch { it.subtitleScale }.first())
        assertTrue(s.revision.value >= 2)
    }

    @Test fun watchEmitsOnChange() = runBlocking {
        val seen = mutableListOf<Int>()
        val job = launch(Dispatchers.Unconfined) {
            s.watch { it.tvBackground }.take(2).toList(seen)
        }
        s.tvBackground = 30
        job.join()
        assertEquals(listOf(72, 30), seen)
    }

    @Test fun platformValueNeverRead() {
        prefs.edit().putString("platform", "").apply()
        assertTrue(s.hasPlatformKey)
        assertEquals(ConsoleKind.PLAYSTATION, s.consoleKind)
    }
}
