// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.tv.link;

import java.io.BufferedInputStream;
import java.io.BufferedOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.net.ServerSocket;
import java.net.Socket;
import java.net.SocketException;
import java.util.HashSet;
import java.util.Set;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.ScheduledFuture;
import java.util.concurrent.TimeUnit;

/**
 * TV tarafı sunucu: aynı bağlantı noktasında HTTP (`/nino/info`, `/nino/show`, `/nino/clear`) ve WebSocket
 * (`/nino/ws`). Aynı anda tek gönderici; yenisi el sıkışınca eskisi `replaced` ile kapatılır.
 *
 * Her bağlantı kendi iş parçacığında okunur; ortak durum bu nesnenin kilidiyle korunur. Dinleyici çağrıları
 * sunucunun iş parçacıklarından gelir.
 */
public final class LinkServer {
    /** Ekranın ve bağlantının değişimleri. */
    public interface Listener {
        void onShow(Wire.Subtitle subtitle);

        /** Ekrandaki altyazı kalktı (id'li clear, süre doldu, sessizlik ya da id'siz clear). */
        void onClear();

        /** Bir gönderici el sıkıştı (true) ya da etkin gönderici koptu (false). */
        void onSender(boolean connected, String client);

        /** Etkin göndericiden Nino uzantı mesajı (style, screen, started…). Varsayılan: yok sayılır. */
        default void onExtension(Wire.Message message) { }

        /** Ölçüm için: bir gönderici bağlantıyı açıp el sıkıştı; ms bağlantının açılmasından welcome'a kadar. */
        default void onHandshake(long ms) { }

        /**
         * Ölçüm için: etkin gönderici kapanış çerçevesi yollamadan koptu. afterSec: bağlı kaldığı süre. cause:
         * `write_error` (göndericiye yazılamadı) ya da `closed` (bağlantı karşı taraftan kesildi). Göndericinin kendi
         * kapatması ve başka göndericiyle değiştirilmesi kopma sayılmaz.
         */
        default void onLost(long afterSec, String cause) { }

        /** Ölçüm için: etkin gönderici başka bir göndericiyle değiştirildi (otomatik teşhiste `replaced`). */
        default void onReplaced(long afterSec) { }
    }

    private final String name;
    private final String id;
    private final int wantedPort;
    private final long helloWithinMs;
    private final long silenceClearsMs;
    private final Listener listener;

    private final ScheduledExecutorService clock = Executors.newSingleThreadScheduledExecutor(r -> {
        Thread t = new Thread(r, "nino-link-clock");
        t.setDaemon(true);
        return t;
    });
    private final Screen screen = new Screen();
    private final Set<Peer> peers = new HashSet<>();
    private ServerSocket socket;
    private volatile boolean running;
    private Peer active;
    private ScheduledFuture<?> silenceTimer;
    private ScheduledFuture<?> durationTimer;

    public LinkServer(String name, String id, int port, Listener listener) {
        this(name, id, port, Wire.HELLO_WITHIN_MS, Wire.SILENCE_CLEARS_MS, listener);
    }

    /** Süreler testler için ayarlanabilir. */
    public LinkServer(String name, String id, int port, long helloWithinMs, long silenceClearsMs, Listener listener) {
        this.name = name;
        this.id = id;
        this.wantedPort = port;
        this.helloWithinMs = helloWithinMs;
        this.silenceClearsMs = silenceClearsMs;
        this.listener = listener;
    }

    /** Dinlemeye başlar; gerçek bağlantı noktasını döner (0 verildiyse sistem seçer). */
    public synchronized int start() throws IOException {
        if (running) return socket.getLocalPort();
        ServerSocket server = new ServerSocket();
        server.setReuseAddress(true);
        server.bind(new InetSocketAddress(wantedPort));
        socket = server;
        running = true;
        Thread accept = new Thread(this::acceptLoop, "nino-link-accept");
        accept.setDaemon(true);
        accept.start();
        return server.getLocalPort();
    }

    public synchronized boolean isRunning() { return running; }

    public synchronized int port() { return socket == null ? 0 : socket.getLocalPort(); }

    public synchronized boolean hasSender() { return active != null; }

    public synchronized void stop() {
        running = false;
        try { if (socket != null) socket.close(); } catch (IOException ignored) { /* kapanıyor */ }
        for (Peer peer : new HashSet<>(peers)) peer.shut();
        peers.clear();
        active = null;
        cancel(silenceTimer);
        cancel(durationTimer);
        clock.shutdownNow();
    }

