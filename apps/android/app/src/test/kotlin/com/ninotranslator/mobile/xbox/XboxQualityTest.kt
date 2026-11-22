// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.xbox

import com.ninotranslator.core.json.Json
import com.ninotranslator.mobile.data.XboxQuality
import com.ninotranslator.mobile.service.SourceState
import com.ninotranslator.mobile.service.TextRef
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.io.File

/** Yayın kalitesinin isteğe yansıması ve "oturum başlatılamadı" hatasının metinleri. */
class XboxQualityTest {
    private val host = XboxStreamHost("https://x.example", "GS", Long.MAX_VALUE)

    private fun settingsOf(server: FakeServer): Map<*, *> = Json.parseObject(server.bodyOf(server.last("/play")))["settings"] as Map<*, *>
    private fun dimensions(info: String): Map<*, *> =
        ((Json.parseObject(info)["dev"] as Map<*, *>)["displayInfo"] as Map<*, *>)["dimensions"] as Map<*, *>

    @Test fun profilesMatchQuality() {
        assertEquals(XboxStreamProfile(1920, 1080, "windows", null), XboxStreamProfile.of(XboxQuality.P1080))
        val p = XboxStreamProfile.of(XboxQuality.P720)
        assertEquals(1280, p.width); assertEquals(720, p.height); assertEquals("android", p.osName)
        assertEquals(4000, p.maxBitrateKbps)
    }

    @Test fun p720AsksForLowerResolution() {
        val server = FakeServer().on("/play", 200, """{"sessionPath":"v5/sessions/home/S"}""")
        XboxStreamApi(server, XboxStreamProfile.P720) { host }.play("F", 0)
        assertEquals("android", settingsOf(server)["osName"])
        val d = dimensions(server.last("/play").headers["X-MS-Device-Info"]!!)
        assertEquals(1280L, (d["widthInPixels"] as Number).toLong()); assertEquals(720L, (d["heightInPixels"] as Number).toLong())
    }

    @Test fun defaultStays1080() {
        val server = FakeServer().on("/play", 200, """{"sessionPath":"v5/sessions/home/S"}""")
        XboxStreamApi(server) { host }.play("F", 0)
        assertEquals("windows", settingsOf(server)["osName"])
        assertEquals(1920L, (dimensions(server.last("/play").headers["X-MS-Device-Info"]!!)["widthInPixels"] as Number).toLong())
    }

    @Test fun dimensionsMessageFollowsProfile() {
        val last = Json.parseObject(XboxChannelMessages.configuration(1280, 720) { "id" }.last())
        val content = Json.parseObject(last["content"] as String)
        assertEquals(1280L, (content["preferredWidth"] as Number).toLong())
        assertEquals(720L, (content["safeAreaBottom"] as Number).toLong())
    }

    @Test fun bitrateGoesIntoVideoSectionOnly() {
        val sdp = "v=0\r\nm=audio 9 UDP 111\r\nc=IN IP4 0.0.0.0\r\nm=video 9 UDP 96\r\nc=IN IP4 0.0.0.0\r\nb=AS:9000\r\na=mid:1\r\n"
        val out = XboxSdp.withVideoBitrate(sdp, 4000)
        assertEquals("v=0\r\nm=audio 9 UDP 111\r\nc=IN IP4 0.0.0.0\r\nm=video 9 UDP 96\r\nc=IN IP4 0.0.0.0\r\nb=AS:4000\r\na=mid:1\r\n", out)
        assertEquals(sdp, XboxSdp.withVideoBitrate(sdp, null))
        assertEquals("v=0\nm=video 9\nb=AS:2500\na=x", XboxSdp.withVideoBitrate("v=0\nm=video 9\na=x", 2500))
        assertEquals("v=0\nm=audio 9", XboxSdp.withVideoBitrate("v=0\nm=audio 9", 2500))
    }

