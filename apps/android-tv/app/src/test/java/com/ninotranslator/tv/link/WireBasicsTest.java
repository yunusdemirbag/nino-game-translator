// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.tv.link;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;
import static org.junit.Assert.fail;

import java.net.InetAddress;
import java.util.Map;

import org.junit.Test;

/** JSON, mesaj biçimi, ekran durumu ve adres kuralı. */
public class WireBasicsTest {
    @Test
    public void jsonReadsWhatItWrites() {
        Object parsed = Json.parse("{\"a\":[1,2.5,true,null],\"b\":\"ş\\n\\u00e7\\\"\"}");
        assertEquals("{\"a\":[1,2.5,true,null],\"b\":\"ş\\nç\\\"\"}", Json.write(parsed));
    }

    @Test
    public void jsonRejectsBrokenText() {
        for (String bad : new String[] {"", "{", "{\"a\":}", "[1,]", "{\"a\":1} x", "\"ab", "tru", "{a:1}"}) {
            try {
                Json.parse(bad);
                fail("kabul edilmemeliydi: " + bad);
            } catch (IllegalArgumentException expected) {
                // doğru
            }
        }
    }

    @Test
    public void lineSeparatorsAreEscapedForThePage() {
        assertEquals("\"a\\u2028b\"", Json.write("a b"));
    }

    @Test
    public void showNeedsIdAndText() throws Exception {
        Wire.Subtitle s = Wire.Subtitle.from(Wire.decode(
                "{\"app\":\"nino\",\"type\":\"show\",\"id\":42,\"text\":\"Buraya gel.\",\"source\":\"Come here.\",\"position\":\"top\",\"durationMs\":1500,\"extra\":1}"));
        assertEquals(42, s.id);
        assertEquals("Buraya gel.", s.text);
        assertEquals("Come here.", s.source);
        assertTrue(s.top);
        assertEquals(1500, s.durationMs);
        try {
            Wire.Subtitle.from(Wire.decode("{\"app\":\"nino\",\"type\":\"show\",\"text\":\"x\"}"));
            fail();
        } catch (Wire.Malformed expected) {
            // id yok
        }
    }

    @Test
    public void positionDefaultsToBottomAndNegativeDurationToZero() throws Exception {
        Wire.Subtitle s = Wire.Subtitle.from(Wire.decode(
                "{\"app\":\"nino\",\"type\":\"show\",\"id\":1,\"text\":\"x\",\"position\":\"middle\",\"durationMs\":-5}"));
        assertFalse(s.top);
        assertEquals(0, s.durationMs);
    }

    @Test
    public void extraShowFieldsReachThePage() throws Exception {
        Wire.Subtitle s = Wire.Subtitle.from(Wire.decode(
                "{\"app\":\"nino\",\"type\":\"show\",\"id\":2,\"text\":\"x\",\"paragraphs\":true,\"box\":{\"top\":0.8}}"));
        assertEquals("{\"paragraphs\":true,\"box\":{\"top\":0.8},\"type\":\"show\",\"id\":2,\"text\":\"x\",\"position\":\"bottom\",\"durationMs\":0}",
                Json.write(s.toMap()));
    }

    @Test
    public void buttonIconsPassThroughUntouched() throws Exception {
        // Tuş simgeleri (⟦T1⟧ + icons) sayfada çizilir; uygulama alanı olduğu gibi iletmeli.
        String icons = "[{\"id\":\"T1\",\"name\":\"cross\",\"png\":\"iVBORw0KGgo=\"}]";
        Wire.Subtitle s = Wire.Subtitle.from(Wire.decode(
                "{\"app\":\"nino\",\"type\":\"show\",\"id\":3,\"text\":\"Bas ⟦T1⟧\",\"icons\":" + icons + "}"));
        assertEquals(icons, Json.write(((java.util.Map<?, ?>) Json.parse(Json.write(s.toMap()))).get("icons")));
        Wire.Message screen = Wire.decode("{\"app\":\"nino\",\"type\":\"screen\",\"items\":[{\"text\":\"⟦T1⟧ Aç\",\"icons\":" + icons + "}]}");
        assertEquals("{\"type\":\"screen\",\"items\":[{\"text\":\"⟦T1⟧ Aç\",\"icons\":" + icons + "}]}", Json.write(screen.fields()));
    }

    @Test(expected = Wire.Malformed.class)
    public void otherAppsAreRefused() throws Exception {
        Wire.decode("{\"app\":\"other\",\"type\":\"show\"}");
    }

    @Test
    public void infoListsVersions() {
        @SuppressWarnings("unchecked")
        Map<String, Object> info = (Map<String, Object>) Json.parse(Wire.info("Salon TV", "abc"));
        assertEquals("info", info.get("type"));
        assertEquals(1L, info.get("version"));
        assertEquals("Salon TV", info.get("name"));
        assertEquals("[1]", Json.write(info.get("versions")));
    }

    @Test
    public void clearWithIdOnlyRemovesThatSubtitle() {
        Screen screen = new Screen();
        assertTrue(screen.put(new Wire.Subtitle(5, "a", null, false, 0)));
        assertFalse(screen.put(new Wire.Subtitle(5, "a", null, false, 0)));
        assertTrue(screen.put(new Wire.Subtitle(6, "b", null, false, 0)));
        assertFalse(screen.remove(5L));
        assertEquals(6, screen.shown().id);
        assertTrue(screen.remove(null));
        assertNull(screen.shown());
        assertFalse(screen.remove(null));
    }

    @Test
    public void onlyHomeAddressesAreAllowed() throws Exception {
        for (String ok : new String[] {"10.1.2.3", "127.0.0.1", "192.168.0.110", "169.254.9.9", "172.16.0.1", "172.31.255.1",
                "::1", "fe80::1", "fd12::3", "::ffff:192.168.1.2"}) {
            assertTrue(ok, HomeNetwork.allows(InetAddress.getByName(ok)));
        }
        for (String no : new String[] {"8.8.8.8", "172.32.0.1", "192.169.0.1", "2001:db8::1", "::ffff:8.8.8.8"}) {
            assertFalse(no, HomeNetwork.allows(InetAddress.getByName(no)));
        }
    }

    @Test
    public void acceptKeyMatchesTheStandardExample() {
        // RFC 6455, bölüm 1.3'teki örnek.
        assertEquals("s3pPLMBiTxaQ9kYGzzhZRbK+xOo=", Frames.acceptKey("dGhlIHNhbXBsZSBub25jZQ=="));
    }

    @Test
    public void base64MatchesTheJavaEncoder() {
        java.util.Random random = new java.util.Random(3);
        for (int size = 0; size < 40; size++) {
            byte[] data = new byte[size];
            random.nextBytes(data);
            assertEquals(java.util.Base64.getEncoder().encodeToString(data), Frames.Base64Text.encode(data));
        }
    }
}
