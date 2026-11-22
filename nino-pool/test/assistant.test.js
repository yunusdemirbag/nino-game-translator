// SPDX-License-Identifier: AGPL-3.0-only
import { test } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { makeD1 } from "./d1-shim.js";
import { handle } from "../src/worker.js";
import { askModel, usageCost } from "../src/assistant.js";
import { KNOWLEDGE } from "../src/knowledge.js";

const NOW = 1763300000;
const TOKEN = "deneme-anahtari";
const png = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==";

function setup(vars = {}, ask) {
  const env = { DB: makeD1(), EXPORT_TOKEN: TOKEN, INSTALL_SALT: "tuz", ASSISTANT_PROVIDER: "gemini", GEMINI_API_KEY: "k", ...vars };
  const calls = [];
  const fake = ask ?? (async (_env, system, messages) => { calls.push({ system, messages }); return { reply: "Merhaba! Nasıl yardımcı olayım?", report: null }; });
  const post = (body) => handle(new Request("http://pool/v1/assistant", { method: "POST", body: JSON.stringify(body) }), env, NOW, fake);
  return { env, post, calls };
}
const chat = (messages, extra = {}) => ({ v: 1, install: randomUUID(), app: "0.2.0", platform: "android", language: "tr", messages, ...extra });

test("soru modele bilgi tabanıyla gider, cevap döner", async () => {
  const { post, calls } = setup();
  const res = await post(chat([{ role: "user", text: "Samsung Q60 TV'mde görüntü titriyor, Nino yüzünden mi?" }]));
  assert.equal(res.status, 200);
  const body = await res.json();
  assert.equal(body.reply, "Merhaba! Nasıl yardımcı olayım?");
  assert.equal(body.report, null);
  assert.match(calls[0].system, /App language: tr/);
  assert.match(KNOWLEDGE, /Samsung akıllı monitörler/);
  assert.match(KNOWLEDGE, /is\.gd\/ninotvapk/);
});

test("model anahtarı yoksa yardımcı kapalı", async () => {
  const { post } = setup({ GEMINI_API_KEY: "" });
  const res = await post(chat([{ role: "user", text: "selam" }]));
  assert.equal(res.status, 503);
  const status = await handle(new Request("http://pool/v1/assistant"), { ASSISTANT_PROVIDER: "gemini" }, NOW);
  assert.deepEqual(await status.json(), { ok: true, enabled: false });
});

test("kullanıcı onaylayınca model bildirim yazar; ekran görüntüsü bildirime eklenir", async () => {
  const { post, env } = setup({}, async () => ({ reply: "Ekibe gönderdim!", report: { kind: "bug", summary: "TCL TV, subtitles not shown" } }));
  const res = await post(chat([
    { role: "user", text: "TV'de altyazı çıkmıyor", images: [{ mime: "image/png", data: png }] },
    { role: "assistant", text: "Ekibe bildireyim mi?" },
    { role: "user", text: "Evet gönder" },
  ]));
  const body = await res.json();
  assert.equal(res.status, 200);
  assert.ok(body.report);
  const list = await (await handle(new Request("http://pool/v1/reports", { headers: { authorization: `Bearer ${TOKEN}` } }), env, NOW)).json();
  assert.equal(list.reports.length, 1);
  assert.match(list.reports[0].text, /\[Yardımcı · Hata\] TCL TV/);
  assert.equal(list.reports[0].images, 1);
});

test("bozuk sohbet reddedilir; kurulum başına günlük sınır", async () => {
  const { post } = setup({ ASSISTANT_PER_INSTALL: "3" });
  assert.equal((await post(chat([{ role: "assistant", text: "x" }]))).status, 400);
  assert.equal((await post(chat([{ role: "user", text: "x", images: [{ mime: "text/html", data: "PGI+" }] }]))).status, 400);
  const install = randomUUID();
  for (let i = 0; i < 3; i++) assert.equal((await post(chat([{ role: "user", text: "soru" }], { install }))).status, 200);
  assert.equal((await post(chat([{ role: "user", text: "soru" }], { install }))).status, 429);
});

test("Gemini isteği resimleri ve JSON şemasını taşır", async () => {
  let sent;
  const fetcher = async (url, init) => { sent = { url, body: JSON.parse(init.body), headers: init.headers };
    return new Response(JSON.stringify({ candidates: [{ content: { parts: [{ text: "{\"reply\":\"Tamam\",\"report\":null}" }] } }] })); };
  const answer = await askModel({ ASSISTANT_PROVIDER: "gemini", GEMINI_API_KEY: "k" }, "sys", [{ role: "user", text: "bak", images: [{ mime: "image/png", data: png }] }], fetcher);
  assert.equal(answer.reply, "Tamam");
  assert.match(sent.url, /gemini-flash-lite-latest:generateContent/);
  assert.equal(sent.headers["x-goog-api-key"], "k");
  assert.equal(sent.body.contents[0].parts[0].inlineData.mimeType, "image/png");
  assert.equal(sent.body.generationConfig.responseMimeType, "application/json");
});

test("aynı ilk soru hazır cevaptan verilir; modele ikinci kez gitmez", async () => {
  const { post, calls } = setup();
  const first = await post(chat([{ role: "user", text: "Vestel TV'mde Nino açılıyor ama ses gidiyor" }]));
  assert.equal(first.status, 200);
  const again = await post(chat([{ role: "user", text: "  vestel tv'mde nino AÇILIYOR ama ses gidiyor " }]));
  assert.equal((await again.json()).reply, "Merhaba! Nasıl yardımcı olayım?");
  assert.equal(calls.length, 1);
  // Başka dilde, resimli ya da devam eden sohbette hazır cevap kullanılmaz.
  await post(chat([{ role: "user", text: "Vestel TV'mde Nino açılıyor ama ses gidiyor" }], { language: "en" }));
  await post(chat([{ role: "user", text: "Vestel TV'mde Nino açılıyor ama ses gidiyor", images: [{ mime: "image/png", data: png }] }]));
  await post(chat([{ role: "user", text: "selam" }, { role: "assistant", text: "Merhaba" }, { role: "user", text: "Vestel TV'mde Nino açılıyor ama ses gidiyor" }]));
  assert.equal(calls.length, 4);
});

test("günlük harcama sınırı aşılınca yoğun der", async () => {
  const { post } = setup({ ASSISTANT_DAILY_USD: "0.01" }, async () => ({ reply: "Tamam", report: null, cost: 6000 }));
  assert.equal((await post(chat([{ role: "user", text: "bir" }]))).status, 200);
  assert.equal((await post(chat([{ role: "user", text: "iki" }]))).status, 200);
  // Tavan dolu: model çağrılmaz, hata yerine "şu an yoğunum" hazır cevabı (robot takılmaz).
  const res = await post(chat([{ role: "user", text: "üç" }]));
  assert.equal(res.status, 200);
  assert.match((await res.json()).reply, /çok soru geliyor/);
  // Hazır cevap sınır aşılsa da verilir (ücretsiz).
  assert.equal((await post(chat([{ role: "user", text: "bir" }]))).status, 200);
});

test("Haiku maliyeti token kullanımından hesaplanır", () => {
  const micro = usageCost("claude-haiku-5-5", { input_tokens: 1000, output_tokens: 400, cache_read_input_tokens: 15000, cache_creation_input_tokens: 0 });
  assert.equal(micro, 100 + 200 + 150);
  assert.equal(usageCost("bilinmeyen", {}), 5000);
});
