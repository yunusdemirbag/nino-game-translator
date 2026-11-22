// SPDX-License-Identifier: AGPL-3.0-only
import { test } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { makeD1 } from "./d1-shim.js";
import { askFree, freeChain, PAUSE_SECONDS } from "../src/free.js";
import { handleTranslate, reviewTranslations } from "../src/translate.js";

const NOW = 1763300000;
const json = (status, body) => new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });
const gemini = (texts) => json(200, { candidates: [{ content: { parts: [{ text: JSON.stringify({ translations: texts }) }] } }] });
const openai = (texts) => json(200, { choices: [{ message: { content: JSON.stringify({ translations: texts }) } }] });

test("zincir: anahtarı olmayan servis atlanır", () => {
  const env = { FREE_CHAIN: "gemini:g-flash, mistral:mistral-small, groq:llama", GEMINI_API_KEY: "g", GROQ_API_KEY: "q" };
  assert.deepEqual(freeChain(env).map((c) => c.id), ["gemini:g-flash", "groq:llama"]);
});

test("hakkı dolan servis atlanır, sıradaki çevirir; süre dolunca yeniden denenir", async () => {
  const env = { FREE_CHAIN: "gemini:g-flash,mistral:m-small", GEMINI_API_KEY: "g", MISTRAL_API_KEY: "m", DB: makeD1() };
  const calls = [];
  let geminiFull = true;
  const fetcher = async (url, init) => {
    calls.push(url);
    const body = JSON.parse(init.body);
    if (url.includes("googleapis")) {
      assert.equal(init.headers["x-goog-api-key"], "g");
      assert.ok(body.systemInstruction.parts[0].text.includes("Turkish"));
      return geminiFull ? json(429, { error: { message: "quota" } }) : gemini(["Arabaya bin!"]);
    }
    assert.equal(init.headers.authorization, "Bearer m");
    return openai(["Arabaya bin lan!"]);
  };
  let answer = await askFree(env, "tr", ["Get in the car!"], [], { now: NOW, fetcher });
  assert.deepEqual(answer, { texts: ["Arabaya bin lan!"], cost: 0, model: "mistral:m-small" });
  // Gemini durduruldu: ikinci istekte hiç sorulmaz.
  answer = await askFree(env, "tr", ["Get in the car!"], [], { now: NOW + 60, fetcher });
  assert.equal(calls.filter((u) => u.includes("googleapis")).length, 1);
  // Süre dolunca yeniden denenir.
  geminiFull = false;
  answer = await askFree(env, "tr", ["Get in the car!"], [], { now: NOW + PAUSE_SECONDS + 1, fetcher });
  assert.equal(answer.model, "gemini:g-flash");
});

test("bütün servisler doluysa çeviri yok, para harcanmaz", async () => {
  const env = { FREE_CHAIN: "gemini:g-full", GEMINI_API_KEY: "g", DB: makeD1() };
  const answer = await askFree(env, "tr", ["Hi."], [], { now: NOW, fetcher: async () => json(429, {}) });
  assert.deepEqual(answer, { texts: null, cost: 0 });
});

test("ücretsiz düzen: Claude'a gitmez, günlük sınır onu durdurmaz, gözden geçirme kapalı", async () => {
  const db = makeD1();
  const env = { DB: db, INSTALL_SALT: "t", TRANSLATE_ENGINE: "free", FREE_CHAIN: "gemini:g-live", GEMINI_API_KEY: "g",
    ANTHROPIC_API_KEY: "k", CLAUDE_ENABLED: "0", TRANSLATE_DAILY_USD: "0", TRANSLATE_GAMES: "*" };
  const realFetch = globalThis.fetch;
  globalThis.fetch = async () => gemini(["Para nerede?"]);
  try {
    const { askLive } = await import("../src/translate.js");
    const result = await handleTranslate(db, env, { v: 1, install: randomUUID(), lang: "tr", game: "gta-vi", lines: ["Where's the money?"] }, NOW, askLive);
    assert.equal(result.body.translations[0].text, "Para nerede?");
    assert.equal(result.body.limited, undefined);
  } finally {
    globalThis.fetch = realFetch;
  }
  const review = await reviewTranslations(db, env, NOW + 3600, async () => { throw new Error("Claude çağrılmamalı"); });
  assert.deepEqual(review, { reviewed: 0, changed: 0, cost: 0 });
});

