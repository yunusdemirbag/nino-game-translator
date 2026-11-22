// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.tv.install

import com.ninotranslator.core.link.ConnectedDisplay
import com.ninotranslator.core.link.DisplayKind
import com.ninotranslator.mobile.data.InstalledTv
import com.ninotranslator.mobile.data.TvBrand
import com.ninotranslator.mobile.tv.TvUpdateNotice

/** Sürüm denetiminin kararı: [keep] true ise kart olduğu gibi kalır (kayıtlı TV'ye ulaşılamadı, başka bilgi yok). */
data class TvUpdateDecision(val notice: TvUpdateNotice?, val keep: Boolean = false)

/** Karttaki "Yeni Sürümü Kur" düğmesi ne yapacak. */
sealed interface TvUpdateAction {
    /** Kayıtlı TV: kurucu hemen çalışır, ilerleme kartta görünür. */
    data class Direct(val request: TvInstallRequest) : TvUpdateAction
    /** Ek bilgi gerekiyor ya da TV kayıtlı değil: kurulum ekranı o TV seçili açılır. */
    data class OpenScreen(val brand: TvBrand, val host: String) : TvUpdateAction
}

/** Kartın o anki görünümü. */
sealed interface TvUpdateCardPhase {
    data object Offer : TvUpdateCardPhase
    data class Running(val step: TvInstallStep?) : TvUpdateCardPhase
    data class Done(val version: String, val alreadyInstalled: Boolean) : TvUpdateCardPhase
    /** [needsScreen]: kullanıcıdan bilgi gerekiyor, devamı kurulum ekranında. */
    data class Failed(val error: TvInstallException, val needsScreen: Boolean) : TvUpdateCardPhase
}

/**
 * TV güncelleme kartının saf kuralları: hangi TV için kart çıkar, düğme hangi akışı açar, kart ne gösterir.
 * Kaynaklar: kayıtlı TV'nin sessiz denetimi (tv.md 3.4) ve bağlanan her Nino TV'nin bildirdiği sürüm (Android TV
 * `welcome.appVersion`, web TV `hello.appVersion`, eski 8787 TV'nin `?app=` değeri).
 */
object TvUpdatePlan {

    /** "ip:port" ise yalnız ip (IPv6 dokunulmaz). */
    fun hostOf(address: String): String = address.trim().let { if (it.count { c -> c == ':' } == 1) it.substringBefore(':') else it }

    /** Bağlı TV'nin markası: tür, kayıtlı TV'nin adresi ya da modelin başındaki ad ("LG …", "Samsung …"). Bilinmiyorsa null. */
    fun brandOf(display: ConnectedDisplay, installed: InstalledTv?): TvBrand? {
        if (display.kind == DisplayKind.ANDROID_TV) return TvBrand.ANDROID_TV
        val host = hostOf(display.address)
        if (installed != null && installed.host == host) return installed.brand
        val model = display.model?.lowercase().orEmpty()
        val words = model.split(' ', '-', '_', '(', ')').filter { it.isNotEmpty() }
        return when {
            words.firstOrNull() == "lg" || "webos" in model -> TvBrand.LG
            "samsung" in model || "tizen" in model -> TvBrand.SAMSUNG
            display.kind == DisplayKind.LEGACY && ("android" in model || "google" in model) -> TvBrand.ANDROID_TV
            else -> null
        }
    }

    /** Bağlı bir TV için kart verisi; TV güncelse ya da marka/sürüm bilinmiyorsa null. Eski 8787 TV sürüm vermezse eski sayılır. */
    fun displayNotice(display: ConnectedDisplay, installed: InstalledTv?, phoneVersion: (TvBrand) -> String?): TvUpdateNotice? {
        val brand = brandOf(display, installed) ?: return null
        val phone = phoneVersion(brand) ?: return null
        val tv = display.appVersion?.trim()?.takeIf { it.isNotEmpty() }
        if (tv == null && display.kind != DisplayKind.LEGACY) return null
        if (tv != null && !TvVersions.phoneIsNewer(phone, tv)) return null
        val host = hostOf(display.address)
        val saved = installed?.takeIf { it.host == host && it.brand == brand }
        return TvUpdateNotice(brand, tv, phone, host, port = saved?.port ?: 0, saved = saved != null, name = display.name.takeIf { it != display.address })
    }

