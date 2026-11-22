// SPDX-License-Identifier: AGPL-3.0-only
import { test } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { makeD1 } from "./d1-shim.js";
import { handle } from "../src/worker.js";
import { canonicalGame, aliasesOf, mergeGameSQL } from "../src/games.js";

const NOW = 1763300000;

test("takma adlar asıl kimliğe çevrilir; öbür oyunlar değişmez", () => {
  for (const id of ["grand-theft-auto-vi", "GTA-VI", "gta6", "gtavi", "pool-gta-6", "gta--6"]) assert.equal(canonicalGame(id), "gta-6");
  assert.equal(canonicalGame("grand-theft-auto-v"), "gta-v");
  assert.equal(canonicalGame("gta-v"), "gta-v");
  assert.equal(canonicalGame(""), "");
  assert.deepEqual(aliasesOf("gta-6").sort(), ["grand-theft-auto-vi", "gta-vi", "gta6", "gtavi", "pool-gta-6"]);
});

test("eski uygulamanın gönderdiği grand-theft-auto-vi satırları gta-6'ya yazılır", async () => {
  const env = { DB: makeD1(), INSTALL_SALT: "tuz" };
  const res = await handle(new Request("http://pool/v1/batches", { method: "POST", body: JSON.stringify({
    v: 1, batch: randomUUID(), install: randomUUID(), app: "3.4.0", platform: "mac",
    lines: [{ text: "Get in the car, Lucia!", game: "grand-theft-auto-vi", count: 1, first: NOW, last: NOW }] }) }), env, NOW);
  assert.equal(res.status, 200);
  const games = env.DB.raw.prepare("SELECT DISTINCT game FROM lines").all().map((r) => r.game);
  assert.deepEqual(games, ["gta-6"]);
  // /v1/config'teki havuz öncelikli liste eski adları korur (eski uygulamalar kendi kimlikleriyle karşılaştırıyor).
  const config = await (await handle(new Request("http://pool/v1/config"), { ...env, POOL_FIRST_GAMES: "grand-theft-auto-vi,gta-6" }, NOW)).json();
  assert.deepEqual(config.poolFirst.games, ["grand-theft-auto-vi", "gta-6"]);
});

function seed(db) {
  const raw = db.raw;
  const line = raw.prepare("INSERT INTO lines (game, key, text, seen, installs, first_seen, last_seen) VALUES (?, ?, ?, ?, ?, ?, ?)");
  const inst = raw.prepare("INSERT INTO line_installs (game, key, install) VALUES (?, ?, ?)");
  // Yalnız takma adda olan satır.
  line.run("grand-theft-auto-vi", "0aaa000000000001", "Only old", 3, 2, 100, 300);
  inst.run("grand-theft-auto-vi", "0aaa000000000001", "i1");
  inst.run("grand-theft-auto-vi", "0aaa000000000001", "i2");
  // İkisinde de olan satır: eski adda daha çok kurulum var → yazılış oradan.
  line.run("grand-theft-auto-vi", "1bbb000000000002", "Get in the car!", 5, 3, 50, 500);
  for (const i of ["i1", "i2", "i3"]) inst.run("grand-theft-auto-vi", "1bbb000000000002", i);
  line.run("gta-6", "1bbb000000000002", "GET IN THE CAR", 2, 2, 80, 900);
  for (const i of ["i3", "i4"]) inst.run("gta-6", "1bbb000000000002", i);
  // Üç takma adda birden (gta6, gtavi) olan satır.
  line.run("gta6", "fccc000000000003", "Lucia", 1, 1, 10, 10);
  line.run("gtavi", "fccc000000000003", "Lucia.", 4, 1, 20, 40);
  inst.run("gta6", "fccc000000000003", "i5");
  inst.run("gtavi", "fccc000000000003", "i6");
  // Yalnız asıl adda olan ve başka oyunun satırı: dokunulmaz.
  line.run("gta-6", "2ddd000000000004", "New only", 1, 1, 70, 70);
  line.run("grand-theft-auto-v", "1bbb000000000002", "Get in the car!", 9, 9, 1, 2);
  // Kurulum listesi silinmiş eski satır: kurulum sayısı düşmemeli.
  line.run("gta-vi", "3eee000000000005", "Pruned", 7, 6, 5, 6);
  // Oturumlar, çeviriler, kurulumlar.
  raw.prepare("INSERT INTO sessions (session, game, lines, first_seen, last_seen) VALUES (?, ?, ?, ?, ?)").run("s1", "grand-theft-auto-vi", 10, 100, 200);
  raw.prepare("INSERT INTO sessions (session, game, lines, first_seen, last_seen) VALUES (?, ?, ?, ?, ?)").run("s1", "gta-6", 4, 150, 400);
  raw.prepare("INSERT INTO sessions (session, game, lines, first_seen, last_seen) VALUES (?, ?, ?, ?, ?)").run("s2", "gta6", 2, 1, 2);
  const tr = raw.prepare("INSERT INTO translations (key, lang, game, source, text, tier, created, updated) VALUES (?, ?, ?, ?, ?, ?, 1, 1)");
  tr.run("1bbb000000000002", "tr", "grand-theft-auto-vi", "Get in the car!", "Arabaya bin!", 2);
  tr.run("1bbb000000000002", "ar", "gta-6", "Get in the car!", "…", 1);
  tr.run("0aaa000000000001", "tr", "gta-vi", "Only old", "Yalnız eski", 1);
  raw.prepare("INSERT INTO installs (install, platform, app, first_seen, last_seen, playing, game, lang) VALUES (?, '', '', 1, 1, 0, ?, '')").run("x", "grand-theft-auto-vi");
}

