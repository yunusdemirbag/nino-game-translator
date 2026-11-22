// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.tv.metrics;

import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Iterator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * Otomatik teşhis bekçisi (tarif: NinoCore otomatik-teshis.md). TV uygulamasında çalışabilen kurallar:
 * - `tv.flapping`: 10 dk içinde 3 kopma (tetik 3. kopmada); sebep kopmaların çoğunun nedeni, karışıksa `mixed`.
 * - `app.hang`: ana iş parçacığı 5 sn yanıt vermedi.
 * - `app.resources`: bellek 400 MB üstünde 2 dk ya da sistemin bellek uyarısı.
 * PS5, okuma ve çeviri kuralları TV'de yoktur (o işler göndericidedir).
 *
 * Saatten ve Android'den bağımsızdır: zaman saniye olarak verilir, bildirimler {@link Sink}'e gider. Testler:
 * WatchmanTest (diag-scenarios.json senaryoları dahil).
 */
public final class Watchman {
    /** Bildirimin gideceği yer (ölçüm kuyruğu). */
    public interface Sink {
        void report(Map<String, Object> diag);
    }

    static final int TRAIL_MAX = 200;
    static final int TRAIL_SEND = 40;
    static final long TRAIL_WINDOW_SEC = 600;
    static final long QUIET_SEC = 120;
    static final long STARTUP_QUIET_SEC = 60;
    static final long ONE_ROOT_SEC = 300;
    static final int DAY_LIMIT = 5;
    static final int RULE_DAY_LIMIT = 2;

    /** Öncelik sırası (tarif): ilk en önemli. */
    static final List<String> PRIORITY = Collections.unmodifiableList(java.util.Arrays.asList(
            "app.hang", "ps5.no_return", "tv.flapping", "ocr.stalled", "tr.errors", "tr.slow", "ocr.silent",
            "app.resources", "pack.download"));

    private final Sink sink;
    private final ArrayDeque<Object[]> trail = new ArrayDeque<>();
    private final ArrayDeque<long[]> drops = new ArrayDeque<>();
    private final List<String> dropCauses = new ArrayList<>();
    private final Set<String> firedThisRun = new HashSet<>();
    private final Map<String, Integer> firedToday = new HashMap<>();
    private final Set<String> off = new HashSet<>();
    private final Map<String, Double> limits = new HashMap<>();
    private final long startedAt;
    private long lastQuietEvent = Long.MIN_VALUE / 2;
    /** Uyku/uyanma ya da kullanıcının durdurması (arka plan hariç): tv.flapping yalnız bunlarla susar. */
    private long lastHardQuiet = Long.MIN_VALUE / 2;
    /** Uygulamanın en son öne geldiği an: hemen ardından gelen kopma `resume` sayılır. */
    private long lastForeground = Long.MIN_VALUE / 2;
    private long day = -1;
    private int today;
    private String lastRule;
    private long lastAt = Long.MIN_VALUE / 2;
    private long memHighSince = -1;
    private Map<String, Object> fixedState = new LinkedHashMap<>();
    private Map<String, Object> tvInfo;

    public Watchman(long nowSec, Sink sink) {
        this.startedAt = nowSec;
        this.sink = sink;
    }

    /** TV'nin kendisi (bildirimdeki `tv` alanı): marka, model, uygulama sürümü. */
    public void setTv(String model, String app) {
        Map<String, Object> tv = new LinkedHashMap<>();
        tv.put("brand", "androidtv");
        if (model != null && !model.isEmpty()) tv.put("model", model.length() > 60 ? model.substring(0, 60) : model);
        if (app != null && !app.isEmpty()) tv.put("app", app);
        tvInfo = tv;
    }

    /** Her bildirime eklenecek sabit durum (ör. net). */
    public void setState(String key, Object value) {
        if (value == null) fixedState.remove(key); else fixedState.put(key, value);
    }

    // --- Uzaktan ayar: telemetry.diag ---

