// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.json

import java.io.Reader

/**
 * Akış hâlinde JSON okuyucu (büyük paketler belleğe ağaç olarak alınmasın diye).
 * Yalnız gereken kadar: nesne/dizi gezme, ad, metin, sayı, değer atlama.
 */
class JsonReader(private val reader: Reader) {
    enum class Token { BEGIN_OBJECT, END_OBJECT, BEGIN_ARRAY, END_ARRAY, NAME, STRING, NUMBER, BOOLEAN, NULL, END }

    private val buf = CharArray(16_384)
    private var len = 0
    private var pos = 0
    // Yığın: 'o' nesne, 'a' dizi; ilk öğe mi bilgisi ayrı.
    private val stack = StringBuilder()
    private val first = ArrayList<Boolean>()
    private var expectValueAfterName = false
    private var peeked: Token? = null

    private fun fill(): Boolean {
        if (pos < len) return true
        len = reader.read(buf, 0, buf.size)
        pos = 0
        return len > 0
    }

    private fun fail(msg: String): Nothing = throw Json.ParseException(msg)

    private fun nextNonSpace(): Char? {
        while (fill()) {
            val c = buf[pos]
            if (c == ' ' || c == '\n' || c == '\r' || c == '\t' || c == '\uFEFF') pos++ else return c
        }
        return null
    }

    fun peek(): Token {
        peeked?.let { return it }
        val t = computePeek()
        peeked = t
        return t
    }

    private fun computePeek(): Token {
        if (expectValueAfterName) return valueToken(nextNonSpace() ?: fail("beklenmeyen son"))
        if (stack.isEmpty()) {
            val c = nextNonSpace() ?: return Token.END
            return valueToken(c)
        }
        val inObject = stack.last() == 'o'
        val isFirst = first.last()
        var c = nextNonSpace() ?: fail("beklenmeyen son")
        if (inObject && c == '}') return Token.END_OBJECT
        if (!inObject && c == ']') return Token.END_ARRAY
        if (!isFirst) {
            if (c != ',') fail("',' bekleniyordu")
            pos++
            c = nextNonSpace() ?: fail("beklenmeyen son")
        }
        if (inObject) { if (c != '"') fail("ad bekleniyordu"); return Token.NAME }
        return valueToken(c)
    }

    private fun valueToken(c: Char): Token = when (c) {
        '{' -> Token.BEGIN_OBJECT
        '[' -> Token.BEGIN_ARRAY
        '"' -> Token.STRING
        't', 'f' -> Token.BOOLEAN
        'n' -> Token.NULL
        else -> if (c == '-' || c.isDigit()) Token.NUMBER else fail("beklenmeyen karakter '$c'")
    }

    private fun consumed() {
        peeked = null
        expectValueAfterName = false
        if (first.isNotEmpty()) first[first.size - 1] = false
    }

    private fun expect(t: Token) { if (peek() != t) fail("$t bekleniyordu, ${peek()} geldi") }

    fun beginObject() { expect(Token.BEGIN_OBJECT); pos++; consumed(); stack.append('o'); first += true }
    fun endObject() { expect(Token.END_OBJECT); pos++; pop() }
    fun beginArray() { expect(Token.BEGIN_ARRAY); pos++; consumed(); stack.append('a'); first += true }
    fun endArray() { expect(Token.END_ARRAY); pos++; pop() }
    private fun pop() { stack.setLength(stack.length - 1); first.removeAt(first.size - 1); peeked = null }

    fun hasNext(): Boolean = peek().let { it != Token.END_OBJECT && it != Token.END_ARRAY && it != Token.END }

    fun nextName(): String {
        expect(Token.NAME)
        val s = readString()
        peeked = null
        if (first.isNotEmpty()) first[first.size - 1] = false
        val c = nextNonSpace() ?: fail("beklenmeyen son")
        if (c != ':') fail("':' bekleniyordu")
        pos++
        expectValueAfterName = true
        return s
    }

    fun nextString(): String { expect(Token.STRING); val s = readString(); consumed(); return s }

    fun nextNumberText(): String {
        expect(Token.NUMBER)
        val b = StringBuilder()
        while (fill()) {
            val c = buf[pos]
            if (c.isDigit() || c == '-' || c == '+' || c == '.' || c == 'e' || c == 'E') { b.append(c); pos++ } else break
        }
        consumed()
        return b.toString()
    }

    fun nextLong(): Long = nextNumberText().let { it.toLongOrNull() ?: it.toDouble().toLong() }

    fun nextBoolean(): Boolean {
        expect(Token.BOOLEAN)
        val v = buf[pos] == 't'
        readWord(if (v) "true" else "false")
        consumed()
        return v
    }

    fun nextNull() { expect(Token.NULL); readWord("null"); consumed() }

    /** Sıradaki değeri ağaç olarak okur (küçük alt nesneler için). */
    fun nextValue(): Any? = when (peek()) {
        Token.BEGIN_OBJECT -> { val m = LinkedHashMap<String, Any?>(); beginObject(); while (hasNext()) { val k = nextName(); m[k] = nextValue() }; endObject(); m }
        Token.BEGIN_ARRAY -> { val l = ArrayList<Any?>(); beginArray(); while (hasNext()) l += nextValue(); endArray(); l }
        Token.STRING -> nextString()
        Token.NUMBER -> nextNumberText().let { t -> if (t.any { it == '.' || it == 'e' || it == 'E' }) t.toDouble() else t.toLongOrNull() ?: t.toDouble() }
        Token.BOOLEAN -> nextBoolean()
        Token.NULL -> { nextNull(); null }
        else -> fail("değer bekleniyordu")
    }

    fun skipValue() { nextValueSkipping() }

    private fun nextValueSkipping() {
        when (peek()) {
            Token.BEGIN_OBJECT -> { beginObject(); while (hasNext()) { nextName(); nextValueSkipping() }; endObject() }
            Token.BEGIN_ARRAY -> { beginArray(); while (hasNext()) nextValueSkipping(); endArray() }
            Token.STRING -> nextString()
            Token.NUMBER -> nextNumberText()
            Token.BOOLEAN -> nextBoolean()
            Token.NULL -> nextNull()
            else -> fail("değer bekleniyordu")
        }
    }

    private fun readWord(w: String) {
        for (ch in w) { if (!fill() || buf[pos] != ch) fail("geçersiz değer"); pos++ }
    }

    private fun readChar(): Char { if (!fill()) fail("kapanmayan yazı"); return buf[pos++] }

    private fun readString(): String {
        if (readChar() != '"') fail("'\"' bekleniyordu")
        val b = StringBuilder()
        while (true) {
            // Hızlı yol: kaçışsız parçayı topluca al.
            if (!fill()) fail("kapanmayan yazı")
            var i = pos
            while (i < len && buf[i] != '"' && buf[i] != '\\') i++
            b.append(buf, pos, i - pos)
            pos = i
            if (pos >= len) continue
            val c = buf[pos++]
            if (c == '"') return b.toString()
            when (val e = readChar()) {
                '"' -> b.append('"'); '\\' -> b.append('\\'); '/' -> b.append('/')
                'b' -> b.append('\b'); 'f' -> b.append('\u000C'); 'n' -> b.append('\n')
                'r' -> b.append('\r'); 't' -> b.append('\t')
                'u' -> {
                    val h = CharArray(4) { readChar() }
                    b.append(String(h).toIntOrNull(16)?.toChar() ?: fail("geçersiz \\u"))
                }
                else -> fail("geçersiz kaçış '$e'")
            }
        }
    }
}
