// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.tv.link;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Küçük bir JSON okuyucu ve yazıcı. Protokol mesajları küçüktür (en çok 16 KB); Android'in org.json'u JVM
 * testlerinde boş olduğu için burada kendi okuyucumuz var.
 *
 * Okunan değerler: Map (nesne), List (dizi), String, Double ya da Long (sayı), Boolean, null.
 */
public final class Json {
    private final String src;
    private int at;

    private Json(String src) { this.src = src; }

    /** Hatalı yazımda IllegalArgumentException atar. */
    public static Object parse(String text) {
        if (text == null) throw new IllegalArgumentException("boş");
        Json reader = new Json(text);
        reader.space();
        Object value = reader.value(0);
        reader.space();
        if (reader.at != text.length()) throw new IllegalArgumentException("fazla karakter");
        return value;
    }

    private Object value(int depth) {
        if (depth > 32) throw new IllegalArgumentException("çok derin");
        if (at >= src.length()) throw new IllegalArgumentException("erken bitti");
        char c = src.charAt(at);
        switch (c) {
            case '{': return object(depth);
            case '[': return array(depth);
            case '"': return string();
            case 't': return word("true", Boolean.TRUE);
            case 'f': return word("false", Boolean.FALSE);
            case 'n': return word("null", null);
            default:
                if (c == '-' || (c >= '0' && c <= '9')) return number();
                throw new IllegalArgumentException("beklenmeyen " + c);
        }
    }

    private Map<String, Object> object(int depth) {
        Map<String, Object> map = new LinkedHashMap<>();
        at++;
        space();
        if (peek('}')) { at++; return map; }
        while (true) {
            space();
            if (!peek('"')) throw new IllegalArgumentException("anahtar yok");
            String key = string();
            space();
            expect(':');
            space();
            map.put(key, value(depth + 1));
            space();
            if (peek(',')) { at++; continue; }
            expect('}');
            return map;
        }
    }

    private List<Object> array(int depth) {
        List<Object> list = new ArrayList<>();
        at++;
        space();
        if (peek(']')) { at++; return list; }
        while (true) {
            space();
            list.add(value(depth + 1));
            space();
            if (peek(',')) { at++; continue; }
            expect(']');
            return list;
        }
    }

    private String string() {
        expect('"');
        StringBuilder out = new StringBuilder();
        while (true) {
            if (at >= src.length()) throw new IllegalArgumentException("yazı kapanmadı");
            char c = src.charAt(at++);
            if (c == '"') return out.toString();
            if (c < 0x20) throw new IllegalArgumentException("denetim karakteri");
            if (c != '\\') { out.append(c); continue; }
            if (at >= src.length()) throw new IllegalArgumentException("kaçış bitmedi");
            char e = src.charAt(at++);
            switch (e) {
                case '"': out.append('"'); break;
                case '\\': out.append('\\'); break;
                case '/': out.append('/'); break;
                case 'b': out.append('\b'); break;
                case 'f': out.append('\f'); break;
                case 'n': out.append('\n'); break;
                case 'r': out.append('\r'); break;
                case 't': out.append('\t'); break;
                case 'u':
                    if (at + 4 > src.length()) throw new IllegalArgumentException("kısa \\u");
                    try {
                        out.append((char) Integer.parseInt(src.substring(at, at + 4), 16));
                    } catch (NumberFormatException bad) {
                        throw new IllegalArgumentException("bozuk \\u");
                    }
                    at += 4;
                    break;
                default: throw new IllegalArgumentException("bilinmeyen kaçış");
            }
        }
    }

    private Object number() {
        int start = at;
        if (peek('-')) at++;
        boolean fraction = false;
        while (at < src.length()) {
            char c = src.charAt(at);
            if (c >= '0' && c <= '9') { at++; continue; }
            if (c == '.' || c == 'e' || c == 'E' || c == '+' || c == '-') { fraction = true; at++; continue; }
            break;
        }
        String digits = src.substring(start, at);
        try {
            if (!fraction) return Long.parseLong(digits);
            return Double.parseDouble(digits);
        } catch (NumberFormatException tooBig) {
            try {
                return Double.parseDouble(digits);
            } catch (NumberFormatException bad) {
                throw new IllegalArgumentException("bozuk sayı");
            }
        }
    }

    private Object word(String word, Object result) {
        if (!src.startsWith(word, at)) throw new IllegalArgumentException("bozuk sözcük");
        at += word.length();
        return result;
    }

    private void space() {
        while (at < src.length()) {
            char c = src.charAt(at);
            if (c != ' ' && c != '\n' && c != '\r' && c != '\t') return;
            at++;
        }
    }

    private boolean peek(char c) { return at < src.length() && src.charAt(at) == c; }

    private void expect(char c) {
        if (!peek(c)) throw new IllegalArgumentException(c + " bekleniyordu");
        at++;
    }

    // --- Yazma ---

    /** Map, List, String, Number, Boolean ve null'u JSON'a çevirir. Anahtar sırası korunur. */
    public static String write(Object value) {
        StringBuilder out = new StringBuilder();
        append(out, value);
        return out.toString();
    }

    private static void append(StringBuilder out, Object value) {
        if (value == null) {
            out.append("null");
        } else if (value instanceof String) {
            quote(out, (String) value);
        } else if (value instanceof Boolean) {
            out.append(value.toString());
        } else if (value instanceof Double || value instanceof Float) {
            double d = ((Number) value).doubleValue();
            if (d == Math.rint(d) && Math.abs(d) < 1e15) out.append((long) d); else out.append(d);
        } else if (value instanceof Number) {
            out.append(((Number) value).longValue());
        } else if (value instanceof Map) {
            out.append('{');
            boolean first = true;
            for (Map.Entry<?, ?> entry : ((Map<?, ?>) value).entrySet()) {
                if (!first) out.append(',');
                first = false;
                quote(out, String.valueOf(entry.getKey()));
                out.append(':');
                append(out, entry.getValue());
            }
            out.append('}');
        } else if (value instanceof List) {
            out.append('[');
            boolean first = true;
            for (Object item : (List<?>) value) {
                if (!first) out.append(',');
                first = false;
                append(out, item);
            }
            out.append(']');
        } else {
            quote(out, value.toString());
        }
    }

    static void quote(StringBuilder out, String text) {
        out.append('"');
        for (int i = 0; i < text.length(); i++) {
            char c = text.charAt(i);
            switch (c) {
                case '"': out.append("\\\""); break;
                case '\\': out.append("\\\\"); break;
                case '\n': out.append("\\n"); break;
                case '\r': out.append("\\r"); break;
                case '\t': out.append("\\t"); break;
                default:
                    // U+2028/2029 JavaScript'te satır sonu sayılır; sayfaya giden betikte sorun çıkarmasın.
                    if (c < 0x20 || c == ' ' || c == ' ') out.append(String.format("\\u%04x", (int) c));
                    else out.append(c);
            }
        }
        out.append('"');
    }
}
