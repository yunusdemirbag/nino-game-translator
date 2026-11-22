// SPDX-License-Identifier: AGPL-3.0-only
// Yardımcıyı aynı sorularla dener (assistant/deneme-sorulari.json). Önce hazır cevap kütüphanesine bakar (ücretsiz);
// kütüphanenin doğrudan vermediği sorular gerçek API'ye gider (ücretlidir), benzer hazır cevap ipucu olarak eklenir.
// Kullanım: ASSISTANT_PROVIDER=gemini GEMINI_API_KEY=... node scripts/eval-assistant.mjs
//           ASSISTANT_PROVIDER=openrouter ASSISTANT_MODEL=google/gemini-2.5-flash-lite OPENROUTER_API_KEY=... node scripts/eval-assistant.mjs
//           ONLY_LIBRARY=1 node scripts/eval-assistant.mjs   (yalnız kütüphane, API yok)
import { readFileSync } from "node:fs";
import { askModel, systemText } from "../src/assistant.js";
import { ANSWERS } from "../src/answers.js";
import { prepareLibrary, matchAnswer } from "../src/answers-match.js";

const questions = JSON.parse(readFileSync(new URL("../assistant/deneme-sorulari.json", import.meta.url)));
const library = prepareLibrary(ANSWERS);
const env = process.env;
let passed = 0, fromLibrary = 0, cost = 0;
for (const item of questions) {
  const started = Date.now();
  const messages = [{ role: "user", text: item.q, images: [] }];
  const match = matchAnswer(library, { language: item.lang, platform: "android", messages });
  let answer;
  if (match?.direct) {
    answer = { reply: match.reply, report: null };
    fromLibrary++;
  } else if (env.ONLY_LIBRARY) {
    console.log(`· [${item.lang}] ${item.q}\n   (modele gider${match ? `, ipucu: ${match.id}` : ""})\n`);
    continue;
  } else {
    try {
      answer = await askModel(env, systemText(item.lang, "android", match?.reply ?? null), messages);
      cost += answer?.cost ?? 0;
    } catch (error) {
      console.log(`✗ ${item.q}\n   HATA: ${error.message}`);
      continue;
    }
  }
  const reply = answer?.reply ?? "";
  const ok = item.must.every((pattern) => new RegExp(pattern, "i").test(reply))
    && item.mustNot.every((pattern) => !new RegExp(pattern).test(reply))
    && (item.expectReport === undefined || Boolean(answer?.report) === item.expectReport);
  if (ok) passed++;
  const source = match?.direct ? `hazır: ${match.id}` : `${Date.now() - started} ms${match ? `, ipucu: ${match.id}` : ""}`;
  console.log(`${ok ? "✓" : "✗"} [${item.lang}] ${item.q} (${source})\n   ${reply.replace(/\n/g, "\n   ")}${answer?.report ? `\n   [bildirim: ${answer.report.summary}]` : ""}\n`);
}
console.log(`${passed}/${questions.length} geçti, ${fromLibrary} hazır cevap (${env.ASSISTANT_PROVIDER ?? "-"} ${env.ASSISTANT_MODEL ?? "varsayılan model"}${cost ? `, ${(cost / 1e6).toFixed(4)} $` : ""})`);
