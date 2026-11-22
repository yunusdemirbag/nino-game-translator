// SPDX-License-Identifier: AGPL-3.0-only
// Hazır cevap kütüphanesi (assistant/hazir-cevaplar.json), eşleme ve ana/yedek model sırası.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { randomUUID } from "node:crypto";
import { makeD1 } from "./d1-shim.js";
import { handle } from "../src/worker.js";
import { askModel, QuotaError, assistantStats, assistantEnabled } from "../src/assistant.js";
import { ANSWERS } from "../src/answers.js";
import { prepareLibrary, matchAnswer, normalize } from "../src/answers-match.js";

const NOW = 1763300000;
const TOKEN = "deneme-anahtari";
const LANGS = ["tr", "en", "ar", "hi", "id", "th", "vi", "ur", "bn", "ms", "fil", "nl"];
const json = JSON.parse(readFileSync(new URL("../assistant/hazir-cevaplar.json", import.meta.url), "utf8"));
const library = prepareLibrary(ANSWERS);
const questions = JSON.parse(readFileSync(new URL("../assistant/deneme-sorulari.json", import.meta.url), "utf8"));
const entry = (id) => ANSWERS.entries.find((e) => e.id === id);

const user = (text, images = []) => ({ role: "user", text, images });
const bot = (text) => ({ role: "assistant", text, images: [] });
const match = (messages, language = "tr", platform = "android") => matchAnswer(library, { language, platform, messages });

function* replies() {
  for (const [lang, text] of Object.entries(json.busy)) if (lang !== "_") yield { id: "busy", lang, text };
  for (const e of json.entries) {
    for (const [lang, text] of Object.entries(e.reply)) yield { id: e.id, lang, text };
    for (const [platform, byLang] of Object.entries(e.variants ?? {})) {
      for (const [lang, text] of Object.entries(byLang)) yield { id: `${e.id}/${platform}`, lang, text };
    }
  }
}

test("üretilen src/answers.js JSON ile aynı (npm run answers)", () => {
  const { _, ...data } = json;
  const { _: note, ...busy } = data.busy;
  assert.deepEqual(ANSWERS, { ...data, busy });
});

test("kütüphane: her konu 12 dilde, kimlikler tutarlı", () => {
  const ids = new Set();
  for (const e of json.entries) {
    assert.ok(!ids.has(e.id), `tekrarlanan kimlik ${e.id}`);
    ids.add(e.id);
    // "langs": yalnız bu dillerde yazılmış adım adım TV rehberi (öbür dillerde soru modele gider).
    for (const lang of e.replyOf ? [] : e.langs ?? LANGS) {
      assert.ok(e.reply[lang]?.trim(), `${e.id}: ${lang} cevabı yok`);
      for (const [platform, byLang] of Object.entries(e.variants ?? {})) assert.ok(byLang[lang]?.trim(), `${e.id}/${platform}: ${lang} yok`);
    }
    for (const platform of Object.keys(e.variants ?? {})) assert.ok(["android", "ios", "desktop"].includes(platform), platform);
    assert.ok(Object.values(e.triggers).flat().length, `${e.id}: tetikleyici yok`);
  }
  for (const e of json.entries) for (const id of e.after ?? []) assert.ok(ids.has(id), `${e.id}: bilinmeyen after ${id}`);
  for (const lang of LANGS) assert.ok(json.busy[lang]?.trim(), `son çare cevabı: ${lang} yok`);
});

