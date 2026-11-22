// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.tv;

import android.app.Activity;
import android.content.Context;
import android.graphics.Color;
import android.graphics.drawable.ColorDrawable;
import android.graphics.drawable.StateListDrawable;
import android.media.tv.TvContract;
import android.media.tv.TvInputManager;
import android.media.tv.TvView;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.provider.Settings;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.KeyEvent;
import android.view.View;
import android.view.WindowManager;
import android.widget.Button;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.TextView;

import java.util.List;

/**
 * Oyunun Nino'nun içinde gösterildiği görünüm: HDMI girişi tam ekran TvView'de, altyazı sayfası üstünde. Görüntü
 * gelmezse katmana geçmeyi önerir (izin varsa kendisi geçer) ya da giriş seçiciyi açar.
 */
final class GameScreen implements SubtitlePage.Host {
    /** Görünümü barındıran ekran. */
    interface Owner {
        /** Katmana geçilmeli; mesaj kullanıcıya gösterilir. */
        void goOverlay(int message);

        /** Sayfanın çizim süreci kapandı; görünüm yeniden kurulmalı. */
        void pageLost();

        void leave();
    }

    private static final long TICK_MS = 1_000;
    private static final int RETRIES = 5;

    private final Activity activity;
    private final Owner owner;
    private final Handler main = new Handler(Looper.getMainLooper());
    private final PictureWatch watch = new PictureWatch();
    final FrameLayout root;
    final SubtitlePage page;
    private TvView tv;
    private LinearLayout box;
    private TextView boxText;
    private LinearLayout buttons;
    private boolean chooserOpen;
    private boolean chooserDismissed;
    private String inputId;
    private int inputNumber;
    private int retries;
    private boolean front;
    private final Runnable tick = this::check;

    GameScreen(Activity activity, Owner owner) {
        this.activity = activity;
        this.owner = owner;
        root = new FrameLayout(activity);
        root.setBackgroundColor(Color.BLACK);
        if (activity.getSystemService(Context.TV_INPUT_SERVICE) != null) {
            tv = new TvView(activity);
            tv.setCallback(new Callback());
            // Bazı TV'lerde HDMI sesi uygulamada sıfırdan başlıyor; tam ses istenir.
            tv.setStreamVolume(1f);
            root.addView(tv);
        }
        page = new SubtitlePage(activity, SubtitlePage.Mode.IN_APP, this);
        root.addView(page.view);
        buildChooser();
    }

