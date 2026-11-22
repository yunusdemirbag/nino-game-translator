// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.tv;

import android.content.Context;
import android.content.SharedPreferences;

import java.util.Locale;

/**
 * Göndericideki "görüntü modu" ayarı (`style` mesajının `displayMode` alanı): oyun Nino'nun içinde mi gösterilir
 * ("inApp"), yoksa TV kendi HDMI ekranında gösterir ve altyazı üstüne mi çizilir ("overlay"). Gönderici her
 * bağlanışta ayarı yeniden yollar ve varsayılanı "inApp"tir. Bu yüzden:
 * - kayıt yokken gelen "inApp" değişiklik sayılmaz (yoksa katman her ilk bağlantıda kapanırdı);
 * - yalnız gerçek değişiklik görünümü değiştirir ve kaydedilir;
 * - "uygulama içinde" ancak kullanıcı göndericide katmandan uygulama içine geçtiyse (kayıtlı "inApp") istenmiş sayılır.
 */
final class DisplayChoice {
    static final String IN_APP = "inApp";
    static final String OVERLAY = "overlay";

    private DisplayChoice() {}

    /** Bilinen bir değerse onu ("in-app", "IN_APP" gibi yazımlar da), değilse null. */
    static String normalize(String value) {
        if (value == null) return null;
        String plain = value.toLowerCase(Locale.ROOT).replaceAll("[^a-z]", "");
        if (plain.equals("inapp")) return IN_APP;
        if (plain.equals("overlay")) return OVERLAY;
        return null;
    }

    /** Gelen değer kayıtlıdan farklı ve geçerli mi. Kayıt yoksa "inApp" sayılır (göndericinin varsayılanı). */
    static boolean differs(String stored, String incoming) {
        String next = normalize(incoming);
        String current = normalize(stored);
        return next != null && !next.equals(current == null ? IN_APP : current);
    }

    private static SharedPreferences prefs(Context context) {
        return context.getSharedPreferences("screen", Context.MODE_PRIVATE);
    }

    static String stored(Context context) { return normalize(prefs(context).getString("displayMode", null)); }

    static boolean wantsInApp(Context context) { return IN_APP.equals(stored(context)); }

    /** Değiştiyse kaydeder ve true döner. */
    static boolean store(Context context, String incoming) {
        if (!differs(stored(context), incoming)) return false;
        prefs(context).edit().putString("displayMode", normalize(incoming)).apply();
        return true;
    }
}
