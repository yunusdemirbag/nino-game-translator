// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
//
// Nino: havuzun kendi çevirilerinden oyun paketleri.
//   GET  /v1/packs[?lang=tr]          → {"ok":true,"packs":[{id,title,version,sha256,size,entries,game,lang}]}
//   GET  /v1/packs/<id>[?lang=tr]     → gzip'li paket (application/gzip; ETag = sha256, If-None-Match → 304)
//   POST /v1/packs/build[?lang=tr]    → paketleri hemen yeniden üretir (Authorization: Bearer EXPORT_TOKEN)
//
// Paket gövdesi uygulamaların okuduğu eski biçimdir: {"format":1,"id","title","lang","entries":{anahtar:çeviri}}, gzip'li.
// Anahtar src/key.js'in satır anahtarıdır (havuzda translations.key olarak zaten bu hâliyle durur); İngilizce metin pakete
// girmez. Uygulamalar dil göndermez ve bu paketleri yalnız İngilizce → Türkçe çeviride kullanır: `lang` verilmezse 'tr'.
//
// Hangi satır pakete girer (pickRow ve ROWS_SQL):
//   1. Çeviri boş değil ve kullanılabilir (usable: ret/özür değil, makul uzunlukta).
//   2. Çeviri havuzun kendi çevirisi: hazır tohumdan gelenler (copy_of = 'seed') ve aslı bilinmeyen eski kopyalar
//      (copy_of = '?') girmez. Aslı bilinen bozuk kopyalar girer; metinleri aslının (gözden geçirilince güncellenen)
//      çevirisidir ve ekran okuması aynı yanlışı tekrar yaptığında işe yarar.
//   3. İngilizcesi çöp değil (junkReason: kırıntı, menü yazısı, bozuk okuma, Türkçe metin).
//   4. Satır o oyunda en az PACK_MIN_INSTALLS (varsayılan 2) ayrı kurulumda görüldü (lines.installs). Ekran okumasının
//      bozduğu satırı iki ayrı oyuncu nadiren aynı biçimde okur; bu, havuzdaki en güvenilir "gerçek altyazı" işaretidir.
//      tier'a bakılmaz: tier 2 gözden geçirilmiş demek değildir (izinsiz oyun/dilde ve çöpte para harcamadan da 2 yapılır).
//   5. Oyunu bilinmeyen satır (game = '') pakete girmez. Oyunda en az PACK_MIN_LINES (varsayılan 20) satır yoksa paket yok.
import { canonicalGame, gameName } from "./games.js";

import { canon } from "./key.js";
import { junkReason } from "./filter.js";
import { usable, LANGUAGES } from "./translate.js";

export const PACK_LIMITS = Object.freeze({
  partBytes: 1 << 20,          // D1 satırı ~2 MB'ı geçemez
  maxPackBytes: 64 << 20,      // uygulamanın kabul ettiği en büyük dosya
  maxPacks: 500,
  page: 5000,                  // üretimde bir sorguda okunan satır
  minInstalls: 2,
  minLines: 20,
});

export const PACK_ID = /^[a-z0-9][a-z0-9-]{0,63}$/;
const CONTROL = /[\u0000-\u001f\u007f]/gu;
const ROMAN = new Set(["ii", "iii", "iv", "v", "vi", "vii", "viii", "ix", "x", "xi", "xii", "xiii", "xiv", "xv", "xvi"]);

/** Havuzun oyun kimliğinden paket kimliği: `grand-theft-auto-vi` → `pool-grand-theft-auto-vi`; uymuyorsa null. */
export function packId(game) {
  const slug = String(game ?? "").toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+/, "").slice(0, 59).replace(/-+$/, "");
  if (!slug) return null;
  const id = `pool-${slug}`;
  return PACK_ID.test(id) ? id : null;
}

