// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.service

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.os.SystemClock
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import com.ninotranslator.core.http.UrlConnectionTransport
import com.ninotranslator.core.link.DisplayEvent
import com.ninotranslator.core.link.DisplayHub
import com.ninotranslator.core.link.NinoLink
import com.ninotranslator.core.link.ShowPayload
import com.ninotranslator.core.packs.GameIds
import com.ninotranslator.core.packs.LegacyPackLibrary
import com.ninotranslator.core.packs.PackStore
import com.ninotranslator.core.pool.LineQueue
import com.ninotranslator.core.pool.PoolConfig
import com.ninotranslator.core.pool.SharedPool
import com.ninotranslator.core.reading.live.GameAskCard
import com.ninotranslator.core.reading.live.Gta6Hints
import com.ninotranslator.core.reading.live.LiveBox
import com.ninotranslator.core.reading.live.LiveLine
import com.ninotranslator.core.reading.live.LiveReading
import com.ninotranslator.core.reading.live.ScreenIdentifyGate
import com.ninotranslator.core.reading.live.LiveClock
import com.ninotranslator.core.reading.live.LiveRegion
import com.ninotranslator.core.reading.live.LiveShowKind
import com.ninotranslator.core.reading.live.LiveStabilizer
import com.ninotranslator.core.reading.live.SubtitleBand
import com.ninotranslator.core.translation.AiModels
import com.ninotranslator.core.translation.Glossary
import com.ninotranslator.core.translation.LineCache
import com.ninotranslator.core.translation.LineResult
import com.ninotranslator.core.translation.LineTranslator
import com.ninotranslator.core.translation.OnDeviceLineTranslator
import com.ninotranslator.core.translation.OnlineEngines
import com.ninotranslator.core.translation.OnlineLineTranslator
import com.ninotranslator.core.translation.OnlineRequest
import com.ninotranslator.core.translation.OnlineService
import com.ninotranslator.core.translation.translateAsync
import com.ninotranslator.core.translation.RecentLines
import com.ninotranslator.core.translation.TargetLanguage
import com.ninotranslator.core.translation.TranslationSettings
import com.ninotranslator.mobile.BuildConfig
import com.ninotranslator.mobile.R
import com.ninotranslator.mobile.data.Engine
import com.ninotranslator.mobile.data.HistoryOrigin
import com.ninotranslator.mobile.data.Nino
import com.ninotranslator.mobile.data.Settings
import com.ninotranslator.mobile.data.SubtitleLayoutStore
import com.ninotranslator.mobile.data.SubtitleTarget
import com.ninotranslator.mobile.data.TvBrand
import com.ninotranslator.mobile.data.VideoSource
import com.ninotranslator.mobile.ocr.MlKitTextReader
import com.ninotranslator.mobile.packs.PoolPacks
import com.ninotranslator.mobile.remoteplay.PairedPs5
import com.ninotranslator.mobile.support.DownloadCounter
import com.ninotranslator.mobile.remoteplay.RemotePlayNative
import com.ninotranslator.mobile.remoteplay.RemotePlayTarget
import com.ninotranslator.mobile.telemetry.AppDiag
import com.ninotranslator.mobile.telemetry.SessionTelemetry
import com.ninotranslator.mobile.translation.MlKitTranslator
import com.ninotranslator.mobile.tv.TvFinders
import com.ninotranslator.mobile.ui.MainActivity
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.asCoroutineDispatcher
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.util.concurrent.Executors

/**
 * Ön plan çeviri hizmeti (servis.md 1–4): görüntü kaynağı → yazı tanıma → okuma kuralları → çeviri → TV ya da telefon.
 * Yapışkan değildir; sistem öldürürse geri gelmez.
 */
