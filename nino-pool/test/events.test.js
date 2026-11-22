// SPDX-License-Identifier: AGPL-3.0-only
import { test } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { readFileSync } from "node:fs";
import { gzipSync } from "node:zlib";
import { makeD1 } from "./d1-shim.js";
import { handle } from "../src/worker.js";
import { MS_EDGES, S_EDGES, bucketOf, percentile, EVENT_LIMITS, pruneEvents } from "../src/events.js";
import { localDayStart } from "../src/stats.js";

const FIXTURE = JSON.parse(readFileSync(new URL("./fixtures/events-v1.json", import.meta.url), "utf8"));
const NOW = 1763303700; // örnek gövdedeki son olaydan biraz sonra
const TOKEN = "panel-anahtari";
const freshEnv = (extra = {}) => ({ DB: makeD1(), EXPORT_TOKEN: TOKEN, INSTALL_SALT: "tuz", STATS_GITHUB: "0", ...extra });
const clone = (v) => JSON.parse(JSON.stringify(v));

function post(env, body, { now = NOW, gzip = false, headers = {} } = {}) {
  const raw = typeof body === "string" ? body : JSON.stringify(body);
  const data = gzip ? gzipSync(Buffer.from(raw)) : raw;
  return handle(new Request("http://pool/v1/events", {
    method: "POST", body: data,
    headers: { "content-type": "application/json", ...(gzip ? { "content-encoding": "gzip" } : {}), ...headers },
  }), env, now);
}
const stats = async (env, now = NOW, days = 7) =>
  (await handle(new Request(`http://pool/v1/events/stats?days=${days}`, { headers: { authorization: `Bearer ${TOKEN}` } }), env, now)).json();
const batchOf = (events, ctx = {}, install = randomUUID()) =>
  ({ v: 1, batch: randomUUID(), install, ctx: { platform: "mac", app: "4.0.0", ...ctx }, events });

test("kovalar ve yüzdelik: sınır kovaya dahil, ara değer, son kova en büyük değere kadar", () => {
  assert.equal(MS_EDGES.length, 18);
  assert.equal(bucketOf(0, MS_EDGES), 0);
  assert.equal(bucketOf(5, MS_EDGES), 0);
  assert.equal(bucketOf(6, MS_EDGES), 1);
  assert.equal(bucketOf(10000, MS_EDGES), 17);
  assert.equal(bucketOf(10001, MS_EDGES), 18);
  assert.equal(bucketOf(3580, S_EDGES), 5);
  // 100 değer, hepsi 100–150 ms kovasında: p50 ≈ 125.
  const counts = new Array(19).fill(0);
  counts[bucketOf(120, MS_EDGES)] = 100;
  assert.equal(percentile(counts, MS_EDGES, 150, 0.5), 125);
  // En büyük değer kova sınırından küçükse üst sınır odur.
  assert.equal(percentile(counts, MS_EDGES, 130, 1), 130);
  // Son kova: 10 s üstü, en büyük 20 s.
  const tail = new Array(19).fill(0);
  tail[18] = 2;
  assert.equal(percentile(tail, MS_EDGES, 20000, 0.5), 15000);
  assert.equal(percentile(new Array(19).fill(0), MS_EDGES, 0, 0.5), null);
});

