// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.tv;

import android.view.KeyEvent;

/** Kumanda tuşlarını sayfanın anladığı kodlara çevirir (LG ve Samsung'un tarayıcı kodlarıyla aynı). */
final class PageKeys {
    static final int BACK = 4;
    static final int OK = 13;
    static final int RED = 403;
    static final int GREEN = 404;
    static final int YELLOW = 405;
    static final int BLUE = 406;

    private PageKeys() {}

    /** 0: sayfaya gitmez. */
    static int of(int keyCode) {
        if (keyCode >= KeyEvent.KEYCODE_0 && keyCode <= KeyEvent.KEYCODE_9) return 48 + keyCode - KeyEvent.KEYCODE_0;
        switch (keyCode) {
            case KeyEvent.KEYCODE_DPAD_LEFT: return 37;
            case KeyEvent.KEYCODE_DPAD_UP: return 38;
            case KeyEvent.KEYCODE_DPAD_RIGHT: return 39;
            case KeyEvent.KEYCODE_DPAD_DOWN: return 40;
            case KeyEvent.KEYCODE_DPAD_CENTER:
            case KeyEvent.KEYCODE_ENTER:
            case KeyEvent.KEYCODE_NUMPAD_ENTER: return OK;
            case KeyEvent.KEYCODE_BACK:
            case KeyEvent.KEYCODE_ESCAPE: return BACK;
            case KeyEvent.KEYCODE_PROG_RED: return RED;
            case KeyEvent.KEYCODE_PROG_GREEN: return GREEN;
            case KeyEvent.KEYCODE_PROG_YELLOW: return YELLOW;
            case KeyEvent.KEYCODE_PROG_BLUE: return BLUE;
            default: return 0;
        }
    }
}
