// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.xbox

import com.ninotranslator.core.json.Json
import com.ninotranslator.mobile.xbox.XboxSamples.iso
import com.ninotranslator.mobile.xbox.XboxSamples.xbl
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class XboxAuthTest {
    private var clock = 1_800_000_000_000L
    private val ms = "oauth2/v2.0/token"

    private fun signedStore(expiresAt: Long = clock + 3_600_000) = MemoryTokenStore(mapOf(
        "access_token" to "AT", "refresh_token" to "RT", "expires_on" to iso(expiresAt), "token_type" to "bearer"))

    private fun expectKind(kind: XboxErrorKind, block: () -> Unit) {
        try { block(); fail("hata bekleniyordu") } catch (e: XboxException) { assertEquals(kind, e.kind) }
    }

    @Test fun deviceCodeAndPollBodies() {
        val b = XboxAuthWire.deviceCodeBody()
        assertTrue(b.contains("client_id=1f907974-e22b-4810-a9de-d9647380c97e"))
        assertTrue(b.contains("scope=xboxlive.signin+openid+profile+offline_access"))
        val p = XboxAuthWire.devicePollBody("DC")
        assertTrue(p.contains("grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Adevice_code"))
        assertTrue(p.contains("device_code=DC"))
        val r = XboxAuthWire.refreshBody("R1")
        assertTrue(r.contains("grant_type=refresh_token") && r.contains("refresh_token=R1") && r.contains("scope="))
        val t = XboxAuthWire.transferBody("R1")
        assertTrue(t.contains("scope=service%3A%3Ahttp%3A%2F%2FPassport.NET%2Fpurpose%3A%3APURPOSE_XBOX_CLOUD_CONSOLE_TRANSFER_TOKEN"))
    }

    @Test fun deviceCodeDefaults() {
        val g = XboxAuthWire.parseDeviceCode("""{"device_code":"D","user_code":"ABCD-EFGH","interval":0}""")!!
        assertEquals("https://www.microsoft.com/link", g.verificationUri)
        assertEquals(900L, g.expiresInSec)
        assertEquals(1L, g.intervalSec)
        assertEquals(5L, XboxAuthWire.parseDeviceCode("""{"device_code":"D","user_code":"U"}""")!!.intervalSec)
        assertNull(XboxAuthWire.parseDeviceCode("""{"user_code":"U"}"""))
    }

    @Test fun pollOutcomes() {
        assertEquals(DevicePoll.Pending, XboxAuthWire.parsePoll(400, """{"error":"authorization_pending"}"""))
        assertEquals(DevicePoll.SlowDown, XboxAuthWire.parsePoll(400, """{"error":"slow_down"}"""))
        assertEquals(DevicePoll.Expired, XboxAuthWire.parsePoll(400, """{"error":"expired_token"}"""))
        assertEquals(DevicePoll.Expired, XboxAuthWire.parsePoll(400, """{"error":"code_expired"}"""))
        assertEquals(DevicePoll.Declined, XboxAuthWire.parsePoll(400, """{"error":"authorization_declined"}"""))
        assertEquals(DevicePoll.Declined, XboxAuthWire.parsePoll(400, """{"error":"access_denied"}"""))
        assertEquals(DevicePoll.ServerBusy, XboxAuthWire.parsePoll(503, ""))
        assertTrue(XboxAuthWire.parsePoll(400, """{"error":"invalid_grant"}""") is DevicePoll.Failed)
        assertTrue(XboxAuthWire.parsePoll(200, """{"access_token":"A","refresh_token":"R"}""") is DevicePoll.Done)
    }

    @Test fun xboxBodies() {
        assertEquals("""{"Properties":{"AuthMethod":"RPS","RpsTicket":"d=AT","SiteName":"user.auth.xboxlive.com"},"RelyingParty":"http://auth.xboxlive.com","TokenType":"JWT"}""",
            XboxAuthWire.userTokenBody("AT"))
        assertEquals("""{"Properties":{"SandboxId":"RETAIL","UserTokens":["UT"]},"RelyingParty":"http://gssv.xboxlive.com/","TokenType":"JWT"}""",
            XboxAuthWire.xstsBody("UT", XboxAuthWire.RP_GSSV))
        assertEquals("""{"token":"G","offeringId":"xhome"}""", XboxAuthWire.streamLoginBody("G"))
    }

    @Test fun notAfterWithSevenDigits() {
        val t = XboxAuthWire.parseXblToken(xbl("X", "2026-11-22T10:16:00.1234567Z"))!!
        assertEquals(java.time.Instant.parse("2026-11-22T10:16:00.123Z").toEpochMilli(), t.expiresAtMs)
        assertEquals("UHS1", t.uhs)
    }

    @Test fun freshAccessTokenNeedsNoNetwork() {
        val server = FakeServer()
        val chain = XboxTokenChain(server, signedStore(), { clock })
        assertEquals("AT", chain.accessToken())
        assertEquals(0, server.requests.size)
    }

    @Test fun accessTokenRefreshedWithinSixtySecondsAndKeepsRefreshToken() {
        val store = signedStore(expiresAt = clock + 59_000)
        val server = FakeServer().on(ms, 200, """{"access_token":"AT2","expires_in":3600}""")
        val chain = XboxTokenChain(server, store, { clock })
        assertEquals("AT2", chain.accessToken())
        assertEquals(1, server.count(ms))
        assertTrue(server.bodyOf(server.last(ms)).contains("refresh_token=RT"))
        assertEquals("RT", store.saved!!["refresh_token"])
        assertEquals(iso(clock + 3_600_000), store.saved!!["expires_on"])
        // İkinci çağrı bellekten.
        assertEquals("AT2", chain.accessToken())
        assertEquals(1, server.count(ms))
    }

    @Test fun refreshRejectedMeansSignIn() {
        val chain = XboxTokenChain(FakeServer().on(ms, 400, """{"error":"invalid_grant"}"""), signedStore(expiresAt = clock), { clock })
        expectKind(XboxErrorKind.SIGN_IN) { chain.accessToken() }
        expectKind(XboxErrorKind.SIGN_IN) { XboxTokenChain(FakeServer(), MemoryTokenStore(), { clock }).accessToken() }
    }

    @Test fun networkErrorIsOffline() {
        val chain = XboxTokenChain(FakeServer().fail("user.auth"), signedStore(), { clock })
        expectKind(XboxErrorKind.OFFLINE) { chain.userToken() }
    }

    @Test fun userTokenHeadersAndCache() {
        val server = FakeServer().on("user.auth", 200, xbl("UT", iso(clock + 3_600_000)))
        val chain = XboxTokenChain(server, signedStore(expiresAt = clock + 86_400_000), { clock })
        assertEquals("UT", chain.userToken().value)
        val r = server.last("user.auth")
        assertEquals("1", r.headers["x-xbl-contract-version"])
        assertEquals("https://www.xbox.com", r.headers["Origin"])
        assertTrue(r.headers["Referer"]!!.startsWith("https://www.xbox.com"))
        chain.userToken()
        assertEquals(1, server.count("user.auth"))
        clock += 3_600_000 - 59_000
        chain.userToken()
        assertEquals(2, server.count("user.auth"))
    }

    @Test fun xstsKeepsSeparateCachePerRelyingParty() {
        val server = FakeServer()
            .on("user.auth", 200, xbl("UT", iso(clock + 3_600_000)))
            .on("xsts", 200, xbl("XS", iso(clock + 3_600_000)))
        val chain = XboxTokenChain(server, signedStore(), { clock })
        chain.xsts(XboxAuthWire.RP_XBOXLIVE); chain.xsts(XboxAuthWire.RP_GSSV); chain.xsts(XboxAuthWire.RP_GSSV)
        assertEquals(2, server.count("xsts"))
        val r = server.last("xsts")
        assertEquals("0", r.headers["ms-cv"])
        assertTrue(r.headers["User-Agent"]!!.contains("Mozilla"))
    }

    @Test fun xstsErrors() {
        fun chainWith(status: Int, body: String) = XboxTokenChain(FakeServer()
            .on("user.auth", 200, xbl("UT", iso(clock + 3_600_000))).on("xsts", status, body), signedStore(), { clock })
        for (err in listOf(2148916233L, 2148916235L, 2148916236L, 2148916237L, 2148916238L))
            expectKind(XboxErrorKind.NO_ACCOUNT) { chainWith(401, """{"XErr":$err}""").xsts(XboxAuthWire.RP_GSSV) }
        expectKind(XboxErrorKind.SIGN_IN) { chainWith(401, """{"XErr":2148916227}""").xsts(XboxAuthWire.RP_GSSV) }
        expectKind(XboxErrorKind.UNEXPECTED) { chainWith(500, "").xsts(XboxAuthWire.RP_GSSV) }
    }

    @Test fun streamLoginPicksDefaultRegion() {
        val body = """{"offeringSettings":{"regions":[{"name":"A","baseUri":"https://a.example"},{"name":"B","baseUri":"https://b.example/","isDefault":true}]},"gsToken":"GS"}"""
        val h = XboxAuthWire.parseStreamHost(body, 1000)!!
        assertEquals("https://b.example", h.baseUri)
        assertEquals("GS", h.token)
        assertEquals(1000 + 1_800_000L, h.expiresAtMs)
        val first = XboxAuthWire.parseStreamHost("""{"offeringSettings":{"regions":[{"baseUri":"https://a"}]},"gsToken":"G","durationInSeconds":60}""", 0)!!
        assertEquals("https://a", first.baseUri)
        assertEquals(60_000L, first.expiresAtMs)

        val server = FakeServer()
            .on("user.auth", 200, xbl("UT", iso(clock + 3_600_000)))
            .on("xsts", 200, xbl("XS", iso(clock + 3_600_000)))
            .on("xhome.gssv-play-prod", 200, body)
        XboxTokenChain(server, signedStore(), { clock }).streamHost()
        val r = server.last("xhome.gssv-play-prod")
        assertEquals("XboxComBrowser", r.headers["x-gssv-client"])
        assertEquals("""{"token":"XS","offeringId":"xhome"}""", server.bodyOf(r))
    }

    @Test fun transferToken() {
        val server = FakeServer().on("login.live.com", 200, """{"access_token":"TT","expires_in":3600}""")
        val chain = XboxTokenChain(server, signedStore(), { clock })
        assertEquals("TT", chain.transferToken())
        assertTrue(server.bodyOf(server.last("login.live.com")).contains("refresh_token=RT"))
        expectKind(XboxErrorKind.SIGN_IN) {
            XboxTokenChain(FakeServer().on("login.live.com", 400, "{}"), signedStore(), { clock }).transferToken()
        }
    }

    @Test fun consoleListReadyOnlyWithBothFlags() {
        val body = """{"result":[
            {"id":"F1","name":"Salon","consoleType":"XboxSeriesX","powerState":"On","consoleStreamingEnabled":true,"remoteManagementEnabled":true},
            {"id":"F2","name":"","consoleType":"XboxSeriesS","powerState":"ConnectedStandby","consoleStreamingEnabled":true,"remoteManagementEnabled":false},
            {"name":"kimliksiz"}]}"""
        val server = FakeServer()
            .on("user.auth", 200, xbl("UT", iso(clock + 3_600_000)))
            .on("xsts", 200, xbl("XS", iso(clock + 3_600_000), uhs = "H9"))
            .on("xccs.xboxlive.com", 200, body)
        val list = XboxTokenChain(server, signedStore(), { clock }).consoles()
        assertEquals(2, list.size)
        assertEquals("Salon", list[0].name); assertEquals("Series X", list[0].model); assertTrue(list[0].streamingEnabled)
        assertNull(list[1].name); assertFalse(list[1].streamingEnabled); assertEquals("ConnectedStandby", list[1].powerState)
        val r = server.last("xccs")
        assertEquals("XBL3.0 x=H9;XS", r.headers["Authorization"])
        assertEquals("4", r.headers["x-xbl-contract-version"])
        assertEquals("RemoteManagement", r.headers["skillplatform"])
        assertTrue(r.url.endsWith("queryCurrentDevice=false&includeStorageDevices=true"))
    }

    @Test fun deviceSignInSurvivesNetworkErrorsAndSlowDown() = runBlocking {
        val store = MemoryTokenStore()
        val server = FakeServer()
            .on("devicecode", 200, """{"device_code":"D","user_code":"ABCD","verification_uri":"https://www.microsoft.com/link","expires_in":900,"interval":5}""")
        val waits = mutableListOf<Long>()
        val account = LiveXboxAccount(XboxTokenChain(server, store, { clock }), { clock }) { waits += it; clock += it }
        val code = account.requestDeviceCode()
        assertEquals("ABCD", code.userCode)
        assertEquals(clock + 900_000, code.expiresAtMs)
        server.on(ms, 400, """{"error":"authorization_pending"}""")
        server.fail(ms)
        server.on(ms, 400, """{"error":"slow_down"}""")
        server.on(ms, 503, "")
        server.on(ms, 200, """{"access_token":"AT","refresh_token":"RT","expires_in":3600}""")
        account.awaitSignIn(code)
        assertEquals(listOf(5000L, 5000L, 5000L, 10000L, 10000L), waits)
        assertEquals("RT", store.saved!!["refresh_token"])
        assertTrue(store.saved!!.containsKey("expires_on"))
    }

    @Test fun deviceSignInExpiresAndDeclines() = runBlocking {
        val server = FakeServer().on("devicecode", 200, """{"device_code":"D","user_code":"U","expires_in":12,"interval":5}""")
        val account = LiveXboxAccount(XboxTokenChain(server, MemoryTokenStore(), { clock }), { clock }) { clock += it }
        server.on(ms, 400, """{"error":"authorization_pending"}""")
        val code = account.requestDeviceCode()
        try { account.awaitSignIn(code); fail() } catch (e: XboxException) { assertEquals(XboxErrorKind.EXPIRED, e.kind) }

        val s2 = FakeServer().on("devicecode", 200, """{"device_code":"D","user_code":"V"}""").on(ms, 400, """{"error":"access_denied"}""")
        val a2 = LiveXboxAccount(XboxTokenChain(s2, MemoryTokenStore(), { clock }), { clock }) { clock += it }
        try { a2.awaitSignIn(a2.requestDeviceCode()); fail() } catch (e: XboxException) { assertEquals(XboxErrorKind.SIGN_IN, e.kind) }
        Unit
    }

    @Test fun jsonWriterRoundTrip() {
        // Gövdeler çekirdeğin JSON okuyucusuyla geri okunabilmeli.
        val m = Json.parseObject(XboxAuthWire.xstsBody("U", XboxAuthWire.RP_XBOXLIVE))
        assertEquals("http://xboxlive.com", m["RelyingParty"])
    }
}
