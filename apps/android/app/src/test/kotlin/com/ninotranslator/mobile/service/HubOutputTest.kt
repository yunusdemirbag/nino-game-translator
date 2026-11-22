// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.service

import com.ninotranslator.core.link.DisplayHub
import com.ninotranslator.core.reading.live.LiveBox
import com.ninotranslator.core.reading.live.LiveShowKind
import com.ninotranslator.core.translation.LineResult
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.Socket

/** Gerçek DisplayHub üstünden: görünüm, "başladı" ve altyazı eski TV akışına (SSE) kutu ve süreyle gider. */
class HubOutputTest {
    @Test fun styleStartedAndSubtitleReachLegacyTv() = runBlocking {
        val hub = DisplayHub(DisplayHub.Config(deviceName = "test", clientVersion = "nino-android/test", ingressPort = 0, legacyPort = 0))
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
        try {
            hub.start()
            val out = HubTvOutput(hub, scope)
            out.setStyle(TvStyle.map(StyleInput(fontSize = 58)))
            out.started()
            Socket("127.0.0.1", hub.legacyLocalPort).use { s ->
                s.soTimeout = 5_000
                s.getOutputStream().write("GET /events HTTP/1.1\r\nHost: x\r\n\r\n".toByteArray())
                val reader = BufferedReader(InputStreamReader(s.getInputStream(), Charsets.UTF_8))
                val seen = StringBuilder()
                fun readUntil(token: String) {
                    while (!seen.contains(token)) { val l = reader.readLine() ?: break; seen.append(l).append('\n') }
                }
                readUntil("event: style")
                val router = SubtitleRouter(scope, out, { 1L }, { 0L }) { _, _ -> }
                // Akış açıldıktan sonra satır gider.
                router.show(ShownLine(1, "We ride at dawn.", "Şafakta yola çıkıyoruz.", 15000, false, LiveShowKind.NEW, false,
                    LineResult.Origin.ON_DEVICE, "mlkit-p3", LiveBox(0.2, 0.8, 0.8, 0.88), 120, 300))
                readUntil("event: subtitle")
                seen.append(reader.readLine()).append('\n')
                val text = seen.toString()
                assertTrue(text, text.contains("\"fontSize\":58"))
                assertTrue(text, text.contains("event: started"))
                val sub = text.substring(text.indexOf("event: subtitle"))
                assertTrue(sub, sub.contains("Şafakta yola çıkıyoruz."))
                assertTrue(sub, sub.contains("\"duration\":15000"))
                assertTrue(sub, sub.contains("\"box\""))
            }
        } finally {
            hub.close()
            scope.cancel()
        }
    }
}
