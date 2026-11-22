// SPDX-License-Identifier: AGPL-3.0-only
// Satır anahtarı: oyun paketlerinin kullandığı anahtarla birebir aynı (Mac'te PackKey). Sunucu anahtarı istemciye
// güvenmeden metinden kendisi hesaplar; aynı cümlenin farklı yazılışları ("Get down!" / "GET DOWN") tek satır sayılır.

const TAG = /<[^<>]{0,40}>/gu;
const MARK = /\p{M}/u;
const KEEP = /[\p{L}\p{N}]/u;

/** Sadeleştirilmiş metin: etiketler boşluk, NFKC, küçük harf, aksansız, harf ve rakam dışı boşluk, tek boşluk. */
export function canon(text) {
  const lowered = text.replace(TAG, " ").normalize("NFKC").toLowerCase().normalize("NFD");
  let out = "";
  let gap = false;
  for (const ch of lowered) {
    if (MARK.test(ch)) continue;
    if (KEEP.test(ch)) {
      if (gap && out.length > 0) out += " ";
      gap = false;
      out += ch;
    } else {
      gap = true;
    }
  }
  return out;
}

/** 16 haneli küçük harf hex anahtar; metinde harf ya da rakam yoksa null. */
export async function lineKey(text) {
  const c = canon(text);
  if (c.length === 0) return null;
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(c));
  return hex(new Uint8Array(digest).slice(0, 8));
}

/** Tuzlanmış kısa özet (kurulum kimliği sunucuda bu hâliyle tutulur). */
export async function saltedDigest(value, salt) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(`${salt}\u0000${value}`));
  return hex(new Uint8Array(digest).slice(0, 12));
}

function hex(bytes) {
  return Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");
}
