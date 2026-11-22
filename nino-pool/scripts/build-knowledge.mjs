// SPDX-License-Identifier: AGPL-3.0-only
// Nino yardımcısının bilgi tabanı: assistant/surum-4-5.md + tv-kurulum.md + bilgiler.md + kurulum rehberleri + README'nin kurulum bölümleri.
// Rehber değişince `npm run knowledge` ile yeniden üretilir; çıktı src/knowledge.js (depoya girer, Worker'a gömülür).
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const repo = join(here, "..", "..");
const read = (p) => readFileSync(join(repo, p), "utf8");

// Görseller, HTML ve yorumlar modele bir şey anlatmaz; çıkarılır.
const clean = (text) => text
  .replace(/<!--[\s\S]*?-->/g, "")
  .replace(/<p[^>]*>[\s\S]*?<\/p>/g, (block) => (/<img/.test(block) ? "" : block.replace(/<[^>]+>/g, "")))
  .replace(/!\[[^\]]*\]\([^)]*\)/g, "")
  .replace(/<[^>]+>/g, "")
  .replace(/\n{3,}/g, "\n\n")
  .trim();

// README'den yalnız kullanıcıya dönük bölümler (İngilizce kısım, derleme ve lisans dışarıda).
function readmeSections(text) {
  const keep = ["Nasıl çalışır", "Yenilikler", "Kimler kullanabilir", "Gerekenler", "Kurulum", "Fotoğraflı kurulum",
    "Telefon uygulaması", "Xbox", "Gizlilik", "Sık sorulanlar"];
  return text.split(/\n(?=## )/).filter((part) => keep.some((title) => part.startsWith(`## ${title}`))).join("\n\n");
}

// Güncel uygulamaların (V4.5) gerçek menü adları ve adım adım TV kurulumu en başta; çelişirse bunlar doğrudur.
// Sık sorulan sorular (assistant/sss.json, gerçek sohbetlerden): yalnız Türkçe soru ve cevap; model öbür dillere çevirir.
const sss = JSON.parse(read("nino-pool/assistant/sss.json")).topics
  .map((t) => `### ${t.question.tr}\n${t.reply.tr.trim()}`).join("\n\n");
const parts = [
  ["Nino V4.5 (güncel)", read("nino-pool/assistant/surum-4-5.md")],
  ["TV kurulumu adım adım (güncel)", read("nino-pool/assistant/tv-kurulum.md")],
  ["Sık sorulan sorular (gerçek sohbetlerden, güncel)", sss],
  ["Ek bilgiler", read("nino-pool/assistant/bilgiler.md")],
  ["Kurulum rehberi (docs/KURULUM.md)", read("docs/KURULUM.md")],
  ["Fotoğraflı Android TV rehberi (docs/KURULUM-ANDROID-TV.md)", read("docs/KURULUM-ANDROID-TV.md")],
  ["README (kullanıcı bölümleri)", readmeSections(read("README.md"))],
];
const knowledge = parts.map(([title, text]) => `===== ${title} =====\n\n${clean(text)}`).join("\n\n");
writeFileSync(join(here, "..", "src", "knowledge.js"),
  "// SPDX-License-Identifier: AGPL-3.0-only\n// Üretilen dosya: scripts/build-knowledge.mjs. Elle değiştirmeyin.\n" +
  `export const KNOWLEDGE = ${JSON.stringify(knowledge)};\n`);
console.log(`bilgi tabanı: ${knowledge.length} karakter`);
