// SPDX-License-Identifier: AGPL-3.0-only
// Nino: ücretsiz çeviri zinciri. Claude yerine ücretsiz planı olan servisler kalite sırasıyla denenir; günlük hakkı biten
// (429) servis bir süre atlanır, sıradaki denenir. Hepsi doluysa satır çevrilmez, uygulama cihazın ücretsiz çevirisini
// gösterir. Para harcanmaz: anahtarlar ücretsiz planlardandır (faturalandırma kapalı), hak dolunca servis yalnız reddeder.
//
// Sıra env.FREE_CHAIN ile verilir (virgüllü "servis:model"), ör. "gemini:gemini-2.5-flash,gemini:gemini-2.5-flash-lite".
// Anahtarı olmayan servis atlanır. Servisler: gemini (GEMINI_API_KEY), deepl:free (DEEPL_API_KEY, aylık karakter hakkı), openai uyumlular: mistral (MISTRAL_API_KEY),
// groq (GROQ_API_KEY), openrouter (OPENROUTER_API_KEY), nvidia (NVIDIA_API_KEY); workersai (anahtar yok, [ai] bağı,
// günlük ücretsiz nöron sınırının altında kalır).

import { instructions, compactInstructions, LANGUAGES, usable } from "./translate.js";

/** Hak doldu cevabında bekleme süresi söylenmezse bu kadar saniye atlanır (söylenirse o kadar). */
export const PAUSE_SECONDS = 2 * 60;
/** Bir servisin cevabı için en çok bekleme (ms); uygulama sunucuyu ~3 sn bekliyor. */
export const FREE_TIMEOUT_MS = 2500;

const OPENAI_COMPATIBLE = {
  mistral: { url: "https://api.mistral.ai/v1/chat/completions", key: "MISTRAL_API_KEY" },
  groq: { url: "https://api.groq.com/openai/v1/chat/completions", key: "GROQ_API_KEY" },
  openrouter: { url: "https://openrouter.ai/api/v1/chat/completions", key: "OPENROUTER_API_KEY" },
  // NVIDIA (build.nvidia.com): ücretsiz geliştirici erişimi, model başına dakikada ~40 istek. Resmen araştırma/test için;
  // kullanıcı bilerek en sona yedek koydu.
  nvidia: { url: "https://integrate.api.nvidia.com/v1/chat/completions", key: "NVIDIA_API_KEY" },
};

class QuotaError extends Error {
  /** Servisin söylediği bekleme (saniye; Gemini RetryInfo.retryDelay ya da retry-after başlığı), bilinmiyorsa null. */
  constructor(message, retrySeconds = null) {
    super(message);
    this.retrySeconds = retrySeconds;
  }
}

/** 429 cevabından bekleme süresi: retry-after başlığı ya da Gemini'nin "retryDelay": "6s". */
export function retrySeconds(headers, body) {
  const header = Number(headers?.get?.("retry-after"));
  if (Number.isFinite(header) && header > 0) return header;
  const match = String(body ?? "").match(/"retryDelay":\s*"(\d+(?:\.\d+)?)s"/);
  return match ? Number(match[1]) : null;
}
/** Model yok/kaldırılmış (404, 410) ya da istek hiç kabul edilmiyor (400): uzun süre atlanır. */
class GoneError extends Error {}
const GONE_PAUSE_SECONDS = 6 * 3600;

function timeoutMs(env) {
  const ms = Number(env?.FREE_TIMEOUT_MS);
  return Number.isFinite(ms) && ms > 0 ? ms : FREE_TIMEOUT_MS;
}

/** Zincir: [{ provider, model, id }] (anahtarı olmayanlar çıkarılmış). */
export function freeChain(env) {
  return String(env?.FREE_CHAIN ?? "").split(",").map((s) => s.trim()).filter(Boolean).map((entry) => {
    const [provider, ...rest] = entry.split(":");
    return { provider, model: rest.join(":"), id: entry };
  }).filter(({ provider, model }) => model && keyOf(env, provider));
}

