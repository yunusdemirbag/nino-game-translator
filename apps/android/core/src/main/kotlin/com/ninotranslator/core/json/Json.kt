// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.json

/**
 * Küçük, bağımlılıksız JSON okuyucu ve yazıcı.
 * Nesne → LinkedHashMap<String, Any?>, dizi → List<Any?>, sayı → Long ya da Double, true/false, null, String.
 */
object Json {
    class ParseException(message: String) : Exception(message)

    fun parse(text: String): Any? {
        val p = Parser(text)
        p.skipSpace()
        val value = p.value()
        p.skipSpace()
        if (!p.atEnd()) throw ParseException("fazla veri: ${p.pos}")
        return value
    }

    fun parseObject(text: String): Map<String, Any?> =
        parse(text) as? Map<String, Any?> ?: throw ParseException("nesne bekleniyordu")

    fun write(value: Any?, pretty: Boolean = false): String = StringBuilder().also { writeTo(it, value, pretty, 0) }.toString()

    fun quote(s: String): String = StringBuilder().also { writeString(it, s) }.toString()

    private fun writeTo(out: StringBuilder, value: Any?, pretty: Boolean, depth: Int) {
        when (value) {
            null -> out.append("null")
            is String -> writeString(out, value)
            is Boolean -> out.append(value)
            is Int, is Long, is Short, is Byte -> out.append(value.toString())
            is Float -> writeDouble(out, value.toDouble())
            is Double -> writeDouble(out, value)
            is Number -> out.append(value.toString())
            is Map<*, *> -> {
                out.append('{')
                var first = true
                for ((k, v) in value) {
                    if (!first) out.append(',')
                    first = false
                    newline(out, pretty, depth + 1)
                    writeString(out, k.toString())
                    out.append(if (pretty) ": " else ":")
                    writeTo(out, v, pretty, depth + 1)
                }
                if (!first) newline(out, pretty, depth)
                out.append('}')
            }
            is Iterable<*> -> {
                out.append('[')
                var first = true
                for (v in value) {
                    if (!first) out.append(',')
                    first = false
                    newline(out, pretty, depth + 1)
                    writeTo(out, v, pretty, depth + 1)
                }
                if (!first) newline(out, pretty, depth)
                out.append(']')
            }
            is Array<*> -> writeTo(out, value.asList(), pretty, depth)
            else -> writeString(out, value.toString())
        }
    }

    private fun writeDouble(out: StringBuilder, d: Double) {
        if (d.isNaN() || d.isInfinite()) out.append("null")
        else if (d == Math.rint(d) && kotlin.math.abs(d) < 1e15) out.append(d.toLong()) else out.append(d)
    }

    private fun newline(out: StringBuilder, pretty: Boolean, depth: Int) {
        if (!pretty) return
        out.append('\n')
        repeat(depth) { out.append("  ") }
    }

    private fun writeString(out: StringBuilder, s: String) {
        out.append('"')
        for (c in s) {
            when (c) {
                '"' -> out.append("\\\"")
                '\\' -> out.append("\\\\")
                '\n' -> out.append("\\n")
                '\r' -> out.append("\\r")
                '\t' -> out.append("\\t")
                '\b' -> out.append("\\b")
                '\u000C' -> out.append("\\f")
                else -> if (c < ' ' || c == ' ' || c == ' ') out.append(String.format("\\u%04x", c.code)) else out.append(c)
            }
        }
        out.append('"')
    }

    private class Parser(val s: String) {
        var pos = 0
        fun atEnd() = pos >= s.length
        fun skipSpace() { while (pos < s.length && s[pos].let { it == ' ' || it == '\n' || it == '\r' || it == '\t' || it == '\uFEFF' }) pos++ }
        fun fail(msg: String): Nothing = throw ParseException("$msg (konum $pos)")

        fun value(): Any? {
            if (atEnd()) fail("beklenmeyen son")
            return when (val c = s[pos]) {
                '{' -> obj()
                '[' -> arr()
                '"' -> str()
                't' -> word("true", true)
                'f' -> word("false", false)
                'n' -> word("null", null)
                else -> if (c == '-' || c.isDigit()) num() else fail("beklenmeyen karakter '$c'")
            }
        }

