// SPDX-License-Identifier: AGPL-3.0-only
// Nino: elle (Claude Code ile) kaliteli çeviri için havuzdan parti çıkarır. Gözden geçirilmemiş (tier 1) Türkçe
// çeviriler; bozuk kopyalar alınmaz (aslı düzelince onlar da düzelir). Oyunda görüldükleri sırayla (sahne bağlamı korunur),
// en çok oyuncunun gördüğü oyun önce.
// Kullanım: node scripts/manual-export.mjs [partiBoyu=200] [partiSayısı=5] [oyun=grand-theft-auto-vi|*] [dil=tr]
// Çıktı: manual/bekleyen/<dil>-<oyun>-<sıra>.json  [{ k, en, tr }]  ("tr" alanı o dildeki mevcut çeviridir)
import { execFileSync } from "node:child_process";
import { mkdirSync, writeFileSync, readdirSync, existsSync } from "node:fs";

const [size = 200, count = 5, game = "grand-theft-auto-vi", lang = "tr"] = process.argv.slice(2);
if (!/^[a-z]{2}$/.test(lang)) throw new Error("dil iki harf olmalı");
const prefix = `${lang}-${game === "*" ? "hepsi" : game}`;
const dir = new URL("../manual/", import.meta.url);
for (const d of ["bekleyen", "hazir", "yuklendi"]) mkdirSync(new URL(d, dir), { recursive: true });

// Zaten bekleyen/hazır partilerdeki satırlar yeniden alınmaz (yalnız aynı dilin partileri: anahtar dillerde ortak).
const taken = new Set();
for (const d of ["bekleyen", "hazir"]) {
  for (const f of readdirSync(new URL(d, dir))) {
    if (f.endsWith(".json") && f.startsWith(`${lang}-`)) for (const r of JSON.parse(execFileSync("cat", [new URL(`${d}/${f}`, dir).pathname]))) taken.add(r.k);
  }
}

const sql = `SELECT t.key AS k, t.source AS en, t.text AS tr,
  COALESCE((SELECT l.first_seen FROM lines l WHERE l.game = t.game AND l.key = t.key), t.created) AS seen
  FROM translations t
  WHERE t.lang = '${lang}' AND t.tier = 1 AND t.text <> '' AND (t.copy_of IS NULL OR t.copy_of = 'seed')${game === "*" ? "" : ` AND t.game = '${game.replace(/'/g, "")}'`}
  ORDER BY seen, t.key LIMIT ${Number(size) * Number(count) + taken.size}`;
const out = execFileSync("npx", ["wrangler", "d1", "execute", "nino-pool", "--remote", "--json", "--command", sql],
  { maxBuffer: 256 * 1024 * 1024, stdio: ["ignore", "pipe", "ignore"] });
const rows = JSON.parse(out)[0].results.filter((r) => !taken.has(r.k)).map(({ k, en, tr }) => ({ k, en, tr }));

let n = 0;
while (existsSync(new URL(`bekleyen/${prefix}-${String(n).padStart(4, "0")}.json`, dir))
  || existsSync(new URL(`hazir/${prefix}-${String(n).padStart(4, "0")}.json`, dir))
  || existsSync(new URL(`yuklendi/${prefix}-${String(n).padStart(4, "0")}.json`, dir))) n++;
let made = 0;
for (let i = 0; i < rows.length && made < Number(count); i += Number(size), made++) {
  const name = `${prefix}-${String(n + made).padStart(4, "0")}.json`;
  writeFileSync(new URL(`bekleyen/${name}`, dir), JSON.stringify(rows.slice(i, i + Number(size)), null, 1));
  console.log("bekleyen/" + name, Math.min(Number(size), rows.length - i), "satır");
}
if (made === 0) console.log("Gözden geçirilecek satır kalmadı.");