test("örnek gövde alınır; panelde sayılar, yüzdelikler, en sık hatalar ve son çökme görünür", async () => {
  const env = freshEnv();
  const res = await post(env, FIXTURE);
  assert.equal(res.status, 200);
  assert.equal(res.headers.get("access-control-allow-origin"), "*");
  const body = await res.json();
  assert.equal(body.ok, true);
  assert.equal(body.accepted, FIXTURE.events.length);
  assert.equal(body.dropped, 0);
  assert.deepEqual(body.config, { enabled: true, sample: 1, maxPerDay: 1000, flushSeconds: 600, diag: { off: [], limits: {} } });

  assert.equal((await handle(new Request("http://pool/v1/events/stats"), env, NOW)).status, 401);
  const s = await stats(env);
  assert.equal(s.ready, true);
  assert.equal(s.totals.launches, 1);
  assert.equal(s.totals.sessions, 1);
  assert.equal(s.totals.crashes, 1);
  assert.equal(s.totals.errors, 3);
  assert.equal(s.totals.lines, 412);
  assert.equal(s.totals.ps5Ok, 1);
  assert.equal(s.totals.ps5Fail, 1);
  assert.equal(s.totals.ps5Rate, 0.5);
  assert.equal(s.totals.tvRate, 1);
  assert.equal(s.totals.errorsPer100, 300);
  assert.equal(s.totals.crashFree, 0);
  // Çökme, çöken sürümün (ver 3.9.0) altına sayılır; yeniden açılan 4.0.0'ın çökmesiz oranını bozmaz.
  assert.deepEqual(s.versions.map((v) => [v.platform, v.app, v.crashes]), [["mac", "4.0.0", 0], ["mac", "3.9.0", 1]]);
  assert.equal(s.versions[0].crashFree, 1);
  assert.deepEqual(s.senderTv, [{ brand: "androidtv", n: 1 }]);

  const problem = (kind, code) => s.problems.find((p) => p.kind === kind && p.code === code);
  assert.equal(problem("error", "tr.provider.http").n, 3);
  assert.deepEqual(problem("error", "tr.provider.http").platforms, { mac: 3 });
  assert.equal(problem("crash", "SIGSEGV").n, 1);
  assert.equal(problem("ps5_connect", "ps5.session.timeout").n, 1);
  assert.equal(problem("ps5_drop", "network_lost").n, 1);
  assert.equal(problem("tv_drop", "timeout").n, 1);
  assert.equal(s.problems.some((p) => p.code === "ok"), false);

  const t = (metric, platform = "*") => s.timings.find((x) => x.metric === metric && x.platform === platform);
  assert.equal(t("ocr").n, 6);
  assert.equal(t("ocr", "mac").n, 6);
  assert.equal(t("tr.total").n, 4);
  assert.ok(t("tr.total").p50 > 200 && t("tr.total").p50 <= 750, `p50 ${t("tr.total").p50}`);
  assert.equal(t("tr.total").max, 900);
  assert.ok(t("tr.total").p99 <= 900);
  assert.equal(t("tr.provider:deepl").n, 2);
  assert.equal(t("ps5.connect").n, 1); // yalnız başarılı bağlantının süresi
  assert.equal(t("ps5.connect").max, 2840);
  assert.equal(t("tv.connect").n, 1);
  assert.equal(t("session").unit, "s");
  assert.equal(t("session").max, 3580);
  assert.equal(t("ps5.after").n, 1);
  assert.equal(t("launch").n, 1);

  assert.deepEqual(s.tvBrands, [{ key: "androidtv", ok: 1, fail: 0, rate: 1 }]);
  assert.deepEqual(s.ps5Via, [{ key: "lan", ok: 1, fail: 1, rate: 0.5 }]);
  assert.deepEqual(s.tvProto, [{ proto: "nino", brand: "androidtv", n: 1 }]);
  assert.deepEqual(s.http, [{ code: "tr.provider.http", http: "429", n: 3 }]);
  assert.deepEqual(s.sources, [{ src: "remoteplay", n: 1 }]);
  assert.deepEqual(s.games, [{ game: "gta-6", sessions: 1, name: "GTA 6", minutes: 60 }]);
  assert.equal(s.daily.length, 7);
  assert.equal(s.daily.at(-1).day, localDayStart(NOW));
  assert.equal(s.daily.at(-1).errors, 3);

  const crash = s.recent.find((r) => r.kind === "crash");
  assert.equal(crash.code, "SIGSEGV");
  assert.equal(crash.os, "macOS 27.0");
  assert.equal(crash.device, "Mac16,1");
  assert.match(crash.detail, /ReadingPipeline\.process/);
  assert.equal(crash.app, "3.9.0");
  assert.match(crash.detail, /up 1820s/);
  // Kurulum kimliği hiçbir özet tablosunda ve son hatalarda yok.
  const raw = env.DB.raw;
  for (const table of ["ev_daily", "ev_timing", "ev_hist", "ev_games", "ev_recent"]) {
    const dump = JSON.stringify(raw.prepare(`SELECT * FROM ${table}`).all());
    assert.equal(dump.includes(FIXTURE.install), false, table);
  }
});

