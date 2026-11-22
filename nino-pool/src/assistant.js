// SPDX-License-Identifier: AGPL-3.0-only
// Nino yardımcısı ("Nino robotu"): uygulamalardaki sohbet. Kullanıcının sorusunu (ve ekran görüntülerini) kurulum bilgi
// tabanıyla birlikte seçilen modele sorar; model çözemediğini kullanıcı onaylarsa Sorun Bildir'e bildirim yazar.
// Sıra: 1) hazır cevap kütüphanesi (assistant/hazir-cevaplar.json, model yok), 2) aynı ilk sorunun kayıtlı cevabı (D1),
// 3) ana model (ASSISTANT_PROVIDER: anthropic | gemini | deepseek | openrouter, ASSISTANT_MODEL; ASSISTANT_DAILY_USD sayılan
// sınır), 4) yedek model (ASSISTANT_FALLBACK=openrouter, ASSISTANT_FALLBACK_MODEL; gerçek maliyetle ASSISTANT_FALLBACK_DAILY_USD).
// İkisi de dolu ya da hatalıysa benzer bir hazır cevap varsa o verilir, yoksa "çok yoğunum". Anahtarlar Cloudflare
// sırlarıdır (ANTHROPIC_API_KEY, GEMINI_API_KEY, DEEPSEEK_API_KEY, OPENROUTER_API_KEY) ve uygulamalara hiç gitmez.

import Anthropic from "@anthropic-ai/sdk";
import { KNOWLEDGE } from "./knowledge.js";
import { saltedDigest } from "./key.js";
import { receiveReport } from "./reports.js";
import { ANSWERS } from "./answers.js";
import { prepareLibrary, matchAnswer, baseLang, scriptLang } from "./answers-match.js";

const LIBRARY = prepareLibrary(ANSWERS);

/** Son çare cevabı: konuşmanın dilinde (yazı sistemi, yoksa uygulama dili), yoksa İngilizce. */
function busyReply(input) {
  const text = input.messages[input.messages.length - 1]?.text ?? "";
  const lang = scriptLang(text, baseLang(input.language)) ?? baseLang(input.language);
  return ANSWERS.busy?.[lang] ?? ANSWERS.busy?.en ?? "";
}

export const ASSISTANT_LIMITS = {
  maxBodyBytes: 6 * 1024 * 1024,
  maxMessages: 24,
  maxText: 2000,
  maxImages: 3,
  maxImageBytes: 1500 * 1024,
  perInstallPerDay: 60,
  dailyBudget: 4000,
  // Günlük en çok harcama (dolar). Aşılınca yardımcı ertesi güne kadar "çok yoğunum" der.
  dailyUsd: 2,
  // Hazır cevaplar bu kadar gün geçerli; bilgi tabanı değişince zaten yeni anahtar oluşur.
  answerDays: 30,
  // Yedek modelin (OpenRouter) günlük gerçek harcama sınırı (dolar).
  fallbackDailyUsd: 2,
  // Modelin cevabı en çok bu kadar beklenir (uygulamalar 90 sn bekler; ana + yedek bunun içinde kalır).
  primaryTimeoutMs: 25_000,
  fallbackTimeoutMs: 35_000,
  // Hak doldu (429) cevabı veren model bu kadar atlanır (servis süre söylemezse).
  pauseSeconds: 600,
  shortPauseSeconds: 30,
};

// Model fiyatları (dolar / milyon token). 1 dolar/MTok = token başına 1 mikro dolar.
// Bilinmeyen model ya da sağlayıcı için güvenli tarafta kalan istek başı tahmin kullanılır.
const PRICES = {
  "claude-haiku-5-5": { input: 0.10, output: 0.50, cacheRead: 0.01, cacheWrite1h: 0.20 },
};
const FALLBACK_REQUEST_MICRO_USD = 5000;

/** Anthropic kullanım bilgisinden maliyet (mikro dolar). */
export function usageCost(model, usage) {
  const price = PRICES[model];
  if (!price || !usage) return FALLBACK_REQUEST_MICRO_USD;
  return Math.ceil(
    (usage.input_tokens ?? 0) * price.input +
    (usage.output_tokens ?? 0) * price.output +
    (usage.cache_read_input_tokens ?? 0) * price.cacheRead +
    (usage.cache_creation_input_tokens ?? 0) * price.cacheWrite1h,
  );
}

/** Hesap bilgisi gizlenir: e-posta adresleri ve "şifre/parola/password" sonrasındaki sözcük. Bildirime ve hazır cevaba girmez. */
export function maskSecrets(text) {
  return String(text ?? "")
    .replace(/[\p{L}\p{N}._%+-]+@[\p{L}\p{N}.-]+\.[\p{L}]{2,}/gu, "[e-posta]")
    .replace(/((?:şifre|sifre|parola|password|pass|pw)\S*\s*[:=]?\s*)\S+/giu, "$1[gizli]");
}

