// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.tv;

import android.app.Activity;
import android.content.ActivityNotFoundException;
import android.content.Intent;
import android.graphics.Color;
import android.net.Uri;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.provider.Settings;
import android.view.KeyEvent;
import android.widget.FrameLayout;
import android.widget.Toast;

/**
 * Nino'nun tek ekranı. Ne göstereceğine {@link Startup} karar verir: ana ekran, izin ekranı ya da oyunun Nino'nun
 * içinde gösterildiği görünüm ({@link GameScreen}). Masaüstü uygulaması bu ekranı ADB ile açabilir; o zaman ekran
 * gösterilmeden katman hazırlanır. Eski (8787) göndericilerin `params` (adres) ve `displayMode` ek bilgileri sayfaya ve
 * görünüm seçimine iletilir.
 */
public class MainActivity extends Activity implements SubtitlePage.Host, GameScreen.Owner, LinkHub.ModeListener {
    private static final long PERMISSION_POLL_MS = 2_000;
    /** Kaynak tuşundan sonra TV'nin kendi giriş menüsünü açması için beklenen süre. */
    private static final long INPUT_MENU_MS = 700;

    private final Handler main = new Handler(Looper.getMainLooper());
    private final Runnable permissionPoll = this::pollPermission;
    private Startup.Plan showing;
    private SubtitlePage page;
    private GameScreen game;

    @Override
    protected void onCreate(Bundle saved) {
        super.onCreate(saved);
        LinkHub.get(this).listenMode(this);
        route(getIntent());
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        route(intent);
    }

    private void route(Intent intent) {
        // Eski (8787) göndericiler uygulamayı adresleriyle ve görüntü modu seçimleriyle açar:
        //   am start -n com.ninotranslator.tv/.MainActivity --es params '{"server":"http://ip:8787"}' --es displayMode overlay
        LinkHub hub = LinkHub.get(this);
        hub.setLaunchParams(intent.getStringExtra("params"));
        String mode = intent.getStringExtra("displayMode");
        if (mode != null) hub.applyDisplayMode(mode);
        boolean fromLauncher = Intent.ACTION_MAIN.equals(intent.getAction());
        // Ekran zaten açıkken masaüstünden gelen açılış, gösterileni değiştirmez.
        if (showing != null && !fromLauncher) fromLauncher = showing != Startup.Plan.QUIET;
        Startup.Plan plan = Startup.decide(BuildConfig.CAN_OVERLAY, permitted(), chosenInApp(),
                DisplayChoice.wantsInApp(this), fromLauncher);
        if (plan == Startup.Plan.HOME || plan == Startup.Plan.QUIET) {
            if (!CaptionOverlay.alive()) CaptionOverlay.begin(this);
        }
        if (plan == Startup.Plan.QUIET) {
            if (showing == null) finish();
            return;
        }
        if (plan == showing) return;
        show(plan);
    }

    private void show(Startup.Plan plan) {
        main.removeCallbacks(permissionPoll);
        SubtitlePage oldPage = page;
        GameScreen oldGame = game;
        page = null;
        game = null;
        showing = plan;
        if (plan == Startup.Plan.IN_APP) {
            game = new GameScreen(this, this);
            setContentView(game.root);
            game.start();
            if (isResumedNow) game.resumed();
        } else {
            FrameLayout root = new FrameLayout(this);
            root.setBackgroundColor(Color.BLACK);
            page = new SubtitlePage(this, plan == Startup.Plan.HOME ? SubtitlePage.Mode.HOME : SubtitlePage.Mode.PERMISSION, this);
            root.addView(page.view);
            setContentView(root);
            page.open();
            if (plan == Startup.Plan.ASK_PERMISSION) {
                Metrics.get(this).errorOnce("tv.overlay.denied");
                main.postDelayed(permissionPoll, PERMISSION_POLL_MS);
            }
        }
        // Eski görünüm yenisi ekrana konduktan sonra bırakılır (arada siyah kare olmasın).
        if (oldPage != null) oldPage.close();
        if (oldGame != null) oldGame.stop();
    }

    private boolean permitted() { return BuildConfig.CAN_OVERLAY && Settings.canDrawOverlays(this); }

    private boolean chosenInApp() { return getSharedPreferences("screen", MODE_PRIVATE).getBoolean("inApp", false); }

    /** İzin ekranı açıkken izin verildi mi (masaüstü ADB ile ya da kullanıcı ayarlardan). */
    private void pollPermission() {
        if (showing != Startup.Plan.ASK_PERMISSION || isFinishing()) return;
        if (permitted()) {
            if (!CaptionOverlay.alive()) CaptionOverlay.begin(this);
            show(Startup.Plan.HOME);
            return;
        }
        main.postDelayed(permissionPoll, PERMISSION_POLL_MS);
    }

    // --- Sayfanın istekleri (ana ekran ve izin ekranı) ---

