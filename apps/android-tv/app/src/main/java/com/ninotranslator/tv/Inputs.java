// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.tv;

import android.content.Context;
import android.media.tv.TvInputInfo;
import android.media.tv.TvInputManager;

import java.util.ArrayList;
import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * TV'nin HDMI girişleri. Numara (1, 2, …) girişin sıralı listedeki yeridir. HDMI-CEC ile görünen cihazlar bazı
 * TV'lerde girişin "alt girişi" olarak ayrıca listelenir; onlar numaraya katılmaz, yalnız cihaz adı için okunur.
 */
final class Inputs {
    /** Bir HDMI girişi. */
    static final class Port {
        final int number;
        final String id;
        /** CEC'in bildirdiği cihaz adı (ör. "PS5"), yoksa null. */
        final String device;
        /** Kullanıcının TV'de girişe verdiği ad, yoksa "". */
        final String label;
        final boolean plugged;

        Port(int number, String id, String device, String label, boolean plugged) {
            this.number = number;
            this.id = id;
            this.device = device;
            this.label = label;
            this.plugged = plugged;
        }
    }

    private Inputs() {}

    static List<Port> ports(Context context) {
        List<Port> ports = new ArrayList<>();
        TvInputManager tv = (TvInputManager) context.getSystemService(Context.TV_INPUT_SERVICE);
        if (tv == null) return ports;
        List<TvInputInfo> all;
        try {
            all = tv.getTvInputList();
        } catch (RuntimeException unavailable) {
            return ports;
        }
        List<TvInputInfo> hdmi = new ArrayList<>();
        for (TvInputInfo info : all) {
            if (info.getType() == TvInputInfo.TYPE_HDMI && info.isPassthroughInput() && info.getParentId() == null) hdmi.add(info);
        }
        hdmi.sort((a, b) -> {
            int byNumber = Long.compare(trailingNumber(a.getId()), trailingNumber(b.getId()));
            return byNumber != 0 ? byNumber : a.getId().compareTo(b.getId());
        });
        for (int i = 0; i < hdmi.size(); i++) {
            TvInputInfo info = hdmi.get(i);
            ports.add(new Port(i + 1, info.getId(), childName(context, all, info.getId()), customLabel(context, info),
                    stateOf(tv, info.getId()) == TvInputManager.INPUT_STATE_CONNECTED));
        }
        return ports;
    }

    static String idOf(Context context, int number) {
        for (Port port : ports(context)) if (port.number == number) return port.id;
        return null;
    }

    /** Girişte bir cihaz var mı; TV söylemiyorsa var sayılır. */
    static boolean somethingOn(Context context, String id) {
        TvInputManager tv = (TvInputManager) context.getSystemService(Context.TV_INPUT_SERVICE);
        if (tv == null || id == null) return true;
        return stateOf(tv, id) != TvInputManager.INPUT_STATE_DISCONNECTED;
    }

    /**
     * PS5'in girişi: önce kullanıcının verdiği ad, sonra CEC cihaz adı, sonra tek bağlı giriş. Bulunamazsa null
     * (tahmin edilmez).
     */
    static Port console(List<Port> ports) {
        for (Port port : ports) if (looksLikePlayStation(port.label)) return port;
        for (Port port : ports) if (looksLikePlayStation(port.device)) return port;
        Port only = null;
        for (Port port : ports) {
            if (!port.plugged) continue;
            if (only != null) return null;
            only = port;
        }
        return only;
    }

    private static final Pattern PLAYSTATION = Pattern.compile("ps\\s*5|play\\s*station", Pattern.CASE_INSENSITIVE);
    private static final Pattern TRAILING_DIGITS = Pattern.compile("(\\d{1,18})\\D*$");

    static boolean looksLikePlayStation(String name) {
        return name != null && PLAYSTATION.matcher(name).find();
    }

    /** "…/HW15" → 15; sayı yoksa en sona. */
    static long trailingNumber(String id) {
        Matcher found = TRAILING_DIGITS.matcher(id);
        return found.find() ? Long.parseLong(found.group(1)) : Long.MAX_VALUE;
    }

    private static int stateOf(TvInputManager tv, String id) {
        try {
            return tv.getInputState(id);
        } catch (RuntimeException unknown) {
            return TvInputManager.INPUT_STATE_CONNECTED_STANDBY;
        }
    }

    private static String childName(Context context, List<TvInputInfo> all, String parent) {
        for (TvInputInfo info : all) {
            if (!parent.equals(info.getParentId())) continue;
            try {
                CharSequence name = info.loadLabel(context);
                if (name != null && name.toString().trim().length() > 0) return name.toString().trim();
            } catch (RuntimeException ignored) {
                // ad okunamadı
            }
        }
        return null;
    }

    private static String customLabel(Context context, TvInputInfo info) {
        try {
            CharSequence label = info.loadCustomLabel(context);
            return label == null ? "" : label.toString().trim();
        } catch (RuntimeException unsupported) {
            return "";
        }
    }
}
