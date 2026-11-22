// SPDX-License-Identifier: AGPL-3.0-only
// Nino: elle çevrilmiş partileri (manual/hazir/*.json, [{ k, tr }]) havuza yazar: tier 2 (gözden geçirilmiş), değişenin
// `updated`i yenilenir (uygulamalar sonraki çekişte alır), bozuk kopyaları da (copy_of) aynı metni alır. Yüklenen dosya
// manual/yuklendi/ altına taşınır.
// Kullanım: node scripts/manual-import.mjs [dosya.json …]  (verilmezse hazir/ altındaki hepsi). Dil dosya adının başından (tr-…, ar-…).
import { execFileSync } from "node:child_process";
import { readdirSync, readFileSync, renameSync } from "node:fs";
import { join, basename } from "node:path";

const dir = new URL("../manual/", import.meta.url).pathname;
const files = process.argv.slice(2).length ? process.argv.slice(2)
  : readdirSync(join(dir, "hazir")).filter((f) => f.endsWith(".json")).map((f) => join(dir, "hazir", f));
const q = (s) => `'${String(s).replace(/'/g, "''")}'`;
const now = Math.floor(Date.now() / 1000);
for (const file of files) {
  const lang = /^([a-z]{2})-/.exec(basename(file))?.[1] ?? "tr";
  const rows = JSON.parse(readFileSync(file, "utf8")).filter((r) => /^[0-9a-f]{16}$/.test(r.k) && typeof r.tr === "string" && r.tr.trim());
  // Kaynağın bekleyen dosyası: yeni satırlarda (manual-new, "g" alanı) çeviri satırı henüz yok, eklenir.
  const src = new Map();
  try { for (const r of JSON.parse(readFileSync(join(dir, "bekleyen", basename(file)), "utf8"))) src.set(r.k, r); } catch {}
  const sql = rows.flatMap(({ k, tr }) => {
    const text = q(tr.replace(/\s+/g, " ").trim());
    const s = src.get(k);
    const insert = s?.g ? [`INSERT OR IGNORE INTO translations (key, lang, game, source, text, tier, created, updated) VALUES (${q(k)}, '${lang}', ${q(s.g)}, ${q(s.en)}, ${text}, 2, ${now}, ${now});`] : [];
    return [...insert,
      `UPDATE translations SET updated = CASE WHEN text = ${text} THEN updated ELSE ${now} END, text = ${text}, tier = 2 WHERE lang = '${lang}' AND key = ${q(k)};`,
      `UPDATE translations SET updated = CASE WHEN text = ${text} THEN updated ELSE ${now} END, text = ${text}, tier = 2 WHERE lang = '${lang}' AND copy_of = ${q(k)};`,
    ];
  }).join("\n");
  // --command (--file değil): dosyayla içe aktarma veritabanını kısa süre kilitler, canlı çeviri beklemesin.
  const statements = sql.split("\n");
  for (let i = 0; i < statements.length; i += 100) {
    // D1 yoğunken ("overloaded", 7429) bekleyip yeniden dener; komutlar tekrar çalıştırılabilir (aynı metni yazar).
    for (let attempt = 1; ; attempt++) {
      try {
        execFileSync("npx", ["wrangler", "d1", "execute", "nino-pool", "--remote", "--yes", "--command", statements.slice(i, i + 100).join("\n")],
          { stdio: ["ignore", "ignore", "pipe"] });
        break;
      } catch (e) {
        if (attempt >= 6) throw e;
        execFileSync("sleep", [String(attempt * 10)]);
      }
    }
  }
  renameSync(file, join(dir, "yuklendi", basename(file)));
  console.log(basename(file), rows.length, "satır yüklendi");
}
