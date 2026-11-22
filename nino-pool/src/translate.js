// SPDX-License-Identifier: AGPL-3.0-only
// Nino çeviri havuzu. Uygulama, hazır pakette olmayan bir satırı buraya sorar:
//   - çevirisi varsa (başka bir oyuncu daha önce görmüşse) hemen döner;
//   - yoksa (çöp değilse ve havuzda bozuk bir kopyası da yoksa) Claude Sonnet o an çevirir, kaydeder ve döner;
//     sonraki herkes aynısını anında alır. Claude yalnız TRANSLATE_LANGS dillerinde (varsayılan Türkçe) para harcar.
// 30 dakikada bir Claude Opus son çevirileri oyunun bağlamıyla toplu işlemle (yarı fiyat) yeniden okur, daha iyi
// olanları değiştirir. Uygulamalar oyun başlarken o oyunun bütün çevirilerini tek seferde, sonra yalnız değişenleri çeker.
// Küfür ve argo sansürsüz: oyun diyaloğu olduğu gibi çevrilir.
import { canonicalGame } from "./games.js";

import Anthropic from "@anthropic-ai/sdk";
import { lineKey, saltedDigest } from "./key.js";
import { junkReason } from "./filter.js";
import { navTranslation } from "./nav.js";
import { blocks, bestMatch } from "./fuzzy.js";
import { splitLine, joinParts } from "./compose.js";
import { askFree, freeEnabled } from "./free.js";

export const TRANSLATE_LIMITS = Object.freeze({
  maxBodyBytes: 64 * 1024,
  maxLines: 12,
  maxText: 300,
  maxContext: 4,
  /** Günlük harcama sınırı (dolar); env.TRANSLATE_DAILY_USD ile değişir. */
  dailyUsd: 6,
  /** Gözden geçirme, sınırın bu kadarı harcanmışsa durur (geri kalanı anında çeviriye kalır). */
  reviewShare: 0.4,
  /** Kurulum başına saatte en çok anında çevrilen satır (aynı sunucu örneği içinde, kaba koruma). */
  perInstallHour: 1500,
  /** Toplu indirmede sayfa başına en çok satır. */
  pageSize: 4000,
  /** Gözden geçirmede bir parçadaki satır ve bir turdaki parça. */
  reviewChunk: 20,
  reviewChunksPerRun: 30,
  /** Yeni çeviri gözden geçirilmeden önce bu kadar bekler (aynı sahnenin satırları birikir). */
  reviewDelay: 10 * 60,
});

// Nino: ilk çeviri de mükemmel olsun diye anında çeviri de güçlü modelle (her satır bir kez çevrilir, herkes havuzdan alır).
export const LIVE_MODEL = "claude-sonnet-5-5";
// Gözden geçirme en güçlü modelle (Codex ile birlikte kararlaştırılan Plan 1); sahne sahne, bağlamla.
export const REVIEW_MODEL = "claude-opus-5-5";
/** Plan 3: Plan 1 zamanında cevap vermez, reddeder ya da hata verirse yalnız o satır için hızlı model. */
export const FALLBACK_MODEL = "claude-haiku-5-5";
/** Plan 1 için en çok bekleme (ms); sonra Plan 3 denenir. */
export const LIVE_TIMEOUT_MS = 4000;
export const FALLBACK_TIMEOUT_MS = 2500;

/** Dolar / milyon jeton (resmî fiyat, 100K jetona kadar). */
const PRICES = {
  "claude-haiku-5-5": { input: 0.10, output: 0.50 },
  "claude-sonnet-5-5": { input: 2.00, output: 10.00, cacheRead: 0.10, cacheWrite1h: 4.00 },
  "claude-opus-5-5": { input: 4.00, output: 20.00, cacheRead: 0.20, cacheWrite1h: 8.00 },
};
const FALLBACK_MICRO_USD = 20000;

export const LANGUAGES = Object.freeze({
  tr: "Turkish", ar: "Arabic", hi: "Hindi", id: "Indonesian", th: "Thai", vi: "Vietnamese",
  ur: "Urdu", bn: "Bengali", ms: "Malay", tl: "Filipino (Tagalog)", nl: "Dutch",
});

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const GAME = /^[a-z0-9][a-z0-9._-]{0,63}$/;
const LETTER = /\p{L}/u;
const CONTROL = /[\u0000-\u001f\u007f-\u009f\u200b-\u200f\u2028\u2029\ufeff]/gu;

/** Model fiyatıyla mikro dolar. */
export function translateCost(model, usage) {
  const price = PRICES[model];
  if (!price || !usage) return FALLBACK_MICRO_USD;
  return Math.ceil((usage.input_tokens ?? 0) * price.input + (usage.output_tokens ?? 0) * price.output
    + (usage.cache_read_input_tokens ?? 0) * (price.cacheRead ?? price.input * 0.1)
    + (usage.cache_creation_input_tokens ?? 0) * (price.cacheWrite1h ?? price.input * 2));
}

const LANGUAGE_NOTES = {
  tr: [
    "Use informal \"sen\" between characters unless the speaker is clearly formal (police to suspect, servant to boss). Natural spoken Istanbul Turkish; Turkish street slang where the original is slangy (\"bro/homie\" → \"kanka/birader\", \"dude\" → \"lan/abi\").",
    "Turkish swearing that matches the English intensity, used the way Turkish speakers really swear:",
    "  \"Fuck!\" / \"Oh fuck!\" → \"Siktir!\" / \"Hassiktir!\"; \"What the fuck?\" → \"Ne halt?\" / \"Bu ne amına koyayım?\"; \"Who the fuck are you?\" → \"Sen de kimsin lan?\";",
    "  \"Shut the fuck up\" → \"Kapa çeneni lan\" / \"Sus amına koyayım\"; \"fucking\" as intensifier → \"lanet olası\", \"siktiğimin\", \"amına koyduğumun\" or a strong \"lan\", never dropped;",
    "  \"motherfucker\" → \"orospu çocuğu\"; \"son of a bitch\" → \"şerefsiz\" / \"orospu çocuğu\"; \"shit\" → \"bok\" (\"No more stupid shit\" → \"Artık saçma sapan bok yemek yok\"), \"shitshow\" → \"bok gibi rezalet\"; \"ass\" → \"göt\"; \"fuck up\" → \"sıçıp batırmak\".",
    "The idiom \"fuck around\" means joking or wasting time, not sex: \"I'm fuckin' around\" / \"I'm just fucking with you\" → \"Dalga geçiyorum lan\" / \"Taşak geçiyorum\"; \"I'm not fucking around\" → \"Şaka yapmıyorum lan\"; \"Don't fuck around\" → \"Oyalanma lan\". Keep it just as rough as the English.",
    "A Turkish sentence nobody would say (\"Sadece sikik atıyorum\", \"Sikmiyorum lan, defolun\") is a wrong translation; say what the line means the way a foul-mouthed Turkish speaker would.",
    "Never add swearing or insults that are not in the English line, and never change the meaning to make it ruder: translate idioms by meaning (\"Says who?\" → \"Kim demiş?\", \"Says fuckin' who?\" → \"Kim demiş lan?\", \"pick you up\" said of cops → \"seni içeri alırlar\").",
  ].join("\n"),
  ar: "Use natural spoken Modern Standard Arabic suitable for game subtitles.",
  nl: "Use informal \"je/jij\" unless clearly formal.",
};

