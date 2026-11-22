// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.link

import com.ninotranslator.core.json.Json
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.onSubscription
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.HttpURLConnection
import java.net.Socket
import java.net.ConnectException
import java.net.NoRouteToHostException
import java.net.SocketException
import java.net.SocketTimeoutException
import java.net.URL
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.atomic.AtomicReference

class DisplayHubTest {
    // Testler yalnız port 0 ile açar: bu Mac'te gerçek Nino 8787'yi tutuyor olabilir.
    private fun config(ingress: Boolean = false, legacy: Boolean = false) = DisplayHub.Config(
        deviceName = "Telefon", clientVersion = "nino-android/test", deviceId = "test-id", appVersion = "9.9.9",
        ingressEnabled = ingress, ingressPort = 0, legacyEnabled = legacy, legacyPort = 0,
        pingIntervalMs = 150, pongTimeoutMs = 2_000, handshakeTimeoutMs = 1_000, legacyPingMs = 60_000,
    )

    private suspend fun waitUntil(ms: Long = 5_000, what: () -> Boolean) {
        withTimeout(ms) { while (!what()) delay(10) }
    }

    private fun types(tv: FakeDisplay) = tv.raw.map { Json.parseObject(it)["type"] }

    // --- Android TV (telefon istemci) ---

    @Test fun androidTvGetsReplayThenSubtitles() = runBlocking {
        FakeDisplay("Salon TV").use { tv ->
            val hub = DisplayHub(config())
            hub.setStyle(mapOf("fontSize" to 46, "placement" to "cover", "background" to 100.0))
            hub.started()
            hub.connectTo("127.0.0.1", tv.port)
            waitUntil { hub.displays.value.any { it.kind == DisplayKind.ANDROID_TV } }
            assertEquals("Salon TV", hub.displays.value.single().name)
            hub.show(ShowPayload(5, "Buraya gel.", "Come here.", extras = mapOf("box" to mapOf("left" to 0.1, "top" to 0.80000, "right" to 1.2, "bottom" to 0.875))))
            hub.clear(5)
            waitUntil { tv.received.any { it is NinoMessage.Clear } }
            assertEquals(listOf("hello", "style", "started", "show", "clear"), types(tv).filter { it != "ping" })
            assertEquals("""{"app":"nino","background":100,"fontSize":46,"placement":"cover","type":"style"}""", tv.raw[1])
            val show = tv.raw.first { it.contains("\"show\"") }
            assertTrue(show, show.contains(""""box":{"bottom":0.875,"left":0.1,"right":1,"top":0.8}"""))
            hub.close()
        }
    }

    @Test fun androidTvReconnectResendsStyleAndLastSubtitle() = runBlocking {
        FakeDisplay().use { tv ->
            val hub = DisplayHub(config())
            hub.connectTo("127.0.0.1", tv.port)
            waitUntil { hub.displays.value.isNotEmpty() }
            hub.setStyle(mapOf("textColor" to "yellow"))
            hub.show(ShowPayload(7, "Kal.", durationMs = 0))
            waitUntil { tv.received.any { it is NinoMessage.Show } }
            tv.dropAll()
            waitUntil(8_000) { tv.connections >= 2 && tv.raw.count { it.contains("\"style\"") } >= 2 && tv.received.count { it is NinoMessage.Show } >= 2 }
            val afterReconnect = tv.raw.drop(tv.raw.indexOfLast { it.contains("\"hello\"") }).map { Json.parseObject(it)["type"] }.filter { it != "ping" }
            assertEquals(listOf("hello", "style", "show"), afterReconnect.take(3))
            hub.close()
        }
    }

    @Test fun androidTvLaterConnectAndDisconnect() = runBlocking {
        val hub = DisplayHub(config())
        FakeDisplay("Geç TV").use { tv ->
            // TV henüz yok gibi: yanlış porta bağlanmaya çalışırken bekler, sonra doğru porta geçilir.
            hub.connectTo("127.0.0.1", 1)
            hub.connectTo("127.0.0.1", tv.port)
            waitUntil { hub.displays.value.isNotEmpty() }
            hub.disconnectFrom("127.0.0.1")
            waitUntil { hub.displays.value.isEmpty() }
        }
        hub.close()
    }

