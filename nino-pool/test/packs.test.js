// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
import { test } from "node:test";
import assert from "node:assert/strict";
import { gunzipSync } from "node:zlib";
import { createHash } from "node:crypto";
import { makeD1 } from "./d1-shim.js";
import { handle } from "../src/worker.js";
import { lineKey } from "../src/key.js";
import { buildPacks, buildScheduled, packId, packTitle, PACK_ID, PACK_LIMITS } from "../src/packs.js";

const NOW = 1763300000;
const ID = /^[a-z0-9][a-z0-9-]{0,63}$/; // istemcinin kuralı (PackUpdater.isValidID)

function setup(vars = {}) {
  const env = { DB: makeD1(), INSTALL_SALT: "tuz", EXPORT_TOKEN: "gizli", PACK_MIN_LINES: "1", ...vars };
  const get = (path, headers = {}) => handle(new Request(`http://pool${path}`, { headers }), env, NOW);
  const post = (path, token = "gizli") => handle(new Request(`http://pool${path}`, {
    method: "POST", headers: token ? { authorization: `Bearer ${token}` } : {} }), env, NOW);
  return { env, get, post };
}

/** Havuza bir satır ve çevirisi: `installs` kurulumda görülmüş. */
async function put(env, { game = "grand-theft-auto-vi", source, text, lang = "tr", installs = 2, copyOf = null, tier = 1 }) {
  const key = await lineKey(source);
  env.DB.raw.prepare(`INSERT OR REPLACE INTO lines (game, key, text, seen, installs, first_seen, last_seen) VALUES (?, ?, ?, ?, ?, ?, ?)`)
    .run(game, key, source, installs, installs, NOW - 100, NOW - 10);
  env.DB.raw.prepare(`INSERT OR REPLACE INTO translations (key, lang, game, source, text, tier, created, updated, copy_of)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`).run(key, lang, game, source, text, tier, NOW - 100, NOW - 100, copyOf);
  return key;
}

async function body(res) {
  return new Uint8Array(await res.arrayBuffer());
}

const sha = (bytes) => createHash("sha256").update(bytes).digest("hex");

test("boş havuz: liste boş, bilinmeyen paket 404", async () => {
  const { env, get } = setup();
  assert.deepEqual(await buildPacks(env.DB, env, NOW), { lang: "tr", packs: 0, changed: 0, removed: 0, entries: 0 });
  const res = await get("/v1/packs");
  assert.equal(res.status, 200);
  assert.deepEqual(await res.json(), { ok: true, packs: [] });
  assert.equal((await get("/v1/packs/pool-yok")).status, 404);
});

test("liste biçimi, sha256 ve gzip'li gövde istemcinin anahtarıyla eşleşir", async () => {
  const { env, get } = setup();
  const lines = [
    ["Get down right now, Lucia!", "Hemen yere yat, Lucia!"],
    ["It’s his mother, she passed.", "Annesi, vefat etti."],
    ["<b>Who</b> is that guy over there?", "Şuradaki adam kim?"],
  ];
  for (const [source, text] of lines) await put(env, { source, text });
  const result = await buildPacks(env.DB, env, NOW);
  assert.equal(result.packs, 1);
  assert.equal(result.entries, 3);

  const list = await (await get("/v1/packs")).json();
  assert.equal(list.packs.length, 1);
  const p = list.packs[0];
  assert.equal(p.id, "pool-gta-6");
  assert.match(p.id, ID);
  assert.equal(p.title, "GTA 6");
  assert.equal(p.version, NOW);
  assert.match(p.sha256, /^[0-9a-f]{64}$/);
  assert.equal(p.entries, 3);

  const res = await get(`/v1/packs/${p.id}`);
  assert.equal(res.status, 200);
  assert.equal(res.headers.get("content-type"), "application/gzip");
  assert.equal(res.headers.get("content-encoding"), null);
  const file = await body(res);
  assert.equal(file.byteLength, p.size);
  assert.equal(sha(file), p.sha256);
  assert.equal(file[0], 0x1f);
  assert.equal(file[1], 0x8b);

  const pack = JSON.parse(gunzipSync(file).toString("utf8"));
  assert.equal(pack.format, 1);
  assert.equal(pack.id, p.id);
  assert.equal(pack.title, "GTA 6");
  for (const [source, text] of lines) assert.equal(pack.entries[await lineKey(source)], text);
  // İstemcinin belgesindeki örnek anahtar (docs/tarif/kutuphane.md).
  assert.equal(await lineKey("It’s his mother, she passed."), "15014c246455f36c");
  assert.ok(Object.keys(pack.entries).every((k) => /^[0-9a-f]{16}$/.test(k)));
  // İngilizce metin pakette yok.
  assert.ok(!JSON.stringify(pack).includes("Get down"));

  // ETag ile 304.
  const again = await get(`/v1/packs/${p.id}`, { "if-none-match": `"${p.sha256}"` });
  assert.equal(again.status, 304);
});

