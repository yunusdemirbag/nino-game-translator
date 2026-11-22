// SPDX-License-Identifier: AGPL-3.0-only
import { test } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { makeD1 } from "./d1-shim.js";
import { handle } from "../src/worker.js";
import { prune } from "../src/pool.js";

const NOW = 1763300000; // 2025-11-16
const TOKEN = "deneme-anahtari";

function setup(vars = {}) {
  const db = makeD1();
  const env = { DB: db, EXPORT_TOKEN: TOKEN, INSTALL_SALT: "tuz", ...vars };
  const post = (body, now = NOW) =>
    handle(new Request("http://pool/v1/batches", { method: "POST", body: typeof body === "string" ? body : JSON.stringify(body) }), env, now);
  const get = (path, token = TOKEN) =>
    handle(new Request(`http://pool${path}`, { headers: token ? { authorization: `Bearer ${token}` } : {} }), env, NOW);
  return { db, env, post, get };
}

function batch(lines, extra = {}) {
  return { v: 1, batch: randomUUID(), install: randomUUID(), app: "0.1.6", platform: "mac", lines, ...extra };
}

const line = (text, extra = {}) => ({ text, game: "gta-v", count: 1, first: NOW - 60, last: NOW - 30, ...extra });

test("satırlar oyun başına yazılır, dışa aktarılır", async () => {
  const { post, get } = setup();
  const res = await post(batch([line("You fucked up now, boy!"), line("Where is Lamar?", { game: "rdr2" })]));
  assert.equal(res.status, 200);
  const body = await res.json();
  assert.equal(body.accepted, 2);
  assert.deepEqual(body.rejected, []);

  const exp = await (await get("/v1/export?game=gta-v")).json();
  assert.equal(exp.lines.length, 1);
  assert.equal(exp.lines[0].text, "You fucked up now, boy!");
  assert.equal(exp.lines[0].key, "e7f18c8f6d1083ab");
  assert.equal(exp.lines[0].seen, 1);
  assert.equal(exp.lines[0].installs, 1);
  assert.equal(exp.lines[0].first_seen, NOW - 60);

  const games = await (await get("/v1/games")).json();
  assert.deepEqual(games.games.map((g) => g.game).sort(), ["gta-v", "rdr2"]);
});

test("aynı parça ikinci kez gelince yeniden sayılmaz", async () => {
  const { post, get } = setup();
  const b = batch([line("Hold on, I'm coming.", { count: 3 })]);
  assert.equal((await post(b)).status, 200);
  const again = await (await post(b)).json();
  assert.equal(again.duplicate, true);
  const exp = await (await get("/v1/export?game=gta-v")).json();
  assert.equal(exp.lines[0].seen, 3);
});

test("aynı cümlenin farklı yazılışı tek satır; görülme ve ayrı kurulum sayılır", async () => {
  const { post, get } = setup();
  const install = randomUUID();
  await post(batch([line("Get down!", { count: 2 })], { install }));
  await post(batch([line("GET DOWN", { first: NOW - 500, last: NOW - 400 })], { install }));
  await post(batch([line("Get down!")]));
  const exp = await (await get("/v1/export?game=gta-v")).json();
  assert.equal(exp.lines.length, 1);
  const row = exp.lines[0];
  assert.equal(row.seen, 4);
  assert.equal(row.installs, 2);
  assert.equal(row.variants, 2);
  assert.equal(row.text, "Get down!"); // en çok görülen yazılış
  assert.equal(row.first_seen, NOW - 500);
  assert.equal(row.last_seen, NOW - 30);
});

test("bozuk satır parçanın geri kalanını düşürmez", async () => {
  const { post, get } = setup();
  const res = await (
    await post(
      batch([
        line("Fine line."),
        line("x".repeat(501)),
        line("12345"),
        { text: 5 },
        line("Bad game.", { game: "GTA V!" }),
        line("Bad count.", { count: 0 }),
        line("Bad session.", { session: "nope" }),
      ]),
    )
  ).json();
  assert.equal(res.accepted, 1);
  assert.deepEqual(
    res.rejected.map((r) => [r.i, r.reason]),
    [
      [1, "too_long"],
      [2, "no_letters"],
      [3, "no_text"],
      [4, "bad_game"],
      [5, "bad_count"],
      [6, "bad_session"],
    ],
  );
  const exp = await (await get("/v1/export?game=gta-v")).json();
  assert.equal(exp.lines.length, 1);
});

test("parça biçimi bozuksa 400, çok büyükse 413", async () => {
  const { post } = setup();
  assert.equal((await post("{not json")).status, 400);
  assert.equal((await post({ v: 2, batch: randomUUID(), install: randomUUID(), lines: [] })).status, 400);
  assert.equal((await post(batch([], { batch: "abc" }))).status, 400);
  assert.equal((await post(batch([], { install: "kim" }))).status, 400);
  assert.equal((await post(batch(Array.from({ length: 501 }, (_, i) => line(`Line number ${i}.`))))).status, 413);
  assert.equal((await post(JSON.stringify(batch([line("y".repeat(400))])) + " ".repeat(600 * 1024))).status, 413);
});