    @Test fun offerCarriesBitrateAt720() {
        val answer = Json.write(mapOf("sdp" to "v=0 answer"))
        val server = FakeServer().on("/sdp", 200, Json.write(mapOf("exchangeResponse" to answer)))
            .on("/ice", 200, Json.write(mapOf("exchangeResponse" to "[]")))
        val peer = object : XboxPeerSide {
            var local = ""
            override fun makeOffer() = "v=0\r\nm=video 9 UDP 96\r\nc=IN IP4 0.0.0.0\r\n"
            override fun applyLocal(sdp: String) { local = sdp }
            override fun applyAnswer(sdp: String) {}
            override fun collectCandidates(maxWaitMs: Long) = emptyList<XboxIceCandidate>()
            override fun addRemote(candidate: XboxIceCandidate) {}
        }
        XboxHandshake(XboxStreamApi(server, XboxStreamProfile.P720) { host }, { "T" }) {}.negotiate("S", peer)
        assertTrue(peer.local.contains("b=AS:4000"))
        assertEquals(peer.local, Json.parseObject(server.bodyOf(server.requests.first { it.url.endsWith("/sdp") }))["sdp"])
    }

    @Test fun startStreamingSessionFailureIsRecognised() {
        val e = try {
            XboxHandshake(XboxStreamApi(FakeServer().on("/state", 200,
                """{"state":"Failed","errorDetails":{"code":"StartStreamingSessionFailed","message":"StartStreamingSession failed"}}""")) { host },
                { "T" }) {}.awaitProvisioned("S")
            fail(); throw IllegalStateException()
        } catch (x: XboxStreamException) { x }
        assertEquals(XboxProblem.START_FAILED, e.problem); assertTrue(e.rejected)
        assertEquals(XboxProblem.BUSY, XboxHandshake.rejectReason(mapOf("code" to "InUse")))
        assertEquals(XboxProblem.UNREACHABLE, XboxHandshake.rejectReason(mapOf("code" to "NoConsole")))
    }

    @Test fun startFailureTextsAndHelp() {
        assertEquals(XboxTexts.START_FAILED, XboxTexts.retryKey(XboxProblem.START_FAILED))
        assertEquals("xbox_reason_start_failed", XboxTexts.reasonKey(XboxProblem.START_FAILED))
        assertEquals(SourceState.Failed(XboxTexts.START_FAILED), XboxTexts.giveUp(XboxProblem.START_FAILED) { "?" })
        assertEquals(SourceState.Failed(XboxTexts.GAVE_UP, "R:xbox_reason_busy"), XboxTexts.giveUp(XboxProblem.BUSY) { "R:$it" })
        assertEquals(TextRef(XboxTexts.START_HELP), XboxTexts.help(SourceState.Failed(XboxTexts.START_FAILED), XboxQuality.P1080))
        assertEquals(TextRef(XboxTexts.START_HELP_720), XboxTexts.help(SourceState.Failed(XboxTexts.START_FAILED), XboxQuality.P720))
        assertNull(XboxTexts.help(SourceState.Failed(XboxTexts.GAVE_UP, "x"), XboxQuality.P1080))
        assertNull(XboxTexts.help(SourceState.Streaming, XboxQuality.P1080))
        // Rejected oturum yeniden denenmez: doğrudan çözüm adımları gösterilir.
        assertEquals(XboxNext.GiveUp(XboxProblem.START_FAILED), XboxRetryPolicy().onEnded(XboxProblem.START_FAILED, true, 0))
    }

    @Test fun helpTextsExistInEveryLanguage() {
        val res = File("src/main/res")
        val dirs = res.listFiles().orEmpty().filter { it.name == "values" || it.name.startsWith("values-") }.filter { File(it, "strings.xml").exists() }
        assertTrue(dirs.size >= 13)
        for (d in dirs) {
            val xml = File(d, "strings.xml").readText()
            for (k in listOf(XboxTexts.START_FAILED, XboxTexts.START_HELP, XboxTexts.START_HELP_720, "xbox_reason_start_failed",
                "settings_xbox_quality", "settings_xbox_quality_note")) assertTrue("${d.name}: $k", xml.contains("name=\"$k\""))
            val help = Regex("name=\"${XboxTexts.START_HELP}\">(.*?)</string>").find(xml)!!.groupValues[1]
            assertTrue("${d.name}: 720p önerisi", help.contains("720p"))
            assertTrue("${d.name}: adımlar", help.contains("\\n5. "))
        }
    }
}
