// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.pool

import com.ninotranslator.core.http.UrlConnectionTransport
import com.ninotranslator.core.json.Json
import com.ninotranslator.core.packs.PackKey
import com.ninotranslator.core.packs.TestFiles
import com.ninotranslator.core.translation.FakeClock
import com.sun.net.httpserver.HttpExchange
import com.sun.net.httpserver.HttpServer
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.io.File
import java.net.InetSocketAddress
import java.util.concurrent.atomic.AtomicInteger

/** Yerel sahte havuz sunucusu. */
class PoolTest {
    private lateinit var server: HttpServer
    private lateinit var base: String
    private val clock = FakeClock(50_000_000)
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val log = ArrayList<String>()
    private val translateCalls = AtomicInteger()
    @Volatile private var config = """{"translate":{"enabled":true,"syncSeconds":60,"contextLines":2,"maxLines":2},"downloads":1234}"""

    private fun reply(x: HttpExchange, code: Int, body: String) {
        val b = body.toByteArray(); x.sendResponseHeaders(code, b.size.toLong()); x.responseBody.use { it.write(b) }
    }

    @Before fun start() {
        server = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
        server.createContext("/") { x ->
            val path = x.requestURI.toString()
            val body = x.requestBody.readBytes().toString(Charsets.UTF_8)
            synchronized(log) { log += "${x.requestMethod} $path ${x.requestHeaders.getFirst("User-Agent")}" + if (body.isNotEmpty()) " $body" else "" }
            when {
                path.startsWith("/v1/config") -> reply(x, 200, config)
                path.startsWith("/v1/translations") -> {
                    val q = x.requestURI.query
                    if (!q.contains("after=")) reply(x, 200, """{"items":[["${PackKey.of("Hello")}","Merhaba",100],["kısa"]],"next":{"since":100,"after":"c1"}}""")
                    else reply(x, 200, """{"items":[["${PackKey.of("Bye")}","Hoşça kal",150]],"next":null}""")
                }
                path.startsWith("/v1/translate") -> {
                    translateCalls.incrementAndGet()
                    Thread.sleep(150)
                    val m = Json.parseObject(body)
                    val lines = m["lines"] as List<*>
                    reply(x, 200, Json.write(mapOf("game" to "gta-6", "translations" to lines.map { mapOf("text" to "TR:$it") })))
                }
                path.startsWith("/v1/identify") -> reply(x, 200, """{"game":"Elden Ring"}""")
                path.startsWith("/v1/ping") -> reply(x, 200, "{}")
                else -> reply(x, 404, "")
            }
        }
        server.start()
        base = "http://127.0.0.1:${server.address.port}"
    }

    @After fun stop() = server.stop(0)

    private fun pool(files: File = TestFiles.tempDir()) = SharedPool(files, UrlConnectionTransport, "1.2.3", scope, clock.now, endpoint = base)

    @Test fun endpointFile() {
        val files = TestFiles.tempDir()
        assertEquals(PoolEndpoint.DEFAULT, PoolEndpoint.resolve(files))
        File(files, "pool").mkdirs()
        File(files, "pool/endpoint.txt").writeText("ftp://x")
        assertEquals(PoolEndpoint.DEFAULT, PoolEndpoint.resolve(files))
        File(files, "pool/endpoint.txt").writeText(" http://localhost:9/ \n")
        assertEquals("http://localhost:9", PoolEndpoint.resolve(files))
        assertEquals("nino-pool/1 (android; 1.2.3)", PoolEndpoint.userAgent("1.2.3"))
        val id = PoolInstall.read(files)
        assertTrue(PoolInstall.isUuid(id)); assertEquals(id, PoolInstall.read(files))
    }

    @Test fun configAndPoolFirst() = runBlocking {
        val p = pool()
        assertTrue(p.isPoolFirst("grand-theft-auto-vi", "tr"))
        assertFalse(p.isPoolFirst("grand-theft-auto-vi", "ar"))
        config = """{"translate":{"enabled":true},"poolFirst":{"games":["elden"],"deadlineMs":50000,"langs":["*"]}}"""
        p.refreshConfig(force = true)
        assertTrue(p.isPoolFirst("elden-ring", "ar")); assertFalse(p.isPoolFirst("gta-6", "tr"))
        assertEquals(10_000L, p.poolFirstDeadlineMs)
        config = """{"translate":{"enabled":false}}"""
        p.refreshConfig(force = true)
        assertFalse(p.isPoolFirst("grand-theft-auto-vi", "tr"))
        assertNull(p.ask("Hello there friend", "tr", null, emptyList(), force = true))
    }

