// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.data

import android.content.SharedPreferences
import com.ninotranslator.core.packs.GameIds
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlin.math.roundToInt
import kotlin.properties.ReadWriteProperty
import kotlin.reflect.KProperty

/**
 * `settings` SharedPreferences dosyası (veri-ve-ayarlar.md §1.1). Anahtar adları kalıcı veri sözleşmesidir.
 * [deviceLanguage]: telefonun sistem dili (ör. "tr", "in", "fil"); çeviri dili yokken türetmede kullanılır.
 */
class Settings(prefs: SharedPreferences, private val deviceLanguage: () -> String = { java.util.Locale.getDefault().language }) {
    val store = PrefStore(prefs)

    /** Değişen anahtar adları. */
    val changes: SharedFlow<String> get() = store.changes

    /** Her yazmada artar. */
    val revision: StateFlow<Long> get() = store.revision

    /** Seçilen değeri izler: ilk değeri hemen verir, sonra yalnız değişince. */
    fun <T> watch(selector: (Settings) -> T): Flow<T> = store.revision.map { selector(this) }.distinctUntilChanged()

    fun addListener(listener: (String) -> Unit): AutoCloseable = store.addListener(listener)

    // --- Kurulum ve akış durumu ---
    var welcomeSeen by bool(K.WELCOME_SEEN, false)
    var tourShown by bool(K.TOUR_SHOWN, false)
    var consoleAsked by bool(K.CONSOLE_ASKED, false)
    var setupSkipped by bool(K.SETUP_SKIPPED, false)
    var onboarded by bool(K.ONBOARDED, false)
    var videoSource by enumPref(K.VIDEO_SOURCE, VideoSource.REMOTE_PLAY)
    var target by enumPref(K.TARGET, SubtitleTarget.TV)
    var tvName by nullableString(K.TV_NAME)

    /** `homeStyleV4`. Eski `homeStyle` anahtarı bilerek okunmaz. */
    var homeStyle by enumPref(K.HOME_STYLE_V4, HomeStyle.LIVING_ROOM)

    /** `platform` anahtarı var mı (değeri okunmaz, §5.1). */
    val hasPlatformKey: Boolean get() = store.has(K.PLATFORM)

    /** §5.1: XBOX kaynağı → Xbox; consoleAsked, yakalama kartı ya da `platform` varsa → PlayStation; yoksa null. */
    val consoleKind: ConsoleKind?
        get() = when {
            videoSource == VideoSource.XBOX -> ConsoleKind.XBOX
            consoleAsked || videoSource == VideoSource.CAPTURE_CARD || hasPlatformKey -> ConsoleKind.PLAYSTATION
            else -> null
        }

    /** Seçilmediyse uygulamanın geri kalanı PlayStation varsayar. */
    val effectiveConsoleKind: ConsoleKind get() = consoleKind ?: ConsoleKind.PLAYSTATION

    /** Konsol türü seçimi (§5.1), tek işlemde. */
    fun selectConsoleKind(kind: ConsoleKind?) {
        val source = videoSource
        store.edit(K.CONSOLE_ASKED, K.PLATFORM, K.VIDEO_SOURCE) {
            putBoolean(K.CONSOLE_ASKED, kind != null)
            if (kind == null) remove(K.PLATFORM) else putString(K.PLATFORM, kind.name)
            when {
                kind == ConsoleKind.XBOX -> putString(K.VIDEO_SOURCE, VideoSource.XBOX.name)
                source == VideoSource.XBOX -> putString(K.VIDEO_SOURCE, VideoSource.REMOTE_PLAY.name)
            }
        }
    }

    /** Hedef seçimi bitti (§5.2). */
    fun completeTargetSelection(target: SubtitleTarget, tvName: String?) {
        store.edit(K.TARGET, K.TV_NAME, K.ONBOARDED) {
            putString(K.TARGET, target.name)
            if (tvName.isNullOrBlank()) remove(K.TV_NAME) else putString(K.TV_NAME, tvName)
            putBoolean(K.ONBOARDED, true)
        }
    }

    /** Telefondan TV uygulaması kuruldu: `tvApp.*`, hedef TV, kurulum bitti. */
    fun recordTvInstall(tv: InstalledTv) {
        store.edit(K.TV_APP_KEYS + listOf(K.TARGET, K.ONBOARDED)) {
            writeTv(tv)
            putString(K.TARGET, SubtitleTarget.TV.name)
            putBoolean(K.ONBOARDED, true)
        }
    }