/** Oyun kimliğinden okunur ad: `grand-theft-auto-vi` → `Grand Theft Auto VI` (uygulama oyunu bu adla da eşler). */
export function packTitle(game) {
  return String(game).split(/[-._]+/).filter(Boolean)
    .map((w) => (ROMAN.has(w) ? w.toUpperCase() : w.charAt(0).toUpperCase() + w.slice(1))).join(" ");
}

function intVar(value, fallback, min = 1) {
  const n = Number.parseInt(value ?? "", 10);
  return Number.isFinite(n) && n >= min ? n : fallback;
}

function rules(env = {}) {
  return {
    minInstalls: intVar(env.PACK_MIN_INSTALLS, PACK_LIMITS.minInstalls),
    minLines: intVar(env.PACK_MIN_LINES, PACK_LIMITS.minLines),
  };
}

function packLang(value) {
  const lang = String(value ?? "tr").toLowerCase().split(/[-_]/)[0];
  return LANGUAGES[lang] ? lang : null;
}

/** Bir aday satır pakete girer mi; girerse temizlenmiş çeviri, girmezse null (kural 1-3; 4-5 sorguda). */
export function pickRow(row) {
  if (row.copy_of === "seed" || row.copy_of === "?") return null;
  const text = typeof row.text === "string" ? row.text.replace(CONTROL, " ").replace(/\s+/gu, " ").trim() : "";
  if (!text || !usable(row.source, text)) return null;
  if (junkReason(row.source)) return null;
  if (!canon(row.source)) return null;
  return text;
}

// Oyun ve anahtar sırasıyla, sayfa sayfa (lines'ın birincil anahtarı (game, key) bu sırayı ucuz verir).
const ROWS_SQL = `
  SELECT l.game, l.key, t.source, t.text, t.copy_of
  FROM lines l JOIN translations t ON t.key = l.key AND t.lang = ?1
  WHERE l.game <> '' AND l.installs >= ?2 AND t.text <> ''
    AND (l.game > ?3 OR (l.game = ?3 AND l.key > ?4))
  ORDER BY l.game, l.key LIMIT ?5`;

/** Pakete girecek satırlar, paket kimliğine göre: Map<id, {game, title, entries: Map<key, text>}>. */
export async function collectPacks(db, lang, env = {}) {
  const { minInstalls, minLines } = rules(env);
  const packs = new Map();
  let game = "", key = "";
  for (;;) {
    const { results } = await db.prepare(ROWS_SQL).bind(lang, minInstalls, game, key, PACK_LIMITS.page).all();
    for (const row of results) {
      // Takma adlı kimlikler (grand-theft-auto-vi) asıl oyunun (gta-6) paketine girer.
      const game = canonicalGame(String(row.game).toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, ""));
      const id = packId(game);
      const text = id ? pickRow(row) : null;
      if (!text) continue;
      let pack = packs.get(id);
      if (!pack) packs.set(id, (pack = { id, game, title: gameName(game) || packTitle(game), entries: new Map() }));
      // Aynı kimliğe düşen iki oyun (gta.vi / gta-vi) birleşir; aynı anahtarda ilk oyunun çevirisi kalır.
      if (!pack.entries.has(row.key)) pack.entries.set(row.key, text);
    }
    if (results.length < PACK_LIMITS.page) break;
    const last = results[results.length - 1];
    game = last.game;
    key = last.key;
  }
  for (const [id, pack] of packs) if (pack.entries.size < minLines) packs.delete(id);
  // En büyük paketler önce; sınırı aşan küçükler bırakılır.
  return new Map([...packs].sort((a, b) => b[1].entries.size - a[1].entries.size || (a[0] < b[0] ? -1 : 1))
    .slice(0, PACK_LIMITS.maxPacks));
}

/** Paket dosyasının JSON metni (anahtarlar sıralı: aynı içerik hep aynı metin). */
export function packJSON(pack, lang) {
  const entries = {};
  for (const k of [...pack.entries.keys()].sort()) entries[k] = pack.entries.get(k);
  return JSON.stringify({ format: 1, id: pack.id, title: pack.title, lang, entries });
}