class TranslationService : Service() {
    private var session: Session? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            session?.stop(); session = null
            stopForegroundCompat()
            stopSelf()
            return START_NOT_STICKY
        }
        if (session != null) return START_NOT_STICKY
        val debug = intent?.getBooleanExtra(EXTRA_DEBUG_FRAMES, false) == true && DebugSources.available(this)
        val kind = if (debug) SourceKind.DEBUG_FRAMES else when (Nino.settings.videoSource) {
            VideoSource.REMOTE_PLAY -> SourceKind.REMOTE_PLAY
            VideoSource.CAPTURE_CARD -> SourceKind.CAPTURE_CARD
            VideoSource.XBOX -> SourceKind.XBOX
        }
        // Hemen ön plana geçilir (ön koşullardan önce; Android süre tanımaz).
        startForegroundCompat(kind)
        val s = Session(kind)
        session = s
        s.start()
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        session?.stop(); session = null
        super.onDestroy()
    }

    private fun stopForegroundCompat() = ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)

    // ---- bildirim (servis.md 1.3) ----

    private fun startForegroundCompat(kind: SourceKind) {
        val texts = ServiceStrings(this)
        val nm = getSystemService(NotificationManager::class.java)
        if (nm.getNotificationChannel(CHANNEL_ID) == null) {
            nm.createNotificationChannel(NotificationChannel(CHANNEL_ID, texts.get(ServiceTexts.NOTIF_CHANNEL), NotificationManager.IMPORTANCE_LOW).apply {
                setSound(null, null); enableVibration(false)
            })
        }
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val stop = PendingIntent.getService(this, 1, Intent(this, TranslationService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val n: Notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(texts.get(ServiceTexts.NOTIF_TITLE))
            .setContentText(texts.get(ServiceTexts.notificationText(kind)))
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setContentIntent(open)
            .addAction(0, texts.get(ServiceTexts.NOTIF_STOP), stop)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .build()
        // Bağlı cihaz türü; yakalama kartında kamera izni varsa kamera türü de (izinsiz kamera türüyle Android 14+ açmaz).
        var type = if (Build.VERSION.SDK_INT >= 29) ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE else 0
        if (kind == SourceKind.CAPTURE_CARD && Build.VERSION.SDK_INT >= 30 && CaptureCardSource.hasPermission(this)) {
            type = type or ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA
        }
        ServiceCompat.startForeground(this, NOTIFICATION_ID, n, type)
    }

    // ---- oturum ----

    /** Bir çeviri oturumu: başlatmadan durdurmaya her şey. */
    private inner class Session(private val kind: SourceKind) {
        private val job = SupervisorJob()
        private val main = CoroutineScope(Dispatchers.Main.immediate + job)
        private val io = CoroutineScope(Dispatchers.IO + SupervisorJob(job))
        private val loopExecutor = Executors.newSingleThreadExecutor { r -> Thread(r, "nino-reading") }
        private val loopDispatcher = loopExecutor.asCoroutineDispatcher()
        private val loopScope = CoroutineScope(loopDispatcher + SupervisorJob(job))
        private val settings: Settings = Nino.settings
        private val texts = ServiceStrings(this@TranslationService)
        private val debug = kind == SourceKind.DEBUG_FRAMES
        private val clock = LiveClock { SystemClock.elapsedRealtime() }
        private val startedAt = System.currentTimeMillis()
        /** Çeviri dili oturum başında bir kez okunur (servis.md 1.1). */
        private val target = TargetLanguage.of(settings.targetLanguage) ?: TargetLanguage.TR

        private val reasons = ConnectReasonBook()
        private val errors = ErrorBook()
        private val game = GameTracker(enabled = !debug)
        @Volatile private var stopped = false

        private var wakeLock: PowerManager.WakeLock? = null
        private var wifiLock: WifiManager.WifiLock? = null
        private var settingsListener: AutoCloseable? = null
        private var source: FrameSource? = null
        private var loop: ReadingLoop? = null
        private var router: SubtitleRouter? = null
        private var tv: TvOutput? = null
        private var reader: MlKitTextReader? = null
        private var mlkit: MlKitTranslator? = null
        @Volatile private var packs: LegacyPackLibrary? = null
        private var pool: SharedPool? = null
        private var lineTranslator: LineTranslator? = null
        private var lastStyle: Map<String, Any?>? = null
        private var poolFirst = false

        // Yan özellikler (okuma.md 9–13).
        private var sideMl: MlKitTextReader? = null
        private var screenMl: MlKitTextReader? = null
        private var onDevice: OnDeviceLineTranslator? = null
        private var online: OnlineLineTranslator? = null
        private var channel: ScreenChannel? = null
        private var extras: ExtraAreaReader? = null
        private var screen: ScreenTranslator? = null
        private var gta: GtaReader? = null
        private var identifier: ScreenGameIdentifier? = null
        private val askCard = GameAskCard(SystemClock.elapsedRealtime())
        @Volatile private var streamingNow = false
        private var lastGtaConfig: Triple<List<LiveBox>, Boolean, Boolean>? = null

        fun start() {
            reasons.reset()
            LiveStatus.update {
                LiveSnapshot(running = true, phaseText = texts.get(ServiceTexts.PREPARING), startedAtMs = startedAt,
                    engineName = engineLabel(null))
            }
            precondition()?.let { fail(it); return }
            acquireLocks()
            settings.translating = true
            main.launch {
                try {
                    // Ağır kurulum ana iş parçacığında yapılmaz (zayıf telefonda "yanıt vermiyor" çıkıyordu).
                    withContext(Dispatchers.IO) { setUp() }
                    if (stopped) return@launch
                    begin()
                } catch (e: CancellationException) {
                    throw e
                } catch (t: Throwable) {
                    Log.e(TAG, "çeviri kurulamadı", t)
                    SessionTelemetry.setupFailed()
                    if (!stopped) fail(ServiceTexts.ERROR_NATIVE)
                } finally {
                    // Kurulum sürerken durdurulduysa yalnız o ana kadar kurulanlar kapatılır.
                    if (stopped) closeResources()
                }
            }
        }

        /** Ön koşul (servis.md 1.1); eksikse hata anahtarı. */
        private fun precondition(): String? = when (kind) {
            SourceKind.DEBUG_FRAMES -> null
            SourceKind.REMOTE_PLAY -> {
                val s = Nino.secrets
                if (s.accountId == null || s.console == null) ServiceTexts.ERROR_NOT_PAIRED else null
            }
            // Yakalama kartında PSN, eşleme ve yerel kitaplık gerekmez; yalnız kamera izni.
            SourceKind.CAPTURE_CARD -> if (CaptureCardSource.hasPermission(this@TranslationService)) null else CaptureCardSource.KEY_NO_PERMISSION
            // Xbox: Microsoft girişi ve seçili Xbox gerekir (servis.md 1.1).
            SourceKind.XBOX -> if (com.ninotranslator.mobile.data.SetupFlow.xboxReady(settings, Nino.secrets)) null else ServiceTexts.ERROR_XBOX_SIGN_IN
        }

        private fun fail(key: String) {
            Log.w(TAG, "çeviri başlamadı: $key")
            SessionTelemetry.failed(key)
            stop()
            LiveStatus.update { LiveSnapshot(errorText = texts.get(key)) }
            if (session === this) session = null
            stopForegroundCompat()
            stopSelf()
        }

        // ---- kurulum (IO) ----

        private fun setUp() {
            if (kind == SourceKind.REMOTE_PLAY && !RemotePlayNative.isReady) throw IllegalStateException("yerel kitaplık yok")
            val ctx = this@TranslationService
            val http = UrlConnectionTransport
            // 1. Oyun paketleri (yalnız Türkçe; ayardan kapalıysa hiç açılmaz). Bellek yetmezse paketsiz sürülür.
            if (target.isTurkish && settings.packsEnabled) packs = loadPacks()
            // 2. Sözlük yalnız Türkçede.
            val glossary = if (target.isTurkish) {
                val embedded = runCatching { ctx.assets.open("glossary-en-tr.json").bufferedReader().use { it.readText() } }.getOrNull()
                Glossary.load(embedded, File(filesDir, "glossary"))
            } else Glossary.EMPTY
            val cacheDir = File(filesDir, "Translations")
            val now = { System.currentTimeMillis() }
            val recent = RecentLines(now)
            // 3. Cihaz içi çevirmen her zaman; anahtarlı motor seçildiyse o önce.
            val ml = MlKitTranslator().also { mlkit = it }
            val onDevice = OnDeviceLineTranslator(ml, { LineCache.open(cacheDir, OnDeviceLineTranslator.ENGINE_NAME, it.code) }, { glossary }, recent, now)
            val online = onlineTranslator(http, cacheDir, glossary, now) { text, t -> onDevice.raw(text, t) }
            this.onDevice = onDevice
            this.online = online
            // 5. Ortak havuz (klipte yok).
            val p = if (debug) null else runCatching {
                SharedPool(filesDir, http, BuildConfig.VERSION_NAME, io, shareEnabled = settings.sharePool, install = Nino.installId).also { sp ->
                    sp.language = target.code
                    sp.queue = LineQueue(filesDir, http, BuildConfig.VERSION_NAME, sp.endpoint, install = Nino.installId)
                }
            }.onFailure { Log.w(TAG, "havuz kurulamadı", it) }.getOrNull()
            pool = p
            lineTranslator = LineTranslator(packs, p, onDevice, online, recent, io) { up -> loop?.improve(up) }
            if (target.isTurkish && settings.packsEnabled) refreshPacksLater()
            if (stopped) return
            reader = MlKitTextReader()
            // Ek alan/telefon/harita ve "ekranı çevir" kendi okuyucularıyla (altyazıyı bekletmez).
            sideMl = MlKitTextReader()
            screenMl = MlKitTextReader()
            if (stopped) return
            // 4. Altyazı sunucusu ve TV bağlantısı (sıralı: önceki oturumun kapanışı bitmiş olur).
            val out = TvHub.output(ctx)
            TvHub.serial { TvHub.sessionOpen = true; out.start() }
            tv = out
            out.subtitlesToTv = settings.target == SubtitleTarget.TV
            settings.installedTv?.takeIf { it.brand == TvBrand.ANDROID_TV }?.let { TvHub.hub(ctx).connectTo(it.host, NinoLink.DEFAULT_PORT) }
            LiveStatus.update { it.copy(engineName = engineLabel(online)) }
        }

        /** Havuzdan inmiş ve içe aktarılmış paketler (uygulamayla paket gelmez; hiç yoksa boş kütüphane). */
        private fun loadPacks(): LegacyPackLibrary? = try {
            PoolPacks.store(this@TranslationService).loadLibrary(settings.disabledPacks)
        } catch (e: OutOfMemoryError) {
            Log.w(TAG, "paketler için bellek yetmedi; paketsiz sürülüyor"); null
        } catch (e: Exception) {
            Log.w(TAG, "paketler açılamadı", e); null
        }

        /** Son bakış 24 saatten eskiyse paketler arka planda havuzla eşitlenir; değişen paketler hemen okunur. */
        private fun refreshPacksLater() {
            io.launch {
                val store = PoolPacks.store(this@TranslationService)
                if (!store.isDue(PackStore.Reason.DAILY)) return@launch
                val r = runCatching { store.refresh() }.getOrNull()?.also(AppDiag::packs) ?: return@launch
                if (!r.changed || stopped) return@launch
                val lib = loadPacks() ?: return@launch
                packs = lib
                lineTranslator?.packs = lib
            }
        }

        private fun onlineTranslator(
            http: UrlConnectionTransport, cacheDir: File, glossary: Glossary, now: () -> Long,
            retry: suspend (String, TargetLanguage) -> String,
        ): OnlineLineTranslator? {
            val engine = settings.engine
            if (engine == Engine.FREE) return null
            val service = OnlineService.of(engine.name) ?: return null
            val key = Nino.secrets.apiKey(engine) ?: return null
            val models = runCatching { AiModels.parse(assets.open("ai-models.json").bufferedReader().use { it.readText() }) }.getOrNull()
            val e = OnlineEngines.create(service, key, http, models, settings.aiModel, now) ?: return null
            // DeepL hedef dili desteklemiyorsa motor yok sayılır.
            if (!e.supports(target)) return null
            return OnlineLineTranslator(e, { LineCache.open(cacheDir, e.cacheName, it.code) }, { glossary }, now, retry).also { it.onRequest = AppDiag::providerRequest }
        }

        private fun engineLabel(online: OnlineLineTranslator?): String = when (online?.engine?.service) {
            OnlineService.DEEPL -> "DeepL"
            OnlineService.GEMINI -> "Gemini"
            OnlineService.OPENAI -> "OpenAI"
            OnlineService.CLAUDE -> "Claude"
            null -> texts.get(DemoSession.ENGINE_FREE_KEY)
        }

        // ---- akış ----

        private fun begin() {
            val out = tv ?: NoTvOutput()
            val r = SubtitleRouter(io, out, { System.currentTimeMillis() }, { clock.nowMs() }) { st, id ->
                LiveStatus.update { StatusBook.withPhone(it, st, id) }
            }
            router = r
            val l = ReadingLoop(loopScope, clock, AppDiag.timed(SessionTelemetry.timed(reader!!)), ::translate, LoopListener(r), { Log.i(TAG, it) }, inPack = ::inPack)
            l.config = loopConfig()
            loop = l
            pushStyle(force = true)
            settingsListener = settings.addListener { key -> main.launch { onSetting(key) } }

            out.connectedCount.onEach { n -> LiveStatus.update { it.copy(connectedTvs = n) }; HealthWatch.onTvCount(n) }.launchIn(main)
            out.portProblems.onEach { ports ->
                errors.set(ServiceTexts.ERROR_PORT, ports.firstOrNull()?.let { TextRef(ServiceTexts.ERROR_PORT, it.toString()) })
                SessionTelemetry.portBusy(ports.isNotEmpty())
                publishErrors()
            }.launchIn(main)

            // 7. Ücretsiz modelin indirilmesi (paketler modeli beklemez).
            mlkit?.let { ml ->
                io.launch {
                    ml.ensureModel(target) { warn ->
                        SessionTelemetry.modelMissing(warn)
                        main.launch { if (warn) errors.set(ServiceTexts.ERROR_MODEL) else errors.clear(ServiceTexts.ERROR_MODEL); publishErrors() }
                    }
                }
            }
            startPoolTimers()

            setUpSide(out)
            HealthWatch.sessionStarted(kind, { game.current }, { settings.target == SubtitleTarget.TV })
            SessionTelemetry.started(kind, TvHub.hub(this@TranslationService)) { game.current }
            if (!debug) AppDiag.watchTv(TvHub.hub(this@TranslationService))
            SessionControl.handler = control

            // 8. Görüntü kaynağı.
            val src = createSource() ?: run { fail(ServiceTexts.ERROR_SOURCE_UNAVAILABLE); return }
            source = src
            src.state.onEach(::onSourceState).launchIn(main)
            src.runningGame.onEach { name -> if (game.onPs5(name)) onGameChanged() }.launchIn(main)
            src.start { frame ->
                // Telefon önce aranır: aynı karenin altyazı okuması telefonun yerini bilsin (yeni sahnenin ilk okumasında
                // telefon yazısı altyazıya kaçmasın). Yan okuyucular gereken parçayı çağrının içinde kopyalar.
                if (screen?.active != true) runCatching { gta?.offer(frame) }
                l.offerFrame(frame)
                SessionTelemetry.onFrame()
                runCatching { screen?.offer(frame) }
                runCatching { extras?.offer(frame) }
                runCatching { identifier?.offer(frame) }
            }

            // Android TV bulma (mDNS): telefon bulur ve bağlanır.
            TvAutoConnect(io, { TvFinders.current }, { TvHub.hub(this@TranslationService) }, { LiveStatus.state.value.connectedTvs }).start()
            // Oyun sorma kartı 15 sn'de bir; GTA 6 okuma ayarları yarım saniyede bir.
            main.launch {
                while (isActive) {
                    if (askCard.check(SystemClock.elapsedRealtime(), game.current != null, settings.askGame, settings.sharePool && !debug)) publishAskCard()
                    delay(GameAskCard.CHECK_MS)
                }
            }
            main.launch { while (isActive) { delay(500); refreshGtaConfig() } }

            // 9. "Çeviri başladı" (TV balonu; sonradan bağlanan TV de kısa süre görür).
            io.launch { runCatching { out.started() } }

            // Bekletme süreleri ve telefon satırının süresi.
            loopScope.launch {
                while (isActive) { delay(TICK_MS); l.tick(); r.tick() }
            }
            // 10. Kare sayısı 2 sn'de bir.
            main.launch {
                while (isActive) { delay(2_000); val n = src.frameCount(); HealthWatch.onFrames(n); LiveStatus.update { it.copy(framesReceived = n) } }
            }
        }

        /** Yan okuyucular (okuma.md 9–12). */
        private fun setUpSide(out: TvOutput) {
            val tvOut = { tv ?: out }
            val ch = ScreenChannel(io, clock, tvOut).also { channel = it }
            val side = SharedReader(sideMl ?: return)
            val screenReader = SharedReader(screenMl ?: return, timeoutMs = 10_000)
            extras = ExtraAreaReader(io, clock, side, { settings.extraAreas }, ::translateSide, tvOut)
            screen = ScreenTranslator(io, screenReader, ch, texts, tvOut, { streamingNow }, { pushStyle(force = true) }, ::batchSide, ::translateSide)
            // Telefon ve harita klipte de okunur (okuma gerçekteki gibi); oyun teması ve oyun tanıma klipte kapalı kalır.
            run {
                gta = GtaReader(
                    io, clock, side, ch, pool, target, filesDir,
                    active = ::gtaActive, poolFirst = { poolFirst }, blocked = { screen?.active == true }, game = { game.current }, sharePool = { settings.sharePool },
                    deviceTranslate = { t -> onDevice?.translate(t, target) },
                    onGta6Seen = { main.launch { if (game.current == null && game.onScreen(GTA6_ID)) onGameChanged() } },
                    onRulesChanged = { main.launch { refreshGtaConfig() } },
                )
            }
            if (!debug) {
                pool?.let { p ->
                    identifier = ScreenGameIdentifier(io, p, System::currentTimeMillis,
                        allowed = { ScreenIdentifyGate.allowed(settings.sharePool, game.userGame != null, debug, game.ps5Game != null, game.packGame != null) },
                        onGame = { g -> main.launch { if (game.onScreen(g)) onGameChanged() } })
                }
            }
        }

        /** Telefon ve harita yalnız havuz öncelikli oyunda (ya da oyun bilinmiyorken havuz dilinde) aranır. */
        private fun gtaActive(): Boolean {
            if (poolFirst) return true
            // Havuz yoksa (klip, kurulamadı) varsayılan havuz ayarı: GTA 6 Türkçede havuz önceliklidir.
            return game.unknownOrGuessed && (pool?.isPoolFirst(GTA6_ID, target.code) ?: PoolConfig().isPoolFirst(GTA6_ID, target.code))
        }

        private fun refreshGtaConfig() {
            val g = gta ?: return
            val now = Triple(g.blackout(), g.subtitlesSuppressed(), gtaActive())
            if (now == lastGtaConfig) return
            lastGtaConfig = now
            loop?.config = loopConfig()
        }

        private val control = object : SessionControl.Handler {
            override fun toggleScreen() { main.launch { screen?.toggle() } }
            override fun clearScreen() { main.launch { screen?.clear() } }
            override fun chooseGame(game: String?) { main.launch { onUserGame(game) } }
            override fun closeGameCard(neverAgain: Boolean) { main.launch { askCard.close(neverAgain); publishAskCard() } }
            override fun openGameCard() { main.launch { askCard.openManually(); publishAskCard() } }
            override fun testSubtitle(text: String) { main.launch { sendTestSubtitle(text) } }
            override fun reloadPacks() { io.launch { reloadPacksNow() } }
        }

        /** Deneme altyazısı: TV hedefinde TV'ye, telefonda canlı satıra; 8 sn sonra kalkar. */
        private fun sendTestSubtitle(text: String) {
            if (stopped) return
            if (settings.target == SubtitleTarget.TV) {
                val out = tv ?: return
                io.launch {
                    runCatching { out.show(ShowPayload(TestSubtitles.ID, text, durationMs = TestSubtitles.DURATION_MS)) }
                    delay(TestSubtitles.DURATION_MS.toLong())
                    runCatching { out.clear(TestSubtitles.ID) }
                }
            } else {
                LiveStatus.update { it.copy(currentLine = text, currentLineId = it.currentLineId + 1) }
                main.launch {
                    delay(TestSubtitles.DURATION_MS.toLong())
                    LiveStatus.update { if (it.currentLine == text) it.copy(currentLine = null, currentLineId = it.currentLineId + 1) else it }
                }
            }
        }

        /** Paketler yeniden okunur; okunamazsa eskisi kalır. Paketler kapalıysa ya da dil Türkçe değilse bir şey yapmaz. */
        private fun reloadPacksNow() {
            if (stopped || !target.isTurkish || !settings.packsEnabled) return
            val lib = loadPacks() ?: return
            if (stopped) return
            packs = lib
            lineTranslator?.packs = lib
            Log.i(TAG, "paketler yeniden okundu: ${lib.packs.size}")
        }

        private fun consoleLabel(): String = when (kind) {
            SourceKind.REMOTE_PLAY -> Nino.secrets.console?.name?.takeIf { it.isNotBlank() } ?: "PS5"
            SourceKind.CAPTURE_CARD -> "capture-card"
            SourceKind.XBOX -> settings.xboxConsole?.id ?: "xbox"
            SourceKind.DEBUG_FRAMES -> "debug"
        }

        private fun publishAskCard() {
            val titles = packs?.packs?.map { it.title }?.filter { it.isNotBlank() && it.lowercase() != "genel" }.orEmpty()
            // Kayıtlı asıl kimlik ("gta-6") kartta okunur adla ("GTA 6") görünür.
            val last = settings.lastGame(consoleLabel())?.let { if (it in GameIds.NAMES) GameIds.name(it) else it }
            val sug = GameAskCard.suggestions(last, titles)
            LiveStatus.update { it.copy(askGameCard = askCard.open, askGameSuggestions = sug) }
        }

        /** Kullanıcının seçimi konsolun adıyla saklanır; sonraki oturumda kartın ilk önerisi olur. */
        private fun onUserGame(g: String?) {
            val name = g?.trim()?.takeIf { it.isNotEmpty() }
            val changed = game.onUserChoice(name)
            if (name != null && !debug) settings.setLastGame(consoleLabel(), name)
            askCard.close(neverAgain = false)
            LiveStatus.update { it.copy(manualGame = name) }
            publishAskCard()
            if (changed) onGameChanged()
        }

        /** Ek alan ve ekran yazısı: aynı paketler ve motor; havuza önerilmez, altyazı bağlamına girmez. */
        private suspend fun translateSide(text: String): LineResult? {
            val lt = lineTranslator ?: return null
            val ts = TranslationSettings(
                target = target, packsEnabled = settings.packsEnabled, sharePool = settings.sharePool,
                showSpeakerNames = settings.showSpeakerNames, manualGame = game.userGame, game = game.current, fromClip = debug, sideText = true,
            )
            return withContext(Dispatchers.Default) { lt.translate(text, ts) }
        }

        /** Yapay zekâ çevirmeninde "ekranı çevir" bütün parçaları tek istekte; havuz öncelikli oyunda kullanılmaz. */
        private suspend fun batchSide(parts: List<String>): List<String>? {
            val e = online?.engine ?: return null
            if (poolFirst || e.service == OnlineService.DEEPL || !e.supports(target)) return null
            return runCatching { e.translateAsync(OnlineRequest(parts, target, game = game.current)) }.getOrNull()
        }

        private fun createSource(): FrameSource? = when (kind) {
            SourceKind.DEBUG_FRAMES -> DebugSources.factory?.create(this@TranslationService, main)
            SourceKind.REMOTE_PLAY -> {
                val s = Nino.secrets
                val reg = s.console ?: return null
                val account = s.accountId ?: return null
                val console = PairedPs5(reg.host, reg.name, reg.registKey, reg.morning)
                RemotePlaySource(RemotePlayTarget(console, account, s.loginPasscode), { moved -> s.updateConsoleHost(moved.host) }, main)
            }
            SourceKind.CAPTURE_CARD -> CaptureCardSource(this@TranslationService)
            SourceKind.XBOX -> settings.xboxConsole?.let {
                com.ninotranslator.mobile.xbox.XboxStreamSource(this@TranslationService, it, com.ninotranslator.mobile.xbox.XboxLive.chain)
            }
        }

        /** Paketteki satır bekletilmez (yalnız Türkçe, paketler açık, oyun havuz öncelikli değil). */
        private fun inPack(text: String): Boolean =
            target.isTurkish && settings.packsEnabled && !poolFirst && packs?.find(text, null, settings.showSpeakerNames) != null

        private suspend fun translate(text: String): LineResult? {
            val lt = lineTranslator ?: return null
            val ts = TranslationSettings(
                target = target, packsEnabled = settings.packsEnabled, sharePool = settings.sharePool,
                showSpeakerNames = settings.showSpeakerNames, manualGame = game.userGame, game = game.current, fromClip = debug,
            )
            return withContext(Dispatchers.Default) { lt.translate(text, ts) }
        }

        private inner class LoopListener(private val r: SubtitleRouter) : ReadingLoop.Listener {
            override fun onReading(raw: List<LiveLine>, reading: LiveReading, region: LiveRegion) {
                if (debug || game.current != null || raw.isEmpty()) return
                if (Gta6Hints.looksLikeGta6(raw.map { it.text })) main.launch { if (game.onScreen(GTA6_ID)) onGameChanged() }
            }

            override fun onShow(line: ShownLine) {
                r.show(line)
                if (line.kind == LiveShowKind.NEW) HealthWatch.onLine(line.translateMs)
                SessionTelemetry.onShow(line)
                AppDiag.shown(line)
                LiveStatus.update { StatusBook.onShown(it, line) { id -> packs?.pack(id)?.title } }
                main.launch { if (errors.has(ServiceTexts.ERROR_TRANSLATION)) { errors.clear(ServiceTexts.ERROR_TRANSLATION); publishErrors() } }
                io.launch { writeHistory(line) }
                if (!debug && line.kind == LiveShowKind.NEW) {
                    line.box?.let { b -> io.launch { learnLayout(b) } }
                    val unique = line.engine != null && packs?.guessedPackId == line.engine
                    main.launch { if (game.onShown(line.origin, line.engine, unique)) onGameChanged() else updatePoolFirst() }
                }
            }

            override fun onClear(id: Int) = r.clear(id)

            override fun onTranslationFailed(source: String) {
                main.launch { errors.set(ServiceTexts.ERROR_TRANSLATION); publishErrors() }
                SessionTelemetry.onTranslationFailed()
                AppDiag.translationFailed()
            }
        }

        /** Geçmiş (servis.md 11): aynı satırın yeniden okuması yeni kayıt açmaz, son kaydı günceller. */
        private fun writeHistory(line: ShownLine) {
            if (line.text.isBlank()) return
            val h = Nino.history
            val origin = if (line.fromPack) HistoryOrigin.PACK else HistoryOrigin.ENGINE
            // Geri getirilen satır zaten geçmişte.
            if (line.kind == LiveShowKind.RESTORED) return
            val last = h.entries.value.firstOrNull()
            val same = last != null && (last.source == line.source ||
                (line.kind == LiveShowKind.NEW && LiveStabilizer.isGrowthOrCorrection(last.source, line.source)))
            if (same) h.remove(last!!.id)
            h.add(line.source, line.text, origin)
        }

        /** Altyazı yerini öğrenme (okuma.md 3): oyun başına kalıcı örnekler. */
        private fun learnLayout(box: LiveBox) {
            if (!SubtitleBand.accepts(box)) return
            Nino.subtitleLayout.record(layoutKey(), com.ninotranslator.mobile.data.SubtitleBand(box.top, box.bottom))
            main.launch { loop?.config = loopConfig() }
        }

        private fun layoutKey(): String = when {
            poolFirst -> SubtitleLayoutStore.GTA6
            else -> (game.packGame ?: game.current?.let { packs?.packForGame(it)?.id })?.let(SubtitleLayoutStore::key) ?: SubtitleLayoutStore.GENERIC
        }

        private fun loopConfig(): LoopConfig {
            val reg = settings.region
            val samples = if (debug) emptyList() else Nino.subtitleLayout.samples(layoutKey()).map { LiveBox(0.0, it.top, 1.0, it.bottom) }
            return LoopConfig(
                region = LiveRegion(reg.top, reg.bottom, reg.left, reg.right),
                band = SubtitleBand.learn(samples),
                bandHeights = samples.map { it.height },
                poolFirstGame = poolFirst,
                fastDetection = settings.fastSubtitleDetection,
                showSpeakerNames = settings.showSpeakerNames,
                target = target,
                subtitlesSuppressed = gta?.subtitlesSuppressed() == true,
                blackout = gta?.blackout().orEmpty(),
                dropLine = gta?.let { g -> if (gtaActive()) g.dropLine else null },
            )
        }

        private fun updatePoolFirst() {
            val pf = !debug && pool?.isPoolFirst(game.current, target.code) == true
            if (pf != poolFirst) {
                poolFirst = pf
                loop?.config = loopConfig()
            }
            // Oyun bu oturumda tanınmadıysa son oynanan oyunun teması kalır; hatırlanan değer yalnız gerçek oyundan yazılır.
            val shown = if (game.current == null) settings.lastGamePoolFirst else pf
            if (game.current != null && !debug) settings.lastGamePoolFirst = pf
            LiveStatus.update { it.copy(poolFirstGame = !debug && shown, game = game.current) }
        }

        private fun onGameChanged() {
            if (askCard.onGameKnown()) publishAskCard()
            updatePoolFirst()
            loop?.config = loopConfig()
            val g = game.current
            pool?.let { p -> io.launch { runCatching { p.sync(g, force = true) } } }
        }

        private fun startPoolTimers() {
            val p = pool ?: return
            io.launch {
                runCatching { p.refreshConfig(force = true) }
                DownloadCounter.record(p.downloads)
                main.launch { updatePoolFirst() }
                while (isActive) {
                    // Sunucu ayarı en çok 600 sn'de bir; toplam indirme sayısı da bu cevaptan (ceviri.md 6.8).
                    runCatching { p.refreshConfig(); DownloadCounter.record(p.downloads) }
                    runCatching { p.sync(game.current); p.ping(game.current) }
                    delay(60_000)
                }
            }
            io.launch {
                delay(5_000)
                while (isActive) { runCatching { p.queue?.tick() }; delay(60_000) }
            }
        }

        // ---- kaynak durumu (servis.md 2) ----

        private fun onSourceState(st: SourceState) {
            reasons.onState(st)
            streamingNow = st == SourceState.Streaming
            HealthWatch.onSourceState(st)
            SessionTelemetry.onSourceState(st)
            val phase = PhaseTexts.phase(st, kind)
            errors.set("capture", reasons.captureProblem)
            errors.set("xbox", com.ninotranslator.mobile.xbox.XboxTexts.help(st, settings.xboxQuality))
            LiveStatus.update {
                it.copy(
                    streaming = st == SourceState.Streaming,
                    phaseText = phase?.let(texts::get) ?: it.phaseText,
                    connectReason = reasons.reason?.let(texts::get),
                    errorText = errors.top?.let(texts::get),
                )
            }
        }

        private fun publishErrors() = LiveStatus.update { it.copy(errorText = errors.top?.let(texts::get)) }

        // ---- ayar değişiklikleri (servis.md 3.9) ----

        private fun onSetting(key: String) {
            if (stopped) return
            when (key) {
                Settings.K.TARGET -> tv?.subtitlesToTv = settings.target == SubtitleTarget.TV
                Settings.K.SHARE_POOL -> pool?.let { p -> if (settings.sharePool) p.shareEnabled = true else p.disable() }
                // Paket açılıp kapatılınca da paketler yeniden okunur.
                Settings.K.DISABLED_PACKS -> io.launch { reloadPacksNow() }
            }
            loop?.config = loopConfig()
            pushStyle(force = false)
        }

        private fun pushStyle(force: Boolean) {
            val m = tvStyleOf(settings)
            if (!force && m == lastStyle) return
            lastStyle = m
            tv?.setStyle(m)
        }

        // ---- kilitler (servis.md 1.4) ----

        private fun acquireLocks() {
            runCatching {
                wakeLock = getSystemService(PowerManager::class.java).newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "nino:translation")
                    .apply { setReferenceCounted(false); acquire() }
            }
            runCatching {
                @Suppress("DEPRECATION")
                val mode = if (Build.VERSION.SDK_INT >= 29) WifiManager.WIFI_MODE_FULL_LOW_LATENCY else WifiManager.WIFI_MODE_FULL_HIGH_PERF
                wifiLock = applicationContext.getSystemService(WifiManager::class.java).createWifiLock(mode, "nino:translation")
                    .apply { setReferenceCounted(false); acquire() }
            }
        }

        private fun releaseLocks() {
            runCatching { wakeLock?.takeIf { it.isHeld }?.release() }
            runCatching { wifiLock?.takeIf { it.isHeld }?.release() }
            wakeLock = null; wifiLock = null
        }

        // ---- durdurma (servis.md 1.2) ----

        fun stop() {
            if (stopped) return
            stopped = true
            if (SessionControl.handler === control) SessionControl.handler = null
            loop?.stop()
            extras?.stop(); gta?.stop(); screen?.clear(); channel?.close()
            HealthWatch.sessionEnded()
            SessionTelemetry.ended()
            runCatching { source?.stop() }
            settingsListener?.close()
            if (settings.translating) {
                settings.translating = false
                settings.lastSessionMs = System.currentTimeMillis() - startedAt
            }
            releaseLocks()
            job.cancel()
            loopScope.cancel()
            closeResources()
            loopExecutor.shutdown()
            reasons.reset()
            LiveStatus.resetKeepingError()
        }

        /** Kurulanları kapatır (iki kez çağrılabilir). TV'ye "durdu" ve kapanış sıralı kuyrukta. */
        @Synchronized
        private fun closeResources() {
            val out = tv; tv = null
            if (out != null) TvHub.serialAsync {
                runCatching { kotlinx.coroutines.runBlocking { out.regionClearAll(); out.screenClear(); out.stopped() } }
                TvHub.sessionOpen = false
                runCatching { out.close() }
            }
            val p = pool; pool = null
            if (p != null) CoroutineScope(Dispatchers.IO).launch { runCatching { p.queue?.tick() } }
            reader?.let { runCatching { it.close() } }; reader = null
            mlkit?.let { runCatching { it.close() } }; mlkit = null
            sideMl?.let { runCatching { it.close() } }; sideMl = null
            screenMl?.let { runCatching { it.close() } }; screenMl = null
        }
    }

    companion object {
        private const val TAG = "Nino"
        const val CHANNEL_ID = "translation"
        private const val NOTIFICATION_ID = 4780
        private const val TICK_MS = 200L
        /** Ekrandan GTA 6 işareti görülünce oyun kimliği (havuzun öncelikli oyun listesindeki biçim). */
        const val GTA6_ID = "gta-6"
        const val ACTION_START = "com.ninotranslator.mobile.action.START_TRANSLATION"
        const val ACTION_STOP = "com.ninotranslator.mobile.action.STOP_TRANSLATION"
        const val EXTRA_DEBUG_FRAMES = "debugFrames"

        fun start(context: Context, debugFrames: Boolean = false) {
            val i = Intent(context, TranslationService::class.java).setAction(ACTION_START).putExtra(EXTRA_DEBUG_FRAMES, debugFrames)
            ContextCompat.startForegroundService(context, i)
        }

        fun stop(context: Context) {
            if (!LiveStatus.state.value.running) { LiveStatus.resetKeepingError(); return }
            context.startService(Intent(context, TranslationService::class.java).setAction(ACTION_STOP))
        }
    }
}

