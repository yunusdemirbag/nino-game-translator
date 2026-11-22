// SPDX-License-Identifier: AGPL-3.0-only
import { test } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { readFileSync } from "node:fs";
import { makeD1 } from "./d1-shim.js";
import { handle } from "../src/worker.js";
import { cleanDiag, compareVersions, DIAG_LIMITS, DIAG_TEXT, diagText, summarizeDiagnoses, pruneDiag } from "../src/diag.js";
import { localDayStart } from "../src/stats.js";

const NOW = 1763303700;
const TOKEN = "panel-anahtari";
const freshEnv = (extra = {}) => ({ DB: makeD1(), EXPORT_TOKEN: TOKEN, INSTALL_SALT: "tuz", STATS_GITHUB: "0", ...extra });
const auth = { authorization: `Bearer ${TOKEN}` };
const post = (env, body, now = NOW) => handle(new Request("http://pool/v1/events", { method: "POST", body: JSON.stringify(body) }), env, now);
const batch = (events, ctx = {}, install = randomUUID()) =>
  ({ v: 1, batch: randomUUID(), install, ctx: { platform: "mac", app: "4.0.0", os: "macOS 27.0", device: "Mac16,1", ...ctx }, events });
const diag = (rule, cause, extra = {}) => ({ k: "diag", t: NOW, rule, cause, sev: "warn", ...extra });
const stats = async (env, now = NOW) => (await handle(new Request("http://pool/v1/events/stats?days=7", { headers: auth }), env, now)).json();

test("teşhis süzülür: serbest metin, yol, adres ve ad gitmez", () => {
  const d = cleanDiag({
    rule: "ps5.no_return", cause: "Ağ gitti 192.168.0.5", sev: "kritik",
    state: { net: "wifi", memMB: 410, ok: true, path: "/Users/yunus/x", "bad key": 1, msg: "connection refused", big: 1e15 },
    trail: [[-30, "net.down"], [-20, "ps5.retry", 2], [5, "gelecek"], [-10, "Hata: /Users/yunus"], "çöp", [-5, "ps5.drop", "x"]],
    tv: { brand: "androidtv", model: "Yunus'un TV'si", app: "4.0.0" }, game: "../etc", ver: { core: "1.0.0", "a b": "1" },
  });
  assert.equal(d.rule, "ps5.no_return");
  assert.equal(d.cause, "unknown");
  assert.equal(d.sev, "warn");
  assert.deepEqual(d.state, { net: "wifi", memMB: 410, ok: true });
  assert.deepEqual(d.trail, [[-30, "net.down"], [-20, "ps5.retry", 2], [-5, "ps5.drop"]]);
  assert.deepEqual(d.tv, { brand: "androidtv", app: "4.0.0" });
  assert.equal(d.game, "");
  assert.deepEqual(d.ver, { core: "1.0.0" });
  assert.equal(cleanDiag({ rule: "Kötü Kural" }), null);
});

test("sürüm karşılaştırma sayıca: 4.10 > 4.9, ön sürüm daha küçük", () => {
  assert.ok(compareVersions("4.10.0", "4.9.2") > 0);
  assert.ok(compareVersions("4.0.0", "4.0.0-beta.2") > 0);
  assert.ok(compareVersions("4.0.0-beta.10", "4.0.0-beta.9") > 0);
  assert.equal(compareVersions("4.0", "4.0.0"), 0);
});

test("teşhis cümleleri tarif senaryolarındaki her kural ve sebebi kapsar", () => {
  const fx = JSON.parse(readFileSync(new URL("./fixtures/diag-scenarios.json", import.meta.url), "utf8"));
  for (const s of fx.scenarios) for (const e of s.expect) {
    assert.ok(DIAG_TEXT[e.rule], e.rule);
    assert.ok(DIAG_TEXT[e.rule][e.cause], `${e.rule} ${e.cause}`);
  }
  assert.equal(diagText("tr.errors", "unknown"), "Sebep belirlenemedi.");
});

