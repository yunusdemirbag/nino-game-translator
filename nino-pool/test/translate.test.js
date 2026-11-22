// SPDX-License-Identifier: AGPL-3.0-only
import { test } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { makeD1 } from "./d1-shim.js";
import { handle } from "../src/worker.js";
import { reviewTranslations, usable, translateCost, instructions } from "../src/translate.js";
import { lineKey } from "../src/key.js";

const NOW = 1763300000;

function setup(vars = {}, live) {
  const env = { DB: makeD1(), INSTALL_SALT: "tuz", ANTHROPIC_API_KEY: "k", ...vars };
  const calls = [];
  const fake = live ?? (async (_env, lang, lines, context) => {
    calls.push({ lang, lines, context });
    return { texts: lines.map((l) => `TR:${l}`), cost: 1000 };
  });
  const post = (body, now = NOW) =>
    handle(new Request("http://pool/v1/translate", { method: "POST", body: JSON.stringify(body) }), env, now, undefined, fake);
  const get = (query, now = NOW) => handle(new Request(`http://pool/v1/translations?${query}`), env, now);
  return { env, post, get, calls };
}
const req = (lines, extra = {}) => ({ v: 1, install: randomUUID(), app: "0.2.2", platform: "mac", lang: "tr", game: "gta-vi", lines, ...extra });

test("bilinmeyen satır o an çevrilir, ikinci oyuncu aynısını modelsiz alır", async () => {
  const { post, calls } = setup();
  let res = await post(req(["Get in the car!", "Shut the fuck up."], { context: ["Lucia, wait."] }));
  assert.equal(res.status, 200);
  let body = await res.json();
  assert.deepEqual(body.translations, [{ text: "TR:Get in the car!", tier: 1 }, { text: "TR:Shut the fuck up.", tier: 1 }]);
  assert.deepEqual(calls[0].context, ["Lucia, wait."]);
  // Aynı cümlenin başka yazılışı da aynı anahtar: model yeniden çağrılmaz.
  res = await post(req(["GET IN THE CAR"]));
  body = await res.json();
  assert.equal(body.translations[0].text, "TR:Get in the car!");
  assert.equal(calls.length, 1);
});

test("aynı istekte tekrar eden satır bir kez çevrilir", async () => {
  const { post, calls } = setup();
  const body = await (await post(req(["Move!", "move", "Go."]))).json();
  assert.equal(calls[0].lines.length, 2);
  assert.equal(body.translations[1].text, "TR:Move!");
});

test("günlük sınır dolunca model çağrılmaz, uygulama kendi çevirisine döner", async () => {
  const { post, calls, env } = setup({ TRANSLATE_DAILY_USD: "0.001" });
  await post(req(["One."]));
  const body = await (await post(req(["Two."]))).json();
  assert.equal(body.limited, "daily_cap");
  assert.equal(body.translations[0].text, null);
  assert.equal(calls.length, 1);
  const spent = await env.DB.prepare("SELECT micro_usd FROM translate_cost").first("micro_usd");
  assert.equal(spent, 1000);
});

test("model ret cevabı verirse çevrilemedi diye hatırlanır, yeniden ücretlendirilmez", async () => {
  let calls = 0;
  const { post, get } = setup({}, async (_e, _l, lines) => { calls++; return { texts: lines.map(() => "I'm sorry, I can't translate that."), cost: 5 }; });
  const body = await (await post(req(["You son of a bitch."]))).json();
  assert.equal(body.translations[0].text, null);
  const again = await (await post(req(["You son of a bitch."]))).json();
  assert.equal(again.translations[0].text, null);
  assert.equal(calls, 1);
  assert.equal((await (await get("lang=tr&since=0")).json()).items.length, 0);
  const { post: post2 } = setup({}, async () => ({ texts: ["tek"], cost: 5 }));
  const body2 = await (await post2(req(["One.", "Two."]))).json();
  assert.deepEqual(body2.translations.map((t) => t.text), [null, null]);
});

test("anahtar yoksa ya da kapalıysa çeviri yapılmaz ama bilinenler döner", async () => {
  const { post, env } = setup();
  await post(req(["Hello."]));
  env.ANTHROPIC_API_KEY = "";
  const body = await (await post(req(["Hello.", "Bye."]))).json();
  assert.equal(body.limited, "disabled");
  assert.deepEqual(body.translations.map((t) => t.text), ["TR:Hello.", null]);
});