    private void acceptLoop() {
        while (running) {
            Socket client;
            try {
                client = socket.accept();
            } catch (IOException closed) {
                return;
            }
            if (!HomeNetwork.allows(client.getInetAddress())) {
                try { client.close(); } catch (IOException ignored) { /* yok sayılır */ }
                continue;
            }
            Thread worker = new Thread(() -> serve(client), "nino-link-peer");
            worker.setDaemon(true);
            worker.start();
        }
    }

    private void serve(Socket client) {
        try {
            client.setTcpNoDelay(true);
            client.setSoTimeout((int) Math.max(1000, helloWithinMs));
            InputStream in = new BufferedInputStream(client.getInputStream());
            OutputStream out = new BufferedOutputStream(client.getOutputStream());
            Request request;
            try {
                request = Request.read(in, Wire.MAX_MESSAGE_BYTES);
            } catch (Request.TooLarge big) {
                Request.respond(out, 413, Wire.error(Wire.ERR_TOO_LARGE, null));
                return;
            }
            route(client, request, in, out);
        } catch (IOException ignored) {
            // Bağlantı koptu ya da istek bozuk.
        } finally {
            try { client.close(); } catch (IOException ignored) { /* kapalı */ }
        }
    }

    private void route(Socket client, Request request, InputStream in, OutputStream out) throws IOException {
        switch (request.path) {
            case "/nino/info":
                if (!request.method.equals("GET")) { Request.respond(out, 405, Wire.error(Wire.ERR_MESSAGE, "GET")); return; }
                Request.respond(out, 200, Wire.info(name, id));
                return;
            case "/nino/ws":
                if (!request.wantsWebSocket()) { Request.respond(out, 400, Wire.error(Wire.ERR_HANDSHAKE, "websocket")); return; }
                Request.upgrade(out, request.header("Sec-WebSocket-Key"));
                talk(client, in, out);
                return;
            case "/nino/show":
            case "/nino/clear":
                if (!request.method.equals("POST")) { Request.respond(out, 405, Wire.error(Wire.ERR_MESSAGE, "POST")); return; }
                oneShot(request, out);
                return;
            default:
                Request.respond(out, 404, Wire.error(Wire.ERR_MESSAGE, "yok"));
        }
    }

    /** WebSocket kullanamayanlar için tek seferlik gösterme/temizleme. */
    private void oneShot(Request request, OutputStream out) throws IOException {
        Wire.Message message;
        try {
            message = Wire.decode(request.body);
        } catch (Wire.Malformed bad) {
            Request.respond(out, 400, Wire.error(Wire.ERR_MESSAGE, bad.getMessage()));
            return;
        }
        boolean show = request.path.equals("/nino/show");
        if (!message.type.equals(show ? "show" : "clear")) {
            Request.respond(out, 400, Wire.error(Wire.ERR_MESSAGE, "tür yola uymuyor"));
            return;
        }
        noteActivity();
        if (show) {
            try {
                put(Wire.Subtitle.from(message));
            } catch (Wire.Malformed bad) {
                Request.respond(out, 400, Wire.error(Wire.ERR_MESSAGE, bad.getMessage()));
                return;
            }
        } else {
            remove(message.whole("id"));
        }
        Request.respond(out, 200, Wire.ok());
    }

    // --- WebSocket konuşması ---

    private void talk(Socket client, InputStream in, OutputStream out) throws IOException {
        Peer peer = new Peer(client, out, new Conversation(name));
        boolean cleanly = false;
        synchronized (this) {
            if (!running) return;
            peers.add(peer);
        }
        ScheduledFuture<?> helloTimer = clock.schedule(() -> apply(peer, peer.talk.helloTimedOut()),
                helloWithinMs, TimeUnit.MILLISECONDS);
        try {
            while (!peer.talk.isDone()) {
                if (peer.talk.isOpen()) client.setSoTimeout(0);
                Frames.Incoming incoming;
                try {
                    incoming = Frames.next(in, out, Wire.MAX_MESSAGE_BYTES);
                } catch (java.net.SocketTimeoutException slow) {
                    if (!peer.talk.isOpen()) break;
                    continue;
                }
                if (incoming.closed) { cleanly = true; break; }
                if (incoming.tooLarge) {
                    peer.send(Wire.error(Wire.ERR_TOO_LARGE, null));
                    break;
                }
                if (peer == activePeer()) noteActivity();
                apply(peer, peer.talk.receive(incoming.text));
            }
        } catch (SocketException | java.io.EOFException gone) {
            // karşı taraf kapattı
        } finally {
            cancel(helloTimer);
            boolean byUs = peer.isShut() && !peer.writeFailed;
            peer.shut();
            if (left(peer) && !cleanly && !byUs) {
                listener.onLost(java.util.concurrent.TimeUnit.NANOSECONDS.toSeconds(System.nanoTime() - peer.readyAt),
                        peer.writeFailed ? "write_error" : "closed");
            }
        }
    }