test("gzip gövde açılır; aynı parça yeniden gelince iki kez sayılmaz", async () => {
  const env = freshEnv();
  const first = await post(env, FIXTURE, { gzip: true });
  assert.equal(first.status, 200);
  assert.equal((await first.json()).accepted, FIXTURE.events.length);
  const again = await (await post(env, FIXTURE, { gzip: true })).json();
  assert.equal(again.duplicate, true);
  assert.equal(again.accepted, 0);
  assert.equal((await stats(env)).totals.errors, 3);
  // Başlık olmadan gzip baytları da tanınır (bazı ağ katmanları başlığı siler).
  const body = gzipSync(Buffer.from(JSON.stringify({ ...clone(FIXTURE), batch: randomUUID() })));
  const res = await handle(new Request("http://pool/v1/events", { method: "POST", body }), env, NOW);
  assert.equal(res.status, 200);
  assert.equal((await stats(env)).totals.errors, 6);
});

test("bozuk gövde 400, büyük gövde 413, açılınca büyüyen gzip 413", async () => {
  const env = freshEnv();
  assert.equal((await post(env, "{oops")).status, 400);
  assert.equal((await post(env, { ...clone(FIXTURE), v: 2 })).status, 400);
  assert.equal((await post(env, { ...clone(FIXTURE), ctx: { platform: "amiga" } })).status, 400);
  assert.equal((await post(env, { ...clone(FIXTURE), batch: "x" })).status, 400);
  assert.equal((await post(env, { ...clone(FIXTURE), install: "kim" })).status, 400);
  const many = Array.from({ length: EVENT_LIMITS.maxEvents + 1 }, () => ({ k: "launch", t: NOW }));
  assert.equal((await post(env, batchOf(many))).status, 400);
  assert.equal((await post(env, "x".repeat(EVENT_LIMITS.maxInflated + 1))).status, 413);
  const bomb = gzipSync(Buffer.from(JSON.stringify({ pad: "a".repeat(EVENT_LIMITS.maxInflated + 10) })));
  assert.ok(bomb.length < EVENT_LIMITS.maxCompressed);
  const res = await handle(new Request("http://pool/v1/events", { method: "POST", body: bomb }), env, NOW);
  assert.equal(res.status, 413);
  assert.equal((await handle(new Request("http://pool/v1/events"), env, NOW)).status, 405);
});

test("bilinmeyen tür ve alanlar atlanır, serbest yazı ve yollar saklanmaz", async () => {
  const env = freshEnv();
  const res = await (await post(env, batchOf([
    { k: "launch", t: NOW, extra: "yok sayılır" },
    { k: "subtitle", t: NOW, text: "Get in the car!" },
    { k: "error", t: NOW, code: "Hata: /Users/yunus/Desktop dosyası yok" },
    { k: "error", t: NOW },
    { k: "error", t: NOW - 8 * 86400, code: "eski.olay" },
    { k: "crash", t: NOW, code: "NSInvalidArgumentException", where: "/Users/yunus/app.swift:12" },
    { k: "ps5_connect", t: NOW, r: "olmadı ki", ms: 10 },
    { k: "session", t: NOW, dur: 60, game: "../../etc", h: { "ocr": { n: 2, sum: 10, max: 6, h: [1] }, "Bad Name": { n: 1, h: [1] } } },
    "çöp",
  ], { os: "macOS 27.0 <script>", device: "Yunus'un MacBook'u\n" }))).json();
  assert.equal(res.accepted, 3);
  assert.equal(res.dropped, 6);
  const s = await stats(env);
  assert.equal(s.totals.errors, 0);
  assert.equal(s.totals.crashes, 1);
  assert.deepEqual(s.games, []); // geçersiz oyun kimliği
  assert.equal(s.timings.some((t) => t.metric === "ocr"), false); // h toplamı n'e eşit değil
  const crash = s.recent.find((r) => r.kind === "crash");
  assert.equal(crash.detail, ""); // yol içeren "where" atıldı
  assert.equal(crash.os, ""); // kurala uymayan işletim sistemi ve cihaz adı saklanmaz
  assert.equal(crash.device, "");
  const all = JSON.stringify(env.DB.raw.prepare("SELECT * FROM ev_recent").all()) + JSON.stringify(env.DB.raw.prepare("SELECT * FROM ev_daily").all());
  assert.equal(/Users|Get in the car|olmadı/.test(all), false);
});