    // --- Web TV (TV telefona bağlanır) ---

    private fun webTv(hub: DisplayHub, name: String, model: String? = null): WebSocketClient {
        val ws = WebSocketClient.connect("ws://127.0.0.1:${hub.ingressLocalPort}/nino/ws", 2_000)
        ws.setReadTimeout(3_000)
        val hello = NinoMessage.decode(ws.receiveText()!!) as NinoMessage.Hello
        assertEquals(1, hello.version)
        assertEquals("Telefon", hello.device)
        assertEquals("nino-android/test", hello.client)
        ws.sendText(NinoMessage.Welcome(1, name, model, "2.0.0").encode())
        return ws
    }

    /** Sıradaki ping dışı mesaj. TV olarak ping'e pong döner. */
    private fun next(ws: WebSocketClient): Map<String, Any?> {
        while (true) {
            val text = ws.receiveText() ?: error("bağlantı kapandı")
            val m = Json.parseObject(text)
            if (m["type"] == "ping") { ws.sendText(NinoMessage.Pong((m["t"] as Number).toLong()).encode()); continue }
            return m
        }
    }

    @Test fun webTvInfoAndHandshake() = runBlocking {
        val hub = DisplayHub(config(ingress = true))
        hub.start()
        assertTrue(hub.portProblems.value.isEmpty())
        val c = URL("http://127.0.0.1:${hub.ingressLocalPort}/nino/info").openConnection() as HttpURLConnection
        assertEquals(200, c.responseCode)
        assertEquals("*", c.getHeaderField("Access-Control-Allow-Origin"))
        val info = NinoMessage.decode(c.inputStream.readBytes().toString(Charsets.UTF_8)) as NinoMessage.Info
        assertEquals("sender", info.role)
        assertEquals("Telefon", info.name)
        assertEquals("9.9.9", info.appVersion)
        val o = URL("http://127.0.0.1:${hub.ingressLocalPort}/nino/info").openConnection() as HttpURLConnection
        o.requestMethod = "OPTIONS"
        assertEquals(204, o.responseCode)

        hub.setStyle(mapOf("font" to "rounded"))
        hub.show(ShowPayload(3, "Hazır.", durationMs = 0, extras = mapOf("replace" to true, "light" to 0.456)))
        val ws = webTv(hub, "LG TV", "LG OLED55")
        assertEquals("style", next(ws)["type"])
        val replayed = next(ws)
        assertEquals("show", replayed["type"])
        assertEquals(0.46, (replayed["light"] as Number).toDouble(), 0.0)
        waitUntil { hub.displays.value.any { it.kind == DisplayKind.WEB_TV } }
        val d = hub.displays.value.single()
        assertEquals("LG TV", d.name); assertEquals("LG OLED55", d.model); assertEquals("2.0.0", d.appVersion)
        hub.screen(listOf(mapOf("text" to "Görev", "box" to mapOf("left" to 0.1, "top" to 0.1, "right" to 0.4, "bottom" to 0.2),
            "angle" to 0.2, "alpha" to 0.333)), 120_000, overlay = true)
        val screen = next(ws)
        assertEquals("screen", screen["type"]); assertEquals(true, screen["overlay"])
        val item = (screen["items"] as List<*>).single() as Map<*, *>
        assertFalse(item.containsKey("angle")); assertEquals(0.33, (item["alpha"] as Number).toDouble(), 0.0)
        hub.region("map", "Köprü", mapOf("left" to 0.7, "top" to 0.05, "right" to 0.95, "bottom" to 0.1), lineHeight = 0.02)
        assertEquals("region", next(ws)["type"])
        hub.stopped()
        assertEquals("stopped", next(ws)["type"])
        ws.close()
        hub.close()
    }