/**
 * Kısa çeviri talimatı (~250 jeton): jeton sınırlı ücretsiz servisler (Groq, OpenRouter, NVIDIA) için. Uzun talimatın
 * özü: anlam ve ton, küfür aynı şiddette, adlar aynen, OCR bozukluğunu düzelt, yalnız çeviri.
 */
export function compactInstructions(lang) {
  const name = LANGUAGES[lang];
  return [
    `Translate English subtitles of an 18+ video game into natural spoken ${name}, short like official game subtitles.`,
    "Translate meaning and tone, not word by word. Swearing and slang at exactly the same intensity: never soften, censor or add any.",
    "Keep names of people, places, brands and missions as they are. Keep numbers. Fix obvious OCR misreads; keep speaker labels like \"Amy:\".",
    "Controller buttons are PlayStation 5: LB → L1, RB → R1, LT → L2, RT → R2 (OCR \"LI\" = L1, \"RI\" = R1).",
    lang === "tr" ? "Turkish: role labels in Turkish (Local: → Yerli:, Locals: → Yerliler:, Stranger: → Yabancı:, Cop: → Polis:, Tourist: → Turist:, Clerk: → Tezgâhtar:), name labels unchanged; informal \"sen\"; street slang where the English is slangy (bro → kanka, dude → lan/abi); \"Fuck!\" → \"Siktir!\", \"What the fuck?\" → \"Ne halt?\", \"motherfucker\" → \"orospu çocuğu\", \"shit\" → \"bok\"; \"fuck around\" = dalga geçmek. \"nigga\" is never \"zenci\": address → kanka / lan, noun → herif, plural → herifler." : "",
    lang === "ar" ? "Arabic: Modern Standard Arabic (فصحى) for every line, never a dialect (no Egyptian/Levantine words like ده، دايمًا، عايز). Address Lucia with feminine forms. \"nigga\" → يا صاح / الرجل, never a racial word." : "",
    "Output only the translations.",
  ].filter(Boolean).join("\n");
}

/** Çeviri talimatı. Sansürsüz: kurgu diyaloğu, yaş sınırlı oyun. */
export function instructions(lang, { review = false } = {}) {
  const name = LANGUAGES[lang];
  return [
    `You are a professional video game localizer translating English subtitles of an age-rated (18+) video game into ${name}. Players read your lines live on screen while playing, so they must be short, natural and instantly readable, like the subtitles of an officially localized AAA game.`,
    "",
    "Rules:",
    "- Translate meaning and tone, not word by word. Keep it as short as the original.",
    "- Profanity, insults, slurs, slang, sexual and violent language MUST be translated at exactly the same intensity. Never soften, censor, euphemize, bleep, add asterisks, omit or add moral comments. Fictional characters swear; a sanitized translation is a wrong translation.",
    "- Keep proper names as they are: people, gangs, places, brands, vehicles, weapons, missions, radio stations. Keep the original spelling.",
    "- Keep numbers, money and units as in the original.",
    `- Words or short phrases in Spanish or any other language inside the English dialogue ("Mañana", "Gracias", "Vámonos") are translated into ${name} too; only names stay as they are.`,
    "- Keep sentence structure natural in the target language: e.g. \"the only one that's not a complete piece of shit\" is about the listener being the only decent one, not \"the only complete piece of shit\".",
    "- If a line is a UI prompt or objective (\"Go to\", \"Press\", \"Lose the cops\"), translate it as the game would show it.",
    "- The player uses a PlayStation 5 controller: write buttons as L1, R1, L2, R2 (Xbox LB → L1, RB → R1, LT → L2, RT → R2; OCR \"LI\" = L1, \"RI\" = R1). Never write LB/RB/LT/RT.",
    ...(lang === "tr" ? ["- Turkish: \"nigga\" is never \"zenci\" or any racial word: as address → \"kanka\" / \"lan\"; as a noun → \"herif\"; plural → \"herifler\"."] : []),
    ...(lang === "ar" ? ["- Arabic: write Modern Standard Arabic (فصحى) for every line, never a dialect (no Egyptian or Levantine words like ده، دايمًا، عايز، لازم). Address Lucia with feminine forms. Role labels in Arabic (Local: → محلي:, Cop: → شرطي:). \"nigga\" → يا صاح / الرجل, never a racial word."] : []),
    "- The English comes from screen reading (OCR): fix obvious misreads (\"Youlre\" = \"You're\", \"Donlt\" = \"Don't\", \"Ihäd\" = \"I had\") and drop stray HUD fragments or single stray letters around the dialogue. A speaker label like \"Amy:\" stays as \"Amy:\". Role labels (\"Local:\", \"Stranger:\", \"Cop:\", \"Tourist:\", \"Clerk:\") are translated as a short role word followed by a colon. If the whole line is unreadable garbage, return it unchanged.",
    "- A controller button icon in a prompt is often misread as a stray character (\"Press 7 to open the map\", \"Press [1] to open the map\", \"Press do to open the index\"): treat it as a button and leave it out (\"Haritayı açmak için tuşa bas\").",
    "- Output only translations. No quotes, notes, explanations or alternatives.",
    LANGUAGE_NOTES[lang] ? `- ${LANGUAGE_NOTES[lang]}` : "",
    review
      ? "- You are reviewing earlier fast translations. The lines are in the order they were first seen in the game, so neighbours give context (who speaks, who is addressed, running jokes, names). Fix mistranslations, wrong address (sen/siz), wrong gender, lost slang or softened swearing, unnatural wording. Check each line separately for: (1) meaning, (2) swearing intensity: is it softer or harsher than the English, (3) added swearing or insults not in the English, (4) names kept as in the original. If a translation is already good, return it unchanged."
      : "- Context lines (if given) are what was said just before; use them to pick the right meaning and address, but translate only the numbered lines.",
  ].filter(Boolean).join("\n");
}

const LIVE_SCHEMA = {
  type: "object",
  properties: { translations: { type: "array", items: { type: "string" } } },
  required: ["translations"],
  additionalProperties: false,
};

/** Tek modelle anında çeviri. Dönüş { texts: string[]|null, cost }. */
export async function askLiveModel(env, model, lang, lines, context, timeoutMs, effort = model === LIVE_MODEL ? liveEffort(env) : "low") {
  const client = new Anthropic({ apiKey: env.ANTHROPIC_API_KEY, timeout: timeoutMs, maxRetries: 0 });
  const body = [
    context.length ? `Context (do not translate):\n${context.map((c) => `- ${c}`).join("\n")}\n` : "",
    `Translate these ${lines.length} lines into ${LANGUAGES[lang]}. Return exactly ${lines.length} translations in the same order.`,
    ...lines.map((line, i) => `${i + 1}. ${line}`),
  ].filter(Boolean).join("\n");
  const sonnet = model === LIVE_MODEL;
  const response = await client.messages.create({
    model,
    max_tokens: 1500,
    // Düşünme kapalı (hız): Sonnet 5.5'te "between_tools", Haiku 5.5'te "disabled".
    thinking: { type: sonnet ? "between_tools" : "disabled" },
    // Talimat her dilde aynı kalır: bir saat önbellekte durur, her satırda yeniden ücretlendirilmez.
    system: [{ type: "text", text: instructions(lang), cache_control: { type: "ephemeral", ttl: "1h" } }],
    messages: [{ role: "user", content: body }],
    output_config: { effort, format: { type: "json_schema", schema: LIVE_SCHEMA } },
  });
  const cost = translateCost(model, response.usage);
  if (response.stop_reason !== "end_turn") return { texts: null, cost, usage: response.usage };
  const text = response.content.filter((b) => b.type === "text").map((b) => b.text).join("");
  const parsed = JSON.parse(text);
  const texts = Array.isArray(parsed.translations) && parsed.translations.length === lines.length ? parsed.translations : null;
  return { texts, cost, usage: response.usage };
}

