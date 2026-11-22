// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.tv;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import java.util.Arrays;

import org.junit.Test;

public class InputsTest {
    @Test
    public void idsSortByTheirLastNumber() {
        assertEquals(2, Inputs.trailingNumber("com.tv/.HdmiInput/HW2"));
        assertEquals(10, Inputs.trailingNumber("com.tv/.HdmiInput/HW10"));
        assertEquals(Long.MAX_VALUE, Inputs.trailingNumber("hdmi"));
        assertEquals(7, Inputs.trailingNumber("x7/"));
    }

    @Test
    public void playStationNames() {
        assertTrue(Inputs.looksLikePlayStation("PS5"));
        assertTrue(Inputs.looksLikePlayStation("SONY PS 5"));
        assertTrue(Inputs.looksLikePlayStation("PlayStation 5"));
        assertFalse(Inputs.looksLikePlayStation("Digiturk"));
        assertFalse(Inputs.looksLikePlayStation(null));
    }

    @Test
    public void consoleIsFoundByLabelThenDeviceThenSinglePluggedInput() {
        Inputs.Port soundbar = new Inputs.Port(1, "a", "Soundbar", "", true);
        Inputs.Port game = new Inputs.Port(2, "b", null, "Oyun PS5", true);
        Inputs.Port cec = new Inputs.Port(3, "c", "PlayStation 5", "", true);
        Inputs.Port empty = new Inputs.Port(4, "d", null, "", false);
        assertEquals(2, Inputs.console(Arrays.asList(soundbar, game, cec)).number);
        assertEquals(3, Inputs.console(Arrays.asList(soundbar, cec)).number);
        assertNull("iki bağlı giriş: tahmin yok", Inputs.console(Arrays.asList(soundbar, new Inputs.Port(2, "b", null, "", true))));
        assertEquals(1, Inputs.console(Arrays.asList(soundbar, empty)).number);
        assertNull(Inputs.console(Arrays.asList(empty)));
    }
}
