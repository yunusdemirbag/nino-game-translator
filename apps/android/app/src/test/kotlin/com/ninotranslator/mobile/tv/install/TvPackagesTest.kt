// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.tv.install

import com.ninotranslator.mobile.data.InstalledTv
import com.ninotranslator.mobile.data.TvBrand
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class TvPackagesTest {
    @Test fun versionCompareIsNumericPerPart() {
        assertTrue(TvVersions.compare("0.10.0", "0.9.9") > 0)
        assertEquals(0, TvVersions.compare("4.0", "4.0.0"))
        assertEquals(0, TvVersions.compare("1.2.beta", "1.2.0")) // sayı olmayan parça 0
        assertTrue(TvVersions.compare("0.1.0-beta.37", "0.1.0-beta.36") > 0)
        assertTrue(TvVersions.compare("4.0.3", "4.0.10") < 0)
        assertEquals(0, TvVersions.compare("x.y", "0.0"))
        assertTrue(TvVersions.phoneIsNewer("4.0.3", null))
        assertTrue(TvVersions.phoneIsNewer("4.0.3", "4.0.2"))
        assertFalse(TvVersions.phoneIsNewer("4.0.3", "4.0.3"))
        assertFalse(TvVersions.phoneIsNewer("4.0.3", "4.1"))
    }

    @Test fun indexParsing() {
        val idx = TvPackageIndex.parse("# yorum\n\napk=nino-androidtv_4.0.2.apk\nipk = com.ninotranslator.tv_4.0.3_all.ipk\n" +
            "wgt=nino-samsung_4.0.3.wgt\nwgt.version=4.0.4\nbozuk satır\n")
        assertEquals(TvPackage("nino-androidtv_4.0.2.apk", "4.0.2"), idx.get(TvBrand.ANDROID_TV))
        assertEquals(TvPackage("com.ninotranslator.tv_4.0.3_all.ipk", "4.0.3"), idx.get(TvBrand.LG))
        assertEquals("4.0.4", idx.get(TvBrand.SAMSUNG)?.version) // config.xml'den yazılan sürüm üstün
        assertNull(TvPackageIndex.parse("").get(TvBrand.LG))
    }

    @Test fun missingPackageIsReported() {
        val src = object : TvPackageSource {
            override val index = TvPackageIndex.parse("ipk=com.ninotranslator.tv_1.0.0_all.ipk")
            override fun open(path: String) = null
        }
        for (b in listOf(TvBrand.SAMSUNG, TvBrand.LG)) {
            try { src.bytes(b); error("hata bekleniyordu") } catch (e: TvInstallException) { assertEquals(TvInstallError.PACKAGE_MISSING, e.error) }
        }
    }

    @Test fun updateCardOnlyWhenTvIsStrictlyOlder() {
        val tv = InstalledTv(TvBrand.LG, "192.168.1.9", 0, "4.0.1")
        val n = TvAppVersionCheck.notice(tv, "4.0.1", "4.0.3")!!
        assertEquals(TvBrand.LG, n.brand); assertEquals("4.0.1", n.tvVersion); assertEquals("4.0.3", n.phoneVersion); assertEquals("192.168.1.9", n.host)
        assertNull(TvAppVersionCheck.notice(tv, "4.0.3", "4.0.3"))
        assertNull(TvAppVersionCheck.notice(tv, "4.1.0", "4.0.3"))
        assertNull(TvAppVersionCheck.notice(tv, null, "4.0.3"))
        assertNull(TvAppVersionCheck.notice(tv, "4.0.1", null))
    }

    @Test fun samsungInfoAndStatus() {
        val json = """{"device":{"name":"[TV] Salon","modelName":"QE65Q80C","developerMode":"1","developerIP":"192.168.1.30"},"name":"x"}"""
        val info = NetworkTvInstaller.parseSamsungInfo(json)!!
        assertEquals("[TV] Salon", info.name); assertEquals("QE65Q80C", info.model)
        assertEquals(TvCandidateStatus.DevOn, NetworkTvInstaller.samsungStatus(info, "192.168.1.30"))
        assertEquals(TvCandidateStatus.DevOtherIp("192.168.1.30"), NetworkTvInstaller.samsungStatus(info, "192.168.1.31"))
        val off = NetworkTvInstaller.parseSamsungInfo("""{"device":{"developerMode":"0","developerIP":"0.0.0.0"}}""")!!
        assertEquals(TvCandidateStatus.DevOff, NetworkTvInstaller.samsungStatus(off, "1.2.3.4"))
        assertNull(off.developerIp)
        assertNull(NetworkTvInstaller.samsungStatus(NetworkTvInstaller.parseSamsungInfo("""{"device":{}}"""), "1.2.3.4"))
        assertEquals(TvCandidateStatus.DevOn, NetworkTvInstaller.samsungStatus(NetworkTvInstaller.parseSamsungInfo("""{"device":{"developerMode":"true"}}"""), null))
    }

    @Test fun safeFileNames() {
        assertEquals("192.168.0.5", TvInstallEnv.safeName(" 192.168.0.5 "))
        assertEquals("tv_local_x", TvInstallEnv.safeName("tv/local x"))
        assertEquals("AB_CD_EF", TvInstallEnv.safeName("AB+CD/EF", allowDot = false))
    }
}
