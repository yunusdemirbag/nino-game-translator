// SPDX-License-Identifier: AGPL-3.0-only
// Nino: ekran okumasının bozduğu satırlar ("lopkin gont yo wanna startan the engine"). Bu yazılış bir daha aynı
// gelmeyeceği için Claude'a para ödenmez; uygulama ücretsiz çeviriyle gösterir. Sözlük havuzun kendi satırlarından
// (scripts/build-vocab.mjs): sözcüklerin en az GARBLE_MIN'i sözlükte yoksa satır anlamsız sayılır.

export const GARBLE_MIN = 0.25;
/** Bu kadar sözcükten kısa satırlar değerlendirilmez (kısa satırda tek ad oranı bozar). */
const MIN_WORDS = 3;

export function words(text) {
  return String(text ?? "").toLowerCase().replace(/[’`]/g, "'").match(/[a-z]+(?:'[a-z]+)*/g) ?? [];
}

/** Bu kadar sözcük sözlükte değilse bakılır (tek nadir sözcük, "duffel", satırı düşürmesin). */
const MIN_UNKNOWN = 2;

/** Sözlükte olmayan sözcüklerin oranı (0-1); kısa satırda ya da yalnız bir bilinmeyen sözcük varsa 0. */
export function garbleRatio(text, vocab) {
  const list = words(text).filter((w) => w.length >= 2);
  if (list.length < MIN_WORDS || !vocab || vocab.size === 0) return 0;
  const unknown = list.filter((w) => !vocab.has(w)).length;
  return unknown < MIN_UNKNOWN ? 0 : unknown / list.length;
}
