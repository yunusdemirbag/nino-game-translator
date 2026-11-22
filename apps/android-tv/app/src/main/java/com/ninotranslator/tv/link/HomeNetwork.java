// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.tv.link;

import java.net.Inet4Address;
import java.net.Inet6Address;
import java.net.InetAddress;

/** Bağlantının ev ağından gelip gelmediği: protokol yalnız özel ve yerel adresleri kabul eder. */
public final class HomeNetwork {
    private HomeNetwork() {}

    public static boolean allows(InetAddress address) {
        if (address == null) return false;
        byte[] b = address.getAddress();
        if (address instanceof Inet4Address) return privateV4(b[0] & 0xFF, b[1] & 0xFF);
        if (address instanceof Inet6Address) {
            // ::ffff:a.b.c.d biçimi IPv4 sayılır.
            boolean mapped = true;
            for (int i = 0; i < 10; i++) if (b[i] != 0) mapped = false;
            if (mapped && (b[10] & 0xFF) == 0xFF && (b[11] & 0xFF) == 0xFF) return privateV4(b[12] & 0xFF, b[13] & 0xFF);
            if (address.isLoopbackAddress()) return true;
            int top = b[0] & 0xFF;
            if (top == 0xFE && (b[1] & 0xC0) == 0x80) return true; // fe80::/10
            return (top & 0xFE) == 0xFC; // fc00::/7
        }
        return false;
    }

    private static boolean privateV4(int a, int b) {
        return a == 10 || a == 127 || (a == 192 && b == 168) || (a == 169 && b == 254) || (a == 172 && b >= 16 && b <= 31);
    }
}
