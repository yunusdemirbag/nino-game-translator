// SPDX-License-Identifier: AGPL-3.0-only
// Oyun kimliklerinin tek adı. Aynı oyun uygulamalardan farklı kimliklerle gelebiliyor: eski sürümler havuz kimliğini
// oyunun tam adından üretiyor ("Grand Theft Auto VI" → "grand-theft-auto-vi"), paketler kısa adı kullanıyor ("gta-6"),
// ekrandan okuma bazen "gtavi" / "gta6" gibi yazılışlar veriyor. Sunucu her girişte kimliği tek ada çevirir; böylece
// satırlar, oturumlar ve çeviriler tek oyunda birikir. Eski uygulamalar eski kimliği göndermeye devam edebilir.

/** takma ad → asıl kimlik. Asıl kimlik, gömülü oyun paketinin kimliğiyle aynı (gta-6, gta-v…). */
export const GAME_ALIASES = Object.freeze({
  // GTA 6
  "grand-theft-auto-vi": "gta-6",
  "gta-vi": "gta-6",
  "gta6": "gta-6",
  "gtavi": "gta-6",
  "pool-gta-6": "gta-6",
  // GTA 5 (gömülü paket: gta-v)
  "grand-theft-auto-v": "gta-v",
  "gta-5": "gta-v",
  "gta5": "gta-v",
  "gtav": "gta-v",
  "pool-gta-5": "gta-v",
  "pool-gta-v": "gta-v",
  // Kesme işaretinin tire olduğu yazılışlar ve aynı oyunun uzun adları
  "assassin-s-creed-shadows": "assassins-creed-shadows",
  "marvel-s-spider-man-2": "marvels-spider-man-2",
  "death-stranding-director-s-cut": "death-stranding-directors-cut",
  "death-stranding-2-on-the-beach": "death-stranding-2",
  "farcry6": "far-cry-6",
  "ghost-of-y-tei": "ghost-of-yotei",
});

/** Panelde gösterilen okunur adlar. Listede olmayan kimlik tirelerden ayrılıp büyük harfle yazılır. */
export const GAME_NAMES = Object.freeze({
  "gta-6": "GTA 6",
  "gta-v": "GTA 5",
  "grand-theft-auto-iv": "GTA 4",
  "gta-iv": "GTA 4",
  "grand-theft-auto-online": "GTA Online",
  "red-dead-redemption-2": "Red Dead Redemption 2",
  "call-of-duty-modern-warfare-2019": "Call of Duty: Modern Warfare (2019)",
  "assassins-creed-shadows": "Assassin's Creed Shadows",
  "assassin-s-creed-mirage": "Assassin's Creed Mirage",
  "mafia-the-old-country": "Mafia: The Old Country",
  "death-stranding-2": "Death Stranding 2",
  "death-stranding-directors-cut": "Death Stranding Director's Cut",
  "elden-ring": "Elden Ring",
  "elden-ring-shadow-of-the-erdtree": "Elden Ring: Shadow of the Erdtree",
  "marvels-spider-man-2": "Marvel's Spider-Man 2",
  "kingdom-come-deliverance-ii": "Kingdom Come: Deliverance II",
  "the-last-of-us-part-ii": "The Last of Us Part II",
  "the-last-of-us-part-ii-remastered": "The Last of Us Part II Remastered",
  "wuchang-fallen-feathers": "Wuchang: Fallen Feathers",
  "far-cry-6": "Far Cry 6",
  "ghost-of-yotei": "Ghost of Yōtei",
  "astro-s-playroom": "Astro's Playroom",
  "final-fantasy.vii-remake": "Final Fantasy VII Remake",
  "ea-sports-fc-26": "EA Sports FC 26",
  "ea-sports-fc-27": "EA Sports FC 27",
  "nba-2k26": "NBA 2K26",
  "007-first-light": "007 First Light",
});

const ROMAN = /^(i|ii|iii|iv|v|vi|vii|viii|ix|x)$/;

/** Okunur ad: "gta-6" → "GTA 6", "red-dead-redemption-2" → "Red Dead Redemption 2"; boşsa "". */
export function gameName(id) {
  const game = canonicalGame(id);
  if (!game) return "";
  if (GAME_NAMES[game]) return GAME_NAMES[game];
  return game.split(/[-_.]+/).filter(Boolean)
    .map((w) => (ROMAN.test(w) ? w.toUpperCase() : w.charAt(0).toUpperCase() + w.slice(1))).join(" ");
}

/** {game, n…} satırlarını asıl kimlikte toplar (sayısal alanlar toplanır) ve okunur adı ekler; büyükten küçüğe. */
export function mergeGameRows(rows, { key = "game", sortBy = "n" } = {}) {
  const out = new Map();
  for (const r of rows) {
    const game = canonicalGame(r[key] ?? "") ?? "";
    const prev = out.get(game);
    if (!prev) { out.set(game, { ...r, [key]: game, name: gameName(game) }); continue; }
    for (const [k, v] of Object.entries(r)) if (k !== key && typeof v === "number") prev[k] = (prev[k] ?? 0) + v;
  }
  return [...out.values()].sort((a, b) => (b[sortBy] ?? 0) - (a[sortBy] ?? 0));
}