    @SuppressWarnings("unchecked")
    public void applyConfig(Map<String, Object> diag) {
        if (diag == null) return;
        off.clear();
        limits.clear();
        if (diag.get("off") instanceof List) {
            for (Object rule : (List<Object>) diag.get("off")) if (rule instanceof String) off.add((String) rule);
        }
        if (diag.get("limits") instanceof Map) {
            for (Map.Entry<String, Object> e : ((Map<String, Object>) diag.get("limits")).entrySet()) {
                if (e.getValue() instanceof Number) limits.put(e.getKey(), ((Number) e.getValue()).doubleValue());
            }
        }
    }

    private double limit(String key, double fallback) {
        Double v = limits.get(key);
        return v == null ? fallback : v;
    }

    // --- İz ---

    /** İz adımı ekler (kod ölçümdeki hata kodu kuralına uyar). value: sayı ya da null. */
    public void step(long now, String code, Number value) {
        String c = Outbox.Codes.code(code);
        trail.addLast(new Object[] {now, c, value});
        while (trail.size() > TRAIL_MAX || (!trail.isEmpty() && now - (Long) trail.peekFirst()[0] > TRAIL_WINDOW_SEC)) {
            trail.removeFirst();
        }
        switch (c) {
            case "app.foreground":
                lastForeground = now;
                lastQuietEvent = now;
                break;
            case "app.background":
                lastQuietEvent = now;
                break;
            case "sys.sleep":
            case "sys.wake":
            case "session.stop":
                lastQuietEvent = now;
                lastHardQuiet = now;
                break;
            default:
                break;
        }
    }

    private boolean quiet(long now) {
        return now - startedAt < STARTUP_QUIET_SEC || now - lastQuietEvent < QUIET_SEC;
    }

    /**
     * tv.flapping'in susturması: arka plana gidip gelme sayılmaz (TV uygulamasında kopmanın kendisi olabilir); yalnız
     * açılışın ilk 60 sn'si, uyku/uyanma ve kullanıcının durdurması.
     */
    private boolean quietForTv(long now) {
        return now - startedAt < STARTUP_QUIET_SEC || now - lastHardQuiet < QUIET_SEC;
    }

    /** Öne gelişten bu kadar saniye içindeki kopma `resume` sayılır (ör. HDMI girişi değişti, uygulama döndü). */
    static final long RESUME_SEC = 10;

    // --- Kurallar ---

    /** Gönderici bağlandı. */
    public void tvConnected(long now) { step(now, "tv.connect", null); }

    /**
     * Bağlı gönderici koptu. cause: write_error · timeout · closed · resume · replaced · network_change. Öne gelişten
     * hemen sonraki kopma `resume` sayılır. Susturma anındaki kopmalar sayılmaz (sayaç sıfırlanır).
     */
    public void tvDropped(long now, String cause) {
        step(now, "tv.drop", null);
        // Bağlantı katmanı sebebi kendisi biliyorsa (write_error, timeout, replaced…) o geçerli; yalnız belirsiz
        // kopmalar (closed ya da bilinmeyen) öne gelişten sonraki 10 sn içindeyse `resume` sayılır.
        boolean vague = cause == null || "closed".equals(cause) || "unknown".equals(cause);
        if (vague && now - lastForeground <= RESUME_SEC) cause = "resume";
        if (quietForTv(now)) {
            drops.clear();
            dropCauses.clear();
            return;
        }
        long window = (long) (limit("tvFlapWindowMin", 10) * 60);
        int count = (int) limit("tvFlapCount", 3);
        drops.addLast(new long[] {now});
        dropCauses.add(cause == null ? "unknown" : cause);
        while (!drops.isEmpty() && now - drops.peekFirst()[0] > window) {
            drops.removeFirst();
            dropCauses.remove(0);
        }
        if (drops.size() < count) return;
        Map<String, Object> state = new LinkedHashMap<>();
        state.put("drops", (long) drops.size());
        state.put("tvCount", 1L);
        fire(now, "tv.flapping", majority(dropCauses), "warn", state);
        drops.clear();
        dropCauses.clear();
    }

    private static String majority(List<String> causes) {
        Map<String, Integer> n = new HashMap<>();
        String best = "unknown";
        int top = 0;
        boolean tie = false;
        for (String c : causes) {
            int k = n.merge(c, 1, Integer::sum);
            if (k > top) { top = k; best = c; tie = false; }
            else if (k == top && !c.equals(best)) tie = true;
        }
        if (top * 2 <= causes.size() || tie) return causes.isEmpty() ? "unknown" : "mixed";
        return best;
    }

