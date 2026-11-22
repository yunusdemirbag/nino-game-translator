// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.tv.link;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import java.io.ByteArrayOutputStream;
import java.io.DataInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.InetAddress;
import java.net.Socket;
import java.net.SocketTimeoutException;
import java.nio.charset.StandardCharsets;
import java.util.Map;
import java.util.Random;
import java.util.concurrent.BlockingQueue;
import java.util.concurrent.LinkedBlockingQueue;
import java.util.concurrent.TimeUnit;

import org.junit.After;
import org.junit.Before;
import org.junit.Test;

/** Sunucu gerçek soketlerle, göndericinin yapacağı gibi (maskeli çerçeveler) denenir. */
public class LinkServerTest {
    private static final String HELLO = "{\"app\":\"nino\",\"type\":\"hello\",\"version\":1,\"client\":\"test\"}";

    private final BlockingQueue<String> events = new LinkedBlockingQueue<>();
    private final BlockingQueue<String> metrics = new LinkedBlockingQueue<>();
    private LinkServer server;
    private int port;

    @Before
    public void start() throws IOException {
        server = new LinkServer("Salon TV", "tv-1", 0, 800, 1500, new LinkServer.Listener() {
            @Override public void onShow(Wire.Subtitle s) { events.add("show " + s.id + " " + s.text); }
            @Override public void onClear() { events.add("clear"); }
            @Override public void onSender(boolean connected, String client) { events.add((connected ? "in " : "out ") + client); }
            @Override public void onExtension(Wire.Message m) { events.add("ext " + m.type + " " + Json.write(m.fields())); }
            @Override public void onHandshake(long ms) { metrics.add("connect " + (ms >= 0 && ms < 5000)); }
            @Override public void onLost(long afterSec, String cause) { metrics.add("lost " + afterSec + " " + cause); }
        });
        port = server.start();
    }

    @After
    public void stop() { server.stop(); }

    private String event() throws InterruptedException {
        String e = events.poll(3, TimeUnit.SECONDS);
        return e == null ? "(yok)" : e;
    }

    @Test
    public void infoAnswersOverHttp() throws Exception {
        String reply = http("GET", "/nino/info", null);
        assertTrue(reply, reply.startsWith("HTTP/1.1 200"));
        Map<?, ?> info = (Map<?, ?>) Json.parse(reply.substring(reply.indexOf("\r\n\r\n") + 4));
        assertEquals("Salon TV", info.get("name"));
        assertEquals("tv-1", info.get("id"));
        assertTrue(http("GET", "/nope", null).startsWith("HTTP/1.1 404"));
    }

    @Test
    public void senderShowsAndClears() throws Exception {
        try (Client c = new Client()) {
            c.send(HELLO);
            assertEquals("welcome", type(c.receive()));
            assertEquals("in test", event());
            c.send("{\"app\":\"nino\",\"type\":\"show\",\"id\":42,\"text\":\"Buraya gel.\"}");
            assertEquals("show 42 Buraya gel.", event());
            // Geç gelen eski clear yeni altyazıyı silmez.
            c.send("{\"app\":\"nino\",\"type\":\"clear\",\"id\":41}");
            c.send("{\"app\":\"nino\",\"type\":\"ping\",\"t\":99}");
            assertEquals("{\"app\":\"nino\",\"type\":\"pong\",\"t\":99}", c.receive());
            c.send("{\"app\":\"nino\",\"type\":\"clear\",\"id\":42}");
            assertEquals("clear", event());
        }
        assertEquals("out test", event());
    }

    @Test
    public void newSenderReplacesTheOld() throws Exception {
        try (Client first = new Client(); Client second = new Client()) {
            first.send(HELLO);
            first.receive();
            event();
            second.send(HELLO);
            second.receive();
            Map<?, ?> error = (Map<?, ?>) Json.parse(first.receive());
            assertEquals("replaced", error.get("code"));
            assertTrue(first.closedByServer());
            assertEquals("in test", event());
            // Yeni gönderici çalışmayı sürdürür.
            second.send("{\"app\":\"nino\",\"type\":\"show\",\"id\":1,\"text\":\"ikinci\"}");
            assertEquals("show 1 ikinci", event());
        }
    }