test("bozuk istekler", async () => {
  const { post } = setup();
  assert.equal((await post({ v: 1, install: "x", lang: "tr", lines: ["a"] })).status, 400);
  assert.equal((await post(req(["a"], { lang: "fr" }))).status, 400);
  assert.equal((await post(req(Array.from({ length: 13 }, (_, i) => `Line ${i}`)))).status, 413);
  const body = await (await post(req(["!!!", "x".repeat(400), "Okay."]))).json();
  assert.deepEqual(body.translations.map((t) => t.text), [null, null, "TR:Okay."]);
});

test("toplu indirme: oyunun çevirileri ve sonradan değişenler, sayfalı", async () => {
  const { post, get } = setup();
  await post(req(["Alpha."]), NOW);
  await post(req(["Beta."], { game: "rdr2" }), NOW + 10);
  await post(req(["Gamma."], { lang: "ar" }), NOW + 20);
  let body = await (await get("lang=tr&game=gta-vi&since=0&_byGame=1", NOW + 30)).json();
  assert.equal(body.items.length, 1);
  // Oyun adı şimdilik süzmez: dilin bütün çevirileri gelir.
  assert.equal((await (await get("lang=tr&game=gta-vi&since=0", NOW + 30)).json()).items.length, 2);
  assert.equal(body.items[0][1], "TR:Alpha.");
  assert.equal(body.items[0][0], await lineKey("Alpha."));
  body = await (await get("lang=tr&since=0")).json();
  assert.equal(body.items.length, 2);
  body = await (await get(`lang=tr&since=${NOW}`)).json();
  assert.deepEqual(body.items.map((i) => i[1]), ["TR:Beta."]);
  assert.equal((await get("lang=xx")).status, 400);
});

test("gözden geçirme: güçlü model sırayla okur, değişen çeviri güncellenir ve yeniden indirilir", async () => {
  const { post, get, env } = setup();
  await post(req(["Where's the money?", "Relax."]), NOW);
  const seenBy = [];
  const review = async (_env, lang, game, items) => {
    seenBy.push({ lang, game, items });
    return { texts: items.map((i) => (i.source === "Relax." ? "Sakin ol be." : i.text)), cost: 2000 };
  };
  // Gecikme dolmadan gözden geçirilmez.
  let result = await reviewTranslations(env.DB, env, NOW + 60, review);
  assert.equal(result.reviewed, 0);
  result = await reviewTranslations(env.DB, env, NOW + 3600, review);
  assert.deepEqual(result, { reviewed: 2, changed: 1, cost: 2000 });
  assert.equal(seenBy[0].game, "gta-6");
  const body = await (await get(`lang=tr&since=${NOW}`, NOW + 3600)).json();
  assert.deepEqual(body.items.map((i) => [i[1], i[3]]), [["Sakin ol be.", 2]]);
  // Ret: parça işaretlenir, bir daha gönderilmez.
  await post(req(["Third line here."]), NOW + 100);
  let fails = 0;
  const refusing = async () => { fails++; return { texts: null, cost: 10 }; };
  assert.equal((await reviewTranslations(env.DB, env, NOW + 4000, refusing)).failed, 1);
  await reviewTranslations(env.DB, env, NOW + 6000, refusing);
  assert.equal(fails, 1);
  // İkinci tur: gözden geçirilmiş satırlar yeniden gitmez.
  result = await reviewTranslations(env.DB, env, NOW + 7200, review);
  assert.equal(result.reviewed, 0);
});

test("uzaktan ayar", async () => {
  const { env } = setup({ TRANSLATE_DEADLINE_MS: "700", MIN_VERSION_IOS: "0.2.2" });
  const body = await (await handle(new Request("http://pool/v1/config"), env, NOW)).json();
  assert.equal(body.translate.enabled, true);
  assert.equal(body.translate.deadlineMs, 700);
  assert.equal(body.minVersion.ios, "0.2.2");
  // Havuz öncelikli oyunlar: varsayılan GTA 6, bekleme 1500 ms.
  assert.deepEqual(body.poolFirst.games, ["grand-theft-auto-vi", "gta-vi", "gta-6", "gta6"]);
  assert.equal(body.poolFirst.deadlineMs, 1500);
});

