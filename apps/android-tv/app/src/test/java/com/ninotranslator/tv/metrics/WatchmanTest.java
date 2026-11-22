// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.tv.metrics;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

import com.ninotranslator.tv.link.Json;

import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

import org.junit.Test;

/** Otomatik teşhis bekçisi: ortak senaryolar (diag-scenarios.json) ve TV'ye özgü kurallar. */
public class WatchmanTest {
    /** TV'de çalışan kurallar; senaryolardaki öbür kurallar (PS5, okuma, çeviri) TV'de hiç tetiklenmemeli. */
    private static final Set<String> TV_RULES = new HashSet<>(Arrays.asList("tv.flapping", "app.hang", "app.resources"));

    @SuppressWarnings("unchecked")
    private static List<Object> scenarios() throws Exception {
        try (InputStream in = WatchmanTest.class.getClassLoader().getResourceAsStream("diag-scenarios.json")) {
            String text = new String(in.readAllBytes(), StandardCharsets.UTF_8);
            return (List<Object>) ((Map<String, Object>) Json.parse(text)).get("scenarios");
        }
    }

    @Test
    @SuppressWarnings("unchecked")
    public void sharedScenarios() throws Exception {
        int checked = 0;
        for (Object o : scenarios()) {
            Map<String, Object> s = (Map<String, Object>) o;
            List<Map<String, Object>> got = new ArrayList<>();
            Watchman w = new Watchman(-10_000, got::add);
            List<Object> causes = s.get("dropCodes") instanceof List ? (List<Object>) s.get("dropCodes") : new ArrayList<>();
            int drop = 0;
            for (Object row : (List<Object>) s.get("timeline")) {
                List<Object> r = (List<Object>) row;
                long t = ((Number) r.get(0)).longValue();
                String code = (String) r.get(1);
                Number value = r.size() > 2 ? (Number) r.get(2) : null;
                if (code.equals("tv.drop")) w.tvDropped(t, drop < causes.size() ? (String) causes.get(drop++) : "unknown");
                else if (code.equals("tv.connect")) w.tvConnected(t);
                else w.step(t, code, value);
            }
            List<String> want = new ArrayList<>();
            for (Object e : (List<Object>) s.get("expect")) {
                Map<String, Object> x = (Map<String, Object>) e;
                if (TV_RULES.contains(x.get("rule"))) want.add(x.get("at") + " " + x.get("rule") + " " + x.get("cause") + " " + x.get("sev"));
            }
            List<String> have = new ArrayList<>();
            for (Map<String, Object> e : got) have.add(e.get("t") + " " + e.get("rule") + " " + e.get("cause") + " " + e.get("sev"));
            assertEquals((String) s.get("name"), want, have);
            checked++;
        }
        assertTrue(checked >= 9);
    }

    @Test
    @SuppressWarnings("unchecked")
    public void reportHasTheSharedShape() {
        List<Map<String, Object>> got = new ArrayList<>();
        Watchman w = new Watchman(0, got::add);
        w.setTv("TCL 98U95A", "4.5.0");
        w.setState("net", "wifi");
        w.tvConnected(100);
        w.tvDropped(200, "timeout");
        w.tvDropped(300, "timeout");
        w.tvDropped(400, "write_error");
        Map<String, Object> d = got.get(0);
        assertEquals("diag", d.get("k"));
        assertEquals("timeout", d.get("cause"));
        assertEquals(400L, d.get("t"));
        Map<String, Object> state = (Map<String, Object>) d.get("state");
        assertEquals("wifi", state.get("net"));
        assertEquals(3L, state.get("drops"));
        List<Object> trail = (List<Object>) d.get("trail");
        assertEquals(Arrays.asList(-300L, "tv.connect"), trail.get(0));
        assertEquals(Arrays.asList(0L, "tv.drop"), trail.get(trail.size() - 1));
        assertEquals("TCL 98U95A", ((Map<String, Object>) d.get("tv")).get("model"));
    }

