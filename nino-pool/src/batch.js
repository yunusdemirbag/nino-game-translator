// SPDX-License-Identifier: AGPL-3.0-only
// Nino: toplu ücretsiz çeviri (Nino'ın gece paketi gibi, ama yarım saatte bir). Anında çeviride hak dolduğu için
// cihazın kendi çevirisiyle geçilen satırlar havuzda İngilizce bekler; burada 50'şer satırlık partilerle ücretsiz
// servislere (önce Gemini) gönderilir. Ücretsiz servislerin sınırı istek sayısı olduğundan aynı hakla ~30 kat satır çevrilir.
// Önce birden çok oyuncunun gördüğü (gerçek, tekrar eden) satırlar. Uygulamalar yeni çevirileri birkaç dakikada çeker.

import { junkReason } from "./filter.js";
import { navTranslation } from "./nav.js";
import { askFree, freeChain } from "./free.js";
import { freeEnabled } from "./free.js";
import { indexBlocks } from "./translate.js";

export const BATCH_LIMITS = Object.freeze({
  /** Bir partide satır. */
  size: 50,
  /** Bir turda en çok parti (yarım saatte en çok 2.000 satır). */
  maxChunks: 40,
  /** Bir turun en uzun süresi (ms); zamanlanmış çalışma 15 dakikayla sınırlı. */
  maxMs: 8 * 60 * 1000,
  /** Bir partinin cevabı için bekleme (ms). */
  timeoutMs: 60_000,
});

/** Toplu çeviride kullanılacak servisler: BATCH_CHAIN ("servis:model" virgüllü) ya da zincirdeki Gemini modelleri. */
export function batchChain(env) {
  if (env.BATCH_CHAIN) return freeChain({ ...env, FREE_CHAIN: env.BATCH_CHAIN });
  return freeChain(env).filter((c) => c.provider === "gemini");
}

function gameFilter(env) {
  const parts = String(env.TRANSLATE_GAMES ?? "").split(",").map((g) => g.trim().toLowerCase()).filter(Boolean);
  if (parts.length === 0 || parts.includes("*")) return { sql: "1", args: [] };
  return { sql: `(${parts.map((_, i) => `instr(l.game, ?${i + 2}) > 0`).join(" OR ")})`, args: parts };
}

/**
 * Bir tur. Dönüş { translated, junk, chunks, failed, stopped? }. `ask` testlerde verilir.
 */
export async function batchTranslate(db, env, now, { ask = askFree, lang = "tr", clock = () => Date.now(), maxChunks = BATCH_LIMITS.maxChunks } = {}) {
  if (env.BATCH_TRANSLATE === "0" || !freeEnabled(env)) return { translated: 0, junk: 0, chunks: 0, failed: 0, stopped: "disabled" };
  const chain = batchChain(env);
  if (chain.length === 0) return { translated: 0, junk: 0, chunks: 0, failed: 0, stopped: "no_chain" };
  const started = clock();
  const games = gameFilter(env);
  const { results } = await db.prepare(
    `SELECT l.key, MIN(l.game) AS game, MIN(l.text) AS text, MAX(l.installs) AS installs, SUM(l.seen) AS seen
     FROM lines l
     WHERE ${games.sql} AND NOT EXISTS (SELECT 1 FROM translations t WHERE t.key = l.key AND t.lang = ?1)
     GROUP BY l.key ORDER BY installs DESC, seen DESC LIMIT ${BATCH_LIMITS.size * maxChunks}`,
  ).bind(lang, ...games.args).all();

  // Çöp ve yol tarifi: Gemini'ye gitmez; boş çeviriyle işaretlenir ki her turda yeniden seçilmesin.
  const todo = [];
  const junk = [];
  for (const r of results) {
    if (junkReason(r.text) || navTranslation(r.text, lang)) junk.push(r);
    else todo.push(r);
  }
  if (junk.length > 0) await write(db, lang, now, junk.map((r) => ({ k: r.key, g: r.game, s: r.text, t: "", r: 0 })));

  let translated = 0;
  let chunks = 0;
  let failed = 0;
  let stopped;
  for (let i = 0; i < todo.length; i += BATCH_LIMITS.size) {
    if (clock() - started > BATCH_LIMITS.maxMs) { stopped = "time"; break; }
    const part = todo.slice(i, i + BATCH_LIMITS.size);
    const answer = await ask(env, lang, part.map((r) => r.text), [], {
      db, now: Math.floor(clock() / 1000), chain, timeout: BATCH_LIMITS.timeoutMs, partial: true,
    });
    chunks++;
    if (!answer.texts) {
      failed++;
      // Bütün servisler doluysa bu tur biter (sonraki turda devam).
      if (failed >= 2) { stopped = "quota"; break; }
      continue;
    }
    const rows = part.map((r, j) => (answer.texts[j] ? { k: r.key, g: r.game, s: r.text, t: answer.texts[j].replace(/\s+/g, " ").trim(), r: 1 } : null))
      .filter(Boolean);
    await write(db, lang, now, rows);
    translated += rows.length;
  }
  return { translated, junk: junk.length, chunks, failed, ...(stopped ? { stopped } : {}) };
}

async function write(db, lang, now, rows) {
  if (rows.length === 0) return;
  await db.prepare(
    `INSERT OR IGNORE INTO translations (key, lang, game, source, text, tier, created, updated)
     SELECT json_extract(value, '$.k'), ?1, json_extract(value, '$.g'), json_extract(value, '$.s'), json_extract(value, '$.t'),
            json_extract(value, '$.r'), ?2, ?2
     FROM json_each(?3)`,
  ).bind(lang, now, JSON.stringify(rows)).run();
  await indexBlocks(db, lang, rows.filter((r) => r.t)).catch(() => {});
}