test("uzaktan ayar: havuz öncelikli oyunlar ve bekleme değişebilir", async () => {
  const { env } = setup({ POOL_FIRST_GAMES: " GTA6 , mafia--the-old-country,", POOL_FIRST_DEADLINE_MS: "2000" });
  const body = await (await handle(new Request("http://pool/v1/config"), env, NOW)).json();
  assert.deepEqual(body.poolFirst.games, ["gta6", "mafia-the-old-country"]);
  assert.equal(body.poolFirst.deadlineMs, 2000);
  const { env: off } = setup({ POOL_FIRST_GAMES: "" });
  assert.deepEqual((await (await handle(new Request("http://pool/v1/config"), off, NOW)).json()).poolFirst.games, []);
});

test("yardımcılar", () => {
  assert.equal(usable("Fuck you!", "Siktir git!"), true);
  assert.equal(usable("Hi", ""), false);
  assert.equal(usable("Hi", "x".repeat(200)), false);
  assert.equal(translateCost("claude-haiku-5-5", { input_tokens: 1000, output_tokens: 1000 }), 600);
  assert.match(instructions("tr"), /Never soften, censor/);
  assert.match(instructions("tr"), /"sen"/);
});

test("Claude yalnız izinli oyunlarda çevirir", async () => {
  const { post, calls } = setup({ TRANSLATE_GAMES: "grand-theft-auto-vi,mafia" });
  let body = await (await post(req(["Hello there."], { game: "elden-ring" }))).json();
  assert.equal(body.limited, "game");
  assert.equal(calls.length, 0);
  body = await (await post(req(["Hello there."], { game: "" }))).json();
  assert.equal(body.limited, "game");
  body = await (await post(req(["Get in the car!"], { game: "grand-theft-auto-vi" }))).json();
  assert.equal(body.translations[0].text, "TR:Get in the car!");
  body = await (await post(req(["Move it."], { game: "mafia-the-old-country" }))).json();
  assert.equal(body.translations[0].text, "TR:Move it.");
  assert.equal(calls.length, 2);
});

test("oyun bildirilmese de GTA 6 satırlardan tanınır ve kurulum için hatırlanır", async () => {
  const { post, calls } = setup({ TRANSLATE_GAMES: "grand-theft-auto-vi" });
  const install = randomUUID();
  // İsim yok: tanınmaz, Claude çağrılmaz.
  let body = await (await post(req(["Get in the car."], { game: "", install }))).json();
  assert.equal(body.limited, "game");
  // Bağlamda Lucia geçti: GTA 6 tanınır.
  body = await (await post(req(["Drive, drive!"], { game: "", install, context: ["Lucia, you okay?"] }))).json();
  assert.equal(body.game, "gta-6");
  assert.equal(body.translations[0].text, "TR:Drive, drive!");
  // Sonraki isimsiz satır da aynı kurulumda GTA 6 sayılır.
  body = await (await post(req(["Hold on tight."], { game: "", install }, ), NOW + 600)).json();
  assert.equal(body.translations[0].text, "TR:Hold on tight.");
  assert.equal(calls.length, 2);
  // Başka kurulum etkilenmez.
  body = await (await post(req(["Hold on, man."], { game: "" }))).json();
  assert.equal(body.limited, "game");
});

test("oyun ekrandan tanınır, kurulum için hatırlanır ve çeviri o oyunla yapılır", async () => {
  const { env, calls } = setup({ TRANSLATE_GAMES: "grand-theft-auto-vi" });
  const install = randomUUID();
  const identify = async () => ({ game: "Grand Theft Auto VI", confidence: 0.95, cost: 500 });
  const res = await handle(new Request("http://pool/v1/identify", { method: "POST", body: JSON.stringify({ v: 1, install, image: "/9j/AAAA" }) }),
    env, NOW, undefined, undefined, identify);
  const body = await res.json();
  assert.deepEqual([body.game, body.id], ["Grand Theft Auto VI", "gta-6"]);
  const fake = async (_e, _l, lines) => { calls.push(lines); return { texts: lines.map((l) => "TR:" + l), cost: 1 }; };
  const t = await (await handle(new Request("http://pool/v1/translate", { method: "POST",
    body: JSON.stringify(req(["Hold on tight."], { game: "", install })) }), env, NOW + 60, undefined, fake)).json();
  assert.equal(t.translations[0].text, "TR:Hold on tight.");
  assert.equal(t.game, "gta-6");
  // Emin değilse oyun yazılmaz.
  const unsure = async () => ({ game: "Some Game", confidence: 0.3, cost: 1 });
  const u = await (await handle(new Request("http://pool/v1/identify", { method: "POST", body: JSON.stringify({ v: 1, install: randomUUID(), image: "/9j/AAAA" }) }),
    env, NOW, undefined, undefined, unsure)).json();
  assert.equal(u.game, null);
});

