// SPDX-License-Identifier: AGPL-3.0-only
import { test } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { makeD1 } from "./d1-shim.js";
import { handle } from "../src/worker.js";

const NOW = 1763300000;
const TOKEN = "panel-anahtari";

test("panel: şu an oynayan, kurulumlar, çeviriler; anahtarsız açılmaz", async () => {
  const env = { DB: makeD1(), EXPORT_TOKEN: TOKEN, INSTALL_SALT: "tuz", ANTHROPIC_API_KEY: "k", STATS_GITHUB: "0" };
  const live = async (_e, _l, lines) => ({ texts: lines.map((l) => "TR " + l), cost: 300 });
  const a = randomUUID(), b = randomUUID();
  const ping = (install, platform, game, now = NOW) =>
    handle(new Request(`http://pool/v1/ping?install=${install}&platform=${platform}&app=0.2.2&game=${game}&lang=tr`), env, now);
  assert.equal((await ping(a, "mac", "gta-vi")).status, 204);
  await ping(b, "ios", "gta-vi", NOW - 600); // 10 dk önce: şu an oynamıyor
  await handle(new Request("http://pool/v1/translate", { method: "POST", body: JSON.stringify({
    v: 1, install: a, app: "0.2.2", platform: "mac", lang: "tr", game: "gta-vi", lines: ["Get in the car right now!"] }) }),
    env, NOW, undefined, live);
  assert.equal((await handle(new Request("http://pool/v1/stats"), env, NOW)).status, 401);
  const res = await handle(new Request("http://pool/v1/stats", { headers: { authorization: `Bearer ${TOKEN}` } }), env, NOW,
    undefined, undefined);
  const s = await res.json();
  assert.equal(s.players.now, 1);
  assert.deepEqual(s.players.games, [{ game: "gta-6", n: 1, name: "GTA 6" }]);
  assert.equal(s.players.installs, 2);
  assert.equal(s.players.active24h, 2);
  assert.equal(s.translations.lines, 1);
  assert.equal(s.translations.words, 6);
  assert.equal(s.spend.translateToday, 0.0003);
  const page = await handle(new Request("http://pool/panel"), env, NOW);
  assert.match(await page.text(), /Nino Panel/);
});

test("panel geçmişi: saatin en yükseği kalır, gün gün açan/oynayan/yeni kurulum; kimse oynamazken de ölçülür", async () => {
  const env = { DB: makeD1(), EXPORT_TOKEN: TOKEN, INSTALL_SALT: "tuz", STATS_GITHUB: "0" };
  const { samplePlayers, localDayStart, SAMPLE_EVERY } = await import("../src/stats.js");
  // Türkiye saatiyle bir günün öğleni: gün ve saat sınırlarına uzak.
  const noon = localDayStart(NOW) + 12 * 3600;
  const hour = noon - (noon % 3600);
  const ping = (install, now) =>
    handle(new Request(`http://pool/v1/ping?install=${install}&platform=windows&app=0.2.7&game=gta-vi&lang=tr`), env, now);
  const stats = async (now) => (await handle(new Request("http://pool/v1/stats", { headers: { authorization: `Bearer ${TOKEN}` } }), env, now)).json();
  const [a, b, c] = [randomUUID(), randomUUID(), randomUUID()];

  // Üç kişi aynı anda oynuyor.
  await ping(a, noon);
  await ping(b, noon + 5);
  await ping(c, noon + 10);
  await samplePlayers(env.DB, noon + 10, { force: true });
  let s = await stats(noon + 20);
  assert.equal(s.players.now, 3);
  assert.deepEqual(s.players.peak, { today: 3, week: 3, allTime: 3, allTimeHour: hour, since: hour });
  assert.deepEqual(s.players.hourly, [{ hour, peak: 3 }]);

  // Yarım saat sonra yalnız biri oynuyor: saatin en yükseği 3 kalır.
  await ping(a, noon + 1800);
  await samplePlayers(env.DB, noon + 1800, { force: true });
  s = await stats(noon + 1800 + SAMPLE_EVERY + 1);
  assert.equal(s.players.now, 1);
  assert.equal(s.players.peak.today, 3);
  assert.deepEqual(s.players.hourly, [{ hour, peak: 3 }]);

  // Ertesi gün kimse oynamıyor: panel açılınca o saat 0 olarak yazılır, rekor dünkü 3'tür.
  const next = noon + 86400;
  s = await stats(next);
  assert.equal(s.players.now, 0);
  assert.equal(s.players.peak.today, 0);
  assert.equal(s.players.peak.week, 3);
  assert.equal(s.players.peak.allTime, 3);
  assert.equal(s.players.peak.allTimeHour, hour);
  const days = s.players.daily;
  assert.equal(days.length, 14);
  assert.deepEqual(days.at(-2), { day: localDayStart(noon), active: 3, played: 3, peak: 3, fresh: 3 });
  assert.deepEqual(days.at(-1), { day: localDayStart(next), active: 0, played: 0, peak: 0, fresh: 0 });
  assert.equal(days[0].active, null);
  assert.deepEqual(s.players.langs, [{ lang: "tr", n: 3 }]);
});