    @Test fun syncPagesAndStoresOnDisk() = runBlocking {
        val files = TestFiles.tempDir()
        val p = pool(files)
        p.refreshConfig()
        assertEquals(1234L, p.downloads)
        assertEquals(2, p.sync("rdr2", force = true))
        assertEquals("Merhaba", p.lookup("tr", PackKey.of("Hello")!!))
        assertEquals(0, p.sync("rdr2")) // en erken 60 sn sonra
        val reqs = log.filter { it.contains("/v1/translations") }
        assertEquals(2, reqs.size)
        assertTrue(reqs[0].contains("lang=tr&since=0&game=rdr2 nino-pool/1 (android; 1.2.3)"))
        assertTrue(reqs[1].contains("after=c1"))
        val disk = Json.parseObject(File(files, "translation-pool/translations-tr.json").readText())
        assertEquals("tr", disk["language"])
        assertEquals(150L, ((disk["cursors"] as Map<*, *>)["rdr2"] as Map<*, *>)["since"])
        // Havuz kapalıyken bellek boş ve hiçbir şey sorulmaz.
        p.disable()
        assertNull(p.lookup("tr", PackKey.of("Hello")!!))
        assertEquals(0, p.sync("rdr2", force = true))
        assertFalse(File(files, "translation-pool/translations-tr.json").exists())
    }

    @Test fun askDeduplicatesAndRemembersServerGame() = runBlocking {
        val p = pool()
        p.refreshConfig()
        val answers = (0 until 3).map { scope.async { p.ask("Where is the car?", "tr", null, listOf("a", "b", "c"), force = false) } }.awaitAll()
        assertEquals(List(3) { "TR:Where is the car?" }, answers)
        assertEquals(1, translateCalls.get())
        assertEquals("TR:Where is the car?", p.ask("Where is the car?", "tr", null, emptyList(), force = false))
        assertEquals(1, translateCalls.get())
        val body = Json.parseObject(log.first { it.startsWith("POST /v1/translate") }.substringAfter("1.2.3) "))
        assertEquals(listOf("b", "c"), body["context"]); assertEquals("android", body["platform"]); assertEquals(1L, body["v"])
        // Sunucu oyunu tanıdı (gta-6): 600 sn havuz öncelikli.
        assertTrue(p.isPoolFirst(null, "tr"))
        clock.advance(600_001)
        assertFalse(p.isPoolFirst(null, "tr"))
        // Türkçe ya da sistem yazısı sorulmaz; havuz kapalıyken yalnız force ile.
        assertNull(p.ask("Oturum açıldı ğ", "tr", null, emptyList(), false))
        p.shareEnabled = false
        assertNull(p.ask("Another line here", "tr", null, emptyList(), false))
        assertEquals("TR:Another line here", p.ask("Another line here", "tr", null, emptyList(), true))
    }

    @Test fun askManyChunksAndIdentify() = runBlocking {
        val p = pool()
        p.refreshConfig()
        val out = p.askMany(listOf("One line", "Two line", "Three line", "Hello"), "tr", "gta-6", emptyList(), force = false)
        assertEquals(listOf("TR:One line", "TR:Two line", "TR:Three line", "TR:Hello"), out)
        assertEquals(2, translateCalls.get()) // maxLines 2
        assertEquals("Elden Ring", p.identify("AAAA"))
        val id = Json.parseObject(log.first { it.startsWith("POST /v1/identify") }.substringAfter("1.2.3) "))
        assertEquals("AAAA", id["image"]); assertEquals(p.install, id["install"])
        assertTrue(p.ping("gta-6"))
        assertTrue(log.any { it.startsWith("GET /v1/ping?install=${p.install}&platform=android&app=1.2.3&game=gta-6&lang=tr") })
    }

    @Test fun identifySchedule() {
        val s = IdentifySchedule(0)
        assertEquals(8_000L, s.nextAt())
        s.record(8_000, null); assertEquals(68_000L, s.nextAt())
        repeat(5) { s.record(s.nextAt()!!, null) }
        assertNull(s.nextAt())
        val t = IdentifySchedule(0)
        t.record(8_000, "Elden Ring")
        assertEquals(8_000L + 300_000, t.nextAt())
        t.record(t.nextAt()!!, "Elden Ring"); assertEquals(308_000L + 1_200_000, t.nextAt())
    }

    @Test fun lineFilter() {
        assertEquals("a b c", PoolLineFilter.clean("a​ b\t\n c "))
        assertTrue(PoolLineFilter.accepts("Get to the chopper!"))
        assertFalse(PoolLineFilter.accepts("12345"))
        assertFalse(PoolLineFilter.accepts("Kapıyı aç"))
        assertFalse(PoolLineFilter.accepts("Player1 signed in"))
        assertFalse(PoolLineFilter.accepts("Lütfen bekleyin"))
        assertFalse(PoolLineFilter.accepts("#@!% ab ?!?!"))
        assertFalse(PoolLineFilter.accepts("a".repeat(501)))
    }
}
