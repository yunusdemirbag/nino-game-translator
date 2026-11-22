// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.tv.install.adb

import com.ninotranslator.mobile.tv.install.LocalIoException
import java.io.EOFException
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream

/**
 * ADB/SDB çerçevesi (AOSP protocol.txt): 24 baytlık küçük-endian başlık (komut, arg0, arg1, veri uzunluğu, veri bayt
 * toplamı, komut XOR 0xFFFFFFFF) ve veri.
 */
class AdbMessage(val command: Int, val arg0: Int, val arg1: Int, val data: ByteArray = EMPTY) {
    val name: String get() = commandName(command)

    fun encode(): ByteArray {
        val out = ByteArray(HEADER + data.size)
        putLe(out, 0, command)
        putLe(out, 4, arg0)
        putLe(out, 8, arg1)
        putLe(out, 12, data.size)
        putLe(out, 16, checksum(data))
        putLe(out, 20, command xor -1)
        data.copyInto(out, HEADER)
        return out
    }

    override fun toString() = "$name($arg0, $arg1, ${data.size} bayt)"

    companion object {
        const val HEADER = 24
        val EMPTY = ByteArray(0)

        val CNXN = cmd("CNXN")
        val AUTH = cmd("AUTH")
        val OPEN = cmd("OPEN")
        val OKAY = cmd("OKAY")
        val CLSE = cmd("CLSE")
        val WRTE = cmd("WRTE")
        val STLS = cmd("STLS")

        const val AUTH_TOKEN = 1
        const val AUTH_SIGNATURE = 2
        const val AUTH_RSAPUBLICKEY = 3

        fun cmd(s: String): Int = (s[0].code) or (s[1].code shl 8) or (s[2].code shl 16) or (s[3].code shl 24)

        fun commandName(c: Int): String {
            val chars = CharArray(4) { ((c ushr (8 * it)) and 0xFF).toChar() }
            return if (chars.all { it in 'A'..'Z' }) String(chars) else "0x" + Integer.toHexString(c)
        }

        fun checksum(data: ByteArray): Int { var s = 0; for (b in data) s += b.toInt() and 0xFF; return s }

        /**
         * Bir çerçeve okur. Sihirli sayı ve uzunluk ([maxData]) her zaman denetlenir; [verifyChecksum] (sdb) açıksa bayt
         * toplamı da. Yeni adbd'ler toplamı 0 gönderir.
         */
        fun read(input: InputStream, maxData: Int, verifyChecksum: Boolean): AdbMessage {
            val h = readFully(input, HEADER)
            val command = getLe(h, 0)
            val length = getLe(h, 12)
            if (getLe(h, 20) != (command xor -1)) throw LocalIoException("bozuk çerçeve: sihirli sayı tutmuyor")
            if (length < 0 || length > maxData) throw LocalIoException("bozuk çerçeve: uzunluk $length")
            val data = if (length == 0) EMPTY else readFully(input, length)
            if (verifyChecksum && checksum(data) != getLe(h, 16)) throw LocalIoException("bozuk çerçeve: bayt toplamı tutmuyor")
            return AdbMessage(command, getLe(h, 4), getLe(h, 8), data)
        }

        fun write(output: OutputStream, m: AdbMessage) { output.write(m.encode()); output.flush() }

        fun readFully(input: InputStream, n: Int): ByteArray {
            val b = ByteArray(n)
            var off = 0
            while (off < n) {
                val r = input.read(b, off, n - off)
                if (r < 0) throw LocalIoException("bağlantı kapandı")
                off += r
            }
            return b
        }

        fun putLe(b: ByteArray, off: Int, v: Int) {
            b[off] = v.toByte(); b[off + 1] = (v ushr 8).toByte(); b[off + 2] = (v ushr 16).toByte(); b[off + 3] = (v ushr 24).toByte()
        }

        fun getLe(b: ByteArray, off: Int): Int =
            (b[off].toInt() and 0xFF) or ((b[off + 1].toInt() and 0xFF) shl 8) or
                ((b[off + 2].toInt() and 0xFF) shl 16) or ((b[off + 3].toInt() and 0xFF) shl 24)
    }
}
