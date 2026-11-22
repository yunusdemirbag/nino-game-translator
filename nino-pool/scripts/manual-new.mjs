// SPDX-License-Identifier: AGPL-3.0-only
// Nino: havuzda hiç çevirisi olmayan satırları elle (Claude Code ile) çevirmek için parti çıkarır. En çok oyuncunun
// gördüğü önce; çöp ve yol tarifi satırları alınmaz. Çıktı manual-export ile aynı biçimde, "tr" boş:
// manual/bekleyen/<dil>-yeni-<sıra>.json  [{ k, en, tr: "", g }]. Yükleme: node scripts/manual-import.mjs (yeni satırı ekler).
// Kullanım: node scripts/manual-new.mjs [partiBoyu=300] [partiSayısı=8] [oyunlar=grand-theft-auto-vi,gta-vi,gta-6,gta6] [dil=tr]
import { execFileSync } from "node:child_process";
import { mkdirSync, writeFileSync, readdirSync, existsSync, readFileSync } from "node:fs";
import { junkReason } from "../src/filter.js";

const [size = 300, count = 8, games = "grand-theft-auto-vi,gta-vi,gta-6,gta6", lang = "tr"] = process.argv.slice(2);
if (!/^[a-z]{2}$/.test(lang)) throw new Error("dil iki harf olmalı");
const dir = new URL("../manual/", import.meta.url);
for (const d of ["bekleyen", "hazir", "yuklendi"]) mkdirSync(new URL(d, dir), { recursive: true });
const taken = new Set();
for (const d of ["bekleyen", "hazir"]) {
  for (const f of readdirSync(new URL(d, dir))) if (f.endsWith(".json") && f.startsWith(`${lang}-`)) for (const r of JSON.parse(readFileSync(new URL(`${d}/${f}`, dir)))) taken.add(r.k);
}
const list = games.split(",").map((g) => `'${g.replace(/[^a-z0-9-]/g, "")}'`).join(",");
const want = Number(size) * Number(count);
const sql = `SELECT l.key AS k, MIN(l.game) AS g, MIN(l.text) AS en, MAX(l.installs) AS i, SUM(l.seen) AS s
  FROM lines l WHERE l.game IN (${list}) AND NOT EXISTS (SELECT 1 FROM translations t WHERE t.key = l.key AND t.lang = '${lang}')
  GROUP BY l.key ORDER BY i DESC, s DESC LIMIT ${want * 6 + taken.size}`;
const out = execFileSync("npx", ["wrangler", "d1", "execute", "nino-pool", "--remote", "--json", "--command", sql],
  { maxBuffer: 256 * 1024 * 1024, stdio: ["ignore", "pipe", "ignore"] });
const rows = JSON.parse(out)[0].results.filter((r) => !taken.has(r.k) && !junkReason(r.en)).slice(0, want)
  .map(({ k, en, g }) => ({ k, en, tr: "", g }));
const prefix = `${lang}-yeni`;
let n = 0;
const used = (i) => ["bekleyen", "hazir", "yuklendi"].some((d) => existsSync(new URL(`${d}/${prefix}-${String(i).padStart(4, "0")}.json`, dir)));
while (used(n)) n++;
for (let i = 0, made = 0; i < rows.length; i += Number(size), made++) {
  const name = `${prefix}-${String(n + made).padStart(4, "0")}.json`;
  writeFileSync(new URL(`bekleyen/${name}`, dir), JSON.stringify(rows.slice(i, i + Number(size)), null, 1));
  console.log("bekleyen/" + name, Math.min(Number(size), rows.length - i), "satır");
}
if (rows.length === 0) console.log("Çevrilecek yeni satır yok.");