test("kütüphane: yardımcının biçim kuralları (düz metin, tek soru, sürüm numarası ve kişisel veri yok)", () => {
  for (const { id, lang, text } of replies()) {
    const where = `${id} [${lang}]`;
    // Tırnak içindeki ekran yazısı ("İzin verilsin mi?") soru sayılmaz.
    assert.ok((text.replace(/["“«][^"”»]*["”»]/g, "").match(/[?؟]/g) ?? []).length <= 1, `${where}: birden çok soru`);
    assert.doesNotMatch(text, /\*\*|^#|\[[^\]]+\]\(/m, `${where}: markdown`);
    assert.doesNotMatch(text, /@[\w-]+\.\w/, `${where}: e-posta`);
    assert.doesNotMatch(text, /\bV?\d\.\d(\.\d)?\b/, `${where}: sürüm numarası`);
    if (lang !== "tr") assert.doesNotMatch(text, /[ğışĞİŞ]|Ayarlar|Kur ve aç|TV.ye Kur/, `${where}: Türkçe kalmış`);
    // Numaralı adımlar kendi satırında.
    for (const step of text.match(/(?<![\p{L}\p{N}.])\d\. /gu) ?? []) assert.ok(new RegExp(`(^|\\n)${step.trim().replace(".", "\\.")} `).test(text), `${where}: adım satır başında değil`);
  }
});

test("öneri düğmeleri her dilde doğrudan hazır cevap alır", () => {
  // Uygulamaların öneri düğmeleri (nino-android values-*/strings.xml assistant_chip_1..4).
  const chips = {
    tr: ["PS5 + TV + telefon", "PS5 + monitör + bilgisayar", "Xbox + TV", "TV uygulamasını nasıl kurarım?"],
    en: ["PS5 + TV + phone", "PS5 + monitor + computer", "Xbox + TV", "How do I install the TV app?"],
    ar: ["PS5 + تلفاز + هاتف", "PS5 + شاشة + كمبيوتر", "Xbox + تلفاز", "كيف أثبّت تطبيق التلفاز؟"],
    hi: ["PS5 + TV + फ़ोन", "PS5 + मॉनिटर + कंप्यूटर", "Xbox + TV", "TV ऐप कैसे इंस्टॉल करूँ?"],
    id: ["PS5 + TV + ponsel", "PS5 + monitor + komputer", "Xbox + TV", "Cara pasang aplikasi TV?"],
    th: ["PS5 + TV + โทรศัพท์", "PS5 + จอมอนิเตอร์ + คอมพิวเตอร์", "Xbox + TV", "ติดตั้งแอป TV ยังไง?"],
    vi: ["PS5 + TV + điện thoại", "PS5 + màn hình + máy tính", "Xbox + TV", "Cài ứng dụng TV thế nào?"],
    ur: ["PS5 + TV + فون", "PS5 + مانیٹر + کمپیوٹر", "Xbox + TV", "TV ایپ کیسے انسٹال کروں؟"],
    bn: ["PS5 + TV + ফোন", "PS5 + মনিটর + কম্পিউটার", "Xbox + TV", "TV অ্যাপ কীভাবে ইনস্টল করব?"],
    ms: ["PS5 + TV + telefon", "PS5 + monitor + komputer", "Xbox + TV", "Cara pasang apl TV?"],
    fil: ["PS5 + TV + phone", "PS5 + monitor + computer", "Xbox + TV", "Paano i-install ang TV app?"],
    nl: ["PS5 + TV + telefoon", "PS5 + monitor + computer", "Xbox + TV", "Hoe installeer ik de TV-app?"],
  };
  const expected = ["kurulum-ps5-tv", "kurulum-ps5-monitor", "kurulum-xbox-tv", "tv-uygulamasi-kurulum"];
  for (const [lang, list] of Object.entries(chips)) {
    list.forEach((text, i) => {
      const m = match([user(text)], lang);
      assert.ok(m?.direct, `${lang}: "${text}" doğrudan değil (${m?.id})`);
      assert.equal(m.id, expected[i], `${lang}: "${text}"`);
      assert.equal(m.lang, lang, `${lang}: "${text}" cevap dili`);
    });
  }
});

test("marka cevabı ve ardından kurulum adımı (sohbetin 2. ve 3. adımı)", () => {
  const chip = entry("kurulum-ps5-tv").reply.tr;
  const tcl = match([user("PS5 + TV + telefon"), bot(chip), user("TCL 55C805")]);
  assert.equal(tcl.id, "marka-android-tv");
  assert.ok(tcl.direct);
  assert.equal(match([user("PS5 + TV + telefon"), bot(chip), user("Samsung")]).id, "marka-samsung");
  assert.equal(match([user("PS5 + TV + telefon"), bot(chip), user("lg")]).id, "marka-lg");
  // Bilinmeyen marka ya da iki marka: model karar verir.
  assert.equal(match([user("PS5 + TV + telefon"), bot(chip), user("Sunny webOS")]), null);
  // Vestel'in bazılarında geliştirici seçeneği yok: model sorar.
  assert.equal(match([user("PS5 + TV + telefon"), bot(chip), user("Vestel")]), null);
  assert.ok(!match([user("PS5 + TV + telefon"), bot(chip), user("Samsung 2014 model")])?.direct);
  assert.ok(!match([user("PS5 + TV + telefon"), bot(chip), user("samsung mu lg mi bilmiyorum")])?.direct);
  // Arapça sohbette marka adı Arapça cevap alır.
  const chipAr = entry("kurulum-ps5-tv").reply.ar;
  assert.equal(match([user("PS5 + تلفاز + هاتف"), bot(chipAr), user("TCL")], "tr").lang, "ar");

  // Adım adım: her cevap tek adım ve tek kontrol sorusu; "tamam" bir sonraki adımı getirir.
  const steps = entry("marka-android-tv").reply.tr;
  assert.equal(match([user("x"), bot(steps), user("tamam")]).id, "atv-2");
  const atv3 = entry("atv-3").reply.tr;
  const ios = match([user("x"), bot(atv3), user("tamam")], "tr", "ios");
  assert.ok(ios.direct);
  assert.equal(ios.id, "atv-4");
  assert.match(ios.reply, /TV uygulamasını bu telefonla yükle/);
  assert.match(match([user("x"), bot(atv3), user("yaptım")], "tr", "android").reply, /Profil › "TV'ye Nino'yu Kur"/);
  assert.match(match([user("x"), bot(entry("atv-3").reply.en), user("ok")], "en", "windows").reply, /Redo setup starting at the TV/);
  // Arapça zincir Arapça sürer.
  assert.equal(match([user("x"), bot(entry("atv-2").reply.ar), user("تم")], "tr").lang, "ar");
  // Başka dilde (ör. Tayca) adım adım rehber yok: model.
  assert.ok(!match([user("PS5 + TV + โทรศัพท์"), bot(entry("kurulum-ps5-tv").reply.th), user("TCL")], "th")?.direct);
  // "Yaptım ama…", "bulamadım": modele.
  assert.ok(!match([user("x"), bot(steps), user("yaptım ama geliştirici seçenekleri yok")])?.direct);
  assert.equal(match([user("x"), bot(steps), user("bulamadım")]), null);
  // "tamam" yalnız bizim marka cevabımızdan sonra anlamlı.
  assert.equal(match([user("tamam")]), null);
  assert.equal(match([user("x"), bot("Başka bir şey"), user("tamam")]), null);
});

test("sık takılma noktaları sohbetin ortasında da modelsiz cevaplanır", () => {
  const mid = (text, lang = "tr", platform = "android") => match([user("PS5 + TV + telefon"), bot("Başka bir şey"), user(text)], lang, platform);
  assert.equal(mid("Host PC IP nerede").id, "ip-nerede");
  assert.match(mid("Host PC IP nerede").reply, /büyük mavi rakamlarla/);
  assert.match(mid("ip nerede", "tr", "mac").reply, /TV için Nino uygulaması/);
  assert.equal(mid("paket geçersiz diyor").id, "paket-gecersiz");
  assert.equal(mid("tv listede çıkmıyor").id, "tv-listede-yok");
  // "Aynı wifi'de" çoğu zaman modelin sorusuna cevaptır: ortada hazır cevap verilmez.
  assert.equal(mid("aynı wifi de"), null);
  assert.equal(mid("TV YE KURU BULAMIYORUM"), null);
  assert.equal(mid("geliştirici modu kapandı").id, "gelistirici-kapandi");
  assert.equal(mid("الحزمة غير صالحة").lang, "ar");
  // Ayrıntılı ya da genel soru sohbetin ortasında modele kalır.
  assert.equal(mid("ücretsiz mi"), null);
  assert.equal(mid("ip nerede ama samsungda kutu gri ve değişmiyor"), null);
  // Selamdan sonraki cevap ilk soru gibi.
  assert.equal(match([user("merhaba"), bot(entry("selam").reply.tr), user("ps5 tv telefon")]).id, "kurulum-ps5-tv");
  // "Samsung adımlarını anlatayım mı?" → "evet" → 1. adım; sonra 2. adım.
  const yes = match([user("Samsung tv destekleniyor mu"), bot(entry("samsung-destek").reply.tr), user("evet")]);
  assert.equal(yes.reply, entry("marka-samsung").reply.tr);
  assert.equal(match([user("x"), bot(yes.reply), user("geldim")]).id, "sam-2");
});

test("ayrıntılı ya da resimli soru doğrudan cevap almaz (ipucu olur)", () => {
  assert.ok(match([user("ücretsiz mi")]).direct);
  assert.ok(!match([user("ücretsiz mi", [{ mime: "image/png", data: "AAAA" }])])?.direct);
  assert.ok(!match([user("herşeyi kurdum tvde altyazı gözükmüyor")])?.direct);
  assert.ok(!match([user("ps5 bağlantıyı reddetti hatasını alıyorum (kod 0x80108b26)")])?.direct);
  assert.equal(match([user("bana python ile bir web sitesi yazar mısın")]), null);
  // Sohbetin ortasındaki SSS sorusu modele kalır (bağlam önemli).
  assert.equal(match([user("selam"), bot("Merhaba"), user("ücretsiz mi")]), null);
  // Tek sözcüklü tetikleyici + başka sözcük: doğrudan değil ("switch user" ≠ Nintendo Switch).
  assert.ok(!match([user("switch user")], "en")?.direct);
  assert.ok(match([user("switch")], "en").direct);
});

test("deneme soruları: doğrudan verilen hazır cevap beklenen bilgiyi içerir", () => {
  for (const item of questions) {
    const m = match([user(item.q)], item.lang);
    if (item.expectReport) { assert.ok(!m?.direct, `bildirim gereken soru hazır cevap aldı: ${item.q}`); continue; }
    if (!m?.direct) continue;
    for (const pattern of item.must) assert.match(m.reply, new RegExp(pattern, "i"), `${item.q} → ${m.id}`);
    for (const pattern of item.mustNot) assert.doesNotMatch(m.reply, new RegExp(pattern), `${item.q} → ${m.id}`);
  }
});

test("normalleştirme: Türkçe harfler, kesme işareti, Arapça harekeler", () => {
  assert.equal(normalize("TV'Yİ KURDUM"), "tv yi kurdum");
  assert.equal(normalize("ŞİFRE ığüöç"), "sifre iguoc");
  assert.equal(normalize("كيف أثبّت"), "كيف اثبت");
});

// ---- Sunucu akışı ----

function setup(vars = {}, ask) {
  const env = { DB: makeD1(), EXPORT_TOKEN: TOKEN, INSTALL_SALT: "tuz", ASSISTANT_PROVIDER: "gemini", GEMINI_API_KEY: "k",
    ASSISTANT_FALLBACK: "openrouter", OPENROUTER_API_KEY: "o", ASSISTANT_FALLBACK_MODEL: "google/gemini-2.5-flash-lite", ...vars };
  const calls = [];
  const fake = ask ?? (async (_env, system, messages, target) => { calls.push({ system, messages, target }); return { reply: `${target.role} cevabı`, report: null, cost: 1000 }; });
  const post = (body) => handle(new Request("http://pool/v1/assistant", { method: "POST", body: JSON.stringify(body) }), env, NOW, fake);
  return { env, post, calls };
}
const chat = (messages, extra = {}) => ({ v: 1, install: randomUUID(), app: "4.0.0", platform: "android", language: "tr", messages, ...extra });

test("hazır cevap modele gitmez; panel sayaçları", async () => {
  const { post, calls, env } = setup();
  const res = await post(chat([{ role: "user", text: "PS5 + TV + telefon" }]));
  assert.equal(res.status, 200);
  assert.equal((await res.json()).reply, entry("kurulum-ps5-tv").reply.tr);
  assert.equal(calls.length, 0);
  await post(chat([{ role: "user", text: "Vestel TV'mde ses gidiyor" }]));
  assert.equal(calls.length, 1);
  assert.equal(calls[0].target.role, "primary");
  const stats = await assistantStats(env.DB, env, NOW);
  assert.equal(stats.library, 1);
  assert.equal(stats.primary, 1);
  assert.equal(stats.readyRate, 0.5);
  assert.deepEqual(stats.topics, [{ id: "kurulum-ps5-tv", n: 1 }]);
  assert.equal(stats.fallbackModel, "google/gemini-2.5-flash-lite");
  const panel = await (await handle(new Request("http://pool/v1/stats", { headers: { authorization: `Bearer ${TOKEN}` } }), { ...env, STATS_GITHUB: "0" }, NOW)).json();
  assert.equal(panel.assistant.library, 1);
});

test("emin olunmayan soruda hazır cevap modele ipucu olarak gider", async () => {
  const { post, calls } = setup();
  await post(chat([{ role: "user", text: "herşeyi kurdum tvde altyazı gözükmüyor" }]));
  assert.equal(calls.length, 1);
  assert.match(calls[0].system, /PREPARED ANSWER/);
  assert.ok(calls[0].system.includes(entry("altyazi-cikmiyor").reply.tr));
});

test("ana modelin sınırı dolunca yedek model; ikisi de dolunca yoğunum ya da benzer hazır cevap", async () => {
  const { post, calls, env } = setup({ ASSISTANT_DAILY_USD: "0.004", ASSISTANT_FALLBACK_DAILY_USD: "0.002" },
    async (_env, _system, _messages, target) => { calls.push(target.role); return { reply: target.role, report: null, cost: target.role === "primary" ? undefined : 1500 }; });
  const ask = async (text) => post(chat([{ role: "user", text }]));
  assert.equal((await (await ask("birinci soru burada")).json()).reply, "primary"); // 0,005 sayılır → sınır doldu
  assert.equal((await (await ask("ikinci soru burada")).json()).reply, "fallback"); // 0,0015 gerçek
  assert.equal((await (await ask("üçüncü soru burada")).json()).reply, "fallback"); // 0,003 → doldu
  // Tavan dolu: model çağrılmaz, robot takılmaz; kullanıcının dilinde "şu an yoğunum" cevabı.
  const busy = await ask("dördüncü soru burada");
  assert.equal(busy.status, 200);
  assert.equal((await busy.json()).reply, ANSWERS.busy.tr);
  const busyAr = await post(chat([{ role: "user", text: "سؤال رابع هنا" }]));
  assert.equal((await busyAr.json()).reply, ANSWERS.busy.ar);
  // Benzer hazır cevap varsa "yoğunum" yerine o verilir.
  const near = await ask("herşeyi kurdum tvde altyazı gözükmüyor");
  assert.equal(near.status, 200);
  assert.equal((await near.json()).reply, entry("altyazi-cikmiyor").reply.tr);
  assert.deepEqual(calls, ["primary", "fallback", "fallback"]);
  const stats = await assistantStats(env.DB, env, NOW);
  assert.equal(stats.fallbackUsd, 0.003);
  assert.equal(stats.busy, 2);
  assert.equal(stats.busyLibrary, 1);
});

test("sohbet adımları sunucuda modelsiz yürür: öneri → marka → tamam", async () => {
  const { post, calls } = setup();
  const install = randomUUID();
  const history = [{ role: "user", text: "PS5 + TV + telefon" }];
  for (const next of ["TCL", "tamam"]) {
    const res = await post(chat(history, { install }));
    history.push({ role: "assistant", text: (await res.json()).reply }, { role: "user", text: next });
  }
  const last = await (await post(chat(history, { install }))).json();
  assert.match(last.reply, /Hakkında ekranında aşağı in/);
  assert.equal(calls.length, 0);
});

test("ana model sınırda, yedek hata verirse 'yoğunum' cevabı", async () => {
  const { post } = setup({ ASSISTANT_DAILY_USD: "0" }, async () => { throw new Error("openrouter 500"); });
  const res = await post(chat([{ role: "user", text: "birinci soru burada" }], { language: "en" }));
  assert.equal(res.status, 200);
  assert.equal((await res.json()).reply, ANSWERS.busy.en);
});

test("ana model OpenRouter: gerçek maliyet kendi sayacında, Gemini'nin sayılan harcaması engel değil", async () => {
  const seen = [];
  const { post, env } = setup({ ASSISTANT_PROVIDER: "openrouter", ASSISTANT_MODEL: "google/gemini-2.5-flash-lite", ASSISTANT_FALLBACK: "0",
    ASSISTANT_DAILY_USD: "0.003" }, async (_env, _s, _m, target) => { seen.push(`${target.role}:${target.provider}`); return { reply: "or", report: null, cost: 2000 }; });
  // Gemini'den kalan sayılan harcama (assistant_cost) OpenRouter'ı durdurmaz.
  await env.DB.prepare("INSERT INTO assistant_cost (day, micro_usd) VALUES (?, ?)").bind(Math.floor(NOW / 86400), 2_000_000).run();
  assert.equal((await (await post(chat([{ role: "user", text: "birinci soru burada" }]))).json()).reply, "or");
  assert.equal((await (await post(chat([{ role: "user", text: "ikinci soru burada" }]))).json()).reply, "or"); // 0,004 $ → doldu
  assert.equal((await (await post(chat([{ role: "user", text: "üçüncü soru burada" }]))).json()).reply, ANSWERS.busy.tr);
  assert.deepEqual(seen, ["primary:openrouter", "primary:openrouter"]);
  const stats = await assistantStats(env.DB, env, NOW);
  assert.equal(stats.primaryUsd, 0.004);
  assert.equal(stats.primaryModel, "google/gemini-2.5-flash-lite");
  assert.equal(stats.fallbackModel, "");
});

test("ana model hata verince yedek model; hak doldu (429) ise ana model bir süre atlanır", async () => {
  const seen = [];
  const { post } = setup({}, async (_env, _s, _m, target) => {
    seen.push(target.role);
    if (target.role === "primary") throw new QuotaError("gemini 429", 120);
    return { reply: "yedek", report: null, cost: 100 };
  });
  assert.equal((await (await post(chat([{ role: "user", text: "birinci soru burada" }]))).json()).reply, "yedek");
  assert.equal((await (await post(chat([{ role: "user", text: "ikinci soru burada" }]))).json()).reply, "yedek");
  assert.deepEqual(seen, ["primary", "fallback", "fallback"]);
});

test("ikisi de hata verirse de robot takılmaz", async () => {
  const { post } = setup({}, async () => { throw new Error("x"); });
  const res = await post(chat([{ role: "user", text: "birinci soru burada" }]));
  assert.equal(res.status, 200);
  assert.equal((await res.json()).reply, ANSWERS.busy.tr);
  assert.ok(assistantEnabled({ ASSISTANT_FALLBACK: "openrouter", OPENROUTER_API_KEY: "o" }));
  assert.ok(!assistantEnabled({ ASSISTANT_FALLBACK: "openrouter" }));
});

test("OpenRouter isteği: bilgi tabanı başta, resim, JSON şeması, gerçek maliyet", async () => {
  let sent;
  const fetcher = async (url, init) => { sent = { url, body: JSON.parse(init.body), headers: init.headers };
    return new Response(JSON.stringify({ choices: [{ message: { content: "{\"reply\":\"Tamam\",\"report\":null}" } }], usage: { cost: 0.00042 } })); };
  const png = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==";
  const answer = await askModel({ OPENROUTER_API_KEY: "o" }, "sys", [{ role: "user", text: "bak", images: [{ mime: "image/png", data: png }] }], fetcher,
    { provider: "openrouter", model: "google/gemini-2.5-flash-lite" });
  assert.equal(answer.reply, "Tamam");
  assert.equal(answer.cost, 420);
  assert.equal(sent.url, "https://openrouter.ai/api/v1/chat/completions");
  assert.equal(sent.headers.authorization, "Bearer o");
  assert.equal(sent.body.model, "google/gemini-2.5-flash-lite");
  assert.match(sent.body.messages[0].content[0].text, /^NINO KNOWLEDGE:/);
  assert.deepEqual(sent.body.messages[0].content[0].cache_control, { type: "ephemeral" });
  assert.equal(sent.body.messages[0].content[1].text, "sys");
  assert.match(sent.body.messages[1].content[0].image_url.url, /^data:image\/png;base64,/);
  assert.equal(sent.body.response_format.type, "json_object");
  assert.deepEqual(sent.body.usage, { include: true });
  assert.equal(sent.body.models, undefined);
  // Seçili model meşgulse OpenRouter'ın aynı istekte geçeceği modeller.
  await askModel({ OPENROUTER_API_KEY: "o", ASSISTANT_MODEL_ALTERNATIVES: "deepseek/deepseek-v4.1-flash, google/gemini-3.1-flash-lite" }, "sys",
    [{ role: "user", text: "x", images: [] }], fetcher, { provider: "openrouter", model: "google/gemini-2.5-flash-lite" });
  assert.deepEqual(sent.body.models, ["google/gemini-2.5-flash-lite", "deepseek/deepseek-v4.1-flash", "google/gemini-3.1-flash-lite"]);
  // Bozuk cevapta da maliyet sayılır.
  const bad = async () => new Response(JSON.stringify({ choices: [{ message: { content: "olmadı" } }], usage: { cost: 0.001 } }));
  await assert.rejects(askModel({ OPENROUTER_API_KEY: "o" }, "s", [{ role: "user", text: "x", images: [] }], bad, { provider: "openrouter", model: "m" }),
    (error) => error.cost === 1000);
  // Hak doldu: bekleme süresiyle QuotaError.
  const full = async () => new Response("{}", { status: 429, headers: { "retry-after": "30" } });
  await assert.rejects(askModel({ GEMINI_API_KEY: "k", ASSISTANT_PROVIDER: "gemini" }, "s", [{ role: "user", text: "x", images: [] }], full),
    (error) => error instanceof QuotaError && error.retrySeconds === 30);
});