test("DeepL: ücretsiz anahtar api-free adresine gider; aylık hak dolunca (456) sıradaki çevirir", async () => {
  const env = { FREE_CHAIN: "deepl:free,groq:llama", DEEPL_API_KEY: "abc:fx", GROQ_API_KEY: "q", DB: makeD1() };
  let full = false;
  const fetcher = async (url, init) => {
    if (url.includes("deepl")) {
      assert.equal(url, "https://api-free.deepl.com/v2/translate");
      assert.equal(init.headers.authorization, "DeepL-Auth-Key abc:fx");
      const body = JSON.parse(init.body);
      assert.equal(body.target_lang, "TR");
      assert.equal(body.context, "Lucia, wait.");
      return full ? json(456, { message: "Quota exceeded" }) : json(200, { translations: body.text.map((t) => ({ text: `TR ${t}` })) });
    }
    return openai(["Bekle!"]);
  };
  let answer = await askFree(env, "tr", ["Wait!"], ["Lucia, wait."], { now: NOW, fetcher });
  assert.deepEqual(answer, { texts: ["TR Wait!"], cost: 0, model: "deepl:free" });
  full = true;
  answer = await askFree(env, "tr", ["Wait!"], ["Lucia, wait."], { now: NOW + 1, fetcher });
  assert.equal(answer.model, "groq:llama");
});

test("Workers AI: günlük nöron sınırına yaklaşınca çağrılmaz (ücretli planda para yazmasın)", async () => {
  const { workersAiEstimate } = await import("../src/free.js");
  const runs = [];
  const AI = { async run(model, input) { runs.push([model, input]); return { translated_text: `TR ${input.text}` }; } };
  const line = "Stay close to the boat and watch for the cops.";
  const cap = workersAiEstimate([line]) * 2.5;
  const env = { FREE_CHAIN: "workersai:@cf/meta/m2m100-1.2b", AI, WORKERS_AI_DAILY_NEURONS: String(cap), DB: makeD1() };
  for (let i = 0; i < 2; i++) {
    const answer = await askFree(env, "tr", [line], [], { now: NOW + 7000 + i });
    assert.deepEqual(answer.texts, [`TR ${line}`]);
  }
  assert.deepEqual(runs[0], ["@cf/meta/m2m100-1.2b", { text: line, source_lang: "english", target_lang: "turkish" }]);
  // Üçüncüsü sınırı aşar: çağrılmaz.
  const answer = await askFree(env, "tr", [line], [], { now: NOW + 7002 });
  assert.equal(answer.texts, null);
  assert.equal(runs.length, 2);
  // Veritabanı yoksa hiç çağrılmaz.
  const noDb = await askFree({ ...env, DB: undefined, FREE_CHAIN: "workersai:@cf/x" }, "tr", [line], [], { db: null, now: NOW });
  assert.equal(noDb.texts, null);
  assert.equal(runs.length, 2);
});

test("kaldırılmış model (410) uzun süre atlanır", async () => {
  const env = { FREE_CHAIN: "nvidia:gone-model,groq:ok", NVIDIA_API_KEY: "n", GROQ_API_KEY: "q", DB: makeD1() };
  let gone = 0;
  const fetcher = async (url) => (url.includes("nvidia") ? (gone++, json(410, { title: "Gone" })) : openai(["Tamam."]));
  await askFree(env, "tr", ["Okay."], [], { now: NOW + 9000, fetcher });
  await askFree(env, "tr", ["Okay."], [], { now: NOW + 9000 + PAUSE_SECONDS + 5, fetcher });
  assert.equal(gone, 1);
});

