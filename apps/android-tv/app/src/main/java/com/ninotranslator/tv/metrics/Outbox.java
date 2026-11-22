// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.tv.metrics;

import com.ninotranslator.tv.link.Json;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

/**
 * Ölçüm kuyruğu ve gönderim kuralları (tarif: NinoCore docs/tarif/olcum.md). Ağdan, diskten ve saatten bağımsızdır:
 * diske yazılacak durumu {@link #save()} verir, gönderilecek gövdeyi {@link #nextBody} kurar, sunucunun cevabını
 * {@link #answered} işler. Testler: OutboxTest.
 *
 * Gizlilik: buraya yalnız kodlar ve sayılar girer (metin, ad, adres yok); bunu olayları kuran taraf sağlar.
 */
public final class Outbox {
    public static final int MAX_QUEUE = 2000;
    public static final int MAX_BATCH = 300;
    public static final int FLUSH_AT = 100;
    static final long DAY_MS = 24L * 3600 * 1000;
    static final long MAX_BACKOFF_MS = 3600_000;

    /** Sunucunun uzaktan ayarı (`telemetry`). */
    public static final class Config {
        public boolean enabled = true;
        public double sample = 1;
        public int maxPerDay = 1000;
        public int flushSeconds = 600;
        /** `telemetry.diag`: kapatılan kurallar ve eşikler (bekçi okur). */
        public Map<String, Object> diag;
    }

    private final List<Map<String, Object>> queue = new ArrayList<>();
    private final Config config = new Config();
    /** Gönderilmeyi bekleyen parça: kimliği yeniden denemede aynı kalır. */
    private String batchId;
    private int batchSize;
    private long day = -1;
    private int today;
    private long waitUntil;
    private int failures;

    public Config config() { return config; }

    public int size() { return queue.size(); }

    // --- Olay ekleme ---

    /**
     * Olay ekler. `crash` dışındakiler günlük sınıra tabidir. Aynı hata kodu art arda gelirse `n` artar.
     *
     * @param now duvar saati (ms); günlük sayaç ve `t` için
     */
    public void add(Map<String, Object> event, long now) {
        if (!config.enabled) return;
        // Çökme ve otomatik teşhis günlük sınırdan muaftır (teşhisin kendi sınırları vardır).
        boolean crash = "crash".equals(event.get("k")) || "diag".equals(event.get("k"));
        long thisDay = now / DAY_MS;
        if (thisDay != day) {
            day = thisDay;
            today = 0;
        }
        if (!crash && today >= config.maxPerDay) return;
        if (!event.containsKey("t")) event.put("t", now / 1000);
        if (merge(event)) return;
        today++;
        queue.add(event);
        while (queue.size() > MAX_QUEUE) dropOldest();
    }

    private boolean merge(Map<String, Object> event) {
        if (!"error".equals(event.get("k")) || queue.isEmpty()) return false;
        int last = queue.size() - 1;
        if (batchId != null && last < batchSize) return false; // gönderilmekte olan parçaya dokunulmaz
        Map<String, Object> prev = queue.get(last);
        if (!"error".equals(prev.get("k")) || !same(prev.get("code"), event.get("code"))
                || !same(prev.get("http"), event.get("http"))) {
            return false;
        }
        Object n = prev.get("n");
        prev.put("n", (n instanceof Number ? ((Number) n).longValue() : 1) + 1);
        return true;
    }

    private static boolean same(Object a, Object b) { return a == null ? b == null : a.equals(b); }

    private void dropOldest() {
        int from = batchId != null ? batchSize : 0; // gönderilmekte olan parça korunur
        for (int i = from; i < queue.size(); i++) {
            if (!"crash".equals(queue.get(i).get("k"))) {
                queue.remove(i);
                return;
            }
        }
        queue.remove(from < queue.size() ? from : 0);
    }

    // --- Gönderim ---

    /** Şimdi gönderilmeli mi: kuyrukta olay var, ölçüm açık ve bekleme süresi dolmuş. */
    public boolean ready(long now) { return config.enabled && !queue.isEmpty() && now >= waitUntil; }