function keyOf(env, provider) {
  if (provider === "gemini") return env.GEMINI_API_KEY;
  if (provider === "deepl") return env.DEEPL_API_KEY;
  if (provider === "workersai") return env.AI;
  return OPENAI_COMPATIBLE[provider] ? env[OPENAI_COMPATIBLE[provider].key] : undefined;
}

export function freeEnabled(env) {
  return env?.TRANSLATE_ENGINE === "free" && freeChain(env).length > 0;
}

function prompt(lang, lines, context) {
  return [
    context.length ? `Context (do not translate):\n${context.map((c) => `- ${c}`).join("\n")}\n` : "",
    `Translate these ${lines.length} lines into ${LANGUAGES[lang]}. Return JSON {"translations": [...]} with exactly ${lines.length} strings in the same order.`,
    ...lines.map((line, i) => `${i + 1}. ${line}`),
  ].filter(Boolean).join("\n");
}

function parse(text, count) {
  const cleaned = String(text ?? "").replace(/^```(?:json)?\s*|\s*```$/g, "").trim();
  const parsed = JSON.parse(cleaned);
  const list = Array.isArray(parsed) ? parsed : parsed?.translations;
  return Array.isArray(list) && list.length === count && list.every((t) => typeof t === "string") ? list : null;
}

async function post(url, headers, body, timeoutMs, fetcher) {
  const response = await fetcher(url, {
    method: "POST",
    headers: { "content-type": "application/json", ...headers },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(timeoutMs),
  });
  // 429: hak/hız sınırı; 456: DeepL'in aylık karakter hakkı doldu.
  if (response.status === 429 || response.status === 456) {
    const text = await response.text();
    throw new QuotaError(`${response.status} ${text.slice(0, 3000)}`, response.status === 429 ? retrySeconds(response.headers, text) : null);
  }
  if ([400, 404, 410].includes(response.status)) throw new GoneError(`${response.status} ${(await response.text()).slice(0, 200)}`);
  if (!response.ok) throw new Error(`${response.status} ${(await response.text()).slice(0, 200)}`);
  return response.json();
}

const SAFETY_OFF = ["HARM_CATEGORY_HARASSMENT", "HARM_CATEGORY_HATE_SPEECH", "HARM_CATEGORY_SEXUALLY_EXPLICIT", "HARM_CATEGORY_DANGEROUS_CONTENT"]
  .map((category) => ({ category, threshold: "BLOCK_NONE" }));

function geminiThinking(mode = "minimal") {
  if (mode === "default") return {};
  if (mode === "off") return { thinkingConfig: { thinkingBudget: 0 } };
  return { thinkingConfig: { thinkingLevel: mode } };
}

async function askGemini(env, model, lang, lines, context, timeoutMs, fetcher) {
  const data = await post(
    `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:generateContent`,
    { "x-goog-api-key": env.GEMINI_API_KEY },
    {
      systemInstruction: { parts: [{ text: instructions(lang) }] },
      contents: [{ role: "user", parts: [{ text: prompt(lang, lines, context) }] }],
      safetySettings: SAFETY_OFF,
      generationConfig: {
        temperature: 0.3,
        responseMimeType: "application/json",
        responseSchema: { type: "OBJECT", properties: { translations: { type: "ARRAY", items: { type: "STRING" } } }, required: ["translations"] },
        // Düşünme hız için kısılır: "off" (2.x: bütçe 0), "minimal"/"low" (3.x: düşünme düzeyi), "default" (modelin kendisi).
        ...geminiThinking(env.GEMINI_THINKING),
      },
    },
    timeoutMs,
    fetcher,
  );
  const text = (data.candidates?.[0]?.content?.parts ?? []).map((p) => p.text ?? "").join("");
  return parse(text, lines.length);
}

