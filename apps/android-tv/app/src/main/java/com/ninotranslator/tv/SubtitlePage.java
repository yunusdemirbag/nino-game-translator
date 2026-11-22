// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.tv;

import android.annotation.SuppressLint;
import android.content.Context;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.os.Handler;
import android.os.Looper;
import android.util.DisplayMetrics;
import android.view.View;
import android.view.WindowManager;
import android.webkit.JavascriptInterface;
import android.webkit.WebSettings;
import android.webkit.WebView;

import com.ninotranslator.tv.link.Json;
import com.ninotranslator.tv.link.Wire;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Şeffaf bir WebView'de çalışan Nino sayfası (assets/page). Altyazıyı, ana ekranı, izin ekranını ve bekleme demosunu
 * o çizer; bu sınıf sayfaya olayları taşır ve sayfanın isteklerini barındıran tarafa iletir.
 *
 * Sayfaya giden her şey `window.ninoAndroid.receive(nesne)` çağrısıdır (web/androidtv.js); nesneler {@link Json} ile yazılır, metin hiçbir
 * zaman betik olarak eklenmez. Sayfa hazır olana kadar olaylar sırada bekler.
 */
final class SubtitlePage implements LinkHub.Viewer {
    /** Sayfanın göründüğü yer. */
    enum Mode { HOME, PERMISSION, OVERLAY, IN_APP }

    /** Sayfanın istekleri; hepsi ana iş parçacığında çağrılır. */
    interface Host {
        default void pickHdmi(int number) { }

        default void stepHdmi(int step) { }

        default void findConsole() { }

        default void grantPermission() { }

        default void continueWithout() { }

        void leave();

        /**
         * WebView'in çizim süreci çöktü ya da bellek için kapatıldı (düşük güçlü TV'lerde olur). Bu sayfa artık
         * kullanılamaz; barındıran taraf yenisini kurar. Uygulama kapanmaz.
         */
        default void pageLost() { }
    }

    /** LG ve Samsung'la ortak sayfa (apps/tv-web; derlemede assets/tv'ye konur, bkz. app/build.gradle). */
    private static final String PAGE = "file:///android_asset/tv/index.html";

    final WebView view;
    private final Context context;
    private final Host host;
    private final Mode mode;
    private final Handler main = new Handler(Looper.getMainLooper());
    private final List<String> waiting = new ArrayList<>();
    private boolean ready;
    private boolean closed;

    @SuppressLint({"SetJavaScriptEnabled", "AddJavascriptInterface"})
    SubtitlePage(Context context, Mode mode, Host host) {
        this.context = context;
        this.mode = mode;
        this.host = host;
        view = new WebView(context);
        view.setBackgroundColor(Color.TRANSPARENT);
        view.setLayerType(View.LAYER_TYPE_HARDWARE, null);
        view.setFocusable(false);
        WebSettings settings = view.getSettings();
        settings.setJavaScriptEnabled(true);
        settings.setDomStorageEnabled(true);
        settings.setAllowFileAccess(true);
        settings.setAllowContentAccess(false);
        settings.setUseWideViewPort(true);
        settings.setLoadWithOverviewMode(true);
        settings.setSupportZoom(false);
        // Sayfa 1920 piksel genişliğinde düzenlenir; WebView ekranın gerçek genişliğine ölçekler.
        view.setInitialScale(scalePercent());
        view.addJavascriptInterface(new Bridge(), "NinoNative");
        view.setWebViewClient(new android.webkit.WebViewClient() {
            @Override
            @android.annotation.TargetApi(26)
            public boolean onRenderProcessGone(WebView dead, android.webkit.RenderProcessGoneDetail detail) {
                android.util.Log.w("NinoPage", "sayfa süreci kapandı; yeniden kuruluyor");
                Metrics.get(context).error(detail.didCrash() ? "tv.page.crashed" : "tv.page.oom");
                close();
                main.post(host::pageLost);
                return true;
            }
        });
        if (BuildConfig.DEBUG) {
            // Hata ayıklama derlemesinde sayfanın günlüğü logcat'e (etiket NinoPage) düşer.
            view.setWebChromeClient(new android.webkit.WebChromeClient() {
                @Override
                public boolean onConsoleMessage(android.webkit.ConsoleMessage m) {
                    android.util.Log.d("NinoPage", m.messageLevel() + " " + m.message() + " @" + m.sourceId() + ":" + m.lineNumber());
                    return true;
                }
            });
            WebView.setWebContentsDebuggingEnabled(true);
        }
    }

    void open() {
        view.loadUrl(PAGE);
        LinkHub.get(context).watch(this);
    }

    void close() {
        if (closed) return;
        closed = true;
        LinkHub.get(context).unwatch(this);
        main.removeCallbacksAndMessages(null);
        view.destroy();
    }

    // --- Merkezden gelenler ---

    @Override
    public void show(Wire.Subtitle subtitle) { send(subtitle.toMap()); }

    @Override
    public void clear() { send(event("clear")); }

    @Override
    public void extension(Map<String, Object> message) { send(new LinkedHashMap<>(message)); }

    @Override
    public void legacy(boolean holder) {
        Map<String, Object> e = event("legacy");
        e.put("on", holder);
        send(e);
    }

    @Override
    public void legacyLinked(boolean open) {
        Map<String, Object> e = event("legacyLink");
        e.put("open", open);
        send(e);
    }

    @Override
    public boolean prefersLegacy() { return mode == Mode.OVERLAY; }

    @Override
    public void relaunch(String params) {
        Map<String, Object> e = event("relaunch");
        e.put("params", params);
        send(e);
    }

