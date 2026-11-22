// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.tv.link;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Nino Bağlantı Protokolü'nün (sürüm 1) sabitleri ve mesaj biçimi. Her mesaj `"app": "nino"` ve `"type"` taşıyan
 * bir JSON nesnesidir; bilinmeyen alanlar yok sayılır.
 */
public final class Wire {
    public static final int VERSION = 1;
    public static final int[] VERSIONS = {1};
    public static final int PORT = 47800;
    public static final String SERVICE_TYPE = "_nino._tcp";
    /** Örtü görseli (cover) taşıyan show için ortak kararla 512 KB (diğer mesajlar göndericide 16 KB altında). */
    public static final int MAX_MESSAGE_BYTES = 512 * 1024;
    public static final long HELLO_WITHIN_MS = 5_000;
    public static final long SILENCE_CLEARS_MS = 20_000;

    public static final String ERR_VERSION = "version_unsupported";
    public static final String ERR_HANDSHAKE = "bad_handshake";
    public static final String ERR_MESSAGE = "bad_message";
    public static final String ERR_TOO_LARGE = "too_large";
    public static final String ERR_REPLACED = "replaced";

    private Wire() {}

    /** Çözülmüş bir mesaj: türü ve tüm alanları. */
    public static final class Message {
        public final String type;
        private final Map<String, Object> fields;

        Message(String type, Map<String, Object> fields) {
            this.type = type;
            this.fields = fields;
        }

        /** Tam sayı alanı; yoksa, sayı değilse ya da kesirliyse null. */
        public Long whole(String key) {
            Object value = fields.get(key);
            if (value instanceof Long) return (Long) value;
            if (value instanceof Double) {
                double d = (Double) value;
                if (d == Math.rint(d) && !Double.isInfinite(d)) return (long) d;
            }
            return null;
        }

        public String text(String key) {
            Object value = fields.get(key);
            return value instanceof String ? (String) value : null;
        }

        /** "app" dışındaki tüm alanlar (sayfaya gönderilmek için). */
        public Map<String, Object> fields() {
            Map<String, Object> copy = new LinkedHashMap<>(fields);
            copy.remove("app");
            return copy;
        }
    }

    /** Mesaj çözülemedi; `reason` hata ayıklama içindir. */
    public static final class Malformed extends Exception {
        public Malformed(String reason) { super(reason); }
    }

    public static Message decode(String text) throws Malformed {
        Object parsed;
        try {
            parsed = Json.parse(text);
        } catch (IllegalArgumentException bad) {
            throw new Malformed("JSON değil: " + bad.getMessage());
        }
        if (!(parsed instanceof Map)) throw new Malformed("nesne değil");
        @SuppressWarnings("unchecked")
        Map<String, Object> map = (Map<String, Object>) parsed;
        if (!"nino".equals(map.get("app"))) throw new Malformed("app nino değil");
        Object type = map.get("type");
        if (!(type instanceof String)) throw new Malformed("type yok");
        return new Message((String) type, map);
    }

    /** Ekrana konacak altyazı (`show` mesajı). */
    public static final class Subtitle {
        public final long id;
        public final String text;
        public final String source;
        public final boolean top;
        public final long durationMs;
        /** Mesajdaki diğer alanlar (Nino uzantıları: box, paragraphs, replace…); sayfaya olduğu gibi gider. */
        private final Map<String, Object> rest;

        public Subtitle(long id, String text, String source, boolean top, long durationMs) {
            this(id, text, source, top, durationMs, new LinkedHashMap<>());
        }

        private Subtitle(long id, String text, String source, boolean top, long durationMs, Map<String, Object> rest) {
            this.id = id;
            this.text = text;
            this.source = source;
            this.top = top;
            this.durationMs = Math.max(0, durationMs);
            this.rest = rest;
        }

        /** `show` mesajından; zorunlu alan (id, text) yoksa Malformed. */
        public static Subtitle from(Message message) throws Malformed {
            Long id = message.whole("id");
            String text = message.text("text");
            if (id == null) throw new Malformed("id yok");
            if (text == null) throw new Malformed("text yok");
            Long duration = message.whole("durationMs");
            Map<String, Object> rest = message.fields();
            for (String known : new String[] {"type", "id", "text", "source", "position", "durationMs"}) rest.remove(known);
            return new Subtitle(id, text, message.text("source"), "top".equals(message.text("position")),
                    duration == null ? 0 : duration, rest);
        }

        /** Sayfaya giden biçim: {type:"show", id, text, source, position, durationMs}. */
        public Map<String, Object> toMap() {
            Map<String, Object> map = new LinkedHashMap<>(rest);
            map.put("type", "show");
            map.put("id", id);
            map.put("text", text);
            if (source != null) map.put("source", source);
            map.put("position", top ? "top" : "bottom");
            map.put("durationMs", durationMs);
            return map;
        }

        @Override
        public boolean equals(Object other) {
            if (!(other instanceof Subtitle)) return false;
            Subtitle s = (Subtitle) other;
            return id == s.id && top == s.top && durationMs == s.durationMs && text.equals(s.text)
                    && (source == null ? s.source == null : source.equals(s.source));
        }

        @Override
        public int hashCode() { return Long.hashCode(id) * 31 + text.hashCode(); }
    }

    // --- Giden mesajlar ---

    static Map<String, Object> base(String type) {
        Map<String, Object> map = new LinkedHashMap<>();
        map.put("app", "nino");
        map.put("type", type);
        return map;
    }

    static List<Object> versionList() {
        List<Object> list = new ArrayList<>();
        for (int v : VERSIONS) list.add((long) v);
        return list;
    }

    public static String info(String name, String id) {
        Map<String, Object> map = base("info");
        map.put("version", (long) VERSION);
        map.put("versions", versionList());
        map.put("name", name);
        map.put("id", id);
        return Json.write(map);
    }

    static String welcome(int version, String name) {
        Map<String, Object> map = base("welcome");
        map.put("version", (long) version);
        map.put("name", name);
        return Json.write(map);
    }

    static String pong(long t) {
        Map<String, Object> map = base("pong");
        map.put("t", t);
        return Json.write(map);
    }

    static String ok() { return Json.write(base("ok")); }

    static String error(String code, String message) {
        Map<String, Object> map = base("error");
        map.put("code", code);
        if (message != null) map.put("message", message);
        if (ERR_VERSION.equals(code)) map.put("versions", versionList());
        return Json.write(map);
    }

    static boolean supports(long version) {
        for (int v : VERSIONS) if (v == version) return true;
        return false;
    }
}
