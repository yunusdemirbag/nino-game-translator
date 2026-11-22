// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.tv.link;

import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;

/**
 * TV'nin tek bir göndericiyle konuşması: el sıkışma ve mesaj kuralları. Ağdan ve zamandan bağımsızdır; her gelen
 * metin için ne yapılacağını bir {@link Step} olarak döner. Zaman aşımları dışarıdan bildirilir.
 */
public final class Conversation {
    /** Bir mesaja verilen karşılık. */
    public static final class Step {
        /** Göndericiye sırayla yollanacak mesajlar. */
        public final List<String> replies = new ArrayList<>();
        /** Gösterilecek altyazı (yoksa null). */
        public Wire.Subtitle show;
        /** `clear` geldi. */
        public boolean clear;
        /** `clear`'ın id'si (yoksa null: ekranın tümü). */
        public Long clearId;
        /** El sıkışma bu adımda bitti. */
        public boolean ready;
        /** Bağlantı kapatılmalı. */
        public boolean close;
        /** Protokolün çekirdeğinde olmayan bir Nino uzantı mesajı (style, screen, started…); gösterici isterse kullanır. */
        public Wire.Message extension;

        boolean isEmpty() { return replies.isEmpty() && show == null && !clear && !ready && !close && extension == null; }
    }

    private enum Phase { HELLO, OPEN, DONE }

    private final String name;
    private Phase phase = Phase.HELLO;
    private String client = "";

    public Conversation(String name) { this.name = name; }

    public synchronized boolean isOpen() { return phase == Phase.OPEN; }

    public synchronized boolean isDone() { return phase == Phase.DONE; }

    /** Göndericinin kendini tanıttığı ad (`client`, yoksa `device`). */
    public String client() { return client; }

    public synchronized Step receive(String text) {
        Step step = new Step();
        if (phase == Phase.DONE) return step;
        if (text.getBytes(StandardCharsets.UTF_8).length > Wire.MAX_MESSAGE_BYTES) return fail(step, Wire.ERR_TOO_LARGE);

        Wire.Message message;
        try {
            message = Wire.decode(text);
        } catch (Wire.Malformed bad) {
            if (phase == Phase.HELLO) return fail(step, Wire.ERR_HANDSHAKE);
            step.replies.add(Wire.error(Wire.ERR_MESSAGE, bad.getMessage()));
            return step;
        }

        if (phase == Phase.HELLO) return greet(step, message);

        switch (message.type) {
            case "show":
                try {
                    step.show = Wire.Subtitle.from(message);
                } catch (Wire.Malformed bad) {
                    step.replies.add(Wire.error(Wire.ERR_MESSAGE, bad.getMessage()));
                }
                break;
            case "clear":
                step.clear = true;
                step.clearId = message.whole("id");
                break;
            case "ping": {
                Long t = message.whole("t");
                if (t == null) step.replies.add(Wire.error(Wire.ERR_MESSAGE, "t yok"));
                else step.replies.add(Wire.pong(t));
                break;
            }
            case "hello":
            case "welcome":
            case "info":
            case "pong":
            case "ok":
            case "error":
                // Göstericiye yönelik olmayan türler: yok sayılır.
                break;
            default:
                // Uzantı ya da bilinmeyen tür: bağlantı sürer, gösterici isterse kullanır.
                step.extension = message;
                break;
        }
        return step;
    }

    private Step greet(Step step, Wire.Message message) {
        if (!"hello".equals(message.type)) return fail(step, Wire.ERR_HANDSHAKE);
        Long version = message.whole("version");
        if (version == null) return fail(step, Wire.ERR_HANDSHAKE);
        if (!Wire.supports(version)) return fail(step, Wire.ERR_VERSION);
        String who = message.text("client");
        if (who == null) who = message.text("device");
        client = who == null ? "" : who;
        phase = Phase.OPEN;
        step.replies.add(Wire.welcome(version.intValue(), name));
        step.ready = true;
        return step;
    }

    /** 5 sn içinde hello gelmedi. */
    public synchronized Step helloTimedOut() {
        Step step = new Step();
        if (phase != Phase.HELLO) return step;
        phase = Phase.DONE;
        step.close = true;
        return step;
    }

    /** Başka bir gönderici geldi; bu konuşma kapanır. */
    public synchronized Step replaced() {
        Step step = new Step();
        if (phase == Phase.DONE) return step;
        return fail(step, Wire.ERR_REPLACED);
    }

    private Step fail(Step step, String code) {
        phase = Phase.DONE;
        step.replies.add(Wire.error(code, null));
        step.close = true;
        return step;
    }
}