test("hız sınırı: kurulum başına günlük parça ve olay; 429 ertesi güne kadar bekletir, parça sonra yine kabul edilir", async () => {
  const env = freshEnv();
  const install = randomUUID();
  for (let i = 0; i < EVENT_LIMITS.perInstallBatches; i++) {
    assert.equal((await post(env, batchOf([{ k: "launch", t: NOW }], {}, install))).status, 200);
  }
  const blocked = batchOf([{ k: "launch", t: NOW }], {}, install);
  const res = await post(env, blocked);
  assert.equal(res.status, 429);
  const wait = Number(res.headers.get("retry-after"));
  assert.ok(wait > 0 && wait <= 86400);
  // Başka kurulum etkilenmez.
  assert.equal((await post(env, batchOf([{ k: "launch", t: NOW }]))).status, 200);
  // Ertesi gün aynı parça (aynı batch kimliği) kabul edilir: reddedilen parça "görüldü" sayılmamıştı.
  const ok = await (await post(env, blocked, { now: NOW + wait + 10 })).json();
  assert.equal(ok.accepted, 1);
  assert.equal(ok.duplicate, undefined);

  const env2 = freshEnv();
  const big = Array.from({ length: EVENT_LIMITS.maxEvents }, () => ({ k: "launch", t: NOW }));
  const who = randomUUID();
  for (let i = 0; i < Math.floor(EVENT_LIMITS.perInstallEvents / EVENT_LIMITS.maxEvents); i++) {
    assert.equal((await post(env2, batchOf(big, {}, who))).status, 200);
  }
  assert.equal((await post(env2, batchOf([{ k: "launch", t: NOW }], {}, who))).status, 429);

  const env3 = freshEnv({ EVENTS_DAILY_BATCHES: "2" });
  await post(env3, batchOf([{ k: "launch", t: NOW }]));
  await post(env3, batchOf([{ k: "launch", t: NOW }]));
  assert.equal((await post(env3, batchOf([{ k: "launch", t: NOW }]))).status, 429);
});

test("sunucudan kapatılınca hiçbir şey yazılmaz ve uygulamaya kapalı denir; /v1/config ayarı verir", async () => {
  const env = freshEnv({ TELEMETRY_ENABLED: "0", TELEMETRY_SAMPLE: "0.25" });
  const body = await (await post(env, FIXTURE)).json();
  assert.equal(body.accepted, 0);
  assert.equal(body.config.enabled, false);
  assert.equal(env.DB.raw.prepare("SELECT COUNT(*) AS n FROM ev_daily").get().n, 0);
  const config = await (await handle(new Request("http://pool/v1/config"), env, NOW)).json();
  assert.deepEqual(config.telemetry, { enabled: false, sample: 0.25, maxPerDay: 1000, flushSeconds: 600, diag: { off: [], limits: {} } });
  assert.equal(config.ok, true); // eski alanlar yerinde
  assert.ok(config.translate);
});

test("geliştirici yapıları (channel: dev) alınır ama sayılmaz", async () => {
  const env = freshEnv();
  const body = await (await post(env, { ...clone(FIXTURE), ctx: { ...FIXTURE.ctx, channel: "dev" } })).json();
  assert.equal(body.dev, true);
  assert.equal(body.accepted, 0);
  assert.equal(env.DB.raw.prepare("SELECT COUNT(*) AS n FROM ev_daily").get().n, 0);
});

test("/v1/config web TV'lerden okunabilir: CORS başlığı ve OPTIONS", async () => {
  const env = freshEnv();
  const res = await handle(new Request("http://pool/v1/config", { headers: { origin: "file://" } }), env, NOW);
  assert.equal(res.status, 200);
  assert.equal(res.headers.get("access-control-allow-origin"), "*");
  assert.equal(res.headers.get("cache-control"), "public, max-age=300");
  const pre = await handle(new Request("http://pool/v1/config", { method: "OPTIONS" }), env, NOW);
  assert.equal(pre.status, 204);
  assert.equal(pre.headers.get("access-control-allow-origin"), "*");
  assert.match(pre.headers.get("access-control-allow-methods"), /GET/);
  // Ölçüm cevapları da (hata cevapları dahil) okunabilir.
  const bad = await post(env, "{oops");
  assert.equal(bad.headers.get("access-control-allow-origin"), "*");
});