test("imzaya göre gruplanır; panelde en sık, yeni çıkan sorun; örnekte kurulum kimliği yok", async () => {
  const env = freshEnv();
  const a = randomUUID();
  const b = randomUUID();
  const res = await (await post(env, batch([
    diag("ps5.no_return", "network_lost", { state: { net: "wifi" }, trail: [[-30, "net.down"]], game: "gta-vi" }),
    diag("tv.flapping", "write_error", { tv: { brand: "androidtv", model: "TCL 98U95A", app: "4.0.0" } }),
    { k: "launch", t: NOW },
  ], {}, a))).json();
  assert.equal(res.accepted, 3);
  await post(env, batch([diag("ps5.no_return", "timeout")], {}, b));
  const s = await stats(env);
  const top = s.diag.top;
  assert.equal(s.diag.total, 3);
  assert.deepEqual([top[0].rule, top[0].platform, top[0].model, top[0].n, top[0].installs], ["ps5.no_return", "mac", "Mac16,1", 2, 2]);
  assert.deepEqual(top[0].causes, { network_lost: 1, timeout: 1 });
  const tv = top.find((g) => g.rule === "tv.flapping");
  assert.equal(tv.model, "TCL 98U95A"); // TV kurallarında imza TV modeliyle
  assert.equal(tv.text, "TV'ye gönderim tekrar tekrar başarısız oldu.");
  assert.equal(s.diag.fresh.length, 2);
  // İki gün sonra artık "yeni" değil.
  assert.equal((await stats(env, NOW + 3 * 86400)).diag.fresh.length, 0);
  const dump = JSON.stringify(env.DB.raw.prepare("SELECT * FROM diag_samples").all())
    + JSON.stringify(env.DB.raw.prepare("SELECT * FROM diag_daily").all()) + JSON.stringify(env.DB.raw.prepare("SELECT * FROM diag_groups").all());
  assert.equal(dump.includes(a) || dump.includes(b), false);
});

test("sınırlar: kurulum başına günde 10, kural başına 3; aşanlar sessizce atılır, öbür olaylar yazılır; örnek imza başına 3", async () => {
  const env = freshEnv();
  const who = randomUUID();
  const res = await (await post(env, batch([
    ...Array.from({ length: 5 }, () => diag("tr.slow", "provider_slow")),
    { k: "launch", t: NOW },
  ], {}, who))).json();
  assert.equal(res.accepted, 1 + DIAG_LIMITS.perRuleDay);
  assert.equal(res.dropped, 5 - DIAG_LIMITS.perRuleDay);
  const rules = ["ocr.silent", "tr.errors", "app.hang", "pack.download"];
  for (const r of rules) await post(env, batch([diag(r, "unknown"), diag(r, "unknown"), diag(r, "unknown")], {}, who));
  const n = env.DB.raw.prepare("SELECT SUM(n) AS n FROM diag_daily").get().n;
  assert.equal(n, DIAG_LIMITS.perInstallDay);
  // Örnekler: aynı imzada başka kurulumlardan da gelse günde en çok 3.
  for (let i = 0; i < 4; i++) await post(env, batch([diag("tr.slow", "network_slow")]));
  assert.equal(env.DB.raw.prepare("SELECT COUNT(*) AS n FROM diag_samples WHERE rule = 'tr.slow'").get().n, DIAG_LIMITS.samplesPerSignatureDay);
  // Ertesi gün kurulumun sınırı açılır.
  const next = await (await post(env, batch([diag("tr.slow", "provider_slow")], {}, who), NOW + 86400)).json();
  assert.equal(next.accepted, 1);
});

test("sürüm sonrası artış: açılış başına oran 2 katı geçerse uyarı (sürümler sayıca sıralanır)", async () => {
  const env = freshEnv();
  const launches = (app, n) => Array.from({ length: n }, () => ({ k: "launch", t: NOW }));
  // 4.9.0: 40 açılış, 1 bildirim; 4.10.0: 30 açılış, 4 bildirim → artış. Her bildirim ayrı kurulumdan (sınır yok).
  await post(env, batch(launches("4.9.0", 40), { app: "4.9.0" }));
  await post(env, batch(launches("4.10.0", 30), { app: "4.10.0" }));
  await post(env, batch([diag("ocr.stalled", "ocr_hang")], { app: "4.9.0" }));
  for (let i = 0; i < 4; i++) await post(env, batch([diag("ocr.stalled", "ocr_hang")], { app: "4.10.0" }));
  // Az açılan sürüm (5 açılış) karşılaştırmaya girmez.
  await post(env, batch(launches("4.11.0-beta.1", 5), { app: "4.11.0-beta.1" }));
  const r = (await stats(env)).diag.regressions;
  assert.equal(r.length, 1);
  assert.deepEqual([r[0].platform, r[0].rule, r[0].newApp, r[0].oldApp, r[0].nNew, r[0].nOld], ["mac", "ocr.stalled", "4.10.0", "4.9.0", 4, 1]);
  assert.ok(r[0].factor > 5);
});