    /** Konuşmanın adımını uygular: cevaplar, ekran, el sıkışma ve kapanış. */
    private void apply(Peer peer, Conversation.Step step) {
        for (String reply : step.replies) peer.send(reply);
        if (step.ready) {
            peer.readyAt = System.nanoTime();
            becomeActive(peer);
            listener.onHandshake(java.util.concurrent.TimeUnit.NANOSECONDS.toMillis(peer.readyAt - peer.openedAt));
        }
        boolean current = peer == activePeer();
        if (step.show != null && current) put(step.show);
        if (step.clear && current) remove(step.clearId);
        if (step.extension != null && current) listener.onExtension(step.extension);
        if (step.close) peer.shut();
    }

    private void becomeActive(Peer peer) {
        Peer old;
        synchronized (this) {
            old = active;
            active = peer;
        }
        if (old != null && old != peer) {
            apply(old, old.talk.replaced());
            listener.onReplaced(java.util.concurrent.TimeUnit.NANOSECONDS.toSeconds(System.nanoTime() - old.readyAt));
        }
        noteActivity();
        listener.onSender(true, peer.talk.client());
    }

    /** Etkin gönderici buydu ise true. */
    private boolean left(Peer peer) {
        boolean wasActive;
        synchronized (this) {
            peers.remove(peer);
            // Sessizlik saati sürer: gönderici geri gelmezse ekran 20 sn sonra temizlenir.
            wasActive = active == peer;
            if (wasActive) active = null;
        }
        if (wasActive && running) listener.onSender(false, peer.talk.client());
        return wasActive && running;
    }

    private synchronized Peer activePeer() { return active; }

    // --- Ekran ---

    private void put(Wire.Subtitle subtitle) {
        synchronized (this) {
            screen.put(subtitle);
            cancel(durationTimer);
            if (subtitle.durationMs > 0) {
                long shownId = subtitle.id;
                durationTimer = clock.schedule(() -> remove(shownId), subtitle.durationMs, TimeUnit.MILLISECONDS);
            }
        }
        // Aynı altyazı yeniden gelse de iletilir: sayfa onu kendi saatiyle (kopma payı, demo) kaldırmış olabilir.
        listener.onShow(subtitle);
    }

    private void remove(Long id) {
        boolean changed;
        synchronized (this) {
            changed = screen.remove(id);
            if (changed) cancel(durationTimer);
        }
        if (changed) listener.onClear();
    }

    /** Etkin göndericiden mesaj geldi: sessizlik saati baştan başlar. */
    private void noteActivity() {
        synchronized (this) {
            if (!running) return;
            cancel(silenceTimer);
            silenceTimer = clock.schedule(() -> remove(null), silenceClearsMs, TimeUnit.MILLISECONDS);
        }
    }

    private static void cancel(ScheduledFuture<?> timer) {
        if (timer != null) timer.cancel(false);
    }

    /** Bir WebSocket bağlantısı. */
    private static final class Peer {
        final Socket socket;
        final OutputStream out;
        final Conversation talk;
        final long openedAt = System.nanoTime();
        volatile long readyAt = System.nanoTime();
        volatile boolean writeFailed;
        private boolean shut;

        Peer(Socket socket, OutputStream out, Conversation talk) {
            this.socket = socket;
            this.out = out;
            this.talk = talk;
        }

        void send(String text) {
            try {
                Frames.sendText(out, text);
            } catch (IOException gone) {
                writeFailed = true;
                shut();
            }
        }

        synchronized boolean isShut() { return shut; }

        synchronized void shut() {
            if (shut) return;
            shut = true;
            try { Frames.sendClose(out); } catch (IOException ignored) { /* kopmuş */ }
            try { socket.close(); } catch (IOException ignored) { /* kapalı */ }
        }
    }
}