test("oyun havuzdaki satırdan da tanınır", async () => {
  const { post, calls } = setup({ TRANSLATE_GAMES: "grand-theft-auto-vi" });
  await post(req(["We hit the jewelry store at midnight, Jason."], { game: "grand-theft-auto-vi" }));
  const install = randomUUID();
  // Yeni oyuncu oyun adı göndermiyor; havuzda bilinen uzun satır geldi: GTA 6 tanınır.
  let body = await (await post(req(["We hit the jewelry store at midnight, Jason."], { game: "", install }))).json();
  assert.equal(body.game, "gta-6");
  // Sonraki yeni satırı da Claude çevirir.
  body = await (await post(req(["Grab the duffel bag."], { game: "", install }), NOW + 30)).json();
  assert.equal(body.translations[0].text, "TR:Grab the duffel bag.");
  assert.equal(calls.length, 2);
});

test("havuz öncelikli oyunun satırı, uygulama başka oyun sansa da o oyunu döndürür", async () => {
  const { post } = setup({ TRANSLATE_GAMES: "grand-theft-auto-vi" });
  const line = "I still can't believe I shacked up with a car thief.";
  let body = await (await post(req([line], { game: "grand-theft-auto-vi" }))).json();
  assert.equal(body.game, "gta-6");
  body = await (await post(req([line], { game: "call-of-duty-modern-warfare-2019" }))).json();
  assert.equal(body.game, "gta-6");
  assert.ok(body.translations[0].text);
  // Bilinmeyen satır ve başka oyun: oyun değişmez.
  body = await (await post(req(["A brand new line nobody has seen."], { game: "red-dead-redemption-2" }))).json();
  assert.equal(body.game, "red-dead-redemption-2");
});

test("GTA 6'ya özgü ad geçen satır, uygulama başka oyun sansa da GTA 6 sayılır", async () => {
  const { post } = setup({ TRANSLATE_GAMES: "grand-theft-auto-vi" });
  const body = await (await post(req(["Lucia, get in the car."], { game: "red-dead-redemption-2" }))).json();
  assert.equal(body.game, "gta-6");
  assert.ok(body.translations[0].text);
});

test("GTA VI oynayan kurulumda ekran GTA V sanılırsa GTA VI sayılır", async () => {
  const { env } = setup({ TRANSLATE_GAMES: "grand-theft-auto-vi" });
  const install = randomUUID();
  const fake = async (_e, _l, lines) => ({ texts: lines.map((l) => "TR:" + l), cost: 1 });
  await handle(new Request("http://pool/v1/translate", { method: "POST",
    body: JSON.stringify(req(["Lucia, get in the car."], { game: "", install })) }), env, NOW, undefined, fake);
  const wrong = async () => ({ game: "Grand Theft Auto V", confidence: 0.9, cost: 1 });
  const body = await (await handle(new Request("http://pool/v1/identify", { method: "POST", body: JSON.stringify({ v: 1, install, image: "/9j/AAAA" }) }),
    env, NOW + 60, undefined, undefined, wrong)).json();
  assert.equal(body.id, "gta-6");
  // Başka kurulumda gerçek GTA V olduğu gibi kalır.
  const other = await (await handle(new Request("http://pool/v1/identify", { method: "POST", body: JSON.stringify({ v: 1, install: randomUUID(), image: "/9j/AAAA" }) }),
    env, NOW + 60, undefined, undefined, wrong)).json();
  assert.equal(other.id, "gta-v");
});

test("çöp satırlar Claude'a gitmez, İngilizcesi havuza yazılır", async () => {
  const { post, calls, env } = setup();
  const res = await (await post(req(["RESTORE ALL (A) RESTORE DEFAULT", "Eklenti Yüklenmesi gerekmiyor", "XIS", "GET DOWN!", "Hi."]))).json();
  assert.deepEqual(res.translations.map((t) => t.text), [null, null, null, "TR:GET DOWN!", "TR:Hi."]);
  assert.deepEqual(calls[0].lines, ["GET DOWN!", "Hi."]);
  const saved = env.DB.raw.prepare("SELECT text FROM lines ORDER BY text").all().map((r) => r.text);
  assert.deepEqual(saved, ["Eklenti Yüklenmesi gerekmiyor", "RESTORE ALL (A) RESTORE DEFAULT", "XIS"]);
});

