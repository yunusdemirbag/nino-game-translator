// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.packs

import android.content.Context
import com.ninotranslator.core.http.UrlConnectionTransport
import com.ninotranslator.core.packs.PackStore
import com.ninotranslator.core.pool.PoolEndpoint
import com.ninotranslator.mobile.BuildConfig

/**
 * Oyun paketleri havuzdan iner (uygulamayla paket gelmez). İnenler `files/packs-remote/` içinde durur; eski
 * sürümün indirdiği paketler de aynı yerden okunmaya devam eder. Paketler yalnız Türkçe.
 */
object PoolPacks {
    fun store(context: Context): PackStore {
        val files = context.applicationContext.filesDir
        return PackStore(
            files, emptyList(), UrlConnectionTransport, PoolEndpoint.resolve(files),
            lang = "tr", userAgent = PoolEndpoint.userAgent(BuildConfig.VERSION_NAME),
        )
    }
}