/** Kimliği asıl ada çevirir (küçük harf, art arda tireler teke). Takma ad değilse olduğu gibi döner. */
export function canonicalGame(id) {
  if (typeof id !== "string" || id === "") return id;
  const clean = id.toLowerCase().replace(/-{2,}/g, "-");
  return GAME_ALIASES[clean] ?? clean;
}

/** Bir asıl kimliğin bütün takma adları (birleştirme için). */
export function aliasesOf(target) {
  return Object.entries(GAME_ALIASES).filter(([, to]) => to === target).map(([from]) => from);
}

const quote = (s) => `'${String(s).replace(/'/g, "''")}'`;
const HEX = "0123456789abcdef";

/**
 * Takma adlardaki satırları asıl kimliğe taşıyan SQL. Satır anahtarlarının ilk hex hanesine göre 16 parça (her biri ayrı
 * çalıştırılabilir; önce tek parçayla denemek için). Hiçbir veri silinmeden önce asıl kimliğe eklenir:
 *  - lines: aynı anahtar iki oyunda da varsa görülme toplanır, ilk/son görülme genişler, kurulum sayısı en büyüğü ve
 *    birleşen kurulum listesinin sayısından büyük olanı; yazılış en çok kurulumda (sonra en çok görülen) olanınki.
 *  - line_installs: birleşim (aynı kurulum bir kez).
 * Ardından `tail`: oturumlar (satır sayıları toplanır), çevirilerin oyun sütunu, kurulumların son oyunu.
 * Çevirilerin anahtarı (key, lang) oyundan bağımsız olduğu için orada çakışma olmaz; yalnız `game` sütunu güncellenir.
 * Komutlar yeniden çalıştırılabilir: takma adda satır kalmadıysa hiçbir şey yapmaz.
 */
export function mergeGameSQL(target, aliases = aliasesOf(target)) {
  const T = quote(target);
  const A = `(${aliases.map(quote).join(", ")})`;
  const parts = [];
  for (let i = 0; i < 16; i++) {
    const lo = quote(HEX[i]);
    const rangeOf = (t) => (i < 15 ? `${t}key >= ${lo} AND ${t}key < ${quote(HEX[i + 1])}` : `${t}key >= ${lo}`);
    const range = rangeOf("");
    const inA = `game IN ${A} AND ${range}`;
    const best = (col) => `(SELECT b.${col} FROM lines b WHERE b.game IN ${A} AND b.key = lines.key ORDER BY b.installs DESC, b.seen DESC LIMIT 1)`;
    parts.push({
      prefix: HEX[i],
      sql: [
        `INSERT OR IGNORE INTO line_installs (game, key, install) SELECT ${T}, key, install FROM line_installs WHERE ${inA};`,
        `UPDATE lines SET
           seen = seen + (SELECT SUM(a.seen) FROM lines a WHERE a.game IN ${A} AND a.key = lines.key),
           first_seen = min(first_seen, (SELECT MIN(a.first_seen) FROM lines a WHERE a.game IN ${A} AND a.key = lines.key)),
           last_seen = max(last_seen, (SELECT MAX(a.last_seen) FROM lines a WHERE a.game IN ${A} AND a.key = lines.key)),
           text = CASE WHEN ${best("installs")} > installs THEN ${best("text")} ELSE text END,
           installs = max(installs, (SELECT MAX(a.installs) FROM lines a WHERE a.game IN ${A} AND a.key = lines.key))
         WHERE game = ${T} AND ${range} AND key IN (SELECT key FROM lines WHERE ${inA});`,
        `INSERT INTO lines (game, key, text, seen, installs, first_seen, last_seen)
         SELECT ${T}, a.key,
                (SELECT b.text FROM lines b WHERE b.game IN ${A} AND b.key = a.key ORDER BY b.installs DESC, b.seen DESC LIMIT 1),
                SUM(a.seen), MAX(a.installs), MIN(a.first_seen), MAX(a.last_seen)
         FROM lines a WHERE a.game IN ${A} AND ${rangeOf("a.")}
           AND NOT EXISTS (SELECT 1 FROM lines t WHERE t.game = ${T} AND t.key = a.key)
         GROUP BY a.key;`,
        `UPDATE lines SET installs = max(installs, (SELECT COUNT(*) FROM line_installs li WHERE li.game = ${T} AND li.key = lines.key))
         WHERE game = ${T} AND ${range} AND key IN (SELECT key FROM lines WHERE ${inA});`,
        `DELETE FROM line_installs WHERE ${inA};`,
        `DELETE FROM lines WHERE ${inA};`,
        `UPDATE translations SET game = ${T} WHERE ${inA};`,
      ].join("\n"),
    });
  }
  const tail = [
    `INSERT INTO sessions (session, game, lines, first_seen, last_seen)
     SELECT session, ${T}, SUM(lines), MIN(first_seen), MAX(last_seen) FROM sessions WHERE game IN ${A} GROUP BY session
     ON CONFLICT (session, game) DO UPDATE SET lines = lines + excluded.lines,
       first_seen = min(first_seen, excluded.first_seen), last_seen = max(last_seen, excluded.last_seen);`,
    `DELETE FROM sessions WHERE game IN ${A};`,
    `UPDATE installs SET game = ${T} WHERE game IN ${A};`,
    // Anahtarı hex olmayan (beklenmeyen) çeviri satırları da kalmasın.
    `UPDATE translations SET game = ${T} WHERE game IN ${A};`,
  ].join("\n");
  return { parts, tail };
}