    @Test
    public void tvFlappingIgnoresBackgroundButNotSleepOrStop() {
        List<Map<String, Object>> got = new ArrayList<>();
        Watchman w = new Watchman(0, got::add);
        w.tvDropped(10, "closed");
        w.tvDropped(20, "closed");
        w.tvDropped(30, "closed");
        assertEquals("ilk 60 sn susturulur", 0, got.size());
        w.step(1000, "sys.sleep", null);
        w.tvDropped(1010, "closed");
        w.tvDropped(1020, "closed");
        w.tvDropped(1030, "closed");
        assertEquals("uyku sonrası 2 dk susturulur", 0, got.size());
        // Arka plana gidip gelme susturmaz: öne gelişin hemen ardındaki kopmalar "resume".
        w.step(2000, "app.background", null);
        w.step(2005, "app.foreground", null);
        w.tvDropped(2008, "closed");
        w.step(2100, "app.background", null);
        w.step(2101, "app.foreground", null);
        w.tvDropped(2103, "closed");
        w.tvDropped(2200, "closed");
        assertEquals(1, got.size());
        assertEquals("resume", got.get(0).get("cause"));
    }

    @Test
    public void replacedSendersCountAsDrops() {
        List<Map<String, Object>> got = new ArrayList<>();
        Watchman w = new Watchman(-1000, got::add);
        w.tvDropped(100, "replaced");
        w.tvDropped(200, "replaced");
        w.tvDropped(300, "closed");
        assertEquals("replaced", got.get(0).get("cause"));
        // Arka plan öbür kuralları yine susturur.
        List<Map<String, Object>> mem = new ArrayList<>();
        Watchman m = new Watchman(-1000, mem::add);
        m.step(100, "app.background", null);
        m.memory(110, 10, true);
        assertEquals(0, mem.size());
    }

    @Test
    public void mixedCausesAndOncePerRun() {
        List<Map<String, Object>> got = new ArrayList<>();
        Watchman w = new Watchman(-1000, got::add);
        w.tvDropped(100, "closed");
        w.tvDropped(110, "timeout");
        w.tvDropped(120, "write_error");
        w.tvDropped(500, "closed");
        w.tvDropped(510, "closed");
        w.tvDropped(520, "closed");
        assertEquals(1, got.size());
        assertEquals("mixed", got.get(0).get("cause"));
    }

    @Test
    public void hangMemoryPriorityAndRemoteSwitch() {
        List<Map<String, Object>> got = new ArrayList<>();
        Watchman w = new Watchman(0, got::add);
        w.memory(100, 450, false);
        w.memory(219, 460, false);
        assertEquals("2 dk dolmadı", 0, got.size());
        w.memory(220, 470, false);
        assertEquals("app.resources", got.get(0).get("rule"));
        // 5 dk içinde daha önemli kural (app.hang) yine gider; daha önemsizi gitmez.
        w.mainThreadBlocked(300, 6, 300L);
        assertEquals("app.hang", got.get(1).get("rule"));
        assertEquals("main_thread", got.get(1).get("cause"));

        List<Map<String, Object>> off = new ArrayList<>();
        Watchman quiet = new Watchman(0, off::add);
        Map<String, Object> diag = new LinkedHashMap<>();
        diag.put("off", Arrays.asList((Object) "app.hang"));
        Map<String, Object> limits = new LinkedHashMap<>();
        limits.put("memHighMB", 600L);
        diag.put("limits", limits);
        quiet.applyConfig(diag);
        quiet.mainThreadBlocked(300, 9, null);
        quiet.memory(100, 500, false);
        quiet.memory(400, 500, false);
        assertEquals(0, off.size());
        quiet.memory(500, 10, true); // sistemin bellek uyarısı hemen sayılır
        assertEquals("memory_high", off.get(0).get("cause"));
    }

    @Test
    public void knownCausesWinOverResume() {
        List<Map<String, Object>> got = new ArrayList<>();
        Watchman w = new Watchman(-1000, got::add);
        w.step(100, "app.foreground", null);
        w.tvDropped(102, "write_error");
        w.step(200, "app.foreground", null);
        w.tvDropped(203, "write_error");
        w.step(300, "app.foreground", null);
        w.tvDropped(305, "closed");
        assertEquals("write_error", got.get(0).get("cause"));
    }
}
