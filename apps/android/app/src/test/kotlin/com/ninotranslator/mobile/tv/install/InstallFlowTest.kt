// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.tv.install

import com.ninotranslator.mobile.data.TvBrand
import com.ninotranslator.mobile.tv.install.adb.AdbDialect
import com.ninotranslator.mobile.tv.install.adb.AdbKey
import com.ninotranslator.mobile.tv.install.adb.AdbTls
import com.ninotranslator.mobile.tv.install.adb.AndroidTvInstaller
import com.ninotranslator.mobile.tv.install.adb.FakeTv
import com.ninotranslator.mobile.tv.install.samsung.SamsungCertificates
import com.ninotranslator.mobile.tv.install.samsung.SamsungInstaller
import org.bouncycastle.asn1.x500.X500Name
import org.bouncycastle.asn1.x509.SubjectPublicKeyInfo
import org.bouncycastle.cert.X509v3CertificateBuilder
import org.bouncycastle.operator.DefaultDigestAlgorithmIdentifierFinder
import org.bouncycastle.operator.DefaultSignatureAlgorithmIdentifierFinder
import org.bouncycastle.operator.bc.BcRSAContentSignerBuilder
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.math.BigInteger
import java.nio.file.Files
import java.util.Date
import java.util.zip.ZipEntry
import java.util.zip.ZipInputStream
import java.util.zip.ZipOutputStream

/** Kurucuların uçtan uca akışı, yerel döngüdeki sahte TV'lerle (gerçek TV'ye bağlanılmaz). */
class InstallFlowTest {
    private val logLines = ArrayList<String>()

    private fun env(files: Map<String, ByteArray>, index: String): TvInstallEnv = TvInstallEnv(
        Files.createTempDirectory("nb").toFile(), Files.createTempDirectory("cache").toFile(),
        object : TvPackageSource {
            override val index = TvPackageIndex.parse(index)
            override fun open(path: String) = files[path]?.let { ByteArrayInputStream(it) }
        },
        { synchronized(logLines) { logLines += it } },
    )

    @Test fun androidTvInstallsGrantsOverlayAndLaunches() {
        val apk = ByteArray(123_456) { (it * 31).toByte() }
        var installed: String? = null
        val tv = FakeTv(AdbDialect.ADB) { service, input ->
            when {
                service.startsWith("shell:dumpsys package") -> if (installed == null) "Unable to find package\n" else "    versionName=$installed\n"
                service.startsWith("exec:cmd package install -r -S") -> if (input.contentEquals(apk)) { installed = "4.0.3"; "Success\n" } else "Failure [bozuk]\n"
                service.startsWith("shell:appops set") -> ""
                service.startsWith("shell:am start") -> "Starting: Intent { cmp=com.ninotranslator.tv/.MainActivity }\n"
                else -> ""
            }
        }
        tv.use {
            val e = env(mapOf("tv/nino-androidtv_4.0.3.apk" to apk), "apk=nino-androidtv_4.0.3.apk\napk.version=4.0.3")
            val steps = ArrayList<TvInstallStep>()
            val r = AndroidTvInstaller(e).install(TvInstallRequest(TvBrand.ANDROID_TV, "127.0.0.1:${tv.port}"), { steps += it })
            assertEquals(TvInstallResult("4.0.3", alreadyInstalled = false, host = "127.0.0.1", port = tv.port), r)
            assertEquals(listOf(TvInstallStep.CONNECTING, TvInstallStep.READING, TvInstallStep.INSTALLING, TvInstallStep.LAUNCHING), steps)
            assertTrue(tv.commands.contains("shell:appops set com.ninotranslator.tv SYSTEM_ALERT_WINDOW allow"))
            assertTrue(tv.commands.contains("shell:am start -n com.ninotranslator.tv/.MainActivity"))
            assertTrue(File(e.noBackupDir, "adb/adbkey").isFile)
            // İkinci kez: güncel, yalnız izin + açma.
            val r2 = AndroidTvInstaller(e).install(TvInstallRequest(TvBrand.ANDROID_TV, "127.0.0.1:${tv.port}"), {})
            assertTrue(r2.alreadyInstalled)
            assertEquals(2, tv.commands.count { it.startsWith("shell:appops") })
        }
        tv.failure?.let { throw it }
    }