test("panel geçmişi: tablo yoksa \"buradayım\" ve panel yine çalışır", async () => {
  const env = { DB: makeD1(), EXPORT_TOKEN: TOKEN, INSTALL_SALT: "tuz", STATS_GITHUB: "0" };
  await env.DB.prepare("DROP TABLE player_hours").run();
  const a = randomUUID();
  const later = NOW + 7 * 86400;
  assert.equal((await handle(new Request(`http://pool/v1/ping?install=${a}&platform=mac&app=0.2.7&game=gta-vi&lang=tr`), env, later)).status, 204);
  const s = await (await handle(new Request("http://pool/v1/stats", { headers: { authorization: `Bearer ${TOKEN}` } }), env, later)).json();
  assert.equal(s.players.now, 1);
  assert.equal(s.players.peak.allTime, 1);
  assert.deepEqual(s.players.hourly, []);
});

test("panel: TV uygulaması markasını ve modelini bildirir; panelde modele göre sayılır", async () => {
  const env = { DB: makeD1(), EXPORT_TOKEN: TOKEN, INSTALL_SALT: "tuz", STATS_GITHUB: "0" };
  const tv = (install, brand, model, app = "0.9.33", now = NOW) =>
    handle(new Request(`http://pool/v1/tv?install=${install}&brand=${brand}&model=${encodeURIComponent(model)}&app=${app}`), env, now);
  const [a, b, c] = [randomUUID(), randomUUID(), randomUUID()];
  assert.equal((await tv(a, "androidtv", "TCL 98U95A")).status, 204);
  await tv(b, "androidtv", "TCL 98U95A");
  await tv(c, "samsung", "QE55Q70CATXTK", "0.9.31");
  await tv(a, "androidtv", "TCL 98U95A", "0.9.33", NOW + 86400); // aynı TV ertesi gün: yeniden sayılmaz
  await tv(randomUUID(), "roku", "X");                            // bilinmeyen marka yazılmaz
  await tv("kimlik-degil", "lg", "OLED65B4");                     // geçersiz kimlik yazılmaz
  await tv(randomUUID(), "lg", "<script>alert(1)</script>\u0000 OLED65B46LA"); // model temizlenir
  const s = await (await handle(new Request("http://pool/v1/stats", { headers: { authorization: `Bearer ${TOKEN}` } }), env, NOW + 90000)).json();
  assert.equal(s.tvs.total, 4);
  assert.deepEqual(s.tvs.byBrand, [{ brand: "androidtv", n: 2 }, { brand: "lg", n: 1 }, { brand: "samsung", n: 1 }]);
  assert.deepEqual(s.tvs.models[0], { brand: "androidtv", model: "TCL 98U95A", n: 2 });
  assert.ok(s.tvs.models.some((m) => m.brand === "lg" && m.model === "script alert(1) /script OLED65B46LA"));
  assert.deepEqual(s.tvs.versions[0], { app: "0.9.33", n: 3 });
});

test("panel: GitHub indirme sayıları alınamazsa son bilinen değer gösterilir", async () => {
  const { collectStats } = await import("../src/stats.js");
  const db = makeD1();
  const env = { EXPORT_TOKEN: TOKEN, INSTALL_SALT: "tuz" };
  const releases = [{ tag_name: "v0.2.7", assets: [{ name: "Nino-Mac.zip", download_count: 5 }, { name: "Nino-TV.apk", download_count: 7 }] }];
  const works = async () => ({ ok: true, json: async () => releases });
  const limited = async () => ({ ok: false, status: 403 });
  const first = await collectStats(db, env, NOW + 500000, works);
  assert.deepEqual(first.downloads, { mac: 5, windows: 0, android: 0, tv: 7, total: 12, latest: "v0.2.7" });
  // Bellekteki değer eskidi ve GitHub sınıra takıldı: bellekteki son değer sürer.
  const second = await collectStats(db, env, NOW + 500000 + 700, limited);
  assert.equal(second.downloads.total, 12);
  // Saklanan değer veritabanında da durur (sunucu yeni açılınca oradan okunur).
  const row = await db.prepare("SELECT value FROM stats_cache WHERE key = 'downloads'").first();
  assert.equal(JSON.parse(row.value).total, 12);
});
