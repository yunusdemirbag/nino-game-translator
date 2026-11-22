// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.link

import java.io.IOException
import java.net.ConnectException
import java.net.NoRouteToHostException
import java.net.PortUnreachableException
import java.net.SocketTimeoutException
import java.net.UnknownHostException

/** Bir TV bağlantısının neden koptuğu. */
enum class DropReason {
    /** TV'den bir süre ses yok (ping/pong zaman aşımı) ya da gönderim sırası doldu (bağlantı asılı). */
    TIMEOUT,
    /** Karşı taraf bağlantıyı kapattı. */
    CLOSED,
    /** Yazılamadı (soket yazma hatası). */
    WRITE_ERROR,
    /** Aynı TV'ye yeni bağlantı açıldı; eskisi kapatıldı. */
    REPLACED,
    /** Ağ yok ya da TV'ye ulaşılamıyor. */
    NETWORK_LOST,
    /** Uygulama durdurdu (oturum bitti, TV listeden çıkarıldı). Kopma sayılmaz. */
    STOPPED,
    OTHER;

    companion object {
        /** Okuma sırasında düşen istisnadan neden. */
        fun of(e: Throwable): DropReason = when {
            e is SocketTimeoutException -> TIMEOUT
            isNetwork(e) -> NETWORK_LOST
            // TCP yeniden gönderimleri tükendi: karşı taraf sessizce gitti.
            e.message?.lowercase()?.let { "timed out" in it || "etimedout" in it } == true -> TIMEOUT
            e is IOException -> CLOSED
            else -> OTHER
        }

        internal fun isNetwork(e: Throwable): Boolean {
            if (e is NoRouteToHostException || e is UnknownHostException || e is PortUnreachableException) return true
            val m = e.message?.lowercase().orEmpty()
            // Wi-Fi gidince Android açık soketleri "connection abort" ile keser (cihazda denenmedi).
            return "unreachable" in m || "enetunreach" in m || "ehostunreach" in m || "enetdown" in m || "no route" in m ||
                "connection abort" in m || "econnaborted" in m
        }
    }
}

/** Android TV'ye bağlanılamama nedeni. */
enum class ConnectFailure {
    TIMEOUT, REFUSED, PROTOCOL, NETWORK, OTHER;

    companion object {
        fun of(e: Throwable): ConnectFailure = when {
            e is NinoSender.SenderException.VersionUnsupported || e is NinoSender.SenderException.UnexpectedReply -> PROTOCOL
            e is NinoSender.SenderException.Rejected -> REFUSED
            e is NinoSender.SenderException.Timeout || e is SocketTimeoutException -> TIMEOUT
            DropReason.isNetwork(e) -> NETWORK
            e is ConnectException -> REFUSED
            else -> OTHER
        }
    }
}

/** TV bağlantı olayları ([DisplayHub.events]). Günlük ve ölçüm içindir. */
sealed interface DisplayEvent {
    /** TV altyazı almaya başladı. */
    data class Connected(val display: ConnectedDisplay) : DisplayEvent

    /** Bağlı TV gitti. [afterMs] bağlı kaldığı süre. */
    data class Dropped(val display: ConnectedDisplay, val reason: DropReason, val afterMs: Long) : DisplayEvent

    /** Android TV'ye bağlanma denemesi başarısız (her bağlantı döneminde bir kez). */
    data class ConnectFailed(val host: String, val reason: ConnectFailure) : DisplayEvent
}
