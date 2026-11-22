// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.ui.theme

import androidx.compose.ui.graphics.Color

/** Renk belirteçleri (ekranlar-1 §1.1). Yalnız açık tema vardır. */
object NinoColors {
    /** Pencere zemini. */
    val Background = Color(0xFFEEF3FB)
    /** Karo zemini (beyaz %85). */
    val Surface = Color.White.copy(alpha = 0.85f)
    /** Segment rayı, kod kutuları, tur kartı, açılır dil satırı, iletişim kutusu. */
    val Surface2 = Color(0xFFE6EDF8)
    /** İkincil düğme, simge düğmesi, metin alanı. */
    val Raised = Color.White
    /** Karo kenarı, ayraçlar (beyaz %75). */
    val Border = Color.White.copy(alpha = 0.75f)
    /** Düğme ve alan kenarları. */
    val BorderStrong = Color(0xFFD3DEEF)
    /** Ana yazı ("mürekkep"). */
    val Ink = Color(0xFF0A1430)
    /** Açıklamalar. */
    val InkSecondary = Color(0xFF55607A)
    val Accent = Color(0xFF0070D1)
    val AccentLight = Color(0xFF1A86E8)
    /** Metin düğmeleri, adım satırı. */
    val AccentText = Color(0xFF0058A8)
    val Navy = Color(0xFF003085)
    /** Karo simgelerinin daire zemini. */
    val AccentSoft = Color(0xFFDDEBFA)
    /** Paket etiketi yazısı, gölge tonu. */
    val PackDark = Color(0xFF00205B)
    val PackSoft = Color(0xFFE2E8F5)
    val Success = Color(0xFF1E6B45)
    val Warning = Color(0xFF9A4A08)
    val Danger = Color(0xFFB3261E)
    val DangerBackground = Color(0xFFFBE4E2)
    /** Koyu sahne kartı degradesi. */
    val StageTop = Color(0xFF151E36)
    val StageBottom = Color(0xFF06080F)
    /** "Canlı" noktası, "Ücretsiz" etiketi. */
    val LiveGreen = Color(0xFF30C578)
    val FlagRed = Color(0xFFE30A17)
    val FlagRedDark = Color(0xFFA80514)

    /** Birincil düğme degradesi. */
    val PrimaryTop = Color(0xFF1B2747)

    /** Ekran zemini degradesi (§1.1). */
    val ScreenTop = Color(0xFFF7FAFF)
    val ScreenBottom = Color(0xFFE3ECFA)

    /** Telefon altyazısının sarı rengi. */
    val SubtitleYellow = Color(0xFFFFD54A)
}
