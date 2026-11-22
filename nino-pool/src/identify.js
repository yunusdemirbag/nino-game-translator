// SPDX-License-Identifier: AGPL-3.0-only
// Nino: oyunu ekrandan tanıma. PS5 çalışan oyunu bildirmiyor; hazır paketi olmayan yeni oyun (GTA 6) satırlardan da
// tanınamıyor. Uygulama Remote Play görüntüsünden küçük bir kare gönderir, Claude oyunun adını söyler. Tanınan oyun
// kuruluma yazılır; çeviri havuzu o oyunun satırlarını o adla toplar ve (izinliyse) Claude ile çevirir.
import { canonicalGame } from "./games.js";

import Anthropic from "@anthropic-ai/sdk";
import { saltedDigest } from "./key.js";
import { translateCost } from "./translate.js";

export const IDENTIFY_LIMITS = Object.freeze({
  maxBodyBytes: 600 * 1024,
  maxImageBytes: 450 * 1024,
  /** Kurulum başına günde en çok tanıma isteği (sunucu örneği içinde, kaba koruma). */
  perInstallDay: 30,
});
export const IDENTIFY_MODEL = "claude-sonnet-5-5";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const hits = new Map();

const SCHEMA = {
  type: "object",
  properties: {
    game: { type: ["string", "null"] },
    confidence: { type: "number" },
  },
  required: ["game", "confidence"],
  additionalProperties: false,
};

/** Oyun adından havuz kimliği ("Grand Theft Auto VI" → "grand-theft-auto-vi"); uygulamalardaki NinoPool.gameID ile aynı. */
export function gameId(name) {
  return String(name ?? "").toLowerCase().replace(/[^a-z0-9._-]+/g, "-").replace(/^[-._]+|[-._]+$/g, "").slice(0, 64);
}

export async function askIdentify(env, image, mime) {
  const client = new Anthropic({ apiKey: env.ANTHROPIC_API_KEY, timeout: 20_000, maxRetries: 0 });
  const response = await client.messages.create({
    model: IDENTIFY_MODEL,
    max_tokens: 200,
    thinking: { type: "between_tools" },
    system: "You identify video games from a single screenshot of a PlayStation 5 or Xbox stream (gameplay, HUD, menus, map, loading or title screen). Answer with the exact official title as sold (e.g. \"Grand Theft Auto VI\", \"Mafia: The Old Country\"). If the picture is the console's home screen or a system menu, give the game only if its title is clearly shown as the selected or running game. Grand Theft Auto VI (2026, set in Leonida / Vice City, protagonists Jason and Lucia, pause menu with a pink \"VI\" logo and tabs JASON & LUCIA / MAP / BRIEF / PROGRESS) is a different game from Grand Theft Auto V (2013, Los Santos, Michael / Franklin / Trevor): a modern, photorealistic GTA scene in Florida-like swamps, beaches or Vice City is GTA VI, never GTA V. If you are not sure, return null. confidence is 0-1.",
    messages: [{
      role: "user",
      content: [
        { type: "image", source: { type: "base64", media_type: mime, data: image } },
        { type: "text", text: "Which game is this?" },
      ],
    }],
    output_config: { effort: "low", format: { type: "json_schema", schema: SCHEMA } },
  });
  const cost = translateCost(IDENTIFY_MODEL, response.usage);
  if (response.stop_reason !== "end_turn") return { game: null, confidence: 0, cost };
  const parsed = JSON.parse(response.content.filter((b) => b.type === "text").map((b) => b.text).join(""));
  return { game: typeof parsed.game === "string" ? parsed.game.slice(0, 120) : null, confidence: Number(parsed.confidence) || 0, cost };
}

/**
 * POST /v1/identify { v:1, install, platform, app, image: base64 jpeg/png }
 * → { ok, game: "Grand Theft Auto VI" | null, id: "grand-theft-auto-vi" | null, confidence }
 */
export async function handleIdentify(db, env, body, now, ask = askIdentify, addCost) {
  if (!body || body.v !== 1 || typeof body.install !== "string" || !UUID.test(body.install) || typeof body.image !== "string") {
    return { status: 400, body: { ok: false, error: "bad_request" } };
  }
  if (!env.ANTHROPIC_API_KEY || env.CLAUDE_ENABLED === "0" || env.TRANSLATE_ENABLED === "0") return { status: 503, body: { ok: false, error: "disabled" } };
  const bytes = Math.floor(body.image.length * 0.75);
  if (bytes > IDENTIFY_LIMITS.maxImageBytes) return { status: 413, body: { ok: false, error: "too_large" } };
  const mime = body.image.startsWith("iVBOR") ? "image/png" : "image/jpeg";
  const install = await saltedDigest(body.install.toLowerCase(), env.INSTALL_SALT ?? "");
  const day = Math.floor(now / 86400);
  const used = hits.get(install);
  const count = used && used[0] === day ? used[1] : 0;
  if (count >= IDENTIFY_LIMITS.perInstallDay) return { status: 429, body: { ok: false, error: "rate" } };
  hits.set(install, [day, count + 1]);
  if (hits.size > 5000) hits.clear();

  let answer = { game: null, confidence: 0, cost: 0 };
  try {
    answer = await ask(env, body.image, mime);
  } catch (error) {
    console.error("tanıma hatası", String(error?.message ?? error).slice(0, 200));
  }
  if (answer.cost && addCost) await addCost(db, now, answer.cost);
  let sure = answer.game && answer.confidence >= 0.7 ? answer.game : null;
  // GTA VI ekranı modelce bazen "Grand Theft Auto V" sanılıyor. Bu kurulum son saatlerde GTA VI satırlarıyla görüldüyse
  // (sunucu satırlardan tanıdı) GTA V cevabı GTA VI sayılır.
  if (sure && gameId(sure) === "grand-theft-auto-v") {
    const recent = await db.prepare("SELECT game, playing FROM installs WHERE install = ?").bind(install).first().catch(() => null);
    if (recent?.game && /^(grand-theft-auto-vi|gta-vi|gta-6|gta6)$/.test(recent.game) && now - (recent.playing ?? 0) < 6 * 3600) {
      sure = "Grand Theft Auto VI";
    }
  }
  const id = sure ? canonicalGame(gameId(sure)) : null;
  if (id) {
    // Bu kurulumun bundan sonraki satırları (oyun adı gelmese de) bu oyundan sayılır.
    await db.prepare(
      `INSERT INTO installs (install, platform, app, first_seen, last_seen, playing, game, lang) VALUES (?1, '', '', ?2, ?2, ?2, ?3, '')
       ON CONFLICT (install) DO UPDATE SET last_seen = ?2, playing = ?2, game = ?3`,
    ).bind(install, now, id).run().catch(() => {});
  }
  return { status: 200, body: { ok: true, game: sure, id, confidence: answer.confidence } };
}