const all = (db, sql) => db.raw.prepare(sql).all().map((r) => ({ ...r }));

test("birleştirme: veri kaybı yok, çakışmada en çok kurulumlu yazılış, kurulumlar birleşir, yeniden çalıştırılabilir", async () => {
  const db = makeD1();
  seed(db);
  const before = all(db, "SELECT SUM(seen) AS seen FROM lines WHERE game IN ('gta-6','grand-theft-auto-vi','gta-vi','gta6','gtavi','pool-gta-6')")[0].seen;
  const { parts, tail } = mergeGameSQL("gta-6");
  assert.equal(parts.length, 16);
  // Önce tek parça (anahtarı "1" ile başlayanlar) deneme.
  db.raw.exec(parts.find((p) => p.prefix === "1").sql);
  assert.equal(all(db, "SELECT COUNT(*) AS n FROM lines WHERE game = 'grand-theft-auto-vi' AND key LIKE '1%'")[0].n, 0);
  assert.equal(all(db, "SELECT COUNT(*) AS n FROM lines WHERE game = 'grand-theft-auto-vi' AND key LIKE '0%'")[0].n, 1);
  for (const p of parts) db.raw.exec(p.sql);
  db.raw.exec(tail);

  const lines = Object.fromEntries(all(db, "SELECT * FROM lines WHERE game = 'gta-6'").map((r) => [r.key, r]));
  assert.deepEqual(Object.keys(lines).sort(), ["0aaa000000000001", "1bbb000000000002", "2ddd000000000004", "3eee000000000005", "fccc000000000003"]);
  const both = lines["1bbb000000000002"];
  assert.deepEqual([both.text, both.seen, both.installs, both.first_seen, both.last_seen], ["Get in the car!", 7, 4, 50, 900]);
  const multi = lines["fccc000000000003"];
  assert.deepEqual([multi.text, multi.seen, multi.installs, multi.first_seen, multi.last_seen], ["Lucia.", 5, 2, 10, 40]);
  assert.equal(lines["3eee000000000005"].installs, 6); // kurulum listesi silinmiş olsa da sayı korunur
  assert.equal(all(db, "SELECT COUNT(*) AS n FROM lines WHERE game IN ('grand-theft-auto-vi','gta-vi','gta6','gtavi','pool-gta-6')")[0].n, 0);
  const after = all(db, "SELECT SUM(seen) AS seen FROM lines WHERE game = 'gta-6'")[0].seen;
  assert.equal(after, before); // görülme toplamı aynı
  assert.equal(all(db, "SELECT COUNT(*) AS n FROM line_installs WHERE game = 'gta-6' AND key = '1bbb000000000002'")[0].n, 4);
  assert.equal(all(db, "SELECT COUNT(*) AS n FROM line_installs WHERE game <> 'gta-6'")[0].n, 0);
  // Başka oyunun satırı yerinde.
  assert.equal(all(db, "SELECT seen FROM lines WHERE game = 'grand-theft-auto-v'")[0].seen, 9);
  // Oturumlar toplandı, çeviriler ve kurulumlar taşındı; çeviri metinleri aynı.
  assert.deepEqual(all(db, "SELECT session, lines, first_seen, last_seen FROM sessions ORDER BY session"),
    [{ session: "s1", lines: 14, first_seen: 100, last_seen: 400 }, { session: "s2", lines: 2, first_seen: 1, last_seen: 2 }]);
  assert.deepEqual(all(db, "SELECT DISTINCT game FROM sessions"), [{ game: "gta-6" }]);
  assert.deepEqual(all(db, "SELECT key, lang, game, text, tier FROM translations ORDER BY key, lang"), [
    { key: "0aaa000000000001", lang: "tr", game: "gta-6", text: "Yalnız eski", tier: 1 },
    { key: "1bbb000000000002", lang: "ar", game: "gta-6", text: "…", tier: 1 },
    { key: "1bbb000000000002", lang: "tr", game: "gta-6", text: "Arabaya bin!", tier: 2 },
  ]);
  assert.equal(all(db, "SELECT game FROM installs")[0].game, "gta-6");

  // Yeniden çalıştırmak hiçbir şeyi değiştirmez.
  const snapshot = JSON.stringify(all(db, "SELECT * FROM lines ORDER BY game, key"));
  for (const p of parts) db.raw.exec(p.sql);
  db.raw.exec(tail);
  assert.equal(JSON.stringify(all(db, "SELECT * FROM lines ORDER BY game, key")), snapshot);
});

