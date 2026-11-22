// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.tv;

import android.content.Context;
import android.content.SharedPreferences;
import android.net.nsd.NsdManager;
import android.net.nsd.NsdServiceInfo;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.provider.Settings;
import android.util.Log;

import com.ninotranslator.tv.link.LinkServer;
import com.ninotranslator.tv.link.Wire;

import java.net.Inet4Address;
import java.net.InetAddress;
import java.net.NetworkInterface;
import java.util.UUID;
import java.util.concurrent.CopyOnWriteArrayList;

/**
 * Süreç boyunca tek olan bağlantı merkezi: protokol sunucusunu açar, kendini ağda yayınlar ve olayları ana iş
 * parçacığında altyazı sayfalarına dağıtır. Uygulama içi görünüm, katman ve ana ekran aynı merkezi dinler; ekran
 * kapanınca bağlantı sürer.
 */
final class LinkHub {
    /** Merkezi dinleyen bir sayfa. Hepsi ana iş parçacığında çağrılır. */
    interface Viewer {
        void show(Wire.Subtitle subtitle);

        void clear();

        void sender(boolean connected);

        /** Nino uzantı mesajı (type alanıyla birlikte). */
        void extension(java.util.Map<String, Object> message);

        /** Eski (8787) gönderici uygulamayı yeni açılış bilgisiyle açtı (ör. {"server":"http://ip:8787"}). */
        default void relaunch(String params) { }

        /** Eski yolu (8787) bu sayfa mı çalıştırır. Aynı anda yalnız bir sayfa çalıştırır (bkz. legacyHolder). */
        default void legacy(boolean holder) { }

        /** Eski yoldan bir gönderici bağlı mı (eski yolu çalıştıran sayfa bildirir; öbür sayfalar durumu gösterir). */
        default void legacyLinked(boolean open) { }

        /** Eski yolu tercihen bu sayfa mı çalıştırmalı (katman: süreç boyunca açık kalır). */
        default boolean prefersLegacy() { return false; }
    }

    /**
     * Eski yolu (8787, sayfanın kendi bağlantı katmanı) çalıştıran tek sayfa. İki sayfa aynı anda bağlanırsa (ana
     * ekran arka planda açıkken katman) gönderici aynı TV'yi iki kez görür ve birini öbürüyle 2 sn'de bir değiştirir.
     * Katman sayfası varsa o, yoksa en son açılan sayfa.
     */
    private Viewer legacyHolder;
    private boolean legacyOpen;

    private void pickLegacyHolder() {
        Viewer next = null;
        for (Viewer v : viewers) if (v.prefersLegacy()) { next = v; break; }
        if (next == null && !viewers.isEmpty()) next = viewers.get(viewers.size() - 1);
        if (next == legacyHolder) return;
        Viewer old = legacyHolder;
        legacyHolder = next;
        if (old != null && viewers.contains(old)) old.legacy(false);
        if (next != null) next.legacy(true);
        if (next == null || old != null) setLegacyLinked(false);
    }

    boolean isLegacyHolder(Viewer viewer) { return viewer == legacyHolder; }

    /** Eski yolu çalıştıran sayfa bağlantı durumunu bildirdi; öbür sayfalara iletilir. */
    void setLegacyLinked(boolean open) {
        legacyOpen = open;
        for (Viewer v : viewers) v.legacyLinked(open);
    }

    /** Son açılış bilgisi (eski göndericinin `params` ek bilgisi); yeni açılan sayfa da bununla başlar. */
    private String launchParams = "";

    String launchParams() { return launchParams; }

    void setLaunchParams(String params) {
        if (params == null || params.trim().isEmpty()) return;
        launchParams = params;
        for (Viewer v : viewers) v.relaunch(params);
    }

    private static final String TAG = "NinoLink";
    private static LinkHub instance;

