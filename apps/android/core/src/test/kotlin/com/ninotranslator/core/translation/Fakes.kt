// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.translation

import com.ninotranslator.core.http.HttpRequest
import com.ninotranslator.core.http.HttpResponse
import com.ninotranslator.core.http.HttpTransport

/** Elle ilerletilen saat. */
class FakeClock(var ms: Long = 1_000_000) { fun advance(d: Long) { ms += d }; val now: () -> Long = { ms } }

/** İstekleri kaydeden, cevabı işlevle veren sahte ağ. */
class FakeHttp(var handler: (HttpRequest) -> HttpResponse) : HttpTransport {
    val requests = ArrayList<HttpRequest>()
    override fun send(request: HttpRequest): HttpResponse { synchronized(requests) { requests += request }; return handler(request) }
    companion object {
        fun json(status: Int, body: String, headers: Map<String, String> = emptyMap()) = HttpResponse(status, headers.mapKeys { it.key.lowercase() }, body.toByteArray())
    }
}

val HttpRequest.bodyText: String get() = body?.toString(Charsets.UTF_8) ?: ""

/** Sahte cihaz içi çevirmen: tabloda varsa o, yoksa "[tr]" önekli metin. */
class FakeOnDevice(val table: MutableMap<String, String> = HashMap()) : OnDeviceTranslator {
    val calls = ArrayList<String>()
    var fail = false
    override suspend fun translate(text: String, target: TargetLanguage): String {
        calls += text
        if (fail) throw IllegalStateException("model yok")
        return table[text] ?: "[${target.code}] $text"
    }
}