test("hak doldu cevabındaki bekleme süresi kadar atlanır (Gemini retryDelay, retry-after)", async () => {
  const { retrySeconds } = await import("../src/free.js");
  assert.equal(retrySeconds(new Headers(), '{"error":{"details":[{"retryDelay": "6s"}]}}'), 6);
  assert.equal(retrySeconds(new Headers({ "retry-after": "12" }), "{}"), 12);
  assert.equal(retrySeconds(new Headers(), "{}"), null);
  const env = { FREE_CHAIN: "gemini:g-rpm,groq:ok", GEMINI_API_KEY: "g", GROQ_API_KEY: "q", DB: makeD1() };
  let asked = 0;
  const fetcher = async (url) => {
    if (url.includes("googleapis")) { asked++; return json(429, { error: { details: [{ retryDelay: "6s" }] } }); }
    return openai(["Tamam."]);
  };
  await askFree(env, "tr", ["Okay."], [], { now: NOW + 20000, fetcher });
  await askFree(env, "tr", ["Okay."], [], { now: NOW + 20003, fetcher });
  assert.equal(asked, 1);
  await askFree(env, "tr", ["Okay."], [], { now: NOW + 20010, fetcher });
  assert.equal(asked, 2);
});

test("günlük satır sınırı: DeepL'in aylık hakkı bir günde bitmesin", async () => {
  const env = { FREE_CHAIN: "deepl:free,groq:ok", DEEPL_API_KEY: "d:fx", GROQ_API_KEY: "q", FREE_DAILY_LINES: "deepl:free=2", DB: makeD1() };
  const fetcher = async (url, init) => (url.includes("deepl")
    ? json(200, { translations: JSON.parse(init.body).text.map((t) => ({ text: `TR ${t}` })) }) : openai(["Tamam."]));
  const used = [];
  for (let i = 0; i < 3; i++) used.push((await askFree(env, "tr", ["Okay."], [], { now: NOW + 30000 + i, fetcher })).model);
  assert.deepEqual(used, ["deepl:free", "deepl:free", "groq:ok"]);
});

test("günlük dolar sınırı: ücretli OpenRouter modeli sınıra gelince çağrılmaz", async () => {
  const env = { FREE_CHAIN: "openrouter:paid", OPENROUTER_API_KEY: "o", FREE_DAILY_USD: "openrouter:paid=0.5", DB: makeD1() };
  let calls = 0;
  const fetcher = async (url, init) => {
    calls++;
    assert.equal(JSON.parse(init.body).usage.include, true);
    return json(200, { choices: [{ message: { content: JSON.stringify({ translations: ["Tamam."] }) } }], usage: { cost: 0.3 } });
  };
  const got = [];
  for (let i = 0; i < 3; i++) got.push((await askFree(env, "tr", ["Okay."], [], { now: NOW + 40000 + i, fetcher }))?.model ?? null);
  assert.deepEqual(got, ["openrouter:paid", "openrouter:paid", null]);
  assert.equal(calls, 2);
});

test("ücretli servislerin toplamı günlük sınırı aşmaz; ücretsiz modeller sayılmaz", async () => {
  const env = { FREE_CHAIN: "openrouter:a,openrouter:b,openrouter:c:free", OPENROUTER_API_KEY: "o", FREE_PAID_DAILY_USD: "0.5", DB: makeD1() };
  const fetcher = async (url, init) => {
    const { model } = JSON.parse(init.body);
    if (model === "a") return json(429, {});
    return json(200, { choices: [{ message: { content: JSON.stringify({ translations: ["Tamam."] }) } }], usage: { cost: model === "b" ? 0.3 : 0 } });
  };
  const got = [];
  for (let i = 0; i < 3; i++) got.push((await askFree(env, "tr", ["Okay."], [], { now: NOW + 50000 + i * 1000, fetcher }))?.model ?? null);
  assert.deepEqual(got, ["openrouter:b", "openrouter:b", "openrouter:c:free"]);
});