    /** Ana iş parçacığı bu kadar saniyedir yanıt vermiyor (izleyiciden). */
    public void mainThreadBlocked(long now, long blockedSec, Long memMB) {
        if (blockedSec < limit("hangSec", 5)) return;
        Map<String, Object> state = new LinkedHashMap<>();
        state.put("blockedSec", blockedSec);
        if (memMB != null) state.put("memMB", memMB);
        // Donma kendisi bir sorun: başlangıç susturması dışında susturulmaz (arka plan donmayı açıklamaz).
        fireIfNotStarting(now, "app.hang", "main_thread", "error", state);
    }

    /** Bellek ölçümü (MB). systemWarning: işletim sisteminin bellek uyarısı geldi. */
    public void memory(long now, long memMB, boolean systemWarning) {
        double high = limit("memHighMB", 400);
        if (systemWarning) step(now, "mem.high", memMB);
        if (memMB <= high && !systemWarning) {
            memHighSince = -1;
            return;
        }
        if (memHighSince < 0) memHighSince = now;
        if (!systemWarning && now - memHighSince < 120) return;
        if (quiet(now)) return;
        Map<String, Object> state = new LinkedHashMap<>();
        state.put("memMB", memMB);
        fire(now, "app.resources", "memory_high", "warn", state);
        memHighSince = -1;
    }

    private void fireIfNotStarting(long now, String rule, String cause, String sev, Map<String, Object> state) {
        if (now - startedAt < STARTUP_QUIET_SEC) return;
        fire(now, rule, cause, sev, state);
    }

    // --- Gönderim: sınırlar, tek kök ---

    private void fire(long now, String rule, String cause, String sev, Map<String, Object> state) {
        if (off.contains(rule) || firedThisRun.contains(rule)) return;
        long thisDay = Math.floorDiv(now, 86_400L);
        if (thisDay != day) {
            day = thisDay;
            today = 0;
            firedToday.clear();
        }
        if (today >= DAY_LIMIT || firedToday.getOrDefault(rule, 0) >= RULE_DAY_LIMIT) return;
        // Aynı 5 dakikada daha önemli bir kural gittiyse bu yalnız iz adımı olur.
        if (lastRule != null && now - lastAt < ONE_ROOT_SEC && PRIORITY.indexOf(lastRule) <= PRIORITY.indexOf(rule)) {
            step(now, rule, null);
            return;
        }
        firedThisRun.add(rule);
        firedToday.merge(rule, 1, Integer::sum);
        today++;
        lastRule = rule;
        lastAt = now;

        Map<String, Object> e = Outbox.event("diag");
        e.put("rule", rule);
        e.put("cause", Outbox.Codes.code(cause));
        e.put("sev", sev);
        e.put("t", now);
        Map<String, Object> st = new LinkedHashMap<>(fixedState);
        st.putAll(state);
        e.put("state", st);
        e.put("trail", trailFor(now));
        if (tvInfo != null) e.put("tv", tvInfo);
        sink.report(e);
    }

    /** Son 40 adım, eskiden yeniye: [saniye (≤ 0), kod, sayı?]. */
    private List<Object> trailFor(long now) {
        List<Object> out = new ArrayList<>();
        List<Object[]> all = new ArrayList<>(trail);
        int from = Math.max(0, all.size() - TRAIL_SEND);
        for (int i = from; i < all.size(); i++) {
            Object[] s = all.get(i);
            long ago = Math.max(-3600, (Long) s[0] - now);
            List<Object> row = new ArrayList<>();
            row.add(ago);
            row.add(s[1]);
            if (s[2] != null) row.add(((Number) s[2]).longValue());
            out.add(row);
        }
        return out;
    }

    /** Testler için: bellekteki iz adımı sayısı. */
    int trailSize() {
        int n = 0;
        for (Iterator<Object[]> it = trail.iterator(); it.hasNext(); it.next()) n++;
        return n;
    }
}