    void start() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            try {
                activity.getWindow().setPreferMinimalPostProcessing(true);
            } catch (RuntimeException unsupported) {
                // TV oyun modunu bilmiyor
            }
        }
        // Hangi girişin açılacağına sayfa karar verir (kayıtlı giriş ya da PS5 araması) ve showHdmi ile ister.
        page.open();
    }

    void stop() {
        main.removeCallbacksAndMessages(null);
        if (tv != null) tv.reset();
        page.close();
    }

    // --- Giriş ---

    /** Sayfa bir girişi istedi. 0: bilinmiyor; PS5'in girişi, o da yoksa HDMI 1 açılır. */
    @Override
    public void pickHdmi(int number) {
        if (number < 1) {
            Inputs.Port console = Inputs.console(Inputs.ports(activity));
            number = console == null ? 1 : console.number;
        }
        open(number);
    }

    /** Seçicide seçilen giriş sayfaya sayı tuşu olarak gider; sayfa kaydeder ve showHdmi ile ister. */
    private void choose(int number) {
        hideChooser();
        if (number >= 1 && number <= 9) page.key(48 + number); else open(number);
    }

    @Override
    public void leave() { owner.leave(); }

    @Override
    public void pageLost() { owner.pageLost(); }

    private void open(int number) {
        inputNumber = number;
        hideChooser();
        chooserDismissed = false;
        watch.restart();
        String id = Inputs.idOf(activity, number);
        if (tv == null || id == null) {
            page.hdmi(number, "sourceError", null);
            // TV girişleri uygulamalara hiç açmıyor: beklemenin anlamı yok, hemen söylenir.
            if (tv != null && Inputs.ports(activity).isEmpty()) {
                Metrics.get(activity).error("tv.hdmi.noaccess");
                showChooser(false);
            }
            return;
        }
        retries = 0;
        tune(id);
    }

    private void tune(String id) {
        inputId = id;
        page.hdmi(inputNumber, "loading", null);
        watch.opened(SystemClock.elapsedRealtime());
        screenOn(true);
        tv.setStreamVolume(1f);
        tv.tune(id, TvContract.buildChannelUriForPassthroughInput(id));
        schedule();
    }

    private void retry() {
        if (tv == null || inputId == null || retries >= RETRIES) return;
        retries++;
        String id = inputId;
        main.postDelayed(() -> { if (id.equals(inputId)) tune(id); }, 1_500L * retries);
    }

    private final class Callback extends TvView.TvInputCallback {
        @Override
        public void onVideoAvailable(String id) {
            retries = 0;
            watch.seen();
            hideChooser();
            screenOn(true);
            page.hdmi(inputNumber, "playing", null);
        }

        @Override
        public void onVideoUnavailable(String id, int reason) {
            // PS5 çözünürlük ya da HDR değiştirirken kısa süre "ayarlanıyor" olur; ekran o arada açık kalır.
            if (reason == TvInputManager.VIDEO_UNAVAILABLE_REASON_TUNING
                    || reason == TvInputManager.VIDEO_UNAVAILABLE_REASON_BUFFERING) {
                watch.dark(SystemClock.elapsedRealtime());
                return;
            }
            dark();
        }

        @Override
        public void onConnectionFailed(String id) { dark(); retry(); }

        @Override
        public void onDisconnected(String id) { dark(); retry(); }
    }

    private void dark() {
        screenOn(false);
        watch.dark(SystemClock.elapsedRealtime());
        page.hdmi(inputNumber, "inputError", null);
        schedule();
    }

    /** Ekran yalnız HDMI oynarken açık tutulur; görüntü yokken TV ekran koruyucusuna geçebilsin. */
    private void screenOn(boolean on) {
        if (on) activity.getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        else activity.getWindow().clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
    }

    private void schedule() {
        main.removeCallbacks(tick);
        if (front && !watch.everSeen()) main.postDelayed(tick, TICK_MS);
    }

    private void check() {
        if (!front || watch.everSeen() || tv == null) return;
        long now = SystemClock.elapsedRealtime();
        boolean device = Inputs.somethingOn(activity, inputId);
        if (watch.moveToOverlay(now, device, overlayPermitted())) {
            Metrics.get(activity).error("tv.hdmi.dark");
            release();
            owner.goOverlay(R.string.to_overlay_dark);
            return;
        }
        if (watch.tooLongDark(now) && !chooserOpen && !chooserDismissed) {
            Metrics.get(activity).error(device ? "tv.hdmi.dark" : "tv.hdmi.empty");
            showChooser(device);
        }
        schedule();
    }

    boolean overlayPermitted() {
        return BuildConfig.CAN_OVERLAY && Settings.canDrawOverlays(activity);
    }

    /** Girişi bırakır ki TV onu kendi ekranında açabilsin. */
    void release() {
        main.removeCallbacksAndMessages(null);
        if (tv != null) tv.reset();
        inputId = null;
    }

    // --- Yaşam döngüsü ---

    void resumed() {
        front = true;
        // Bazı TV'ler arka plandayken girişi bırakıyor; öne gelince yeniden açılır.
        if (tv != null && inputId != null) tune(inputId);
        page.visible(true);
    }

    void paused() {
        front = false;
        main.removeCallbacks(tick);
        watch.restart();
    }

    /** Arka plana itildi; TV kendi oynatıcısını öne çektiyse katmana geçilir. True: geçildi. */
    boolean stopped() {
        if (tv != null && inputId != null && watch.pushedAway(SystemClock.elapsedRealtime(), overlayPermitted())) {
            release();
            owner.goOverlay(R.string.to_overlay_dark);
            return true;
        }
        page.visible(false);
        return false;
    }

    // --- Giriş seçici ---

    private float px(float designPixels) {
        int w = activity.getResources().getDisplayMetrics().widthPixels;
        int h = activity.getResources().getDisplayMetrics().heightPixels;
        return designPixels * Math.max(w, h) / 1920f;
    }

    private void buildChooser() {
        box = new LinearLayout(activity);
        box.setOrientation(LinearLayout.VERTICAL);
        box.setVisibility(View.GONE);
        android.graphics.drawable.GradientDrawable shape = new android.graphics.drawable.GradientDrawable();
        shape.setColor(0xEB0A122A);
        shape.setCornerRadius(px(32));
        shape.setStroke(Math.max(1, Math.round(px(1))), 0x2EFFFFFF);
        box.setBackground(shape);
        int pad = Math.round(px(34));
        box.setPadding(pad, pad, pad, pad);
        boxText = new TextView(activity);
        boxText.setTextColor(0xFFF2F5FB);
        boxText.setTextSize(TypedValue.COMPLEX_UNIT_PX, px(28));
        boxText.setLineSpacing(0, 1.3f);
        box.addView(boxText);
        buttons = new LinearLayout(activity);
        buttons.setOrientation(LinearLayout.HORIZONTAL);
        LinearLayout.LayoutParams row = new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT);
        row.topMargin = pad;
        box.addView(buttons, row);
        FrameLayout.LayoutParams place = new FrameLayout.LayoutParams(
                Math.round(px(1400)), FrameLayout.LayoutParams.WRAP_CONTENT, Gravity.TOP | Gravity.CENTER_HORIZONTAL);
        place.topMargin = Math.round(px(60));
        root.addView(box, place);
    }

    /** Görüntü gelmiyor: neden, HDMI girişleri ve ne yapılabileceği. */
    private void showChooser(boolean deviceOnInput) {
        chooserOpen = true;
        buttons.removeAllViews();
        List<Inputs.Port> ports = Inputs.ports(activity);
        StringBuilder text = new StringBuilder();
        Button focus = null;
        if (ports.isEmpty()) {
            text.append(activity.getString(R.string.chooser_no_access));
        } else {
            if (inputNumber > 0) {
                text.append(activity.getString(deviceOnInput ? R.string.chooser_dark : R.string.chooser_empty, inputNumber)).append(' ');
            }
            text.append(activity.getString(R.string.chooser_pick)).append("\n\n").append(activity.getString(R.string.chooser_still_dark));
            for (Inputs.Port port : ports) {
                String label = "HDMI " + port.number + (port.device != null ? " · " + port.device
                        : port.plugged ? " · " + activity.getString(R.string.chooser_plugged) : "");
                Button b = button(label, v -> choose(port.number));
                if (Inputs.looksLikePlayStation(port.device) || (focus == null && port.plugged && port.number != inputNumber)) focus = b;
            }
        }
        if (overlayPermitted()) {
            text.append("\n\n").append(activity.getString(R.string.chooser_overlay));
            button(activity.getString(R.string.chooser_overlay_button), v -> {
                release();
                owner.goOverlay(R.string.to_overlay_chosen);
            });
        } else if (BuildConfig.CAN_OVERLAY) {
            text.append("\n\n").append(activity.getString(R.string.permission_how));
        } else {
            text.append("\n\n").append(activity.getString(R.string.chooser_play_build));
        }
        Button close = button(activity.getString(R.string.chooser_close), v -> {
            chooserDismissed = true;
            hideChooser();
        });
        boxText.setText(text);
        box.setVisibility(View.VISIBLE);
        (focus != null ? focus : buttons.getChildCount() > 0 ? (Button) buttons.getChildAt(0) : close).requestFocus();
    }

    private Button button(String label, View.OnClickListener click) {
        Button b = new Button(activity);
        b.setText(label);
        b.setAllCaps(false);
        b.setTextColor(Color.WHITE);
        b.setTextSize(TypedValue.COMPLEX_UNIT_PX, px(26));
        StateListDrawable look = new StateListDrawable();
        look.addState(new int[] {android.R.attr.state_focused}, new ColorDrawable(0xFF2D8CFF));
        look.addState(new int[] {}, new ColorDrawable(0x33FFFFFF));
        b.setBackground(look);
        int pad = Math.round(px(16));
        b.setPadding(2 * pad, pad, 2 * pad, pad);
        b.setFocusable(true);
        b.setOnClickListener(click);
        LinearLayout.LayoutParams gap = new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT);
        gap.rightMargin = pad;
        buttons.addView(b, gap);
        return b;
    }

    private void hideChooser() {
        if (!chooserOpen) return;
        chooserOpen = false;
        box.setVisibility(View.GONE);
        buttons.removeAllViews();
    }

    /** Seçici açıkken Geri kapatır, 1–4 girişi seçer; oklar ve Tamam düğmelere kendiliğinden gider. */
    boolean chooserKey(KeyEvent event) {
        if (!chooserOpen) return false;
        int code = event.getKeyCode();
        boolean digit = code >= KeyEvent.KEYCODE_1 && code <= KeyEvent.KEYCODE_4;
        if (code != KeyEvent.KEYCODE_BACK && !digit) return false;
        if (event.getAction() == KeyEvent.ACTION_DOWN) {
            if (digit) {
                choose(code - KeyEvent.KEYCODE_0);
            } else {
                chooserDismissed = true;
                hideChooser();
            }
        }
        return true;
    }

    boolean chooserOpen() { return chooserOpen; }
}
