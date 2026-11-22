// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.remoteplay

import com.ninotranslator.core.http.HttpResponse
import com.ninotranslator.core.http.HttpTransport
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PsnLoginTest {
    @Test fun authorizeUrlHasParametersInOrder() {
        val u = PsnLogin.authorizeUrl
        assertTrue(u.startsWith("https://auth.api.sonyentertainmentnetwork.com/2.0/oauth/authorize?service_entity=urn%3Aservice-entity%3Apsn&response_type=code&client_id=ba495a24"))
        assertTrue(u.contains("scope=psn%3Aclientapp%20referenceDataService"))
        assertTrue(u.endsWith("&prompt=always&PlatformPrivacyWs1=minimal"))
    }

    @Test fun extractsRedirectFromSurroundingText() {
        val t = "kopya: \"https://remoteplay.dl.playstation.net/remoteplay/redirect?code=AbC123&cid=x\" sonu"
        assertEquals("https://remoteplay.dl.playstation.net/remoteplay/redirect?code=AbC123&cid=x", PsnLogin.extractRedirect(t))
        assertNull(PsnLogin.extractRedirect("https://remoteplay.dl.playstation.net/remoteplay/redirect?code="))
        assertNull(PsnLogin.extractRedirect("https://example.com/?code=1"))
        assertEquals("https://remoteplay.dl.playstation.net/remoteplay/redirect?error=access_denied",
            PsnLogin.extractRedirect("https://remoteplay.dl.playstation.net/remoteplay/redirect?error=access_denied<br>"))
    }

    @Test fun parsesErrorsAndRateLimit() {
        val r = PsnLogin.parseRedirect("https://remoteplay.dl.playstation.net/remoteplay/redirect?error=invalid_request&error_description=Too+many+requests&error_code=4165")
        r as PsnLogin.Redirect.Error
        assertEquals("invalid_request · Too many requests · 4165", r.message)
        assertTrue(r.rateLimited)
        val c = PsnLogin.parseRedirect("https://remoteplay.dl.playstation.net/remoteplay/redirect?code=v3.ABC%2Bx")
        assertEquals(PsnLogin.Redirect.Code("v3.ABC+x"), c)
    }

    @Test fun recognisesGoogle() {
        assertTrue(PsnLogin.isGoogle("https://accounts.google.com/o/oauth2/auth?x=1"))
        assertFalse(PsnLogin.isGoogle("https://my.account.sony.com/"))
    }

    @Test fun exchangesCodeForAccountId() {
        val calls = ArrayList<String>()
        val http = HttpTransport { req ->
            calls += req.method + " " + req.url
            if (req.method == "POST") {
                assertTrue(req.headers["Authorization"]!!.startsWith("Basic "))
                assertTrue(String(req.body!!).startsWith("grant_type=authorization_code&code=abc&scope="))
                HttpResponse(200, body = "{\"access_token\":\"tok\"}".toByteArray())
            } else HttpResponse(200, body = "{\"user_id\":\"1234567890123456789\"}".toByteArray())
        }
        val id = PsnLogin.accountIdFromRedirect("https://remoteplay.dl.playstation.net/remoteplay/redirect?code=abc", http)
        assertArrayEquals(PsnAccountId.fromUserId("1234567890123456789"), id)
        assertEquals("GET https://auth.api.sonyentertainmentnetwork.com/2.0/oauth/token/tok", calls[1])
    }

    @Test(expected = PsnLogin.LoginException::class)
    fun tokenRejectionThrows() {
        PsnLogin.exchange("abc") { HttpResponse(400, body = "{\"error\":\"invalid_grant\"}".toByteArray()) }
    }
}