export async function gzip(text) {
  const stream = new Blob([new TextEncoder().encode(text)]).stream().pipeThrough(new CompressionStream("gzip"));
  return new Uint8Array(await new Response(stream).arrayBuffer());
}

export async function sha256Hex(data) {
  const bytes = typeof data === "string" ? new TextEncoder().encode(data) : data;
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest), (b) => b.toString(16).padStart(2, "0")).join("");
}

/**
 * Bir dilin paketlerini üretir ve saklar. İçeriği değişmeyen pakete dokunulmaz (sürümü ve sha'sı aynı kalır);
 * artık kurala uymayan paket listeden kalkar (uygulama indirdiği kopyayı siler). Sorgu hata verirse hiçbir şey
 * silinmez (hata yukarı gider). Dönüş: { lang, packs, changed, removed, entries }.
 */
export async function buildPacks(db, env, now, lang = "tr") {
  if (!packLang(lang)) throw new Error(`bilinmeyen dil: ${lang}`);
  const built = await collectPacks(db, lang, env);
  const { results: stored } = await db.prepare("SELECT id, content FROM packs WHERE lang = ?").bind(lang).all();
  const previous = new Map(stored.map((r) => [r.id, r.content]));
  let changed = 0, entries = 0;
  for (const pack of built.values()) {
    entries += pack.entries.size;
    const json = packJSON(pack, lang);
    const content = await sha256Hex(json);
    if (previous.get(pack.id) === content) {
      await db.prepare("UPDATE packs SET built = ? WHERE lang = ? AND id = ?").bind(now, lang, pack.id).run();
      continue;
    }
    const file = await gzip(json);
    if (file.byteLength > PACK_LIMITS.maxPackBytes) continue;
    const sha = await sha256Hex(file);
    const parts = [];
    for (let i = 0; i < file.byteLength; i += PACK_LIMITS.partBytes) parts.push(file.slice(i, i + PACK_LIMITS.partBytes));
    // Parçalar ve liste satırı tek işlemde: yarım yazılmış paket listede görünmez.
    await db.batch([
      db.prepare("DELETE FROM pack_parts WHERE lang = ? AND id = ?").bind(lang, pack.id),
      ...parts.map((data, part) => db.prepare("INSERT INTO pack_parts (lang, id, part, data) VALUES (?, ?, ?, ?)")
        .bind(lang, pack.id, part, data)),
      db.prepare(
        `INSERT INTO packs (lang, id, game, title, version, sha256, content, entries, bytes, parts, built)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?5)
         ON CONFLICT (lang, id) DO UPDATE SET game = ?3, title = ?4,
           version = MAX(?5, packs.version + 1), sha256 = ?6, content = ?7, entries = ?8, bytes = ?9, parts = ?10, built = ?5`,
      ).bind(lang, pack.id, pack.game, pack.title, now, sha, content, pack.entries.size, file.byteLength, parts.length),
    ]);
    changed++;
  }
  const gone = [...previous.keys()].filter((id) => !built.has(id));
  for (const id of gone) {
    await db.batch([
      db.prepare("DELETE FROM pack_parts WHERE lang = ? AND id = ?").bind(lang, id),
      db.prepare("DELETE FROM packs WHERE lang = ? AND id = ?").bind(lang, id),
    ]);
  }
  return { lang, packs: built.size, changed, removed: gone.length, entries };
}

/** Zamanlanmış üretim (günde bir): PACK_LANGS (varsayılan "tr") dilleri; PACK_ENABLED = "0" ise hiç. */
export async function buildScheduled(db, env, now) {
  if (env.PACK_ENABLED === "0") return [];
  const langs = String(env.PACK_LANGS ?? "tr").split(",").map((s) => s.trim()).filter((l) => packLang(l) === l);
  const out = [];
  for (const lang of langs) out.push(await buildPacks(db, env, now, lang));
  return out;
}

