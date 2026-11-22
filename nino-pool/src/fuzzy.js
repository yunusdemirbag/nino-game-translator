// SPDX-License-Identifier: AGPL-3.0-only
// Nino: ekran okumasının bozduğu kopyaları havuzdaki çeviriyle eşleştirir ("Oh heyl Jason" → "Oh hey Jason").
// Güvenlik: sayılar birebir aynı olmalı ("Turn Right 411 ft" ≠ "417 ft"), olumsuzluk ikisinde de olmalı ya da hiçbirinde
// olmamalı ("I do" ≠ "I don't"), metinler en az %90 benzer olmalı. Kısa satırlar (12 harften az) eşleştirilmez.

import { canon } from "./key.js";

export const FUZZY_MIN = 0.9;
const BLOCK = 10;
const MIN_LENGTH = 12;

/** Ekran okumasının sık karıştırdıklarını birleştirir, boşlukları atar. */
export function fold(text) {
  return canon(text).replace(/rn/g, "m").replace(/vv/g, "w").replace(/[l1|]/g, "i").replace(/0/g, "o").replace(/ /g, "");
}

/** Eşleştirme için aranacak parçalar (baştaki ve sondaki 10 harf); kısa satırda boş. */
export function blocks(text) {
  const f = fold(text);
  if (f.length < MIN_LENGTH) return [];
  return [`p${f.slice(0, BLOCK)}`, `s${f.slice(-BLOCK)}`];
}

function numbers(text) {
  return (String(text).match(/\d+/g) ?? []).join(",");
}

/** Olumsuzluk var mı (ekran okumasının bozduğu "donlt", "ainlt" de sayılır). */
function negative(text) {
  const t = String(text).toLowerCase().replace(/n[l1i|]t\b/g, "n't").replace(/[’`]/g, "'");
  return /\b(not|never|no|nothing|nobody|none|nope|nah)\b|n't\b|\b(dont|cant|wont|didnt|aint|isnt|wasnt|doesnt|couldnt|shouldnt|wouldnt)\b/.test(t);
}

function distance(a, b, limit) {
  if (Math.abs(a.length - b.length) > limit) return limit + 1;
  let prev = Array.from({ length: b.length + 1 }, (_, i) => i);
  for (let i = 1; i <= a.length; i++) {
    const cur = [i];
    let best = i;
    for (let j = 1; j <= b.length; j++) {
      cur[j] = Math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1));
      if (cur[j] < best) best = cur[j];
    }
    if (best > limit) return limit + 1;
    prev = cur;
  }
  return prev[b.length];
}

/** İki satır aynı cümle mi (0-1 benzerlik; güvenlik kuralları tutmazsa 0). */
export function similarity(a, b) {
  if (numbers(a) !== numbers(b) || negative(a) !== negative(b)) return 0;
  const fa = fold(a);
  const fb = fold(b);
  if (fa.length < MIN_LENGTH || fb.length < MIN_LENGTH) return fa === fb ? 1 : 0;
  const longest = Math.max(fa.length, fb.length);
  const limit = Math.floor(longest * (1 - FUZZY_MIN));
  const d = distance(fa, fb, limit);
  return d > limit ? 0 : 1 - d / longest;
}

/** Adaylar içinde en benzeri (FUZZY_MIN altındaysa null). */
export function bestMatch(text, candidates) {
  let best = null;
  let score = 0;
  for (const c of candidates) {
    const s = similarity(text, c.source);
    if (s >= FUZZY_MIN && s > score) { best = c; score = s; }
  }
  return best;
}
