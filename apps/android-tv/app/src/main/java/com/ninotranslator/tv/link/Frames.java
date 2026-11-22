// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.tv.link;

import java.io.ByteArrayOutputStream;
import java.io.EOFException;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;

/**
 * WebSocket (RFC 6455) çerçeveleri: sunucu tarafı. Gelen çerçeveler maskeli olmalıdır; giden çerçeveler maskesizdir.
 * Yalnız metin mesajları taşınır; parçalı (fragmented) metin birleştirilir.
 */
public final class Frames {
    static final int TEXT = 0x1;
    static final int CONTINUATION = 0x0;
    static final int BINARY = 0x2;
    static final int CLOSE = 0x8;
    static final int PING = 0x9;
    static final int PONG = 0xA;

    private static final String MAGIC = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";

    private Frames() {}

    /** Okuma sırasında gelen olaylar. */
    public static final class Incoming {
        /** Tam bir metin mesajı; kapanışta null. */
        public final String text;
        /** Karşı taraf kapattı. */
        public final boolean closed;
        /** Mesaj sınırı aşıldı. */
        public final boolean tooLarge;

        private Incoming(String text, boolean closed, boolean tooLarge) {
            this.text = text;
            this.closed = closed;
            this.tooLarge = tooLarge;
        }
    }

    /** Ham bir çerçeve. */
    private static final class Raw {
        boolean fin;
        int opcode;
        byte[] payload;
    }

    /** `Sec-WebSocket-Accept` değeri. */
    public static String acceptKey(String key) {
        try {
            MessageDigest sha1 = MessageDigest.getInstance("SHA-1");
            byte[] digest = sha1.digest((key.trim() + MAGIC).getBytes(StandardCharsets.US_ASCII));
            return Base64Text.encode(digest);
        } catch (NoSuchAlgorithmException impossible) {
            throw new IllegalStateException(impossible);
        }
    }

    /**
     * Sıradaki metin mesajını okur. Ping'lere kendisi pong ile, kapanışa kapanışla karşılık verir.
     *
     * @param limit tek mesajın en büyük boyu (bayt)
     */
    public static Incoming next(InputStream in, OutputStream out, int limit) throws IOException {
        ByteArrayOutputStream message = null;
        while (true) {
            Raw raw = read(in, limit);
            if (raw == null) return new Incoming(null, false, true);
            switch (raw.opcode) {
                case PING:
                    write(out, PONG, raw.payload);
                    continue;
                case PONG:
                    continue;
                case CLOSE:
                    try { write(out, CLOSE, new byte[0]); } catch (IOException ignored) { /* zaten kopmuş */ }
                    return new Incoming(null, true, false);
                case TEXT:
                case BINARY:
                    message = new ByteArrayOutputStream();
                    message.write(raw.payload);
                    break;
                case CONTINUATION:
                    if (message == null) throw new IOException("başsız devam çerçevesi");
                    message.write(raw.payload);
                    break;
                default:
                    throw new IOException("bilinmeyen opcode " + raw.opcode);
            }
            if (message.size() > limit) return new Incoming(null, false, true);
            if (raw.fin) return new Incoming(new String(message.toByteArray(), StandardCharsets.UTF_8), false, false);
        }
    }

    /** null: çerçeve sınırı aştı (yükü okunmadı). */
    private static Raw read(InputStream in, int limit) throws IOException {
        int first = byteOf(in);
        int second = byteOf(in);
        Raw raw = new Raw();
        raw.fin = (first & 0x80) != 0;
        raw.opcode = first & 0x0F;
        boolean masked = (second & 0x80) != 0;
        long length = second & 0x7F;
        if (length == 126) {
            length = (byteOf(in) << 8) | byteOf(in);
        } else if (length == 127) {
            length = 0;
            for (int i = 0; i < 8; i++) length = (length << 8) | byteOf(in);
        }
        if (!masked) throw new IOException("istemci çerçevesi maskesiz");
        if (length < 0 || length > limit) return null;
        byte[] mask = new byte[4];
        fill(in, mask);
        byte[] payload = new byte[(int) length];
        fill(in, payload);
        for (int i = 0; i < payload.length; i++) payload[i] ^= mask[i & 3];
        raw.payload = payload;
        return raw;
    }

    public static void sendText(OutputStream out, String text) throws IOException {
        write(out, TEXT, text.getBytes(StandardCharsets.UTF_8));
    }

    public static void sendClose(OutputStream out) throws IOException {
        write(out, CLOSE, new byte[0]);
    }

    static void write(OutputStream out, int opcode, byte[] payload) throws IOException {
        int length = payload.length;
        byte[] head;
        if (length < 126) {
            head = new byte[] {(byte) (0x80 | opcode), (byte) length};
        } else if (length <= 0xFFFF) {
            head = new byte[] {(byte) (0x80 | opcode), 126, (byte) (length >> 8), (byte) length};
        } else {
            head = new byte[10];
            head[0] = (byte) (0x80 | opcode);
            head[1] = 127;
            for (int i = 0; i < 8; i++) head[9 - i] = (byte) (((long) length) >> (8 * i));
        }
        synchronized (out) {
            out.write(head);
            out.write(payload);
            out.flush();
        }
    }

    private static int byteOf(InputStream in) throws IOException {
        int b = in.read();
        if (b < 0) throw new EOFException();
        return b;
    }

    private static void fill(InputStream in, byte[] into) throws IOException {
        int done = 0;
        while (done < into.length) {
            int n = in.read(into, done, into.length - done);
            if (n < 0) throw new EOFException();
            done += n;
        }
    }

    /** java.util.Base64 Android 8'den önce yok; tek kullanım için küçük bir kodlayıcı. */
    static final class Base64Text {
        private static final char[] ALPHABET =
                "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".toCharArray();

        private Base64Text() {}

        static String encode(byte[] data) {
            StringBuilder out = new StringBuilder((data.length + 2) / 3 * 4);
            for (int i = 0; i < data.length; i += 3) {
                int b0 = data[i] & 0xFF;
                int b1 = i + 1 < data.length ? data[i + 1] & 0xFF : 0;
                int b2 = i + 2 < data.length ? data[i + 2] & 0xFF : 0;
                out.append(ALPHABET[b0 >> 2]);
                out.append(ALPHABET[((b0 & 3) << 4) | (b1 >> 4)]);
                out.append(i + 1 < data.length ? ALPHABET[((b1 & 0xF) << 2) | (b2 >> 6)] : '=');
                out.append(i + 2 < data.length ? ALPHABET[b2 & 0x3F] : '=');
            }
            return out.toString();
        }
    }
}
