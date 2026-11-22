// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.tv;

import android.app.ActivityManager;
import android.app.ApplicationExitInfo;
import android.content.Context;
import android.content.SharedPreferences;
import android.os.Build;
import android.os.SystemClock;

import com.ninotranslator.tv.link.Json;
import com.ninotranslator.tv.metrics.Outbox;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;
import java.util.zip.GZIPOutputStream;

/**
 * Anonim hata ve hız ölçümü (tarif: NinoCore docs/tarif/olcum.md). Yalnız kod ve sayı gider: altyazı, ad, adres
 * gitmez. TV'de ayar ekranı yok; sunucu `telemetry.enabled` ile kapatabilir. Kurallar {@link Outbox}'tadır; bu sınıf
 * diski, ağı ve zamanlamayı yapar. Bütün iş tek bir arka iş parçacığında yürür.
 */
final class Metrics {
    /** Havuzun kök adresi; boşsa (hata ayıklama derlemesi) hiçbir şey gönderilmez, olaylar yalnız kuyrukta durur. */
    private static final String POOL = BuildConfig.METRICS_URL;
    private static final int TIMEOUT_MS = 15_000;
    private static Metrics instance;

    private final Context app;
    private final ScheduledExecutorService worker = Executors.newSingleThreadScheduledExecutor(r -> {
        Thread t = new Thread(r, "nino-metrics");
        t.setDaemon(true);
        t.setPriority(Thread.MIN_PRIORITY);
        return t;
    });
    private final Outbox outbox = new Outbox();
    private final File dir;
    private final long startedAt = SystemClock.elapsedRealtime();
    /** Otomatik teşhis bekçisi; yalnız `worker` iş parçacığında kullanılır. */
    private com.ninotranslator.tv.metrics.Watchman watchman;
    /** Ana iş parçacığının son yanıt verdiği an (izleyici için). */
    private volatile long mainTick = SystemClock.elapsedRealtime();

    private Metrics(Context context) {
        app = context.getApplicationContext();
        dir = new File(app.getFilesDir(), "telemetry");
    }

    static synchronized Metrics get(Context context) {
        if (instance == null) instance = new Metrics(context);
        return instance;
    }

    /** Süreç açılışında bir kez (NinoTvApp). Önceki çalışma çöktüyse bildirir, `launch` ekler, çökme yakalayıcıyı kurar. */
    void start() {
        watchCrashes();
        worker.execute(() -> {
            dir.mkdirs();
            outbox.load(read(new File(dir, "queue.json")));
            Map<String, Object> crash = previousCrash();
            if (crash != null) outbox.add(crash, System.currentTimeMillis());
            writeMarker(null, null);
            outbox.add(Outbox.event("launch"), System.currentTimeMillis());
            watchman = new com.ninotranslator.tv.metrics.Watchman(nowSec(), diag -> {
                outbox.add(diag, System.currentTimeMillis());
                save();
            });
            watchman.setTv(LinkHub.model(), version());
            watchman.applyConfig(outbox.config().diag);
            save();
            schedule();
            watchHealth();
        });
    }

    private static long nowSec() { return System.currentTimeMillis() / 1000; }

    // --- Otomatik teşhis (bekçi) ---

    void tvConnected() { worker.execute(() -> { if (watchman != null) watchman.tvConnected(nowSec()); }); }

    /** cause: write_error · timeout · closed · resume · network_change */
    void tvDropped(String cause) { worker.execute(() -> { if (watchman != null) watchman.tvDropped(nowSec(), cause); }); }

    /** İz adımı (app.background, app.foreground…). */
    void step(String code) { worker.execute(() -> { if (watchman != null) watchman.step(nowSec(), code, null); }); }

    /** İşletim sisteminin bellek uyarısı (onTrimMemory, uygulama öndeyken). */
    void memoryWarning() { worker.execute(() -> { if (watchman != null) watchman.memory(nowSec(), memoryMB(), true); }); }

    /**
     * Donma izleyicisi ve bellek ölçümü. Ana iş parçacığına saniyede bir küçük bir iş bırakılır; 5 sn'den uzun süre
     * yapılmazsa donma sayılır. Bellek 30 sn'de bir ölçülür. Zayıf TV'lerde de yükü önemsizdir.
     */
    private void watchHealth() {
        android.os.Handler main = new android.os.Handler(android.os.Looper.getMainLooper());
        worker.scheduleWithFixedDelay(() -> {
            long blocked = (SystemClock.elapsedRealtime() - mainTick) / 1000;
            if (blocked >= 5 && watchman != null) watchman.mainThreadBlocked(nowSec(), blocked, memoryMB());
            main.post(() -> mainTick = SystemClock.elapsedRealtime());
        }, 1, 1, TimeUnit.SECONDS);
        worker.scheduleWithFixedDelay(() -> {
            if (watchman != null) watchman.memory(nowSec(), memoryMB(), false);
        }, 30, 30, TimeUnit.SECONDS);
    }

    private static long memoryMB() {
        try {
            return android.os.Debug.getPss() / 1024;
        } catch (RuntimeException unknown) {
            return 0;
        }
    }