function hasSecret(text) {
  return maskSecrets(text) !== String(text ?? "");
}

/** Hazır cevap anahtarı: yalnız resimsiz, tek mesajlık ilk soru için; aksi hâlde null. */
async function answerKey(input) {
  if (input.messages.length !== 1 || input.messages[0].images.length) return null;
  if (hasSecret(input.messages[0].text)) return null;
  const text = input.messages[0].text.toLocaleLowerCase("tr").normalize("NFKC")
    .replace(/[\p{P}\p{S}]+/gu, " ").replace(/\s+/g, " ").trim();
  if (!text) return null;
  const source = `${KNOWLEDGE.length}|${INSTRUCTIONS.length}|${input.language}|${input.platform}|${text}`;
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(source));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

const PLATFORMS = new Set(["mac", "windows", "linux", "android", "ios", "tv"]);
const MIMES = new Set(["image/jpeg", "image/png", "image/webp"]);
const DEFAULT_MODELS = { anthropic: "claude-haiku-5-5", gemini: "gemini-flash-lite-latest", deepseek: "deepseek-chat", openrouter: "google/gemini-2.5-flash-lite" };
const KEYS = { anthropic: "ANTHROPIC_API_KEY", gemini: "GEMINI_API_KEY", deepseek: "DEEPSEEK_API_KEY", openrouter: "OPENROUTER_API_KEY" };
// OpenRouter cevabında maliyet yoksa istek başı sayılan (güvenli tarafta) tahmin: 0,003 dolar.
const OPENROUTER_DEFAULT_MICRO_USD = 3000;

const INSTRUCTIONS = `You are "Nino", the friendly little robot helper inside the Nino Game Translator apps. You help people install
and use Nino: the free, open-source app that translates English subtitles of PS5 and Xbox games live and shows them on
the TV on top of the game.

How to answer:
- Always reply in the language the user writes in (if unclear, use the app language given below).
- The NINO KNOWLEDGE is written in Turkish. When you answer in another language, write EVERYTHING in that language,
  including menu and button names: translate Nino's own menu names (e.g. "Profil › Nino'yu TV'ye Kur" →
  "Profile › Install Nino on TV" in English), and give TV, PS5, Xbox, Windows and Mac menu names as they appear in that
  language. Never leave Turkish words in a non-Turkish answer.
- In Turkish always use the casual "sen" form (kurdun mu, söyler misin), never "siz".
- Be warm, short and concrete. Format every answer for easy reading on a phone:
  * one short opening sentence (no "Merhaba, ben Nino" after the first message), then an empty line;
  * steps as a numbered list, each step on its OWN line starting with "1.", "2.", … and ONE short action per step
    (max ~15 words; put the menu path in the step, e.g. "Ayarlar › Sistem › Hakkında'yı aç.");
  * put an empty line between steps and before any closing note or question;
  * a closing question or tip goes in its own short paragraph at the end.
  Plain text only: no tables, no headings, no bold/markdown, no markdown links (write URLs plainly).
- Base every answer on the NINO KNOWLEDGE below. If it doesn't cover the question, say honestly that you are not sure
  and suggest sending a report. Never invent menu names, features, prices or dates.
- Your character: a cheerful little robot with a red Turkish-flag cap. Friendly and casual ("sen" in Turkish), never
  childish; a light emoji now and then is fine.
- Think like an expert support technician. Start from the user's setup. If you don't yet know their devices, first
  ask (in one short message) which they have and where they want Nino: console (PS5 or Xbox), screen (Android TV /
  Google TV, Samsung or LG TV, smart or plain monitor, TV brand and model), and what runs Nino (Mac, Windows PC,
  Android phone, iPhone). When they answer (e.g. "monitor, PS5, phone"), pick the right path from the knowledge and
  give a short, numbered plan for exactly that setup.
- Installing the TV app: the way we recommend is always automatic, from the phone or computer Nino (it installs and
  later updates the TV app by itself). Never suggest third-party downloader apps. Guide it one step at a time:
  1) if you don't know it yet, first ask only for the TV brand and model (or a photo of Settings › About);
  2) then explain ONLY how to turn on developer mode / USB debugging for THAT brand (for Android TV / Google TV:
     Settings › System › About › tap "Android TV OS build" 7 times, then Developer options › USB debugging on),
     and ask the user to say when it is done;
  3) next step: tell the user to press "Install on TV" / "Kur ve aç" in Nino (phone: Profil › Nino'yu TV'ye Kur); ONLY
     THEN the TV asks "Allow USB debugging?": tick "Always allow from this computer" › Allow;
  4) last: confirm Nino opened on the TV, and remind them to leave USB debugging on so Nino can update the TV app.
  If the brand is already given, go straight to that brand's steps; never ask for the brand or model again.
  Explain TV setup for someone who knows nothing about technology: ONE step per message (which remote button to
  press, the exact menu name, what they will see on screen), short simple sentences, no jargon; if a technical word
  is unavoidable, explain it in one short sentence. End every step with ONE check question such as "Ekranında ne
  görüyorsun?" / "What do you see on the screen?" or "Bu adım tamam mı?" / "Is this step done?". Wait for the answer
  before the next step. If the TV's menu names differ by model or year, use the variant for their model; if unknown,
  give the most common one and ask what they see. If they get stuck, ask for a photo of the TV screen.
  Manual install from the TV browser (https://is.gd/ninotvapk) is only a last resort; mention that it won't update
  itself then.
- When something goes wrong, find WHERE it fails before answering: which step of the setup, what the screen shows,
  the exact error text, app versions. Ask ONE focused question at a time (never a long questionnaire) and ask for a
  screenshot when it would help; when the user sends one, read it carefully (menus, error text, which app/screen),
  tell the user in one sentence which screen/step they are on, then give the next single step.
  Then give the most likely fix first, then the next one if that doesn't help.
- Stay on topic: Nino, consoles, TVs, monitors, capture cards, streaming with Nino. Politely decline other topics.
- Never ask for passwords, PSN/Microsoft credentials, API keys or payment details. If the user writes a password,
  email or account details, never repeat them in your reply or in the report summary.
- Only use menu paths and button names that appear in the NINO KNOWLEDGE; if you don't know one, describe it in plain
  words instead of inventing a name.
- Ask exactly ONE question per message (one question mark). Even troubleshooting checklists are numbered steps.
- For an unsupported device, console or feature, send the "request" report right away and say you sent it; don't ask
  whether to send it.

Reports to the Nino team (the bug pool):
- Send a report RIGHT AWAY (no need to ask permission) when:
  * it is a bug in Nino: a crash, a button or screen that doesn't work, wrong/missing subtitles or translation that
    isn't explained by settings, an error message from Nino, something the knowledge says should work but doesn't;
  * or you have tried the fixes the knowledge offers and the problem is still not solved;
  * or the user asks for a feature or device Nino doesn't support yet (kind "request").
- To send: set "report" with kind ("bug", "unsolved" or "request") and a short English summary for the team: Nino
  device and app, console, TV/monitor brand and model, language, what happens, at which step, error text, what was
  already tried. In your reply tell the user briefly that you sent it to the team and that they will look at it, and
  still give any workaround you know.
- Send at most one report per problem in a conversation: if your earlier reply already says you sent it, don't send it
  again unless there is clearly new information.
- Otherwise "report" is null.

Reply with JSON only: {"reply": "<message to the user>", "report": null or {"kind": "bug" | "unsolved" | "request", "summary": "<for the team>"}}.`;

