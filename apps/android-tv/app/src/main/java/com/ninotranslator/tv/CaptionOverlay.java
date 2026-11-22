// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.tv;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.content.pm.ServiceInfo;
import android.graphics.PixelFormat;
import android.os.Build;
import android.os.IBinder;
import android.provider.Settings;
import android.view.WindowManager;

/**
 * Katman: TV PS5'i kendi HDMI ekranında gösterir, altyazı onun üstündeki şeffaf ve odak almayan pencerede durur;
 * kumanda oyuna gider. Yalnız sideload derlemesinde vardır ve "diğer uygulamaların üzerinde göster" izni ister.
 * Ön plan servisidir: Nino ekranı kapansa da altyazı sürer.
 */
public class CaptionOverlay extends Service implements LinkHub.ModeListener {
    private static final String CHANNEL = "caption";
    private static final int NOTICE = 7;

    private static volatile boolean alive;

    private WindowManager windows;
    private SubtitlePage page;

    static boolean alive() { return alive; }

    static void begin(Context context) {
        Intent intent = new Intent(context, CaptionOverlay.class);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) context.startForegroundService(intent);
        else context.startService(intent);
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        foreground();
        if (page == null && !(Settings.canDrawOverlays(this) && attach())) {
            // İzin geri alınmış ya da pencere açılamadı: Nino'nun kendi ekranı açılır.
            stopSelf();
            Intent open = new Intent(this, MainActivity.class).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            try {
                startActivity(open);
            } catch (RuntimeException blocked) {
                // Arka plandan açılamadı; kullanıcı Nino'yu kendisi açar.
            }
            return START_NOT_STICKY;
        }
        alive = true;
        return START_NOT_STICKY;
    }

    private boolean attach() {
        windows = (WindowManager) getSystemService(WINDOW_SERVICE);
        SubtitlePage fresh = new SubtitlePage(this, SubtitlePage.Mode.OVERLAY, new SubtitlePage.Host() {
            @Override public void leave() { stopSelf(); }
            @Override public void pageLost() { reattach(); }
        });
        try {
            windows.addView(fresh.view, fullScreenLayer());
        } catch (RuntimeException refused) {
            fresh.close();
            return false;
        }
        page = fresh;
        page.open();
        LinkHub.get(this).listenMode(this);
        return true;
    }

    /**
     * Tam ekran, saydam, odak almayan pencere. Dokunmayı alttakine geçiren pencereleri (NOT_TOUCHABLE) Android 12+
     * yarı saydam çizer; TV'de dokunmatik ekran yok, odak almamak kumandanın oyuna gitmesine yeter.
     */
    private static WindowManager.LayoutParams fullScreenLayer() {
        WindowManager.LayoutParams p = new WindowManager.LayoutParams();
        p.width = WindowManager.LayoutParams.MATCH_PARENT;
        p.height = WindowManager.LayoutParams.MATCH_PARENT;
        p.format = PixelFormat.TRANSLUCENT;
        p.type = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
                ? WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
                : WindowManager.LayoutParams.TYPE_PHONE;
        p.flags = WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE | WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN
                | WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS;
        // Katman da TV'den oyun modunu ister (Android 11+).
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) p.preferMinimalPostProcessing = true;
        return p;
    }

    /** Sayfanın çizim süreci kapandı: pencere yeni bir sayfayla yeniden açılır. */
    private void reattach() {
        if (page != null) {
            try { windows.removeView(page.view); } catch (RuntimeException gone) { /* pencere yok */ }
            page = null;
        }
        if (!attach()) stopSelf();
    }

    private void foreground() {
        Notification.Builder builder;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationManager notices = (NotificationManager) getSystemService(NOTIFICATION_SERVICE);
            notices.createNotificationChannel(new NotificationChannel(CHANNEL, "Nino", NotificationManager.IMPORTANCE_LOW));
            builder = new Notification.Builder(this, CHANNEL);
        } else {
            builder = new Notification.Builder(this);
        }
        Notification notice = builder.setSmallIcon(R.mipmap.icon)
                .setContentTitle("Nino")
                .setContentText(getString(R.string.overlay_notice))
                .setOngoing(true)
                .build();
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(NOTICE, notice, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE);
        } else {
            startForeground(NOTICE, notice);
        }
    }

    /** Göndericide "uygulama içinde" seçildi: katman kapanır, oyun Nino'nun içinde açılır. */
    @Override
    public void displayModeChanged(String mode) {
        if (!DisplayChoice.IN_APP.equals(mode)) return;
        stopSelf();
        try {
            startActivity(new Intent(this, MainActivity.class).setAction(Intent.ACTION_MAIN)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
        } catch (RuntimeException blocked) {
            // Arka plandan açılamadı; Nino kumandadan açılınca uygulama içinde başlar.
        }
    }

    @Override
    public void onDestroy() {
        alive = false;
        LinkHub.get(this).unlistenMode(this);
        if (page != null) {
            try { windows.removeView(page.view); } catch (RuntimeException gone) { /* pencere yok */ }
            page.close();
            page = null;
        }
        super.onDestroy();
    }

    @Override
    public IBinder onBind(Intent intent) { return null; }
}
