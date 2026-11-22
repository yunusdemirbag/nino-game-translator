// SPDX-License-Identifier: AGPL-3.0-only
// Nino otomatik teşhis (tarif: NinoCore docs/tarif/otomatik-teshis.md). Uygulamaların bekçisi bir sorun fark edince
// ölçüm kanalıyla ("k": "diag") kural, sebep kodu, sayısal durum ve kodlu iz gönderir. Burada: doğrulama, sınırlar,
// imzaya göre gruplama, panel listeleri (en sık, yeni çıkan, sürüm sonrası artış), günlük özet ve yardımcı modelle
// kısa Türkçe özet. Serbest metin alınmaz.
import { canonicalGame, gameName } from "./games.js";

import { localDayStart } from "./stats.js";

export const DIAG_LIMITS = {
  perInstallDay: 10,
  perRuleDay: 3,
  samplesPerSignatureDay: 3,
  maxStateKeys: 30,
  maxTrail: 40,
  maxVersions: 6,
  summariesPerRun: 10,
};

const RULE = /^[a-z0-9_.]{1,40}$/;
const CODE = /^[A-Za-z0-9_.$-]{1,64}$/;
const SHORT = /^[A-Za-z0-9_.$-]{1,40}$/;
const KEY = /^[A-Za-z0-9_]{1,24}$/;
const VERSION = /^[0-9A-Za-z.+-]{1,24}$/;
const MODEL = /^[A-Za-z0-9][A-Za-z0-9 ,._()+-]{0,59}$/;
const GAME = /^[a-z0-9][a-z0-9._-]{0,63}$/;
const SEVERITIES = new Set(["info", "warn", "error"]);
const TV_BRANDS = new Set(["androidtv", "samsung", "lg"]);

/** Teşhis cümleleri (tarifteki tabloyla aynı). Uygulamalar kendi dillerinde aynı anlamı yazar. */
export const DIAG_TEXT = {
  "ps5.no_return": {
    title: "PS5 koptu, geri gelmedi",
    network_lost: "Cihazın ağ bağlantısı gitti; PS5'e yeniden ulaşılamadı.",
    ps5_standby: "PS5 dinlenme moduna geçti.",
    ps5_closed: "PS5 Remote Play oturumunu kapattı.",
    kicked: "Başka bir cihaz PS5'e bağlandı.",
    timeout: "PS5'ten veri gelmedi; ağ yavaş ya da PS5 yanıt vermiyor.",
    stalled: "Görüntü durdu ve toparlanmadı.",
  },
  "tv.flapping": {
    title: "TV bağlantısı tekrar tekrar kopuyor",
    write_error: "TV'ye gönderim tekrar tekrar başarısız oldu.",
    timeout: "TV bir süre yanıt vermedi; Wi-Fi zayıf olabilir.",
    closed: "TV bağlantıyı kapatıyor.",
    resume: "TV uygulaması arka plana gidip geri geliyor.",
    network_change: "Ağ değişiyor (Wi-Fi ↔ kablo ya da adres değişti).",
    replaced: "TV bağlantısının yerini tekrar tekrar yeni bir bağlantı alıyor (TV yeniden bağlanıyor ya da başka cihaza geçiyor).",
    mixed: "TV bağlantısı farklı sebeplerle kopuyor.",
  },
  "ocr.silent": {
    title: "Görüntü geliyor ama yazı okunmuyor",
    video_black: "Görüntü kararık ya da donuk; altyazı okunamıyor.",
    region_wrong: "Elle seçilen okuma alanında yazı yok.",
    no_text: "Uzun süredir ekranda okunacak yazı bulunamadı.",
  },
  "ocr.stalled": {
    title: "Yazı tanıma ya da görüntü takıldı",
    ocr_hang: "Yazı tanıma yanıt vermiyor.",
    frames_stopped: "PS5'ten görüntü karesi gelmiyor.",
    decoder: "Görüntü çözücü takıldı.",
  },
  "tr.slow": {
    title: "Çeviri gecikmesi yüksek",
    provider_slow: "Seçilen çeviri hizmeti yavaş yanıt veriyor.",
    pool_slow: "Nino çeviri havuzu yavaş yanıt veriyor.",
    device_busy: "Cihaz yoğun; yazı tanıma da yavaşladı.",
    network_slow: "İnternet bağlantısı yavaş.",
  },
  "tr.errors": {
    title: "Çeviri hizmeti sık hata veriyor",
    quota: "Çeviri hizmetinin kullanım hakkı doldu.",
    auth: "Çeviri anahtarı kabul edilmiyor.",
    offline: "İnternet yok; çeviri hizmetine ulaşılamıyor.",
    server: "Çeviri hizmeti hata veriyor.",
    timeout: "Çeviri hizmeti zamanında yanıt vermiyor.",
  },
  "app.hang": { title: "Uygulama askıda kaldı", main_thread: "Uygulama birkaç saniye donup kaldı." },
  "app.resources": {
    title: "Bellek ya da işlemci aşırı",
    memory_high: "Uygulama çok bellek kullanıyor.",
    cpu_high: "Uygulama işlemciyi uzun süre yoğun kullanıyor.",
    thermal: "Cihaz ısındı, sistem yavaşlatıyor.",
  },
  "pack.download": {
    title: "Oyun paketi indirilemedi",
    offline: "Oyun paketi internet olmadığı için inmedi.",
    http_4xx: "Oyun paketi sunucuda bulunamadı.",
    http_5xx: "Paket sunucusu hata veriyor.",
    corrupt: "İnen oyun paketi bozuk.",
    storage_full: "Cihazda yer kalmadı.",
  },
};