const REPLY_SCHEMA = {
  type: "object",
  properties: {
    reply: { type: "string" },
    report: {
      anyOf: [
        { type: "null" },
        { type: "object", properties: { kind: { type: "string", enum: ["bug", "unsolved", "request"] }, summary: { type: "string" } }, required: ["kind", "summary"], additionalProperties: false },
      ],
    },
  },
  required: ["reply", "report"],
  additionalProperties: false,
};

export function systemText(language, platform, hint = null) {
  const base = `${INSTRUCTIONS}\n\nApp language: ${language || "unknown"}. User's device running Nino: ${platform}.`;
  if (!hint) return base;
  return `${base}\n\nPREPARED ANSWER: the Nino team wrote this answer for a similar question. If it fits what the user actually asked,
base your reply on it (adapt it to the user's words, answer in the user's language); if it doesn't fit, ignore it.
---
${hint}
---`;
}

/** Sohbet modelin hak doldu cevabı (429): bir süre atlanır. */
export class QuotaError extends Error {
  constructor(message, retrySeconds) { super(message); this.retrySeconds = retrySeconds; }
}

function retrySeconds(response, data) {
  const header = Number(response.headers?.get?.("retry-after"));
  if (Number.isFinite(header) && header > 0) return header;
  const delay = data?.error?.details?.find?.((d) => d.retryDelay)?.retryDelay;
  const seconds = parseFloat(String(delay ?? ""));
  return Number.isFinite(seconds) ? seconds : null;
}

async function failed(response, name) {
  const text = await response.text().catch(() => "");
  let data = null;
  try { data = JSON.parse(text); } catch { /* düz metin */ }
  // Teşhis için hata gövdesinin başı günlüğe girer (anahtar ya da kullanıcı metni içermez).
  const detail = `${name} ${response.status} ${text.slice(0, 200).replace(/\s+/g, " ")}`;
  if (response.status === 429) return new QuotaError(detail, retrySeconds(response, data));
  return new Error(detail);
}