    @Override
    public void sender(boolean connected) {
        Map<String, Object> e = event("link");
        e.put("open", connected);
        send(e);
    }

    // --- Barındıran taraftan gelenler ---

    /** HDMI girişinin durumu: loading, ready, playing, inputError, sourceError. */
    void hdmi(int number, String state, String device) {
        Map<String, Object> e = event("hdmi");
        e.put("port", (long) number);
        e.put("state", state);
        if (device != null) e.put("device", device);
        send(e);
    }

    /** Kumanda tuşu (sayfanın anladığı kodlarla: 0–9 için 48–57, oklar 37–40, Tamam 13, Geri 4, renkler 403/404/406). */
    void key(int code) {
        Map<String, Object> e = event("key");
        e.put("code", (long) code);
        send(e);
    }

    /** Uygulama arka plana geçti ya da öne geldi. */
    void visible(boolean on) {
        Map<String, Object> e = event("visible");
        e.put("on", on);
        send(e);
    }

    private static Map<String, Object> event(String type) {
        Map<String, Object> e = new LinkedHashMap<>();
        e.put("type", type);
        return e;
    }

    private void send(Map<String, Object> message) {
        String json = Json.write(message);
        main.post(() -> {
            if (closed) return;
            if (!ready) {
                waiting.add(json);
                return;
            }
            run(json);
        });
    }

    private void run(String json) {
        view.evaluateJavascript("window.ninoAndroid&&window.ninoAndroid.receive(" + json + ")", null);
    }

    private int scalePercent() {
        DisplayMetrics metrics = new DisplayMetrics();
        WindowManager windows = (WindowManager) context.getSystemService(Context.WINDOW_SERVICE);
        windows.getDefaultDisplay().getRealMetrics(metrics);
        int wide = Math.max(metrics.widthPixels, metrics.heightPixels);
        return wide > 0 ? Math.max(1, Math.round(wide * 100f / 1920f)) : 0;
    }

    private String setup() {
        Map<String, Object> s = new LinkedHashMap<>();
        s.put("mode", mode.name().toLowerCase(java.util.Locale.ROOT).replace("_", ""));
        s.put("name", LinkHub.get(context).tvName());
        s.put("address", LinkHub.address());
        s.put("version", version());
        s.put("overlayBuild", BuildConfig.CAN_OVERLAY);
        s.put("model", LinkHub.model());
        s.put("install", Metrics.get(context).install());
        s.put("params", LinkHub.get(context).launchParams());
        s.put("legacy", LinkHub.get(context).isLegacyHolder(this));
        Inputs.Port console = Inputs.console(Inputs.ports(context));
        s.put("consolePort", console == null ? 0L : (long) console.number);
        s.put("consoleLabel", console == null || Inputs.looksLikePlayStation(console.label) ? "" : console.label);
        return Json.write(s);
    }

    private String version() {
        try {
            return context.getPackageManager().getPackageInfo(context.getPackageName(), 0).versionName;
        } catch (PackageManager.NameNotFoundException e) {
            return "";
        }
    }

    /** Sayfanın çağırabildikleri ("NinoNative"). WebView'in kendi iş parçacığından gelir. */
    private final class Bridge {
        @JavascriptInterface
        public String setup() { return SubtitlePage.this.setup(); }

        @JavascriptInterface
        public void ready() {
            main.post(() -> {
                if (closed) return;
                ready = true;
                for (String json : waiting) run(json);
                waiting.clear();
            });
        }

        @JavascriptInterface
        public void pickHdmi(int number) { main.post(() -> host.pickHdmi(number)); }

        @JavascriptInterface
        public void stepHdmi(int step) { main.post(() -> host.stepHdmi(step)); }

        /** PS5'in girişinin numarası, bulunamazsa 0 (ortak sayfanın findConsolePort'u için). */
        @JavascriptInterface
        public int consolePort() {
            Inputs.Port console = Inputs.console(Inputs.ports(context));
            return console == null ? 0 : console.number;
        }

        @JavascriptInterface
        public void findConsole() { main.post(host::findConsole); }

        @JavascriptInterface
        public void grantPermission() { main.post(host::grantPermission); }

        @JavascriptInterface
        public void continueWithout() { main.post(host::continueWithout); }

        @JavascriptInterface
        public void leave() { main.post(host::leave); }

        /**
         * Sayfanın eski yol ölçümü (tv_connect / tv_drop). Sayfadan gelen hiçbir şeye güvenilmez: yalnız bu iki tür
         * ve bilinen alanlar, kod kuralına uyan değerlerle alınır.
         */
        @JavascriptInterface
        public void measure(String json) { Metrics.get(context).recordFromPage(json); }

        /** Eski yolu çalıştıran sayfa: eski yoldan bir gönderici bağlı mı. */
        @JavascriptInterface
        public void legacyLinked(boolean open) {
            main.post(() -> { if (!closed && LinkHub.get(context).isLegacyHolder(SubtitlePage.this)) LinkHub.get(context).setLegacyLinked(open); });
        }

        /** Eski (8787) göndericinin `style` olayındaki görüntü modu. */
        @JavascriptInterface
        public void setDisplayMode(String mode) { main.post(() -> LinkHub.get(context).applyDisplayMode(mode)); }

        /** Sayfanın havuz için tuttuğu kurulum kimliği (ölçüm aynısını kullanır). */
        @JavascriptInterface
        public void adoptInstall(String id) { Metrics.get(context).adoptInstall(id); }
    }
}