/** Anında çevirinin özeni (Sonnet): env.LIVE_EFFORT, varsayılan "medium". */
export function liveEffort(env) {
  return ["low", "medium", "high"].includes(env?.LIVE_EFFORT) ? env.LIVE_EFFORT : "medium";
}

/**
 * Anında çeviri, plan sırasıyla: Plan 1 Sonnet 5.5 (en çok 4 sn); zamanında cevap vermez, reddeder ya da hata
 * verirse Plan 3 Haiku 5.5 (en çok 2,5 sn). Her satır yeniden Plan 1'den başlar. Dönüş { texts, cost, model }.
 */
export async function askLive(env, lang, lines, context) {
  let cost = 0;
  for (const [model, timeout] of [[LIVE_MODEL, LIVE_TIMEOUT_MS], [FALLBACK_MODEL, FALLBACK_TIMEOUT_MS]]) {
    try {
      const answer = await askLiveModel(env, model, lang, lines, context, timeout);
      cost += answer.cost;
      if (answer.texts && answer.texts.every((t, i) => usable(lines[i], t))) return { texts: answer.texts, cost, model };
    } catch (error) {
      console.error("çeviri hatası", model, String(error?.message ?? error).slice(0, 200));
    }
  }
  return { texts: null, cost };
}

const REVIEW_SCHEMA = {
  type: "object",
  properties: {
    lines: {
      type: "array",
      items: {
        type: "object",
        properties: { n: { type: "integer" }, text: { type: "string" } },
        required: ["n", "text"],
        additionalProperties: false,
      },
    },
  },
  required: ["lines"],
  additionalProperties: false,
};

/** Gözden geçirmenin özeni (Opus): env.REVIEW_EFFORT, varsayılan "medium" (kıyasta "high" kadar iyi, daha ucuz). */
export function reviewEffort(env) {
  return ["low", "medium", "high"].includes(env?.REVIEW_EFFORT) ? env.REVIEW_EFFORT : "medium";
}

/** Gözden geçirme isteği (anında ve toplu işlemde aynı). */
export function reviewParams(lang, game, items, { model = REVIEW_MODEL, effort = "medium" } = {}) {
  const body = [
    `Game: ${game || "unknown"}. Review these ${items.length} subtitle translations into ${LANGUAGES[lang]}.`,
    `Return all ${items.length} lines with their number n and the final translation.`,
    "",
    ...items.map((item, i) => `${i + 1}. EN: ${item.source}\n   ${lang.toUpperCase()}: ${item.text}`),
  ].join("\n");
  return {
    model,
    max_tokens: 16000,
    system: instructions(lang, { review: true }),
    messages: [{ role: "user", content: body }],
    thinking: { type: "adaptive" },
    output_config: { effort, format: { type: "json_schema", schema: REVIEW_SCHEMA } },
  };
}

/** Modelin gözden geçirme cevabından satırlar (bozuksa null). */
export function parseReview(items, message) {
  if (!message || message.stop_reason !== "end_turn") return null;
  const text = message.content.filter((b) => b.type === "text").map((b) => b.text).join("");
  const parsed = JSON.parse(text);
  const out = items.map((item) => item.text);
  for (const line of parsed.lines ?? []) {
    const i = Number(line.n) - 1;
    if (i >= 0 && i < out.length && typeof line.text === "string") out[i] = line.text;
  }
  return out;
}

/** Gözden geçirme (anında): [{source, text}] sırayla; dönüş { texts: string[]|null, cost }. */
export async function askReview(env, lang, game, items, { model = REVIEW_MODEL, effort = reviewEffort(env) } = {}) {
  const client = new Anthropic({ apiKey: env.ANTHROPIC_API_KEY, timeout: 90_000, maxRetries: 1 });
  const response = await client.messages.create(reviewParams(lang, game, items, { model, effort }));
  const cost = translateCost(model, response.usage);
  return { texts: parseReview(items, response), cost, usage: response.usage };
}

/** Toplu işlem (Batch API, yarı fiyat): oluştur, durumunu sor, sonuçlarını oku. Testlerde taklidi verilir. */
export function anthropicBatches(env) {
  const client = () => new Anthropic({ apiKey: env.ANTHROPIC_API_KEY, timeout: 60_000, maxRetries: 1 });
  return {
    async create(requests) { return client().messages.batches.create({ requests }); },
    async retrieve(id) { return client().messages.batches.retrieve(id); },
    async results(id) {
      const out = [];
      for await (const result of await client().messages.batches.results(id)) out.push(result);
      return out;
    },
  };
}

function day(now) {
  return new Date(now * 1000).toISOString().slice(0, 10);
}

function capMicro(env) {
  const usd = Number(env.TRANSLATE_DAILY_USD ?? TRANSLATE_LIMITS.dailyUsd);
  return Math.round((Number.isFinite(usd) && usd >= 0 ? usd : TRANSLATE_LIMITS.dailyUsd) * 1_000_000);
}

async function spentToday(db, now) {
  return (await db.prepare("SELECT micro_usd FROM translate_cost WHERE day = ?").bind(day(now)).first("micro_usd")) ?? 0;
}

/** Günlük masrafa ekler; `review` ise gözden geçirme payına da yazılır (toplam micro_usd'nin içindedir). */
export async function addCost(db, now, micro, review = false) {
  const value = Math.max(0, Math.round(micro));
  await db.prepare(
    `INSERT INTO translate_cost (day, micro_usd, review_micro_usd) VALUES (?1, ?2, ?3)
     ON CONFLICT(day) DO UPDATE SET micro_usd = micro_usd + excluded.micro_usd, review_micro_usd = review_micro_usd + excluded.review_micro_usd`,
  ).bind(day(now), value, review ? value : 0).run();
}

/**
 * Claude yalnız bu oyunlarda para harcar (anında çeviri ve gözden geçirme); env.TRANSLATE_GAMES virgülle ayrılmış
 * parçalar ("grand-theft-auto-vi,gta-vi,mafia"): oyun kimliği bunlardan birini içeriyorsa açık. "*" hepsi.
 * Öbür oyunlar hazır paket ve cihazın ücretsiz çevirisiyle devam eder; havuzdaki çeviriler yine okunur.
 */
export function gameAllowed(env, game) {
  // Listedeki takma adlar da asıl kimliğe çevrilir ("grand-theft-auto-vi" yazılı olsa da "gta-6" izinli olur).
  const list = String(env.TRANSLATE_GAMES ?? "*").split(",").map((g) => g.trim().toLowerCase()).filter(Boolean)
    .map((g) => (g === "*" ? g : canonicalGame(g)));
  if (list.includes("*")) return true;
  const id = canonicalGame(String(game ?? "").toLowerCase());
  return id !== "" && list.some((part) => id.includes(part));
}

/**
 * Claude yalnız bu dillerde para harcar: env.TRANSLATE_LANGS (virgüllü), varsayılan "tr". Öbür dillerde havuzdaki
 * çeviriler yine verilir; yeni satırları uygulama kullanıcının kendi motoruyla ya da ücretsiz çeviriyle çevirir.
 */
export function translateLangs(env) {
  return String(env?.TRANSLATE_LANGS ?? "tr").split(",").map((l) => l.trim().toLowerCase()).filter((l) => LANGUAGES[l] || l === "*");
}

