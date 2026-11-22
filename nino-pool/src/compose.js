// SPDX-License-Identifier: AGPL-3.0-only
// Nino: ekran okuması iki altyazıyı tek satırda birleştirebiliyor ("Okay, let me get back. Escort the bachelor party
// through the trench") ya da başına konuşanın adını koyuyor ("Lucia: Shut up!"). Satırın her cümlesi havuzda ya da
// hazır tohumda varsa çevirisi cümlelerden kurulur; Claude'a sorulmaz.

/** Konuşan adı: büyük harfle başlayan bir ya da iki sözcük ve iki nokta ("Lucia:", "Cal Hampton:"). */
const SPEAKER = /(^|\s)((?:[A-Z][\p{L}'’.-]{0,14})(?: [A-Z][\p{L}'’.-]{0,14})?:)(?=\s)/gu;
const SENTENCE_END = /(?<=[.!?…])\s+/u;
const HAS_WORD = /\p{L}{2}/u;

/**
 * Satırı parçalara böler: [{ label?: "Lucia:" } | { text: "Shut up!" }]. Çevrilecek en az bir cümle yoksa ya da satır
 * tek cümleyse ve konuşan adı da yoksa null (birleştirecek bir şey yok).
 */
export function splitLine(text) {
  const source = String(text ?? "").trim();
  const parts = [];
  let last = 0;
  for (const match of source.matchAll(SPEAKER)) {
    const start = match.index + match[1].length;
    pushSentences(parts, source.slice(last, start));
    parts.push({ label: match[2] });
    last = start + match[2].length;
  }
  pushSentences(parts, source.slice(last));
  const sentences = parts.filter((p) => p.text);
  const labels = parts.length - sentences.length;
  if (sentences.length === 0) return null;
  if (sentences.length === 1 && labels === 0) return null;
  return parts;
}

function pushSentences(parts, chunk) {
  for (const piece of chunk.split(SENTENCE_END)) {
    const text = piece.trim();
    if (text && HAS_WORD.test(text)) parts.push({ text });
  }
}

/** Parçaları çevirileriyle birleştirir; `translations` cümle metni → çeviri. Eksik varsa null. */
export function joinParts(parts, translate) {
  const out = [];
  for (const part of parts) {
    if (part.label) { out.push(part.label); continue; }
    const t = translate(part.text);
    if (!t) return null;
    out.push(t);
  }
  return out.join(" ");
}