    /** Olay ekler (yalnız kod ve sayı içermeli). */
    void record(Map<String, Object> event) {
        worker.execute(() -> {
            outbox.add(event, System.currentTimeMillis());
            save();
            if (outbox.full()) flush();
        });
    }

    void error(String code) { record(Outbox.error(code)); }

    /** Sayfanın ölçtüğü bağlantı olayı (bkz. Outbox.fromPage); geçersizse yok sayılır. */
    void recordFromPage(String json) {
        Map<String, Object> event = Outbox.fromPage(json);
        if (event == null) return;
        record(event);
        // Eski yolun bağlanma/kopmaları da bekçiye (TV bağlantısı sık kopuyor mu).
        if ("tv_connect".equals(event.get("k")) && "ok".equals(event.get("r"))) tvConnected();
        if ("tv_drop".equals(event.get("k"))) tvDropped("timeout".equals(event.get("code")) ? "timeout" : "closed");
    }

    private final java.util.Set<String> once = java.util.Collections.synchronizedSet(new java.util.HashSet<>());

    /** Süreç başına bir kez sayılan hata (ör. izin ekranı her yeniden kuruluşta sayılmasın). */
    void errorOnce(String code) { if (once.add(code)) error(code); }

    /** Uygulama arka plana geçti: kuyruk hemen gönderilir. */
    void flushSoon() { worker.execute(this::flush); }

    /** Sayfanın havuz için tuttuğu kurulum kimliği; ölçüm de aynısını kullanır. */
    void adoptInstall(String id) {
        if (id == null || !id.matches("[0-9a-fA-F-]{36}")) return;
        prefs().edit().putString("install", id.toLowerCase(java.util.Locale.ROOT)).apply();
    }

    String install() {
        String id = prefs().getString("install", null);
        if (id == null) {
            id = UUID.randomUUID().toString();
            prefs().edit().putString("install", id).apply();
        }
        return id;
    }

    private SharedPreferences prefs() { return app.getSharedPreferences("metrics", Context.MODE_PRIVATE); }

    private void schedule() {
        long every = Math.max(30, outbox.config().flushSeconds);
        worker.schedule(() -> {
            flush();
            schedule();
        }, every, TimeUnit.SECONDS);
    }

    // --- Gönderim ---

    private void flush() {
        long now = System.currentTimeMillis();
        if (POOL.isEmpty() || !outbox.ready(now)) return;
        String body = outbox.nextBody(install(), ctx());
        if (body == null) return;
        save();
        int status = 0;
        String answer = null;
        long retryAfter = 0;
        HttpURLConnection http = null;
        try {
            http = (HttpURLConnection) new URL(POOL + "/v1/events").openConnection();
            http.setConnectTimeout(TIMEOUT_MS);
            http.setReadTimeout(TIMEOUT_MS);
            http.setRequestMethod("POST");
            http.setDoOutput(true);
            http.setRequestProperty("content-type", "application/json");
            http.setRequestProperty("content-encoding", "gzip");
            byte[] packed = gzip(body);
            http.setFixedLengthStreamingMode(packed.length);
            try (OutputStream out = http.getOutputStream()) {
                out.write(packed);
            }
            status = http.getResponseCode();
            String after = http.getHeaderField("retry-after");
            if (after != null) {
                try { retryAfter = Long.parseLong(after.trim()); } catch (NumberFormatException ignored) { /* tarih biçimi */ }
            }
            InputStream in = status < 400 ? http.getInputStream() : http.getErrorStream();
            answer = in == null ? "" : text(in);
        } catch (IOException offline) {
            status = 0;
        } finally {
            if (http != null) http.disconnect();
        }
        outbox.answered(status, answer, retryAfter, System.currentTimeMillis());
        if (watchman != null) watchman.applyConfig(outbox.config().diag);
        save();
    }

    private Map<String, Object> ctx() {
        Map<String, Object> c = new LinkedHashMap<>();
        c.put("platform", "androidtv");
        c.put("app", version());
        c.put("os", "Android " + Build.VERSION.RELEASE);
        c.put("device", LinkHub.model());
        c.put("tv", "");
        c.put("channel", BuildConfig.DEBUG ? "dev" : "release");
        return c;
    }

    private String version() {
        try {
            return app.getPackageManager().getPackageInfo(app.getPackageName(), 0).versionName;
        } catch (Exception e) {
            return "";
        }
    }

    // --- Çökmeler (çalışma işareti) ---

    /** Yakalanmamış istisnada yalnız sınıf adı ve uygulama içi en üst çerçeve işarete yazılır (mesaj yazılmaz). */
    private void watchCrashes() {
        Thread.UncaughtExceptionHandler previous = Thread.getDefaultUncaughtExceptionHandler();
        Thread.setDefaultUncaughtExceptionHandler((thread, error) -> {
            try {
                writeMarker(error.getClass().getName(), ownFrame(error));
            } catch (RuntimeException ignored) {
                // işaret yazılamadı
            }
            if (previous != null) previous.uncaughtException(thread, error);
        });
    }