test("ekran okumasının bozduğu kopya havuzdaki çeviriyi alır, Claude'a sorulmaz", async () => {
  const { post, calls } = setup();
  await post(req(["Looks like I'm gonna need to come back when I have a little more cash."]));
  const res = await (await post(req(["Looks Iike lI'm gonna need to come back when I have a little more cash.", "Where did you park the truck?"]))).json();
  assert.equal(res.translations[0].text, "TR:Looks like I'm gonna need to come back when I have a little more cash.");
  assert.equal(calls.length, 2);
  assert.deepEqual(calls[1].lines, ["Where did you park the truck?"]);
  // Sayısı ya da olumsuzluğu farklı olan eşleşmez.
  await post(req(["I really want to go back to the boat tonight."]));
  await post(req(["I really don't want to go back to the boat tonight."]));
  assert.deepEqual(calls.at(-1).lines, ["I really don't want to go back to the boat tonight."]);
});

test("Claude yalnız izinli dillerde çevirir; öbürlerinde havuzdakiler yine döner", async () => {
  const { post, calls, env } = setup();
  const res = await (await post(req(["Where's the money?"], { lang: "ar" }))).json();
  assert.equal(res.translations[0].text, null);
  assert.equal(res.limited, "lang");
  assert.equal(calls.length, 0);
  env.DB.raw.prepare("INSERT INTO translations (key, lang, game, source, text, tier, created, updated) VALUES (?, 'ar', '', ?, ?, 1, 0, 0)")
    .run(await lineKey("Relax."), "Relax.", "اهدأ.");
  const known = await (await post(req(["Relax."], { lang: "ar" }))).json();
  assert.equal(known.translations[0].text, "اهدأ.");
  const body = await (await handle(new Request("http://pool/v1/config"), env, NOW)).json();
  assert.deepEqual(body.poolFirst.langs, ["tr"]);
  const { post: postAll, calls: allCalls } = setup({ TRANSLATE_LANGS: "tr,ar" });
  await postAll(req(["Where's the money?"], { lang: "ar" }));
  assert.equal(allCalls.length, 1);
});

test("gözden geçirme toplu işlemle: gönderilir, bekleyen yeniden gönderilmez, bitince yazılır ve yarı fiyat sayılır", async () => {
  const { post, env } = setup();
  await post(req(["Where's the money?", "Relax.", "RESTORE ALL (A) RESTORE DEFAULT"]), NOW);
  const created = [];
  let ended = false;
  const fake = {
    async create(requests) { created.push(requests); return { id: `b${created.length}` }; },
    async retrieve() { return { processing_status: ended ? "ended" : "in_progress" }; },
    async results() {
      const params = created[0][0].params;
      assert.equal(params.model, "claude-opus-5-5");
      assert.equal(params.output_config.effort, "medium");
      const n = Number(params.messages[0].content.match(/(\d+)\. EN: Relax\./)[1]);
      const content = JSON.stringify({ lines: [{ n, text: "Sakin ol be." }] });
      return [{ custom_id: "c0", result: { type: "succeeded", message: { stop_reason: "end_turn", content: [{ type: "text", text: content }],
        usage: { input_tokens: 1000, output_tokens: 1000 } } } }];
    },
  };
  let result = await reviewTranslations(env.DB, env, NOW + 3600, undefined, undefined, fake);
  assert.equal(result.submitted, 1);
  assert.equal(created[0].length, 1);
  // Çöp satır gönderilmez (havuza zaten çevrilmeden girmezdi); yalnız iki satır.
  assert.match(created[0][0].params.messages[0].content, /Review these 2 subtitle/);
  result = await reviewTranslations(env.DB, env, NOW + 5400, undefined, undefined, fake);
  assert.equal(result.submitted, 0);
  assert.equal(created.length, 1);
  ended = true;
  result = await reviewTranslations(env.DB, env, NOW + 7200, undefined, undefined, fake);
  assert.equal(result.reviewed, 2);
  assert.equal(result.changed, 1);
  assert.equal(result.cost, Math.ceil(translateCost("claude-opus-5-5", { input_tokens: 1000, output_tokens: 1000 }) / 2));
  const rows = env.DB.raw.prepare("SELECT source, text, tier FROM translations ORDER BY source").all().map((r) => [r.source, r.text, r.tier]);
  assert.deepEqual(rows, [["Relax.", "Sakin ol be.", 2], ["Where's the money?", "TR:Where's the money?", 2]]);
  assert.equal(env.DB.raw.prepare("SELECT COUNT(*) n FROM review_pending").get().n, 0);
});