export function diagTitle(rule) {
  return DIAG_TEXT[rule]?.title ?? rule;
}

export function diagText(rule, cause) {
  return DIAG_TEXT[rule]?.[cause] ?? (cause === "unknown" ? "Sebep belirlenemedi." : cause);
}

const match = (v, re) => (typeof v === "string" && re.test(v) ? v : "");

/** Bir "diag" olayını doğrular; serbest metin taşıyabilecek her şey atılır. Geçersiz kuralda null. */
export function cleanDiag(e) {
  const rule = match(e?.rule, RULE);
  if (!rule) return null;
  const cause = match(e.cause, SHORT) || "unknown";
  const sev = SEVERITIES.has(e.sev) ? e.sev : "warn";
  const state = {};
  if (e.state && typeof e.state === "object" && !Array.isArray(e.state)) {
    for (const [k, v] of Object.entries(e.state)) {
      if (Object.keys(state).length >= DIAG_LIMITS.maxStateKeys) break;
      if (!KEY.test(k)) continue;
      if (typeof v === "boolean" || (typeof v === "number" && Number.isFinite(v) && Math.abs(v) < 1e12)) state[k] = v;
      else if (typeof v === "string" && SHORT.test(v)) state[k] = v;
    }
  }
  const trail = [];
  if (Array.isArray(e.trail)) {
    for (const step of e.trail.slice(-DIAG_LIMITS.maxTrail)) {
      if (!Array.isArray(step) || step.length < 2) continue;
      const [at, code, n] = step;
      if (!Number.isFinite(at) || at < -3600 || at > 0 || !match(code, CODE)) continue;
      const clean = [Math.round(at), code];
      if (Number.isFinite(n) && Math.abs(n) < 1e9) clean.push(n);
      trail.push(clean);
    }
  }
  const tv = {};
  if (e.tv && typeof e.tv === "object") {
    if (TV_BRANDS.has(e.tv.brand)) tv.brand = e.tv.brand;
    if (match(e.tv.model, MODEL)) tv.model = e.tv.model;
    if (match(e.tv.app, VERSION)) tv.app = e.tv.app;
  }
  const ver = {};
  if (e.ver && typeof e.ver === "object") {
    for (const [k, v] of Object.entries(e.ver)) {
      if (Object.keys(ver).length >= DIAG_LIMITS.maxVersions) break;
      if (KEY.test(k) && match(v, VERSION)) ver[k] = v;
    }
  }
  return { rule, cause, sev, state, trail, tv, game: canonicalGame(match(e.game, GAME)), ver };
}

