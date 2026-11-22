// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.remoteplay

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ReasonsTest {
    private val unknown = "Unknown Session Request Error"

    @Test fun coarseGroups() {
        fun kind(r: Int) = SessionEndReasons.classify(r, "x", emptyList()).kind
        assertEquals(EndKind.STOPPED, kind(QuitReason.STOPPED))
        assertEquals(EndKind.IN_USE, kind(QuitReason.SESSION_REQUEST_RP_IN_USE))
        assertEquals(EndKind.REFUSED, kind(QuitReason.SESSION_REQUEST_CONNECTION_REFUSED))
        assertEquals(EndKind.REFUSED, kind(QuitReason.CTRL_CONNECTION_REFUSED))
        assertEquals(EndKind.REFUSED, kind(QuitReason.PSN_REGIST_FAILED))
        assertEquals(EndKind.NETWORK, kind(QuitReason.STREAM_CONNECTION_REMOTE_DISCONNECTED))
        assertEquals(EndKind.NETWORK, kind(QuitReason.STREAM_CONNECTION_REMOTE_SHUTDOWN))
        assertEquals(EndKind.NETWORK, kind(QuitReason.CTRL_CONNECT_FAILED))
        assertEquals(EndKind.NETWORK, kind(QuitReason.STREAM_CONNECTION_UNKNOWN))
        assertEquals(EndKind.OTHER, kind(QuitReason.CTRL_UNKNOWN))
    }

    @Test fun sessionRequestLinesDecide() {
        fun c(vararg lines: String) = SessionEndReasons.classify(QuitReason.SESSION_REQUEST_UNKNOWN, unknown, lines.toList())
        assertEquals(EndKind.REMOTE_PLAY_DISABLED, c("Reported Application Reason: 0x80108b12 (x)").kind)
        assertEquals(EndKind.REGISTRATION_INVALID, c("Reported Application Reason: 0x80108b26 (x)").kind)
        assertEquals(EndKind.REGISTRATION_INVALID, c("Reported Application Reason: 0x80108b02").kind)
        val rej = c("Reported Application Reason: 0x80108b33 (x)")
        assertEquals(EndKind.REJECTED, rej.kind)
        assertEquals(0x80108b33L, rej.appCode)
        assertEquals(EndKind.NETWORK, c("Session request connect failed eventually.").kind)
        // Son anlamlı satır kazanır.
        assertEquals(EndKind.NETWORK, c("Reported Application Reason: 0x80108b12", "Failed to send session request").kind)
        assertEquals(EndKind.REMOTE_PLAY_DISABLED, c("Failed to send session request", "Reported Application Reason: 0x80108b12").kind)
        val plain = c("something else")
        assertEquals(EndKind.REJECTED, plain.kind)
        assertNull(plain.appCode)
    }

    @Test fun otherWithoutSessionRequestStaysOther() {
        val e = SessionEndReasons.classify(QuitReason.CTRL_UNKNOWN, "Unknown Ctrl Error",
            listOf("Reported Application Reason: 0x80108b12"))
        assertEquals(EndKind.OTHER, e.kind)
        assertTrue(e.kind.retry)
    }

    @Test fun phaseKeys() {
        val host = "192.168.1.20"
        fun key(k: EndKind, code: Long? = null, answered: Boolean = true) =
            SessionEndReasons.phaseKey(SessionEnd(k, code), answered, host)
        assertNull(key(EndKind.STOPPED))
        assertEquals("phase_in_use", key(EndKind.IN_USE))
        assertEquals("phase_refused", key(EndKind.REFUSED))
        assertEquals("phase_network", key(EndKind.NETWORK))
        assertEquals("phase_not_found_host", key(EndKind.NETWORK, answered = false))
        assertEquals("phase_not_found_host", key(EndKind.OTHER, answered = false))
        assertEquals("phase_in_use", key(EndKind.IN_USE, answered = false))
        assertEquals("phase_not_found", SessionEndReasons.phaseKey(SessionEnd(EndKind.NETWORK), false, null))
        assertEquals("phase_registration_invalid", key(EndKind.REGISTRATION_INVALID))
        assertEquals("phase_remote_play_disabled", key(EndKind.REMOTE_PLAY_DISABLED))
        assertEquals("phase_rejected_code", key(EndKind.REJECTED, 0x80108b33L))
        assertEquals("phase_rejected", key(EndKind.REJECTED))
        assertEquals("0x80108b33", SessionEndReasons.phaseDetail("phase_rejected_code", SessionEnd(EndKind.REJECTED, 0x80108b33L), host))
        assertEquals(host, SessionEndReasons.phaseDetail("phase_not_found_host", SessionEnd(EndKind.NETWORK), host))
        assertFalse(EndKind.REGISTRATION_INVALID.retry)
        assertFalse(EndKind.REMOTE_PLAY_DISABLED.retry)
    }

    @Test fun registReasons() {
        fun r(app: Long, vararg lines: String, code: Int = NativeRegistResult.FAILED) =
            RegistReasons.classify(code, app, lines.toList())
        assertEquals("regist_wrong_account", r(0x80108b02L).reasonKey)
        assertEquals("regist_wrong_code", r(0x80108b09L).reasonKey)
        assertEquals("0x80108b09", r(0x80108b09L).detail)
        assertEquals("regist_in_use", r(0x80108b10L).reasonKey)
        assertEquals("regist_version", r(0x80108b11L).reasonKey)
        assertEquals("regist_crashed", r(0x80108b15L).reasonKey)
        assertEquals("regist_failed", r(0x80108b99L).reasonKey)
        assertEquals("regist_bad_address", r(0, "Regist failed to getaddrinfo on x").reasonKey)
        val noAnswer = r(0, "Regist search failed")
        assertEquals("regist_no_answer", noAnswer.reasonKey)
        assertTrue(noAnswer.retryable)
        assertEquals("Regist search failed", noAnswer.detail)
        assertEquals("regist_no_reply", r(0, "Regist failed to receive response HTTP header").reasonKey)
        assertEquals("regist_no_reply", r(0, code = NativeRegistResult.NO_REPLY).reasonKey)
        assertEquals("regist_failed", r(0).reasonKey)
        assertFalse(r(0x80108b09L).retryable)
        assertFalse(r(0, "Regist failed to getaddrinfo").retryable)
    }

    @Test fun pairingPin() {
        assertEquals(12345678, PairingPin.parse("1234 5678"))
        assertEquals(12345678, PairingPin.parse("1234-5678"))
        assertEquals(12345678, PairingPin.parse("12.34_56–78"))
        assertEquals(1234567, PairingPin.parse("01234567"))
        assertEquals(12345678, PairingPin.parse("١٢٣٤٥٦٧٨")) // Arapça-Hint rakamları
        assertNull(PairingPin.parse("1234567"))
        assertNull(PairingPin.parse("123456789"))
        assertNull(PairingPin.parse("1234a678"))
        assertNull(PairingPin.parse(""))
    }
}
