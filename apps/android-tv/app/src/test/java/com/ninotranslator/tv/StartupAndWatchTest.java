// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.tv;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

public class StartupAndWatchTest {
    @Test
    public void playBuildAlwaysShowsTheGameInside() {
        assertEquals(Startup.Plan.IN_APP, Startup.decide(false, true, false, false, true));
        assertEquals(Startup.Plan.IN_APP, Startup.decide(false, false, false, false, false));
    }

    @Test
    public void overlayBuildNeverTouchesTheInput() {
        assertEquals(Startup.Plan.HOME, Startup.decide(true, true, false, false, true));
        assertEquals(Startup.Plan.QUIET, Startup.decide(true, true, false, false, false));
        // İzin sonradan verildiyse eski "izinsiz" seçimi önemsizdir.
        assertEquals(Startup.Plan.HOME, Startup.decide(true, true, true, false, true));
        assertEquals(Startup.Plan.ASK_PERMISSION, Startup.decide(true, false, false, false, true));
        assertEquals(Startup.Plan.IN_APP, Startup.decide(true, false, true, false, true));
    }

    @Test
    public void senderCanAskForTheGameInsideNino() {
        assertEquals(Startup.Plan.IN_APP, Startup.decide(true, true, false, true, true));
        assertEquals(Startup.Plan.IN_APP, Startup.decide(true, true, false, true, false));
        // İzin yoksa izin ekranı yine sorulur (seçim izin vermez).
        assertEquals(Startup.Plan.ASK_PERMISSION, Startup.decide(true, false, false, true, true));
    }

    @Test
    public void displayModeOnlyCountsRealChanges() {
        assertEquals(DisplayChoice.IN_APP, DisplayChoice.normalize("in-app"));
        assertEquals(DisplayChoice.OVERLAY, DisplayChoice.normalize(" Overlay "));
        assertEquals(null, DisplayChoice.normalize("tv"));
        assertTrue(DisplayChoice.differs(null, "overlay"));
        // Göndericinin varsayılanı ilk bağlantıda katmanı kapatmamalı.
        assertFalse(DisplayChoice.differs(null, "inApp"));
        assertFalse(DisplayChoice.differs(null, "in_app"));
        assertFalse(DisplayChoice.differs("overlay", "OVERLAY"));
        assertTrue(DisplayChoice.differs("overlay", "inApp"));
        assertFalse(DisplayChoice.differs("overlay", "bilinmeyen"));
    }

    @Test
    public void darkInputMovesToOverlayAfterTenSeconds() {
        PictureWatch watch = new PictureWatch();
        watch.opened(1_000);
        watch.dark(4_000); // yeniden deneme saati sıfırlamaz
        assertFalse(watch.moveToOverlay(10_999, true, true));
        assertTrue(watch.moveToOverlay(11_000, true, true));
        assertFalse("izin yok", watch.moveToOverlay(11_000, true, false));
        assertFalse("girişte cihaz yok", watch.moveToOverlay(11_000, false, true));
        assertTrue(watch.tooLongDark(11_000));
    }

    @Test
    public void picturesThatCameOnceNeverMoveToOverlay() {
        PictureWatch watch = new PictureWatch();
        watch.opened(0);
        watch.seen();
        watch.dark(1_000);
        assertFalse(watch.moveToOverlay(60_000, true, true));
        assertTrue(watch.everSeen());
    }

    @Test
    public void backgroundTimeDoesNotCount() {
        PictureWatch watch = new PictureWatch();
        watch.opened(0);
        watch.restart();
        assertFalse(watch.tooLongDark(30_000));
        watch.dark(30_000);
        assertFalse(watch.tooLongDark(39_999));
        assertTrue(watch.tooLongDark(40_000));
    }

    @Test
    public void beingPushedAwaySoonAfterOpeningMeansTheTvTookOver() {
        PictureWatch watch = new PictureWatch();
        assertFalse("hiç açılmadı", watch.pushedAway(100, true));
        watch.opened(1_000);
        assertTrue(watch.pushedAway(5_999, true));
        assertFalse(watch.pushedAway(6_000, true));
        assertFalse(watch.pushedAway(2_000, false));
    }
}
