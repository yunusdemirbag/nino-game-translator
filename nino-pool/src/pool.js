// SPDX-License-Identifier: AGPL-3.0-only
// Havuzun iş kuralları. Veritabanı D1 arayüzüyle verilir (prepare/bind/run/all/first, batch); testlerde aynı arayüz
// Node'un yerleşik SQLite'ı üzerinde çalışır.

import { checkBatch, checkLine, RequestError } from "./validate.js";
import { lineKey, saltedDigest } from "./key.js";

export const BATCH_RETENTION_DAYS = 30;

function day(now) {
  return new Date(now * 1000).toISOString().slice(0, 10);
}

function secondsUntilNextDay(now) {
  return 86400 - (now % 86400);
}

function intVar(value, fallback) {
  const n = Number.parseInt(value ?? "", 10);
  return Number.isFinite(n) && n > 0 ? n : fallback;
}

/**
 * Bir parçayı işler. Dönen { status, body, retryAfter? }.
 * - Aynı parça kimliği ikinci kez gelirse hiçbir şey yeniden sayılmaz, yine 200 döner (istemci kuyruğundan siler).
 * - Geçersiz satırlar `rejected` içinde sırasıyla bildirilir; geçerliler yazılır.
 * - Sınır aşılırsa 429 + Retry-After: istemci parçayı saklar, sonra yeniden dener.
 */
export async function receiveBatch(db, env, raw, now) {
  let meta;
  try {
    meta = checkBatch(raw);
  } catch (error) {
    if (error instanceof RequestError) return { status: error.status, body: { ok: false, error: error.code } };
    throw error;
  }
  const install = await saltedDigest(meta.install, env.INSTALL_SALT ?? "");

  const done = await db.prepare("SELECT lines FROM batches WHERE id = ?").bind(meta.batch).first();
  if (done) return { status: 200, body: { ok: true, batch: meta.batch, duplicate: true, accepted: done.lines, rejected: [] } };

  const hourly = intVar(env.INSTALL_HOURLY_BATCHES, 60);
  const recent = await db
    .prepare("SELECT COUNT(*) AS n FROM batches WHERE install = ? AND received_at > ?")
    .bind(install, now - 3600)
    .first();
  if ((recent?.n ?? 0) >= hourly) {
    return { status: 429, retryAfter: 900, body: { ok: false, error: "install_rate" } };
  }

  // Satırlar: geçersizler ayıklanır, anahtarlar sunucuda hesaplanır, aynı (oyun, anahtar, oturum) birleşir.
  const rejected = [];
  const merged = new Map();
  for (let i = 0; i < meta.lines.length; i++) {
    const line = checkLine(meta.lines[i], now);
    if (line.reject) {
      rejected.push({ i, reason: line.reject });
      continue;
    }
    const key = await lineKey(line.text);
    if (!key) {
      rejected.push({ i, reason: "no_letters" });
      continue;
    }
    const id = `${line.game}\u0000${key}\u0000${line.session ?? ""}\u0000${line.text}`;
    const prev = merged.get(id);
    if (prev) {
      prev.n += line.count;
      prev.f = Math.min(prev.f, line.first);
      prev.l = Math.max(prev.l, line.last);
    } else {
      merged.set(id, { g: line.game, k: key, t: line.text, s: line.session, n: line.count, f: line.first, l: line.last });
    }
  }
  const rows = [...merged.values()];
  const accepted = meta.lines.length - rejected.length;

  const budget = intVar(env.DAILY_LINE_BUDGET, 15000);
  const today = day(now);
  const used = await db.prepare("SELECT lines FROM usage WHERE day = ?").bind(today).first();
  if ((used?.lines ?? 0) + accepted > budget && (used?.lines ?? 0) > 0) {
    return { status: 429, retryAfter: secondsUntilNextDay(now), body: { ok: false, error: "daily_budget" } };
  }

  const json = JSON.stringify(rows);
  const statements = [
    // İlk sırada: aynı parça aynı anda iki kez gelirse ikincisi burada takılır ve tümü geri alınır.
    db.prepare("INSERT INTO batches (id, install, received_at, lines) VALUES (?, ?, ?, ?)").bind(meta.batch, install, now, accepted),
    db
      .prepare(
        `INSERT INTO usage (day, lines, batches) VALUES (?, ?, 1)
         ON CONFLICT (day) DO UPDATE SET lines = lines + excluded.lines, batches = batches + 1`,
      )
      .bind(today, accepted),
  ];
  if (rows.length > 0) {
    const src = `SELECT json_extract(value, '$.g') AS g, json_extract(value, '$.k') AS k, json_extract(value, '$.t') AS t,
                        json_extract(value, '$.s') AS s, json_extract(value, '$.n') AS n, json_extract(value, '$.f') AS f,
                        json_extract(value, '$.l') AS l
                 FROM json_each(?)`;
    statements.push(
      db
        .prepare(
          `INSERT INTO lines (game, key, text, seen, installs, first_seen, last_seen)
           SELECT g, k, t, n, 0, f, l FROM (${src}) WHERE true
           ON CONFLICT (game, key) DO UPDATE SET
             seen = seen + excluded.seen,
             first_seen = min(first_seen, excluded.first_seen),
             last_seen = max(last_seen, excluded.last_seen)`,
        )
        .bind(json),
      db.prepare(`INSERT OR IGNORE INTO line_installs (game, key, install) SELECT g, k, ? FROM (${src})`).bind(install, json),
      db
        .prepare(
          `UPDATE lines SET installs = (SELECT COUNT(*) FROM line_installs li WHERE li.game = lines.game AND li.key = lines.key)
           WHERE (game, key) IN (SELECT g, k FROM (${src}))`,
        )
        .bind(json),
      db
        .prepare(
          `INSERT INTO line_texts (key, text, seen) SELECT k, t, n FROM (${src}) WHERE true
           ON CONFLICT (key, text) DO UPDATE SET seen = seen + excluded.seen`,
        )
        .bind(json),
      db
        .prepare(`INSERT OR IGNORE INTO line_sessions (session, key) SELECT s, k FROM (${src}) WHERE g = '' AND s IS NOT NULL`)
        .bind(json),
      db
        .prepare(
          `INSERT INTO sessions (session, game, lines, first_seen, last_seen)
           SELECT s, g, COUNT(*), MIN(f), MAX(l) FROM (${src}) WHERE s IS NOT NULL GROUP BY s, g
           ON CONFLICT (session, game) DO UPDATE SET
             lines = lines + excluded.lines,
             first_seen = min(first_seen, excluded.first_seen),
             last_seen = max(last_seen, excluded.last_seen)`,
        )
        .bind(json),
    );
  }

  try {
    await db.batch(statements);
  } catch (error) {
    // Aynı parça başka bir istekte az önce yazıldıysa: zaten sayıldı.
    if (/UNIQUE|PRIMARY KEY|constraint/i.test(String(error?.message ?? error))) {
      const again = await db.prepare("SELECT lines FROM batches WHERE id = ?").bind(meta.batch).first();
      if (again) return { status: 200, body: { ok: true, batch: meta.batch, duplicate: true, accepted: again.lines, rejected: [] } };
    }
    throw error;
  }
  return { status: 200, body: { ok: true, batch: meta.batch, duplicate: false, accepted, rejected } };
}