    // --- Dil ve çeviri ---

    /**
     * Çeviri dili (iki harfli küçük kod). Anahtar yoksa: kurulumu bitmiş eski kurulum `tr`; yeni kurulumda telefon dili
     * listedeyse o, değilse `tr`. Türetilen değer ilk okumada yazılır.
     */
    var targetLanguage: String
        get() {
            store.string(K.TARGET_LANGUAGE)?.takeIf { it.isNotBlank() }?.let { return it }
            val derived = if (onboarded) "tr" else AppLanguage.fromDevice(deviceLanguage())
            store.putString(K.TARGET_LANGUAGE, derived)
            return derived
        }
        set(value) = store.putString(K.TARGET_LANGUAGE, AppLanguage.normalizeForSave(value))

    /** Arayüz dili etiketi (§5.3). */
    val uiLanguageTag: String get() = AppLanguage.uiTag(targetLanguage)

    var engine by enumPref(K.ENGINE, Engine.FREE)
    var aiModel by nullableString(K.AI_MODEL)
    var packsEnabled by bool(K.PACKS_ENABLED, true)
    var disabledPacks: Set<String>
        get() = store.stringSet(K.DISABLED_PACKS)
        set(value) = store.edit(K.DISABLED_PACKS) { putStringSet(K.DISABLED_PACKS, value.toSet()) }
    var sharePool by bool(K.SHARE_POOL, true)
    var askGame by bool(K.ASK_GAME, true)
    var showSpeakerNames by bool(K.SHOW_SPEAKER_NAMES, true)
    var fastSubtitleDetection by bool(K.FAST_SUBTITLE_DETECTION, false)
    var lastGamePoolFirst by bool(K.LAST_GAME_POOL_FIRST, false)

    /** O konsolda son seçilen oyun. [consoleLabel] için bkz. [lastGameConsoleLabel]. */
    /** Eski kayıttaki takma ad ("grand-theft-auto-vi") okunurken asıl kimliğe ("gta-6") çevrilir. */
    fun lastGame(consoleLabel: String): String? = GameIds.upgradeStored(store.string(K.LAST_GAME_PREFIX + consoleLabel))
    fun setLastGame(consoleLabel: String, game: String?) =
        store.putString(K.LAST_GAME_PREFIX + consoleLabel, game?.takeIf { it.isNotBlank() })

    // --- Altyazı görünümü ---

    /** Yüzde, 40–160'a sıkıştırılır. */
    var subtitleScale: Int
        get() = store.int(K.SUBTITLE_SCALE, 100).coerceIn(40, 160)
        set(value) = store.putInt(K.SUBTITLE_SCALE, value.coerceIn(40, 160))

    /** Kullanıcı ölçek kaydırıcısını oynattı: ölçek yazılır ve otomatik boy kapanır (§5.4). */
    fun setSubtitleScaleByUser(value: Int) {
        store.edit(K.SUBTITLE_SCALE, K.TV_AUTO_SIZE) {
            putInt(K.SUBTITLE_SCALE, value.coerceIn(40, 160))
            putBoolean(K.TV_AUTO_SIZE, false)
        }
    }

    /** Anahtar yoksa: ölçek 100 ve tvFontSize 46 ise açık, değilse kapalı. */
    var tvAutoSize: Boolean
        get() = if (store.has(K.TV_AUTO_SIZE)) store.bool(K.TV_AUTO_SIZE, true)
        else subtitleScale == 100 && tvFontSize == 46
        set(value) = store.putBool(K.TV_AUTO_SIZE, value)

    var tvFontSize by int(K.TV_FONT_SIZE, 46)
    var phoneTextSize by int(K.PHONE_TEXT_SIZE, 34)
    var textColor by enumPref(K.TEXT_COLOR, TextColor.WHITE)
    var subtitleFont: SubtitleFont
        get() = SubtitleFont.parse(store.string(K.SUBTITLE_FONT))
        set(value) = store.putString(K.SUBTITLE_FONT, value.wire)
    var tvBackground: Int
        get() = store.int(K.TV_BACKGROUND, 72).coerceIn(0, 100)
        set(value) = store.putInt(K.TV_BACKGROUND, value.coerceIn(0, 100))
    var tvBackgroundShape by enumPref(K.TV_BACKGROUND_SHAPE, TvBackgroundShape.FIT)
    var stackPrevious by bool(K.STACK_PREVIOUS, true)
    var tvWatermark by bool(K.TV_WATERMARK, true)
    var tvDisplayMode by enumPref(K.TV_DISPLAY_MODE, TvDisplayMode.IN_APP)
    var tvPlacement by enumPref(K.TV_PLACEMENT, TvPlacement.COVER)
    var tvBottomPercent: Int
        get() = store.int(K.TV_BOTTOM_PERCENT, 7).coerceIn(0, 85)
        set(value) = store.putInt(K.TV_BOTTOM_PERCENT, value.coerceIn(0, 85))
    var keepScreenOn by bool(K.KEEP_SCREEN_ON, true)

