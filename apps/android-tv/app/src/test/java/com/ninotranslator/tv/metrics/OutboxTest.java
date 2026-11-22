// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.tv.metrics;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotEquals;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import com.ninotranslator.tv.link.Json;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import org.junit.Test;

/** Ölçüm kuyruğu: gövde biçimi (events-v1.json ile aynı yapı), cevap kuralları, sınırlar, disk. */
public class OutboxTest {
    private static final long NOW = 1_763_300_000_000L;
    private static final String INSTALL = "8d0f5c9e-3b1a-4c2d-9e8f-7a6b5c4d3e2f";

    private static Map<String, Object> ctx() {
        Map<String, Object> c = new LinkedHashMap<>();
        c.put("platform", "androidtv");
        c.put("app", "4.1.0");
        c.put("os", "Android 14");
        c.put("device", "TCL 98U95A");
        c.put("tv", "");
        c.put("channel", "release");
        return c;
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> parse(String json) { return (Map<String, Object>) Json.parse(json); }

    @Test
    @SuppressWarnings("unchecked")
    public void bodyHasTheSharedShape() {
        Outbox box = new Outbox();
        Map<String, Object> launch = Outbox.event("launch");
        box.add(launch, NOW);
        Map<String, Object> crash = Outbox.event("crash");
        crash.put("code", "java.lang.IllegalStateException");
        crash.put("where", Outbox.Codes.where("com.ninotranslator.tv.GameScreen.tune"));
        crash.put("ver", "4.1.0");
        box.add(crash, NOW);
        Map<String, Object> connect = Outbox.event("tv_connect");
        connect.put("r", "ok");
        connect.put("ms", 420L);
        connect.put("brand", "androidtv");
        connect.put("proto", "nino");
        box.add(connect, NOW + 5000);

        Map<String, Object> body = parse(box.nextBody(INSTALL, ctx()));
        assertEquals(1L, body.get("v"));
        assertEquals(36, ((String) body.get("batch")).length());
        assertEquals(INSTALL, body.get("install"));
        assertEquals("androidtv", ((Map<String, Object>) body.get("ctx")).get("platform"));
        List<Object> events = (List<Object>) body.get("events");
        assertEquals(3, events.size());
        Map<String, Object> first = (Map<String, Object>) events.get(0);
        assertEquals("launch", first.get("k"));
        assertEquals(NOW / 1000, first.get("t"));
        assertEquals("ok", ((Map<String, Object>) events.get(2)).get("r"));
    }

    @Test
    public void retriesKeepTheBatchIdAndSuccessEmptiesIt() {
        Outbox box = new Outbox();
        box.add(Outbox.event("launch"), NOW);
        String first = (String) parse(box.nextBody(INSTALL, ctx())).get("batch");
        box.answered(503, "", 0, NOW);
        assertFalse("bekleme sürüyor", box.ready(NOW + 59_000));
        assertTrue(box.ready(NOW + 60_000));
        assertEquals(first, parse(box.nextBody(INSTALL, ctx())).get("batch"));
        // Bekleme sırasında gelen olay o parçaya girmez.
        box.add(Outbox.event("launch"), NOW + 1);
        assertEquals(1, ((List<?>) parse(box.nextBody(INSTALL, ctx())).get("events")).size());
        box.answered(200, "{\"ok\":true,\"accepted\":1,\"dropped\":0}", 0, NOW);
        assertEquals(1, box.size());
        assertNotEquals(first, parse(box.nextBody(INSTALL, ctx())).get("batch"));
    }

    @Test
    public void backoffDoublesUpToAnHour() {
        Outbox box = new Outbox();
        box.add(Outbox.event("launch"), NOW);
        long[] waits = {60_000, 120_000, 240_000, 480_000, 960_000, 1_920_000, 3_600_000, 3_600_000};
        for (long wait : waits) {
            box.answered(0, null, 0, NOW);
            assertEquals(NOW + wait, box.waitUntil());
        }
    }

    @Test
    public void badAndTooLargeAndRateLimited() {
        Outbox box = new Outbox();
        for (int i = 0; i < 4; i++) box.add(Outbox.event("launch"), NOW + i);
        box.nextBody(INSTALL, ctx());
        box.answered(413, "", 0, NOW);
        assertEquals(2, ((List<?>) parse(box.nextBody(INSTALL, ctx())).get("events")).size());
        box.answered(400, "", 0, NOW);
        assertEquals(2, box.size());
        box.nextBody(INSTALL, ctx());
        box.answered(429, "", 120, NOW);
        assertEquals(NOW + 120_000, box.waitUntil());
        assertEquals(2, box.size());
    }

    @Test
    public void sameErrorInARowIsCounted() {
        Outbox box = new Outbox();
        box.add(Outbox.error("tv.hdmi.dark"), NOW);
        box.add(Outbox.error("tv.hdmi.dark"), NOW + 1);
        box.add(Outbox.error("tv.hdmi.dark"), NOW + 2);
        box.add(Outbox.error("tv.overlay.denied"), NOW + 3);
        assertEquals(2, box.size());
        @SuppressWarnings("unchecked")
        Map<String, Object> first = (Map<String, Object>) ((List<?>) parse(box.nextBody(INSTALL, ctx())).get("events")).get(0);
        assertEquals(3L, first.get("n"));
    }

    @Test
    public void codesNeverCarryTextOrPaths() {
        assertEquals("tv.hdmi.dark", Outbox.Codes.code("tv.hdmi.dark"));
        assertEquals("Ccomebadpath", Outbox.Codes.code("C:\\come bad/path"));
        assertEquals("other", Outbox.Codes.code("  //  "));
        assertNull(Outbox.Codes.where("/"));
        assertEquals("GameScreen.tune", Outbox.Codes.where("GameScreen.tune"));
    }

    @Test
    public void dailyLimitStillLetsCrashesThrough() {
        Outbox box = new Outbox();
        box.applyConfig("{\"config\":{\"telemetry\":{\"enabled\":true,\"maxPerDay\":2,\"flushSeconds\":300}}}");
        assertEquals(300, box.config().flushSeconds);
        box.add(Outbox.event("launch"), NOW);
        box.add(Outbox.event("launch"), NOW);
        box.add(Outbox.event("launch"), NOW);
        box.add(Outbox.event("crash"), NOW);
        assertEquals(3, box.size());
        box.add(Outbox.event("launch"), NOW + Outbox.DAY_MS);
        assertEquals("yeni gün", 4, box.size());
    }

    @Test
    public void serverCanSwitchItOff() {
        Outbox box = new Outbox();
        box.add(Outbox.event("launch"), NOW);
        box.applyConfig("{\"telemetry\":{\"enabled\":false}}");
        assertEquals(0, box.size());
        box.add(Outbox.event("launch"), NOW);
        assertEquals(0, box.size());
        assertFalse(box.ready(NOW));
    }

    @Test
    public void queueIsCappedAndKeepsCrashes() {
        Outbox box = new Outbox();
        box.applyConfig("{\"telemetry\":{\"maxPerDay\":100000}}");
        box.add(Outbox.event("crash"), NOW);
        for (int i = 0; i < Outbox.MAX_QUEUE + 10; i++) box.add(Outbox.event("launch"), NOW);
        assertEquals(Outbox.MAX_QUEUE, box.size());
        @SuppressWarnings("unchecked")
        Map<String, Object> first = (Map<String, Object>) ((List<?>) parse(box.nextBody(INSTALL, ctx())).get("events")).get(0);
        assertEquals("crash", first.get("k"));
        assertEquals(Outbox.MAX_BATCH, ((List<?>) parse(box.nextBody(INSTALL, ctx())).get("events")).size());
    }

    @Test
    public void surviveARestart() {
        Outbox box = new Outbox();
        box.add(Outbox.event("launch"), NOW);
        box.add(Outbox.error("tv.page.lost"), NOW);
        String batch = (String) parse(box.nextBody(INSTALL, ctx())).get("batch");
        Outbox again = new Outbox();
        again.load(box.save());
        assertEquals(2, again.size());
        assertEquals("yarım kalan parça aynı kimlikle", batch, parse(again.nextBody(INSTALL, ctx())).get("batch"));
        Outbox broken = new Outbox();
        broken.load("{bozuk");
        assertEquals(0, broken.size());
    }

    @Test
    public void pageEventsAreFilteredToKnownFields() {
        Map<String, Object> ok = Outbox.fromPage("{\"k\":\"tv_connect\",\"r\":\"ok\",\"ms\":420,\"proto\":\"legacy\",\"text\":\"gizli\"}");
        assertEquals("{\"k\":\"tv_connect\",\"r\":\"ok\",\"ms\":420,\"brand\":\"androidtv\",\"proto\":\"legacy\"}", Json.write(ok));
        Map<String, Object> drop = Outbox.fromPage("{\"k\":\"tv_drop\",\"code\":\"network lost/x\",\"after\":12}");
        assertEquals("networklostx", drop.get("code"));
        assertEquals("legacy", drop.get("proto"));
        assertNull(Outbox.fromPage("{\"k\":\"crash\",\"code\":\"x\"}"));
        assertNull(Outbox.fromPage("{\"k\":\"tv_connect\",\"r\":\"ok\"}"));
        assertNull(Outbox.fromPage("bozuk"));
    }
}