    private static String ownFrame(Throwable error) {
        for (StackTraceElement frame : error.getStackTrace()) {
            if (frame.getClassName().startsWith("com.ninotranslator.")) {
                String cls = frame.getClassName();
                return Outbox.Codes.where(cls.substring(cls.lastIndexOf('.') + 1) + "." + frame.getMethodName());
            }
        }
        return null;
    }

    private void writeMarker(String code, String where) {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("ver", version());
        m.put("start", System.currentTimeMillis() / 1000);
        m.put("up", (SystemClock.elapsedRealtime() - startedAt) / 1000);
        if (code != null) m.put("code", Outbox.Codes.code(code));
        if (where != null) m.put("where", where);
        dir.mkdirs();
        write(new File(dir, "running.json"), Json.write(m));
    }

    /**
     * Önceki çalışmanın işareti duruyorsa nasıl bittiğine bakılır. Android 11+'da sistemin çıkış nedeni kullanılır:
     * çökme, ANR ve bellek yetmezliği sayılır; sistemin ya da kullanıcının kapatması sayılmaz. Daha eski sürümlerde
     * yalnız yakalayıcının yazdığı istisna sayılır (yanlış "çöktü" demesin).
     */
    @SuppressWarnings("unchecked")
    private Map<String, Object> previousCrash() {
        String saved = read(new File(dir, "running.json"));
        if (saved == null) return null;
        Map<String, Object> marker;
        try {
            marker = (Map<String, Object>) Json.parse(saved);
        } catch (RuntimeException broken) {
            return null;
        }
        String code = marker.get("code") instanceof String ? (String) marker.get("code") : null;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            long startedMs = marker.get("start") instanceof Number ? ((Number) marker.get("start")).longValue() * 1000 : 0;
            String reason = exitReason(startedMs);
            if (reason == null) return null;
            if (code == null || !reason.equals("crash")) code = reason.equals("crash") ? "unclean_exit" : reason;
        } else if (code == null) {
            return null;
        }
        Map<String, Object> e = Outbox.event("crash");
        e.put("code", code);
        if (marker.get("where") instanceof String) e.put("where", marker.get("where"));
        e.put("ver", marker.get("ver") instanceof String ? marker.get("ver") : "");
        if (marker.get("up") instanceof Number) e.put("up", marker.get("up"));
        return e;
    }

    /**
     * crash, anr, oom ya da null (çökme değil). Kayıt önceki çalışmadan (işaretin yazılmasından) eski ise sayılmaz:
     * çıkış kayıtları yeniden başlatmadan sonra da durur, TV fişten çekilince eski çökme yeniden bildirilmesin.
     */
    private String exitReason(long startedMs) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return null;
        try {
            ActivityManager am = (ActivityManager) app.getSystemService(Context.ACTIVITY_SERVICE);
            // WebView'in ayrı süreçleri de aynı paketle kaydedilir; yalnız uygulamanın kendi sürecine bakılır.
            ApplicationExitInfo last = null;
            for (ApplicationExitInfo exit : am.getHistoricalProcessExitReasons(app.getPackageName(), 0, 16)) {
                if (app.getPackageName().equals(exit.getProcessName())) {
                    last = exit;
                    break;
                }
            }
            if (last == null || last.getTimestamp() < startedMs) return null;
            switch (last.getReason()) {
                case ApplicationExitInfo.REASON_CRASH:
                case ApplicationExitInfo.REASON_CRASH_NATIVE:
                    return "crash";
                case ApplicationExitInfo.REASON_ANR:
                    return "anr";
                case ApplicationExitInfo.REASON_LOW_MEMORY:
                    return "oom";
                default:
                    return null;
            }
        } catch (RuntimeException unavailable) {
            return null;
        }
    }

    // --- Disk ---

    private void save() { write(new File(dir, "queue.json"), outbox.save()); }

    private static String read(File file) {
        if (!file.exists()) return null;
        try (InputStream in = new FileInputStream(file)) {
            return text(in);
        } catch (IOException unreadable) {
            return null;
        }
    }

    private static void write(File file, String text) {
        File temp = new File(file.getPath() + ".tmp");
        try (OutputStream out = new FileOutputStream(temp)) {
            out.write(text.getBytes(StandardCharsets.UTF_8));
        } catch (IOException full) {
            return;
        }
        if (!temp.renameTo(file)) temp.delete();
    }

    private static String text(InputStream in) throws IOException {
        ByteArrayOutputStream all = new ByteArrayOutputStream();
        byte[] buf = new byte[8192];
        int n;
        while ((n = in.read(buf)) > 0) all.write(buf, 0, n);
        return all.toString("UTF-8");
    }

    private static byte[] gzip(String body) throws IOException {
        ByteArrayOutputStream packed = new ByteArrayOutputStream();
        try (GZIPOutputStream zip = new GZIPOutputStream(packed)) {
            zip.write(body.getBytes(StandardCharsets.UTF_8));
        }
        return packed.toByteArray();
    }
}