    /** TV'ye giden yazı boyu = round(tvFontSize × ölçek / 100). */
    val tvFontPx: Int get() = (tvFontSize * subtitleScale / 100.0).roundToInt()

    /** TV'ye giden koyuluk: COVER'da 60'ın altı 100 olur; kayıtlı değer değişmez. */
    val effectiveTvBackground: Int
        get() = tvBackground.let { if (tvPlacement == TvPlacement.COVER && it < 60) 100 else it }

    // --- Okunan bölgeler ---

    /** Bozuk/eksik JSON → varsayılan bölge. */
    var region: Region
        get() = Region.parse(store.string(K.REGION)) ?: Region.DEFAULT
        set(value) = store.putString(K.REGION, value.toJson())

    /** Anahtar yoksa kayıtlı bölgeden türetilir. */
    val areaPreset: AreaPreset
        get() = parseEnum<AreaPreset>(store.string(K.AREA_PRESET)) ?: Region.presetOf(region)

    /** Hazır bölge seçimi: BOTTOM/TOP/FULL hem bölgeyi hem seçimi yazar; CUSTOM kayıtlı bölgeyi korur. */
    fun selectAreaPreset(preset: AreaPreset) {
        val r = Region.of(preset)
        store.edit(K.REGION, K.AREA_PRESET) {
            if (r != null) putString(K.REGION, r.toJson())
            putString(K.AREA_PRESET, preset.name)
        }
    }

    /** Elle çizilen bölge: `region` + `areaPreset` = CUSTOM. */
    fun setCustomRegion(r: Region) {
        store.edit(K.REGION, K.AREA_PRESET) {
            putString(K.REGION, r.toJson())
            putString(K.AREA_PRESET, AreaPreset.CUSTOM.name)
        }
    }

    /** En çok 3. */
    var extraAreas: List<ExtraArea>
        get() {
            val (list, repaired) = ExtraArea.parse(store.string(K.EXTRA_AREAS))
            // Boş kimliğe üretilen yeni kimlik bir kez yazılır ki arayüz ve hizmet aynı kimliği görsün.
            if (repaired) store.putString(K.EXTRA_AREAS, ExtraArea.toJson(list))
            return list
        }
        set(value) = store.putString(K.EXTRA_AREAS, ExtraArea.toJson(value))

    // --- Xbox ---
    var xboxConsole: XboxConsole?
        get() = XboxConsole.parse(store.string(K.XBOX_CONSOLE))
        set(value) = store.putString(K.XBOX_CONSOLE, value?.toJson())
    var xboxAudioOnDevice by bool(K.XBOX_AUDIO_ON_DEVICE, true)
    var xboxQuality by enumPref(K.XBOX_QUALITY, XboxQuality.P1080)

    // --- TV uygulaması kurulumu ---
    var tvInstallBrand: TvBrand?
        get() = parseEnum<TvBrand>(store.string(K.TV_INSTALL_BRAND))
        set(value) = store.putString(K.TV_INSTALL_BRAND, value?.name)

    /** `tvApp.*` dörtlüsü; marka ya da adres yoksa null. null yazmak dördünü siler. */
    var installedTv: InstalledTv?
        get() {
            val brand = parseEnum<TvBrand>(store.string(K.TV_APP_BRAND)) ?: return null
            val host = store.string(K.TV_APP_HOST)?.takeIf { it.isNotBlank() } ?: return null
            return InstalledTv(brand, host, store.int(K.TV_APP_PORT, 0), store.string(K.TV_APP_VERSION))
        }
        set(value) = store.edit(K.TV_APP_KEYS) { writeTv(value) }

    /** LG geliştirici oturumunun son uzatıldığı an (Unix ms) ya da null. */
    fun lgSessionRenewedAt(address: String): Long? {
        val key = lgKey(address)
        return if (store.has(key)) store.long(key, 0L) else null
    }