export async function listPacks(db, lang) {
  const { results } = await db.prepare(
    `SELECT id, title, version, sha256, bytes, entries, game FROM packs WHERE lang = ? ORDER BY id LIMIT ${PACK_LIMITS.maxPacks}`,
  ).bind(lang).all();
  return results.map((r) => ({ id: r.id, title: r.title, version: r.version, sha256: r.sha256, size: r.bytes,
    entries: r.entries, game: r.game, lang }));
}

/** Saklanan gzip'li dosya; yoksa null. */
export async function readPack(db, lang, id) {
  const head = await db.prepare("SELECT sha256, bytes, parts FROM packs WHERE lang = ? AND id = ?").bind(lang, id).first();
  if (!head) return null;
  const { results } = await db.prepare("SELECT part, data FROM pack_parts WHERE lang = ? AND id = ? ORDER BY part")
    .bind(lang, id).all();
  if (results.length !== head.parts) return null;
  const out = new Uint8Array(head.bytes);
  let offset = 0;
  for (const r of results) {
    // D1 BLOB'u sayı dizisi ya da ArrayBuffer olarak verebilir; Node'un SQLite'ı Uint8Array.
    const bytes = r.data instanceof Uint8Array ? r.data : new Uint8Array(r.data);
    if (offset + bytes.byteLength > out.byteLength) return null;
    out.set(bytes, offset);
    offset += bytes.byteLength;
  }
  return offset === head.bytes ? { data: out, sha256: head.sha256 } : null;
}

function json(status, body, headers = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store", ...headers },
  });
}

/** `/v1/packs` ve `/v1/packs/...` istekleri. `authorized`: yönetici anahtarı doğru mu (worker.js denetler). */
export async function handlePacks(request, env, url, path, authorized, now = Math.floor(Date.now() / 1000)) {
  const lang = packLang(url.searchParams.get("lang") ?? "tr");
  if (!lang) return json(400, { ok: false, error: "bad_lang" });

  if (path === "/v1/packs/build") {
    if (request.method !== "POST") return json(405, { ok: false, error: "method" });
    if (!env.EXPORT_TOKEN) return json(503, { ok: false, error: "export_disabled" });
    if (!authorized) return json(401, { ok: false, error: "unauthorized" });
    return json(200, { ok: true, ...(await buildPacks(env.DB, env, now, lang)) });
  }
  if (request.method !== "GET" && request.method !== "HEAD") return json(405, { ok: false, error: "method" });

  // Liste: veritabanı hatası 5xx olarak gider (boş liste değil), yoksa uygulama indirdiği paketleri silerdi.
  if (path === "/v1/packs") {
    return json(200, { ok: true, packs: await listPacks(env.DB, lang) }, { "cache-control": "public, max-age=300" });
  }

  const id = path.slice("/v1/packs/".length);
  if (!PACK_ID.test(id)) return json(400, { ok: false, error: "bad_id" });
  const pack = await readPack(env.DB, lang, id);
  if (!pack) return json(404, { ok: false, error: "not_found" });
  const etag = `"${pack.sha256}"`;
  const common = { etag, "x-pack-sha256": pack.sha256, "cache-control": "public, max-age=300" };
  if ((request.headers.get("if-none-match") ?? "").split(",").map((s) => s.trim()).includes(etag)) {
    return new Response(null, { status: 304, headers: common });
  }
  // Content-Encoding yok: dosyanın kendisi gzip'tir; aksi hâlde istemci açılmış hâlini alır ve sha tutmaz.
  return new Response(request.method === "HEAD" ? null : pack.data, {
    headers: { ...common, "content-type": "application/gzip", "content-length": String(pack.data.byteLength),
      "content-disposition": `attachment; filename="${id}.json.gz"` },
  });
}
