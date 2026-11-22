// SPDX-License-Identifier: AGPL-3.0-only
// Takma adlı oyun kimliklerini asıl kimliğe taşıyan SQL dosyalarını yazar (src/games.js → mergeGameSQL).
//   node scripts/merge-game.mjs gta-6 <klasör>
// Çıktı: 00-dogrula.sql (önce/sonra sayılar), 01-parca-0.sql … 16-parca-f.sql, 17-son.sql.
// Çalıştırma (yalnız onaydan sonra, önce bir parça):
//   npx wrangler d1 execute nino-pool --remote --file <klasör>/01-parca-0.sql
import { mkdirSync, writeFileSync } from "node:fs";
import { mergeGameSQL, aliasesOf } from "../src/games.js";

const [target = "gta-6", out = "merge-out"] = process.argv.slice(2);
const aliases = aliasesOf(target);
const all = [target, ...aliases].map((g) => `'${g}'`).join(", ");
const A = aliases.map((g) => `'${g}'`).join(", ");
mkdirSync(out, { recursive: true });
writeFileSync(`${out}/00-dogrula.sql`, [
  `SELECT game, COUNT(*) AS lines, SUM(seen) AS seen, SUM(installs) AS installs FROM lines WHERE game IN (${all}) GROUP BY game;`,
  `SELECT COUNT(DISTINCT key) AS distinct_keys, SUM(seen) AS total_seen FROM lines WHERE game IN (${all});`,
  `SELECT game, COUNT(*) AS n FROM line_installs WHERE game IN (${all}) GROUP BY game;`,
  `SELECT game, COUNT(*) AS n FROM sessions WHERE game IN (${all}) GROUP BY game;`,
  `SELECT game, COUNT(*) AS n FROM translations WHERE game IN (${all}) GROUP BY game;`,
  `SELECT game, COUNT(*) AS n FROM installs WHERE game IN (${all}) GROUP BY game;`,
].join("\n") + "\n");
const { parts, tail } = mergeGameSQL(target, aliases);
parts.forEach((p, i) => writeFileSync(`${out}/${String(i + 1).padStart(2, "0")}-parca-${p.prefix}.sql`, p.sql + "\n"));
writeFileSync(`${out}/17-son.sql`, tail + "\n");
console.log(`${target} ← ${A}\n${parts.length + 2} dosya: ${out}`);