function withTimeout(fetcher, ms) {
  return (url, init) => fetcher(url, { ...init, signal: AbortSignal.timeout(ms) });
}

function decodeBase64(text) {
  if (typeof text !== "string" || !/^[A-Za-z0-9+/=\s]+$/.test(text)) return null;
  try {
    return atob(text.replace(/\s+/g, "")).length;
  } catch {
    return null;
  }
}

/** Gelen sohbeti doğrular: [{role: "user"|"assistant", text, images?: [{mime, data}]}]; son mesaj kullanıcınındır. */
export function validateConversation(body) {
  if (!body || typeof body !== "object" || body.v !== 1) return { error: "bad_request" };
  const install = typeof body.install === "string" ? body.install : "";
  if (install.length < 8 || install.length > 64) return { error: "bad_request" };
  const platform = PLATFORMS.has(body.platform) ? body.platform : "";
  if (!platform) return { error: "bad_platform" };
  const raw = Array.isArray(body.messages) ? body.messages.slice(-ASSISTANT_LIMITS.maxMessages) : [];
  if (!raw.length || raw[raw.length - 1]?.role !== "user") return { error: "bad_request" };
  let imageCount = 0;
  const messages = [];
  for (const message of raw) {
    const role = message?.role === "assistant" ? "assistant" : message?.role === "user" ? "user" : null;
    if (!role) return { error: "bad_request" };
    const text = typeof message.text === "string" ? message.text.slice(0, ASSISTANT_LIMITS.maxText) : "";
    const images = [];
    for (const image of (role === "user" && Array.isArray(message.images) ? message.images : [])) {
      const size = decodeBase64(image?.data);
      if (!MIMES.has(image?.mime) || !size) return { error: "bad_image" };
      if (size > ASSISTANT_LIMITS.maxImageBytes) return { error: "image_too_large", status: 413 };
      images.push({ mime: image.mime, data: image.data.replace(/\s+/g, "") });
    }
    imageCount += images.length;
    if (!text.trim() && !images.length) continue;
    messages.push({ role, text, images });
  }
  if (imageCount > ASSISTANT_LIMITS.maxImages * 2) return { error: "too_many_images" };
  if (!messages.length || messages[messages.length - 1].role !== "user") return { error: "bad_request" };
  return {
    install, platform, messages,
    app: typeof body.app === "string" ? body.app.slice(0, 40) : "",
    language: typeof body.language === "string" ? body.language.slice(0, 16) : "",
    // Cihaz bilgileri modele gönderilmez; yalnız yardımcının açtığı bildirime eklenir.
    device: typeof body.device === "string" ? body.device : "",
  };
}

// ---- Modeller ----

async function askAnthropic(env, model, system, messages) {
  const client = new Anthropic({ apiKey: env.ANTHROPIC_API_KEY });
  const response = await client.messages.create({
    model,
    max_tokens: 2000,
    // Bilgi tabanı sabit kalır ve önbelleğe alınır; her soruda yeniden ücretlendirilmez.
    system: [
      { type: "text", text: `NINO KNOWLEDGE:\n\n${KNOWLEDGE}`, cache_control: { type: "ephemeral", ttl: "1h" } },
      { type: "text", text: system },
    ],
    messages: messages.map((m) => ({
      role: m.role,
      content: [
        ...m.images.map((image) => ({ type: "image", source: { type: "base64", media_type: image.mime, data: image.data } })),
        { type: "text", text: m.text || "(screenshot)" },
      ],
    })),
    output_config: { effort: "medium", format: { type: "json_schema", schema: REPLY_SCHEMA } },
  });
  const cost = usageCost(model, response.usage);
  if (response.stop_reason === "refusal") return { reply: "", report: null, refused: true, cost };
  const text = response.content.filter((block) => block.type === "text").map((block) => block.text).join("");
  return { ...JSON.parse(text), cost };
}

async function askGemini(env, model, system, messages, fetcher) {
  const response = await fetcher(`https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:generateContent`, {
    method: "POST",
    headers: { "content-type": "application/json", "x-goog-api-key": env.GEMINI_API_KEY },
    body: JSON.stringify({
      systemInstruction: { parts: [{ text: `NINO KNOWLEDGE:\n\n${KNOWLEDGE}\n\n${system}` }] },
      contents: messages.map((m) => ({
        role: m.role === "assistant" ? "model" : "user",
        parts: [...m.images.map((image) => ({ inlineData: { mimeType: image.mime, data: image.data } })), { text: m.text || "(screenshot)" }],
      })),
      generationConfig: {
        maxOutputTokens: 1500,
        responseMimeType: "application/json",
        responseSchema: {
          type: "OBJECT",
          properties: { reply: { type: "STRING" }, report: { type: "OBJECT", nullable: true, properties: { kind: { type: "STRING", enum: ["bug", "unsolved", "request"] }, summary: { type: "STRING" } } } },
          required: ["reply"],
        },
      },
    }),
  });
  if (!response.ok) throw await failed(response, "gemini");
  const data = await response.json();
  const text = data?.candidates?.[0]?.content?.parts?.map((p) => p.text ?? "").join("") ?? "";
  return JSON.parse(text);
}

