// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.remoteplay

import android.util.Log
import java.nio.ByteBuffer

/** Yerel kütüphanenin durumu. Yüklenemezse arayüz `error_native` gösterir. */
sealed interface NativeStatus {
    data object Ready : NativeStatus
    data class Unavailable(val detail: String) : NativeStatus
}

/** Yerelden gelen oturum olayları. onFrame çözücünün çıkış iş parçacığında; arabellek yalnız çağrı süresince geçerli. */
interface NativeSessionListener {
    fun onConnected()
    fun onLoginPinRequest(previousIncorrect: Boolean)
    fun onQuit(reason: Int, text: String?)
    fun onFrame(buffer: ByteBuffer, width: Int, height: Int, stride: Int, colorFormat: Int, hasChroma: Boolean, pts: Long)
}

/** Eşlemenin ham sonucu (yerel kod oluşturur; alan sırası JNI imzasıyla aynı). */
class NativeRegistResult(
    val code: Int,
    val appReason: Long,
    val errorLines: Array<String>,
    val nickname: String?,
    val registKey: ByteArray?,
    val morning: ByteArray?,
) {
    companion object {
        const val SUCCESS = 0
        const val FAILED = 1
        const val NO_REPLY = 2
        const val NOT_STARTED = 3
    }
}

/** chiaki-ng üstündeki JNI köprüsü. Hepsi arka planda çağrılır; bir kısmı bloklar. */
object RemotePlayNative {
    private const val TAG = "NinoRP"

    val status: NativeStatus by lazy {
        try {
            System.loadLibrary("nino-remoteplay")
            val r = nativeInit()
            if (r == 0) NativeStatus.Ready else NativeStatus.Unavailable("chiaki_lib_init: $r")
        } catch (t: Throwable) {
            Log.e(TAG, "Yerel kütüphane yüklenemedi", t)
            NativeStatus.Unavailable(t.message ?: t.javaClass.simpleName)
        }
    }

    val isReady: Boolean get() = status == NativeStatus.Ready

    @JvmStatic external fun nativeInit(): Int
    /** Bloklar. Her PS5 için 5 alan: adres, ad, "1"/"0" uyanık, çalışan uygulama kimliği, adı. */
    @JvmStatic external fun nativeDiscover(addresses: Array<String>, timeoutMs: Int): Array<String>
    @JvmStatic external fun nativeWakeup(host: String, credential: Long): Int
    /** En çok ~30 sn bloklar. */
    @JvmStatic external fun nativeRegister(host: String, accountId: ByteArray, pin: Int): NativeRegistResult
    @JvmStatic external fun nativeOpenSession(
        host: String, registKey: ByteArray, morning: ByteArray, accountId: ByteArray,
        width: Int, height: Int, software: Boolean, minFrameIntervalMs: Int, listener: NativeSessionListener,
    ): Long
    @JvmStatic external fun nativeOpenError(): String?
    /** Durdurur ve iş parçacıklarını bekler; geri çağrının içinden çağrılmaz. */
    @JvmStatic external fun nativeCloseSession(handle: Long)
    @JvmStatic external fun nativeSetLoginPin(handle: Long, pin: ByteArray): Int
    @JvmStatic external fun nativeSessionErrors(handle: Long): Array<String>
    @JvmStatic external fun nativeSessionFrames(handle: Long): Long
    @JvmStatic external fun nativeSessionSoftware(handle: Long): Boolean
}
