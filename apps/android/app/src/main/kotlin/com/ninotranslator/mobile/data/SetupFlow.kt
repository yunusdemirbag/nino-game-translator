// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.data

/** Kurulum akışının ekranları. */
enum class SetupStep { WELCOME, CONSOLE_TYPE, MICROSOFT_SIGN_IN, XBOX_PICK, PSN_SIGN_IN, PS5_PAIR, TARGET, HOME }

/**
 * Kurulum kararı için gereken durum. "has…" alanları geçerliliği anlatır (8 baytlık hesap kimliği, dört alanı tam PS5
 * kaydı, `refresh_token`'ı dolu Xbox jetonu), yalnız anahtarın varlığını değil.
 */
data class SetupState(
    val welcomeSeen: Boolean,
    val consoleKind: ConsoleKind?,
    val onboarded: Boolean,
    val hasAccount: Boolean,
    val hasConsole: Boolean,
    val setupSkipped: Boolean,
    val videoSource: VideoSource,
    val hasXboxToken: Boolean,
    val hasXboxConsole: Boolean,
)

/** Sıradaki ekran kararı (§5.2, ekranlar-1 §3). Saf işlevler. */
object SetupFlow {
    fun next(s: SetupState): SetupStep {
        if (!s.welcomeSeen) return SetupStep.WELCOME
        if (s.consoleKind == null && !s.onboarded && !s.hasAccount && !s.hasConsole && !s.setupSkipped) {
            return SetupStep.CONSOLE_TYPE
        }
        if (s.consoleKind == ConsoleKind.XBOX) {
            if (!s.hasXboxToken && !s.setupSkipped) return SetupStep.MICROSOFT_SIGN_IN
            if (!s.hasXboxConsole && !s.setupSkipped) return SetupStep.XBOX_PICK
        } else {
            val needsPsn = !s.setupSkipped && s.videoSource != VideoSource.CAPTURE_CARD
            if (!s.hasAccount && needsPsn) return SetupStep.PSN_SIGN_IN
            if (!s.hasConsole && needsPsn) return SetupStep.PS5_PAIR
        }
        return if (s.onboarded) SetupStep.HOME else SetupStep.TARGET
    }

    /** Ana ekrandaki "eşleme akışı" (ekranlar-1 §3.4). */
    fun pairingStep(kind: ConsoleKind?, hasAccount: Boolean, hasXboxToken: Boolean): SetupStep =
        if (kind == ConsoleKind.XBOX) {
            if (hasXboxToken) SetupStep.XBOX_PICK else SetupStep.MICROSOFT_SIGN_IN
        } else {
            if (hasAccount) SetupStep.PS5_PAIR else SetupStep.PSN_SIGN_IN
        }

    /** Ayar ve gizli değerlerden durum. */
    fun stateOf(settings: Settings, secrets: Secrets) = SetupState(
        welcomeSeen = settings.welcomeSeen,
        consoleKind = settings.consoleKind,
        onboarded = settings.onboarded,
        hasAccount = secrets.accountId != null,
        hasConsole = secrets.console != null,
        setupSkipped = settings.setupSkipped,
        videoSource = settings.videoSource,
        hasXboxToken = secrets.xboxToken != null,
        hasXboxConsole = settings.xboxConsole != null,
    )

    fun next(settings: Settings, secrets: Secrets): SetupStep = next(stateOf(settings, secrets))

    /** Xbox'a hazır: seçili Xbox ve geçerli Microsoft jetonu (§5.1). */
    fun xboxReady(settings: Settings, secrets: Secrets) = settings.xboxConsole != null && secrets.xboxToken != null
}