    fun setLgSessionRenewedAt(address: String, ms: Long?) {
        val key = lgKey(address)
        store.edit(key) { if (ms == null) remove(key) else putLong(key, ms) }
    }

    // --- Bildirim, ölçüm ve sağlık ---
    var notifyDisconnect by bool(K.NOTIFY_DISCONNECT, true)
    var notifyPacks by bool(K.NOTIFY_PACKS, true)
    var usageData by bool(K.USAGE_DATA, true)
    var autoReport by bool(K.AUTO_REPORT, true)
    var translating by bool(K.TRANSLATING, false)
    var lastExitReportAt by long(K.LAST_EXIT_REPORT_AT, 0L)
    var lastSessionMs by long(K.LAST_SESSION_MS, 0L)
    var downloadTotal by int(K.DOWNLOAD_TOTAL, 0)

    /** Meta olayları: kullanım verisi açık ve karşılama geçilmiş (§5.6). */
    val metaEventsAllowed: Boolean get() = usageData && welcomeSeen

    /** Açılışta: `translating` okunur ve hemen false yapılır. true döndüyse önceki süreç çeviri sırasında ölmüştür. */
    fun consumeTranslatingFlag(): Boolean {
        val was = store.bool(K.TRANSLATING, false)
        if (was || !store.has(K.TRANSLATING)) store.editNow(listOf(K.TRANSLATING)) { putBoolean(K.TRANSLATING, false) }
        return was
    }

    // --- iç yardımcılar ---

    private fun SharedPreferences.Editor.writeTv(tv: InstalledTv?) {
        if (tv == null) {
            K.TV_APP_KEYS.forEach { remove(it) }
        } else {
            putString(K.TV_APP_BRAND, tv.brand.name)
            putString(K.TV_APP_HOST, tv.host)
            putInt(K.TV_APP_PORT, tv.port)
            if (tv.version.isNullOrBlank()) remove(K.TV_APP_VERSION) else putString(K.TV_APP_VERSION, tv.version)
        }
    }

    private fun bool(key: String, def: Boolean) = object : ReadWriteProperty<Settings, Boolean> {
        override fun getValue(thisRef: Settings, property: KProperty<*>) = store.bool(key, def)
        override fun setValue(thisRef: Settings, property: KProperty<*>, value: Boolean) = store.putBool(key, value)
    }

    private fun int(key: String, def: Int) = object : ReadWriteProperty<Settings, Int> {
        override fun getValue(thisRef: Settings, property: KProperty<*>) = store.int(key, def)
        override fun setValue(thisRef: Settings, property: KProperty<*>, value: Int) = store.putInt(key, value)
    }

    private fun long(key: String, def: Long) = object : ReadWriteProperty<Settings, Long> {
        override fun getValue(thisRef: Settings, property: KProperty<*>) = store.long(key, def)
        override fun setValue(thisRef: Settings, property: KProperty<*>, value: Long) = store.putLong(key, value)
    }

    private fun nullableString(key: String) = object : ReadWriteProperty<Settings, String?> {
        override fun getValue(thisRef: Settings, property: KProperty<*>) = store.string(key)
        override fun setValue(thisRef: Settings, property: KProperty<*>, value: String?) =
            store.putString(key, value?.takeIf { it.isNotBlank() })
    }

    private inline fun <reified E : Enum<E>> enumPref(key: String, def: E) = object : ReadWriteProperty<Settings, E> {
        override fun getValue(thisRef: Settings, property: KProperty<*>) = parseEnum<E>(store.string(key)) ?: def
        override fun setValue(thisRef: Settings, property: KProperty<*>, value: E) = store.putString(key, value.name)
    }

