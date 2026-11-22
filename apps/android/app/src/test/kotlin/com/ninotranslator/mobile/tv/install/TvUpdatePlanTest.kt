// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.tv.install

import com.ninotranslator.core.link.ConnectedDisplay
import com.ninotranslator.core.link.DisplayKind
import com.ninotranslator.mobile.data.InstalledTv
import com.ninotranslator.mobile.data.TvBrand
import com.ninotranslator.mobile.tv.TvUpdateNotice
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Güncelleme kartının kararı: hangi TV, hangi sürüm, hangi akış. */
class TvUpdatePlanTest {
    private val phone: (TvBrand) -> String? = { mapOf(TvBrand.ANDROID_TV to "4.5.0", TvBrand.LG to "4.5.0", TvBrand.SAMSUNG to "4.5.0")[it] }

    private fun display(kind: DisplayKind, address: String, model: String? = null, version: String? = null, name: String = address) =
        ConnectedDisplay("k-$address", name, address, kind, model, version)

    @Test fun brandFromKindModelAndSavedTv() {
        assertEquals(TvBrand.ANDROID_TV, TvUpdatePlan.brandOf(display(DisplayKind.ANDROID_TV, "10.0.0.2"), null))
        assertEquals(TvBrand.LG, TvUpdatePlan.brandOf(display(DisplayKind.WEB_TV, "10.0.0.3", "LG OLED55C3"), null))
        assertEquals(TvBrand.SAMSUNG, TvUpdatePlan.brandOf(display(DisplayKind.WEB_TV, "10.0.0.4", "Samsung QE65Q80C"), null))
        assertEquals(TvBrand.SAMSUNG, TvUpdatePlan.brandOf(display(DisplayKind.LEGACY, "10.0.0.5", "Samsung UE50"), null))
        assertNull(TvUpdatePlan.brandOf(display(DisplayKind.WEB_TV, "10.0.0.6", "Philips 55"), null))
        assertNull(TvUpdatePlan.brandOf(display(DisplayKind.WEB_TV, "10.0.0.6"), null))
        // "LGX" gibi bir model LG sayılmaz; kayıtlı TV'nin adresi markayı verir.
        assertNull(TvUpdatePlan.brandOf(display(DisplayKind.WEB_TV, "10.0.0.7", "LGX 1"), null))
        assertEquals(TvBrand.LG, TvUpdatePlan.brandOf(display(DisplayKind.WEB_TV, "10.0.0.7"), InstalledTv(TvBrand.LG, "10.0.0.7")))
    }

    @Test fun versionCompareDecidesNotice() {
        assertEquals("4.4.2", TvUpdatePlan.displayNotice(display(DisplayKind.ANDROID_TV, "10.0.0.2", version = "4.4.2"), null, phone)!!.tvVersion)
        assertNull(TvUpdatePlan.displayNotice(display(DisplayKind.ANDROID_TV, "10.0.0.2", version = "4.5.0"), null, phone))
        assertNull(TvUpdatePlan.displayNotice(display(DisplayKind.ANDROID_TV, "10.0.0.2", version = "4.10.0"), null, phone))
        assertNotNullNotice(TvUpdatePlan.displayNotice(display(DisplayKind.ANDROID_TV, "10.0.0.2", version = "0.9.9"), null, phone))
        // Yeni protokolde sürüm bildirmeyen TV için karar verilmez.
        assertNull(TvUpdatePlan.displayNotice(display(DisplayKind.WEB_TV, "10.0.0.3", "LG 55"), null, phone))
        // Telefonda o markanın paketi yoksa kart çıkmaz.
        assertNull(TvUpdatePlan.displayNotice(display(DisplayKind.ANDROID_TV, "10.0.0.2", version = "1.0"), null) { null })
    }

    private fun assertNotNullNotice(n: TvUpdateNotice?) = assertTrue(n != null)

    @Test fun legacyTvWithoutVersionIsOld() {
        val n = TvUpdatePlan.displayNotice(display(DisplayKind.LEGACY, "10.0.0.5:8787", "LG 43UQ"), null, phone)!!
        assertEquals(TvBrand.LG, n.brand); assertNull(n.tvVersion); assertEquals("10.0.0.5", n.host); assertFalse(n.saved)
        // Eski TV sürüm bildirdiyse karşılaştırılır.
        assertNull(TvUpdatePlan.displayNotice(display(DisplayKind.LEGACY, "10.0.0.5", "LG 43UQ", "4.5.0"), null, phone))
    }

    @Test fun savedTvComesFirst() {
        val saved = InstalledTv(TvBrand.SAMSUNG, "10.0.0.9", version = "4.0.0")
        val other = display(DisplayKind.ANDROID_TV, "10.0.0.2", version = "4.0.0")
        val d = TvUpdatePlan.decide(saved, "4.0.0", listOf(other), phone)
        assertEquals("10.0.0.9", d.notice!!.host); assertTrue(d.notice!!.saved); assertFalse(d.keep)
    }

