// SPDX-License-Identifier: AGPL-3.0-only
// Nino yardımcısı: hazır cevap eşlemesi (model çağırmadan). Veri: assistant/hazir-cevaplar.json → src/answers.js.
//
// Girdi biçimi (her girdi):
//   id          kimlik
//   triggers    { dil: ["kısa ifade", …], "*": [dilden bağımsız, ör. marka adları] }
//   reply       { dil: "cevap" }        variants: { android | ios | desktop: { dil: "cevap" } } (platforma göre)
//   after       [girdi kimlikleri]: girdi yalnız önceki Nino mesajı bu hazır cevaplardan biriyse denenir
//               (ör. "TV'nin markası ne?" → "TCL"). `after` olmayan girdiler yalnız sohbetin ilk sorusunda denenir.
//   opener      selamlaşma: bu cevaptan sonraki mesaj ilk soru gibi eşlenir
//   anytime     sohbetin her yerinde denenir (sık takılma noktaları: "IP nerede", "Paket geçersiz"…); yalnız doğrudan
//               eşleşmede verilir, ipucu olmaz
//   maxExtra    tetikleyicinin dışında en çok kaç anlamlı sözcük olabilir (varsayılan 1)
//   allowDigits sayılar (model numarası) doğrudan cevaba engel değil
//   replyOf     cevabı başka girdiden al (aynı adım, başka giriş yolu)
//   langs       cevabın yazıldığı diller (yoksa 12 dilin hepsi); başka dilde soru modele gider
//
// Güvenlik: yanlış hazır cevap hiç cevaptan kötüdür. Doğrudan cevap yalnız kısa, tetikleyicinin tamamını içeren, ayrıntı
// (hata kodu, "denedim", ekran görüntüsü) taşımayan mesaja verilir; gerisinde hazır cevap modele ipucu olarak gider.

const LATIN = /[a-z]/;
const THAI = /[฀-๿]/;
const ARABIC = /[؀-ۿ]/;
const DEVANAGARI = /[ऀ-ॿ]/;
const BENGALI = /[ঀ-৿]/;
const LANG_ALIASES = { tl: "fil", in: "id" };
const MAX_DIRECT_WORDS = 14;

/** "tr-TR" → "tr", "tl" → "fil". */
export function baseLang(language) {
  const base = String(language ?? "").toLowerCase().split(/[-_]/)[0];
  return LANG_ALIASES[base] ?? base;
}

