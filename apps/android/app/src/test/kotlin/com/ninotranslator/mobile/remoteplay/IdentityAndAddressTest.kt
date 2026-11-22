// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.remoteplay

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test
import java.nio.ByteBuffer

class IdentityAndAddressTest {

    @Test fun accountIdFromUserIdIsLittleEndian() {
        val id = PsnAccountId.fromUserId("1234567890123456789")!!
        assertEquals(8, id.size)
        var v = 0L
        for (i in 7 downTo 0) v = (v shl 8) or (id[i].toLong() and 0xff)
        assertEquals(1234567890123456789L, v)
        assertArrayEquals(byteArrayOf(1, 0, 0, 0, 0, 0, 0, 0), PsnAccountId.fromUserId("1"))
        // İşaretsiz 64 bitin üst yarısı.
        assertArrayEquals(ByteArray(8) { -1 }, PsnAccountId.fromUserId("18446744073709551615"))
        assertNull(PsnAccountId.fromUserId("18446744073709551616"))
        assertNull(PsnAccountId.fromUserId("-5"))
        assertNull(PsnAccountId.fromUserId("abc"))
    }

    @Test fun accountIdBase64RoundTrip() {
        val id = PsnAccountId.fromUserId("1234567890123456789")!!
        val b64 = PsnAccountId.toBase64(id)
        assertEquals(12, b64.length)
        assertArrayEquals(id, PsnAccountId.fromBase64(b64))
        assertNull(PsnAccountId.fromBase64("AAAA")) // 3 bayt
        assertNull(PsnAccountId.fromBase64("!!!"))
        assertNull(PsnAccountId.fromBase64(null))
    }

    @Test fun wakeCredentialFromRegistKey() {
        val key = ByteArray(16).also { "1a2b3c4d".toByteArray().copyInto(it) }
        assertEquals(0x1a2b3c4dL, WakeCredential.fromRegistKey(key))
        val full = "ffffffffffffffff".toByteArray()
        assertEquals(-1L, WakeCredential.fromRegistKey(full))
        assertNull(WakeCredential.fromRegistKey(ByteArray(16)))
        assertNull(WakeCredential.fromRegistKey("xyz".toByteArray()))
    }

    @Test fun loginPasscode() {
        assertEquals("1234", LoginPasscode.normalize(" 12 34 "))
        assertNull(LoginPasscode.normalize("123"))
        assertNull(LoginPasscode.normalize("12345"))
        assertNull(LoginPasscode.normalize("12a4"))
        assertNull(LoginPasscode.normalize("١٢٣٤"))
        assertNull(LoginPasscode.normalize(null))
    }

    @Test fun localAddressPicksWlanPrivate() {
        val list = listOf(
            NetInterface("lo", true, true, listOf("127.0.0.1")),
            NetInterface("rmnet0", true, false, listOf("10.20.30.40")),
            NetInterface("tun0", true, false, listOf("10.8.0.2")),
            NetInterface("eth0", true, false, listOf("172.20.1.5")),
            NetInterface("wlan0", true, false, listOf("8.8.8.8", "192.168.0.42")),
        )
        assertEquals("192.168.0.42", NetworkAddresses.pickLocalAddress(list))
        assertEquals("172.20.1.5", NetworkAddresses.pickLocalAddress(list.filter { it.name != "wlan0" }))
        assertNull(NetworkAddresses.pickLocalAddress(list.take(3)))
        assertNull(NetworkAddresses.pickLocalAddress(listOf(NetInterface("wlan0", false, false, listOf("192.168.0.2")))))
        assertNull(NetworkAddresses.pickLocalAddress(listOf(NetInterface("wlan0", true, false, listOf("172.32.0.1")))))
    }

    @Test fun subnetTargetsSkipSelf() {
        val t = NetworkAddresses.subnetTargets("192.168.0.42")
        assertEquals(253, t.size)
        assertEquals("192.168.0.1", t.first())
        assertEquals("192.168.0.254", t.last())
        assert("192.168.0.42" !in t)
        assertEquals(listOf("192.168.0.110"), NetworkAddresses.searchTargets("192.168.0.110", emptyList()))
        assertEquals(emptyList<String>(), NetworkAddresses.searchTargets(null, emptyList()))
    }

    @Test fun manualAddressCleanup() {
        assertEquals("192.168.1.20", NetworkAddresses.cleanManualAddress(" http://192.168.1.20:9295/x "))
        assertEquals("192.168.1.20", NetworkAddresses.cleanManualAddress("192,168,1,20"))
        assertEquals("10.0.0.5", NetworkAddresses.cleanManualAddress("10.0.0.5"))
        assertEquals("10.0.0.5", NetworkAddresses.cleanManualAddress("010.0.0.5"))
        assertNull(NetworkAddresses.cleanManualAddress("192.168.1"))
        assertNull(NetworkAddresses.cleanManualAddress("192.168.1.256"))
        assertNull(NetworkAddresses.cleanManualAddress("ps5.local"))
        assertNull(NetworkAddresses.cleanManualAddress(""))
    }

    @Test fun relocationPick() {
        fun ps(a: String, n: String) = FoundPs5(a, n, true, null, null)
        assertEquals("1", HostRelocation.pick(listOf(ps("1", "Salon"), ps("2", "Oda")), "Salon")?.address)
        assertNull(HostRelocation.pick(listOf(ps("1", "Salon"), ps("2", "Salon")), "Salon"))
        assertEquals("3", HostRelocation.pick(listOf(ps("3", "Başka")), "Salon")?.address)
        assertNull(HostRelocation.pick(listOf(ps("1", "A"), ps("2", "B")), "Salon"))
        assertNull(HostRelocation.pick(emptyList(), "Salon"))
    }

    @Test fun finderParse() {
        val r = Ps5Finder.parse(arrayOf("192.168.0.5", "", "1", "PPSA01", "Game", "192.168.0.6", "Oda", "0", "", ""))
        assertEquals(2, r.size)
        assertEquals(FoundPs5("192.168.0.5", "PS5", true, "PPSA01", "Game"), r[0])
        assertEquals(FoundPs5("192.168.0.6", "Oda", false, null, null), r[1])
    }

    @Test fun frameWrapSplitsPlanes() {
        val w = 4; val h = 2
        val buf = ByteBuffer.allocateDirect(w * h + 2 * (w / 2) * (h / 2))
        for (i in 0 until buf.capacity()) buf.put(i, i.toByte())
        val f = RemotePlayFrame.wrap(buf, w, h, w, 21, true, 7)
        assertNotNull(f)
        assertEquals(8, f!!.luma.remaining())
        assertEquals(4, f.chroma!!.remaining())
        assertEquals(8.toByte(), f.chroma!!.get(0))
        assertArrayEquals(ByteArray(8) { it.toByte() }, f.copyLuma())
        assertNull(RemotePlayFrame.wrap(buf, w, h, w, 21, false, 7)!!.chroma)
        assertNull(RemotePlayFrame.wrap(ByteBuffer.allocateDirect(3), w, h, w, 21, false, 7))
    }
}