async function askDeepSeek(env, model, system, messages, fetcher) {
  // DeepSeek resim göremez: ekran görüntüsü yalnız "gönderildi" diye belirtilir.
  const response = await fetcher("https://api.deepseek.com/chat/completions", {
    method: "POST",
    headers: { "content-type": "application/json", authorization: `Bearer ${env.DEEPSEEK_API_KEY}` },
    body: JSON.stringify({
      model,
      max_tokens: 1500,
      response_format: { type: "json_object" },
      messages: [
        { role: "system", content: `NINO KNOWLEDGE:\n\n${KNOWLEDGE}\n\n${system}` },
        ...messages.map((m) => ({
          role: m.role,
          content: (m.images.length ? `[The user attached ${m.images.length} screenshot(s) you cannot see; ask them to describe it.]\n` : "") + (m.text || ""),
        })),
      ],
    }),
  });
  if (!response.ok) throw await failed(response, "deepseek");
  const data = await response.json();
  return JSON.parse(data?.choices?.[0]?.message?.content ?? "");
}

/** OpenRouter'ın sırayla denediği modeller: seçili model, sonra ASSISTANT_MODEL_ALTERNATIVES (meşgulse kendisi geçer). */
export function openRouterModels(env, model) {
  const extra = String(env.ASSISTANT_MODEL_ALTERNATIVES ?? "").split(",").map((m) => m.trim()).filter(Boolean);
  return [...new Set([model, ...extra])].slice(0, 3);
}

async function askOpenRouter(env, model, system, messages, fetcher) {
  const models = openRouterModels(env, model);
  const response = await fetcher("https://openrouter.ai/api/v1/chat/completions", {
    method: "POST",
    headers: { "content-type": "application/json", authorization: `Bearer ${env.OPENROUTER_API_KEY}`, "x-title": "Nino" },
    body: JSON.stringify({
      model,
      // Model meşgulse (429) ya da hata verirse OpenRouter aynı istekte sıradakine geçer.
      ...(models.length > 1 ? { models } : {}),
      max_tokens: 1500,
      // Bilgi tabanı en başta ve hep aynı: sağlayıcının önbelleği (ucuz okuma) tutar.
      messages: [
        // Bilgi tabanı ayrı ve önbellek işaretli parça: her istekte aynı kalır, sağlayıcı önbellekten ucuza okur
        // (Gemini 2.5 ayrıca örtük önbellek tutar). Dil, platform ve ipucu ikinci parçada.
        { role: "system", content: [
          { type: "text", text: `NINO KNOWLEDGE:\n\n${KNOWLEDGE}`, cache_control: { type: "ephemeral" } },
          { type: "text", text: system },
        ] },
        ...messages.map((m) => ({
          role: m.role,
          content: m.role === "user" && m.images.length
            ? [...m.images.map((image) => ({ type: "image_url", image_url: { url: `data:${image.mime};base64,${image.data}` } })), { type: "text", text: m.text || "(screenshot)" }]
            : m.text || "",
        })),
      ],
      // Çeviri zincirinde (src/free.js) canlıda denenmiş biçim: json_object + usage + düşük akıl yürütme.
      response_format: { type: "json_object" },
      // Cevapla birlikte gerçek maliyet (usage.cost, dolar) gelir.
      usage: { include: true },
      reasoning: { effort: "low" },
    }),
  });
  if (!response.ok) throw await failed(response, "openrouter");
  const data = await response.json();
  const usd = Number(data?.usage?.cost);
  const cost = Number.isFinite(usd) && usd >= 0 ? Math.ceil(usd * 1_000_000) : OPENROUTER_DEFAULT_MICRO_USD;
  try {
    return { ...JSON.parse(data?.choices?.[0]?.message?.content ?? ""), cost };
  } catch {
    const error = new Error("openrouter bad json");
    error.cost = cost;
    throw error;
  }
}

/**
 * Bir modele sorar. Döner: { reply, report: null | { kind, summary }, cost? }. `target` verilmezse ana model.
 * Testlerde handleAssistant'a `ask` verilerek değiştirilir.
 */
