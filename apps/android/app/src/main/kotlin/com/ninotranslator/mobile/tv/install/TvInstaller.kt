// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.tv.install

import com.ninotranslator.mobile.data.TvBrand
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

/** Kurulumun o anki adımı; arayüz metne çevirir (ekranlar-2 "TV uygulaması kurulumu"). */
enum class TvInstallStep {
    PAIRING, APPROVE, KEY, PLAY, CONNECTING, READING, SIGNIN, CERTIFICATE, SIGNING, INSTALLING, UNINSTALLING, LAUNCHING,
}

/** Kurulum hataları. */
enum class TvInstallError {
    // Ortak
    SPACE, CONNECTION, PACKAGE_MISSING, FAILED, NOT_READY, ADDRESS_INVALID,
    // Samsung
    SAMSUNG_UNREACHABLE, SAMSUNG_TOO_OLD, SAMSUNG_LOGIN, SAMSUNG_CERTIFICATE, SAMSUNG_MISMATCH, SAMSUNG_REJECTED,
    SAMSUNG_CLOCK, SAMSUNG_BLOCKED,
    // LG
    LG_UNREACHABLE, LG_KEY_SERVER, LG_PASSPHRASE, LG_KEY_REFUSED,
    // Android TV
    ANDROID_UNREACHABLE, ANDROID_NOT_APPROVED, ANDROID_NOT_PAIRED, ANDROID_PAIRING, ANDROID_PLAY_COPY, ANDROID_OTHER_COPY,
    ANDROID_REMOVE_MANUALLY, ANDROID_NEED_PORT, ANDROID_NEED_PAIR_PORT,
}

/**
 * Kurulum hatası. [detail] ekranda "Ayrıntılar" altında gösterilen teknik veri (sistemin ya da TV'nin iletisi, kod,
 * sürüm; Nino'nun kendi cümlesi değil). [note] yalnız kurulum günlüğüne giden Türkçe açıklama. [maintenanceHint]
 * Samsung "sunucu bakımda" notu eklensin mi. [tvSays] LG'nin kendi yanıtı.
 */
class TvInstallException(
    val error: TvInstallError,
    val detail: String? = null,
    val maintenanceHint: Boolean = false,
    val tvSays: String? = null,
    val note: String? = null,
) : Exception(listOfNotNull(note, detail).joinToString(": ").ifEmpty { error.name }) {
    /** Android TV'de "TV'deki kopyayı kaldırıp kur" düğmesi çıksın mı. */
    val replacePossible: Boolean get() = error == TvInstallError.ANDROID_PLAY_COPY || error == TvInstallError.ANDROID_OTHER_COPY
}

/** TV karosundaki durum etiketi. */
sealed interface TvCandidateStatus {
    data object DevOn : TvCandidateStatus
    data object DevOff : TvCandidateStatus
    data class DevOtherIp(val ip: String) : TvCandidateStatus
    data object DebugOn : TvCandidateStatus
    data object DebugOff : TvCandidateStatus
}

/** Ağda bulunan, kurulabilecek TV. */
data class TvCandidate(
    val name: String,
    val address: String,
    val brand: TvBrand,
    val model: String? = null,
    val status: TvCandidateStatus? = null,
)

/** Kur ve aç isteği. */
data class TvInstallRequest(
    val brand: TvBrand,
    /** IP; Android TV kablosuzda "ip:port". */
    val address: String,
    val tvName: String? = null,
    /** LG Passphrase (büyük harf, boşluksuz) ya da null. */
    val passphrase: String? = null,
    /** Android TV: kablosuz hata ayıklama yolu. */
    val wireless: Boolean = false,
    val pairAddress: String? = null,
    val pairCode: String? = null,
    /** Android TV: TV'deki uyumsuz kopyayı kaldırıp kur (yalnız kullanıcı basarsa). */
    val replaceExisting: Boolean = false,
)

/** Başarılı kurulum. */
data class TvInstallResult(val version: String, val alreadyInstalled: Boolean, val host: String, val port: Int = 0)

/**
 * TV'ye Nino kurulumu (Samsung Tizen, LG webOS, Android TV adb). Ağ ve kurulum işi bu arayüzün arkasında; arayüz
 * yalnız bunu bilir. Kurulum günlüğü `Nino.tvInstallLog`'a yazılır.
 */
interface TvInstaller {
    /** Markanın TV'lerini arar (SSDP, port taraması). */
    suspend fun discover(brand: TvBrand): List<TvCandidate>

    /** LG: bu TV için anahtar kayıtlı mı. */
    fun hasLgKey(address: String): Boolean

    /** Kurar ve açar. Adımlar [onStep] ile bildirilir. Hata [TvInstallException]. */
    suspend fun install(request: TvInstallRequest, onStep: (TvInstallStep) -> Unit): TvInstallResult

    /**
     * Samsung girişi gerekince açılacak adres (arayüz tam ekran giriş sayfası gösterir); gerekmiyorsa null. Jeton
     * telefonda 127.0.0.1:4794'te dinleyen sunucuya gelir, o da kurulumun işi.
     */
    val samsungSignInUrl: StateFlow<String?>

    /** Kullanıcı Samsung girişini kapattı: kurulum giriş hatasıyla biter. */
    fun cancelSamsungSignIn()
}

/** Asıl kurulum katmanı yazılana kadar: arama boş döner, kurulum "henüz hazır değil" der. */
object NotReadyTvInstaller : TvInstaller {
    private val url = MutableStateFlow<String?>(null)
    override suspend fun discover(brand: TvBrand): List<TvCandidate> = emptyList()
    override fun hasLgKey(address: String): Boolean = false
    override suspend fun install(request: TvInstallRequest, onStep: (TvInstallStep) -> Unit): TvInstallResult =
        throw TvInstallException(TvInstallError.NOT_READY)
    override val samsungSignInUrl: StateFlow<String?> get() = url
    override fun cancelSamsungSignIn() { url.value = null }
}

/** Kullanılan kurulum katmanı: asıl kurucu, uygulama bağlamı hazır olunca kendiliğinden kurulur. Testte değiştirilebilir. */
object TvInstallers {
    @Volatile private var chosen: TvInstaller? = null

    var current: TvInstaller
        get() = chosen ?: synchronized(this) {
            chosen ?: runCatching { NetworkTvInstaller.create(com.ninotranslator.mobile.data.Nino.appContext) }.getOrNull()?.also { chosen = it }
        } ?: NotReadyTvInstaller
        set(value) { chosen = value }
}

/** Nino'nun kendi G/Ç hatası (iletisi Türkçe, yalnız günlük için; ekranda gösterilmez). */
open class LocalIoException(message: String, cause: Throwable? = null) : java.io.IOException(message, cause)

/**
 * Ekranda gösterilecek teknik ayrıntı: hata zincirinde Nino'nun kendi iletisi olmayan ilk hatanın iletisi (sistemin,
 * kütüphanenin ya da TV'nin), yoksa null. Nino'nun Türkçe iletileri yalnız günlüğe gider.
 */
fun techDetail(e: Throwable?): String? {
    var c = e
    var depth = 0
    while (c != null && depth++ < 10) {
        if (c !is LocalIoException && c !is TvInstallException) return c.message?.takeIf { it.isNotBlank() } ?: c.javaClass.simpleName
        if (c is TvInstallException && c.detail != null) return c.detail
        c = c.cause?.takeIf { it !== c }
    }
    return null
}
