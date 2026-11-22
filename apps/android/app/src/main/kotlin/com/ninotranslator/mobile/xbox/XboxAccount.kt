// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.xbox

import com.ninotranslator.mobile.data.Nino
import com.ninotranslator.mobile.data.XboxConsole
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import com.ninotranslator.core.http.UrlConnectionTransport

/** Microsoft cihaz kodu (servis.md §10.1). */
data class XboxDeviceCode(val userCode: String, val verificationUri: String, val expiresAtMs: Long)

/** Xbox hata türleri; arayüz metne çevirir (ekranlar-2 "Microsoft girişi"). */
enum class XboxErrorKind { SIGN_IN, EXPIRED, NO_ACCOUNT, OFFLINE, UNEXPECTED, NOT_READY }

class XboxException(val kind: XboxErrorKind, val detail: String? = null) : Exception(detail ?: kind.name)

/**
 * Microsoft hesabı ve Xbox listesi. Ağ işi bu arayüzün arkasında; arayüz yalnız bunu bilir. Başarılı girişte
 * jetonu `Nino.secrets.saveXboxTokenResponse` ile uygulama kaydeder.
 */
interface XboxAccount {
    /** Microsoft'tan cihaz kodu ister. */
    suspend fun requestDeviceCode(): XboxDeviceCode

    /** Kullanıcı onaylayana ya da kodun süresi dolana kadar bekler; onayda jeton kaydedilmiş olur. */
    suspend fun awaitSignIn(code: XboxDeviceCode)

    /** Hesaptaki Xbox'lar. Giriş gerekiyorsa [XboxErrorKind.SIGN_IN]. */
    suspend fun listConsoles(): List<XboxConsole>

    /** Microsoft oturumunu siler. */
    fun signOut()
}

/** Asıl Xbox katmanı yazılana kadar: her iş "henüz hazır değil" der; çıkış yine çalışır. */
object NotReadyXboxAccount : XboxAccount {
    override suspend fun requestDeviceCode(): XboxDeviceCode = throw XboxException(XboxErrorKind.NOT_READY)
    override suspend fun awaitSignIn(code: XboxDeviceCode) = throw XboxException(XboxErrorKind.NOT_READY)
    override suspend fun listConsoles(): List<XboxConsole> = throw XboxException(XboxErrorKind.NOT_READY)
    override fun signOut() { Nino.secrets.clearXboxToken() }
}

/** Kullanılan Xbox katmanı: öntanımlı asıl Microsoft/Xbox Live uygulaması; testler başkasını koyabilir. */
object XboxAccounts {
    @Volatile private var replaced: XboxAccount? = null
    var current: XboxAccount
        get() = replaced ?: XboxLive.account
        set(value) { replaced = value }
}

/** Jetonun kalıcı yeri: `Nino.secrets` (`xboxUserToken`, Keystore ile şifreli). */
object SecretsXboxTokenStore : XboxTokenStore {
    override fun load(): Map<String, Any?>? = Nino.secrets.xboxToken?.raw
    override fun save(response: Map<String, Any?>, nowMs: Long) { Nino.secrets.saveXboxTokenResponse(response, nowMs) }
    override fun clear() { Nino.secrets.clearXboxToken() }
}

/** Uygulama boyunca tek jeton zinciri (giriş ekranları ve yayın aynı belleği paylaşır). */
object XboxLive {
    val chain: XboxTokenChain by lazy { XboxTokenChain(UrlConnectionTransport, SecretsXboxTokenStore) }
    val account: XboxAccount by lazy { LiveXboxAccount(chain) }
}

/** Asıl hesap katmanı (servis.md 10.1–10.3). */
class LiveXboxAccount(
    private val chain: XboxTokenChain,
    private val now: () -> Long = System::currentTimeMillis,
    private val wait: suspend (Long) -> Unit = { delay(it) },
) : XboxAccount {
    private val grants = java.util.concurrent.ConcurrentHashMap<String, DeviceCodeGrant>()

    override suspend fun requestDeviceCode(): XboxDeviceCode = withContext(Dispatchers.IO) {
        val g = chain.requestDeviceCode()
        grants.clear()
        grants[g.userCode] = g
        XboxDeviceCode(g.userCode, g.verificationUri, now() + g.expiresInSec * 1000)
    }

    override suspend fun awaitSignIn(code: XboxDeviceCode) {
        val g = grants[code.userCode] ?: throw XboxException(XboxErrorKind.EXPIRED)
        var intervalMs = g.intervalSec * 1000
        while (true) {
            wait(intervalMs)
            if (now() >= code.expiresAtMs) throw XboxException(XboxErrorKind.EXPIRED)
            // Ağ hatası girişi bitirmez: kullanıcı tarayıcıdayken Android arka plan isteğini kesebilir.
            val r = try {
                withContext(Dispatchers.IO) { chain.pollDeviceCode(g.deviceCode) }
            } catch (e: java.io.IOException) {
                continue
            }
            when (r) {
                DevicePoll.Pending, DevicePoll.ServerBusy -> Unit
                DevicePoll.SlowDown -> intervalMs += 5_000
                DevicePoll.Expired -> throw XboxException(XboxErrorKind.EXPIRED)
                DevicePoll.Declined -> throw XboxException(XboxErrorKind.SIGN_IN)
                is DevicePoll.Failed -> throw XboxException(XboxErrorKind.UNEXPECTED, r.detail)
                is DevicePoll.Done -> {
                    withContext(Dispatchers.IO) { chain.signedIn(r.response) }
                    grants.remove(code.userCode)
                    return
                }
            }
        }
    }

    override suspend fun listConsoles(): List<XboxConsole> = withContext(Dispatchers.IO) { chain.consoles() }

    override fun signOut() {
        chain.reset()
        Nino.secrets.clearXboxToken()
    }
}

/**
 * Süren Microsoft girişi. Ekrandan bağımsızdır: tablet döndürülse ya da ekran kapansa da kodun süresi bitene kadar
 * bekler. Arayüz [state]'i izler.
 */
object XboxSignIn {
    data class State(
        val code: XboxDeviceCode? = null,
        val working: Boolean = false,
        val waiting: Boolean = false,
        val error: XboxException? = null,
        /** Onay geldi; ekran bir kez ilerleyip [consumeDone] çağırır. */
        val done: Boolean = false,
    )

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val _state = MutableStateFlow(State())
    val state: StateFlow<State> = _state.asStateFlow()
    private var job: Job? = null

    /** Kod ister; [onCode] kod gelince ana iş parçacığı dışından çağrılır (panoya kopyalama, tarayıcı). */
    fun start(onCode: (XboxDeviceCode) -> Unit) {
        if (_state.value.working || _state.value.waiting) return
        job?.cancel()
        _state.value = State(working = true)
        job = scope.launch {
            val account = XboxAccounts.current
            try {
                val code = account.requestDeviceCode()
                _state.value = State(code = code, waiting = true)
                onCode(code)
                account.awaitSignIn(code)
                _state.value = State(done = true)
            } catch (e: XboxException) {
                _state.update { State(code = null, error = e) }
            } catch (e: kotlinx.coroutines.CancellationException) {
                throw e
            } catch (e: Exception) {
                _state.update { State(error = XboxException(XboxErrorKind.UNEXPECTED, e.message)) }
            }
        }
    }

    /** "Şimdilik Atla" ya da geri: süren giriş iptal. */
    fun cancel() {
        job?.cancel()
        job = null
        _state.value = State()
    }

    fun consumeDone() { _state.update { if (it.done) State() else it } }
}
