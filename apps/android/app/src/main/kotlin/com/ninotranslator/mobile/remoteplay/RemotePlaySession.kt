// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.remoteplay

import android.os.Build
import android.os.SystemClock
import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.asCoroutineDispatcher
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.nio.ByteBuffer
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger

/** Oturum durumu. Nedenler strings anahtarı adıdır (`phase_network` gibi); [detail] anahtarın %1$s değeri. */
sealed interface RemotePlayState {
    data object Idle : RemotePlayState
    data object Preparing : RemotePlayState
    data object Connecting : RemotePlayState
    data object Streaming : RemotePlayState
    /** Kopuk; [inMs] sonra yeniden denenecek. Neden ana ekranda kalır. */
    data class Reconnecting(val reasonKey: String, val detail: String? = null, val inMs: Long = 0) : RemotePlayState
    /** Durdu, yeniden denenmez (kayıt geçersiz, Uzaktan Oynama kapalı, şifre, görüntü yok, kütüphane yok…). */
    data class Failed(val reasonKey: String, val detail: String? = null) : RemotePlayState
}

/** Tanı olayı (sağlık ekranı ve sorun bildirimi için): ne yapıldığı, art arda görüntüsüz oturum sayısı, kare sayısı. */
data class RemotePlayDiagnostic(val action: String, val streak: Int, val frames: Long)

/** Oturumun girdileri. Veri katmanından okunup verilir; bu sınıf ayarlara dokunmaz. */
class RemotePlayTarget(
    val console: PairedPs5,
    val accountId: ByteArray,
    /** `secrets/loginPasscode`; yoksa null. */
    val loginPasscode: String?,
)

/**
 * PS5 Remote Play oturumu: bulma → (gerekirse) uyandırma → oturum → görüntü bekçisi → yeniden bağlanma.
 * Bütün işler tek sıralı kuyrukta yürür; her başlatma "kuşak" numarasını artırır, eski kuşağın olayları yok sayılır.
 *
 * @param onHostChanged PS5 yeni adreste bulununca çağrılır; veri katmanı kaydı kalıcı olarak günceller.
 * @param frameListener kareler (en çok saniyede 5). Çözücünün çıkış iş parçacığında; kare yalnız çağrı süresince geçerli.
 */