    @Test fun savedTvUnreachableKeepsCard() {
        val saved = InstalledTv(TvBrand.LG, "10.0.0.9")
        assertTrue(TvUpdatePlan.decide(saved, null, emptyList(), phone).keep)
        // Kayıtlı TV ulaşılamaz ama bağlıyken eski sürüm bildiriyor: kart onun için, kayıtlı sayılır.
        val d = TvUpdatePlan.decide(saved, null, listOf(display(DisplayKind.WEB_TV, "10.0.0.9", "LG 55", "4.1.0")), phone)
        assertEquals("4.1.0", d.notice!!.tvVersion); assertTrue(d.notice!!.saved)
        // Bağlıyken güncel sürüm bildiriyorsa kart kalkar.
        val up = TvUpdatePlan.decide(saved, null, listOf(display(DisplayKind.WEB_TV, "10.0.0.9", "LG 55", "4.5.0")), phone)
        assertNull(up.notice); assertFalse(up.keep)
    }

    @Test fun connectedTvWithoutSavedTv() {
        val d = TvUpdatePlan.decide(null, null, listOf(display(DisplayKind.ANDROID_TV, "10.0.0.2", version = "4.0.0", name = "Salon TV")), phone)
        val n = d.notice!!
        assertEquals(TvBrand.ANDROID_TV, n.brand); assertFalse(n.saved); assertEquals("Salon TV", n.name)
        assertNull(TvUpdatePlan.decide(null, null, emptyList(), phone).notice)
        assertFalse(TvUpdatePlan.decide(null, null, emptyList(), phone).keep)
        // Kayıtlı TV güncel: başka bağlı eski TV için kart çıkar.
        val d2 = TvUpdatePlan.decide(InstalledTv(TvBrand.SAMSUNG, "10.0.0.9"), "4.5.0", listOf(display(DisplayKind.ANDROID_TV, "10.0.0.2", version = "4.0.0")), phone)
        assertEquals("10.0.0.2", d2.notice!!.host)
    }

    @Test fun actionPerBrand() {
        fun n(brand: TvBrand, saved: Boolean = true, port: Int = 0) = TvUpdateNotice(brand, "4.0.0", "4.5.0", "10.0.0.9", port, saved)
        assertEquals(TvUpdateAction.Direct(TvInstallRequest(TvBrand.SAMSUNG, "10.0.0.9")), TvUpdatePlan.action(n(TvBrand.SAMSUNG), false))
        assertEquals(TvUpdateAction.Direct(TvInstallRequest(TvBrand.LG, "10.0.0.9")), TvUpdatePlan.action(n(TvBrand.LG), true))
        assertEquals(TvUpdateAction.OpenScreen(TvBrand.LG, "10.0.0.9"), TvUpdatePlan.action(n(TvBrand.LG), false))
        assertEquals("10.0.0.9:5555", (TvUpdatePlan.action(n(TvBrand.ANDROID_TV), false) as TvUpdateAction.Direct).request.address)
        assertEquals("10.0.0.9:37123", (TvUpdatePlan.action(n(TvBrand.ANDROID_TV, port = 37123), false) as TvUpdateAction.Direct).request.address)
        assertEquals(TvUpdateAction.OpenScreen(TvBrand.ANDROID_TV, "10.0.0.9"), TvUpdatePlan.action(n(TvBrand.ANDROID_TV, saved = false), false))
    }

    @Test fun errorsThatNeedTheScreen() {
        assertTrue(TvUpdatePlan.needsScreen(TvInstallException(TvInstallError.LG_PASSPHRASE)))
        assertTrue(TvUpdatePlan.needsScreen(TvInstallException(TvInstallError.ANDROID_NOT_PAIRED)))
        assertTrue(TvUpdatePlan.needsScreen(TvInstallException(TvInstallError.ANDROID_PLAY_COPY)))
        assertTrue(TvUpdatePlan.needsScreen(TvInstallException(TvInstallError.SAMSUNG_LOGIN)))
        assertFalse(TvUpdatePlan.needsScreen(TvInstallException(TvInstallError.CONNECTION)))
        assertFalse(TvUpdatePlan.needsScreen(TvInstallException(TvInstallError.SPACE)))
    }

    @Test fun cardPhaseFollowsSessionOfSameTv() {
        val ok = TvInstallResult("4.5.0", false, "10.0.0.9")
        assertEquals(TvUpdateCardPhase.Offer, TvUpdatePlan.phase("10.0.0.9", null, false, null, null, null))
        assertEquals(TvUpdateCardPhase.Offer, TvUpdatePlan.phase("10.0.0.9", "10.0.0.8", true, null, null, null))
        assertEquals(TvUpdateCardPhase.Running(TvInstallStep.INSTALLING),
            TvUpdatePlan.phase("10.0.0.9", "10.0.0.9:5555", true, TvInstallStep.INSTALLING, null, null))
        assertEquals(TvUpdateCardPhase.Done("4.5.0", false), TvUpdatePlan.phase("10.0.0.9", "10.0.0.9", false, null, ok, null))
        val e = TvInstallException(TvInstallError.LG_PASSPHRASE)
        assertEquals(TvUpdateCardPhase.Failed(e, true), TvUpdatePlan.phase("10.0.0.9", "10.0.0.9", false, null, null, e))
        assertEquals("fe80::1", TvUpdatePlan.hostOf("fe80::1"))
    }
}