export async function askModel(env, system, messages, fetcher = fetch, target = null) {
  const provider = target?.provider ?? env.ASSISTANT_PROVIDER;
  const model = target?.model || (target ? DEFAULT_MODELS[provider] : env.ASSISTANT_MODEL || DEFAULT_MODELS[provider]);
  if (provider === "anthropic") return askAnthropic(env, model, system, messages);
  if (provider === "gemini") return askGemini(env, model, system, messages, fetcher);
  if (provider === "deepseek") return askDeepSeek(env, model, system, messages, fetcher);
  if (provider === "openrouter") return askOpenRouter(env, model, system, messages, fetcher);
  throw new Error("no provider");
}

/** Ana ve yedek model (anahtarı tanımlı olanlar), sırayla. */
export function assistantModels(env) {
  const out = [];
  const primary = env.ASSISTANT_PROVIDER;
  if (primary && env[KEYS[primary]]) {
    out.push({ role: "primary", provider: primary, model: env.ASSISTANT_MODEL || DEFAULT_MODELS[primary] });
  }
  const fallback = env.ASSISTANT_FALLBACK;
  if (fallback && fallback !== "0" && env[KEYS[fallback]]) {
    out.push({ role: "fallback", provider: fallback, model: env.ASSISTANT_FALLBACK_MODEL || DEFAULT_MODELS[fallback] });
  }
  return out;
}

export function assistantEnabled(env) {
  return assistantModels(env).length > 0;
}

/** POST /v1/assistant. Döner: { status, body, retryAfter? }. */
/** Sunucudaki gerçek çağrı: (env, sistem, mesajlar, hedef model, zaman aşımlı fetch). */
const defaultAsk = (env, system, messages, target, fetcher) => askModel(env, system, messages, fetcher, target);