test("yol tarifi kuralla çevrilir: model çağrılmaz, havuza yazılmaz", async () => {
  const { env, post, calls } = setup();
  const res = await post(req(["Turn Right 405 ft 432 ft", "Keep Left O ft 2 ft", "U-Turn Left 5 ft 24 ft", "Turn Left 366 ft—", "Turn right at the lights, okay?"]));
  const body = await res.json();
  assert.deepEqual(body.translations.slice(0, 4).map((t) => t.text),
    ["Sağa dön 405 ft 432 ft", "Solda kal 0 ft 2 ft", "Sola U dönüşü 5 ft 24 ft", "Sola dön 366 ft"]);
  // Arkasında söz olan cümle altyazıdır: modele gider.
  assert.deepEqual(calls.map((c) => c.lines), [["Turn right at the lights, okay?"]]);
  const { results } = await env.DB.prepare("SELECT source FROM translations").all();
  assert.deepEqual(results.map((r) => r.source), ["Turn right at the lights, okay?"]);
});

test("yol tarifi kuralı: yalnız yön ve mesafe", async () => {
  const { navTranslation } = await import("../src/nav.js");
  assert.equal(navTranslation("Keep Right 304 ft 303 ft", "tr"), "Sağda kal 304 ft 303 ft");
  assert.equal(navTranslation("-turn Right 67 ft 82 ft", "tr"), "Sağa dön 67 ft 82 ft");
  assert.equal(navTranslation("Turn Right i 100 ft 103 ft", "tr"), "Sağa dön 100 ft 103 ft");
  assert.equal(navTranslation("Turn Right 3.9 km", "tr"), "Sağa dön 3.9 km");
  assert.equal(navTranslation("Turn Right", "tr"), null);
  assert.equal(navTranslation("Keep left and you'll be fine, 20 ft or so", "tr"), null);
  assert.equal(navTranslation("Turn Right 405 ft", "ar"), null);
});

test("hazır çeviri tohumu: modelden önce bakılır, günlük sınır dolsa da cevaplar, havuza İngilizcesiyle yazılır", async () => {
  const { env, post, get, calls } = setup({ TRANSLATE_DAILY_USD: "0" });
  const key = await lineKey("You made it through half a scuba tour.");
  await env.DB.prepare("INSERT INTO seeds (lang, key, text) VALUES ('tr', ?, 'Tüplü dalış turunun yarısını tamamladın.')").bind(key).run();
  let res = await post(req(["You made it through half a scuba tour.", "Never seen before."]));
  let body = await res.json();
  assert.deepEqual(body.translations, [{ text: "Tüplü dalış turunun yarısını tamamladın.", tier: 1 }, { text: null, tier: 0 }]);
  assert.equal(body.limited, "daily_cap");
  assert.equal(calls.length, 0);
  const row = await env.DB.prepare("SELECT source, text, tier FROM translations WHERE key = ?").bind(key).first();
  assert.deepEqual(row, { source: "You made it through half a scuba tour.", text: "Tüplü dalış turunun yarısını tamamladın.", tier: 1 });
  // Kullanılan tohum toplu indirmeye de girer; kullanılmayanlar girmez.
  res = await get("lang=tr&game=gta-vi&since=0");
  body = await res.json();
  assert.equal(body.items.length, 1);
  // Başka dilde tohum kullanılmaz.
  res = await post(req(["You made it through half a scuba tour."], { lang: "ar" }));
  body = await res.json();
  assert.equal(body.translations[0].text, null);
});

