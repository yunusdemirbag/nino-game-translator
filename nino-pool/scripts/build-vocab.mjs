// SPDX-License-Identifier: AGPL-3.0-only
// Nino: anlamsız satır süzgecinin sözlüğü (src/vocab.js). Havuzdaki İngilizce satırlarda en az MIN farklı satırda geçen
// sözcükler: gerçek sözcükler (argo, adlar, "gonna") tekrar eder, ekran okumasının bozduğu yazılışlar ("searcfiing") etmez.
// Kullanım: node scripts/build-vocab.mjs  (canlı D1'den okur; wrangler oturumu gerekir)
import { execFileSync } from "node:child_process";
import { writeFileSync } from "node:fs";
import { words } from "../src/garble.js";

const MIN = 3;
const out = execFileSync("npx", ["wrangler", "d1", "execute", "nino-pool", "--remote", "--json", "--command", "SELECT text FROM lines"],
  { maxBuffer: 512 * 1024 * 1024, stdio: ["ignore", "pipe", "ignore"] });
const df = new Map();
for (const { text } of JSON.parse(out)[0].results) for (const w of new Set(words(text))) df.set(w, (df.get(w) ?? 0) + 1);
const vocab = [...df].filter(([, n]) => n >= MIN).map(([w]) => w).sort();
writeFileSync(new URL("../src/vocab.js", import.meta.url),
  `// SPDX-License-Identifier: AGPL-3.0-only\n// Üretildi: scripts/build-vocab.mjs (${new Date().toISOString().slice(0, 10)}, ${vocab.length} sözcük). Elle düzenlemeyin.\n` +
  `export const VOCAB = new Set(${JSON.stringify(vocab.join(" "))}.split(" "));\n`);
console.log(vocab.length, "sözcük");