class RemotePlaySession(
    private val onHostChanged: (PairedPs5) -> Unit = {},
    private val frameListener: RemotePlayFrameListener,
    private val finder: Ps5Finder = Ps5Finder(),
    private val manufacturer: String? = Build.MANUFACTURER,
    private val width: Int = 1920,
    private val height: Int = 1080,
) {
    private val executor = Executors.newSingleThreadExecutor { r -> Thread(r, "nino-rp-session") }
    private val scope = CoroutineScope(SupervisorJob() + executor.asCoroutineDispatcher())
    private val generation = AtomicInteger(0)

    private val _state = MutableStateFlow<RemotePlayState>(RemotePlayState.Idle)
    val state: StateFlow<RemotePlayState> = _state.asStateFlow()
    private val _diagnostics = MutableSharedFlow<RemotePlayDiagnostic>(extraBufferCapacity = 16)
    val diagnostics: SharedFlow<RemotePlayDiagnostic> = _diagnostics.asSharedFlow()
    private val _runningApp = MutableStateFlow<FoundPs5?>(null)
    /** Bağlıyken PS5'e sorulan son durum (çalışan oyunun kimliği ve adı; ana ekranda boş). Havuzda oyunu tanımak için. */
    val runningApp: StateFlow<FoundPs5?> = _runningApp.asStateFlow()

    // Aşağıdakiler yalnız kuyrukta değişir.
    private var target: RemotePlayTarget? = null
    @Volatile private var handle = 0L
    private val backoff = ReconnectBackoff()
    private val watchdog = FrameWatchdog()
    private var lastSearchAnswered = true
    private var lastRelocateScanAt = 0L
    private var keepSoftware: Boolean? = null
    private var watchdogJob: Job? = null
    private var retryJob: Job? = null
    private var runningAppJob: Job? = null

    /** Gelen kare sayısı (tanı amaçlı; bu oturumda çözülen). */
    fun frameCount(): Long = handle.let { if (it != 0L) RemotePlayNative.nativeSessionFrames(it) else 0L }

    /** Başlatır (bloklamaz). Geri çekilme ve görüntüsüz oturum sayacı sıfırlanır. */
    fun start(target: RemotePlayTarget) {
        val gen = generation.incrementAndGet()
        _state.value = RemotePlayState.Preparing
        scope.launch {
            this@RemotePlaySession.target = target
            resetForUserAction()
            connect(gen)
        }
    }

    /** Elle yeniden bağlan (ör. ağ değişince): oturumu kapatır, geri çekilme ve bekçiyi sıfırlar, hemen bağlanır. */
    fun reconnectNow() {
        val gen = generation.incrementAndGet()
        scope.launch {
            if (target == null) return@launch
            resetForUserAction()
            connect(gen)
        }
    }

    /** Durdurur (bloklamaz). */
    fun stop() {
        generation.incrementAndGet()
        scope.launch {
            cancelTimers()
            closeSession()
            target = null
            _state.value = RemotePlayState.Idle
        }
    }

    /** Durdurur ve kuyruğu kapatır; bu nesne bir daha kullanılmaz. */
    fun release() {
        stop()
        scope.launch { scope.cancel() }
        executor.shutdown()
    }

    // --- kuyruk içi ---

    private fun resetForUserAction() {
        cancelTimers()
        closeSession()
        backoff.reset()
        watchdog.resetAll()
        keepSoftware = null
    }

    private fun cancelTimers() {
        watchdogJob?.cancel(); watchdogJob = null
        runningAppJob?.cancel(); runningAppJob = null
        retryJob?.cancel(); retryJob = null
    }

    private fun current(gen: Int) = gen == generation.get()

    private suspend fun connect(gen: Int) {
        if (!current(gen)) return
        val t = target ?: return
        _state.value = RemotePlayState.Connecting
        if (!RemotePlayNative.isReady) {
            _state.value = RemotePlayState.Failed("error_native")
            return
        }
        if (!t.console.isValid || !PsnAccountId.isValid(t.accountId)) {
            _state.value = RemotePlayState.Failed("error_not_paired")
            return
        }
        var console = t.console
        var found = finder.findBlocking(console.host, Ps5Finder.SAVED_ADDRESS_SEARCH_MS).firstOrNull()
        if (!current(gen)) return
        if (found == null && now() - lastRelocateScanAt >= RELOCATE_COOLDOWN_MS) {
            lastRelocateScanAt = now()
            val all = finder.findBlocking(null, Ps5Finder.RELOCATE_SEARCH_MS)
            if (!current(gen)) return
            HostRelocation.pick(all, console.name)?.let { pick ->
                found = pick
                if (pick.address != console.host) {
                    Log.i(TAG, "PS5 yeni adreste bulundu")
                    console = PairedPs5(pick.address, console.name, console.registKey, console.morning)
                    target = RemotePlayTarget(console, t.accountId, t.loginPasscode)
                    runCatching { onHostChanged(console) }
                }
            }
        }
        lastSearchAnswered = found != null
        // Yanıt yoksa da bağlanmayı dene; "bulunamadı" kuralı için bilgi saklandı.
        if (found?.awake == false) {
            if (!wake(gen, console)) return
        }
        openSession(gen, console, t)
    }

    /** true: uyandı (ya da uyandırma kimliği yok, yine de denenir). false: vazgeçildi ya da kuşak değişti. */
    private suspend fun wake(gen: Int, console: PairedPs5): Boolean {
        val credential = WakeCredential.fromRegistKey(console.registKey) ?: return true
        Log.i(TAG, "PS5 dinlenmede, uyandırılıyor")
        RemotePlayNative.nativeWakeup(console.host, credential)
        val deadline = now() + WAKE_TIMEOUT_MS
        while (now() < deadline) {
            delay(WAKE_POLL_MS)
            if (!current(gen)) return false
            val f = finder.findBlocking(console.host, Ps5Finder.SAVED_ADDRESS_SEARCH_MS).firstOrNull()
            if (!current(gen)) return false
            if (f?.awake == true) return true
        }
        scheduleRetry(gen, "phase_asleep", null)
        return false
    }

    private fun openSession(gen: Int, console: PairedPs5, t: RemotePlayTarget) {
        if (!current(gen)) return
        val software = keepSoftware ?: DecoderChoice.startWithSoftware(manufacturer, watchdog.noPictureSessions)
        keepSoftware = null
        val h = RemotePlayNative.nativeOpenSession(
            console.host, console.registKey, console.morning, t.accountId, width, height, software,
            FRAME_INTERVAL_MS, Listener(gen),
        )
        if (h == 0L) {
            val err = RemotePlayNative.nativeOpenError()
            Log.e(TAG, "Oturum açılamadı: $err")
            scheduleRetry(gen, "phase_reconnecting", err)
            return
        }
        handle = h
    }

    private fun closeSession() {
        watchdogJob?.cancel(); watchdogJob = null
        watchdog.onDisconnected()
        val h = handle
        if (h != 0L) {
            handle = 0L
            RemotePlayNative.nativeCloseSession(h)
        }
    }

    private fun scheduleRetry(gen: Int, reasonKey: String, detail: String?) {
        if (!current(gen)) return
        closeSession()
        val next = generation.incrementAndGet()
        val wait = backoff.nextDelayMs()
        _state.value = RemotePlayState.Reconnecting(reasonKey, detail, wait)
        retryJob?.cancel()
        retryJob = scope.launch {
            delay(wait)
            connect(next)
        }
    }

    private fun fail(gen: Int, reasonKey: String, detail: String? = null) {
        if (!current(gen)) return
        generation.incrementAndGet()
        cancelTimers()
        closeSession()
        _state.value = RemotePlayState.Failed(reasonKey, detail)
    }

    /** Bekçi takılma bulunca hemen (geri çekilmesiz) yeniden kurar. */
    private fun rebuild(gen: Int, sameDecoder: Boolean) {
        if (!current(gen)) return
        val t = target ?: return
        keepSoftware = if (sameDecoder && handle != 0L) RemotePlayNative.nativeSessionSoftware(handle) else null
        closeSession()
        val next = generation.incrementAndGet()
        _state.value = RemotePlayState.Reconnecting("phase_reconnecting")
        scope.launch { if (current(next)) openSession(next, t.console, t) }
    }

    private fun onConnected(gen: Int) {
        if (!current(gen)) return
        backoff.reset()
        _state.value = RemotePlayState.Streaming
        watchdog.onConnected(now())
        startRunningAppQuery()
        watchdogJob?.cancel()
        watchdogJob = scope.launch {
            while (current(gen)) {
                delay(WATCHDOG_TICK_MS)
                if (!current(gen) || handle == 0L) break
                val frames = RemotePlayNative.nativeSessionFrames(handle)
                when (val v = watchdog.tick(now(), frames)) {
                    FrameWatchdog.Verdict.Ok -> Unit
                    FrameWatchdog.Verdict.Stalled -> {
                        _diagnostics.tryEmit(RemotePlayDiagnostic("rebuild_same_decoder", 0, frames))
                        rebuild(gen, sameDecoder = true)
                        break
                    }
                    is FrameWatchdog.Verdict.NoPicture -> {
                        _diagnostics.tryEmit(RemotePlayDiagnostic("rebuild_other_decoder", v.sessions, frames))
                        rebuild(gen, sameDecoder = false)
                        break
                    }
                    is FrameWatchdog.Verdict.GiveUp -> {
                        _diagnostics.tryEmit(RemotePlayDiagnostic("give_up", v.sessions, frames))
                        fail(gen, "phase_no_picture")
                        break
                    }
                }
            }
        }
    }

    /** Çalışan oyunu sorma: ilki 30 sn sonra, sonra 2 dk'da bir; kayıtlı adres 2 sn aranır. Kuyruğu bloklamaz. */
    private fun startRunningAppQuery() {
        if (runningAppJob?.isActive == true) return
        runningAppJob = scope.launch(Dispatchers.IO) {
            delay(RUNNING_APP_FIRST_MS)
            while (true) {
                val host = target?.console?.host ?: break
                finder.findBlocking(host, Ps5Finder.SAVED_ADDRESS_SEARCH_MS).firstOrNull()?.let { _runningApp.value = it }
                delay(RUNNING_APP_EVERY_MS)
            }
        }
    }

    private fun onPinRequest(gen: Int, previousIncorrect: Boolean) {
        if (!current(gen)) return
        if (previousIncorrect) {
            // Aynı şifre yeniden gönderilmez.
            fail(gen, "phase_passcode_incorrect")
            return
        }
        val pin = LoginPasscode.normalize(target?.loginPasscode)
        if (pin == null || handle == 0L) {
            fail(gen, "phase_passcode")
            return
        }
        RemotePlayNative.nativeSetLoginPin(handle, pin.toByteArray(Charsets.US_ASCII))
    }

    private fun onQuit(gen: Int, reason: Int, text: String?) {
        if (!current(gen)) return
        val lines = if (handle != 0L) RemotePlayNative.nativeSessionErrors(handle).toList() else emptyList()
        val end = SessionEndReasons.classify(reason, text, lines)
        val host = target?.console?.host
        if (end.kind == EndKind.STOPPED) {
            closeSession()
            scheduleRetry(gen, "phase_reconnecting", null)
            return
        }
        val key = SessionEndReasons.phaseKey(end, lastSearchAnswered, host) ?: "phase_reconnecting"
        val detail = SessionEndReasons.phaseDetail(key, end, host)
        if (!end.kind.retry) fail(gen, key, detail) else scheduleRetry(gen, key, detail)
    }

    private fun now() = SystemClock.elapsedRealtime()

    /** Yerel geri çağrılar: olaylar kuyruğa atılır (kütüphane durum kilidini tutarken çağırır); kareler doğrudan. */
    private inner class Listener(private val gen: Int) : NativeSessionListener {
        override fun onConnected() { scope.launch { onConnected(gen) } }
        override fun onLoginPinRequest(previousIncorrect: Boolean) { scope.launch { onPinRequest(gen, previousIncorrect) } }
        override fun onQuit(reason: Int, text: String?) { scope.launch { onQuit(gen, reason, text) } }

        override fun onFrame(buffer: ByteBuffer, width: Int, height: Int, stride: Int, colorFormat: Int,
                             hasChroma: Boolean, pts: Long) {
            if (!current(gen)) return
            val frame = RemotePlayFrame.wrap(buffer, width, height, stride, colorFormat, hasChroma, now()) ?: return
            try {
                frameListener.onFrame(frame)
            } catch (t: Throwable) {
                Log.e(TAG, "Kare dinleyicisi hata verdi", t)
            }
        }
    }

    companion object {
        private const val TAG = "NinoRP"
        /** Kotlin'e en çok saniyede 5 kare. */
        const val FRAME_INTERVAL_MS = 200
        private const val WATCHDOG_TICK_MS = 1_000L
        private const val WAKE_POLL_MS = 2_000L
        private const val WAKE_TIMEOUT_MS = 20_000L
        private const val RELOCATE_COOLDOWN_MS = 30_000L
        private const val RUNNING_APP_FIRST_MS = 30_000L
        private const val RUNNING_APP_EVERY_MS = 120_000L
    }
}