/** TV olayının günlük satırı. Saf; birim testi var. */
internal fun tvEventLine(e: DisplayEvent): String = when (e) {
    is DisplayEvent.Connected -> "TV bağlandı: ${e.display.kind.name.lowercase()}"
    is DisplayEvent.Dropped -> "TV koptu: ${e.display.kind.name.lowercase()}, neden ${e.reason.name.lowercase()}, ${e.afterMs / 1000} sn bağlı kaldı"
    is DisplayEvent.ConnectFailed -> "Android TV'ye bağlanılamadı: ${e.reason.name.lowercase()}"
}

/** Süreç boyunca tek DisplayHub (TV bağlantıları ve altyazı sunucuları). */
object TvHub {
    /** Açma/kapama sırası: önceki oturumun geç kapanışı yeni oturumun sunucusunu kapatmasın. */
    private val lifecycle = Executors.newSingleThreadExecutor { r -> Thread(r, "nino-tv-hub") }

    /** Sırada çalıştırır ve bitmesini bekler (IO iş parçacığından). */
    fun serial(block: () -> Unit) { lifecycle.submit(Runnable { block() }).get() }

    fun serialAsync(block: () -> Unit) { lifecycle.execute(Runnable { block() }) }

    @Volatile private var instance: DisplayHub? = null
    @Volatile private var out: HubTvOutput? = null
    /** Çeviri oturumu bağlantıyı açtı (yalnız [serial] içinde değişir). */
    @Volatile internal var sessionOpen = false
    /** Deneme altyazısı için çeviri yokken açıldı. */
    @Volatile private var idleOpen = false

