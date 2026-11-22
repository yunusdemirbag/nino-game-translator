// SPDX-License-Identifier: AGPL-3.0-only
// Nino: oyunun yol tarifi satırları ("Turn Right 405 ft 432 ft") kuralla çevrilir. Her mesafe ayrı bir satır olduğu
// için eskiden her biri ayrı ayrı Claude'a gidiyordu (19 Kasım 2026: havuzdaki Türkçe satırların %4'ü).

const MOVES = {
  tr: { "turn right": "Sağa dön", "turn left": "Sola dön", "keep right": "Sağda kal", "keep left": "Solda kal",
        "u-turn right": "Sağa U dönüşü", "u-turn left": "Sola U dönüşü" },
};
const MOVE = /^[\s\-–—'"‘’.,·•]*(u-?\s?turn|turn|keep)\s+(left|right)\b(.*)$/i;
/** Mesafe: sayı (okuma hatasıyla "O"/"o" = 0) + birim. */
const DISTANCE = /(\d+(?:[.,]\d+)?|[Oo])\s*(ft|mi|yd|km|m)\b/g;

/**
 * Satır yol tarifiyse çevirisi ("Sağa dön 405 ft 432 ft"), değilse null. Yalnız yön + mesafelerden oluşan satırlar
 * sayılır; arkasında başka söz varsa ("Turn right at the lights, okay?") altyazıdır, dokunulmaz.
 */
export function navTranslation(raw, lang) {
  const moves = MOVES[lang];
  if (!moves) return null;
  const match = MOVE.exec(String(raw ?? "").trim());
  if (!match) return null;
  const kind = match[1].toLowerCase().replace(/\s/g, "").replace(/^uturn$/, "u-turn");
  const move = moves[`${kind} ${match[2].toLowerCase()}`];
  if (!move) return null;
  const rest = match[3];
  const distances = [...rest.matchAll(DISTANCE)].map((d) => `${/^[Oo]$/.test(d[1]) ? "0" : d[1]} ${d[2].toLowerCase()}`);
  if (distances.length === 0) return null;
  // Mesafeler çıkınca geriye yalnız okuma kırıntısı (noktalama, tek tük harf) kalmalı.
  const leftover = rest.replace(DISTANCE, " ").replace(/[^\p{L}\p{N}]/gu, "");
  if (leftover.length > 2) return null;
  return `${move} ${distances.join(" ")}`;
}