    /** Kuyruk erken gönderim için yeterince doldu mu. */
    public boolean full() { return queue.size() >= FLUSH_AT; }

    /** Gönderilecek gövde (JSON). Kuyruk boşsa null. */
    public String nextBody(String install, Map<String, Object> ctx) {
        if (queue.isEmpty()) return null;
        if (batchId == null) {
            batchId = UUID.randomUUID().toString();
            batchSize = Math.min(MAX_BATCH, queue.size());
        }
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("v", 1L);
        body.put("batch", batchId);
        body.put("install", install);
        body.put("ctx", ctx);
        body.put("events", new ArrayList<Object>(queue.subList(0, batchSize)));
        return Json.write(body);
    }

    /**
     * Sunucunun cevabı. status 0: ağ hatası. retryAfterSec: 429'daki `retry-after` (yoksa 0).
     * Cevap gövdesindeki `config.telemetry` (ya da üst düzey `telemetry`) uygulanır.
     */
    public void answered(int status, String body, long retryAfterSec, long now) {
        if (status == 200) {
            removeBatch();
            failures = 0;
            waitUntil = 0;
            applyConfig(body);
        } else if (status == 400) {
            removeBatch();
        } else if (status == 413) {
            if (batchSize <= 1) removeBatch();
            else {
                batchSize = batchSize / 2;
                batchId = UUID.randomUUID().toString(); // içerik değişti: yeni parça
            }
        } else if (status == 429) {
            waitUntil = now + Math.max(60, retryAfterSec) * 1000;
        } else {
            failures++;
            long wait = 60_000L << Math.min(6, failures - 1);
            waitUntil = now + Math.min(MAX_BACKOFF_MS, wait);
        }
    }

    private void removeBatch() {
        int n = Math.min(batchSize, queue.size());
        queue.subList(0, n).clear();
        batchId = null;
        batchSize = 0;
    }

    /** `/v1/config` ya da `/v1/events` cevabındaki ölçüm ayarı. */
    @SuppressWarnings("unchecked")
    public void applyConfig(String body) {
        if (body == null || body.isEmpty()) return;
        Object parsed;
        try {
            parsed = Json.parse(body);
        } catch (IllegalArgumentException bad) {
            return;
        }
        if (!(parsed instanceof Map)) return;
        Map<String, Object> root = (Map<String, Object>) parsed;
        Object holder = root.get("config") instanceof Map ? root.get("config") : root;
        Object t = ((Map<String, Object>) holder).get("telemetry");
        if (!(t instanceof Map)) return;
        Map<String, Object> tm = (Map<String, Object>) t;
        if (tm.get("enabled") instanceof Boolean) {
            config.enabled = (Boolean) tm.get("enabled");
            if (!config.enabled) clear();
        }
        if (tm.get("sample") instanceof Number) config.sample = Math.max(0, Math.min(1, ((Number) tm.get("sample")).doubleValue()));
        if (tm.get("maxPerDay") instanceof Number) config.maxPerDay = Math.max(0, ((Number) tm.get("maxPerDay")).intValue());
        if (tm.get("flushSeconds") instanceof Number) config.flushSeconds = Math.max(30, ((Number) tm.get("flushSeconds")).intValue());
        if (tm.get("diag") instanceof Map) config.diag = (Map<String, Object>) tm.get("diag");
    }

    public void clear() {
        queue.clear();
        batchId = null;
        batchSize = 0;
    }

    /** Ne zaman yeniden denenebileceği (ms, duvar saati); 0: hemen. */
    public long waitUntil() { return waitUntil; }

    // --- Disk ---

    /** Diske yazılacak durum. */
    public String save() {
        Map<String, Object> s = new LinkedHashMap<>();
        s.put("events", new ArrayList<Object>(queue));
        if (batchId != null) {
            s.put("batch", batchId);
            s.put("batchSize", (long) batchSize);
        }
        s.put("day", day);
        s.put("today", (long) today);
        s.put("enabled", config.enabled);
        s.put("maxPerDay", (long) config.maxPerDay);
        s.put("flushSeconds", (long) config.flushSeconds);
        s.put("sample", config.sample);
        return Json.write(s);
    }

