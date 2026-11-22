// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.tv.link;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

/** El sıkışma ve mesaj kuralları (ağsız). */
public class ConversationTest {
    private static final String HELLO = "{\"app\":\"nino\",\"type\":\"hello\",\"version\":1,\"device\":\"Mac\",\"client\":\"nino-mac/0.1.0\"}";

    private static String code(String reply) {
        return (String) ((java.util.Map<?, ?>) Json.parse(reply)).get("code");
    }

    private static String type(String reply) {
        return (String) ((java.util.Map<?, ?>) Json.parse(reply)).get("type");
    }

    @Test
    public void helloIsAnsweredWithWelcome() {
        Conversation talk = new Conversation("Salon TV");
        Conversation.Step step = talk.receive(HELLO);
        assertTrue(step.ready);
        assertFalse(step.close);
        assertEquals("{\"app\":\"nino\",\"type\":\"welcome\",\"version\":1,\"name\":\"Salon TV\"}", step.replies.get(0));
        assertEquals("nino-mac/0.1.0", talk.client());
        assertTrue(talk.isOpen());
    }

    @Test
    public void anythingBeforeHelloEndsTheTalk() {
        Conversation talk = new Conversation("TV");
        Conversation.Step step = talk.receive("{\"app\":\"nino\",\"type\":\"show\",\"id\":1,\"text\":\"x\"}");
        assertTrue(step.close);
        assertNull(step.show);
        assertEquals("bad_handshake", code(step.replies.get(0)));
        assertTrue(talk.isDone());
        assertTrue(talk.receive(HELLO).isEmpty());
    }

    @Test
    public void wrongAppOrBrokenJsonBeforeHelloIsABadHandshake() {
        assertEquals("bad_handshake", code(new Conversation("TV").receive("{\"app\":\"x\",\"type\":\"hello\",\"version\":1}").replies.get(0)));
        assertEquals("bad_handshake", code(new Conversation("TV").receive("hello").replies.get(0)));
    }

    @Test
    public void unsupportedVersionListsOurs() {
        Conversation.Step step = new Conversation("TV").receive("{\"app\":\"nino\",\"type\":\"hello\",\"version\":7}");
        assertTrue(step.close);
        assertEquals("{\"app\":\"nino\",\"type\":\"error\",\"code\":\"version_unsupported\",\"versions\":[1]}", step.replies.get(0));
    }

    @Test
    public void showClearAndPing() {
        Conversation talk = new Conversation("TV");
        talk.receive(HELLO);
        Conversation.Step show = talk.receive("{\"app\":\"nino\",\"type\":\"show\",\"id\":3,\"text\":\"Merhaba\"}");
        assertEquals("Merhaba", show.show.text);
        Conversation.Step clear = talk.receive("{\"app\":\"nino\",\"type\":\"clear\",\"id\":3}");
        assertTrue(clear.clear);
        assertEquals(Long.valueOf(3), clear.clearId);
        Conversation.Step all = talk.receive("{\"app\":\"nino\",\"type\":\"clear\"}");
        assertTrue(all.clear);
        assertNull(all.clearId);
        Conversation.Step ping = talk.receive("{\"app\":\"nino\",\"type\":\"ping\",\"t\":1732233600000}");
        assertEquals("{\"app\":\"nino\",\"type\":\"pong\",\"t\":1732233600000}", ping.replies.get(0));
    }

    @Test
    public void unknownTypesAndBadMessagesKeepTheTalkOpen() {
        Conversation talk = new Conversation("TV");
        talk.receive(HELLO);
        Conversation.Step unknown = talk.receive("{\"app\":\"nino\",\"type\":\"sparkle\",\"x\":1}");
        assertEquals("sparkle", unknown.extension.type);
        assertFalse(unknown.close);
        assertTrue(unknown.replies.isEmpty());
        assertTrue("göstericiye yönelik olmayan tür", talk.receive("{\"app\":\"nino\",\"type\":\"pong\",\"t\":1}").isEmpty());
        Conversation.Step broken = talk.receive("{nope");
        assertEquals("bad_message", code(broken.replies.get(0)));
        assertFalse(broken.close);
        Conversation.Step noText = talk.receive("{\"app\":\"nino\",\"type\":\"show\",\"id\":1}");
        assertEquals("bad_message", code(noText.replies.get(0)));
        assertNull(noText.show);
        assertTrue(talk.isOpen());
    }

    @Test
    public void oversizedMessageCloses() {
        Conversation talk = new Conversation("TV");
        talk.receive(HELLO);
        StringBuilder big = new StringBuilder();
        while (big.length() <= Wire.MAX_MESSAGE_BYTES) big.append("xxxxxxxxxx");
        Conversation.Step step = talk.receive(big.toString());
        assertTrue(step.close);
        assertEquals("too_large", code(step.replies.get(0)));
    }

    @Test
    public void timeoutAndReplacement() {
        Conversation waiting = new Conversation("TV");
        assertTrue(waiting.helloTimedOut().close);
        assertTrue(waiting.helloTimedOut().isEmpty());

        Conversation open = new Conversation("TV");
        open.receive(HELLO);
        assertTrue(open.helloTimedOut().isEmpty());
        Conversation.Step step = open.replaced();
        assertTrue(step.close);
        assertEquals("error", type(step.replies.get(0)));
        assertEquals("replaced", code(step.replies.get(0)));
    }
}