test("kurulum başına saatlik sınır 429 + Retry-After", async () => {
  const { post } = setup({ INSTALL_HOURLY_BATCHES: "2" });
  const install = randomUUID();
  assert.equal((await post(batch([line("One line here.")], { install }))).status, 200);
  assert.equal((await post(batch([line("Two lines here.")], { install }))).status, 200);
  const res = await post(batch([line("Three lines here.")], { install }));
  assert.equal(res.status, 429);
  assert.equal(res.headers.get("retry-after"), "900");
  // Başka kurulum etkilenmez.
  assert.equal((await post(batch([line("Other install.")]))).status, 200);
});

test("günlük bütçe dolunca ertesi güne kadar 429", async () => {
  const { post } = setup({ DAILY_LINE_BUDGET: "3" });
  assert.equal((await post(batch([line("A one."), line("A two.")]))).status, 200);
  const res = await post(batch([line("A three."), line("A four.")]));
  assert.equal(res.status, 429);
  assert.equal(Number(res.headers.get("retry-after")), 86400 - (NOW % 86400));
  assert.equal((await post(batch([line("A three."), line("A four.")]), NOW + 86400)).status, 200);
});

test("oyunu bilinmeyen satırlar oturumla gruplanır, oturumun oyun ipucu görünür", async () => {
  const { post, get } = setup();
  const session = randomUUID();
  await post(
    batch([
      line("Unknown game line one.", { game: null, session }),
      line("Unknown game line two.", { game: null, session }),
      line("Known line.", { game: "gta-v", session }),
    ]),
  );
  const sessions = (await (await get("/v1/sessions")).json()).sessions;
  assert.equal(sessions.length, 1);
  assert.equal(sessions[0].session, session);
  assert.equal(sessions[0].lines, 2);
  assert.equal(sessions[0].hint, "gta-v");
  const exp = await (await get(`/v1/export?game=&session=${session}`)).json();
  assert.deepEqual(exp.lines.map((l) => l.text).sort(), ["Unknown game line one.", "Unknown game line two."]);
});

test("dışa aktarma sayfalı ve en az kurulum süzgeçli", async () => {
  const { post, get } = setup();
  await post(batch(Array.from({ length: 30 }, (_, i) => line(`Paged line number ${i}.`))));
  let after = "";
  const seen = [];
  for (;;) {
    const page = await (await get(`/v1/export?game=gta-v&limit=7&after=${after}`)).json();
    seen.push(...page.lines);
    if (!page.next) break;
    after = page.next;
  }
  assert.equal(seen.length, 30);
  assert.equal(new Set(seen.map((l) => l.key)).size, 30);
  const strict = await (await get("/v1/export?game=gta-v&min_installs=2")).json();
  assert.equal(strict.lines.length, 0);
});

test("dışa aktarma anahtar ister; anahtar yoksa kapalı", async () => {
  const { get } = setup();
  assert.equal((await get("/v1/export?game=gta-v", null)).status, 401);
  assert.equal((await get("/v1/games", "yanlis-anahtari")).status, 401);
  const closed = setup({ EXPORT_TOKEN: undefined });
  assert.equal((await closed.get("/v1/games")).status, 503);
});

test("kurulum kimliği sunucuda açık hâliyle tutulmaz", async () => {
  const { db, post } = setup();
  const install = randomUUID();
  await post(batch([line("Privacy check line.")], { install }));
  const rows = db.raw.prepare("SELECT install FROM batches UNION SELECT install FROM line_installs").all();
  assert.ok(rows.length > 0);
  for (const r of rows) assert.notEqual(r.install, install);
});

test("bakım eski parça kimliklerini siler", async () => {
  const { db, post } = setup();
  await post(batch([line("Old batch line.")]), NOW - 40 * 86400);
  await post(batch([line("New batch line.")]));
  await prune(db, NOW);
  assert.equal(db.raw.prepare("SELECT COUNT(*) AS n FROM batches").get().n, 1);
  assert.equal(db.raw.prepare("SELECT COUNT(*) AS n FROM lines").get().n, 2);
});

test("aynı anda iki kez gelen parça tek sayılır", async () => {
  const { post, get } = setup();
  const b = batch([line("Race line.", { count: 5 })]);
  const [a, c] = await Promise.all([post(b), post(b)]);
  assert.equal(a.status, 200);
  assert.equal(c.status, 200);
  const exp = await (await get("/v1/export?game=gta-v")).json();
  assert.equal(exp.lines[0].seen, 5);
});
