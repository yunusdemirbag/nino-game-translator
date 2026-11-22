// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.tv.install

import com.ninotranslator.mobile.data.TvBrand
import java.io.File
import java.io.InputStream

/** TV uygulamasının kimlikleri (tv.md 3.5). */
object TvAppIds {
    const val ANDROID_PACKAGE = "com.ninotranslator.tv"
    const val LG_APP = "com.ninotranslator.tv"
    const val SAMSUNG_APP = "NinoTVApps.Nino"
    const val SAMSUNG_PACKAGE = "NinoTVApps"
}

/**
 * Sürüm karşılaştırma (tv.md 3.5): `.` ve `-` ile parçalara bölünür, sayı olmayan ya da eksik parça 0 sayılır,
 * parça parça sayısal karşılaştırılır ("beta.37" gibi sonekler 0'a düşer).
 */
object TvVersions {
    private fun parts(v: String): List<Long> = v.trim().split('.', '-').map { it.toLongOrNull() ?: 0L }

    fun compare(a: String, b: String): Int {
        val x = parts(a); val y = parts(b)
        for (i in 0 until maxOf(x.size, y.size)) {
            val p = x.getOrElse(i) { 0L }; val q = y.getOrElse(i) { 0L }
            if (p != q) return p.compareTo(q)
        }
        return 0
    }

    /** Telefondaki paket TV'dekinden **kesin** yeni mi; TV'de yoksa (null) her zaman kurulur. */
    fun phoneIsNewer(phone: String, tv: String?): Boolean = tv == null || compare(phone, tv) > 0
}

/** Telefonla gelen bir TV paketi. */
data class TvPackage(val fileName: String, val version: String)

/**
 * Gömülü TV paketlerinin dizini (`assets/tv/index.txt`, `anahtar=değer` satırları; `#` ve boş satırlar atlanır).
 * Anahtarlar: `apk`, `ipk`, `wgt` (dosya adı) ve `<tür>.version`.
 */
class TvPackageIndex(private val values: Map<String, String>) {
    fun get(brand: TvBrand): TvPackage? {
        val kind = kindOf(brand)
        val name = values[kind]?.takeIf { it.isNotBlank() } ?: return null
        val version = values["$kind.version"]?.takeIf { it.isNotBlank() } ?: versionFromName(brand, name) ?: return null
        return TvPackage(name, version)
    }

    companion object {
        fun parse(text: String): TvPackageIndex {
            val m = LinkedHashMap<String, String>()
            text.lineSequence().map { it.trim() }.filter { it.isNotEmpty() && !it.startsWith("#") }.forEach { line ->
                val i = line.indexOf('=')
                if (i > 0) m[line.substring(0, i).trim()] = line.substring(i + 1).trim()
            }
            return TvPackageIndex(m)
        }

        fun kindOf(brand: TvBrand) = when (brand) {
            TvBrand.ANDROID_TV -> "apk"
            TvBrand.LG -> "ipk"
            TvBrand.SAMSUNG -> "wgt"
        }

        /** Dosya adındaki sürüm: `com.ninotranslator.tv_<sürüm>_all.ipk` (`_` ile 2. parça), `nino-…_<sürüm>.apk/.wgt`. */
        fun versionFromName(brand: TvBrand, name: String): String? = when (brand) {
            TvBrand.LG -> name.split('_').getOrNull(1)?.takeIf { it.isNotEmpty() }
            else -> name.substringAfterLast('_', "").substringBeforeLast('.').takeIf { it.isNotEmpty() }
        }
    }
}

/** Paketlere erişim (uygulamada assets, testte klasör). */
interface TvPackageSource {
    val index: TvPackageIndex
    fun open(path: String): InputStream?

    /** Paketin geçici dosyaya çıkarılmış kopyası (paket yoksa [TvInstallError.PACKAGE_MISSING]). */
    fun extract(brand: TvBrand, dir: File, name: String): Pair<File, TvPackage> {
        val p = index.get(brand) ?: throw TvInstallException(TvInstallError.PACKAGE_MISSING)
        val input = open("tv/${p.fileName}") ?: throw TvInstallException(TvInstallError.PACKAGE_MISSING)
        dir.mkdirs()
        val out = File(dir, name)
        input.use { i -> out.outputStream().use { o -> i.copyTo(o) } }
        return out to p
    }

    fun bytes(brand: TvBrand): Pair<ByteArray, TvPackage> {
        val p = index.get(brand) ?: throw TvInstallException(TvInstallError.PACKAGE_MISSING)
        val bytes = open("tv/${p.fileName}")?.use { it.readBytes() } ?: throw TvInstallException(TvInstallError.PACKAGE_MISSING)
        return bytes to p
    }
}