/** Oyunlar ve satır sayıları (dışa aktarma için). game = '' bilinmeyen oyun. */
export async function listGames(db) {
  const { results } = await db
    .prepare(
      `SELECT game, COUNT(*) AS lines, SUM(seen) AS seen, MAX(last_seen) AS last_seen
       FROM lines GROUP BY game ORDER BY lines DESC`,
    )
    .all();
  return results;
}

/**
 * Bir oyunun satırları, paket hazırlamak için. Sayfalı: `after` bir önceki sayfanın `next` değeri.
 * Her satırda en çok görülen yazılış, toplam görülme, ayrı kurulum sayısı, ilk/son görülme.
 * `session` verilirse (yalnız bilinmeyen oyunda) o oturumda görülen satırlar.
 */
export async function exportLines(db, { game = "", after = "", limit = 1000, minInstalls = 1, session = null } = {}) {
  limit = Math.min(Math.max(Number.parseInt(limit, 10) || 1000, 1), 5000);
  minInstalls = Math.max(Number.parseInt(minInstalls, 10) || 1, 1);
  const join = session ? "JOIN line_sessions ls ON ls.key = l.key AND ls.session = ?" : "";
  const params = session ? [session, game, after, minInstalls, limit] : [game, after, minInstalls, limit];
  const { results } = await db
    .prepare(
      `SELECT l.key, l.seen, l.installs, l.first_seen, l.last_seen,
              COALESCE((SELECT t.text FROM line_texts t WHERE t.key = l.key ORDER BY t.seen DESC, t.text LIMIT 1), l.text) AS text,
              (SELECT COUNT(*) FROM line_texts t WHERE t.key = l.key) AS variants
       FROM lines l ${join}
       WHERE l.game = ? AND l.key > ? AND l.installs >= ?
       ORDER BY l.key LIMIT ?`,
    )
    .bind(...params)
    .all();
  const next = results.length === limit ? results[results.length - 1].key : null;
  return { game, lines: results, next };
}

/** Oyunu bilinmeyen satırların oturumları: hangi oturumda kaç satır görüldü, o oturumda bilinen bir oyun ipucu var mı. */
export async function listUnknownSessions(db, { limit = 200 } = {}) {
  limit = Math.min(Math.max(Number.parseInt(limit, 10) || 200, 1), 1000);
  const { results } = await db
    .prepare(
      `SELECT s.session, s.lines, s.first_seen, s.last_seen,
              (SELECT k.game FROM sessions k WHERE k.session = s.session AND k.game <> '' ORDER BY k.lines DESC LIMIT 1) AS hint
       FROM sessions s WHERE s.game = '' ORDER BY s.last_seen DESC LIMIT ?`,
    )
    .bind(limit)
    .all();
  return results;
}

/** Günlük bakım: tekrar sayılmasın diye tutulan eski parça kimlikleri ve eski kullanım kayıtları silinir. */
export async function prune(db, now) {
  await db.batch([
    db.prepare("DELETE FROM batches WHERE received_at < ?").bind(now - BATCH_RETENTION_DAYS * 86400),
    db.prepare("DELETE FROM usage WHERE day < ?").bind(day(now - 90 * 86400)),
  ]);
}