test("seçim kuralı: tek kurulum, tohum, eski kopya, boş, ret, çöp ve oyunsuz satırlar girmez", async () => {
  const { env } = setup();
  const ok = await put(env, { source: "Keep your head down until dark.", text: "Buradan çıkmamız lazım." });
  const copy = await put(env, { source: "Keep your head d0wn until dark.", text: "Buradan çıkmamız lazım.", copyOf: ok });
  const single = await put(env, { source: "Only one player saw this line.", text: "Bunu bir kişi gördü.", installs: 1 });
  const seed = await put(env, { source: "This came from a seed pack.", text: "Tohumdan geldi.", copyOf: "seed" });
  const old = await put(env, { source: "Old copy with unknown origin.", text: "Eski kopya.", copyOf: "?" });
  const empty = await put(env, { source: "Nobody could translate this.", text: "" });
  const refusal = await put(env, { source: "Kill him now.", text: "I'm sorry, I can't translate that." });
  const junk = await put(env, { source: "MAIN MENU", text: "ANA MENÜ" });
  const unknown = await put(env, { game: "", source: "Line from an unknown game.", text: "Bilinmeyen oyun." });
  const other = await put(env, { lang: "ar", source: "Arabic only line here.", text: "سطر" });

  await buildPacks(env.DB, env, NOW);
  const { data } = await (await import("../src/packs.js")).readPack(env.DB, "tr", "pool-gta-6");
  const entries = JSON.parse(gunzipSync(data).toString("utf8")).entries;
  assert.equal(entries[ok], "Buradan çıkmamız lazım.");
  assert.equal(entries[copy], "Buradan çıkmamız lazım.");
  for (const k of [single, seed, old, empty, refusal, junk, unknown, other]) assert.equal(entries[k], undefined, k);
  assert.equal(Object.keys(entries).length, 2);
});

test("kimlik kuralı: havuz oyun kimliği istemcinin kuralına uyar, uymayan istek 400", async () => {
  for (const game of ["gta.vi", "rdr_2", "a", "x".repeat(64), "9-lives", "Mafia..Old"]) {
    const id = packId(game);
    assert.match(id, ID, game);
    assert.ok(id.length <= 64);
  }
  assert.equal(packId("---"), null);
  assert.equal(packId(""), null);
  assert.equal(packTitle("red-dead-redemption-ii"), "Red Dead Redemption II");
  assert.equal(PACK_ID.source, ID.source);

  const { get } = setup();
  assert.equal((await get("/v1/packs/Bad_ID")).status, 400);
  assert.equal((await get("/v1/packs/-x")).status, 400);
  assert.equal((await get(`/v1/packs/${"a".repeat(65)}`)).status, 400);
  assert.equal((await get("/v1/packs?lang=xx")).status, 400);
});

test("aynı kimliğe düşen oyunlar birleşir; en az satır sınırı", async () => {
  const { env } = setup({ PACK_MIN_LINES: "2" });
  await put(env, { game: "gta.vi", source: "First line of the game.", text: "Birinci." });
  await put(env, { game: "gta-vi", source: "Second line of the game.", text: "İkinci." });
  await put(env, { game: "mafia", source: "A lonely mafia line.", text: "Yalnız satır." });
  const result = await buildPacks(env.DB, env, NOW);
  assert.equal(result.packs, 1);
  const { results } = await env.DB.prepare("SELECT id, entries FROM packs").all();
  assert.deepEqual(results, [{ id: "pool-gta-6", entries: 2 }]);
});