test("uzaktan ayar: saklanan toplam indirme verilir; yoksa alan gönderilmez", async () => {
  const { env } = setup();
  let body = await (await handle(new Request("http://pool/v1/config"), env, NOW)).json();
  assert.equal("downloads" in body, false);
  await env.DB.prepare("INSERT INTO stats_cache (key, value, at) VALUES ('downloads', ?, ?)")
    .bind(JSON.stringify({ mac: 10, windows: 20, android: 30, tv: 5, total: 65, latest: "v3.4.1" }), NOW).run();
  body = await (await handle(new Request("http://pool/v1/config"), env, NOW)).json();
  assert.equal(body.downloads, 65);
  assert.equal(body.ok, true);
});

test("birleşik satır havuzdaki cümlelerinden kurulur, Claude'a sorulmaz, havuza yazılmaz", async () => {
  const { env, post, calls } = setup();
  await post(req(["Okay, let me get back to the guys.", "Not too far now."]));
  await env.DB.prepare("INSERT INTO seeds (lang, key, text) VALUES ('tr', ?, 'Kapa çeneni!')").bind(await lineKey("Shut up!")).run();
  const body = await (await post(req(["Okay, let me get back to the guys. Not too far now.", "Lucia: Shut up!", "Lucia: Where is the boat?"]))).json();
  assert.equal(body.translations[0].text, "TR:Okay, let me get back to the guys. TR:Not too far now.");
  assert.equal(body.translations[1].text, "Lucia: Kapa çeneni!");
  // Bir cümlesi eksik olan Claude'a gider.
  assert.deepEqual(calls.at(-1).lines, ["Lucia: Where is the boat?"]);
  const n = env.DB.raw.prepare("SELECT COUNT(*) n FROM translations WHERE source LIKE '%Not too far now.%' AND source LIKE 'Okay%'").get().n;
  assert.equal(n, 0);
});

test("anlamsız okunmuş satır Claude'a gitmez; tek nadir sözcük satırı düşürmez", async () => {
  const { post, calls } = setup();
  const body = await (await post(req(["Okay, lopkin gont yo wannaa startann the engine?", "Grab the duffel bag."]))).json();
  assert.equal(body.translations[0].text, null);
  assert.deepEqual(calls.map((c) => c.lines), [["Grab the duffel bag."]]);
});

test("bozuk kopyalar ve hazır tohum ayrıca gözden geçirilmez; kopya aslının yeni metnini alır", async () => {
  const { post, env } = setup();
  await post(req(["Looks like I'm gonna need to come back when I have a little more cash."]), NOW);
  await post(req(["Looks Iike lI'm gonna need to come back when I have a little more cash."]), NOW + 1);
  await env.DB.prepare("INSERT INTO seeds (lang, key, text) VALUES ('tr', ?, 'Kasabaya dön.')").bind(await lineKey("Head back to town.")).run();
  await post(req(["Head back to town."]), NOW + 2);
  const created = [];
  const fake = {
    async create(requests) { created.push(requests); return { id: "b1" }; },
    async retrieve() { return { processing_status: "ended" }; },
    async results() {
      const content = JSON.stringify({ lines: [{ n: 1, text: "Biraz daha param olunca gelmem lazım galiba." }] });
      return [{ custom_id: "c0", result: { type: "succeeded", message: { stop_reason: "end_turn", content: [{ type: "text", text: content }],
        usage: { input_tokens: 1000, output_tokens: 1000 } } } }];
    },
  };
  await reviewTranslations(env.DB, env, NOW + 3600, undefined, undefined, fake);
  assert.equal(created.length, 1);
  assert.match(created[0][0].params.messages[0].content, /Review these 1 subtitle/);
  await reviewTranslations(env.DB, env, NOW + 7200, undefined, undefined, fake);
  const rows = env.DB.raw.prepare("SELECT source, text, tier FROM translations ORDER BY source").all().map((r) => [r.source, r.text, r.tier]);
  assert.deepEqual(rows, [
    ["Head back to town.", "Kasabaya dön.", 1],
    ["Looks Iike lI'm gonna need to come back when I have a little more cash.", "Biraz daha param olunca gelmem lazım galiba.", 2],
    ["Looks like I'm gonna need to come back when I have a little more cash.", "Biraz daha param olunca gelmem lazım galiba.", 2],
  ]);
  const cost = env.DB.raw.prepare("SELECT micro_usd, review_micro_usd FROM translate_cost").get();
  assert.equal(cost.review_micro_usd, Math.ceil(translateCost("claude-opus-5-5", { input_tokens: 1000, output_tokens: 1000 }) / 2));
  assert.ok(cost.micro_usd > cost.review_micro_usd);
});