    /** Anahtar adları (kalıcı sözleşme). */
    object K {
        const val WELCOME_SEEN = "welcomeSeen"
        const val TOUR_SHOWN = "tourShown"
        const val CONSOLE_ASKED = "consoleAsked"
        const val PLATFORM = "platform"
        const val SETUP_SKIPPED = "setupSkipped"
        const val ONBOARDED = "onboarded"
        const val VIDEO_SOURCE = "videoSource"
        const val TARGET = "target"
        const val TV_NAME = "tvName"
        const val HOME_STYLE_V4 = "homeStyleV4"
        const val TARGET_LANGUAGE = "targetLanguage"
        const val ENGINE = "engine"
        const val AI_MODEL = "aiModel"
        const val PACKS_ENABLED = "packsEnabled"
        const val DISABLED_PACKS = "disabledPacks"
        const val SHARE_POOL = "sharePool"
        const val ASK_GAME = "askGame"
        const val SHOW_SPEAKER_NAMES = "showSpeakerNames"
        const val FAST_SUBTITLE_DETECTION = "fastSubtitleDetection"
        const val LAST_GAME_PREFIX = "lastGame."
        const val LAST_GAME_POOL_FIRST = "ninoLastGamePoolFirst"
        const val SUBTITLE_SCALE = "subtitleScale"
        const val TV_AUTO_SIZE = "tvAutoSize"
        const val TV_FONT_SIZE = "tvFontSize"
        const val PHONE_TEXT_SIZE = "phoneTextSize"
        const val TEXT_COLOR = "textColor"
        const val SUBTITLE_FONT = "subtitleFont"
        const val TV_BACKGROUND = "tvBackground"
        const val TV_BACKGROUND_SHAPE = "tvBackgroundShape"
        const val STACK_PREVIOUS = "stackPrevious"
        const val TV_WATERMARK = "tvWatermark"
        const val TV_DISPLAY_MODE = "tvDisplayMode"
        const val TV_PLACEMENT = "tvPlacement"
        const val TV_BOTTOM_PERCENT = "tvBottomPercent"
        const val KEEP_SCREEN_ON = "keepScreenOn"
        const val REGION = "region"
        const val AREA_PRESET = "areaPreset"
        const val EXTRA_AREAS = "extraAreas"
        const val XBOX_CONSOLE = "xboxConsole"
        const val XBOX_AUDIO_ON_DEVICE = "xboxAudioOnDevice"
        const val XBOX_QUALITY = "xboxQuality"
        const val TV_INSTALL_BRAND = "experimental.tvInstallBrand"
        const val TV_APP_BRAND = "tvApp.brand"
        const val TV_APP_HOST = "tvApp.host"
        const val TV_APP_PORT = "tvApp.port"
        const val TV_APP_VERSION = "tvApp.version"
        const val LG_SESSION_PREFIX = "tvApp.lgSessionRenewed."
        const val NOTIFY_DISCONNECT = "notify.disconnect"
        const val NOTIFY_PACKS = "notify.packs"
        const val USAGE_DATA = "usageData"
        const val AUTO_REPORT = "autoReport"
        const val TRANSLATING = "translating"
        const val LAST_EXIT_REPORT_AT = "lastExitReportAt"
        const val LAST_SESSION_MS = "lastSessionMs"
        const val DOWNLOAD_TOTAL = "ninoDownloadTotal"

        val TV_APP_KEYS = listOf(TV_APP_BRAND, TV_APP_HOST, TV_APP_PORT, TV_APP_VERSION)

        /** Çeviri sürerken değişince TV'ye hemen yeni görünüm gönderilen anahtarlar (§5.4). */
        val TV_APPEARANCE_KEYS = setOf(
            SUBTITLE_SCALE, TEXT_COLOR, SUBTITLE_FONT, TV_FONT_SIZE, TV_BACKGROUND, TV_BACKGROUND_SHAPE, STACK_PREVIOUS,
            TV_DISPLAY_MODE, TV_PLACEMENT, TV_BOTTOM_PERCENT, TV_AUTO_SIZE, TV_WATERMARK,
        )

        /** Çeviri sürerken okuma bölgesini hemen değiştiren anahtarlar (§5.5). */
        val READ_AREA_KEYS = setOf(REGION, EXTRA_AREAS)
    }

    companion object {
        const val FILE = "settings"

        /** LG oturum anahtarı: boşluklar atılmış, küçük harfli adres. */
        fun lgKey(address: String) = K.LG_SESSION_PREFIX + address.filterNot { it.isWhitespace() }.lowercase()

        /** `lastGame.<ad>` için konsol adı: PS5 adı (boşsa adresi), Xbox adı (boşsa "Xbox"). */
        fun lastGameConsoleLabel(kind: ConsoleKind, name: String?, host: String?): String = when (kind) {
            ConsoleKind.PLAYSTATION -> name?.takeIf { it.isNotBlank() } ?: host.orEmpty()
            ConsoleKind.XBOX -> name?.takeIf { it.isNotBlank() } ?: "Xbox"
        }
    }
}