test("CORS ön isteği (web TV'ler) ve tablolar yokken 503 (istemci saklar)", async () => {
  const env = freshEnv();
  const pre = await handle(new Request("http://pool/v1/events", { method: "OPTIONS" }), env, NOW);
  assert.equal(pre.status, 204);
  assert.equal(pre.headers.get("access-control-allow-origin"), "*");
  assert.match(pre.headers.get("access-control-allow-headers"), /content-encoding/);

  env.DB.raw.exec("DROP TABLE ev_daily");
  const res = await post(env, FIXTURE);
  assert.equal(res.status, 503);
  assert.equal(res.headers.get("retry-after"), "3600");
  // Parça "görüldü" kalmadı: tablolar gelince yeniden gönderilebilir.
  assert.equal(env.DB.raw.prepare("SELECT COUNT(*) AS n FROM ev_batches").get().n, 0);
  const s = await stats(env);
  assert.equal(s.ready, false);
});

test("günler ayrı sayılır; bakım eski parça kimliklerini ve son hataları siler", async () => {
  const env = freshEnv();
  const yesterday = NOW - 86400;
  await post(env, batchOf([{ k: "error", t: yesterday, code: "ocr.failed" }]), { now: yesterday });
  await post(env, batchOf([{ k: "error", t: NOW, code: "ocr.failed" }, { k: "error", t: NOW, code: "ocr.failed" }]));
  const s = await stats(env);
  assert.deepEqual(s.daily.slice(-2).map((d) => d.errors), [1, 2]);
  assert.equal((await stats(env, NOW, 1)).totals.errors, 2);
  await pruneEvents(env.DB, NOW + 31 * 86400);
  const left = (t) => env.DB.raw.prepare(`SELECT COUNT(*) AS n FROM ${t}`).get().n;
  assert.equal(left("ev_batches"), 0);
  assert.equal(left("ev_recent"), 0);
  assert.equal(left("ev_quota"), 0);
  assert.ok(left("ev_daily") > 0); // özetler kalır
});

test("eski uç noktalar değişmedi: /v1/ping ve /v1/tv ölçüm tablolarına yazmaz, kurulum sayısı aynı", async () => {
  const env = freshEnv();
  await post(env, FIXTURE);
  const s = await (await handle(new Request("http://pool/v1/stats", { headers: { authorization: `Bearer ${TOKEN}` } }), env, NOW)).json();
  assert.equal(s.players.installs, 0); // ölçüm kurulum saymaz
  const ping = await handle(new Request(`http://pool/v1/ping?install=${randomUUID()}&platform=mac&app=3.4&game=gta-vi&lang=tr`), env, NOW);
  assert.equal(ping.status, 204);
  assert.equal((await stats(env)).totals.launches, 1);
});

test("panel sayfası Sağlık bölümünü içerir ve şablon dizgisi bozulmadı", async () => {
  const page = await (await handle(new Request("http://pool/panel"), freshEnv(), NOW)).text();
  assert.match(page, /Sağlık/);
  assert.match(page, /\/v1\/events\/stats/);
});

