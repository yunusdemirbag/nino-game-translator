// SPDX-License-Identifier: AGPL-3.0-only
// Nino yardımcısının hazır cevapları: assistant/hazir-cevaplar.json → src/answers.js (Worker'a gömülür, depoya girer).
// JSON değişince `npm run answers` ile yeniden üretilir.
import { readFileSync, writeFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const data = JSON.parse(readFileSync(join(here, "..", "assistant", "hazir-cevaplar.json"), "utf8"));
delete data._;
if (data.busy) delete data.busy._;
writeFileSync(join(here, "..", "src", "answers.js"),
  "// SPDX-License-Identifier: AGPL-3.0-only\n// Üretilen dosya: scripts/build-answers.mjs (kaynak assistant/hazir-cevaplar.json). Elle değiştirmeyin.\n" +
  `export const ANSWERS = ${JSON.stringify(data)};\n`);
console.log(`hazır cevaplar: ${data.entries.length} konu`);