test("okunur adlar ve panel listelerinde tek oyun", async () => {
  const { gameName, mergeGameRows } = await import("../src/games.js");
  assert.equal(gameName("grand-theft-auto-vi"), "GTA 6");
  assert.equal(gameName("grand-theft-auto-v"), "GTA 5");
  assert.equal(gameName("call-of-duty--modern-warfare--2019"), "Call of Duty: Modern Warfare (2019)");
  assert.equal(gameName("assassin-s-creed-shadows"), "Assassin's Creed Shadows");
  assert.equal(gameName("some-new-game-ii"), "Some New Game II");
  assert.equal(gameName(""), "");
  assert.deepEqual(mergeGameRows([{ game: "gta-6", n: 113 }, { game: "grand-theft-auto-vi", n: 111 }, { game: "gta-v", n: 5 }, { game: "grand-theft-auto-v", n: 2 }]),
    [{ game: "gta-6", n: 224, name: "GTA 6" }, { game: "gta-v", n: 7, name: "GTA 5" }]);

  // Panelde "şu an oynanan": eski kayıtlar iki ayrı kimlikle dursa da tek GTA 6.
  const env = { DB: makeD1(), EXPORT_TOKEN: "k", INSTALL_SALT: "tuz", STATS_GITHUB: "0" };
  const ins = env.DB.raw.prepare("INSERT INTO installs (install, platform, app, first_seen, last_seen, playing, game, lang) VALUES (?, 'mac', '3.4', ?, ?, ?, ?, 'tr')");
  ins.run("a", NOW, NOW, NOW, "gta-6");
  ins.run("b", NOW, NOW, NOW, "grand-theft-auto-vi");
  ins.run("c", NOW, NOW, NOW, "red-dead-redemption-2");
  const s = await (await handle(new Request("http://pool/v1/stats", { headers: { authorization: "Bearer k" } }), env, NOW)).json();
  assert.deepEqual(s.players.games, [{ game: "gta-6", n: 2, name: "GTA 6" }, { game: "red-dead-redemption-2", n: 1, name: "Red Dead Redemption 2" }]);
});

test("GTA 5 birleştirmesi de gta-v'ye", () => {
  const { parts, tail } = mergeGameSQL("gta-v");
  assert.match(parts[0].sql, /'grand-theft-auto-v'/);
  assert.doesNotMatch(parts[0].sql + tail, /'grand-theft-auto-vi'/);
});
