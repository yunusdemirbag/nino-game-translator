// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.service

import android.content.Context
import android.graphics.Bitmap
import android.util.Log
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update

/**
 * Oyundaki bir yazının çevirisi ve görüntüdeki yeri (0–1 oranları). Yer bilinmiyorsa dört değer de null.
 * Ekran çevirisi ve ek alan çevirileri (görev, telefon, bildirim) için.
 */
data class PlacedText(
    val text: String,
    val left: Float? = null,
    val top: Float? = null,
    val right: Float? = null,
    val bottom: Float? = null,
)

/** "Son çeviriler" listesindeki satır (en yeni başta, en çok 20). */
data class RecentTranslation(
    val id: Int,
    val source: String,
    val translation: String,
    /** Kökeni: paket, havuz ya da motor. */
    val origin: TranslationOrigin,
    /** Çeviri süresi (ms); paket satırında null. */
    val translateMs: Long? = null,
)

enum class TranslationOrigin { PACK, POOL, ENGINE }

/**
 * Çeviri hizmetinin arayüze gösterdiği anlık durum. Arayüz yalnız bunu okur; hizmet [LiveStatus.update] ile yazar.
 * Metinler (aşama, neden, hata) hizmet tarafından yerelleştirilmiş olarak verilir.
 */
data class LiveSnapshot(
    /** Çeviri açık (gerçek oturum ya da örnek oturum). */
    val running: Boolean = false,
    /** Örnek (demo) oturum açık; konsol gerekmez. */
    val demo: Boolean = false,
    /** Görüntü geliyor (Remote Play/Xbox/kart kareleri akıyor). Açık + akıyor = "Canlı". */
    val streaming: Boolean = false,
    /** Hizmetin o anki aşama yazısı (ör. "PS5'e bağlanılıyor…", "Altyazılar okunuyor"). */
    val phaseText: String? = null,
    /** Bağlanamama nedeni (ör. PS5'i şu an başka bir Remote Play kullanıyor); bağlanırken ana ekranda kalır. */
    val connectReason: String? = null,
    /** Ana ekranda uyarı karosunda gösterilecek hata (ör. kamera izni yok). */
    val errorText: String? = null,
    /** Şu an ekranda görünen çeviri; yoksa null. Telefon ekranı için en çok 42 harflik satırlara bölünmüştür. */
    val currentLine: String? = null,
    /** Bir önceki çeviri satırı (telefon tam ekranında "önceki satır"). */
    val previousLine: String? = null,
    /** Son gösterilen çeviri (şu an görünmese de). */
    val lastLine: String? = null,
    /** Kullanılan oyun paketinin kimliği ve oyun adı. */
    val packId: String? = null,
    val packTitle: String? = null,
    /** Oynanan oyun "öncelikli havuz oyunu" olarak tanındı (GTA 6): gün batımı fonu ve renkli LED. */
    val poolFirstGame: Boolean = false,
    /** Bağlı TV sayısı. */
    val connectedTvs: Int = 0,
    /** Çevirinin başladığı an (System.currentTimeMillis); "çeviri başladı" balonu için. */
    val startedAtMs: Long? = null,
    /** Son oyun karesi (altyazı alanı önizlemesi); yalnız önizleme açıkken dolu tutulabilir. */
    val lastFrame: Bitmap? = null,
    /** Ekranı çevir sonuçları. */
    val screenTranslations: List<PlacedText> = emptyList(),
    /** Ekran çevirisi sürüyor. */
    val screenTranslating: Boolean = false,
    /** Ek alan çevirileri. */
    val extraTranslations: List<PlacedText> = emptyList(),
    // ---- hizmetin eklediği alanlar ----
    /** Telefon ekranındaki satırın yazı ölçeği (3 satıra sığmayan yazı 0.75'e kadar küçülür). */
    val currentLineScale: Float = 1f,
    /** Telefon satırının numarası (aynı metin yeniden gösterilince de değişir). */
    val currentLineId: Int = 0,
    /** Son çeviriler, en yeni başta, en çok 20. */
    val recent: List<RecentTranslation> = emptyList(),
    /** Oturumda gösterilen satır ve paketten gelen satır sayısı. */
    val shownLines: Int = 0,
    val packLines: Int = 0,
    /** Alınan toplam kare. */
    val framesReceived: Long = 0,
    /** Motor adı: "Ücretsiz", "DeepL", "Gemini", "OpenAI", "Claude". */
    val engineName: String? = null,
    /** Tanınan/seçilen oyun; yoksa null. */
    val game: String? = null,
    /** "Hangi oyunu oynuyorsunuz?" kartı açık (servis.md 4). */
    val askGameCard: Boolean = false,
    /** Kartın önerileri: önce bu konsolda son seçilen, sonra kurulu paketlerin oyun adları. */
    val askGameSuggestions: List<String> = emptyList(),
    /** Kullanıcının bu oturumda elle seçtiği oyun; yoksa null. */
    val manualGame: String? = null,
    /** "Ekranı çevir" sonuçları ekranda (düğme durumu: boşta / çevriliyor [screenTranslating] / ekranda). */
    val screenShowing: Boolean = false,
    /** "Ekranı çevir" kısa notu ("Ekranda yazı bulunamadı." gibi); yoksa null. */
    val screenNotice: String? = null,
    /** Oyun içi telefon paneli ya da harita kartı TV'de gösteriliyor (GTA 6). */
    val gameOverlayActive: Boolean = false,
    /** Sistem sağlığı (servis.md 5); oturum bitince son değerler kalır. */
    val health: HealthSnapshot? = null,
)

