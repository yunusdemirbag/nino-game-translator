// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.tv.link;

import java.io.ByteArrayOutputStream;
import java.io.EOFException;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.util.HashMap;
import java.util.Locale;
import java.util.Map;

/** Bir HTTP/1.1 isteğinin başı ve (varsa) gövdesi. Yalnız protokolün ihtiyacı kadar. */
public final class Request {
    static final int MAX_HEAD_BYTES = 8 * 1024;

    public final String method;
    public final String path;
    private final Map<String, String> headers;
    public final String body;

    private Request(String method, String path, Map<String, String> headers, String body) {
        this.method = method;
        this.path = path;
        this.headers = headers;
        this.body = body;
    }

    /** Başlık değeri (adı büyük-küçük harfe duyarsız); yoksa "". */
    public String header(String name) {
        String value = headers.get(name.toLowerCase(Locale.ROOT));
        return value == null ? "" : value;
    }

    public boolean wantsWebSocket() {
        return header("Upgrade").equalsIgnoreCase("websocket")
                && header("Connection").toLowerCase(Locale.ROOT).contains("upgrade")
                && !header("Sec-WebSocket-Key").isEmpty();
    }

    /** Gövde sınırı aşıldı. */
    public static final class TooLarge extends IOException {
        TooLarge() { super("çok büyük"); }
    }

    /** İsteği okur. Bozuksa IOException; gövde `bodyLimit`'i aşarsa TooLarge. */
    public static Request read(InputStream in, int bodyLimit) throws IOException {
        ByteArrayOutputStream head = new ByteArrayOutputStream();
        int matched = 0;
        while (matched < 4) {
            int b = in.read();
            if (b < 0) throw new EOFException();
            head.write(b);
            if (head.size() > MAX_HEAD_BYTES) throw new IOException("başlık çok uzun");
            boolean expectedCr = matched == 0 || matched == 2;
            if ((expectedCr && b == '\r') || (!expectedCr && b == '\n')) matched++;
            else matched = b == '\r' ? 1 : 0;
        }
        String[] lines = head.toString("ISO-8859-1").split("\r\n");
        String[] first = lines[0].split(" ");
        if (first.length < 3 || !first[2].startsWith("HTTP/")) throw new IOException("bozuk istek satırı");
        Map<String, String> headers = new HashMap<>();
        for (int i = 1; i < lines.length; i++) {
            int colon = lines[i].indexOf(':');
            if (colon <= 0) continue;
            headers.put(lines[i].substring(0, colon).trim().toLowerCase(Locale.ROOT), lines[i].substring(colon + 1).trim());
        }
        String path = first[1];
        int query = path.indexOf('?');
        if (query >= 0) path = path.substring(0, query);

        String body = "";
        String length = headers.get("content-length");
        if (length != null) {
            int size;
            try {
                size = Integer.parseInt(length.trim());
            } catch (NumberFormatException bad) {
                throw new IOException("bozuk uzunluk");
            }
            if (size < 0) throw new IOException("bozuk uzunluk");
            if (size > bodyLimit) throw new TooLarge();
            byte[] data = new byte[size];
            int done = 0;
            while (done < size) {
                int n = in.read(data, done, size - done);
                if (n < 0) throw new EOFException();
                done += n;
            }
            body = new String(data, StandardCharsets.UTF_8);
        }
        return new Request(first[0].toUpperCase(Locale.ROOT), path, headers, body);
    }

    /** JSON cevabı yazar ve bağlantıyı kapanmaya hazırlar. */
    public static void respond(OutputStream out, int status, String json) throws IOException {
        byte[] body = json.getBytes(StandardCharsets.UTF_8);
        String head = "HTTP/1.1 " + status + " " + reason(status) + "\r\n"
                + "Content-Type: application/json; charset=utf-8\r\n"
                + "Content-Length: " + body.length + "\r\n"
                + "Cache-Control: no-store\r\n"
                + "Connection: close\r\n\r\n";
        out.write(head.getBytes(StandardCharsets.US_ASCII));
        out.write(body);
        out.flush();
    }

    public static void upgrade(OutputStream out, String key) throws IOException {
        String head = "HTTP/1.1 101 Switching Protocols\r\n"
                + "Upgrade: websocket\r\n"
                + "Connection: Upgrade\r\n"
                + "Sec-WebSocket-Accept: " + Frames.acceptKey(key) + "\r\n\r\n";
        out.write(head.getBytes(StandardCharsets.US_ASCII));
        out.flush();
    }

    private static String reason(int status) {
        switch (status) {
            case 200: return "OK";
            case 400: return "Bad Request";
            case 403: return "Forbidden";
            case 404: return "Not Found";
            case 405: return "Method Not Allowed";
            case 413: return "Payload Too Large";
            default: return "Error";
        }
    }
}