/** İmzadaki model: TV kurallarında TV modeli, öbürlerinde cihaz modeli. */
export function signatureModel(diag, device) {
  return diag.rule.startsWith("tv.") ? diag.tv.model ?? "" : device;
}

/**
 * Bir parçadaki teşhisler için yazma komutları. Kurulum başına günlük sınırlar burada uygulanır; aşanlar sessizce
 * atılır (öbür olayları bekletmesin). Tablolar yoksa teşhisler atılır, parçanın geri kalanı yine yazılır.
 */
export async function diagStatements(db, { day, now, install, platform, app, os, device }, diags) {
  if (diags.length === 0) return { statements: [], accepted: 0, dropped: 0 };
  let seen;
  try {
    seen = (await db.prepare("SELECT rule, SUM(n) AS n FROM diag_seen WHERE day = ? AND install = ? GROUP BY rule")
      .bind(day, install).all()).results;
  } catch {
    return { statements: [], accepted: 0, dropped: diags.length };
  }
  const perRule = new Map(seen.map((r) => [r.rule, Number(r.n) || 0]));
  let total = [...perRule.values()].reduce((a, b) => a + b, 0);
  const statements = [];
  const samples = new Map();
  let accepted = 0;
  for (const d of diags) {
    const used = perRule.get(d.rule) ?? 0;
    if (total >= DIAG_LIMITS.perInstallDay || used >= DIAG_LIMITS.perRuleDay) continue;
    perRule.set(d.rule, used + 1);
    total++;
    accepted++;
    const model = signatureModel(d, device);
    statements.push(
      db.prepare(`INSERT INTO diag_daily (day, rule, platform, app, model, cause, n) VALUES (?, ?, ?, ?, ?, ?, 1)
        ON CONFLICT (day, rule, platform, app, model, cause) DO UPDATE SET n = n + 1`)
        .bind(day, d.rule, platform, app, model, d.cause),
      db.prepare(`INSERT INTO diag_seen (day, install, rule, platform, app, model, n) VALUES (?, ?, ?, ?, ?, ?, 1)
        ON CONFLICT (day, install, rule, platform, app, model) DO UPDATE SET n = n + 1`)
        .bind(day, install, d.rule, platform, app, model),
      db.prepare(`INSERT INTO diag_groups (rule, platform, model, first_seen, last_seen, first_app, total) VALUES (?, ?, ?, ?, ?, ?, 1)
        ON CONFLICT (rule, platform, model) DO UPDATE SET last_seen = excluded.last_seen, total = total + 1`)
        .bind(d.rule, platform, model, now, now, app),
    );
    // Örnek: imza başına günde en çok 3 (sayım veritabanından + bu parçadakiler).
    const sig = `${d.rule}\u0000${model}`;
    if (!samples.has(sig)) {
      const row = await db.prepare("SELECT COUNT(*) AS n FROM diag_samples WHERE day = ? AND rule = ? AND platform = ? AND app = ? AND model = ?")
        .bind(day, d.rule, platform, app, model).first();
      samples.set(sig, Number(row?.n) || 0);
    }
    if (samples.get(sig) < DIAG_LIMITS.samplesPerSignatureDay) {
      samples.set(sig, samples.get(sig) + 1);
      statements.push(db.prepare(
        `INSERT INTO diag_samples (at, day, rule, cause, sev, platform, app, model, os, tv, game, state, trail, ver)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      ).bind(now, day, d.rule, d.cause, d.sev, platform, app, model, os, JSON.stringify(d.tv), d.game,
        JSON.stringify(d.state), JSON.stringify(d.trail), JSON.stringify(d.ver)));
    }
  }
  return { statements, accepted, dropped: diags.length - accepted };
}

/** Sürümleri sayıca karşılaştırır: 4.10.0 > 4.9.2; ön sürüm eki (-beta.2) aynı sayıda daha küçük. */
export function compareVersions(a, b) {
  const parse = (v) => {
    const [main, pre] = String(v).split("-", 2);
    return { parts: main.split(/[.+]/).map((x) => Number.parseInt(x, 10) || 0), pre: pre ?? null };
  };
  const x = parse(a);
  const y = parse(b);
  for (let i = 0; i < Math.max(x.parts.length, y.parts.length); i++) {
    const d = (x.parts[i] ?? 0) - (y.parts[i] ?? 0);
    if (d !== 0) return d;
  }
  if (x.pre === y.pre) return 0;
  if (x.pre === null) return 1;
  if (y.pre === null) return -1;
  return x.pre.localeCompare(y.pre, "en", { numeric: true });
}

/** Sürüm sonrası artış için alt sınırlar. */
export const REGRESSION = { minLaunches: 20, minReports: 3, factor: 2 };
const FRESH_SECONDS = 48 * 3600;

/** Panelin "Otomatik teşhis" bölümü. Tablolar yoksa null. */
export async function diagStats(db, now, since) {
  const all = async (sql, ...args) => (await db.prepare(sql).bind(...args).all()).results;
  let rows, installs, groups, launches;
  try {
    [rows, installs, groups, launches] = await Promise.all([
      all("SELECT rule, platform, app, model, cause, SUM(n) AS n FROM diag_daily WHERE day >= ? GROUP BY rule, platform, app, model, cause", since),
      all("SELECT rule, platform, model, COUNT(DISTINCT install) AS n FROM diag_seen GROUP BY rule, platform, model"),
      all("SELECT rule, platform, model, first_seen, last_seen, first_app, total, summary FROM diag_groups WHERE last_seen >= ?", since),
      all("SELECT platform, app, SUM(n) AS n FROM ev_daily WHERE day >= ? AND kind = 'launch' GROUP BY platform, app", since),
    ]);
  } catch {
    return null;
  }
  const key = (r) => `${r.rule}\u0000${r.platform}\u0000${r.model}`;
  const installsOf = new Map(installs.map((r) => [key(r), Number(r.n) || 0]));
  const groupOf = new Map(groups.map((g) => [key(g), g]));
  const top = new Map();
  for (const r of rows) {
    const n = Number(r.n) || 0;
    const g = top.get(key(r)) ?? { rule: r.rule, platform: r.platform, model: r.model, n: 0, causes: {}, apps: {} };
    g.n += n;
    g.causes[r.cause] = (g.causes[r.cause] ?? 0) + n;
    g.apps[r.app] = (g.apps[r.app] ?? 0) + n;
    top.set(key(r), g);
  }
  const decorate = (g) => {
    const info = groupOf.get(key(g));
    const cause = Object.entries(g.causes ?? {}).sort((a, b) => b[1] - a[1])[0]?.[0] ?? "unknown";
    return {
      ...g, title: diagTitle(g.rule), cause, text: diagText(g.rule, cause), installs: installsOf.get(key(g)) ?? 0,
      firstSeen: info?.first_seen ?? null, lastSeen: info?.last_seen ?? null, firstApp: info?.first_app ?? "",
      summary: info?.summary ?? "", fresh: info ? now - info.first_seen < FRESH_SECONDS : false,
    };
  };
  const list = [...top.values()].map(decorate).sort((a, b) => b.n - a.n);

  // Sürüm sonrası artış: her platformda yeterince açılan en yeni iki sürüm, açılış başına bildirim oranı.
  const launchOf = new Map(launches.map((r) => [`${r.platform}\u0000${r.app}`, Number(r.n) || 0]));
  const byPlatform = new Map();
  for (const r of launches) {
    if (!r.app || (Number(r.n) || 0) < REGRESSION.minLaunches) continue;
    const v = byPlatform.get(r.platform) ?? [];
    v.push(r.app);
    byPlatform.set(r.platform, v);
  }
  const perVersion = new Map();
  for (const r of rows) {
    const k = `${r.platform}\u0000${r.rule}\u0000${r.app}`;
    perVersion.set(k, (perVersion.get(k) ?? 0) + (Number(r.n) || 0));
  }
  const regressions = [];
  for (const [platform, versions] of byPlatform) {
    if (versions.length < 2) continue;
    versions.sort(compareVersions);
    const [oldApp, newApp] = versions.slice(-2);
    const rules = new Set(rows.filter((r) => r.platform === platform).map((r) => r.rule));
    for (const rule of rules) {
      const nNew = perVersion.get(`${platform}\u0000${rule}\u0000${newApp}`) ?? 0;
      const nOld = perVersion.get(`${platform}\u0000${rule}\u0000${oldApp}`) ?? 0;
      const rateNew = nNew / launchOf.get(`${platform}\u0000${newApp}`);
      const rateOld = nOld / launchOf.get(`${platform}\u0000${oldApp}`);
      if (nNew >= REGRESSION.minReports && rateNew >= REGRESSION.factor * rateOld) {
        regressions.push({ platform, rule, title: diagTitle(rule), newApp, oldApp, nNew, nOld, rateNew, rateOld,
          factor: rateOld > 0 ? rateNew / rateOld : null });
      }
    }
  }
  regressions.sort((a, b) => (b.factor ?? Infinity) - (a.factor ?? Infinity) || b.nNew - a.nNew);

  return {
    total: list.reduce((s, g) => s + g.n, 0),
    top: list.slice(0, 20),
    fresh: list.filter((g) => g.fresh).slice(0, 15),
    regressions: regressions.slice(0, 15),
  };
}

/** /teshis sayfası: bir günün grupları, sebepleri, örnekleri ve özetleri. `day`: Türkiye saatiyle günün başı. */
export async function diagDaily(db, now, day = localDayStart(now)) {
  const all = async (sql, ...args) => (await db.prepare(sql).bind(...args).all()).results;
  try {
    const [rows, samples, groups] = await Promise.all([
      all("SELECT rule, platform, app, model, cause, n FROM diag_daily WHERE day = ?", day),
      all("SELECT at, rule, cause, sev, platform, app, model, os, tv, game, state, trail, ver FROM diag_samples WHERE day = ? ORDER BY at DESC LIMIT 300", day),
      all("SELECT rule, platform, model, first_seen, first_app, total, summary, summary_at FROM diag_groups"),
    ]);
    const key = (r) => `${r.rule}\u0000${r.platform}\u0000${r.model}`;
    const info = new Map(groups.map((g) => [key(g), g]));
    const out = new Map();
    for (const r of rows) {
      const g = out.get(key(r)) ?? { rule: r.rule, platform: r.platform, model: r.model, title: diagTitle(r.rule), n: 0,
        causes: [], apps: {}, samples: [] };
      g.n += r.n;
      g.causes.push({ cause: r.cause, text: diagText(r.rule, r.cause), app: r.app, n: r.n });
      g.apps[r.app] = (g.apps[r.app] ?? 0) + r.n;
      out.set(key(r), g);
    }
    for (const s of samples) {
      const g = out.get(key(s));
      if (!g || g.samples.length >= 3) continue;
      const parse = (v) => { try { return JSON.parse(v); } catch { return {}; } };
      g.samples.push({ ...s, gameName: gameName(s.game), text: diagText(s.rule, s.cause), tv: parse(s.tv), state: parse(s.state), trail: parse(s.trail), ver: parse(s.ver) });
    }
    const list = [...out.values()].map((g) => {
      const i = info.get(key(g));
      return { ...g, firstSeen: i?.first_seen ?? null, firstApp: i?.first_app ?? "", summary: i?.summary ?? "",
        summaryAt: i?.summary_at ?? 0, fresh: i ? now - i.first_seen < FRESH_SECONDS : false };
    }).sort((a, b) => b.n - a.n);
    return { ok: true, ready: true, day, total: list.reduce((s, g) => s + g.n, 0), groups: list };
  } catch {
    return { ok: true, ready: false, day, total: 0, groups: [] };
  }
}

const SUMMARY_SYSTEM = `Sen Nino'nun (PS5 altyazı çevirmeni) geliştiricisine yardım eden bir mühendissin. Sana bir
otomatik teşhis grubunun teknik verisi verilecek: kural, sebep kodları, uygulama sürümleri, cihaz/TV modeli, örnek
bildirimlerin sayısal durumu ve kodlu izi (her adım: kaç saniye önce, kod, sayı). En çok 3 kısa cümleyle Türkçe yaz:
ne oluyor, muhtemel sebep, ne yapılmalı. Uydurma; veride yoksa "veri yetmiyor" de. JSON cevabın "reply" alanına yaz.`;

/**
 * Değişen grupları (son özetten beri yeni bildirim gelen) yardımcı modelle özetler; en çok `limit` grup.
 * `ask(env, system, messages)` → { reply }. Hata olursa o grup atlanır.
 */
export async function summarizeDiagnoses(db, env, now, ask, { limit = DIAG_LIMITS.summariesPerRun } = {}) {
  let groups;
  try {
    groups = (await db.prepare(
      `SELECT rule, platform, model, total, first_app FROM diag_groups
       WHERE total > summary_n AND last_seen >= ? ORDER BY total - summary_n DESC LIMIT ?`,
    ).bind(now - 7 * 86400, limit).all()).results;
  } catch {
    return { summarized: 0, failed: 0 };
  }
  let summarized = 0;
  let failed = 0;
  for (const g of groups) {
    try {
      const causes = (await db.prepare(
        `SELECT app, cause, SUM(n) AS n FROM diag_daily WHERE rule = ? AND platform = ? AND model = ? AND day >= ?
         GROUP BY app, cause ORDER BY n DESC LIMIT 20`,
      ).bind(g.rule, g.platform, g.model, localDayStart(now) - 6 * 86400).all()).results;
      const samples = (await db.prepare(
        `SELECT app, cause, sev, os, tv, game, state, trail, ver FROM diag_samples WHERE rule = ? AND platform = ? AND model = ?
         ORDER BY at DESC LIMIT 3`,
      ).bind(g.rule, g.platform, g.model).all()).results;
      const data = {
        kural: g.rule, kuralAdi: diagTitle(g.rule), platform: g.platform, model: g.model, toplam: g.total, ilkSurum: g.first_app,
        sebepler: causes.map((c) => ({ ...c, anlam: diagText(g.rule, c.cause) })),
        ornekler: samples.map((s) => ({ ...s, tv: JSON.parse(s.tv), state: JSON.parse(s.state), trail: JSON.parse(s.trail), ver: JSON.parse(s.ver) })),
      };
      const answer = await ask(env, SUMMARY_SYSTEM, [{ role: "user", text: JSON.stringify(data), images: [] }]);
      const text = String(answer?.reply ?? "").replace(/\s+/g, " ").trim().slice(0, 600);
      if (!text) throw new Error("empty");
      await db.prepare("UPDATE diag_groups SET summary = ?, summary_at = ?, summary_n = ? WHERE rule = ? AND platform = ? AND model = ?")
        .bind(text, now, g.total, g.rule, g.platform, g.model).run();
      summarized++;
    } catch {
      failed++;
    }
  }
  return { summarized, failed };
}

export async function pruneDiag(db, now) {
  const day = localDayStart(now);
  try {
    await db.batch([
      db.prepare("DELETE FROM diag_seen WHERE day < ?").bind(day - 3 * 86400),
      db.prepare("DELETE FROM diag_samples WHERE at < ?").bind(now - 30 * 86400),
      db.prepare("DELETE FROM diag_daily WHERE day < ?").bind(day - 400 * 86400),
      db.prepare("DELETE FROM diag_groups WHERE last_seen < ?").bind(now - 400 * 86400),
    ]);
  } catch {
    // Tablolar yoksa geç.
  }
}