    /** TV'nin izin ekranı; o yoksa genel listesi, o da yoksa Nino'nun uygulama sayfası. Hiçbiri yoksa yolu söyler. */
    @Override
    public void grantPermission() {
        Uri self = Uri.fromParts("package", getPackageName(), null);
        if (open(new Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION).setData(self))) return;
        if (open(new Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION))) return;
        if (open(new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).setData(self))) return;
        Toast.makeText(this, R.string.permission_settings_missing, Toast.LENGTH_LONG).show();
    }

    /** Ekranı açabildiyse true. Bazı TV üreticileri ayar ekranlarını kaldırmış ya da kilitlemiştir. */
    private boolean open(Intent screen) {
        try {
            startActivity(screen);
            return true;
        } catch (ActivityNotFoundException | SecurityException refused) {
            return false;
        }
    }

    @Override
    public void continueWithout() {
        getSharedPreferences("screen", MODE_PRIVATE).edit().putBoolean("inApp", true).apply();
        show(Startup.Plan.IN_APP);
    }

    @Override
    public void leave() { finish(); }

    /** Sayfanın çizim süreci kapandı: aynı görünüm yeni bir sayfayla yeniden kurulur. */
    @Override
    public void pageLost() {
        if (isFinishing() || showing == null) return;
        Startup.Plan again = showing;
        showing = null;
        show(again);
    }

    // --- GameScreen.Owner ---

    @Override
    public void goOverlay(int message) {
        Toast.makeText(this, message, Toast.LENGTH_LONG).show();
        CaptionOverlay.begin(this);
        finish();
    }

    // --- Kumanda ---

    @Override
    public boolean dispatchKeyEvent(KeyEvent event) {
        int code = event.getKeyCode();
        // Kaynak ve HDMI tuşları TV'nin kendisine kalır (bazı TV'lerde WebView yutuyordu).
        if (code == KeyEvent.KEYCODE_TV_INPUT || (code >= KeyEvent.KEYCODE_TV_INPUT_HDMI_1 && code <= KeyEvent.KEYCODE_TV_INPUT_HDMI_4)) {
            if (code == KeyEvent.KEYCODE_TV_INPUT && event.getAction() == KeyEvent.ACTION_UP) {
                main.postDelayed(this::inputMenuDidNotOpen, INPUT_MENU_MS);
            }
            return false;
        }
        if (game != null && game.chooserKey(event)) return true;
        if (game != null && game.chooserOpen()) return super.dispatchKeyEvent(event);
        int pageCode = PageKeys.of(code);
        SubtitlePage target = game != null ? game.page : page;
        if (pageCode == 0 || target == null) return super.dispatchKeyEvent(event);
        if (event.getAction() == KeyEvent.ACTION_DOWN) target.key(pageCode);
        return true;
    }

    /**
     * Kaynak tuşuna basıldı ama TV'nin giriş menüsü Nino'nun önüne gelmedi (bazı TV'ler uygulama içindeyken açmıyor).
     * Nino çekilir ve TV'nin kendi canlı yayın ekranı açılır; orada kaynak tuşu her zaman çalışır.
     */
    private void inputMenuDidNotOpen() {
        boolean menuOpened = !hasWindowFocus();
        if (menuOpened || isFinishing()) return;
        if (game != null) game.release();
        Intent liveTv = new Intent(LIVE_TV_ACTION).setFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        if (open(liveTv)) Toast.makeText(this, R.string.press_input_again, Toast.LENGTH_LONG).show();
        finish();
    }

    /** Android TV'nin canlı yayın uygulamasını öne getiren eylem (TV ayarlarında "açılışta canlı yayın"). */
    private static final String LIVE_TV_ACTION = "com.android.tv.action.FORCE_LAUNCH_ON_BOOT";

    // --- Yaşam döngüsü ---

    private boolean isResumedNow;

    @Override
    protected void onResume() {
        super.onResume();
        Metrics.get(this).step("app.foreground");
        isResumedNow = true;
        if (game != null) game.resumed();
        // Ayarlardan dönüldü: izin verildiyse hemen ilerlenir.
        if (showing == Startup.Plan.ASK_PERMISSION) {
            main.removeCallbacks(permissionPoll);
            pollPermission();
        }
    }

    @Override
    protected void onPause() {
        super.onPause();
        isResumedNow = false;
        if (game != null) game.paused();
    }

    @Override
    protected void onStop() {
        super.onStop();
        Metrics.get(this).step("app.background");
        Metrics.get(this).flushSoon();
        if (game != null && !isFinishing()) game.stopped();
    }

    /**
     * Göndericide görüntü modu değişti. Uygulama içindeyken "katman" seçildiyse ve izin varsa katmana geçilir; izin
     * yoksa ya da Play derlemesindeyse ne yapılacağı söylenir. "Uygulama içinde" seçildiyse görünüm yeniden seçilir.
     */
    @Override
    public void displayModeChanged(String mode) {
        if (DisplayChoice.OVERLAY.equals(mode)) {
            if (game == null) return;
            if (permitted()) {
                game.release();
                goOverlay(R.string.to_overlay_chosen);
            } else {
                Toast.makeText(this, BuildConfig.CAN_OVERLAY ? R.string.permission_how : R.string.chooser_play_build,
                        Toast.LENGTH_LONG).show();
            }
            return;
        }
        if (showing != null && showing != Startup.Plan.IN_APP) route(new Intent(Intent.ACTION_MAIN));
    }

    @Override
    protected void onDestroy() {
        LinkHub.get(this).unlistenMode(this);
        main.removeCallbacksAndMessages(null);
        if (page != null) page.close();
        if (game != null) game.stop();
        page = null;
        game = null;
        super.onDestroy();
    }
}
