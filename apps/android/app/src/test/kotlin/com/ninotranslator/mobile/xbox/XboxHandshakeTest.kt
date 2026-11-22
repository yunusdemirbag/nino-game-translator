// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.xbox

import com.ninotranslator.core.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class XboxHandshakeTest {
    private val base = "https://uks.core.gssv-play-prodxhome.xboxlive.com"
    private val host = XboxStreamHost(base, "GS", Long.MAX_VALUE)
    private val sleeps = mutableListOf<Long>()

    private fun flow(server: FakeServer) = XboxHandshake(XboxStreamApi(server) { host }, { "TT" }) { sleeps += it }

    private fun problem(block: () -> Unit): XboxStreamException =
        try { block(); fail("hata bekleniyordu"); throw IllegalStateException() } catch (e: XboxStreamException) { e }

    @Test fun playSendsServerIdAndReturnsSessionId() {
        val server = FakeServer().on("/play", 200, """{"sessionPath":"v5/sessions/home/ABC-123"}""")
        assertEquals("ABC-123", flow(server).open("F400"))
        val r = server.last("/play")
        assertEquals("POST", r.method)
        assertEquals("$base/v5/sessions/home/play", r.url)
        assertEquals("Bearer GS", r.headers["Authorization"])
        assertEquals("XboxComBrowser", r.headers["X-Gssv-Client"])
        assertTrue(r.headers["X-MS-Device-Info"]!!.contains("Microsoft.GamingApp"))
        val body = Json.parseObject(server.bodyOf(r))
        assertEquals("F400", body["serverId"])
        @Suppress("UNCHECKED_CAST") val s = body["settings"] as Map<String, Any?>
        assertEquals("V3;WebrtcTransport.dll", s["nanoVersion"])
        assertEquals("en-US", s["locale"]); assertEquals("web", s["sdkType"]); assertEquals("windows", s["osName"])
        assertEquals(false, s["enableOptionalDataCollection"])
    }

    @Test fun stateMachineConnectsOnceThenProvisions() {
        val server = FakeServer()
            .on("/state", 200, """{"state":"Provisioning"}""")
            .on("/state", 200, """{"state":"ReadyToConnect","errorDetails":{"code":null,"message":""}}""")
            .on("/state", 200, """{"state":"ReadyToConnect"}""")
            .on("/state", 200, """{"state":"Provisioned"}""")
            .on("/connect", 200, "")
        flow(server).awaitProvisioned("S1")
        assertEquals(1, server.count("/connect"))
        assertEquals("""{"userToken":"TT"}""", server.bodyOf(server.last("/connect")))
        assertEquals(listOf(1000L, 1000L, 1000L), sleeps)
    }

    @Test fun consoleRejectionIsNotRetried() {
        val busy = problem { flow(FakeServer().on("/state", 200, """{"state":"Failed","errorDetails":{"code":"InUse","message":"x"}}""")).awaitProvisioned("S") }
        assertEquals(XboxProblem.BUSY, busy.problem); assertTrue(busy.rejected)
        val other = problem { flow(FakeServer().on("/state", 200, """{"state":"Provisioning","errorDetails":{"code":"NoConsole"}}""")).awaitProvisioned("S") }
        assertEquals(XboxProblem.UNREACHABLE, other.problem); assertTrue(other.rejected)
        val already = problem { flow(FakeServer().on("/state", 200, """{"state":"Failed","errorDetails":{"message":"AlreadyStreaming"}}""")).awaitProvisioned("S") }
        assertEquals(XboxProblem.BUSY, already.problem)
    }

    @Test fun emptyErrorDetailsAreNotErrors() {
        assertFalse(XboxHandshake.hasError(null))
        assertFalse(XboxHandshake.hasError(emptyMap()))
        assertFalse(XboxHandshake.hasError(mapOf("code" to null, "message" to "", "inner" to mapOf("x" to null))))
        assertTrue(XboxHandshake.hasError(mapOf("code" to "X")))
    }

    @Test fun stateTimesOutAfterNinetyPolls() {
        val server = FakeServer().on("/state", 200, """{"state":"Provisioning"}""")
        val e = problem { flow(server).awaitProvisioned("S") }
        assertEquals(XboxProblem.TIMEOUT, e.problem); assertFalse(e.rejected)
        assertEquals(90, server.count("/state"))
    }

    @Test fun httpErrorsAreClassified() {
        assertEquals(XboxProblem.SIGN_IN, XboxStreamApi.classify(401, ""))
        assertEquals(XboxProblem.SIGN_IN, XboxStreamApi.classify(403, "InUse"))
        assertEquals(XboxProblem.BUSY, XboxStreamApi.classify(409, """{"code":"InUse"}"""))
        assertEquals(XboxProblem.BUSY, XboxStreamApi.classify(500, "ConsoleBusy"))
        assertEquals(XboxProblem.UNREACHABLE, XboxStreamApi.classify(404, ""))
        assertEquals(XboxProblem.UNREACHABLE, XboxStreamApi.classify(400, "ConsoleOffline"))
        assertEquals(XboxProblem.SERVICE, XboxStreamApi.classify(500, "boom"))
        val e = problem { flow(FakeServer().on("/play", 404, "")).open("X") }
        assertEquals(XboxProblem.UNREACHABLE, e.problem)
        assertEquals(XboxProblem.NETWORK, problem { flow(FakeServer().fail("/play")).open("X") }.problem)
    }

    private class FakePeer(private val offer: String) : XboxPeerSide {
        var local: String? = null
        var answer: String? = null
        val remote = mutableListOf<XboxIceCandidate>()
        var waited = 0L
        override fun makeOffer() = offer
        override fun applyLocal(sdp: String) { local = sdp }
        override fun applyAnswer(sdp: String) { answer = sdp }
        override fun collectCandidates(maxWaitMs: Long): List<XboxIceCandidate> {
            waited = maxWaitMs
            return listOf(XboxIceCandidate("a=candidate:1 1 UDP 2122 192.168.0.5 50000 typ host", "0", 0))
        }
        override fun addRemote(candidate: XboxIceCandidate) { remote += candidate }
    }

    @Test fun negotiationExchangesSdpAndIce() {
        val answer = Json.write(mapOf("sdp" to "v=0 answer", "sdpType" to "answer"))
        val ice = Json.write(listOf(
            mapOf("candidate" to "a=candidate:1 1 UDP 100 2001:0:4136:e378:8000:63bf:3fff:fdd2 1234 typ host", "sdpMid" to "0", "sdpMLineIndex" to "0"),
            mapOf("candidate" to "a=candidate:2 1 UDP 50 192.168.0.9 9002 typ host", "sdpMid" to "0", "sdpMLineIndex" to 0),
            mapOf("candidate" to "a=end-of-candidates", "sdpMid" to "0", "sdpMLineIndex" to 0),
        ))
        val server = FakeServer()
            .on("/sdp", 200, "{}")       // POST
            .on("/sdp", 204, "")         // ilk GET: henüz yok
            .on("/sdp", 200, Json.write(mapOf("exchangeResponse" to answer)))
            .on("/ice", 200, Json.write(mapOf("exchangeResponse" to ice)))  // POST yanıtı hemen taşır
        val peer = FakePeer("a=fmtp:111 minptime=10;useinbandfec=1\r\na=fmtp:112 useinbandfec=1\r\n")
        flow(server).negotiate("S", peer)
        assertEquals("a=fmtp:111 minptime=10;useinbandfec=1; stereo=1\r\na=fmtp:112 useinbandfec=1\r\n", peer.local)
        assertEquals("v=0 answer", peer.answer)
        assertEquals(5000L, peer.waited)
        val offerBody = Json.parseObject(server.bodyOf(server.requests.first { it.url.endsWith("/sdp") && it.method == "POST" }))
        assertEquals("offer", offerBody["messageType"])
        assertEquals(peer.local, offerBody["sdp"])
        @Suppress("UNCHECKED_CAST") val cfg = offerBody["configuration"] as Map<String, Map<String, Any?>>
        assertEquals(8L, (cfg["input"]!!["maxVersion"] as Number).toLong())
        assertEquals(3L, (cfg["control"]!!["maxVersion"] as Number).toLong())
        assertEquals(24000L, (cfg["chatConfiguration"]!!["sampleFrequencyHz"] as Number).toLong())
        val iceBody = Json.parseObject(server.bodyOf(server.requests.first { it.url.endsWith("/ice") }))
        assertEquals("iceCandidate", iceBody["messageType"])
        assertEquals(listOf(250L, 250L), sleeps)
        assertEquals(listOf(
            "a=candidate:10 1 UDP 1 192.0.2.45 9002 typ host ",
            "a=candidate:11 1 UDP 1 192.0.2.45 40000 typ host ",
            "a=candidate:1 1 UDP 100 2001:0:4136:e378:8000:63bf:3fff:fdd2 1234 typ host",
            "a=candidate:2 1 UDP 50 192.168.0.9 9002 typ host",
        ), peer.remote.map { it.candidate })
    }

    @Test fun exchangeGivesUpAfterThirtyPolls() {
        val server = FakeServer().on("/sdp", 200, "{}").on("/sdp", 204, "")
        val e = problem { flow(server).negotiate("S", FakePeer("v=0")) }
        assertEquals(XboxProblem.TIMEOUT, e.problem)
        assertEquals(30, sleeps.size)
        assertEquals(31, server.count("/sdp"))
    }

    @Test fun keepaliveAndDeletePaths() {
        val server = FakeServer().on("/keepalive", 200, "").on("/sessions/home/S", 200, "")
        val api = XboxStreamApi(server) { host }
        api.keepalive("S"); api.delete("S")
        assertEquals("POST", server.requests[0].method); assertTrue(server.requests[0].url.endsWith("/v5/sessions/home/S/keepalive"))
        assertEquals("DELETE", server.requests[1].method); assertEquals("$base/v5/sessions/home/S", server.requests[1].url)
    }

    @Test fun teredoDecoding() {
        assertEquals("192.0.2.45" to 40000, XboxSdp.teredo("2001:0000:4136:e378:8000:63bf:3fff:fdd2"))
        assertEquals("192.0.2.45" to 40000, XboxSdp.teredo("2001::4136:e378:8000:63bf:3fff:fdd2"))
        assertEquals(null, XboxSdp.teredo("2002::1"))
        assertEquals(null, XboxSdp.teredo("192.168.0.1"))
    }

    @Test fun stereoOnlyFirst() {
        assertEquals("x", XboxSdp.withStereo("x"))
        assertEquals("useinbandfec=1; stereo=1 useinbandfec=1", XboxSdp.withStereo("useinbandfec=1 useinbandfec=1"))
    }
}
