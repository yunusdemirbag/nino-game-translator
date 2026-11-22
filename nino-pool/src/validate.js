// SPDX-License-Identifier: AGPL-3.0-only
// Gelen parçanın biçim ve boyut denetimi. Tek bir bozuk satır parçanın geri kalanını düşürmez: satırlar tek tek
// kabul ya da ret edilir; yalnız parçanın kendisi bozuksa (kimlik yok, çok büyük) bütün istek reddedilir.
import { canonicalGame } from "./games.js";

export const LIMITS = Object.freeze({
  maxBodyBytes: 512 * 1024,
  maxLines: 500,
  maxTextLength: 500,
  maxGameLength: 64,
  maxCount: 100000,
  maxAppLength: 40,
});

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const GAME = /^[a-z0-9][a-z0-9._-]*$/;
const PLATFORMS = new Set(["mac", "windows", "linux", "android", "ios", "tv", "test"]);
// Denetim karakterleri, sıfır genişlikli boşluklar, satır/paragraf ayırıcılar ve BOM boşluk olur.
const CONTROL = new RegExp("[" + [[0x00, 0x1f], [0x7f, 0x9f], [0x200b, 0x200f], [0x2028, 0x2029], [0xfeff, 0xfeff]]
  .map(([a, b]) => `\\u{${a.toString(16)}}-\\u{${b.toString(16)}}`).join("") + "]", "gu");
const LETTER = /\p{L}/u;
// En eski kabul edilen zaman (2024-01-01); en ileri: şimdi + 1 gün.
const EARLIEST = 1704067200;

export class RequestError extends Error {
  constructor(status, code) {
    super(code);
    this.status = status;
    this.code = code;
  }
}

/** Parçanın üst bilgisini denetler; bozuksa RequestError atar. Satırlar ayrıca `checkLine` ile denetlenir. */
export function checkBatch(body) {
  if (body === null || typeof body !== "object" || Array.isArray(body)) throw new RequestError(400, "not_object");
  if (body.v !== 1) throw new RequestError(400, "unknown_version");
  if (typeof body.batch !== "string" || !UUID.test(body.batch)) throw new RequestError(400, "bad_batch_id");
  if (typeof body.install !== "string" || !UUID.test(body.install)) throw new RequestError(400, "bad_install");
  if (!Array.isArray(body.lines)) throw new RequestError(400, "no_lines");
  if (body.lines.length > LIMITS.maxLines) throw new RequestError(413, "too_many_lines");
  const app = typeof body.app === "string" ? body.app.slice(0, LIMITS.maxAppLength) : "";
  const platform = PLATFORMS.has(body.platform) ? body.platform : "other";
  return { batch: body.batch.toLowerCase(), install: body.install.toLowerCase(), app, platform, lines: body.lines };
}

/** Tek satır: { text, game, session, count, first, last } ya da { reject: "neden" }. */
export function checkLine(line, now) {
  if (line === null || typeof line !== "object") return { reject: "not_object" };
  if (typeof line.text !== "string") return { reject: "no_text" };
  const text = line.text.replace(CONTROL, " ").replace(/\s+/gu, " ").trim();
  if (text.length === 0) return { reject: "empty" };
  if ([...text].length > LIMITS.maxTextLength) return { reject: "too_long" };
  if (!LETTER.test(text)) return { reject: "no_letters" };

  let game = "";
  if (line.game !== undefined && line.game !== null && line.game !== "") {
    if (typeof line.game !== "string" || line.game.length > LIMITS.maxGameLength || !GAME.test(line.game)) {
      return { reject: "bad_game" };
    }
    game = canonicalGame(line.game);
  }

  let session = null;
  if (line.session !== undefined && line.session !== null) {
    if (typeof line.session !== "string" || !UUID.test(line.session)) return { reject: "bad_session" };
    session = line.session.toLowerCase();
  }

  const count = line.count === undefined ? 1 : line.count;
  if (!Number.isInteger(count) || count < 1 || count > LIMITS.maxCount) return { reject: "bad_count" };

  const latest = now + 86400;
  const clamp = (t) => (Number.isFinite(t) ? Math.min(Math.max(Math.floor(t), EARLIEST), latest) : now);
  let first = clamp(line.first ?? now);
  let last = clamp(line.last ?? first);
  if (last < first) [first, last] = [last, first];

  return { text, game, session, count, first, last };
}