export function langAllowed(env, lang) {
  const list = translateLangs(env);
  return list.includes("*") || list.includes(lang);
}

/** Çevirinin benzer satır parçalarını yazar (src/fuzzy.js). */
export async function indexBlocks(db, lang, rows) {
  const entries = rows.flatMap((r) => blocks(r.s).map((b) => ({ b, k: r.k })));
  if (entries.length === 0) return;
  await db.prepare(
    `INSERT OR IGNORE INTO translation_blocks (lang, block, key)
     SELECT ?, json_extract(value, '$.b'), json_extract(value, '$.k') FROM json_each(?)`,
  ).bind(lang, JSON.stringify(entries)).run().catch((error) => console.error("benzer satır dizini", error));
}

/**
 * Claude'a gitmeyen satırların (çöp, izinsiz dil) İngilizcesi yine havuza yazılır (kurulum kimliği tutulmaz);
 * dışa aktarmada ve elle çeviride kullanılır.
 */
async function rememberEnglish(db, game, items, now) {
  const rows = items.filter((i) => i.key).map((i) => ({ k: i.key, t: i.text }));
  if (rows.length === 0) return;
  await db.prepare(
    `INSERT INTO lines (game, key, text, seen, installs, first_seen, last_seen)
     SELECT ?1, json_extract(value, '$.k'), json_extract(value, '$.t'), 1, 0, ?2, ?2 FROM json_each(?3) WHERE true
     ON CONFLICT (game, key) DO UPDATE SET seen = seen + 1, last_seen = max(last_seen, excluded.last_seen)`,
  ).bind(game, now, JSON.stringify(rows)).run().catch((error) => console.error("İngilizce havuza yazılamadı", error));
}

/**
 * Oyun kimliği gelmeyen (PS5 çoğu zaman bildirmez, hazır paketi olmayan oyunda paketten de tanınamaz) satırlardan oyunu
 * tanır: oyuna özgü isimler (karakter, şehir) satırda ya da bağlamında geçiyorsa. Tanınan oyun kuruluma birkaç saat
 * yazılır; o kurulumun sonraki satırları da o oyundan sayılır.
 */
