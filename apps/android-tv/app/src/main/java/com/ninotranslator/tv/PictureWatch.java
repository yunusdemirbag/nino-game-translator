// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.tv;

/**
 * Uygulamanın içinde açılan HDMI görüntüsünün gelip gelmediğini izler. Zaman dışarıdan verilir (bkz.
 * PictureWatchTest).
 *
 * - Giriş açıldıktan sonra {@link #NO_PICTURE_MS} boyunca hiç görüntü yoksa bu TV görüntüyü uygulamaya
 *   vermiyor sayılır: izin ve girişte cihaz varsa katmana geçilir, yoksa giriş seçici gösterilir.
 * - Görüntü bir kez geldiyse sonradan kesilmesi (PS5 uyudu) bu kararı değiştirmez.
 * - Giriş açıldıktan {@link #PUSHED_AWAY_MS} içinde uygulama arka plana itilirse TV kendi oynatıcısını öne
 *   çekmiştir; izin varsa katmana geçilir.
 * - Uygulama arka plandayken süre işlemez.
 */
final class PictureWatch {
    static final long NO_PICTURE_MS = 10_000;
    static final long PUSHED_AWAY_MS = 5_000;

    private long openedAt = -1;
    private long darkSince = -1;
    private boolean seen;

    /** Giriş (yeniden) açıldı. */
    void opened(long now) {
        openedAt = now;
        dark(now);
    }

    /** Görüntü yok (açılışta ya da TvView bildirdi). Saat yalnız ilk seferde başlar. */
    void dark(long now) {
        if (!seen && darkSince < 0) darkSince = now;
    }

    /** Görüntü geldi. */
    void seen() {
        seen = true;
        darkSince = -1;
    }

    boolean everSeen() { return seen; }

    /** Uygulama arka plana geçti ya da yeni giriş seçildi: görüntüsüz süre baştan sayılır. */
    void restart() { darkSince = -1; }

    /** Görüntü bu kadar süredir gelmiyor. */
    boolean tooLongDark(long now) {
        return !seen && darkSince >= 0 && now - darkSince >= NO_PICTURE_MS;
    }

    /** Katmana geçilmeli mi (görüntü gelmedi). */
    boolean moveToOverlay(long now, boolean deviceOnInput, boolean permitted) {
        return permitted && deviceOnInput && tooLongDark(now);
    }

    /** Uygulama arka plana itildi: TV HDMI'yı kendi oynatıcısında açtı mı. */
    boolean pushedAway(long now, boolean permitted) {
        return permitted && openedAt >= 0 && now - openedAt < PUSHED_AWAY_MS;
    }
}