    @Test fun androidTvSignatureMismatchOffersReplaceThenManual() {
        val apk = ByteArray(1000) { 1 }
        val tv = FakeTv(AdbDialect.ADB) { service, _ ->
            when {
                service.startsWith("shell:dumpsys") -> "versionName=0.9.18\ninstallerPackageName=com.android.vending\n"
                service.startsWith("exec:cmd package install") -> "Failure [INSTALL_FAILED_UPDATE_INCOMPATIBLE: imza]\n"
                else -> "Success\n"
            }
        }
        tv.use {
            val e = env(mapOf("tv/nino-androidtv_4.0.3.apk" to apk), "apk=nino-androidtv_4.0.3.apk")
            val first = runCatching { AndroidTvInstaller(e).install(TvInstallRequest(TvBrand.ANDROID_TV, "127.0.0.1:${tv.port}"), {}) }
                .exceptionOrNull() as TvInstallException
            assertEquals(TvInstallError.ANDROID_PLAY_COPY, first.error)
            assertTrue(first.replacePossible)
            assertFalse(tv.commands.any { it.contains("uninstall") }) // kendiliğinden kaldırılmaz
            val second = runCatching {
                AndroidTvInstaller(e).install(TvInstallRequest(TvBrand.ANDROID_TV, "127.0.0.1:${tv.port}", replaceExisting = true), {})
            }.exceptionOrNull() as TvInstallException
            assertEquals(TvInstallError.ANDROID_REMOVE_MANUALLY, second.error)
            assertTrue(tv.commands.contains("shell:pm uninstall com.ninotranslator.tv"))
        }
    }

    @Test fun androidTvUnreachableAndMissingPackage() {
        val e = env(emptyMap(), "")
        val missing = runCatching { AndroidTvInstaller(e).install(TvInstallRequest(TvBrand.ANDROID_TV, "127.0.0.1:1"), {}) }.exceptionOrNull() as TvInstallException
        assertEquals(TvInstallError.PACKAGE_MISSING, missing.error)
        val e2 = env(mapOf("tv/a.apk" to ByteArray(1)), "apk=a.apk\napk.version=1.0")
        val port = java.net.ServerSocket(0).use { it.localPort } // kapalı port
        val un = runCatching { AndroidTvInstaller(e2).install(TvInstallRequest(TvBrand.ANDROID_TV, "127.0.0.1:$port"), {}) }.exceptionOrNull() as TvInstallException
        assertEquals(TvInstallError.ANDROID_UNREACHABLE, un.error)
        val needPair = runCatching {
            AndroidTvInstaller(e2).install(TvInstallRequest(TvBrand.ANDROID_TV, "127.0.0.1:$port", wireless = true, pairCode = "123456", pairAddress = "127.0.0.1"), {})
        }.exceptionOrNull() as TvInstallException
        assertEquals(TvInstallError.ANDROID_NEED_PAIR_PORT, needPair.error)
        assertEquals("10.0.0.2" to 41235, AndroidTvInstaller(e2).parseHostPort(" 10,0,0,2:41235 "))
        assertEquals(null, AndroidTvInstaller(e2).parseHostPort("10.0.0.2:70000"))
        assertTrue(AndroidTvInstaller.parseDumpsys("installerPackageName=com.android.vending versionName=1.2").fromPlay)
        assertTrue(AndroidTvInstaller.overlayFailed("Security exception: not allowed"))
        val space = runCatching { AndroidTvInstaller.checkInstallOutput("Failure [INSTALL_FAILED_INSUFFICIENT_STORAGE]", false, false) }.exceptionOrNull() as TvInstallException
        assertEquals(TvInstallError.SPACE, space.error)
    }

    // --- Samsung ---

    private fun cert(subject: String, issuer: String, signKey: AdbKey, subjectKey: AdbKey): ByteArray {
        val b = X509v3CertificateBuilder(X500Name(issuer), BigInteger.TEN, Date(System.currentTimeMillis() - 60_000),
            Date(System.currentTimeMillis() + 86_400_000L * 30), X500Name(subject), SubjectPublicKeyInfo.getInstance(subjectKey.publicKey.encoded))
        val alg = DefaultSignatureAlgorithmIdentifierFinder().find("SHA256withRSA")
        return b.build(BcRSAContentSignerBuilder(alg, DefaultDigestAlgorithmIdentifierFinder().find(alg)).build(AdbTls.privateParams(signKey))).encoded
    }

    private fun wgt(): ByteArray = ByteArrayOutputStream().also { out ->
        ZipOutputStream(out).use { z -> z.putNextEntry(ZipEntry("config.xml")); z.write("<widget/>".toByteArray()); z.closeEntry() }
    }.toByteArray()