const GAME_SIGNATURES = [
  ["gta-6", /\b(grand theft auto vi|gta ?(vi|6)|leonida|vice city|port gellhorn|ambrosia|grassrivers|kalaga|lucia|jason duval|dre'?quan|real dimez|boobie ike)\b/i],
];
export const GAME_MEMORY_SECONDS = 4 * 3600;

export function detectGame(texts) {
  const joined = texts.filter(Boolean).join(" \n ");
  for (const [game, pattern] of GAME_SIGNATURES) if (pattern.test(joined)) return game;
  return "";
}

/** Claude (anında çeviri, gözden geçirme, ekrandan oyun tanıma) açık mı: anahtar var ve CLAUDE_ENABLED "0" değil. */
export function claudeEnabled(env) {
  return env.CLAUDE_ENABLED !== "0" && Boolean(env.ANTHROPIC_API_KEY);
}

/** Yeni satır çevrilebilir mi: ücretsiz zincir (TRANSLATE_ENGINE="free") ya da Claude. */
export function translateEnabled(env) {
  return env.TRANSLATE_ENABLED !== "0" && (freeEnabled(env) || claudeEnabled(env));
}

function clean(text) {
  return typeof text === "string" ? text.replace(CONTROL, " ").replace(/\s+/gu, " ").trim() : "";
}

/** Modelin cevabı kullanılabilir mi: boş değil, makul uzunlukta, ret/özür değil. */
export function usable(source, translation) {
  const t = clean(translation);
  if (!t) return false;
  if ([...t].length > Math.max(40, [...source].length * 4)) return false;
  if (/\b(I can(?:not|'t)|I'm sorry|as an AI|I won't)\b/i.test(t) && !/\b(I can(?:not|'t)|sorry|won't)\b/i.test(source)) return false;
  return true;
}

/**
 * Hazır çeviri tohumunda (seeds tablosu) bulunan satırlar Claude'a sorulmadan oradan cevaplanır ve İngilizcesiyle birlikte
 * havuza yazılır (tier 1: sonradan gözden geçirilebilir). Dönüş: hâlâ çevirisi olmayanlar.
 */
async function fromSeeds(db, lang, game, missing, now) {
  const { results } = await db.prepare(`SELECT key, text FROM seeds WHERE lang = ? AND key IN (SELECT value FROM json_each(?))`)
    .bind(lang, JSON.stringify(missing.map((m) => m.key))).all().catch(() => ({ results: [] }));
  if (results.length === 0) return missing;
  const seeds = new Map(results.map((r) => [r.key, r.text]));
  const rest = [];
  const rows = [];
  for (const m of missing) {
    const text = seeds.get(m.key);
    if (!text || !usable(m.text, text)) { rest.push(m); continue; }
    m.result = clean(text);
    m.tier = 1;
    m.seeded = true;
    rows.push({ k: m.key, s: m.text, t: m.result, r: 1 });
  }
  if (rows.length > 0) {
    // copy_of 'seed': hazır çeviri Opus'a gönderilmez (para harcamasın).
    await db.prepare(
      `INSERT OR IGNORE INTO translations (key, lang, game, source, text, tier, created, updated, copy_of)
       SELECT json_extract(value, '$.k'), ?, ?, json_extract(value, '$.s'), json_extract(value, '$.t'), json_extract(value, '$.r'), ?, ?, 'seed'
       FROM json_each(?)`,
    ).bind(lang, game, now, now, JSON.stringify(rows)).run().catch((error) => console.error("tohum satırı yazılamadı", error));
    await indexBlocks(db, lang, rows).catch(() => {});
  }
  return rest;
}

/**
 * Birleşik satır ("Cümle A. Cümle B." ya da "Lucia: Cümle") cümlelerinin hepsi havuzda ya da tohumda varsa çevirisi
 * cümlelerden kurulur (Claude'a sorulmaz). Havuza yazılmaz: cümleler gözden geçirildikçe sonraki istekte o da düzelir.
 * Dönüş: hâlâ çevirisi olmayanlar.
 */
async function fromPieces(db, lang, missing) {
  const split = [];
  for (const m of missing) {
    const parts = splitLine(m.text);
    if (!parts) continue;
    for (const part of parts) if (part.text) part.key = await lineKey(part.text);
    split.push({ m, parts });
  }
  if (split.length === 0) return missing;
  const keys = [...new Set(split.flatMap((s) => s.parts.map((p) => p.key).filter(Boolean)))];
  const found = new Map();
  const { results: own } = await db.prepare(
    `SELECT key, text, tier FROM translations WHERE lang = ? AND text <> '' AND key IN (SELECT value FROM json_each(?))`,
  ).bind(lang, JSON.stringify(keys)).all().catch(() => ({ results: [] }));
  for (const r of own) found.set(r.key, { text: r.text, tier: r.tier });
  const { results: seeded } = await db.prepare(`SELECT key, text FROM seeds WHERE lang = ? AND key IN (SELECT value FROM json_each(?))`)
    .bind(lang, JSON.stringify(keys.filter((k) => !found.has(k)))).all().catch(() => ({ results: [] }));
  for (const r of seeded) found.set(r.key, { text: r.text, tier: 1 });
  const done = new Set();
  for (const { m, parts } of split) {
    const byText = new Map(parts.filter((p) => p.text).map((p) => [p.text, found.get(p.key)]));
    const text = joinParts(parts, (t) => byText.get(t)?.text);
    if (!text || !usable(m.text, text)) continue;
    m.result = clean(text);
    m.tier = Math.min(...[...byText.values()].map((v) => v.tier));
    m.composed = true;
    done.add(m);
  }
  return missing.filter((m) => !done.has(m));
}

/**
 * Havuzda aynı cümlenin bozuk bir kopyası çevrilmişse onun çevirisi verilir (Claude'a sorulmaz) ve bu yazılış da havuza
 * eklenir. Dönüş: hâlâ çevirisi olmayanlar.
 */
async function fromSimilar(db, lang, game, missing, now) {
  const wanted = [...new Set(missing.flatMap((m) => blocks(m.text)))];
  if (wanted.length === 0) return missing;
  const { results } = await db.prepare(
    `SELECT t.key, t.source, t.text, t.tier, t.copy_of FROM translation_blocks b JOIN translations t ON t.lang = b.lang AND t.key = b.key
     WHERE b.lang = ? AND b.block IN (SELECT value FROM json_each(?)) AND t.text <> '' LIMIT 400`,
  ).bind(lang, JSON.stringify(wanted)).all().catch(() => ({ results: [] }));
  if (results.length === 0) return missing;
  const rest = [];
  const rows = [];
  for (const m of missing) {
    const match = bestMatch(m.text, results);
    if (!match) { rest.push(m); continue; }
    m.result = match.text;
    m.tier = match.tier;
    m.similar = true;
    rows.push({ k: m.key, s: m.text, t: match.text, r: match.tier, c: match.copy_of || match.key });
  }
  if (rows.length > 0) {
    // copy_of: aslının anahtarı. Kopya ayrıca gözden geçirilmez; aslı gözden geçirilince onun metnini alır.
    await db.prepare(
      `INSERT OR IGNORE INTO translations (key, lang, game, source, text, tier, created, updated, copy_of)
       SELECT json_extract(value, '$.k'), ?, ?, json_extract(value, '$.s'), json_extract(value, '$.t'), json_extract(value, '$.r'), ?, ?,
              json_extract(value, '$.c')
       FROM json_each(?)`,
    ).bind(lang, game, now, now, JSON.stringify(rows)).run().catch((error) => console.error("benzer satır yazılamadı", error));
  }
  return rest;
}

// Sunucu örneği içi kaba sınır: kurulum → [saat, satır].
const installHits = new Map();

/**
 * POST /v1/translate
 * { v:1, install, app, platform, lang, game?, lines:[text…], context?:[text…] }
 * → { ok, translations:[{ text: string|null, tier }] } (sıra aynı; çevrilemeyen null, uygulama kendi çevirisini kullanır)
 */
export async function handleTranslate(db, env, body, now, live = askLive) {
  // Ücretsiz zincir açıksa Claude yerine o kullanılır (testler kendi taklidini verir).
  const free = live === askLive && freeEnabled(env);
  if (free) live = (e, lang, lines, context) => askFree(e, lang, lines, context, { db, now });
  if (!body || typeof body !== "object" || body.v !== 1) return { status: 400, body: { ok: false, error: "bad_request" } };
  if (typeof body.install !== "string" || !UUID.test(body.install)) return { status: 400, body: { ok: false, error: "bad_install" } };
  const lang = typeof body.lang === "string" ? body.lang.toLowerCase().split(/[-_]/)[0] : "";
  if (!LANGUAGES[lang]) return { status: 400, body: { ok: false, error: "bad_lang" } };
  if (!Array.isArray(body.lines) || body.lines.length === 0) return { status: 400, body: { ok: false, error: "no_lines" } };
  if (body.lines.length > TRANSLATE_LIMITS.maxLines) return { status: 413, body: { ok: false, error: "too_many_lines" } };
  // "Mafia: The Old Country" uygulamada "mafia--the-old-country" olur; aynı oyun tek adla tutulsun.
  let game = typeof body.game === "string" && GAME.test(body.game) ? canonicalGame(body.game) : "";
  const context = (Array.isArray(body.context) ? body.context : []).slice(-TRANSLATE_LIMITS.maxContext)
    .map(clean).filter((c) => c && [...c].length <= TRANSLATE_LIMITS.maxText);
  // Uygulama başka bir oyun sanıyorsa (benzer satırlı başka oyunun paketi) ama satırda havuz öncelikli oyunun (GTA 6)
  // kendine özgü bir adı geçiyorsa ("Lucia", "Vice City") o oyun geçerlidir.
  const firstGame = (id) => poolFirstGames(env).some((part) => String(id ?? "").toLowerCase().includes(canonicalGame(part))
    || String(id ?? "").toLowerCase().includes(part));
  if (game && !firstGame(game)) {
    const named = detectGame([...body.lines.map(clean), ...context]);
    if (named && firstGame(named)) game = "";
  }
  // Oyun bilinmiyorsa: satırdan/bağlamdan tanınır ya da bu kurulumun son saatlerde tanınan oyunu kullanılır.
  let detected = "";
  if (!game) {
    const installKey = await saltedDigest(body.install.toLowerCase(), env.INSTALL_SALT ?? "");
    detected = detectGame([...body.lines.map(clean), ...context]);
    if (detected) {
      game = detected;
      await db.prepare(
        `INSERT INTO installs (install, platform, app, first_seen, last_seen, playing, game, lang) VALUES (?1, '', '', ?2, ?2, ?2, ?3, '')
         ON CONFLICT (install) DO UPDATE SET last_seen = ?2, playing = ?2, game = ?3`,
      ).bind(installKey, now, detected).run().catch(() => {});
    } else {
      const remembered = await db.prepare("SELECT game, playing FROM installs WHERE install = ?").bind(installKey).first().catch(() => null);
      if (remembered?.game && now - (remembered.playing ?? 0) < GAME_MEMORY_SECONDS && gameAllowed(env, remembered.game)) {
        game = remembered.game;
      }
    }
  }

  // Satırlar ve anahtarları.
  const items = [];
  for (const raw of body.lines) {
    const text = clean(raw);
    const ok = text && [...text].length <= TRANSLATE_LIMITS.maxText && LETTER.test(text);
    items.push({ text, key: ok ? await lineKey(text) : null, result: null, tier: 0 });
  }
  const keys = [...new Set(items.map((i) => i.key).filter(Boolean))];
  if (keys.length > 0) {
    const { results } = await db.prepare(`SELECT key, text, tier, game FROM translations WHERE lang = ? AND key IN (SELECT value FROM json_each(?))`)
      .bind(lang, JSON.stringify(keys)).all();
    const known = new Map(results.map((r) => [r.key, r]));
    // Nino: oyun hâlâ bilinmiyorsa havuzdaki satırdan tanınır (satır daha önce bir oyunda görülüp çevrilmişse; kısa ve
    // her oyunda geçebilecek satırlar sayılmaz). Kuruluma yazılır, sonraki satırlar da o oyundan sayılır.
    // Uygulama başka bir oyun sanıyorsa (ör. benzer satırlı paketten) ama satır havuz öncelikli bir oyunun (GTA 6) uzun bir
    // satırıysa o oyun döner: uygulama cevaptaki oyuna bakıp çeviriyi yalnız havuzdan almaya geçer.
    if (!game || !firstGame(game)) {
      const telling = results.find((r) => r.game && r.text && gameAllowed(env, r.game) && [...String(r.text)].length >= 25
        && (!game || firstGame(r.game)));
      if (telling) {
        game = telling.game;
        const installKey = await saltedDigest(body.install.toLowerCase(), env.INSTALL_SALT ?? "");
        await db.prepare(
          `INSERT INTO installs (install, platform, app, first_seen, last_seen, playing, game, lang) VALUES (?1, '', '', ?2, ?2, ?2, ?3, '')
           ON CONFLICT (install) DO UPDATE SET last_seen = ?2, playing = ?2, game = ?3`,
        ).bind(installKey, now, game).run().catch(() => {});
      }
    }
    for (const item of items) {
      const hit = item.key && known.get(item.key);
      // Boş metin: daha önce çevrilemedi (ret ya da bozuk cevap); yeniden ücretlendirilmez, uygulama kendi çevirisini kullanır.
      if (hit) { item.result = hit.text || null; item.tier = hit.text ? hit.tier : 0; item.known = true; }
    }
  }

  // Bilinmeyenler: önce çöp süzgeci (tabela, menü, kırıntı, zaten Türkçe), sonra havuzdaki benzer satır, sonra Claude.
  let missing = [];
  const skipped = [];
  const seen = new Set();
  for (const item of items) {
    if (!item.key || item.result !== null || item.known || seen.has(item.key)) continue;
    seen.add(item.key);
    // Yol tarifi ("Turn Right 405 ft"): kuralla çevrilir, havuza yazılmaz (her mesafe ayrı satır olurdu).
    const nav = navTranslation(item.text, lang);
    if (nav) { item.result = nav; item.tier = 1; continue; }
    if (junkReason(item.text)) skipped.push(item);
    else missing.push(item);
  }
  // Hazır çeviri tohumu: para harcamaz, dil kısıtına ve günlük sınıra takılmaz.
  if (missing.length > 0) missing = await fromSeeds(db, lang, game, missing, now);
  if (missing.length > 0) missing = await fromPieces(db, lang, missing);
  if (missing.length > 0 && !langAllowed(env, lang)) { skipped.push(...missing); missing = []; }
  if (missing.length > 0) missing = await fromSimilar(db, lang, game, missing, now);
  if (skipped.length > 0) await rememberEnglish(db, game, skipped, now);
  let limited = null;
  if (missing.length === 0 && skipped.length > 0 && !langAllowed(env, lang)) limited = "lang";
  if (missing.length > 0) {
    if (!translateEnabled(env)) limited = "disabled";
    else if (!gameAllowed(env, game)) limited = "game";
    else if (!free && (await spentToday(db, now)) >= capMicro(env)) limited = "daily_cap";
    else {
      const install = await saltedDigest(body.install.toLowerCase(), env.INSTALL_SALT ?? "");
      const hour = Math.floor(now / 3600);
      const prev = installHits.get(install);
      const used = prev && prev[0] === hour ? prev[1] : 0;
      if (used + missing.length > TRANSLATE_LIMITS.perInstallHour) limited = "install_rate";
      else {
        installHits.set(install, [hour, used + missing.length]);
        if (installHits.size > 5000) installHits.clear();
      }
    }
    if (!limited) {
      let answer = { texts: null, cost: 0 };
      try {
        answer = await live(env, lang, missing.map((m) => m.text), context);
      } catch (error) {
        console.error("çeviri hatası", error);
      }
      if (answer.cost) await addCost(db, now, answer.cost);
      const texts = answer.texts && answer.texts.length === missing.length ? answer.texts : null;
      if (texts) {
        const rows = [];
        missing.forEach((m, i) => {
          if (usable(m.text, texts[i])) {
            m.result = clean(texts[i]);
            m.tier = 1;
            rows.push({ k: m.key, s: m.text, t: m.result, r: 1 });
          } else {
            rows.push({ k: m.key, s: m.text, t: "", r: 0 });
          }
        });
        if (rows.length > 0) {
          await db.prepare(
            `INSERT OR IGNORE INTO translations (key, lang, game, source, text, tier, created, updated)
             SELECT json_extract(value, '$.k'), ?, ?, json_extract(value, '$.s'), json_extract(value, '$.t'), json_extract(value, '$.r'), ?, ?
             FROM json_each(?)`,
          ).bind(lang, game, now, now, JSON.stringify(rows)).run();
          await indexBlocks(db, lang, rows.filter((r) => r.t));
        }
        // Aynı satır aynı istekte birden çok kez geçtiyse.
        const byKey = new Map(missing.filter((m) => m.result !== null).map((m) => [m.key, m]));
        for (const item of items) {
          if (item.result === null && item.key && byKey.has(item.key)) { item.result = byKey.get(item.key).result; item.tier = 1; }
        }
      }
    }
  }

  // Aynı satır istekte birden çok geçtiyse (benzer satırdan gelenler dahil) hepsine aynı çeviri.
  const done = new Map(items.filter((i) => i.key && i.result !== null).map((i) => [i.key, i]));
  for (const item of items) {
    if (item.result === null && item.key && done.has(item.key)) { item.result = done.get(item.key).result; item.tier = done.get(item.key).tier; }
  }

  return {
    status: 200,
    body: {
      ok: true,
      ...(limited ? { limited } : {}),
      ...(game ? { game } : {}),
      translations: items.map((i) => ({ text: i.result, tier: i.tier })),
    },
  };
}

/**
 * GET /v1/translations?lang=tr&game=gta-vi&since=0
 * Oyunun (game boşsa bütün) çevirileri, `since`ten sonra değişenler. Sayfalı: next varsa since=next.updated, after=next.key.
 * → { ok, now, items:[[key, text, updated, tier]], next }
 */
export async function listTranslations(db, params, now) {
  const lang = (params.get("lang") ?? "").toLowerCase().split(/[-_]/)[0];
  if (!LANGUAGES[lang]) return { status: 400, body: { ok: false, error: "bad_lang" } };
  const game = canonicalGame(params.get("game") ?? "");
  if (game && !GAME.test(game)) return { status: 400, body: { ok: false, error: "bad_game" } };
  const since = Math.max(0, Number.parseInt(params.get("since") ?? "0", 10) || 0);
  const after = /^[0-9a-f]{16}$/.test(params.get("after") ?? "") ? params.get("after") : "";
  const limit = TRANSLATE_LIMITS.pageSize;
  // Aynı oyun platformlara göre farklı adla gelebiliyor (gta-v / grand-theft-auto-v); havuz küçükken dilin bütün
  // çevirileri verilir. TRANSLATIONS_BY_GAME=1 ile oyuna göre süzülür.
  const byGame = game && params.get("_byGame") === "1";
  const gameFilter = byGame ? "AND (t.game = ?4 OR EXISTS (SELECT 1 FROM lines l WHERE l.game = ?4 AND l.key = t.key))" : "";
  const { results } = await db.prepare(
    `SELECT t.key, t.text, t.updated, t.tier FROM translations t
     WHERE t.lang = ?1 AND t.text <> '' AND (t.updated > ?2 OR (?3 <> '' AND t.updated = ?2 AND t.key > ?3)) ${gameFilter}
     ORDER BY t.updated, t.key LIMIT ${limit}`,
  ).bind(...(byGame ? [lang, since, after, game] : [lang, since, after])).all();
  const items = results.map((r) => [r.key, r.text, r.updated, r.tier]);
  const last = results[results.length - 1];
  return {
    status: 200,
    body: { ok: true, now, items, next: results.length === limit ? { since: last.updated, after: last.key } : null },
  };
}

/** Toplu işlemde bir parçanın (20 satır) tahmini maliyeti (mikro dolar); cevap gelene kadar bütçeden düşülür. */
const BATCH_CHUNK_ESTIMATE = 20000;
/** Bu kadar saatte bitmeyen toplu işlem unutulur (Anthropic en çok 24 saatte bitirir). */
const BATCH_FORGET_SECONDS = 26 * 3600;

/**
 * Sıradaki gözden geçirilecek parça: en eski gözden geçirilmemiş çeviriler, oyun ve dile göre, görüldükleri sırayla.
 * İzinsiz oyun/dil ve çöp satırlar para harcanmadan gözden geçirilmiş sayılır. `exclude`: bu turda seçilenler.
 */
async function nextChunk(db, env, now, delay, exclude) {
  for (let guard = 0; guard < 20; guard++) {
    const group = await db.prepare(
      `SELECT lang, game FROM translations t WHERE tier = 1 AND text <> '' AND created < ? AND copy_of IS NULL
         AND NOT EXISTS (SELECT 1 FROM review_pending p WHERE p.lang = t.lang AND p.key = t.key)
         AND key NOT IN (SELECT value FROM json_each(?))
       GROUP BY lang, game ORDER BY MIN(created) LIMIT 1`,
    ).bind(now - delay, JSON.stringify([...exclude])).first();
    if (!group) return null;
    if (!gameAllowed(env, group.game) || !langAllowed(env, group.lang)) {
      // İzinli olmayan oyun ya da dilin satırları gözden geçirilmez (para harcanmaz); bir daha seçilmesin diye işaretlenir.
      await db.prepare("UPDATE translations SET tier = 2 WHERE tier = 1 AND lang = ? AND game = ?").bind(group.lang, group.game).run();
      continue;
    }
    const { results } = await db.prepare(
      `SELECT t.key, t.source, t.text,
              COALESCE((SELECT MIN(l.first_seen) FROM lines l WHERE l.key = t.key AND (l.game = t.game OR t.game = '')), t.created) AS seen
       FROM translations t
       WHERE t.tier = 1 AND t.text <> '' AND t.lang = ? AND t.game = ? AND t.created < ? AND t.copy_of IS NULL
         AND NOT EXISTS (SELECT 1 FROM review_pending p WHERE p.lang = t.lang AND p.key = t.key)
         AND t.key NOT IN (SELECT value FROM json_each(?))
       ORDER BY seen, t.key LIMIT ${TRANSLATE_LIMITS.reviewChunk}`,
    ).bind(group.lang, group.game, now - delay, JSON.stringify([...exclude])).all();
    if (results.length === 0) return null;
    const junk = results.filter((r) => junkReason(r.source));
    if (junk.length > 0) {
      await db.prepare(`UPDATE translations SET tier = 2 WHERE lang = ?1 AND key IN (SELECT value FROM json_each(?2))`)
        .bind(group.lang, JSON.stringify(junk.map((r) => r.key))).run();
    }
    const rows = results.filter((r) => !junkReason(r.source));
    if (rows.length > 0) return { lang: group.lang, game: group.game, rows };
  }
  return null;
}

/** Gözden geçirilmiş metinleri yazar (null: ret ya da bozuk cevap, satırlar olduğu gibi kalır). Dönüş: değişen sayısı. */
async function applyReview(db, lang, rows, texts, now) {
  if (!texts) {
    await db.prepare(`UPDATE translations SET tier = 2 WHERE lang = ?1 AND key IN (SELECT value FROM json_each(?2))`)
      .bind(lang, JSON.stringify(rows.map((r) => r.key))).run();
    return 0;
  }
  let changed = 0;
  const out = rows.map((r, i) => {
    const better = usable(r.source, texts[i]) ? clean(texts[i]) : r.text;
    if (better !== r.text) changed++;
    return { k: r.key, t: better, c: better !== r.text ? 1 : 0 };
  });
  await db.prepare(
    `UPDATE translations SET
       tier = 2,
       text = (SELECT json_extract(value, '$.t') FROM json_each(?1) WHERE json_extract(value, '$.k') = translations.key),
       updated = CASE WHEN (SELECT json_extract(value, '$.c') FROM json_each(?1) WHERE json_extract(value, '$.k') = translations.key) = 1
                      THEN ?2 ELSE updated END
     WHERE lang = ?3 AND key IN (SELECT json_extract(value, '$.k') FROM json_each(?1))`,
  ).bind(JSON.stringify(out), now, lang).run();
  // Bozuk kopyalar aslının gözden geçirilmiş metnini alır (ayrıca ücretlendirilmez).
  await db.prepare(
    `UPDATE translations SET
       tier = 2,
       updated = CASE WHEN text IS (SELECT json_extract(value, '$.t') FROM json_each(?1) WHERE json_extract(value, '$.k') = translations.copy_of)
                      THEN updated ELSE ?2 END,
       text = (SELECT json_extract(value, '$.t') FROM json_each(?1) WHERE json_extract(value, '$.k') = translations.copy_of)
     WHERE lang = ?3 AND copy_of IN (SELECT json_extract(value, '$.k') FROM json_each(?1))`,
  ).bind(JSON.stringify(out), now, lang).run().catch((error) => console.error("kopyalar güncellenemedi", error));
  return changed;
}

/**
 * Gözden geçirme turu (zamanlanmış, 30 dakikada bir). Varsayılan: toplu işlem (Batch API, yarı fiyat) — önce biten
 * toplu işlemlerin sonuçları yazılır, sonra bütçe kalırsa yenileri gönderilir. `review` verilirse (testler) ya da
 * env.REVIEW_BATCH = "0" ise eskisi gibi anında. Değişen çevirinin `updated`i yenilenir; uygulamalar sonraki çekişte alır.
 */
export async function reviewTranslations(db, env, now, review = undefined, delay = TRANSLATE_LIMITS.reviewDelay, batches = undefined) {
  // Gözden geçirme yalnız Claude ile (Opus); ücretsiz düzende kapalı.
  if (!translateEnabled(env) || !claudeEnabled(env)) return { reviewed: 0, changed: 0, cost: 0 };
  if (review || env.REVIEW_BATCH === "0") return reviewNow(db, env, now, review ?? askReview, delay);
  return reviewInBatches(db, env, now, delay, batches ?? anthropicBatches(env));
}

async function reviewNow(db, env, now, review, delay) {
  const cap = capMicro(env) * TRANSLATE_LIMITS.reviewShare;
  let reviewed = 0;
  let changed = 0;
  let cost = 0;
  let failed = 0;
  for (let run = 0; run < TRANSLATE_LIMITS.reviewChunksPerRun; run++) {
    if ((await spentToday(db, now)) >= cap) break;
    const chunk = await nextChunk(db, env, now, delay, new Set());
    if (!chunk) break;
    let answer = { texts: null, cost: 0 };
    try {
      answer = await review(env, chunk.lang, chunk.game, chunk.rows.map((r) => ({ source: r.source, text: r.text })));
    } catch (error) {
      console.error("gözden geçirme hatası", error);
    }
    if (answer.cost) { await addCost(db, now, answer.cost, true); cost += answer.cost; }
    if (!answer.texts) failed++;
    else reviewed += chunk.rows.length;
    changed += await applyReview(db, chunk.lang, chunk.rows, answer.texts, now);
  }
  return { reviewed, changed, cost, ...(failed ? { failed } : {}) };
}

async function reviewInBatches(db, env, now, delay, batches) {
  let reviewed = 0;
  let changed = 0;
  let cost = 0;
  let failed = 0;
  let pendingChunks = 0;

  // 1) Bitenleri topla.
  const { results: open } = await db.prepare("SELECT id, model, chunks, created FROM review_batches ORDER BY created").all();
  for (const batch of open) {
    const chunks = JSON.parse(batch.chunks);
    let status = null;
    try {
      status = await batches.retrieve(batch.id);
    } catch (error) {
      console.error("toplu işlem sorulamadı", batch.id, String(error?.message ?? error).slice(0, 200));
    }
    if (status?.processing_status !== "ended") {
      if (now - batch.created > BATCH_FORGET_SECONDS) {
        await db.prepare("DELETE FROM review_pending WHERE batch = ?").bind(batch.id).run();
        await db.prepare("DELETE FROM review_batches WHERE id = ?").bind(batch.id).run();
      } else {
        pendingChunks += chunks.length;
      }
      continue;
    }
    let results = [];
    try {
      results = await batches.results(batch.id);
    } catch (error) {
      console.error("toplu işlem sonuçları okunamadı", batch.id, String(error?.message ?? error).slice(0, 200));
      pendingChunks += chunks.length;
      continue;
    }
    const byId = new Map(results.map((r) => [r.custom_id, r.result]));
    for (const chunk of chunks) {
      const result = byId.get(chunk.id);
      const { results: rows } = await db.prepare(
        `SELECT key, source, text FROM translations WHERE lang = ?1 AND key IN (SELECT value FROM json_each(?2))`,
      ).bind(chunk.lang, JSON.stringify(chunk.keys)).all();
      const ordered = chunk.keys.map((k) => rows.find((r) => r.key === k)).filter(Boolean);
      if (result?.type === "succeeded") {
        const micro = Math.ceil(translateCost(batch.model, result.message.usage) / 2);
        await addCost(db, now, micro, true);
        cost += micro;
        let texts = null;
        try {
          texts = parseReview(ordered, result.message);
        } catch {
          texts = null;
        }
        if (!texts) failed++;
        else reviewed += ordered.length;
        changed += await applyReview(db, chunk.lang, ordered, texts, now);
      } else if (result?.type === "errored" && result.error?.error?.type === "invalid_request_error") {
        // Geçersiz istek her seferinde reddedilir: yeniden gönderilmesin.
        failed++;
        await applyReview(db, chunk.lang, ordered, null, now);
      }
      // Sunucu hatası, süresi dolmuş ya da iptal: satırlar gözden geçirilmemiş kalır, sonraki turda yeniden gönderilir.
    }
    await db.prepare("DELETE FROM review_pending WHERE batch = ?").bind(batch.id).run();
    await db.prepare("DELETE FROM review_batches WHERE id = ?").bind(batch.id).run();
  }

  // 2) Bütçe kalırsa yenilerini gönder (bekleyenlerin tahmini maliyeti de düşülür).
  const cap = capMicro(env) * TRANSLATE_LIMITS.reviewShare;
  const room = cap - (await spentToday(db, now)) - pendingChunks * BATCH_CHUNK_ESTIMATE;
  const allowed = Math.min(TRANSLATE_LIMITS.reviewChunksPerRun, Math.floor(room / BATCH_CHUNK_ESTIMATE));
  const picked = [];
  const exclude = new Set();
  for (let i = 0; i < allowed; i++) {
    const chunk = await nextChunk(db, env, now, delay, exclude);
    if (!chunk) break;
    for (const r of chunk.rows) exclude.add(r.key);
    picked.push(chunk);
  }
  let submitted = 0;
  if (picked.length > 0) {
    const effort = reviewEffort(env);
    const requests = picked.map((chunk, i) => ({
      custom_id: `c${i}`,
      params: reviewParams(chunk.lang, chunk.game, chunk.rows.map((r) => ({ source: r.source, text: r.text })), { model: REVIEW_MODEL, effort }),
    }));
    try {
      const batch = await batches.create(requests);
      const chunks = picked.map((chunk, i) => ({ id: `c${i}`, lang: chunk.lang, game: chunk.game, keys: chunk.rows.map((r) => r.key) }));
      await db.prepare("INSERT INTO review_batches (id, model, chunks, created) VALUES (?, ?, ?, ?)")
        .bind(batch.id, REVIEW_MODEL, JSON.stringify(chunks), now).run();
      const pending = chunks.flatMap((c) => c.keys.map((k) => ({ l: c.lang, k })));
      await db.prepare(
        `INSERT OR REPLACE INTO review_pending (lang, key, batch)
         SELECT json_extract(value, '$.l'), json_extract(value, '$.k'), ? FROM json_each(?)`,
      ).bind(batch.id, JSON.stringify(pending)).run();
      submitted = picked.length;
    } catch (error) {
      console.error("toplu işlem gönderilemedi", String(error?.message ?? error).slice(0, 200));
    }
  }
  return { reviewed, changed, cost, submitted, pending: pendingChunks + submitted, ...(failed ? { failed } : {}) };
}

/** GET /v1/config: uygulamaların uzaktan ayarı (yeni sürüm gerekmeden açılıp kapanır). */
/** Havuz öncelikli oyunlar: env.POOL_FIRST_GAMES (virgüllü), yoksa GTA 6'nın adları. */
export const POOL_FIRST_DEFAULT = Object.freeze(["grand-theft-auto-vi", "gta-vi", "gta-6", "gta6"]);

export function poolFirstGames(env) {
  if (env.POOL_FIRST_GAMES === undefined) return [...POOL_FIRST_DEFAULT];
  // Takma adlar listede kalır: eski uygulamalar /v1/config'teki bu listeyi kendi kimlikleriyle ("grand-theft-auto-vi")
  // karşılaştırıyor.
  return String(env.POOL_FIRST_GAMES).split(",").map((g) => g.trim().toLowerCase().replace(/-{2,}/g, "-")).filter(Boolean);
}

export function remoteConfig(env) {
  const num = (v, d) => (Number.isFinite(Number(v)) && v !== undefined && v !== "" ? Number(v) : d);
  return {
    ok: true,
    translate: {
      enabled: translateEnabled(env),
      deadlineMs: num(env.TRANSLATE_DEADLINE_MS, 900),
      syncSeconds: num(env.TRANSLATE_SYNC_SECONDS, 180),
      contextLines: TRANSLATE_LIMITS.maxContext,
      maxLines: TRANSLATE_LIMITS.maxLines,
    },
    // Nino: bu oyunlarda uygulama satırı önce sunucuya sorar, kullanıcının kendi motorunu (Gemini, DeepL, yapay zekâ)
    // hiç çağırmaz; sunucu `deadlineMs` içinde cevap vermezse yalnız cihazın ücretsiz çevirisine düşer. Kimlikler
    // NinoPool.gameId biçiminde; eşleşme TRANSLATE_GAMES gibi "kimlik bu parçayı içeriyor" kuralıyla.
    poolFirst: {
      games: poolFirstGames(env),
      // Havuz öncelik yalnız bu hedef dillerde (Claude yalnız bunlarda çevirir); öbür dillerde uygulama kendi motorunu kullanır.
      langs: translateLangs(env),
      deadlineMs: num(env.POOL_FIRST_DEADLINE_MS, 1500),
    },
    minVersion: {
      mac: env.MIN_VERSION_MAC ?? "",
      windows: env.MIN_VERSION_WINDOWS ?? "",
      android: env.MIN_VERSION_ANDROID ?? "",
      ios: env.MIN_VERSION_IOS ?? "",
    },
  };
}
