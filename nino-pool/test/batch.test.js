// SPDX-License-Identifier: AGPL-3.0-only
import { test } from "node:test";
import assert from "node:assert/strict";
import { makeD1 } from "./d1-shim.js";
import { batchTranslate, batchChain, BATCH_LIMITS } from "../src/batch.js";
import { lineKey } from "../src/key.js";

const NOW = 1763300000;
const ENV = { TRANSLATE_ENGINE: "free", FREE_CHAIN: "gemini:g1,groq:q", GEMINI_API_KEY: "g", GROQ_API_KEY: "q", TRANSLATE_GAMES: "grand-theft-auto-vi,mafia" };

async function addLine(db, game, text, installs = 1) {
  await db.prepare("INSERT INTO lines (game, key, text, seen, installs, first_seen, last_seen) VALUES (?, ?, ?, 1, ?, 0, 0)")
    .bind(game, await lineKey(text), text, installs).run();
}

test("toplu çeviri: zincirdeki Gemini modelleri, BATCH_CHAIN ile değişir", () => {
  assert.deepEqual(batchChain(ENV).map((c) => c.id), ["gemini:g1"]);
  assert.deepEqual(batchChain({ ...ENV, BATCH_CHAIN: "groq:q" }).map((c) => c.id), ["groq:q"]);
});

test("toplu çeviri: çevrilmemiş satırlar partiyle çevrilir, çok oyunculu önce, çöp işaretlenir, izinsiz oyun alınmaz", async () => {
  const db = makeD1();
  await addLine(db, "grand-theft-auto-vi", "Grab the bag, the cops are close.");
  await addLine(db, "grand-theft-auto-vi", "Where did you park the boat?", 3);
  await addLine(db, "grand-theft-auto-vi", "RESTORE ALL (A) RESTORE DEFAULT");
  await addLine(db, "red-dead-redemption-2", "Howdy, partner.");
  const calls = [];
  const ask = async (_env, lang, lines, _ctx, opts) => {
    calls.push({ lines, opts });
    return { texts: lines.map((l, i) => (i === 1 ? null : `TR ${l}`)), cost: 0 };
  };
  const result = await batchTranslate(db, { ...ENV, DB: db }, NOW, { ask });
  assert.equal(calls.length, 1);
  assert.deepEqual(calls[0].lines, ["Where did you park the boat?", "Grab the bag, the cops are close."]);
  assert.equal(calls[0].opts.partial, true);
  assert.equal(calls[0].opts.timeout, BATCH_LIMITS.timeoutMs);
  assert.deepEqual(result, { translated: 1, junk: 1, chunks: 1, failed: 0 });
  const rows = db.raw.prepare("SELECT source, text, tier FROM translations ORDER BY source").all().map((r) => [r.source, r.text, r.tier]);
  assert.deepEqual(rows, [["RESTORE ALL (A) RESTORE DEFAULT", "", 0], ["Where did you park the boat?", "TR Where did you park the boat?", 1]]);
  // İkinci turda yalnız çevrilemeyen satır kalır.
  calls.length = 0;
  await batchTranslate(db, { ...ENV, DB: db }, NOW + 1800, { ask: async (_e, _l, lines) => ({ texts: lines.map((l) => `TR ${l}`) }) });
  assert.equal(db.raw.prepare("SELECT COUNT(*) n FROM translations WHERE text <> ''").get().n, 2);
});

test("toplu çeviri: servisler doluysa tur erken biter", async () => {
  const db = makeD1();
  for (let i = 0; i < BATCH_LIMITS.size * 4; i++) await addLine(db, "mafia-the-old-country", `Line number ${"abcdefghijklmnopqrstuvwxyz"[i % 26]} for the family ${i}.`);
  let asked = 0;
  const result = await batchTranslate(db, { ...ENV, DB: db }, NOW, { ask: async () => { asked++; return { texts: null, cost: 0 }; } });
  assert.equal(asked, 2);
  assert.equal(result.stopped, "quota");
});