    private final Context app;
    private final Handler main = new Handler(Looper.getMainLooper());
    private final CopyOnWriteArrayList<Viewer> viewers = new CopyOnWriteArrayList<>();
    private LinkServer server;
    private NsdManager.RegistrationListener advert;
    private boolean connected;
    private boolean opening;
    private Wire.Subtitle shown;
    /** Son görünüm ayarı (`style`); sonradan açılan sayfa da aynı görünümle başlasın. */
    private java.util.Map<String, Object> style;

    private LinkHub(Context context) { app = context.getApplicationContext(); }

    static synchronized LinkHub get(Context context) {
        if (instance == null) instance = new LinkHub(context);
        return instance;
    }

    /** Sunucu kapalıysa açar. Bağlantı noktası doluysa sessizce vazgeçer; sonraki çağrı yeniden dener. */
    void ensureRunning() {
        if (opening || (server != null && server.isRunning())) return;
        opening = true;
        String name = tvName();
        LinkServer fresh = new LinkServer(name, tvId(), Wire.PORT, new LinkServer.Listener() {
            @Override public void onShow(Wire.Subtitle subtitle) { main.post(() -> deliverShow(subtitle)); }
            @Override public void onClear() { main.post(LinkHub.this::deliverClear); }
            @Override public void onSender(boolean on, String client) { main.post(() -> deliverSender(on)); }
            @Override public void onExtension(Wire.Message message) { main.post(() -> deliverExtension(message.fields())); }
            @Override public void onHandshake(long ms) {
                java.util.Map<String, Object> e = com.ninotranslator.tv.metrics.Outbox.event("tv_connect");
                e.put("r", "ok");
                e.put("ms", ms);
                e.put("brand", "androidtv");
                e.put("proto", "nino");
                Metrics.get(app).record(e);
                Metrics.get(app).tvConnected();
            }
            @Override public void onReplaced(long afterSec) { Metrics.get(app).tvDropped("replaced"); }
            @Override public void onLost(long afterSec, String cause) {
                Metrics.get(app).tvDropped(cause);
                java.util.Map<String, Object> e = com.ninotranslator.tv.metrics.Outbox.event("tv_drop");
                e.put("code", "network_lost");
                e.put("brand", "androidtv");
                e.put("after", afterSec);
                Metrics.get(app).record(e);
            }
        });
        Thread opener = new Thread(() -> {
            try {
                int port = fresh.start();
                main.post(() -> {
                    opening = false;
                    server = fresh;
                    advertise(name, port);
                });
            } catch (java.io.IOException busy) {
                Log.w(TAG, "sunucu açılamadı: " + busy.getMessage());
                main.post(() -> opening = false);
            }
        }, "nino-link-open");
        opener.start();
    }

    void watch(Viewer viewer) {
        viewers.addIfAbsent(viewer);
        pickLegacyHolder();
        viewer.legacyLinked(legacyOpen);
        ensureRunning();
        viewer.sender(connected);
        if (style != null) viewer.extension(style);
        if (shown != null) viewer.show(shown);
    }

    void unwatch(Viewer viewer) {
        viewers.remove(viewer);
        if (viewer == legacyHolder) legacyHolder = null;
        pickLegacyHolder();
    }

    boolean connected() { return connected; }

    private void deliverShow(Wire.Subtitle subtitle) {
        shown = subtitle;
        for (Viewer v : viewers) v.show(subtitle);
    }

    private void deliverClear() {
        shown = null;
        for (Viewer v : viewers) v.clear();
    }

    /** Göndericideki görüntü modu ayarı değişti (bkz. DisplayChoice). */
    interface ModeListener {
        void displayModeChanged(String mode);
    }

    private final CopyOnWriteArrayList<ModeListener> modeListeners = new CopyOnWriteArrayList<>();

    void listenMode(ModeListener listener) { modeListeners.addIfAbsent(listener); }

    void unlistenMode(ModeListener listener) { modeListeners.remove(listener); }

    private void deliverExtension(java.util.Map<String, Object> message) {
        if ("style".equals(message.get("type"))) {
            style = message;
            Object mode = message.get("displayMode");
            if (mode instanceof String) applyDisplayMode((String) mode);
        }
        for (Viewer v : viewers) v.extension(message);
    }