        fun word(w: String, v: Any?): Any? {
            if (!s.startsWith(w, pos)) fail("geçersiz değer")
            pos += w.length
            return v
        }

        fun obj(): Map<String, Any?> {
            pos++
            val m = LinkedHashMap<String, Any?>()
            skipSpace()
            if (pos < s.length && s[pos] == '}') { pos++; return m }
            while (true) {
                skipSpace()
                if (atEnd() || s[pos] != '"') fail("anahtar bekleniyordu")
                val k = str()
                skipSpace()
                if (atEnd() || s[pos] != ':') fail("':' bekleniyordu")
                pos++
                skipSpace()
                m[k] = value()
                skipSpace()
                if (atEnd()) fail("'}' bekleniyordu")
                when (s[pos]) {
                    ',' -> pos++
                    '}' -> { pos++; return m }
                    else -> fail("',' ya da '}' bekleniyordu")
                }
            }
        }

        fun arr(): List<Any?> {
            pos++
            val l = ArrayList<Any?>()
            skipSpace()
            if (pos < s.length && s[pos] == ']') { pos++; return l }
            while (true) {
                skipSpace()
                l += value()
                skipSpace()
                if (atEnd()) fail("']' bekleniyordu")
                when (s[pos]) {
                    ',' -> pos++
                    ']' -> { pos++; return l }
                    else -> fail("',' ya da ']' bekleniyordu")
                }
            }
        }

        fun str(): String {
            pos++
            val b = StringBuilder()
            while (true) {
                if (atEnd()) fail("kapanmayan yazı")
                val c = s[pos++]
                when (c) {
                    '"' -> return b.toString()
                    '\\' -> {
                        if (atEnd()) fail("yarım kaçış")
                        when (val e = s[pos++]) {
                            '"' -> b.append('"'); '\\' -> b.append('\\'); '/' -> b.append('/')
                            'b' -> b.append('\b'); 'f' -> b.append('\u000C'); 'n' -> b.append('\n')
                            'r' -> b.append('\r'); 't' -> b.append('\t')
                            'u' -> {
                                if (pos + 4 > s.length) fail("yarım \\u")
                                b.append(s.substring(pos, pos + 4).toIntOrNull(16)?.toChar() ?: fail("geçersiz \\u"))
                                pos += 4
                            }
                            else -> fail("geçersiz kaçış '$e'")
                        }
                    }
                    else -> b.append(c)
                }
            }
        }

        fun num(): Any {
            val start = pos
            if (s[pos] == '-') pos++
            while (pos < s.length && s[pos].isDigit()) pos++
            var real = false
            if (pos < s.length && s[pos] == '.') { real = true; pos++; while (pos < s.length && s[pos].isDigit()) pos++ }
            if (pos < s.length && (s[pos] == 'e' || s[pos] == 'E')) {
                real = true; pos++
                if (pos < s.length && (s[pos] == '+' || s[pos] == '-')) pos++
                while (pos < s.length && s[pos].isDigit()) pos++
            }
            val t = s.substring(start, pos)
            if (t == "-" || t.isEmpty()) fail("geçersiz sayı")
            return if (real) t.toDouble() else t.toLongOrNull() ?: t.toDouble()
        }
    }
}

// Okuma kolaylıkları.
fun Map<String, Any?>.str(key: String): String? = this[key] as? String
fun Map<String, Any?>.int(key: String): Int? = (this[key] as? Number)?.toInt()
fun Map<String, Any?>.long(key: String): Long? = (this[key] as? Number)?.toLong()
fun Map<String, Any?>.double(key: String): Double? = (this[key] as? Number)?.toDouble()
fun Map<String, Any?>.bool(key: String): Boolean? = this[key] as? Boolean
@Suppress("UNCHECKED_CAST")
fun Map<String, Any?>.obj(key: String): Map<String, Any?>? = this[key] as? Map<String, Any?>
@Suppress("UNCHECKED_CAST")
fun Map<String, Any?>.list(key: String): List<Any?>? = this[key] as? List<Any?>