    @Test fun oneTvDroppingDoesNotAffectOthers() = runBlocking {
        FakeDisplay("Android").use { atv ->
            val hub = DisplayHub(config(ingress = true))
            hub.start()
            hub.connectTo("127.0.0.1", atv.port)
            val a = webTv(hub, "Samsung")
            val b = webTv(hub, "LG")
            waitUntil { hub.displays.value.size == 3 }
            a.close(1001)
            waitUntil { hub.displays.value.size == 2 }
            atv.dropAll()
            hub.show(ShowPayload(9, "Sürüyor."))
            assertEquals("Sürüyor.", next(b)["text"])
            assertTrue(hub.displays.value.any { it.name == "LG" })
            b.close()
            hub.close()
        }
    }

    @Test fun largeCoverReachesBothKinds() = runBlocking {
        FakeDisplay().use { atv ->
            val hub = DisplayHub(config(ingress = true))
            hub.start()
            hub.connectTo("127.0.0.1", atv.port)
            waitUntil { hub.displays.value.isNotEmpty() }
            val ws = webTv(hub, "Web")
            waitUntil { hub.displays.value.size == 2 }
            val cover = "Q".repeat(100_000)
            hub.show(ShowPayload(4, "Buzlu.", extras = mapOf("cover" to cover)))
            var got: Map<String, Any?>
            while (true) {
                got = Json.parseObject(ws.receiveText(LinkFormat.MAX_COVER_MESSAGE_BYTES)!!)
                if (got["type"] == "show") break
            }
            assertEquals(cover, got["cover"])
            waitUntil { tv(atv).any { it["type"] == "show" } }
            assertEquals(cover, tv(atv).first { it["type"] == "show" }["cover"])
            ws.close()
            hub.close()
        }
    }

    private fun tv(d: FakeDisplay) = d.raw.map { Json.parseObject(it) }

    @Test fun silentWebTvIsDropped() = runBlocking {
        val hub = DisplayHub(config(ingress = true))
        hub.start()
        val ws = webTv(hub, "Sessiz")
        waitUntil { hub.displays.value.size == 1 }
        // TV hiçbir şey yollamaz (pong da yok): 2 sn sonra kapatılır.
        waitUntil(5_000) { hub.displays.value.isEmpty() }
        ws.close()
        hub.close()
    }

    // --- Eski 8787 ---

    private class Sse(port: Int, query: String) : AutoCloseable {
        val socket = Socket("127.0.0.1", port)
        val reader: BufferedReader
        val status: String
        val headers = HashMap<String, String>()

        init {
            socket.soTimeout = 3_000
            socket.getOutputStream().write("GET /events$query HTTP/1.1\r\nHost: x\r\n\r\n".toByteArray())
            reader = BufferedReader(InputStreamReader(socket.getInputStream(), Charsets.UTF_8))
            status = reader.readLine()
            while (true) {
                val l = reader.readLine()
                if (l.isEmpty()) break
                headers[l.substringBefore(':').lowercase()] = l.substringAfter(':').trim()
            }
        }

        /** Sıradaki olay: (ad, veri). retry ve ping atlanır. */
        fun next(): Pair<String, String> {
            var name: String? = null
            var data: String? = null
            while (true) {
                val l = reader.readLine() ?: error("akış bitti")
                when {
                    l.startsWith("event: ") -> name = l.removePrefix("event: ")
                    l.startsWith("data: ") -> data = l.removePrefix("data: ")
                    l.isEmpty() -> {
                        if (name != null && name != "ping") return name to (data ?: "")
                        name = null; data = null
                    }
                }
            }
        }

        override fun close() = socket.close()
    }

    private fun get(port: Int, path: String): Pair<Int, String> {
        val c = URL("http://127.0.0.1:$port$path").openConnection() as HttpURLConnection
        val code = c.responseCode
        val body = (if (code < 400) c.inputStream else c.errorStream)?.use { it.readBytes().toString(Charsets.UTF_8) } ?: ""
        return code to body
    }