    @Test
    public void silentSocketIsClosedAfterHelloTimeout() throws Exception {
        try (Client c = new Client()) {
            assertTrue(c.closedByServer());
        }
    }

    @Test
    public void showBeforeHelloIsRefused() throws Exception {
        try (Client c = new Client()) {
            c.send("{\"app\":\"nino\",\"type\":\"show\",\"id\":1,\"text\":\"x\"}");
            assertEquals("bad_handshake", ((Map<?, ?>) Json.parse(c.receive())).get("code"));
            assertTrue(c.closedByServer());
        }
        assertNull(events.poll(300, TimeUnit.MILLISECONDS));
    }

    @Test
    public void silenceClearsTheScreen() throws Exception {
        try (Client c = new Client()) {
            c.send(HELLO);
            c.receive();
            event();
            c.send("{\"app\":\"nino\",\"type\":\"show\",\"id\":7,\"text\":\"bekle\"}");
            assertEquals("show 7 bekle", event());
            // 1,5 sn hiç mesaj yok (testte sessizlik sınırı kısaltıldı).
            assertEquals("clear", event());
        }
    }

    @Test
    public void durationRemovesTheSubtitle() throws Exception {
        try (Client c = new Client()) {
            c.send(HELLO);
            c.receive();
            event();
            c.send("{\"app\":\"nino\",\"type\":\"show\",\"id\":8,\"text\":\"kısa\",\"durationMs\":200}");
            assertEquals("show 8 kısa", event());
            long since = System.nanoTime();
            assertEquals("clear", event());
            assertTrue(TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - since) < 1200);
        }
    }

    @Test
    public void oneShotPostShowsAndClears() throws Exception {
        String ok = http("POST", "/nino/show", "{\"app\":\"nino\",\"type\":\"show\",\"id\":3,\"text\":\"tek\"}");
        assertTrue(ok, ok.startsWith("HTTP/1.1 200"));
        assertTrue(ok.endsWith("{\"app\":\"nino\",\"type\":\"ok\"}"));
        assertEquals("show 3 tek", event());
        assertTrue(http("POST", "/nino/clear", "{\"app\":\"nino\",\"type\":\"show\"}").startsWith("HTTP/1.1 400"));
        assertTrue(http("POST", "/nino/clear", "{\"app\":\"nino\",\"type\":\"clear\"}").startsWith("HTTP/1.1 200"));
        assertEquals("clear", event());
    }

    @Test
    public void oversizedFrameCloses() throws Exception {
        try (Client c = new Client()) {
            c.send(HELLO);
            c.receive();
            StringBuilder big = new StringBuilder();
            while (big.length() <= Wire.MAX_MESSAGE_BYTES) big.append("0123456789");
            // Sunucu sınırı aşan çerçevenin başlığını görünce yükü okumadan kapatır; istemci yazarken "broken pipe"
            // alabilir. İki durumda da bağlantı kapanmış ve (yetiştiyse) too_large yollanmış olmalı.
            try {
                c.send(big.toString());
                assertEquals("too_large", ((Map<?, ?>) Json.parse(c.receive())).get("code"));
            } catch (java.net.SocketException closedWhileWriting) {
                return;
            }
            assertTrue(c.closedByServer());
        }
    }

    @Test
    public void screenClearsAfterSilenceEvenIfTheSenderLeft() throws Exception {
        try (Client c = new Client()) {
            c.send(HELLO);
            c.receive();
            event();
            c.send("{\"app\":\"nino\",\"type\":\"show\",\"id\":4,\"text\":\"kalmasın\"}");
            assertEquals("show 4 kalmasın", event());
        }
        assertEquals("out test", event());
        assertEquals("clear", event());
    }

    @Test
    public void oneShotShowAlsoClearsAfterSilence() throws Exception {
        http("POST", "/nino/show", "{\"app\":\"nino\",\"type\":\"show\",\"id\":9,\"text\":\"tek\"}");
        assertEquals("show 9 tek", event());
        assertEquals("clear", event());
    }

    @Test
    public void sameSubtitleTwiceReachesThePageTwice() throws Exception {
        try (Client c = new Client()) {
            c.send(HELLO);
            c.receive();
            event();
            String show = "{\"app\":\"nino\",\"type\":\"show\",\"id\":5,\"text\":\"yine\"}";
            c.send(show);
            c.send(show);
            assertEquals("show 5 yine", event());
            assertEquals("show 5 yine", event());
        }
    }

    @Test
    public void ninoExtensionsPassThrough() throws Exception {
        try (Client c = new Client()) {
            c.send(HELLO);
            c.receive();
            event();
            c.send("{\"app\":\"nino\",\"type\":\"style\",\"fontSize\":52}");
            assertEquals("ext style {\"type\":\"style\",\"fontSize\":52}", event());
            // Göstericiye yönelik olmayan türler iletilmez.
            c.send("{\"app\":\"nino\",\"type\":\"welcome\",\"version\":1}");
            c.send("{\"app\":\"nino\",\"type\":\"show\",\"id\":1,\"text\":\"x\",\"box\":{\"left\":0.1},\"replace\":true}");
            assertEquals("show 1 x", event());
        }
    }

    @Test
    public void bigCoverImageReachesThePageIntact() throws Exception {
        java.util.concurrent.atomic.AtomicReference<String> seen = new java.util.concurrent.atomic.AtomicReference<>();
        LinkServer other = new LinkServer("TV", "tv-2", 0, 800, 5000, new LinkServer.Listener() {
            @Override public void onShow(Wire.Subtitle s) { seen.set(Json.write(s.toMap())); events.add("cover"); }
            @Override public void onClear() { }
            @Override public void onSender(boolean connected, String client) { }
        });
        int saved = port;
        port = other.start();
        try (Client c = new Client()) {
            c.send(HELLO);
            c.receive();
            StringBuilder cover = new StringBuilder();
            while (cover.length() < 300_000) cover.append("QUJDRA==");
            c.send("{\"app\":\"nino\",\"type\":\"show\",\"id\":1,\"text\":\"x\",\"box\":{\"left\":0.25,\"top\":0.8,\"right\":0.75,\"bottom\":0.9},\"cover\":\"" + cover + "\"}");
            assertEquals("cover", event());
            Map<?, ?> page = (Map<?, ?>) Json.parse(seen.get());
            assertEquals(cover.toString(), page.get("cover"));
            assertEquals("{\"left\":0.25,\"top\":0.8,\"right\":0.75,\"bottom\":0.9}", Json.write(page.get("box")));
        } finally {
            other.stop();
            port = saved;
        }
    }

    @Test
    public void handshakeAndAbruptDropAreMeasured() throws Exception {
        Client c = new Client();
        c.send(HELLO);
        c.receive();
        assertEquals("connect true", metrics.poll(3, TimeUnit.SECONDS));
        c.close(); // kapanış çerçevesi yok: ağ gitmiş gibi
        assertEquals("lost 0 closed", metrics.poll(3, TimeUnit.SECONDS));
    }

    @Test
    public void cleanCloseAndReplacementAreNotDrops() throws Exception {
        try (Client first = new Client(); Client second = new Client()) {
            first.send(HELLO);
            first.receive();
            second.send(HELLO);
            second.receive();
            assertTrue(first.closedByServer());
            second.closeFrame();
            assertTrue(second.closedByServer());
        }
        assertEquals("connect true", metrics.poll(3, TimeUnit.SECONDS));
        assertEquals("connect true", metrics.poll(3, TimeUnit.SECONDS));
        assertNull(metrics.poll(800, TimeUnit.MILLISECONDS));
    }

    // --- Yardımcılar ---

    private static String type(String json) { return (String) ((Map<?, ?>) Json.parse(json)).get("type"); }

    private String http(String method, String path, String body) throws IOException {
        try (Socket s = new Socket(InetAddress.getLoopbackAddress(), port)) {
            // Makine yüklüyken (öykünücü, derleme) ilk cevap gecikebilir.
            s.setSoTimeout(10_000);
            byte[] data = body == null ? new byte[0] : body.getBytes(StandardCharsets.UTF_8);
            String head = method + " " + path + " HTTP/1.1\r\nHost: tv\r\nContent-Length: " + data.length + "\r\n\r\n";
            OutputStream out = s.getOutputStream();
            out.write(head.getBytes(StandardCharsets.US_ASCII));
            out.write(data);
            out.flush();
            ByteArrayOutputStream all = new ByteArrayOutputStream();
            InputStream in = s.getInputStream();
            byte[] buf = new byte[4096];
            int n;
            while ((n = in.read(buf)) > 0) all.write(buf, 0, n);
            return all.toString("UTF-8");
        }
    }

    /** Göndericiyi taklit eden küçük WebSocket istemcisi. */
    private final class Client implements AutoCloseable {
        final Socket socket;
        final DataInputStream in;
        final OutputStream out;
        final Random random = new Random(7);

        Client() throws IOException {
            socket = new Socket(InetAddress.getLoopbackAddress(), port);
            socket.setSoTimeout(3000);
            out = socket.getOutputStream();
            in = new DataInputStream(socket.getInputStream());
            String key = "dGhlIHNhbXBsZSBub25jZQ==";
            out.write(("GET /nino/ws HTTP/1.1\r\nHost: tv\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
                    + "Sec-WebSocket-Key: " + key + "\r\nSec-WebSocket-Version: 13\r\n\r\n").getBytes(StandardCharsets.US_ASCII));
            out.flush();
            StringBuilder head = new StringBuilder();
            while (!head.toString().endsWith("\r\n\r\n")) head.append((char) in.readUnsignedByte());
            if (!head.toString().startsWith("HTTP/1.1 101") || !head.toString().contains(Frames.acceptKey(key))) {
                throw new IOException("yükseltme olmadı: " + head);
            }
        }

        void send(String text) throws IOException {
            byte[] payload = text.getBytes(StandardCharsets.UTF_8);
            ByteArrayOutputStream frame = new ByteArrayOutputStream();
            frame.write(0x81);
            if (payload.length < 126) {
                frame.write(0x80 | payload.length);
            } else if (payload.length <= 0xFFFF) {
                frame.write(0x80 | 126);
                frame.write(payload.length >> 8);
                frame.write(payload.length & 0xFF);
            } else {
                frame.write(0x80 | 127);
                for (int i = 7; i >= 0; i--) frame.write((int) (((long) payload.length) >> (8 * i)) & 0xFF);
            }
            byte[] mask = new byte[4];
            random.nextBytes(mask);
            frame.write(mask);
            for (int i = 0; i < payload.length; i++) frame.write(payload[i] ^ mask[i & 3]);
            out.write(frame.toByteArray());
            out.flush();
        }

        /** Maskeli kapanış çerçevesi (gönderici düzgün kapatıyor). */
        void closeFrame() throws IOException {
            out.write(new byte[] {(byte) 0x88, (byte) 0x80, 1, 2, 3, 4});
            out.flush();
        }

        /** Sıradaki metin çerçevesi. */
        String receive() throws IOException {
            while (true) {
                int first = in.readUnsignedByte();
                int length = in.readUnsignedByte() & 0x7F;
                if (length == 126) length = in.readUnsignedShort();
                else if (length == 127) length = (int) in.readLong();
                byte[] payload = new byte[length];
                in.readFully(payload);
                int opcode = first & 0x0F;
                if (opcode == 0x1) return new String(payload, StandardCharsets.UTF_8);
                if (opcode == 0x8) throw new IOException("kapandı");
            }
        }

        /** Sunucu kapanış çerçevesi yolladı ya da soketi kapattı. */
        boolean closedByServer() throws IOException {
            try {
                while (true) {
                    int first = in.read();
                    if (first < 0) return true;
                    int length = in.readUnsignedByte() & 0x7F;
                    if (length == 126) length = in.readUnsignedShort();
                    in.readFully(new byte[length]);
                    if ((first & 0x0F) == 0x8) return true;
                }
            } catch (SocketTimeoutException stillOpen) {
                return false;
            } catch (IOException reset) {
                return true;
            }
        }

        @Override
        public void close() throws IOException { socket.close(); }
    }
}