    /**
     * Kart kararı. Önce kayıtlı TV ([installedVersion] onun sessiz denetimle okunan sürümü, ulaşılamadıysa null), sonra
     * bağlı TV'ler. Bağlı TV'nin bildirdiği sürüm kayıtlı TV için de geçerlidir.
     */
    fun decide(
        installed: InstalledTv?,
        installedVersion: String?,
        displays: List<ConnectedDisplay>,
        phoneVersion: (TvBrand) -> String?,
    ): TvUpdateDecision {
        val fromDisplays = displays.mapNotNull { displayNotice(it, installed, phoneVersion) }
        if (installed != null) {
            val phone = phoneVersion(installed.brand)
            val reported = displays.firstOrNull { hostOf(it.address) == installed.host && brandOf(it, installed) == installed.brand }
            if (installedVersion != null && phone != null && TvVersions.compare(phone, installedVersion) > 0) {
                return TvUpdateDecision(TvUpdateNotice(installed.brand, installedVersion, phone, installed.host, installed.port, saved = true))
            }
            fromDisplays.firstOrNull { it.host == installed.host }?.let { return TvUpdateDecision(it) }
            if (installedVersion == null && reported == null && fromDisplays.isEmpty()) return TvUpdateDecision(null, keep = true)
        }
        return TvUpdateDecision(fromDisplays.firstOrNull())
    }

    /**
     * Düğmenin akışı. Kayıtlı TV'de kurucu doğrudan çalışır; LG'de kayıtlı anahtar yoksa Passphrase gerekir, ekran açılır.
     * Samsung girişi kurulum sırasında istenirse arayüz giriş ekranına geçer.
     */
    fun action(notice: TvUpdateNotice, hasLgKey: Boolean): TvUpdateAction {
        if (!notice.saved || (notice.brand == TvBrand.LG && !hasLgKey)) return TvUpdateAction.OpenScreen(notice.brand, notice.host)
        val address = when (notice.brand) {
            TvBrand.ANDROID_TV -> "${notice.host}:${notice.port.takeIf { it > 0 } ?: 5555}"
            else -> notice.host
        }
        return TvUpdateAction.Direct(TvInstallRequest(notice.brand, address, tvName = notice.name))
    }

    /** Kullanıcıdan bilgi isteyen hatalar: devamı kurulum ekranında (eşleme kodu, Passphrase, Samsung girişi, kopyayı kaldırma). */
    fun needsScreen(e: TvInstallException): Boolean = e.replacePossible || e.error in setOf(
        TvInstallError.LG_PASSPHRASE, TvInstallError.LG_KEY_REFUSED,
        TvInstallError.ANDROID_NOT_PAIRED, TvInstallError.ANDROID_PAIRING, TvInstallError.ANDROID_NOT_APPROVED,
        TvInstallError.ANDROID_NEED_PORT, TvInstallError.ANDROID_NEED_PAIR_PORT, TvInstallError.ANDROID_REMOVE_MANUALLY,
        TvInstallError.SAMSUNG_LOGIN, TvInstallError.SAMSUNG_CERTIFICATE, TvInstallError.SAMSUNG_MISMATCH,
    )

    /** Kartın görünümü; kurulum bu kartın TV'si için değilse [TvUpdateCardPhase.Offer]. */
    fun phase(cardHost: String, requestAddress: String?, running: Boolean, step: TvInstallStep?, result: TvInstallResult?,
              error: TvInstallException?): TvUpdateCardPhase {
        if (requestAddress == null || hostOf(requestAddress) != cardHost) return TvUpdateCardPhase.Offer
        return when {
            running -> TvUpdateCardPhase.Running(step)
            result != null -> TvUpdateCardPhase.Done(result.version, result.alreadyInstalled)
            error != null -> TvUpdateCardPhase.Failed(error, needsScreen(error))
            else -> TvUpdateCardPhase.Offer
        }
    }
}