    @Test fun legacyHelloEventsAndFieldNames() = runBlocking {
        val hub = DisplayHub(config(legacy = true))
        hub.start()
        val port = hub.legacyLocalPort
        assertEquals(200 to """{"app":"nino"}""", get(port, "/hello"))
        assertEquals(404, get(port, "/nope").first)

        hub.setStyle(mapOf("fontSize" to 58, "watermark" to false, "backgroundShape" to "band"))
        hub.started()
        Sse(port, "?model=Samsung%20QE65%3CQ80C%3E%22").use { tv ->
            assertTrue(tv.status, tv.status.startsWith("HTTP/1.1 200"))
            assertEquals("text/event-stream; charset=utf-8", tv.headers["content-type"])
            assertEquals("*", tv.headers["access-control-allow-origin"])
            assertEquals("style" to """{"backgroundShape":"band","fontSize":58,"watermark":false}""", tv.next())
            assertEquals("started" to "{}", tv.next())
            waitUntil { hub.displays.value.isNotEmpty() }
            val d = hub.displays.value.single()
            assertEquals(DisplayKind.LEGACY, d.kind); assertEquals("Samsung QE65Q80C", d.model)

            hub.show(ShowPayload(11, "Çabuk ol!\nŞimdi.", durationMs = 0, extras = mapOf(
                "box" to mapOf("left" to 0.12345, "top" to 0.8, "right" to 0.9, "bottom" to 1.0), "paragraphs" to true, "replace" to true)))
            val (name, data) = tv.next()
            assertEquals("subtitle", name)
            val o = Json.parseObject(data)
            assertEquals(15_000L, o["duration"])
            assertEquals(listOf("at", "box", "duration", "paragraphs", "replace", "text"), o.keys.toList())
            assertTrue(data, data.contains(""""box":{"bottom":1,"left":0.1235,"right":0.9,"top":0.8}"""))
            assertTrue(data, data.contains(""""text":"Çabuk ol!\nŞimdi.""""))
            for (k in listOf("app", "type", "id", "source", "position", "durationMs")) assertFalse(k, o.containsKey(k))

            hub.clear(10) // eski kimlik: gitmez
            hub.show(ShowPayload(12, "Kısa.", durationMs = 4_000))
            assertEquals(4_000L, Json.parseObject(tv.next().second)["duration"])
            hub.clear(12)
            assertEquals("clear" to "{}", tv.next())
            hub.screen(listOf(mapOf("text" to "Harita", "card" to true)), 2_500, overlay = false)
            val (sn, sd) = tv.next()
            assertEquals("screen", sn)
            assertEquals("""{"duration":2500,"items":[{"card":true,"text":"Harita"}]}""", sd)
            hub.region("quest", "Görev", mapOf("left" to 0.0, "top" to 0.1, "right" to 0.3, "bottom" to 0.15), line = true)
            assertEquals("region" to """{"box":{"bottom":0.15,"left":0,"right":0.3,"top":0.1},"id":"quest","line":0.05,"text":"Görev"}""", tv.next())
            hub.regionClearAll()
            assertEquals("region-clear" to "{}", tv.next())
        }
        hub.close()
    }

    @Test fun legacyViewerAndPhoneTarget() = runBlocking {
        val hub = DisplayHub(config(legacy = true))
        hub.start()
        hub.started()
        val port = hub.legacyLocalPort
        Sse(port, "?viewer=obs").use { obs ->
            Sse(port, "").use { tv ->
                assertEquals("started" to "{}", tv.next())
                waitUntil { hub.displays.value.size == 1 } // izleyici sayılmaz
                hub.tvSubtitlesEnabled = false
                assertEquals("clear" to "{}", tv.next())
                hub.show(ShowPayload(1, "Yalnız OBS."))
                hub.stopped()
                assertEquals("stopped" to "{}", tv.next()) // altyazı TV'ye gitmedi
                assertEquals("subtitle", obs.next().first) // izleyiciye started gitmez, altyazı gider
                assertEquals("stopped", obs.next().first)
            }
        }
        hub.close()
    }

    @Test fun legacyStartedOnlyWithinWindow() = runBlocking {
        val hub = DisplayHub(config(legacy = true).copy(legacyStartedWindowMs = 100))
        hub.start()
        hub.setStyle(mapOf("bold" to true))
        hub.started()
        delay(250)
        Sse(hub.legacyLocalPort, "").use { tv ->
            assertEquals("style", tv.next().first)
            hub.screenClear()
            assertEquals("screen-clear", tv.next().first) // started arada yok
        }
        hub.close()
    }

    @Test fun busyPortIsReported() {
        java.net.ServerSocket(0).use { busy ->
            val hub = DisplayHub(config(legacy = true).copy(legacyPort = busy.localPort))
            hub.start()
            assertEquals(setOf(busy.localPort), hub.portProblems.value)
            hub.close()
        }
    }

    // --- Biçim ve bulma ---

    @Test fun numberFormat() {
        assertEquals("0.875", LinkFormat.round(0.8750, 4).toString())
        assertEquals("1", LinkFormat.round(1.0, 4).toString())
        assertEquals("0.0001", LinkFormat.round(0.00005, 4).toString())
        assertEquals("0", LinkFormat.round(-0.00001, 4).toString())
        assertEquals("-12.5", LinkFormat.round(-12.46, 1).toString())
        val m = LinkFormat.normalizeMap(mapOf("z" to 1, "a" to mapOf("y" to 2.0, "b" to null), "angle" to -3.04, "light" to 1.7))
        assertEquals("""{"a":{"y":2},"angle":-3,"light":1,"z":1}""", Json.write(m))
    }

    @Test fun oversizedCoverIsDroppedAndScreenTrimmed() {
        val big = "A".repeat(LinkFormat.MAX_COVER_MESSAGE_BYTES)
        val p = LinkFormat.fitShow(ShowPayload(1, "x", extras = mapOf("cover" to big)))
        assertNull(p.extras["cover"])
        val small = LinkFormat.fitShow(ShowPayload(1, "x", extras = mapOf("cover" to "abc")))
        assertEquals("abc", small.extras["cover"])
        val items = List(40) { mapOf<String, Any?>("text" to "x".repeat(1_000)) }
        val fields = LinkFormat.fitScreen(items, 1000, false)
        val n = (fields["items"] as List<*>).size
        assertTrue("$n", n in 1..16)
        assertTrue(LinkFormat.bytes(LinkFormat.extension("screen", fields)) <= LinkFormat.MAX_COMPACT_MESSAGE_BYTES)
    }

    @Test fun manualAddressCleaning() {
        assertEquals("192.168.1.5", ManualAddress.clean(" 192,168,1,5 "))
        assertEquals("10.0.0.10", ManualAddress.clean("http://10.0.0.010:8080/path?x#y"))
        assertEquals("192.168.0.110" to 47801, ManualAddress.cleanWithPort("192.168.0.110:47801"))
        assertEquals("lgwebostv.local", ManualAddress.clean("LGwebOSTV.local."))
        for (bad in listOf("192.168.1", "192.168.1.256", "1.2.3.4:", "1.2.3.4:ab", "fe80::1", "-bad.local", "123", "", "a..b"))
            assertNull(bad, ManualAddress.clean(bad))
    }

    @Test fun ssdpParsing() {
        val lg = "HTTP/1.1 200 OK\r\nST: urn:lge-com:service:webos-second-screen:1\r\nLOCATION: http://192.168.0.20:1527/\r\n\r\n"
        val dial = "HTTP/1.1 200 OK\r\nst: urn:dial-multiscreen-org:service:dial:1\r\nLocation: http://192.168.0.20:8008/dd.xml\r\n\r\n"
        val other = "HTTP/1.1 200 OK\r\nST: upnp:rootdevice\r\nLOCATION: http://192.168.0.1/\r\n\r\n"
        val hits = listOfNotNull(Ssdp.parse(dial), Ssdp.parse(lg), Ssdp.parse(other))
        assertEquals(2, hits.size)
        assertEquals(listOf(SsdpHit("192.168.0.20", SsdpBrand.LG, "http://192.168.0.20:1527/")), Ssdp.merge(hits))
        assertTrue(Ssdp.search("urn:x").contains("MAN: \"ssdp:discover\"\r\nMX: 2\r\nST: urn:x\r\n"))
        assertEquals("[LG] webOS TV & UK7550", Ssdp.friendlyName("<root><device><friendlyName>[LG] webOS TV &amp; UK7550</friendlyName></device></root>"))
        assertEquals("Samsung TV", Ssdp.fallbackName(SsdpBrand.SAMSUNG))
    }

    // --- Canlı tutma ve kopma nedenleri ---

    /** Olayları biriktirir; abonelik kurulunca döner. */
    private class Recorder(hub: DisplayHub) : AutoCloseable {
        val events = CopyOnWriteArrayList<DisplayEvent>()
        private val ready = CompletableDeferred<Unit>()
        private val job: Job = CoroutineScope(Dispatchers.IO).launch {
            hub.events.onSubscription { ready.complete(Unit) }.collect { events += it }
        }
        suspend fun await() = apply { ready.await() }
        fun drops() = events.filterIsInstance<DisplayEvent.Dropped>()
        override fun close() = job.cancel()
    }

    private suspend fun recorder(hub: DisplayHub) = Recorder(hub).await()

    private suspend fun Recorder.waitDrop(ms: Long = 5_000): DisplayEvent.Dropped {
        waitUntil(ms) { drops().isNotEmpty() }
        return drops().first()
    }

    @Test fun pingIntervalsFollowTheRule() {
        // TV: yeni protokolde 15 sn sessizlikte, eski akışta ping görülmüşken 25 sn sessizlikte yeniden bağlanır.
        assertEquals(5_000L, NinoLink.PING_INTERVAL_MS)
        assertEquals(15_000L, NinoLink.PONG_TIMEOUT_MS)
        assertEquals(10_000L, LegacyEventServer.PING_MS)
        val d = DisplayHub.Config("x", "y")
        assertEquals(5_000L, d.pingIntervalMs)
        assertEquals(15_000L, d.pongTimeoutMs)
        assertEquals(10_000L, d.legacyPingMs)
    }

    @Test fun androidTvKeepAlivePings() = runBlocking {
        FakeDisplay().use { tv ->
            val hub = DisplayHub(config())
            hub.connectTo("127.0.0.1", tv.port)
            // 150 ms aralıkla: bir saniyede birkaç ping (kesin zaman değil, alt sınır).
            waitUntil(3_000) { tv.received.count { it is NinoMessage.Ping } >= 3 }
            assertTrue(hub.displays.value.isNotEmpty())
            hub.close()
        }
    }

    @Test fun webTvGetsPings() = runBlocking {
        val hub = DisplayHub(config(ingress = true))
        hub.start()
        val ws = webTv(hub, "Web")
        var pings = 0
        withTimeout(3_000) {
            while (pings < 3) {
                val m = Json.parseObject(ws.receiveText()!!)
                if (m["type"] == "ping") { pings++; ws.sendText(NinoMessage.Pong((m["t"] as Number).toLong()).encode()) }
            }
        }
        assertEquals(1, hub.displays.value.size)
        ws.close()
        hub.close()
    }

    /** Ham SSE okuyucu: ping satırlarını da görür. */
    private fun legacyLines(port: Int): Pair<Socket, BufferedReader> {
        val socket = Socket("127.0.0.1", port)
        socket.soTimeout = 1_500
        socket.getOutputStream().write("GET /events HTTP/1.1\r\nHost: x\r\n\r\n".toByteArray())
        return socket to BufferedReader(InputStreamReader(socket.getInputStream(), Charsets.UTF_8))
    }

    @Test fun legacyFirstPingIsImmediate() = runBlocking {
        // Aralık 60 sn: görülen ping yalnız bağlanınca giden ilk ping olabilir.
        val hub = DisplayHub(config(legacy = true))
        hub.start()
        hub.setStyle(mapOf("bold" to true))
        val (socket, reader) = legacyLines(hub.legacyLocalPort)
        socket.use {
            val start = System.nanoTime()
            val lines = ArrayList<String>()
            while (lines.lastOrNull() != "event: ping") lines += reader.readLine() ?: error("akış bitti")
            assertTrue((System.nanoTime() - start) / 1_000_000 < 1_500)
            assertTrue(lines.contains(": ping"))
            // Ping, son durumdan (style) önce gider.
            assertFalse(lines.any { it == "event: style" })
        }
        hub.close()
    }

    @Test fun legacyPingsRepeat() = runBlocking {
        val hub = DisplayHub(config(legacy = true).copy(legacyPingMs = 100))
        hub.start()
        val (socket, reader) = legacyLines(hub.legacyLocalPort)
        socket.use {
            var pings = 0
            withTimeout(3_000) { while (pings < 4) if ((reader.readLine() ?: error("akış bitti")) == "event: ping") pings++ }
        }
        hub.close()
    }

    @Test fun outboxDropsOnWriteErrorAndStall() {
        val reason = AtomicReference<DropReason?>()
        val broken = Outbox("t-broken", 8, { throw java.io.IOException("Broken pipe") }, { reason.compareAndSet(null, it) })
        broken.post("x")
        runBlocking { waitUntil { reason.get() != null } }
        assertEquals(DropReason.WRITE_ERROR, reason.get())
        broken.close()

        val stall = AtomicReference<DropReason?>()
        val gate = Object()
        val stuck = Outbox("t-stuck", 2, { synchronized(gate) { gate.wait(2_000) } }, { stall.compareAndSet(null, it) })
        repeat(5) { stuck.post("x") }
        assertEquals(DropReason.TIMEOUT, stall.get())
        stuck.close()
    }

    @Test fun androidTvDropReasons() = runBlocking {
        // Pong yok → zaman aşımı.
        FakeDisplay(answerPings = false).use { tv ->
            val hub = DisplayHub(config().copy(pongTimeoutMs = 300))
            recorder(hub).use { r ->
                hub.connectTo("127.0.0.1", tv.port)
                val d = r.waitDrop()
                assertEquals(DropReason.TIMEOUT, d.reason)
                assertEquals(DisplayKind.ANDROID_TV, d.display.kind)
                assertTrue(r.events.first() is DisplayEvent.Connected)
            }
            hub.close()
        }
        // TV kapattı → closed; yeniden bağlanınca yine Connected.
        FakeDisplay().use { tv ->
            val hub = DisplayHub(config())
            recorder(hub).use { r ->
                hub.connectTo("127.0.0.1", tv.port)
                waitUntil { hub.displays.value.isNotEmpty() }
                tv.dropAll()
                assertEquals(DropReason.CLOSED, r.waitDrop().reason)
                waitUntil(8_000) { r.events.count { it is DisplayEvent.Connected } >= 2 }
                hub.close()
                waitUntil { r.drops().size >= 2 }
                assertEquals(DropReason.STOPPED, r.drops().last().reason)
            }
        }
    }

    @Test fun androidTvReplacedAndRefused() = runBlocking {
        FakeDisplay("Bir").use { a -> FakeDisplay("İki").use { b ->
            val hub = DisplayHub(config())
            recorder(hub).use { r ->
                hub.connectTo("127.0.0.1", 1) // kapı kapalı: bağlanılamıyor
                waitUntil(3_000) { r.events.any { it is DisplayEvent.ConnectFailed } }
                delay(1_500) // yeniden denemeler tekrar bildirilmez
                assertEquals(listOf(DisplayEvent.ConnectFailed("127.0.0.1", ConnectFailure.REFUSED)), r.events.toList())
                hub.connectTo("127.0.0.1", a.port)
                waitUntil { hub.displays.value.any { it.name == "Bir" } }
                hub.connectTo("127.0.0.1", b.port)
                val d = r.waitDrop()
                assertEquals(DropReason.REPLACED, d.reason)
                assertEquals("Bir", d.display.name)
                waitUntil { hub.displays.value.any { it.name == "İki" } }
                hub.disconnectFrom("127.0.0.1")
                waitUntil { r.drops().size >= 2 }
                assertEquals(DropReason.STOPPED, r.drops()[1].reason)
                assertEquals(2, r.drops().size)
            }
            hub.close()
        } }
    }

    @Test fun webTvDropReasons() = runBlocking {
        val hub = DisplayHub(config(ingress = true))
        hub.start()
        recorder(hub).use { r ->
            val silent = webTv(hub, "Sessiz")
            assertEquals(DropReason.TIMEOUT, r.waitDrop().reason) // pong yok, 2 sn
            silent.close()
            val closing = webTv(hub, "Kapanan")
            waitUntil { hub.displays.value.size == 1 }
            closing.close(1000)
            waitUntil { r.drops().size >= 2 }
            assertEquals(DropReason.CLOSED, r.drops()[1].reason)
            val last = webTv(hub, "Son")
            waitUntil { hub.displays.value.size == 1 }
            hub.close()
            waitUntil { r.drops().size >= 3 }
            assertEquals(DropReason.STOPPED, r.drops()[2].reason)
            assertEquals(3, r.drops().size) // her kopma bir kez
            last.close()
        }
    }

    @Test fun legacyDropReasons() = runBlocking {
        val hub = DisplayHub(config(legacy = true))
        hub.start()
        recorder(hub).use { r ->
            val (a, _) = legacyLines(hub.legacyLocalPort)
            waitUntil { hub.displays.value.size == 1 }
            a.close()
            val d = r.waitDrop()
            assertEquals(DropReason.CLOSED, d.reason)
            assertEquals(DisplayKind.LEGACY, d.display.kind)
            assertTrue(hub.displays.value.isEmpty())
            val (b, _) = legacyLines(hub.legacyLocalPort)
            waitUntil { hub.displays.value.size == 1 }
            // Aynı adresten yeni akış: eskisi "yerine başkası geldi" ile düşer, TV bir kez görünür.
            val (c, _) = legacyLines(hub.legacyLocalPort)
            waitUntil { r.drops().size >= 2 }
            assertEquals(DropReason.REPLACED, r.drops()[1].reason)
            waitUntil { r.events.count { it is DisplayEvent.Connected } >= 3 }
            assertEquals(1, hub.displays.value.size)
            hub.close()
            waitUntil { r.drops().size >= 3 }
            assertEquals(DropReason.STOPPED, r.drops()[2].reason)
            b.close(); c.close()
        }
    }

    @Test fun reasonClassification() {
        assertEquals(DropReason.TIMEOUT, DropReason.of(SocketTimeoutException()))
        assertEquals(DropReason.NETWORK_LOST, DropReason.of(NoRouteToHostException()))
        assertEquals(DropReason.NETWORK_LOST, DropReason.of(SocketException("Network is unreachable")))
        assertEquals(DropReason.CLOSED, DropReason.of(SocketException("Connection reset")))
        assertEquals(DropReason.TIMEOUT, DropReason.of(SocketException("Connection timed out")))
        assertEquals(DropReason.NETWORK_LOST, DropReason.of(SocketException("Software caused connection abort")))
        assertEquals(DropReason.OTHER, DropReason.of(IllegalStateException()))
        assertEquals(ConnectFailure.REFUSED, ConnectFailure.of(ConnectException("Connection refused")))
        assertEquals(ConnectFailure.TIMEOUT, ConnectFailure.of(SocketTimeoutException()))
        assertEquals(ConnectFailure.TIMEOUT, ConnectFailure.of(NinoSender.SenderException.Timeout()))
        assertEquals(ConnectFailure.PROTOCOL, ConnectFailure.of(NinoSender.SenderException.VersionUnsupported(listOf(9))))
        assertEquals(ConnectFailure.NETWORK, ConnectFailure.of(ConnectException("Network is unreachable")))
        assertEquals(ConnectFailure.OTHER, ConnectFailure.of(IllegalStateException()))
    }
}