/** DeepL hedef dil kodları (Nino dili → DeepL). */
const DEEPL_LANGS = { tr: "TR", ar: "AR", id: "ID", nl: "NL", vi: "VI", th: "TH" };

/** DeepL (çeviri motoru, model yok): "deepl:free". Bağlam satırları `context` olarak verilir (ücretlendirilmez). */
async function askDeepL(env, lang, lines, context, timeoutMs, fetcher) {
  const target = DEEPL_LANGS[lang];
  if (!target) return null;
  const host = String(env.DEEPL_API_KEY).endsWith(":fx") ? "api-free.deepl.com" : "api.deepl.com";
  const data = await post(`https://${host}/v2/translate`, { authorization: `DeepL-Auth-Key ${env.DEEPL_API_KEY}` }, {
    text: lines,
    source_lang: "EN",
    target_lang: target,
    formality: "prefer_less",
    ...(context.length ? { context: context.join("\n") } : {}),
  }, timeoutMs, fetcher);
  const texts = (data.translations ?? []).map((t) => t.text);
  return texts.length === lines.length ? texts : null;
}

/**
 * Cloudflare Workers AI çeviri modeli (anahtar yok, `[ai]` bağı): "workersai:@cf/meta/m2m100-1.2b". Ücretli Workers
 * planında günlük ücretsiz 10.000 nöron aşılınca para yazar; bu yüzden tahmini nöron sayılır ve WORKERS_AI_DAILY_NEURONS
 * (varsayılan 8.000) dolunca o gün hiç çağrılmaz. m2m100: milyon jeton başına 31.050 nöron (girdi ve çıktı ayrı).
 */
export const WORKERS_AI_NEURONS_PER_TOKEN = 31050 / 1_000_000;
const M2M_LANGS = { tr: "turkish", ar: "arabic", hi: "hindi", id: "indonesian", th: "thai", vi: "vietnamese", ur: "urdu", bn: "bengali", ms: "malay", nl: "dutch" };

/** Tahmini nöron: girdi + çıktı jetonu (≈ 3 harf bir jeton, Türkçe çıktı biraz uzun; bol tutulur). */
export function workersAiEstimate(lines) {
  const chars = lines.reduce((n, l) => n + [...l].length, 0);
  const tokens = Math.ceil(chars / 3) * 2.5 + lines.length * 10;
  return tokens * WORKERS_AI_NEURONS_PER_TOKEN;
}

function workersAiCap(env) {
  const cap = Number(env.WORKERS_AI_DAILY_NEURONS);
  return Number.isFinite(cap) && cap >= 0 ? cap : 8000;
}

async function askWorkersAI(env, model, lang, lines, db, id, now) {
  const target = M2M_LANGS[lang];
  if (!target) return null;
  const day = new Date(now * 1000).toISOString().slice(0, 10);
  const estimate = workersAiEstimate(lines);
  const used = (await db?.prepare("SELECT units FROM free_usage WHERE day = ? AND id = ?").bind(day, id).first("units").catch(() => null)) ?? 0;
  // Sayılamıyorsa (veritabanı yok) hiç çağrılmaz: para yazma ihtimali olan servis yalnız sayılabildiğinde kullanılır.
  if (!db || used + estimate > workersAiCap(env)) throw new QuotaError(`günlük nöron sınırı (${Math.round(used)})`);
  await db.prepare(`INSERT INTO free_usage (day, id, units) VALUES (?1, ?2, ?3)
                    ON CONFLICT(day, id) DO UPDATE SET units = units + excluded.units`).bind(day, id, estimate).run();
  const out = await Promise.all(lines.map((text) => env.AI.run(model, { text, source_lang: "english", target_lang: target })));
  const texts = out.map((r) => r?.translated_text);
  return texts.every((t) => typeof t === "string" && t.trim()) ? texts : null;
}