/** Küçük harf, Latin aksanları ve Arapça harekeler atılır (ı→i, ş→s, أ→ا); kesme işareti `apostrophe` ile değişir. */
export function normalize(text, apostrophe = " ") {
  return String(text ?? "")
    .normalize("NFKC")
    .replace(/İ/g, "i").replace(/I/g, "i")
    .toLowerCase()
    .normalize("NFD").replace(/([a-z])\p{M}+/gu, "$1").normalize("NFC")
    .replace(/ı/g, "i")
    .replace(/[ً-ٰٟـ]/g, "")
    .replace(/[أإآ]/g, "ا").replace(/ة/g, "ه").replace(/ى/g, "ي")
    .replace(/['’‘`´]/g, apostrophe)
    .replace(/[^\p{L}\p{N}\p{M}]+/gu, " ")
    .trim();
}

function tokens(text, stop, apostrophe) {
  return normalize(text, apostrophe).split(" ").filter((t) => t && !stop.has(t));
}

function levenshtein1(a, b) {
  if (Math.abs(a.length - b.length) > 1) return false;
  let i = 0, j = 0, edits = 0;
  while (i < a.length && j < b.length) {
    if (a[i] === b[j]) { i++; j++; continue; }
    if (++edits > 1) return false;
    if (a.length > b.length) i++;
    else if (a.length < b.length) j++;
    else { i++; j++; }
  }
  return edits + (a.length - i) + (b.length - j) <= 1;
}

/** Sözcük eşleşmesi: aynı, ek almış ("kurarim" ~ "kurar"), tek harf yazım hatası; Tayca (boşluksuz) içinde geçme. */
function tokenMatch(t, m) {
  if (t === m) return true;
  if (THAI.test(t)) return m.includes(t);
  const short = t.length <= m.length ? t : m;
  const long = short === t ? m : t;
  if (short.length >= 4 && long.startsWith(short)) return true;
  return short.length >= 5 && levenshtein1(t, m);
}

export function scriptLang(text, appLang) {
  if (THAI.test(text)) return "th";
  if (DEVANAGARI.test(text)) return "hi";
  if (BENGALI.test(text)) return "bn";
  if (ARABIC.test(text)) return appLang === "ur" ? "ur" : "ar";
  return null;
}

const flat = (text) => String(text ?? "").replace(/\s+/g, " ").trim();

function platformGroup(platform) {
  if (platform === "mac" || platform === "windows" || platform === "linux") return "desktop";
  return platform;
}

/** Hazır cevap kütüphanesini eşlemeye hazırlar (bir kez). */
export function prepareLibrary(data) {
  const stop = new Set(Object.values(data.stop ?? {}).flat().map((w) => normalize(w)).filter(Boolean));
  const guards = new Set((data.guards?.words ?? []).map((w) => normalize(w)));
  const byReply = new Map();
  const byId = new Map((data.entries ?? []).map((e) => [e.id, e]));
  const entries = (data.entries ?? []).map((raw) => {
    // replyOf: başka bir girdinin cevabını paylaşır (ör. "Samsung adımlarını anlatayım mı?" → "evet" → 1. adım);
    // önceki-mesaj eşlemesinde asıl girdi sayılır.
    const source = raw.replyOf ? byId.get(raw.replyOf) : null;
    const entry = source ? { ...raw, reply: source.reply, variants: source.variants } : raw;
    const texts = source ? [] : [[entry.reply ?? {}, null], ...Object.entries(entry.variants ?? {}).map(([p, r]) => [r, p])];
    for (const [replies] of texts) {
      for (const [lang, text] of Object.entries(replies)) byReply.set(flat(text), { id: entry.id, lang });
    }
    const triggers = [];
    for (const [lang, list] of Object.entries(entry.triggers ?? {})) {
      for (const phrase of list) {
        const words = [...new Set(tokens(phrase, stop, ""))];
        if (words.length) triggers.push({ lang, words });
      }
    }
    return { ...entry, triggers, after: entry.after ? new Set(entry.after) : null };
  });
  const openers = new Set(entries.filter((e) => e.opener).map((e) => e.id));
  return { entries, stop, guards, byReply, openers };
}

/** Kullanıcının mesajı bir tetikleyiciyle ne kadar örtüşüyor. */
function score(trigger, words, joined) {
  const pool = [...words, ...joined];
  const matched = trigger.words.filter((t) => pool.some((m) => tokenMatch(t, m)));
  const coverage = matched.length / trigger.words.length;
  let extras = words.filter((m) => !trigger.words.some((t) => tokenMatch(t, m)));
  // Tayca boşluksuz yazılır: tetikleyicinin dışında kalan harf sayısından sözcük tahmini.
  if (trigger.words.some((t) => THAI.test(t))) {
    const left = words.join("").length - matched.join("").length;
    extras = Array.from({ length: Math.max(0, Math.round(left / 4)) });
  }
  return { coverage, extras, matched, value: coverage + 0.02 * matched.length - 0.08 * extras.length };
}

/**
 * Sohbeti hazır cevaplarla eşler. Döner: null ya da { id, lang, reply, direct, score }.
 * direct: model çağırmadan verilebilir; değilse cevap modele ipucu olarak verilir.
 */
export function matchAnswer(library, input) {
  const messages = input.messages ?? [];
  const last = messages[messages.length - 1];
  if (!last || last.role !== "user" || !String(last.text ?? "").trim()) return null;
  const appLang = baseLang(input.language);

  // Önceki Nino mesajı bir hazır cevapsa: hangisi ve hangi dilde.
  const previous = messages.length >= 3 && messages[messages.length - 2]?.role === "assistant"
    ? library.byReply.get(flat(messages[messages.length - 2].text)) ?? null : null;
  // Selamlaşma ("opener") cevabından sonraki mesaj ilk soru sayılır ("merhaba" → "PS5 + TV + telefon").
  const first = messages.length === 1 || Boolean(previous && library.openers.has(previous.id) && messages.length === 3);
  const anytime = library.entries.some((e) => e.anytime);
  if (!first && !previous && !anytime) return null;

  const words = tokens(last.text, library.stop, " ");
  const all = tokens(last.text, new Set(), " ");
  const joined = tokens(last.text, library.stop, "").filter((w) => !words.includes(w));
  if (!words.length) return null;

  const candidates = [];
  for (const entry of library.entries) {
    if (entry.after ? !(previous && entry.after.has(previous.id)) : !(first || entry.anytime)) continue;
    let best = null;
    for (const trigger of entry.triggers) {
      const s = score(trigger, words, joined);
      if (s.coverage === 0) continue;
      if (!best || s.value > best.value + 1e-9 || (Math.abs(s.value - best.value) < 1e-9 && trigger.lang === appLang)) {
        best = { ...s, trigger };
      }
    }
    if (best) candidates.push({ entry, ...best });
  }
  if (!candidates.length) return null;
  candidates.sort((a, b) => b.value - a.value);
  const top = candidates[0];

  const lang = top.trigger.lang === "*"
    ? (previous?.lang ?? (top.entry.reply?.[appLang] ? appLang : null) ?? scriptLang(last.text, appLang) ?? "en")
    : top.trigger.lang;
  const group = platformGroup(input.platform);
  const reply = top.entry.variants?.[group]?.[lang] ?? top.entry.reply?.[lang] ?? null;
  const hintText = reply ?? top.entry.variants?.[group]?.en ?? top.entry.reply?.en ?? top.entry.reply?.tr ?? null;

  const extraWords = top.extras;
  const unmatched = (w) => !top.trigger.words.some((t) => tokenMatch(t, w));
  const blocked = all.some((w) => library.guards.has(w) && unmatched(w))
    || (!top.entry.allowDigits && extraWords.some((w) => /\d/.test(w)))
    // Yıl ("Samsung 2014 model"): desteğin yıl sınırı var, karar modele.
    || all.some((w) => /^(19|20)\d\d$/.test(w))
    || words.length > MAX_DIRECT_WORDS
    || messages.some((m) => m.images?.length);
  // Başka bir girdi de aynı güçte eşleşiyorsa (ör. iki marka adı) karar modele kalır.
  const rival = candidates.find((c) => c.entry !== top.entry && c.coverage === 1 && c.value >= top.value - 0.01)
    // İlk mesajda marka adı da geçiyorsa ("PS5 iPhone Google TV") "markan ne?" diye soran cevap uymaz.
    || (first && library.entries.some((e) => e.after && e !== top.entry
      && e.triggers.some((t) => t.lang === "*" && score(t, words, joined).coverage === 1)));
  // Tek sözcüklü tetikleyici ilk mesajda yalnız tek başına yazılınca ("switch" evet, "switch user" hayır).
  const maxExtra = top.entry.maxExtra ?? (top.trigger.words.length === 1 && !top.entry.after ? 0 : 1);
  const direct = Boolean(reply) && top.coverage === 1 && extraWords.length <= maxExtra && !blocked && !rival;

  // İpucu: tetikleyicinin tamamı (tek sözcüklüyse kısa mesajda) ya da en az iki sözcüğüyle üçte ikisi geçiyor.
  const hint = top.coverage === 1 ? (top.trigger.words.length >= 2 || words.length <= 3)
    : top.coverage >= 0.66 && top.matched.length >= 2;
  if (!direct && !hint) return null;
  // Sohbetin ortasında yalnız "her yerde" girdisi, yalnız fazla sözcüksüz kesin eşleşme (bağlam modelde).
  if (!first && !top.entry.after && (!direct || extraWords.length > 0)) return null;
  if (!hintText) return null;
  return { id: top.entry.id, lang, reply: direct ? reply : hintText, direct, score: Math.round(top.value * 100) / 100 };
}
