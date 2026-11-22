// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.tv.link;

/** TV'de şu an duran altyazı. `show` eskisinin yerine geçer; id'li `clear` yalnız o altyazıyı kaldırır. */
public final class Screen {
    private Wire.Subtitle shown;

    public Wire.Subtitle shown() { return shown; }

    /** Değiştiyse true. */
    public boolean put(Wire.Subtitle subtitle) {
        if (subtitle.equals(shown)) return false;
        shown = subtitle;
        return true;
    }

    /** id null ise her durumda temizler. Bir şey kalktıysa true. */
    public boolean remove(Long id) {
        if (shown == null) return false;
        if (id != null && id != shown.id) return false;
        shown = null;
        return true;
    }
}