    @Test fun samsungSignsInstallsWithSavedProfileAndRetriesAfterUninstall() {
        var tries = 0
        var version: String? = "4.0.1"
        val tv = FakeTv(AdbDialect.SDB) { service, _ ->
            when {
                service == "capability:" -> "\u0000@platform_version:6.5\nsdk_toolpath:/home/owner/share/tmp/sdk_tools\n"
                service == "shell:0 vd_applist" -> "----\n---- app_tizen_id = NinoTVApps.Nino ----\n---- app_version = $version ----\n----\n"
                service == "shell:0 getduid" -> "DUIDTEST0001\n"
                service.startsWith("shell:0 vd_appinstall NinoTVApps.Nino /home/owner/share/tmp/sdk_tools/nino-") -> {
                    tries++
                    if (tries == 1) "install failed[118, -12] Author certificate not match\n" else { version = "4.0.3"; "spend time for pkgcmd is [900]ms\ninstall completed\n" }
                }
                else -> ""
            }
        }
        tv.use {
            val e = env(mapOf("tv/nino-samsung_4.0.3.wgt" to wgt()), "wgt=nino-samsung_4.0.3.wgt\nwgt.version=4.0.3")
            val k = AdbKey.generate(); val ca = AdbKey.generate()
            SamsungCertificates.saveProfile(e, "DUIDTEST0001", k.privateKey, cert("CN=Nino", "CN=CA", ca, k), cert("CN=TizenSDK", "CN=CA", ca, k), null)
            val steps = ArrayList<TvInstallStep>()
            val r = SamsungInstaller(e, port = tv.port).install(TvInstallRequest(TvBrand.SAMSUNG, "127.0.0.1"), { steps += it })
            assertEquals("4.0.3", r.version); assertFalse(r.alreadyInstalled)
            assertEquals(2, tries)
            assertTrue(steps.contains(TvInstallStep.SIGNING) && steps.contains(TvInstallStep.UNINSTALLING))
            assertFalse(steps.contains(TvInstallStep.SIGNIN)) // kayıtlı profil
            assertTrue(tv.commands.contains("shell:0 vd_appuninstall NinoTVApps"))
            assertTrue(tv.commands.contains("shell:0 was_execute NinoTVApps.Nino"))
            val sent = tv.files.entries.first { it.key.endsWith(".wgt") }
            assertTrue(Regex("/home/owner/share/tmp/sdk_tools/nino-[0-9a-f]{8}\\.wgt").matches(sent.key))
            val names = ArrayList<String>()
            ZipInputStream(ByteArrayInputStream(sent.value)).use { z -> while (true) { names += (z.nextEntry ?: break).name } }
            assertEquals(listOf("author-signature.xml", "signature1.xml", "config.xml"), names)
        }
        tv.failure?.let { throw it }
    }

    @Test fun samsungUpToDateOnlyLaunchesAndRejectedCertificateIsSetAside() {
        val tv = FakeTv(AdbDialect.SDB) { service, _ ->
            when {
                service == "capability:" -> "\u0000\u0010platform_version:5.0\n"
                service == "shell:0 vd_applist" -> "---- app_tizen_id = NinoTVApps.Nino ----\n---- app_version = 4.0.0 ----\n"
                service == "shell:0 getduid" -> "DUIDTEST0002\n"
                service.startsWith("shell:0 vd_appinstall") -> "install failed[118012] Check certificate error : invalid\n"
                else -> ""
            }
        }
        tv.use {
            val e = env(mapOf("tv/nino-samsung_4.0.3.wgt" to wgt()), "wgt=nino-samsung_4.0.3.wgt\nwgt.version=4.0.3")
            val k = AdbKey.generate(); val ca = AdbKey.generate()
            SamsungCertificates.saveProfile(e, "DUIDTEST0002", k.privateKey, cert("CN=Nino", "CN=CA", ca, k), cert("CN=TizenSDK", "CN=CA", ca, k), null)
            val err = runCatching { SamsungInstaller(e, port = tv.port).install(TvInstallRequest(TvBrand.SAMSUNG, "127.0.0.1"), {}) }.exceptionOrNull() as TvInstallException
            assertEquals(TvInstallError.SAMSUNG_REJECTED, err.error)
            assertTrue(err.maintenanceHint)
            assertTrue(File(e.noBackupDir, "samsung").list()!!.any { it.startsWith("DUIDTEST0002.rejected-") })

            val e2 = env(mapOf("tv/nino-samsung_4.0.0.wgt" to wgt()), "wgt=nino-samsung_4.0.0.wgt\nwgt.version=4.0.0")
            val r = SamsungInstaller(e2, port = tv.port).install(TvInstallRequest(TvBrand.SAMSUNG, "127.0.0.1"), {})
            assertTrue(r.alreadyInstalled)
        }
    }

    @Test fun samsungTooOldAndUnreachable() {
        val tv = FakeTv(AdbDialect.SDB) { service, _ -> if (service == "capability:") "\u0000\u0010platform_version:2.3\n" else "" }
        tv.use {
            val e = env(mapOf("tv/w.wgt" to wgt()), "wgt=w.wgt\nwgt.version=4.0.3")
            val old = runCatching { SamsungInstaller(e, port = tv.port).install(TvInstallRequest(TvBrand.SAMSUNG, "127.0.0.1"), {}) }.exceptionOrNull() as TvInstallException
            assertEquals(TvInstallError.SAMSUNG_TOO_OLD, old.error)
            val closed = java.net.ServerSocket(0).use { it.localPort }
            val un = runCatching { SamsungInstaller(e, port = closed).install(TvInstallRequest(TvBrand.SAMSUNG, "127.0.0.1"), {}) }.exceptionOrNull() as TvInstallException
            assertEquals(TvInstallError.SAMSUNG_UNREACHABLE, un.error)
        }
    }

}