    /** Diskteki durumu yükler; bozuksa boş başlar. */
    @SuppressWarnings("unchecked")
    public void load(String saved) {
        clear();
        if (saved == null || saved.isEmpty()) return;
        try {
            Map<String, Object> s = (Map<String, Object>) Json.parse(saved);
            for (Object e : (List<Object>) s.get("events")) {
                if (e instanceof Map && queue.size() < MAX_QUEUE) queue.add((Map<String, Object>) e);
            }
            if (s.get("batch") instanceof String && s.get("batchSize") instanceof Number) {
                batchId = (String) s.get("batch");
                batchSize = Math.min(queue.size(), ((Number) s.get("batchSize")).intValue());
                if (batchSize <= 0) batchId = null;
            }
            if (s.get("day") instanceof Number) day = ((Number) s.get("day")).longValue();
            if (s.get("today") instanceof Number) today = ((Number) s.get("today")).intValue();
            if (s.get("enabled") instanceof Boolean) config.enabled = (Boolean) s.get("enabled");
            if (s.get("maxPerDay") instanceof Number) config.maxPerDay = ((Number) s.get("maxPerDay")).intValue();
            if (s.get("flushSeconds") instanceof Number) config.flushSeconds = ((Number) s.get("flushSeconds")).intValue();
            if (s.get("sample") instanceof Number) config.sample = ((Number) s.get("sample")).doubleValue();
        } catch (RuntimeException broken) {
            clear();
        }
    }

    // --- Olay kurucuları (yalnız kod ve sayı) ---

    public static Map<String, Object> event(String kind) {
        Map<String, Object> e = new LinkedHashMap<>();
        e.put("k", kind);
        return e;
    }

    /**
     * Sayfadan gelen bağlantı olayını süzer: yalnız `tv_connect` (r, ms, proto) ve `tv_drop` (code, after, proto);
     * marka her zaman "androidtv". Bozuk ya da başka türse null.
     */
    @SuppressWarnings("unchecked")
    public static Map<String, Object> fromPage(String json) {
        Object parsed;
        try {
            parsed = Json.parse(json);
        } catch (IllegalArgumentException bad) {
            return null;
        }
        if (!(parsed instanceof Map)) return null;
        Map<String, Object> in = (Map<String, Object>) parsed;
        Object k = in.get("k");
        Object proto = in.get("proto");
        Map<String, Object> e;
        if ("tv_connect".equals(k) && in.get("r") instanceof String && in.get("ms") instanceof Number) {
            e = event("tv_connect");
            e.put("r", Codes.code((String) in.get("r")));
            e.put("ms", Math.max(0, Math.min(3_600_000L, ((Number) in.get("ms")).longValue())));
        } else if ("tv_drop".equals(k) && in.get("code") instanceof String && in.get("after") instanceof Number) {
            e = event("tv_drop");
            e.put("code", Codes.code((String) in.get("code")));
            e.put("after", Math.max(0, ((Number) in.get("after")).longValue()));
        } else {
            return null;
        }
        e.put("brand", "androidtv");
        e.put("proto", "nino".equals(proto) ? "nino" : "legacy");
        return e;
    }

    public static Map<String, Object> error(String code) {
        Map<String, Object> e = event("error");
        e.put("code", Codes.clean(code, 64));
        return e;
    }

    /** Hata kodu ve sembol adı kuralları: yalnız izinli karakterler, sınırlı uzunluk. */
    public static final class Codes {
        private Codes() {}

        static String clean(String code, int max) {
            if (code == null) return "other";
            String c = code.replaceAll("[^A-Za-z0-9_.$-]", "");
            if (c.isEmpty()) return "other";
            return c.length() > max ? c.substring(0, max) : c;
        }

        /** Çökme yeri: sembol adı, `[A-Za-z0-9_.:$<>+-]`, en çok 120 (dosya yolu gitmez). */
        public static String where(String symbol) {
            if (symbol == null) return null;
            String c = symbol.replaceAll("[^A-Za-z0-9_.:$<>+-]", "");
            if (c.isEmpty()) return null;
            return c.length() > 120 ? c.substring(0, 120) : c;
        }

        public static String code(String code) { return clean(code, 64); }
    }
}
