// SPDX-License-Identifier: AGPL-3.0-only
// Nino: Claude'a gönderilmeden önce satır süzgeci. Ekran okumasından gelen tabela, menü, kırıntı ve zaten Türkçe
// yazılar para harcatmasın; bu satırlar uygulamada ücretsiz çeviriyle gösterilir, İngilizcesi yine havuza yazılır.

import { garbleRatio, GARBLE_MIN } from "./garble.js";
import { VOCAB } from "./vocab.js";

const LETTER = /\p{L}/gu;
const LOWER = /\p{Ll}/u;
const WORD = /[\p{L}\p{N}'’]+/gu;
/** Türkçeye özgü harfler (İngilizce altyazıda neredeyse hiç geçmez). */
const TURKISH_LETTER = /[çğışÇĞİŞ]/u;
/** Ekrandaki Türkçe arayüz yazıları (PS5 menüsü, Nino'nun kendi yazıları); Türkçe harfsiz yazılmış olsalar da. */
const TURKISH_WORDS = new Set([
  "bir", "icin", "için", "degil", "değil", "gerekmiyor", "baglan", "bağlan", "yukle", "yükle", "yuklenmesi",
  "yüklenmesi", "eklenti", "ayarlar", "devam", "geri", "tamam", "evet", "hayir", "hayır", "oyun", "oyunu", "oyna", "oynamaya",
  "kaydet", "cikis", "çıkış", "menu", "menü", "seç", "bekleniyor", "eklentisi", "paketi", "secenekler", "altyazi", "altyazı", "ceviri", "çeviri",
]);
/** Sık İngilizce sözcükler: satırda biri varsa Türkçe sayılmaz. */
const ENGLISH_WORDS = new Set([
  "the", "a", "you", "i", "to", "and", "it", "is", "we", "of", "that", "this", "on", "in", "for", "me", "my", "your",
  "what", "go", "get", "no", "yes", "yeah", "come", "okay", "ok", "man", "just", "don't", "i'm", "it's", "let's", "with",
]);

/**
 * Satır Claude'a gitmemeli mi; gitmemeliyse kısa sebep ("kırıntı", "büyük harf", "türkçe", "bozuk", "anlamsız"), yoksa "".
 * Bağırılan altyazılar ("GET DOWN!", "WHAT?!") büyük harf olsa da çevrilir.
 */
export function junkReason(raw) {
  const text = String(raw ?? "").trim();
  const letters = (text.match(LETTER) ?? []).length;
  // "Hi.", "No!" gibi iki harfli altyazılar çevrilir; noktalamasız iki harf ("VI", "sa") kırıntıdır.
  if (letters < 2 || (letters === 2 && !/[.!?]\s*$/.test(text))) return "kırıntı";
  const words = text.match(WORD) ?? [];
  const lowerWords = words.map((w) => w.toLowerCase());
  // Türkçe: Türkçeye özgü harf ya da arayüz sözcüğü var, sık İngilizce sözcük yok.
  const english = lowerWords.some((w) => ENGLISH_WORDS.has(w));
  if (!english && (TURKISH_LETTER.test(text) || lowerWords.some((w) => TURKISH_WORDS.has(w)))) return "türkçe";
  // Yayın istatistiği gibi rakam yığını ("Received: 2741607799 … Width: 2560").
  const digits = (text.match(/\p{N}/gu) ?? []).length;
  if (text.length > 20 && digits * 10 >= text.length * 3) return "bozuk";
  if (/AssembledFrom|tesReceived|cketsRe/i.test(text)) return "bozuk";
  if (!LOWER.test(text)) {
    if (/[!?]\s*$/.test(text)) return "";
    return "büyük harf";
  }
  // Tek sözcük, küçük harfle başlıyor, noktalaması yok: menü ya da kırıntı ("baglan", "mm").
  if (words.length === 1 && /^\p{Ll}/u.test(text) && !/[.!?…]$/.test(text)) return "kırıntı";
  // Bozuk okuma: sözcüklerin çoğu harf-rakam karışık ya da içinde büyük harf ("WAlhat", "pwnge(", "I1").
  const broken = words.filter((w) => /\p{L}/u.test(w) && (/\p{L}\p{N}|\p{N}\p{L}/u.test(w) || /\p{Ll}\p{Lu}/u.test(w)));
  if (words.length >= 2 && broken.length * 2 > words.length) return "bozuk";
  // Sözcüklerin çoğu havuzun hiç görmediği yazılışlar: ekran okuması bozmuş ("searcfiing the wre:ck").
  if (garbleRatio(text, VOCAB) >= GARBLE_MIN) return "anlamsız";
  return "";
}
