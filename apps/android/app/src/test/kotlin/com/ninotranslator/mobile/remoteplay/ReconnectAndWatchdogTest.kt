// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.remoteplay

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ReconnectAndWatchdogTest {

    @Test fun backoffSequenceAndReset() {
        val b = ReconnectBackoff()
        assertEquals(listOf(2000L, 4000L, 8000L, 16000L, 30000L, 30000L, 30000L), List(7) { b.nextDelayMs() })
        b.reset()
        assertEquals(2000L, b.nextDelayMs())
    }

    @Test fun firstFrameMustArriveWithinFiveSeconds() {
        val w = FrameWatchdog()
        w.onConnected(0)
        assertEquals(FrameWatchdog.Verdict.Ok, w.tick(4_000, 0))
        assertEquals(FrameWatchdog.Verdict.NoPicture(1), w.tick(5_000, 0))
        assertFalse(w.connected)
        // Bağlı değilken bekçi bir şey demez.
        assertEquals(FrameWatchdog.Verdict.Ok, w.tick(60_000, 0))
    }

    @Test fun stallAfterPictureAfterEightSeconds() {
        val w = FrameWatchdog()
        w.onConnected(0)
        assertEquals(FrameWatchdog.Verdict.Ok, w.tick(1_000, 30))
        assertEquals(FrameWatchdog.Verdict.Ok, w.tick(8_999, 30))
        assertEquals(FrameWatchdog.Verdict.Stalled, w.tick(9_000, 30))
    }

    @Test fun newFramesKeepSessionAlive() {
        val w = FrameWatchdog()
        w.onConnected(0)
        var frames = 0L
        for (t in 1..60) {
            frames += 30
            assertEquals(FrameWatchdog.Verdict.Ok, w.tick(t * 1_000L, frames))
        }
    }

    @Test fun threeSessionsWithoutPictureGiveUp() {
        val w = FrameWatchdog()
        w.onConnected(0); assertEquals(FrameWatchdog.Verdict.NoPicture(1), w.tick(5_000, 0))
        w.onConnected(10_000); assertEquals(FrameWatchdog.Verdict.NoPicture(2), w.tick(15_000, 0))
        w.onConnected(20_000); assertEquals(FrameWatchdog.Verdict.GiveUp(3), w.tick(25_000, 0))
    }

    @Test fun pictureResetsNoPictureStreak() {
        val w = FrameWatchdog()
        w.onConnected(0); w.tick(5_000, 0)
        assertEquals(1, w.noPictureSessions)
        w.onConnected(10_000); w.tick(11_000, 5)
        assertEquals(0, w.noPictureSessions)
        w.onConnected(20_000); w.tick(25_000, 0)
        assertEquals(1, w.noPictureSessions)
        w.resetAll()
        assertEquals(0, w.noPictureSessions)
    }

    @Test fun decoderChoiceFlipsOnOddStreak() {
        assertTrue(DecoderChoice.startWithSoftware("samsung", 0))
        assertFalse(DecoderChoice.startWithSoftware("samsung", 1))
        assertTrue(DecoderChoice.startWithSoftware("Samsung", 2))
        assertFalse(DecoderChoice.startWithSoftware("Google", 0))
        assertTrue(DecoderChoice.startWithSoftware("Google", 1))
        assertFalse(DecoderChoice.startWithSoftware(null, 2))
    }
}