async function askOpenAI(env, provider, model, lang, lines, context, timeoutMs, fetcher, meter = {}) {
  const { url, key } = OPENAI_COMPATIBLE[provider];
  const data = await post(url, { authorization: `Bearer ${env[key]}` }, {
    model,
    temperature: 0.3,
    response_format: { type: "json_object" },
    // Kısa talimat: bu servislerin sınırı dakikadaki jeton; uzun talimat hakkı birkaç istekte bitirir.
    messages: [{ role: "system", content: compactInstructions(lang) }, { role: "user", content: prompt(lang, lines, context) }],
    // OpenRouter: cevapla birlikte gerçek maliyet (usage.cost, dolar) gelir; ücretli modelde günlük dolar sınırı için.
    ...(provider === "openrouter" ? { usage: { include: true }, reasoning: { effort: "low" } } : {}),
  }, timeoutMs, fetcher);
  meter.cost = Number(data.usage?.cost) || 0;
  return parse(data.choices?.[0]?.message?.content, lines.length);
}

// Sunucu örneği içi: servis → bu zamana kadar atla (D1'de de tutulur, öbür örnekler de görsün).
const paused = new Map();

async function isPaused(db, id, now) {
  if ((paused.get(id) ?? 0) > now) return true;
  const until = await db?.prepare("SELECT until FROM free_pause WHERE id = ?").bind(id).first("until").catch(() => null);
  if (until && until > now) { paused.set(id, until); return true; }
  return false;
}

async function pause(db, id, now, seconds = PAUSE_SECONDS) {
  const until = now + seconds;
  paused.set(id, until);
  await db?.prepare("INSERT INTO free_pause (id, until) VALUES (?1, ?2) ON CONFLICT(id) DO UPDATE SET until = ?2")
    .bind(id, until).run().catch(() => {});
}

/** FREE_DAILY_LINES ("id=satır,id=satır") içinde bu servisin günlük sınırı; yoksa null. */
export function dailyLimit(env, id) {
  for (const part of String(env?.FREE_DAILY_LINES ?? "").split(",")) {
    const at = part.lastIndexOf("=");
    if (at > 0 && part.slice(0, at).trim() === id) {
      const n = Number(part.slice(at + 1));
      return Number.isFinite(n) && n >= 0 ? n : null;
    }
  }
  return null;
}

async function countToday(db, now, id) {
  const day = new Date(now * 1000).toISOString().slice(0, 10);
  return (await db?.prepare("SELECT units FROM free_usage WHERE day = ? AND id = ?").bind(day, id).first("units").catch(() => 0)) ?? 0;
}

/** Günlük sayaç (free_usage): "ok:<id>" çevrilen satır, "full:<id>" hak doldu cevabı, "err:<id>" hata. */
/** Para giden servis: OpenRouter'da adı ":free" ile bitmeyen model. */
export function isPaid(provider, model) {
  return provider === "openrouter" && !String(model).endsWith(":free");
}

async function count(db, now, id, n) {
  const day = new Date(now * 1000).toISOString().slice(0, 10);
  await db?.prepare(`INSERT INTO free_usage (day, id, units) VALUES (?1, ?2, ?3)
                     ON CONFLICT(day, id) DO UPDATE SET units = units + excluded.units`).bind(day, id, n).run().catch(() => {});
}

/**
 * Zinciri sırayla dener. Dönüş { texts: string[]|null, cost: 0, model }. `db` hak dolduğunu öbür örneklere bildirmek için.
 */
