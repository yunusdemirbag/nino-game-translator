// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.data

import org.junit.Assert.assertEquals
import org.junit.Test

class SetupFlowTest {
    private val fresh = SetupState(
        welcomeSeen = true, consoleKind = null, onboarded = false, hasAccount = false, hasConsole = false,
        setupSkipped = false, videoSource = VideoSource.REMOTE_PLAY, hasXboxToken = false, hasXboxConsole = false,
    )

    private fun next(s: SetupState) = SetupFlow.next(s)

    @Test fun welcomeFirst() = assertEquals(SetupStep.WELCOME, next(fresh.copy(welcomeSeen = false, onboarded = true)))

    @Test fun consoleTypeAskedOnFreshInstall() = assertEquals(SetupStep.CONSOLE_TYPE, next(fresh))

    @Test fun consoleTypeNotAskedForOldInstall() {
        assertEquals(SetupStep.PSN_SIGN_IN, next(fresh.copy(setupSkipped = false, hasConsole = true)))
        assertEquals(SetupStep.HOME, next(fresh.copy(onboarded = true, hasAccount = true, hasConsole = true)))
    }

    @Test fun playStationPath() {
        val ps = fresh.copy(consoleKind = ConsoleKind.PLAYSTATION)
        assertEquals(SetupStep.PSN_SIGN_IN, next(ps))
        assertEquals(SetupStep.PS5_PAIR, next(ps.copy(hasAccount = true)))
        assertEquals(SetupStep.TARGET, next(ps.copy(hasAccount = true, hasConsole = true)))
        assertEquals(SetupStep.HOME, next(ps.copy(hasAccount = true, hasConsole = true, onboarded = true)))
    }

    @Test fun skipAndCaptureCardBypassPsn() {
        val ps = fresh.copy(consoleKind = ConsoleKind.PLAYSTATION)
        assertEquals(SetupStep.TARGET, next(ps.copy(setupSkipped = true)))
        assertEquals(SetupStep.TARGET, next(ps.copy(videoSource = VideoSource.CAPTURE_CARD)))
        assertEquals(SetupStep.HOME, next(fresh.copy(setupSkipped = true, onboarded = true)))
    }

    @Test fun xboxPath() {
        val x = fresh.copy(consoleKind = ConsoleKind.XBOX, videoSource = VideoSource.XBOX)
        assertEquals(SetupStep.MICROSOFT_SIGN_IN, next(x))
        assertEquals(SetupStep.XBOX_PICK, next(x.copy(hasXboxToken = true)))
        assertEquals(SetupStep.TARGET, next(x.copy(hasXboxToken = true, hasXboxConsole = true)))
        assertEquals(SetupStep.HOME, next(x.copy(setupSkipped = true, onboarded = true)))
    }

    @Test fun pairingFlow() {
        assertEquals(SetupStep.PSN_SIGN_IN, SetupFlow.pairingStep(null, false, false))
        assertEquals(SetupStep.PS5_PAIR, SetupFlow.pairingStep(ConsoleKind.PLAYSTATION, true, false))
        assertEquals(SetupStep.MICROSOFT_SIGN_IN, SetupFlow.pairingStep(ConsoleKind.XBOX, true, false))
        assertEquals(SetupStep.XBOX_PICK, SetupFlow.pairingStep(ConsoleKind.XBOX, false, true))
    }

    @Test fun fromStoresUsesValidity() {
        val settings = Settings(FakePrefs(mapOf("welcomeSeen" to true, "consoleAsked" to true))) { "tr" }
        val secPrefs = FakePrefs()
        val secrets = Secrets(secPrefs, AesGcmCipher(FixedKeySource()))
        secrets.putString("accountId", "AAAA") // 3 bayt: geçersiz
        assertEquals(SetupStep.PSN_SIGN_IN, SetupFlow.next(settings, secrets))
        secrets.setAccountId(ByteArray(8))
        assertEquals(SetupStep.PS5_PAIR, SetupFlow.next(settings, secrets))
    }
}