/** Çalışan oturumun arayüzden gelen komutları (oturum kaydeder, durunca siler). */
internal object SessionControl {
    interface Handler {
        fun toggleScreen()
        fun clearScreen()
        fun chooseGame(game: String?)
        fun closeGameCard(neverAgain: Boolean)
        fun openGameCard()
        /** 8 sn'lik deneme altyazısı (hedef TV ya da telefon). */
        fun testSubtitle(text: String)
        /** Paket içe aktarıldı ya da silindi: paketler yeniden okunur. */
        fun reloadPacks()
    }

    @Volatile var handler: Handler? = null
}

/** Canlı durum akışı. Hizmet ve örnek oturum yazar, arayüz okur. */
object LiveStatus {
    private val _state = MutableStateFlow(LiveSnapshot())
    val state: StateFlow<LiveSnapshot> = _state.asStateFlow()

    /** Hizmet tarafı yazar. */
    fun update(transform: (LiveSnapshot) -> LiveSnapshot) = _state.update(transform)

    fun reset() { _state.value = LiveSnapshot() }

    /** Durdurulunca: hata metni ve son sağlık ölçümü kalır, gerisi sıfırlanır (servis.md 1.2). */
    internal fun resetKeepingError() = _state.update { LiveSnapshot(errorText = it.errorText, health = it.health) }
}

/** Çeviriyi başlatma/durdurma kapısı. Arayüz yalnız bunu çağırır. */
object TranslationControl {
    private const val TAG = "Nino"

    /** Altyazı alanı önizlemesi açık mı (hizmet bu sürede kareleri [LiveSnapshot.lastFrame]'e yazar; kanca). */
    @Volatile var previewActive = false
        private set

    /** Gerçek çeviri oturumunu başlatır. */
    fun start(context: Context) {
        DemoSession.stop()
        TranslationService.start(context)
    }

    /**
     * Örnek (demo) oturumu başlatır: konsol gerekmez. Geliştirme yapısında deneme kareleri varsa bunun yerine gerçek
     * okuma hattı deneme kareleriyle çalışır (PS5'siz uçtan uca deneme).
     */
    fun startDemo(context: Context) {
        if (DebugSources.available(context)) {
            Log.i(TAG, "örnek oturum: deneme kareleriyle gerçek okuma hattı")
            TranslationService.start(context, debugFrames = true)
            return
        }
        DemoSession.start(context)
    }

    /** Örnek oturum açıksa onu, değilse çeviri hizmetini durdurur. */
    fun stop(context: Context) {
        if (DemoSession.isRunning) { DemoSession.stop(); return }
        TranslationService.stop(context)
    }

    /**
     * "Ekranı çevir" düğmesi (servis.md 3.7): çeviri sürüyorsa bir sonraki kare bir kez okunur ve çevrilir; çevrilirken
     * ya da sonuçlar ekrandayken basmak her şeyi kaldırır. Çeviri çalışmıyorsa bir şey yapmaz.
     */
    fun translateScreen(context: Context) {
        val h = SessionControl.handler ?: run { Log.i(TAG, "ekranı çevir: çeviri çalışmıyor"); return }
        h.toggleScreen()
    }

    /** Ekran çevirilerini kaldır. */
    fun clearScreenTranslations(context: Context) {
        SessionControl.handler?.clearScreen()
            ?: LiveStatus.update { it.copy(screenTranslations = emptyList(), screenTranslating = false, screenShowing = false) }
    }

    /** "Hangi oyunu oynuyorsunuz?" kartında seçilen oyun; null elle seçimi kaldırır. Konsolun adıyla saklanır. */
    fun chooseGame(context: Context, game: String?) { SessionControl.handler?.chooseGame(game) }

    /** Kartı kapat; [neverAgain] "Sorma": bu oturumda bir daha sorulmaz. */
    fun dismissGameCard(context: Context, neverAgain: Boolean) { SessionControl.handler?.closeGameCard(neverAgain) }

    /** "Değiştir": kartı elle açar. */
    fun openGameCard(context: Context) { SessionControl.handler?.openGameCard() }

    /**
     * Deneme altyazısı (servis.md 3.8): çeviri sürüyorsa oturum gönderir; çalışmıyorsa ve hedef TV ise TV bağlantısı
     * kısa süre açılıp gönderilir. [onDone] ana iş parçacığında; hiçbir yere gidemediyse false.
     */
    fun sendTestSubtitle(context: Context, text: String, onDone: (Boolean) -> Unit = {}) = TestSubtitles.send(context, text, onDone)

    /** Paket içe aktarılınca ya da silinince: çalışan çeviri paketleri yeniden okur (servis.md 3.9). */
    fun reloadPacks(context: Context) { SessionControl.handler?.reloadPacks() }

    /** Altyazı alanı önizlemesi açık/kapalı (hizmet bu sürede kareleri [LiveSnapshot.lastFrame]'e yazar). */
    fun setPreviewActive(context: Context, active: Boolean) { previewActive = active }
}