export async function askFree(env, lang, lines, context, {
  db = env?.DB, now = Math.floor(Date.now() / 1000), fetcher = fetch, chain = freeChain(env), timeout = timeoutMs(env), partial = false,
} = {}) {
  for (const { provider, model, id } of chain) {
    if (await isPaused(db, id, now)) continue;
    // Günlük satır sınırı (aylık hakkı olan servis, ör. DeepL, bir günde bitmesin): FREE_DAILY_LINES "deepl:free=600".
    const limit = dailyLimit(env, id);
    if (limit !== null && (await countToday(db, now, `ok:${id}`)) + lines.length > limit) continue;
    // Ücretli servisin günlük dolar sınırı: FREE_DAILY_USD "openrouter:openai/gpt-oss-120b=3".
    const usd = dailyLimit({ FREE_DAILY_LINES: env?.FREE_DAILY_USD }, id);
    if (usd !== null && (await countToday(db, now, `usd:${id}`)) >= usd) continue;
    // Bütün ücretli servislerin toplamı (FREE_PAID_DAILY_USD): OpenRouter'ın ":free" olmayan modelleri ücretli sayılır.
    const paidCap = Number(env?.FREE_PAID_DAILY_USD);
    if (isPaid(provider, model) && Number.isFinite(paidCap) && (await countToday(db, now, "usd:all")) >= paidCap) continue;
    const meter = { cost: 0 };
    try {
      const texts = provider === "gemini" ? await askGemini(env, model, lang, lines, context, timeout, fetcher)
        : provider === "deepl" ? await askDeepL(env, lang, lines, context, timeout, fetcher)
          : provider === "workersai" ? await askWorkersAI(env, model, lang, lines, db, id, now)
            : await askOpenAI(env, provider, model, lang, lines, context, timeout, fetcher, meter);
      // Para giden her cevap sayılır (kullanılmasa da).
      if (meter.cost) await count(db, now, `usd:${id}`, meter.cost);
      if (meter.cost) await count(db, now, "usd:all", meter.cost);
      if (texts && texts.every((t, i) => usable(lines[i], t))) {
        await count(db, now, `ok:${id}`, lines.length);
        return { texts, cost: 0, model: id };
      }
      // Toplu çeviride (50 satır) tek bozuk satır partiyi düşürmesin: kullanılamayan satır null döner.
      if (partial && texts) {
        const kept = texts.map((t, i) => (usable(lines[i], t) ? t : null));
        if (kept.filter(Boolean).length * 5 >= lines.length * 4) {
          await count(db, now, `ok:${id}`, kept.filter(Boolean).length);
          return { texts: kept, cost: 0, model: id };
        }
      }
    } catch (error) {
      await count(db, now, `${error instanceof QuotaError ? "full" : "err"}:${id}`, 1);
      // Servis ne kadar beklenmesini söylediyse o kadar (dakikalık sınırda birkaç saniye, günlükte yenilenene kadar).
      if (error instanceof QuotaError) {
        await pause(db, id, now, error.retrySeconds ? Math.min(Math.max(Math.ceil(error.retrySeconds) + 1, 5), 86400) : PAUSE_SECONDS);
      }
      else if (error instanceof GoneError) await pause(db, id, now, GONE_PAUSE_SECONDS);
      console.error("ücretsiz çeviri hatası", id, String(error?.message ?? error).slice(0, 200));
    }
  }
  return { texts: null, cost: 0 };
}

/**
 * Tanı: zincirdeki her servise kısa bir satır sorar, durdurmayı ve sayacı atlar. Dönüş [{ id, ms, ok, text?, error? }].
 * GET /v1/free-check (yönetici anahtarıyla).
 */
export async function checkFree(env, fetcher = fetch, sample = ["Get in the car!"]) {
  const out = [];
  for (const { provider, model, id } of freeChain(env)) {
    if (provider === "workersai") continue;
    const started = Date.now();
    try {
      const meter = { cost: 0 };
      const texts = provider === "gemini" ? await askGemini(env, model, "tr", sample, [], 30000, fetcher)
        : provider === "deepl" ? await askDeepL(env, "tr", sample, [], 30000, fetcher)
          : await askOpenAI(env, provider, model, "tr", sample, [], 30000, fetcher, meter);
      out.push({ id, ms: Date.now() - started, ok: Boolean(texts), cost: meter.cost, texts });
    } catch (error) {
      out.push({ id, ms: Date.now() - started, ok: false, error: String(error?.message ?? error).slice(0, 3000) });
    }
  }
  return out;
}