test("içerik değişmezse sürüm ve sha aynı; değişince sürüm artar; kuraldan düşen paket kalkar", async () => {
  const { env, get } = setup();
  await put(env, { source: "Stay close to me.", text: "Yanımdan ayrılma." });
  await buildPacks(env.DB, env, NOW);
  const first = (await (await get("/v1/packs")).json()).packs[0];

  assert.equal((await buildPacks(env.DB, env, NOW + 60)).changed, 0);
  const same = (await (await get("/v1/packs")).json()).packs[0];
  assert.equal(same.version, first.version);
  assert.equal(same.sha256, first.sha256);

  await put(env, { source: "Stay close to me.", text: "Yakınımda kal." });
  assert.equal((await buildPacks(env.DB, env, NOW)).changed, 1); // saat geri gitse de sürüm artar
  const changed = (await (await get("/v1/packs")).json()).packs[0];
  assert.equal(changed.version, first.version + 1);
  assert.notEqual(changed.sha256, first.sha256);

  env.DB.raw.prepare("UPDATE lines SET installs = 1").run();
  assert.equal((await buildPacks(env.DB, env, NOW + 120)).removed, 1);
  assert.deepEqual((await (await get("/v1/packs")).json()).packs, []);
  assert.equal(env.DB.raw.prepare("SELECT COUNT(*) AS n FROM pack_parts").get().n, 0);
});

test("büyük paket parçalara bölünür ve birleşince sha tutar", async () => {
  const { env, get } = setup();
  // Rastgele (sıkışmayan) çeviriler: gzip'li dosya bir parçadan büyük olsun.
  const rows = [];
  for (let i = 0; i < 20000; i++) {
    const noise = createHash("sha256").update(String(i)).digest("base64");
    rows.push([`Line number ${i} is spoken here by someone.`, `Satır ${i} ${noise}${noise}${noise}`]);
  }
  const insertLine = env.DB.raw.prepare("INSERT INTO lines (game, key, text, seen, installs, first_seen, last_seen) VALUES ('big-game', ?, ?, 2, 2, 0, 0)");
  const insertT = env.DB.raw.prepare("INSERT INTO translations (key, lang, game, source, text, tier, created, updated) VALUES (?, 'tr', 'big-game', ?, ?, 1, 0, 0)");
  for (const [s, t] of rows) {
    const k = await lineKey(s);
    insertLine.run(k, s);
    insertT.run(k, s, t);
  }
  await buildPacks(env.DB, env, NOW);
  const parts = env.DB.raw.prepare("SELECT parts, bytes FROM packs WHERE id = 'pool-big-game'").get();
  assert.ok(parts.parts >= 2, `parça: ${parts.parts}`);
  assert.ok(parts.bytes > PACK_LIMITS.partBytes);
  const p = (await (await get("/v1/packs")).json()).packs[0];
  const file = await body(await get(`/v1/packs/${p.id}`));
  assert.equal(sha(file), p.sha256);
  assert.equal(Object.keys(JSON.parse(gunzipSync(file).toString("utf8")).entries).length, 20000);
});

test("elle üretim yönetici anahtarı ister; zamanlanmış üretim PACK_ENABLED ile kapanır", async () => {
  const { env, post } = setup();
  await put(env, { source: "Open the door.", text: "Kapıyı aç." });
  assert.equal((await post("/v1/packs/build", null)).status, 401);
  assert.equal((await post("/v1/packs/build", "yanlis")).status, 401);
  const res = await post("/v1/packs/build");
  assert.equal(res.status, 200);
  assert.equal((await res.json()).packs, 1);
  assert.deepEqual(await buildScheduled(env.DB, { ...env, PACK_ENABLED: "0" }, NOW), []);
  const scheduled = await buildScheduled(env.DB, env, NOW);
  assert.equal(scheduled.length, 1);
  assert.equal(scheduled[0].lang, "tr");
});

test("veritabanı hatası boş liste değil 503 verir (istemci paketleri silmesin)", async () => {
  const { env } = setup();
  env.DB.raw.exec("DROP TABLE packs");
  const worker = (await import("../src/worker.js")).default;
  const res = await worker.fetch(new Request("http://pool/v1/packs"), env, {});
  assert.equal(res.status, 503);
});