test("günlük özet sayfası ve yardımcı modelle kısa Türkçe özet (yalnız değişen gruplar)", async () => {
  const env = freshEnv();
  await post(env, batch([diag("ps5.no_return", "ps5_standby", { state: { ps5: "down" }, trail: [[-200, "ps5.drop"]] })]));
  const day = new Date((localDayStart(NOW) + 3 * 3600) * 1000).toISOString().slice(0, 10);
  assert.equal((await handle(new Request(`http://pool/v1/diagnoses/daily?day=${day}`), env, NOW)).status, 401);
  let d = await (await handle(new Request(`http://pool/v1/diagnoses/daily?day=${day}`, { headers: auth }), env, NOW)).json();
  assert.equal(d.ready, true);
  assert.equal(d.total, 1);
  assert.equal(d.groups[0].title, "PS5 koptu, geri gelmedi");
  assert.equal(d.groups[0].causes[0].text, "PS5 dinlenme moduna geçti.");
  assert.deepEqual(d.groups[0].samples[0].trail, [[-200, "ps5.drop"]]);
  assert.equal(d.groups[0].summary, "");

  const asked = [];
  const ask = async (_env, system, messages) => {
    asked.push(JSON.parse(messages[0].text));
    return { reply: "PS5 oyun sırasında dinlenmeye geçiyor. Güç ayarlarında Remote Play açık kalmalı." };
  };
  const sum = await (await handle(new Request("http://pool/v1/diagnoses/summarize", { method: "POST", headers: auth }), env, NOW, ask)).json();
  assert.deepEqual([sum.summarized, sum.failed], [1, 0]);
  assert.equal(asked[0].kural, "ps5.no_return");
  assert.equal(asked[0].ornekler[0].state.ps5, "down");
  d = await (await handle(new Request(`http://pool/v1/diagnoses/daily?day=${day}`, { headers: auth }), env, NOW)).json();
  assert.match(d.groups[0].summary, /dinlenmeye/);
  // Değişmeyen grup yeniden özetlenmez; yeni bildirim gelince yine özetlenir.
  assert.deepEqual(await summarizeDiagnoses(env.DB, env, NOW, ask), { summarized: 0, failed: 0 });
  await post(env, batch([diag("ps5.no_return", "ps5_standby")]));
  assert.equal((await summarizeDiagnoses(env.DB, env, NOW, ask)).summarized, 1);
  // Model hata verirse sayfa yine çalışır.
  await post(env, batch([diag("tr.slow", "pool_slow")]));
  assert.equal((await summarizeDiagnoses(env.DB, env, NOW, async () => { throw new Error("hak doldu"); })).failed, 1);

  const page = await (await handle(new Request("http://pool/teshis"), env, NOW)).text();
  assert.match(page, /Otomatik teşhis/);
});

test("tablolar yoksa teşhis atılır ama öbür olaylar yazılır; bakım eski örnekleri ve kurulum özetini siler", async () => {
  const env = freshEnv();
  for (const t of ["diag_daily", "diag_seen", "diag_samples", "diag_groups"]) env.DB.raw.exec(`DROP TABLE ${t}`);
  const res = await (await post(env, batch([diag("tr.slow", "pool_slow"), { k: "launch", t: NOW }]))).json();
  assert.equal(res.ok, true);
  assert.equal(res.accepted, 1);
  assert.equal((await stats(env)).diag, null);

  const env2 = freshEnv();
  await post(env2, batch([diag("tr.slow", "pool_slow")]));
  await pruneDiag(env2.DB, NOW + 31 * 86400);
  const left = (t) => env2.DB.raw.prepare(`SELECT COUNT(*) AS n FROM ${t}`).get().n;
  assert.equal(left("diag_seen"), 0);
  assert.equal(left("diag_samples"), 0);
  assert.equal(left("diag_daily"), 1);
});

test("uzaktan teşhis ayarı: kapatılan kurallar ve eşikler /v1/config'te", async () => {
  const env = freshEnv({ TELEMETRY_DIAG_OFF: "ocr.silent, Kötü", TELEMETRY_DIAG_LIMITS: '{"tr.slow.p90Ms":4000,"x":"y"}' });
  const c = await (await handle(new Request("http://pool/v1/config"), env, NOW)).json();
  assert.deepEqual(c.telemetry.diag, { off: ["ocr.silent"], limits: { "tr.slow.p90Ms": 4000 } });
});