test("TV bağlantıları: model, TV uygulaması, gönderen ve nedene göre kopma; son 24 saat; kısa sürede çok kopan kurulum uyarısı", async () => {
  const env = freshEnv();
  const mac = randomUUID();
  // Mac (gönderen): TV modelini ve TV uygulama sürümünü olayda bildirir.
  const fromMac = [
    { k: "tv_connect", t: NOW - 7000, r: "ok", ms: 400, brand: "androidtv", proto: "nino", model: "TCL 98U95A", tvApp: "4.0.0" },
    { k: "tv_drop", t: NOW - 5000, code: "write_error", brand: "androidtv", model: "TCL 98U95A", tvApp: "4.0.0", after: 4000 },
    { k: "tv_connect", t: NOW - 2900, r: "ok", ms: 300, brand: "androidtv", proto: "nino", model: "TCL 98U95A", tvApp: "4.0.0" },
    { k: "tv_drop", t: NOW - 2000, code: "network_change", brand: "androidtv", model: "TCL 98U95A", tvApp: "4.0.0", after: 900 },
    { k: "tv_drop", t: NOW - 1000, code: "timeout", brand: "androidtv", model: "TCL 98U95A", tvApp: "4.0.0", after: 800 },
    { k: "tv_drop", t: NOW - 500, code: "close", brand: "androidtv", model: "TCL 98U95A", tvApp: "4.0.0", after: 300 },
  ];
  assert.equal((await post(env, batchOf(fromMac, {}, mac))).status, 200);
  // LG TV'nin kendisi (webOS): marka platformdan, model ctx.device'tan, sürüm ctx.app'ten.
  const lg = batchOf([
    { k: "tv_connect", t: NOW - 600, r: "ok", ms: 500, proto: "nino" },
    { k: "tv_drop", t: NOW - 100, code: "resume", after: 500 },
  ], { platform: "webos", app: "4.0.1", os: "webOS 23", device: "OLED55C3" });
  assert.equal((await post(env, lg)).status, 200);

  const s = await stats(env);
  const tv = s.tvLinks;
  assert.equal(tv.totals.ok, 3);
  assert.equal(tv.totals.drops, 5);
  assert.equal(Math.round(tv.totals.dropRate * 100), 167);
  assert.equal(tv.totals.avgAfter, Math.round((4000 + 900 + 800 + 300 + 500) / 5));
  const tcl = tv.models.find((m) => m.model === "TCL 98U95A");
  assert.deepEqual([tcl.brand, tcl.ok, tcl.drops, tcl.avgAfter], ["androidtv", 2, 4, 1500]);
  const oled = tv.models.find((m) => m.model === "OLED55C3");
  assert.deepEqual([oled.brand, oled.ok, oled.drops], ["lg", 1, 1]);
  assert.deepEqual(tv.tvApps.map((a) => [a.brand, a.tvApp, a.drops]), [["androidtv", "4.0.0", 4], ["lg", "4.0.1", 1]]);
  assert.deepEqual(tv.senders.map((x) => [x.platform, x.drops]), [["mac", 4], ["webos", 1]]);
  assert.deepEqual(tv.reasons.map((r) => r.code).sort(), ["closed", "network_change", "resume", "timeout", "write_error"]);
  assert.equal(tv.last24[0].model, "TCL 98U95A");
  assert.equal(tv.last24[0].drops, 4);
  assert.equal(tv.last24[0].installs, 1);
  // Mac kurulumu son 1 saatte 3 kez koptu → uyarı; LG bir kez → uyarı yok.
  assert.equal(tv.alerts.length, 1);
  assert.equal(tv.alerts[0].model, "TCL 98U95A");
  assert.equal(tv.alerts[0].hour, 3);
  assert.equal(tv.alerts[0].sixHours, 4);
  assert.equal(tv.alerts[0].id.length, 6);
  assert.equal(JSON.stringify(s).includes(mac), false);
  // Eski "tv_drop" sayımı da yerinde (Sağlık bölümü).
  assert.equal(s.totals.tvDrops, 5);

  // 3 gün sonra tek tek kayıtlar (kurulum özetiyle) silinir, günlük toplamlar kalır.
  await pruneEvents(env.DB, NOW + 3 * 86400 + 10);
  assert.equal(env.DB.raw.prepare("SELECT COUNT(*) AS n FROM ev_tv_raw").get().n, 0);
  assert.ok(env.DB.raw.prepare("SELECT COUNT(*) AS n FROM ev_tv_daily").get().n > 0);
});

test("TV alanları süzülür: model ve sürüm kurala uymuyorsa boş", async () => {
  const env = freshEnv();
  await post(env, batchOf([{ k: "tv_drop", t: NOW, code: "timeout", brand: "lg", model: "Yunus'un TV'si", tvApp: "x y", after: 5 }]));
  const s = await stats(env);
  assert.deepEqual(s.tvLinks.models.map((m) => [m.brand, m.model]), [["lg", ""]]);
  assert.deepEqual(s.tvLinks.tvApps.map((m) => m.tvApp), [""]);
});