export async function handleAssistant(db, env, body, now, ask = defaultAsk) {
  if (!assistantEnabled(env)) return { status: 503, body: { ok: false, error: "assistant_disabled" } };
  const input = validateConversation(body);
  if (input.error) return { status: input.status ?? 400, body: { ok: false, error: input.error } };

  const day = Math.floor(now / 86400);
  const install = await saltedDigest(input.install, env.INSTALL_SALT ?? "");
  const perInstall = Number(env.ASSISTANT_PER_INSTALL ?? ASSISTANT_LIMITS.perInstallPerDay);
  const budget = Number(env.ASSISTANT_DAILY_BUDGET ?? ASSISTANT_LIMITS.dailyBudget);
  const mine = await db.prepare("SELECT count FROM assistant_usage WHERE install = ? AND day = ?").bind(install, day).first("count");
  if ((mine ?? 0) >= perInstall) return { status: 429, body: { ok: false, error: "rate_limited" }, retryAfter: 3600 };
  // Günlük toplam istek sınırı yalnız model çağrılarını durdurur; hazır cevaplar yine verilir.
  const total = await db.prepare("SELECT COALESCE(SUM(count), 0) AS n FROM assistant_usage WHERE day = ?").bind(day).first("n");
  const overBudget = (total ?? 0) >= budget;
  await db.prepare("INSERT INTO assistant_usage (install, day, count) VALUES (?, ?, 1) ON CONFLICT(install, day) DO UPDATE SET count = count + 1")
    .bind(install, day).run();

  // 1) Hazır cevap kütüphanesi: kısa ve açık soruya model çağırmadan (ücretsiz) verilir.
  const match = matchAnswer(LIBRARY, input);
  if (match?.direct) {
    await count(db, now, "ask:library", 1);
    await count(db, now, `ask:topic:${match.id}`, 1);
    return { status: 200, body: { ok: true, reply: match.reply, report: null } };
  }

  // 2) Aynı ilk soru daha önce sorulduysa kayıtlı cevap (ücretsiz).
  const key = await answerKey(input);
  if (key) {
    const saved = await db.prepare("SELECT reply FROM assistant_answers WHERE key = ? AND created > ?")
      .bind(key, now - ASSISTANT_LIMITS.answerDays * 86400).first("reply");
    if (saved) {
      await db.prepare("UPDATE assistant_answers SET hits = hits + 1 WHERE key = ?").bind(key).run();
      await count(db, now, "ask:cache", 1);
      return { status: 200, body: { ok: true, reply: saved, report: null } };
    }
  }

  // 3–4) Ana model, sonra yedek model; her birinin kendi günlük sınırı var.
  const system = systemText(input.language, input.platform, match?.reply ?? null);
  if (match) await count(db, now, "ask:hinted", 1);
  let answer = null;
  let errored = false;
  for (const target of overBudget ? [] : assistantModels(env)) {
    if (!(await modelAvailable(db, env, target, day, now))) continue;
    const timeout = target.role === "primary" ? ASSISTANT_LIMITS.primaryTimeoutMs : ASSISTANT_LIMITS.fallbackTimeoutMs;
    try {
      answer = await ask(env, system, input.messages, target, withTimeout(fetch, timeout));
    } catch (error) {
      // Ana model hata verdiyse 502; ana model sınırdayken yedeğin hatası bugünkü gibi "yoğunum" (429).
      if (target.role === "primary") errored = true;
      console.error("yardımcı hatası", target.provider, String(error?.message ?? error).slice(0, 400));
      // Hata cevabı (HTTP hatası) OpenRouter'da ücret yazmaz; bozuk cevabın ücreti error.cost'ta gelir.
      await chargeModel(db, env, target, day, now, error?.cost ?? (target.role === "fallback" ? 0 : undefined));
      await count(db, now, `ask:err:${target.role}`, 1);
      if (error instanceof QuotaError) {
        // OpenRouter'ın 429'u çoğu zaman sağlayıcının anlık sınırı: kısa bekleme. Gemini'nin günlük hakkı: uzun.
        const fallbackWait = realCost(target) ? ASSISTANT_LIMITS.shortPauseSeconds : ASSISTANT_LIMITS.pauseSeconds;
        const wait = error.retrySeconds ? Math.min(Math.max(Math.ceil(error.retrySeconds) + 1, 5), 86400) : fallbackWait;
        await db.prepare("INSERT INTO free_pause (id, until) VALUES (?1, ?2) ON CONFLICT(id) DO UPDATE SET until = ?2")
          .bind(pauseId(target), now + wait).run().catch(() => {});
      }
      continue;
    }
    await chargeModel(db, env, target, day, now, answer?.cost);
    await count(db, now, `ask:model:${target.role}`, 1);
    if (typeof answer?.reply === "string" && answer.reply.trim()) break;
    if (target.role === "primary") errored = true;
    answer = null;
  }

  if (!answer) {
    // Modeller dolu ya da hatalı: benzer bir hazır cevap varsa o; yoksa kullanıcının dilinde "şu an yoğunum" hazır
    // cevabı (en sık çözümler + Sorun Bildir). Uygulama hata göstermez, robot hiç takılmaz.
    if (match) {
      await count(db, now, "ask:library_busy", 1);
      return { status: 200, body: { ok: true, reply: match.reply, report: null } };
    }
    await count(db, now, errored ? "ask:failed" : "ask:busy", 1);
    return { status: 200, body: { ok: true, reply: busyReply(input), report: null } };
  }
  const reply = answer.reply.trim();

  let reportId = null;
  const summary = typeof answer?.report?.summary === "string" ? answer.report.summary.trim() : "";
  if (summary) {
    // Bildirim: modelin özeti, sohbetin metni ve sohbetteki son en çok 3 ekran görüntüsü.
    const transcript = input.messages.map((m) => `${m.role === "user" ? "Kullanıcı" : "Nino"}: ${maskSecrets(m.text)}${m.images.length ? ` [${m.images.length} ekran görüntüsü]` : ""}`).join("\n");
    const images = input.messages.flatMap((m) => m.images).slice(-3);
    const saved = await receiveReport(db, env, {
      v: 1, install: input.install, app: input.app, platform: input.platform, language: input.language, device: input.device,
      text: `[Yardımcı · ${KIND_LABELS[answer.report.kind] ?? "Sorun"}] ${maskSecrets(summary)}\n\n--- Sohbet ---\n${transcript}\nNino: ${maskSecrets(reply)}`.slice(0, 4000), images,
    }, now);
    if (saved.status === 200) reportId = saved.body.id;
  }
  if (key && !summary) {
    await db.prepare("INSERT INTO assistant_answers (key, reply, created) VALUES (?, ?, ?) ON CONFLICT(key) DO UPDATE SET reply = excluded.reply, created = excluded.created, hits = 0")
      .bind(key, reply, now).run();
  }
  return { status: 200, body: { ok: true, reply, report: reportId } };
}

const KIND_LABELS = { bug: "Hata", unsolved: "Çözülemedi", request: "İstek" };

const pauseId = (target) => `ask:${target.provider}:${target.model}`;

/** Gerçek maliyetini cevapta bildiren sağlayıcı (OpenRouter): harcama kendi sayacında, gerçek dolarla. */
const realCost = (target) => target.provider === "openrouter";
const usdCounter = (target) => (realCost(target) ? `ask:usd:${target.provider}` : "ask:usd:fallback");
const capUsd = (env, target) => Number(target.role === "primary"
  ? env.ASSISTANT_DAILY_USD ?? ASSISTANT_LIMITS.dailyUsd
  : env.ASSISTANT_FALLBACK_DAILY_USD ?? ASSISTANT_LIMITS.fallbackDailyUsd);