    /** Çeviri yokken deneme altyazısı için sunucuları açar; oturum açıksa false (oturum gönderir). */
    fun openIdle(): Boolean {
        var ok = false
        serial { if (!sessionOpen) { instance?.start(); idleOpen = instance != null; ok = idleOpen } }
        return ok
    }

    /** [openIdle]'ın açtığını kapatır; bu arada çeviri başladıysa dokunmaz. */
    fun closeIdle() {
        serial { if (idleOpen && !sessionOpen) runCatching { instance?.close() }; idleOpen = false }
    }

    fun hub(context: Context): DisplayHub = instance ?: synchronized(this) {
        instance ?: DisplayHub(DisplayHub.Config(
            deviceName = Build.MODEL ?: "Android",
            clientVersion = "nino-android/${BuildConfig.VERSION_NAME}",
            deviceId = Nino.installId,
            appVersion = BuildConfig.VERSION_NAME,
        )).also { instance = it; logEvents(it) }
    }

    /** TV bağlanma/kopmaları nedeniyle günlüğe (ad ve adres yazılmaz). */
    private fun logEvents(hub: DisplayHub) {
        CoroutineScope(SupervisorJob() + Dispatchers.Default).launch {
            hub.events.collect { e -> Log.i("NinoTv", tvEventLine(e)) }
        }
    }

    /** Bağlı TV'lerden modelini bildiren ilkinin modeli (cihaz özeti). */
    fun connectedModel(): String? = instance?.displays?.value?.firstNotNullOfOrNull { it.model }

    fun output(context: Context): HubTvOutput = out ?: synchronized(this) {
        out ?: HubTvOutput(hub(context), CoroutineScope(SupervisorJob() + Dispatchers.Default)).also { out = it }
    }
}