    /** Göndericiden (yeni yol, eski 8787 yolu ya da açılış ek bilgisi) gelen görüntü modu; değiştiyse bildirilir. */
    void applyDisplayMode(String mode) {
        if (DisplayChoice.store(app, mode)) {
            for (ModeListener l : modeListeners) l.displayModeChanged(DisplayChoice.normalize(mode));
        }
    }

    private void deliverSender(boolean on) {
        connected = on;
        for (Viewer v : viewers) v.sender(on);
    }

    // --- Ağda görünme ---

    private void advertise(String name, int port) {
        NsdManager nsd = (NsdManager) app.getSystemService(Context.NSD_SERVICE);
        if (nsd == null || advert != null) return;
        NsdServiceInfo info = new NsdServiceInfo();
        info.setServiceName(name);
        info.setServiceType(Wire.SERVICE_TYPE);
        info.setPort(port);
        info.setAttribute("v", String.valueOf(Wire.VERSION));
        info.setAttribute("id", tvId());
        advert = new NsdManager.RegistrationListener() {
            @Override public void onRegistrationFailed(NsdServiceInfo s, int code) {
                Log.w(TAG, "yayın başarısız: " + code);
                advert = null;
            }
            @Override public void onUnregistrationFailed(NsdServiceInfo s, int code) { }
            @Override public void onServiceRegistered(NsdServiceInfo s) { Log.i(TAG, "yayında: " + s.getServiceName()); }
            @Override public void onServiceUnregistered(NsdServiceInfo s) { }
        };
        try {
            nsd.registerService(info, NsdManager.PROTOCOL_DNS_SD, advert);
        } catch (RuntimeException refused) {
            advert = null;
        }
    }

    // --- TV'nin kimliği ---

    /** Gönderici listesinde görünen ad: TV'nin kullanıcı adı, yoksa marka ve model. */
    String tvName() {
        String name = null;
        try {
            name = Settings.Global.getString(app.getContentResolver(), "device_name");
        } catch (RuntimeException ignored) {
            // bazı TV'lerde okunamaz
        }
        if (name == null || name.trim().isEmpty()) name = model();
        return name.trim();
    }

    /** "TCL 98U95A" gibi; model zaten markayla başlıyorsa tekrar edilmez. */
    static String model() {
        String maker = Build.MANUFACTURER == null ? "" : Build.MANUFACTURER.trim();
        String model = Build.MODEL == null ? "" : Build.MODEL.trim();
        if (model.isEmpty()) return maker.isEmpty() ? "Nino TV" : maker;
        boolean repeats = model.regionMatches(true, 0, maker, 0, maker.length());
        return repeats ? model : (maker + " " + model).trim();
    }

    private String tvId() {
        SharedPreferences prefs = app.getSharedPreferences("link", Context.MODE_PRIVATE);
        String id = prefs.getString("id", null);
        if (id == null) {
            id = UUID.randomUUID().toString();
            prefs.edit().putString("id", id).apply();
        }
        return id;
    }

    /** TV'nin ev ağındaki IPv4 adresi; bilinmiyorsa "". Kablolu bağlantı (eth) kablosuza tercih edilir. */
    static String address() {
        String wireless = "";
        try {
            java.util.Enumeration<NetworkInterface> faces = NetworkInterface.getNetworkInterfaces();
            while (faces != null && faces.hasMoreElements()) {
                NetworkInterface face = faces.nextElement();
                if (face.isLoopback() || !face.isUp() || face.isVirtual()) continue;
                for (java.net.InterfaceAddress entry : face.getInterfaceAddresses()) {
                    InetAddress ip = entry.getAddress();
                    if (!(ip instanceof Inet4Address) || !ip.isSiteLocalAddress()) continue;
                    if (face.getName().startsWith("eth")) return ip.getHostAddress();
                    if (wireless.isEmpty()) wireless = ip.getHostAddress();
                }
            }
        } catch (java.net.SocketException unreadable) {
            // ağ bilgisi okunamadı
        }
        return wireless;
    }
}