/** Model bugün kullanılabilir mi: hak doldu beklemesinde değil, günlük sınırı dolmamış. */
async function modelAvailable(db, env, target, day, now) {
  const until = await db.prepare("SELECT until FROM free_pause WHERE id = ?").bind(pauseId(target)).first("until").catch(() => null);
  if (until && until > now) return false;
  if (target.role === "primary" && !realCost(target)) {
    // Masrafını bildirmeyen ana model (Gemini): istek başı tahminle sayılan harcama (assistant_cost).
    const spent = await db.prepare("SELECT micro_usd FROM assistant_cost WHERE day = ?").bind(day).first("micro_usd");
    return (spent ?? 0) < Math.round(capUsd(env, target) * 1_000_000);
  }
  // OpenRouter: cevaplardaki gerçek harcama, varsayılan 2 dolar.
  return (await counter(db, now, usdCounter(target))) < capUsd(env, target);
}

async function chargeModel(db, env, target, day, now, cost) {
  if (target.role === "primary" && !realCost(target)) {
    await addCost(db, day, Number.isFinite(cost) ? cost : FALLBACK_REQUEST_MICRO_USD);
    return;
  }
  const micro = Number.isFinite(cost) ? cost : OPENROUTER_DEFAULT_MICRO_USD;
  await count(db, now, usdCounter(target), micro / 1_000_000);
}

// Günlük sayaçlar free_usage tablosunda "ask:" önekiyle (yeni tablo gerekmez; gün UTC 'YYYY-MM-DD').
const dayText = (now) => new Date(now * 1000).toISOString().slice(0, 10);

async function count(db, now, id, n) {
  await db.prepare(`INSERT INTO free_usage (day, id, units) VALUES (?1, ?2, ?3)
                    ON CONFLICT(day, id) DO UPDATE SET units = units + excluded.units`).bind(dayText(now), id, n).run().catch(() => {});
}

async function counter(db, now, id) {
  return (await db.prepare("SELECT units FROM free_usage WHERE day = ? AND id = ?").bind(dayText(now), id).first("units").catch(() => 0)) ?? 0;
}

/** Panel için bugünün yardımcı özeti: kaç cevap nereden geldi, ne harcandı. */
export async function assistantStats(db, env, now) {
  const rows = (await db.prepare("SELECT id, units FROM free_usage WHERE day = ? AND id LIKE 'ask:%'").bind(dayText(now)).all().catch(() => null))?.results ?? [];
  const get = (id) => rows.find((r) => r.id === id)?.units ?? 0;
  const spent = await db.prepare("SELECT micro_usd FROM assistant_cost WHERE day = ?").bind(Math.floor(now / 86400)).first("micro_usd");
  const library = get("ask:library");
  const cache = get("ask:cache");
  const primary = get("ask:model:primary");
  const fallback = get("ask:model:fallback");
  const busyLibrary = get("ask:library_busy");
  const busy = get("ask:busy") + get("ask:failed");
  const answered = library + cache + primary + fallback + busyLibrary;
  const models = assistantModels(env);
  const primaryTarget = models.find((m) => m.role === "primary");
  const fallbackTarget = models.find((m) => m.role === "fallback");
  return {
    library, cache, primary, fallback, busyLibrary, busy,
    hinted: get("ask:hinted"),
    errors: { primary: get("ask:err:primary"), fallback: get("ask:err:fallback") },
    // Hazır cevap oranı: modelsiz verilen cevaplar / bütün verilen cevaplar.
    readyRate: answered ? (library + cache + busyLibrary) / answered : 0,
    // Ana model OpenRouter ise gerçek harcama, Gemini ise sayılan harcama.
    primaryUsd: primaryTarget && realCost(primaryTarget) ? get(usdCounter(primaryTarget)) : (spent ?? 0) / 1e6,
    primaryCapUsd: Number(env.ASSISTANT_DAILY_USD ?? ASSISTANT_LIMITS.dailyUsd),
    fallbackUsd: fallbackTarget ? get(usdCounter(fallbackTarget)) : 0,
    fallbackCapUsd: Number(env.ASSISTANT_FALLBACK_DAILY_USD ?? ASSISTANT_LIMITS.fallbackDailyUsd),
    primaryModel: primaryTarget?.model ?? "",
    fallbackModel: fallbackTarget?.model ?? "",
    topics: rows.filter((r) => r.id.startsWith("ask:topic:")).map((r) => ({ id: r.id.slice(10), n: r.units }))
      .sort((a, b) => b.n - a.n).slice(0, 8),
  };
}

async function addCost(db, day, micro) {
  await db.prepare("INSERT INTO assistant_cost (day, micro_usd) VALUES (?, ?) ON CONFLICT(day) DO UPDATE SET micro_usd = micro_usd + excluded.micro_usd")
    .bind(day, Math.max(0, Math.round(micro))).run();
}
