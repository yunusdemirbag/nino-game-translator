// SPDX-License-Identifier: AGPL-3.0-only
// Sık sorulan sorular: assistant/sss.json → docs/SSS.md (Türkçe), docs/SSS.en.md, docs/SSS.ar.md.
// Kaynak, Nino'ya Sor'un gerçek sohbetlerinden çıkan konulardır (yalnız konu ve genelleştirilmiş soru). `npm run sss`.
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const docs = join(here, "..", "..", "docs");
const { topics } = JSON.parse(readFileSync(join(here, "..", "assistant", "sss.json"), "utf8"));

const GROUPS = {
  "TV türleri": { en: "TV types and the TV app", ar: "أنواع التلفاز وتطبيق التلفاز" },
  "PS5 bağlantısı": { en: "Connecting to the PS5", ar: "الاتصال بجهاز PS5" },
  "Altyazı": { en: "Subtitles", ar: "الترجمة على الشاشة" },
  "Xbox bağlantısı": { en: "Connecting to the Xbox", ar: "الاتصال بجهاز Xbox" },
  "Uygulama sorunları": { en: "App problems (Windows, Mac, iPhone, Android)", ar: "مشاكل التطبيق (ويندوز، ماك، آيفون، أندرويد)" },
  "Kurulum (genel)": { en: "Setup in general", ar: "الإعداد بشكل عام" },
  "Oyun desteği": { en: "Supported games", ar: "الألعاب المدعومة" },
  "Çeviri kalitesi / API": { en: "Translation, language packs and API keys", ar: "الترجمة وحزم اللغات ومفاتيح API" },
  "Gizlilik / hesap": { en: "Privacy and accounts", ar: "الخصوصية والحسابات" },
  "İstekler": { en: "Requests and things Nino doesn't do yet", ar: "طلبات وأشياء لا يفعلها Nino بعد" },
};
const TEXT = {
  tr: { file: "SSS.md", title: "Nino: Sık Sorulan Sorular", intro: "Bu sayfa, uygulamadaki Nino'ya Sor robotuna en çok sorulan soruların cevaplarıdır (en sık sorulandan aşağı doğru). Cevaplar güncel uygulamaların (V4.5) menü adlarıyla yazıldı. Burada bulamazsan uygulamada Nino'ya Sor'a yaz ya da Ayarlar'daki Sorun Bildir'i kullan.", shot: "Ekran görüntüsü eklenecek", other: "Diğer diller", toc: "İçindekiler" },
  en: { file: "SSS.en.md", title: "Nino: Frequently Asked Questions", intro: "These are the answers to the questions people ask the in-app Ask Nino robot most often (most frequent first). Menu names are those of the current apps (V4.5); on screen they appear in your app's language. If your question isn't here, ask Nino in the app or use Report a problem in Settings.", shot: "Screenshot to be added", other: "Other languages", toc: "Contents" },
  ar: { file: "SSS.ar.md", title: "Nino: الأسئلة الشائعة", intro: "هذه إجابات أكثر الأسئلة التي يسألها المستخدمون لروبوت «اسأل Nino» داخل التطبيق (من الأكثر تكرارًا إلى الأقل). أسماء القوائم هي أسماء التطبيقات الحالية (V4.5). إذا لم تجد سؤالك هنا، اسأل Nino في التطبيق أو استخدم «الإبلاغ عن مشكلة» في الإعدادات.", shot: "ستُضاف لقطة شاشة", other: "لغات أخرى", toc: "المحتويات" },
};

const groupTotal = new Map();
for (const t of topics) groupTotal.set(t.group, (groupTotal.get(t.group) ?? 0) + t.count);
const groups = [...groupTotal.keys()].sort((a, b) => groupTotal.get(b) - groupTotal.get(a));
// GitHub'ın başlık bağlantısı: küçük harf, noktalama atılır, her boşluk bir tire.
const slug = (s) => s.toLowerCase().replace(/[^\p{L}\p{N}\p{M}\s-]/gu, "").replace(/\s/g, "-");

for (const [lang, t] of Object.entries(TEXT)) {
  const title = (g) => (lang === "tr" ? g : GROUPS[g]?.[lang] ?? g);
  const links = Object.entries(TEXT).filter(([l]) => l !== lang).map(([, o]) => `[${o.title}](${o.file})`).join(" · ");
  let out = `<!-- Üretilen dosya: nino-pool/scripts/build-sss.mjs (kaynak nino-pool/assistant/sss.json). Elle değiştirmeyin. -->\n`;
  if (lang === "ar") out += `<div dir="rtl">\n\n`;
  out += `# ${t.title}\n\n${t.intro}\n\n${t.other}: ${links}\n\n## ${t.toc}\n\n`;
  for (const g of groups) out += `- [${title(g)}](#${slug(title(g))})\n`;
  for (const g of groups) {
    out += `\n## ${title(g)}\n`;
    for (const topic of topics.filter((x) => x.group === g).sort((a, b) => b.count - a.count)) {
      out += `\n### ${topic.question[lang]}\n\n${topic.reply[lang].trim()}\n\n> 📷 ${t.shot}: \`docs/gorseller/sss/${topic.id}.png\`\n`;
    }
  }
  if (lang === "ar") out += `\n</div>\n`;
  writeFileSync(join(docs, t.file), out);
}
console.log(`SSS: ${topics.length} soru, ${groups.length} bölüm`);
