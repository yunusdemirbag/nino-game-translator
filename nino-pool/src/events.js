// SPDX-License-Identifier: AGPL-3.0-only
// Nino ölçüm: uygulamaların hata ve hız istatistikleri (tarif: NinoCore docs/tarif/olcum.md).
//   POST /v1/events          toplu olaylar (uygulamalar; isteğe bağlı gzip)
//   GET  /v1/events/stats    panelin "Sağlık" bölümü (yönetici anahtarıyla)
// Olaylar alınırken günlük özet tablolarına eklenir; tek tek saklanan yalnız son çökme ve hatalardır (kurulum kimliği
// olmadan). Altyazı metni, IP adresi ve kişisel bilgi alınmaz: serbest yazı alanı yoktur, kodlar sıkı karakter
// kuralıyla süzülür.
import { canonicalGame, mergeGameRows } from "./games.js";

import { saltedDigest } from "./key.js";
import { localDayStart } from "./stats.js";
import { cleanDiag, diagStatements, diagStats } from "./diag.js";

export const EVENT_LIMITS = {
  maxCompressed: 64 * 1024,
  maxInflated: 512 * 1024,
  maxEvents: 300,
  maxMetrics: 24,
  maxAgeSeconds: 7 * 86400,
  perInstallEvents: 1500,
  perInstallBatches: 60,
  recentPerBatch: 20,
};

/** Süre kovalarının üst sınırları (ms). Son kova (dizinin boyu) bunlardan uzun olanlar. */
export const MS_EDGES = [5, 10, 20, 35, 50, 75, 100, 150, 200, 300, 500, 750, 1000, 1500, 2000, 3000, 5000, 10000];
/** Saniyeyle ölçülenler (oturum süresi, kopmadan önceki bağlı kalma süresi). */
export const S_EDGES = [60, 300, 600, 1200, 1800, 3600, 7200, 14400];
const SECOND_METRICS = new Set(["session", "ps5.after", "tv.after"]);
export const edgesFor = (metric) => (SECOND_METRICS.has(metric) ? S_EDGES : MS_EDGES);

export const PLATFORMS = new Set(["mac", "windows", "linux", "android", "ios", "androidtv", "webos", "tizen"]);
const KINDS = new Set(["launch", "session", "crash", "error", "ps5_connect", "ps5_drop", "tv_connect", "tv_drop", "diag"]);
const TV_BRANDS = new Set(["androidtv", "samsung", "lg"]);
const VIAS = new Set(["lan", "remote", "xbox"]);
const PROTOS = new Set(["nino", "legacy"]);
const SOURCES = new Set(["remoteplay", "capture", "xbox", "screen"]);
const CHANNELS = new Set(["release", "beta", "dev"]);

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const CODE = /^[A-Za-z0-9_.$-]{1,64}$/;
const WHERE = /^[A-Za-z0-9_.:$<>+-]{1,120}$/;
const METRIC = /^[a-z0-9_.]{1,32}(:[a-z0-9_-]{1,24})?$/;
const GAME = /^[a-z0-9][a-z0-9._-]{0,63}$/;
const VERSION = /^[0-9A-Za-z.+-]{1,24}$/;
// Cihaz ve işletim sistemi: yalnız model kimliği ve sürüm biçimi (ASCII). Kesme işareti, Türkçe harf vb. varsa
// (ör. "Yunus'un MacBook'u": cihazın adı) hiç saklanmaz.
const OS = /^[A-Za-z][A-Za-z0-9 ._()-]{0,39}$/;
const DEVICE = /^[A-Za-z0-9][A-Za-z0-9 ,._()+-]{0,59}$/;

const CORS = { "access-control-allow-origin": "*" };
export const EVENTS_PREFLIGHT = {
  ...CORS,
  "access-control-allow-methods": "POST, OPTIONS",
  "access-control-allow-headers": "content-type, content-encoding",
  "access-control-max-age": "86400",
};
export const EVENTS_CORS = CORS;

const num = (v, d) => (v !== undefined && v !== "" && Number.isFinite(Number(v)) ? Number(v) : d);
const int = (v, lo, hi) => (Number.isInteger(v) && v >= lo && v <= hi ? v : null);
const pick = (v, set) => (typeof v === "string" && set.has(v) ? v : "");
const match = (v, re) => (typeof v === "string" && re.test(v) ? v : "");

const listOf = (v) => String(v ?? "").split(",").map((x) => x.trim()).filter((x) => /^[a-z0-9_.]{1,40}$/.test(x));
function limitsOf(v) {
  try {
    const o = JSON.parse(v ?? "{}");
    return Object.fromEntries(Object.entries(o).filter(([k, n]) => /^[A-Za-z0-9_.]{1,48}$/.test(k) && Number.isFinite(n)));
  } catch {
    return {};
  }
}

/** Uygulamaların uzaktan ölçüm ayarı (/v1/config ve /v1/events cevabında). */
export function telemetryConfig(env) {
  const sample = Math.min(1, Math.max(0, num(env.TELEMETRY_SAMPLE, 1)));
  return {
    enabled: env.TELEMETRY_ENABLED !== "0",
    sample,
    maxPerDay: Math.max(0, Math.floor(num(env.TELEMETRY_MAX_PER_DAY, 1000))),
    flushSeconds: Math.max(60, Math.floor(num(env.TELEMETRY_FLUSH_SECONDS, 600))),
    // Otomatik teşhis: kapatılan kurallar ve eşikler (tarif: otomatik-teshis.md). Uygulamalar bilmediği anahtarı atlar.
    diag: { off: listOf(env.TELEMETRY_DIAG_OFF), limits: limitsOf(env.TELEMETRY_DIAG_LIMITS) },
  };
}

/** Kova sırası: `v ≤ sınır` olan ilk kova; hepsinden büyükse son kova. */
export function bucketOf(value, edges) {
  for (let i = 0; i < edges.length; i++) if (value <= edges[i]) return i;
  return edges.length;
}

/**
 * Kova adetlerinden yüzdelik (p: 0–1): istenen sıranın düştüğü kovanın alt ve üst sınırı arasında doğrusal ara değer.
 * Son kovanın (ya da en büyük değerden yüksek sınırın) üst sınırı `peak`. Hiç değer yoksa null.
 */
export function percentile(counts, edges, peak, p) {
  const total = counts.reduce((a, b) => a + (b || 0), 0);
  if (total <= 0) return null;
  const rank = Math.max(1e-9, p * total);
  let cum = 0;
  for (let i = 0; i < counts.length; i++) {
    const c = counts[i] || 0;
    if (c > 0 && cum + c >= rank) {
      const lower = i === 0 ? 0 : edges[i - 1];
      let upper = i < edges.length ? edges[i] : Math.max(peak, lower);
      if (peak >= lower && peak < upper) upper = peak;
      return Math.round(lower + ((rank - cum) / c) * (upper - lower));
    }
    cum += c;
  }
  return Math.round(peak);
}

/** Gövdeyi okur; gzip ise (başlıktan bağımsız, ilk iki bayttan anlaşılır) sınırlı boyda açar. */
export async function readEventsBody(request) {
  const declared = Number.parseInt(request.headers.get("content-length") ?? "", 10);
  if (Number.isFinite(declared) && declared > EVENT_LIMITS.maxInflated) return { tooLarge: true };
  const raw = new Uint8Array(await request.arrayBuffer());
  let bytes = raw;
  if (raw.length >= 2 && raw[0] === 0x1f && raw[1] === 0x8b) {
    if (raw.length > EVENT_LIMITS.maxCompressed) return { tooLarge: true };
    const out = await gunzip(raw, EVENT_LIMITS.maxInflated);
    if (out.tooLarge || out.bad) return out;
    bytes = out.bytes;
  } else if (raw.length > EVENT_LIMITS.maxInflated) {
    return { tooLarge: true };
  }
  try {
    return { value: JSON.parse(new TextDecoder().decode(bytes)) };
  } catch {
    return { bad: true };
  }
}

async function gunzip(bytes, max) {
  const reader = new Blob([bytes]).stream().pipeThrough(new DecompressionStream("gzip")).getReader();
  const chunks = [];
  let size = 0;
  try {
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > max) {
        await reader.cancel().catch(() => {});
        return { tooLarge: true };
      }
      chunks.push(value);
    }
  } catch {
    return { bad: true };
  }
  const out = new Uint8Array(size);
  let at = 0;
  for (const c of chunks) {
    out.set(c, at);
    at += c.byteLength;
  }
  return { bytes: out };
}

/** Bir oturumun histogramı geçerli mi: tam sayı adetler, toplamı `n`, en çok kova sayısı kadar. */
function cleanHistogram(raw, edges) {
  if (!raw || typeof raw !== "object" || !Array.isArray(raw.h)) return null;
  const n = int(raw.n, 1, 10_000_000);
  if (n === null || raw.h.length > edges.length + 1) return null;
  let total = 0;
  for (const c of raw.h) {
    if (!Number.isInteger(c) || c < 0) return null;
    total += c;
  }
  if (total !== n) return null;
  const sum = Number.isFinite(raw.sum) && raw.sum >= 0 ? Math.round(raw.sum) : 0;
  const peak = Number.isFinite(raw.max) && raw.max >= 0 ? Math.round(raw.max) : 0;
  return { n, sum, peak, h: raw.h };
}

/** Bir parçanın olaylarını özet satırlarına çevirir (veritabanına dokunmaz). */
/** TV'nin kendisi gönderiyorsa (Android TV, webOS, Tizen) markası platformundan bellidir. */
const TV_PLATFORM_BRAND = { androidtv: "androidtv", webos: "lg", tizen: "samsung" };
/** Kopma nedenlerinin eş adları (istemciler farklı yazabiliyor). */
const DROP_ALIASES = { close: "closed", tv_closed: "closed" };
/** "Kısa sürede çok kopma" uyarısı: son 1 saatte en az 3 ya da son 6 saatte en az 6 kopma. */
export const TV_FLAP = { hour: 3, sixHours: 6 };

export function aggregate(events, now, { app = "", tv = "", platform = "", device = "" } = {}) {
  const tvSelf = TV_PLATFORM_BRAND[platform] ?? "";
  const tvLinks = []; // {kind, code, brand, model, tvApp, after, at}
  const diags = []; // otomatik teşhis (src/diag.js)
  const tvLink = (e, kind, code) => {
    const brand = pick(e.brand, TV_BRANDS) || tvSelf;
    const model = match(e.model, DEVICE) || (tvSelf ? device : "");
    const tvApp = match(e.tvApp, VERSION) || (tvSelf ? app : "");
    const after = kind === "drop" ? int(e.after, 0, 7 * 86400) : null;
    const at = Math.min(now, Math.max(now - 3 * 86400, Math.floor(e.t)));
    tvLinks.push({ kind, code, brand, model, tvApp, after, at });
  };
  const counts = new Map(); // app|kind|code|dim → n (çökme, çöken sürümün altına sayılır)
  const timings = new Map(); // metric → {n, sum, peak, h[]}
  const games = new Map(); // game → {sessions, seconds}
  const recent = [];
  let accepted = 0;
  let dropped = 0;

  const count = (kind, code, dim, n = 1, version = app) => {
    const key = `${version}\u0000${kind}\u0000${code}\u0000${dim}`;
    counts.set(key, (counts.get(key) ?? 0) + n);
  };
  const timing = (metric, add) => {
    const edges = edgesFor(metric);
    let t = timings.get(metric);
    if (!t) timings.set(metric, (t = { n: 0, sum: 0, peak: 0, h: new Array(edges.length + 1).fill(0) }));
    t.n += add.n;
    t.sum += add.sum;
    t.peak = Math.max(t.peak, add.peak);
    add.h.forEach((c, i) => (t.h[i] += c));
  };
  const one = (metric, value) => {
    if (!Number.isFinite(value) || value < 0 || value > 1e9) return;
    const v = Math.round(value);
    const h = new Array(edgesFor(metric).length + 1).fill(0);
    h[bucketOf(v, edgesFor(metric))] = 1;
    timing(metric, { n: 1, sum: v, peak: v, h });
  };
  const remember = (kind, code, detail = "", version = app) => {
    if (recent.length < EVENT_LIMITS.recentPerBatch) recent.push({ kind, code, detail, app: version });
  };

  for (const e of events) {
    const ok = handleOne(e);
    if (ok) accepted++;
    else dropped++;
  }
  return { counts, timings, games, recent, tvLinks, diags, accepted, dropped };

  function handleOne(e) {
    if (!e || typeof e !== "object" || !KINDS.has(e.k)) return false;
    if (!Number.isFinite(e.t) || e.t < now - EVENT_LIMITS.maxAgeSeconds) return false;
    switch (e.k) {
      case "launch":
        count("launch", "", tv);
        if (e.ms !== undefined) one("launch", e.ms);
        return true;
      case "session": {
        const dur = int(e.dur, 0, 7 * 86400);
        if (dur === null) return false;
        count("session", "", pick(e.src, SOURCES));
        one("session", dur);
        const lines = int(e.lines, 0, 1_000_000);
        if (lines) count("lines", "", "", lines);
        const game = canonicalGame(match(e.game, GAME));
        if (game) {
          const g = games.get(game) ?? { sessions: 0, seconds: 0 };
          g.sessions += 1;
          g.seconds += dur;
          games.set(game, g);
        }
        if (e.h && typeof e.h === "object") {
          let used = 0;
          for (const [metric, raw] of Object.entries(e.h)) {
            if (used >= EVENT_LIMITS.maxMetrics || !METRIC.test(metric) || SECOND_METRICS.has(metric)) continue;
            const hist = cleanHistogram(raw, edgesFor(metric));
            if (!hist) continue;
            timing(metric, hist);
            used++;
          }
        }
        return true;
      }
      case "crash": {
        const code = match(e.code, CODE) || "unclean_exit";
        // Çökme, yeniden açılan sürümün değil çöken sürümün (`ver`) altına sayılır.
        const ver = match(e.ver, VERSION);
        count("crash", code, "", 1, ver || app);
        const up = int(e.up, 0, 365 * 86400);
        remember("crash", code, [match(e.where, WHERE), up !== null ? `up ${up}s` : ""].filter(Boolean).join(" · "), ver || app);
        return true;
      }
      case "error": {
        const code = match(e.code, CODE);
        if (!code) return false;
        const http = int(e.http, 100, 599);
        const n = int(e.n, 1, 10_000) ?? 1;
        count("error", code, http !== null ? String(http) : "", n);
        remember("error", code, [http !== null ? `http ${http}` : "", n > 1 ? `×${n}` : ""].filter(Boolean).join(" · "));
        return true;
      }
      case "ps5_connect":
      case "tv_connect": {
        const r = e.r === "ok" ? "ok" : match(e.r, CODE);
        if (!r) return false;
        const tv = e.k === "tv_connect";
        const dim = tv ? pick(e.brand, TV_BRANDS) || tvSelf : pick(e.via, VIAS);
        count(e.k, r, dim);
        if (tv) tvLink(e, "connect", r);
        if (tv && PROTOS.has(e.proto)) count("tv_proto", e.proto, dim);
        if (r === "ok") one(tv ? "tv.connect" : "ps5.connect", e.ms);
        else remember(e.k, r, dim);
        return true;
      }
      case "diag": {
        const d = cleanDiag(e);
        if (!d) return false;
        diags.push(d);
        return true;
      }
      case "ps5_drop":
      case "tv_drop": {
        const tv = e.k === "tv_drop";
        const raw = match(e.code, CODE) || "other";
        const code = tv ? DROP_ALIASES[raw] ?? raw : raw;
        const dim = tv ? pick(e.brand, TV_BRANDS) || tvSelf : "";
        count(e.k, code, dim);
        if (tv) tvLink(e, "drop", code);
        const after = int(e.after, 0, 7 * 86400);
        if (after !== null) one(tv ? "tv.after" : "ps5.after", after);
        remember(e.k, code, dim);
        return true;
      }
    }
    return false;
  }
}

/**
 * POST /v1/events. Döner: { status, body, retryAfter? }.
 * 400 gövde bozuk (istemci siler) · 429 sınır (saklar, bekler) · 503 tablolar hazır değil (saklar, sonra dener).
 */
export async function receiveEvents(db, env, body, now) {
  const config = telemetryConfig(env);
  if (!body || typeof body !== "object" || body.v !== 1) return { status: 400, body: { ok: false, error: "bad_batch" } };
  const ctx = body.ctx && typeof body.ctx === "object" ? body.ctx : {};
  const platform = pick(ctx.platform, PLATFORMS);
  if (!platform) return { status: 400, body: { ok: false, error: "bad_platform" } };
  if (!match(body.batch, UUID) || !match(body.install, UUID)) return { status: 400, body: { ok: false, error: "bad_batch" } };
  const events = Array.isArray(body.events) ? body.events : null;
  if (!events || events.length > EVENT_LIMITS.maxEvents) return { status: 400, body: { ok: false, error: "bad_events" } };
  if (!config.enabled) return { status: 200, body: { ok: true, accepted: 0, dropped: events.length, config } };

  const app = match(ctx.app, VERSION);
  // Geliştirici yapıları (Xcode'da durdurmak "çökme" sayılır) istatistikleri bozmasın: alınır, sayılmaz.
  if (ctx.channel === "dev") return { status: 200, body: { ok: true, dev: true, accepted: 0, dropped: events.length, config } };
  const os = match(ctx.os, OS);
  const device = match(ctx.device, DEVICE);
  const day = localDayStart(now);
  const agg = aggregate(events, now, { app, tv: pick(ctx.tv, TV_BRANDS), platform, device });
  const install = await saltedDigest(body.install.toLowerCase(), env.INSTALL_SALT ?? "");
  const batchId = body.batch.toLowerCase();

  try {
    const inserted = await db.prepare("INSERT OR IGNORE INTO ev_batches (batch, at) VALUES (?, ?)").bind(batchId, now).run();
    if ((inserted.meta?.changes ?? 0) === 0) {
      return { status: 200, body: { ok: true, duplicate: true, accepted: 0, dropped: 0, config } };
    }
    const quota = await db.prepare("SELECT install, events, batches FROM ev_quota WHERE day = ? AND install IN (?, '*')")
      .bind(day, install).all();
    const mine = quota.results.find((r) => r.install === install) ?? { events: 0, batches: 0 };
    const all = quota.results.find((r) => r.install === "*") ?? { events: 0, batches: 0 };
    const budget = Math.max(1, Math.floor(num(env.EVENTS_DAILY_BATCHES, 100_000)));
    if (mine.batches >= EVENT_LIMITS.perInstallBatches || mine.events + agg.accepted > EVENT_LIMITS.perInstallEvents
        || all.batches >= budget) {
      await db.prepare("DELETE FROM ev_batches WHERE batch = ?").bind(batchId).run();
      return { status: 429, body: { ok: false, error: "rate_limited", config }, retryAfter: day + 86400 - now };
    }

    const statements = [];
    for (const who of [install, "*"]) {
      statements.push(db.prepare(
        `INSERT INTO ev_quota (day, install, events, batches) VALUES (?1, ?2, ?3, 1)
         ON CONFLICT (day, install) DO UPDATE SET events = events + ?3, batches = batches + 1`,
      ).bind(day, who, agg.accepted));
    }
    for (const [key, n] of agg.counts) {
      const [version, kind, code, dim] = key.split("\u0000");
      statements.push(db.prepare(
        `INSERT INTO ev_daily (day, platform, app, kind, code, dim, n) VALUES (?, ?, ?, ?, ?, ?, ?)
         ON CONFLICT (day, platform, app, kind, code, dim) DO UPDATE SET n = n + excluded.n`,
      ).bind(day, platform, version, kind, code, dim, n));
    }
    for (const [metric, t] of agg.timings) {
      statements.push(db.prepare(
        `INSERT INTO ev_timing (day, platform, app, metric, n, total, peak) VALUES (?, ?, ?, ?, ?, ?, ?)
         ON CONFLICT (day, platform, app, metric) DO UPDATE SET n = n + excluded.n, total = total + excluded.total,
           peak = max(peak, excluded.peak)`,
      ).bind(day, platform, app, metric, t.n, t.sum, t.peak));
      t.h.forEach((c, bucket) => {
        if (c > 0) statements.push(db.prepare(
          `INSERT INTO ev_hist (day, platform, app, metric, bucket, n) VALUES (?, ?, ?, ?, ?, ?)
           ON CONFLICT (day, platform, app, metric, bucket) DO UPDATE SET n = n + excluded.n`,
        ).bind(day, platform, app, metric, bucket, c));
      });
    }
    for (const [game, g] of agg.games) {
      statements.push(db.prepare(
        `INSERT INTO ev_games (day, game, sessions, seconds) VALUES (?, ?, ?, ?)
         ON CONFLICT (day, game) DO UPDATE SET sessions = sessions + excluded.sessions, seconds = seconds + excluded.seconds`,
      ).bind(day, game, g.sessions, g.seconds));
    }
    for (const l of agg.tvLinks) {
      statements.push(db.prepare(
        `INSERT INTO ev_tv_daily (day, platform, brand, model, tv_app, kind, code, n, after_sum, after_n) VALUES (?, ?, ?, ?, ?, ?, ?, 1, ?, ?)
         ON CONFLICT (day, platform, brand, model, tv_app, kind, code) DO UPDATE SET n = n + 1,
           after_sum = after_sum + excluded.after_sum, after_n = after_n + excluded.after_n`,
      ).bind(day, platform, l.brand, l.model, l.tvApp, l.kind, l.code, l.after ?? 0, l.after === null ? 0 : 1));
      statements.push(db.prepare(
        "INSERT INTO ev_tv_raw (at, install, platform, brand, model, tv_app, kind, code, after) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
      ).bind(l.at, install, platform, l.brand, l.model, l.tvApp, l.kind, l.code, l.after));
    }
    for (const r of agg.recent) {
      statements.push(db.prepare(
        "INSERT INTO ev_recent (at, platform, app, os, device, kind, code, detail) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
      ).bind(now, platform, r.app, os, device, r.kind, r.code, r.detail));
    }
    // Otomatik teşhis: kendi sınırları var; aşanlar sessizce atılır.
    const diag = await diagStatements(db, { day, now, install, platform, app, os, device }, agg.diags);
    statements.push(...diag.statements);
    try {
      await db.batch(statements);
    } catch (error) {
      await db.prepare("DELETE FROM ev_batches WHERE batch = ?").bind(batchId).run().catch(() => {});
      throw error;
    }
    return { status: 200, body: { ok: true, accepted: agg.accepted - diag.dropped, dropped: agg.dropped + diag.dropped, config } };
  } catch (error) {
    // Tablolar henüz yoksa (uzak migration yapılmadan yayınlandıysa): istemci saklar, sonra dener.
    console.error("ölçüm alınamadı", error);
    return { status: 503, body: { ok: false, error: "not_ready" }, retryAfter: 3600 };
  }
}

/** Günlük bakım: eski parça kimlikleri, hız sayaçları, son hatalar ve 400 günden eski özetler. */
export async function pruneEvents(db, now) {
  const day = localDayStart(now);
  try {
    await db.batch([
      db.prepare("DELETE FROM ev_batches WHERE at < ?").bind(now - 7 * 86400),
      db.prepare("DELETE FROM ev_quota WHERE day < ?").bind(day - 3 * 86400),
      db.prepare("DELETE FROM ev_recent WHERE at < ?").bind(now - 30 * 86400),
      db.prepare("DELETE FROM ev_tv_raw WHERE at < ?").bind(now - 3 * 86400),
      ...["ev_daily", "ev_timing", "ev_hist", "ev_games", "ev_tv_daily"].map((t) => db.prepare(`DELETE FROM ${t} WHERE day < ?`).bind(day - 400 * 86400)),
    ]);
  } catch {
    // Tablolar yoksa geç.
  }
}

const rate = (good, bad) => (good + bad > 0 ? good / (good + bad) : null);
const PROBLEM_KINDS = new Set(["crash", "error", "ps5_connect", "ps5_drop", "tv_connect", "tv_drop"]);

/** Bir satır grubunun sayıları: açılış, oturum, çökme, hata, PS5/TV bağlantı. */
function tally() {
  return { launches: 0, sessions: 0, crashes: 0, errors: 0, lines: 0, ps5Ok: 0, ps5Fail: 0, ps5Drops: 0, tvOk: 0, tvFail: 0, tvDrops: 0 };
}
function addTo(t, kind, code, n) {
  if (kind === "launch") t.launches += n;
  else if (kind === "session") t.sessions += n;
  else if (kind === "crash") t.crashes += n;
  else if (kind === "error") t.errors += n;
  else if (kind === "lines") t.lines += n;
  else if (kind === "ps5_connect") code === "ok" ? (t.ps5Ok += n) : (t.ps5Fail += n);
  else if (kind === "ps5_drop") t.ps5Drops += n;
  else if (kind === "tv_connect") code === "ok" ? (t.tvOk += n) : (t.tvFail += n);
  else if (kind === "tv_drop") t.tvDrops += n;
}
function finish(t) {
  return {
    ...t,
    crashFree: t.launches > 0 ? Math.max(0, 1 - t.crashes / t.launches) : null,
    errorsPer100: t.sessions > 0 ? (t.errors / t.sessions) * 100 : null,
    ps5Rate: rate(t.ps5Ok, t.ps5Fail),
    tvRate: rate(t.tvOk, t.tvFail),
  };
}

/** GET /v1/events/stats?days=7: panelin "Sağlık" bölümü. Tablolar yoksa `ready: false`. */
export async function eventStats(db, now, days = 7) {
  const span = Math.min(90, Math.max(1, Math.floor(Number(days)) || 7));
  const today = localDayStart(now);
  const since = today - (span - 1) * 86400;
  const all = async (sql, ...args) => (await db.prepare(sql).bind(...args).all()).results;
  let rows, dims, timing, hist, games, recent;
  try {
    [rows, dims, timing, hist, games, recent] = await Promise.all([
      all("SELECT day, platform, app, kind, code, SUM(n) AS n FROM ev_daily WHERE day >= ? GROUP BY day, platform, app, kind, code", since),
      all(`SELECT kind, code, dim, SUM(n) AS n FROM ev_daily WHERE day >= ? AND dim <> ''
           AND kind IN ('ps5_connect', 'tv_connect', 'tv_proto', 'error', 'session', 'launch') GROUP BY kind, code, dim`, since),
      all("SELECT platform, metric, SUM(n) AS n, SUM(total) AS total, MAX(peak) AS peak FROM ev_timing WHERE day >= ? GROUP BY platform, metric", since),
      all("SELECT platform, metric, bucket, SUM(n) AS n FROM ev_hist WHERE day >= ? GROUP BY platform, metric, bucket", since),
      all("SELECT game, SUM(sessions) AS sessions, SUM(seconds) AS seconds FROM ev_games WHERE day >= ? GROUP BY game ORDER BY sessions DESC, seconds DESC LIMIT 60", since),
      all("SELECT at, platform, app, os, device, kind, code, detail FROM ev_recent ORDER BY at DESC, id DESC LIMIT 40"),
    ]);
  } catch {
    return { ok: true, ready: false, now, days: span, since };
  }

  const totals = tally();
  const byVersion = new Map();
  const byPlatform = new Map();
  const byDay = new Map();
  for (let d = since; d <= today; d += 86400) byDay.set(d, tally());
  const problems = new Map();
  for (const r of rows) {
    const n = Number(r.n) || 0;
    const vKey = `${r.platform}\u0000${r.app}`;
    if (!byVersion.has(vKey)) byVersion.set(vKey, { platform: r.platform, app: r.app, ...tally() });
    if (!byPlatform.has(r.platform)) byPlatform.set(r.platform, { platform: r.platform, ...tally() });
    for (const t of [totals, byVersion.get(vKey), byPlatform.get(r.platform), byDay.get(r.day)]) if (t) addTo(t, r.kind, r.code, n);
    if (PROBLEM_KINDS.has(r.kind) && r.code !== "ok") {
      const pKey = `${r.kind}\u0000${r.code}`;
      const p = problems.get(pKey) ?? { kind: r.kind, code: r.code, n: 0, platforms: {}, versions: {} };
      p.n += n;
      p.platforms[r.platform] = (p.platforms[r.platform] ?? 0) + n;
      const v = `${r.platform} ${r.app}`.trim();
      p.versions[v] = (p.versions[v] ?? 0) + n;
      problems.set(pKey, p);
    }
  }
  const busy = (a, b) => b.launches + b.sessions - (a.launches + a.sessions);

  // Süre yüzdelikleri: platform başına ve hepsi ("*").
  const groups = new Map();
  const group = (platform, metric) => {
    const key = `${platform}\u0000${metric}`;
    if (!groups.has(key)) groups.set(key, { platform, metric, n: 0, total: 0, peak: 0, h: new Array(edgesFor(metric).length + 1).fill(0) });
    return groups.get(key);
  };
  for (const t of timing) {
    for (const g of [group(t.platform, t.metric), group("*", t.metric)]) {
      g.n += Number(t.n) || 0;
      g.total += Number(t.total) || 0;
      g.peak = Math.max(g.peak, Number(t.peak) || 0);
    }
  }
  for (const h of hist) {
    for (const g of [group(h.platform, h.metric), group("*", h.metric)]) {
      if (h.bucket >= 0 && h.bucket < g.h.length) g.h[h.bucket] += Number(h.n) || 0;
    }
  }
  const timings = [...groups.values()].filter((g) => g.n > 0).map((g) => {
    const edges = edgesFor(g.metric);
    return {
      platform: g.platform, metric: g.metric, unit: edges === S_EDGES ? "s" : "ms", n: g.n,
      avg: Math.round(g.total / g.n), p50: percentile(g.h, edges, g.peak, 0.5), p90: percentile(g.h, edges, g.peak, 0.9),
      p99: percentile(g.h, edges, g.peak, 0.99), max: g.peak,
    };
  }).sort((a, b) => a.metric.localeCompare(b.metric) || (a.platform === "*" ? -1 : b.platform === "*" ? 1 : b.n - a.n));

  const dimList = (kind) => dims.filter((d) => d.kind === kind);
  const success = (kind) => {
    const m = new Map();
    for (const d of dimList(kind)) {
      const e = m.get(d.dim) ?? { key: d.dim, ok: 0, fail: 0 };
      if (d.code === "ok") e.ok += Number(d.n) || 0;
      else e.fail += Number(d.n) || 0;
      m.set(d.dim, e);
    }
    return [...m.values()].map((e) => ({ ...e, rate: rate(e.ok, e.fail) })).sort((a, b) => b.ok + b.fail - (a.ok + a.fail));
  };

  return {
    ok: true, ready: true, now, days: span, since,
    totals: finish(totals),
    platforms: [...byPlatform.values()].map(finish).sort(busy),
    versions: [...byVersion.values()].map(finish).sort(busy).slice(0, 40),
    daily: [...byDay.entries()].map(([day, t]) => ({ day, ...finish(t) })),
    problems: [...problems.values()].sort((a, b) => b.n - a.n).slice(0, 30),
    timings,
    tvBrands: success("tv_connect"),
    ps5Via: success("ps5_connect"),
    tvProto: dimList("tv_proto").map((d) => ({ proto: d.code, brand: d.dim, n: Number(d.n) || 0 })),
    http: dimList("error").map((d) => ({ code: d.code, http: d.dim, n: Number(d.n) || 0 })).sort((a, b) => b.n - a.n).slice(0, 15),
    // Gönderen uygulamaların (Mac, telefon…) bağlı olduğu TV markası, açılışa göre.
    senderTv: dimList("launch").map((d) => ({ brand: d.dim, n: Number(d.n) || 0 })).sort((a, b) => b.n - a.n),
    sources: dimList("session").map((d) => ({ src: d.dim, n: Number(d.n) || 0 })).sort((a, b) => b.n - a.n),
    games: mergeGameRows(games.map((g) => ({ game: g.game, sessions: Number(g.sessions) || 0, seconds: Number(g.seconds) || 0 })), { sortBy: "sessions" })
      .slice(0, 15).map(({ seconds, ...g }) => ({ ...g, minutes: Math.round(seconds / 60) })),
    recent,
    tvLinks: await tvLinkStats(db, now, since),
    diag: await diagStats(db, now, since),
  };
}

/**
 * Panelin "TV bağlantıları" bölümü: seçili aralıkta modele, TV uygulama sürümüne, gönderen platforma ve kopma nedenine
 * göre deneme / kopma; son 24 saatte en çok kopan modeller; kısa sürede çok kopan kurulumlar (uyarı).
 * Kopma oranı = kopma / başarılı bağlantı. Tablolar yoksa null.
 */
export async function tvLinkStats(db, now, since) {
  const all = async (sql, ...args) => (await db.prepare(sql).bind(...args).all()).results;
  let rows, last24, flaps;
  try {
    [rows, last24, flaps] = await Promise.all([
      all(`SELECT platform, brand, model, tv_app, kind, code, SUM(n) AS n, SUM(after_sum) AS after_sum, SUM(after_n) AS after_n
           FROM ev_tv_daily WHERE day >= ? GROUP BY platform, brand, model, tv_app, kind, code`, since),
      all(`SELECT brand, model, SUM(kind = 'drop') AS drops, SUM(kind = 'connect' AND code = 'ok') AS ok,
             SUM(kind = 'connect' AND code <> 'ok') AS fails, COUNT(DISTINCT CASE WHEN kind = 'drop' THEN install END) AS installs
           FROM ev_tv_raw WHERE at > ? GROUP BY brand, model HAVING drops > 0 ORDER BY drops DESC, ok DESC LIMIT 15`, now - 86400),
      all(`SELECT install, MAX(platform) AS platform, MAX(brand) AS brand, MAX(model) AS model, MAX(tv_app) AS tv_app,
             SUM(at > ?2) AS hour, COUNT(*) AS six, MIN(at) AS first, MAX(at) AS last, GROUP_CONCAT(DISTINCT code) AS codes
           FROM ev_tv_raw WHERE kind = 'drop' AND at > ?1 GROUP BY install
           HAVING SUM(at > ?2) >= ?3 OR COUNT(*) >= ?4 ORDER BY last DESC LIMIT 30`,
        now - 6 * 3600, now - 3600, TV_FLAP.hour, TV_FLAP.sixHours),
    ]);
  } catch {
    return null;
  }
  const groups = { models: new Map(), apps: new Map(), senders: new Map(), reasons: new Map() };
  const totals = { ok: 0, fails: 0, drops: 0, afterSum: 0, afterN: 0 };
  const bump = (map, key, base, r) => {
    const g = map.get(key) ?? { ...base, ok: 0, fails: 0, drops: 0, afterSum: 0, afterN: 0 };
    add(g, r);
    map.set(key, g);
  };
  const add = (g, r) => {
    const n = Number(r.n) || 0;
    if (r.kind === "connect") r.code === "ok" ? (g.ok += n) : (g.fails += n);
    else {
      g.drops += n;
      g.afterSum += Number(r.after_sum) || 0;
      g.afterN += Number(r.after_n) || 0;
    }
  };
  for (const r of rows) {
    add(totals, r);
    bump(groups.models, `${r.brand}\u0000${r.model}`, { brand: r.brand, model: r.model }, r);
    bump(groups.apps, `${r.brand}\u0000${r.tv_app}`, { brand: r.brand, tvApp: r.tv_app }, r);
    bump(groups.senders, r.platform, { platform: r.platform }, r);
    if (r.kind === "drop") bump(groups.reasons, r.code, { code: r.code }, r);
  }
  const finishTv = ({ afterSum, afterN, ...g }) => ({
    ...g, dropRate: g.ok > 0 ? g.drops / g.ok : null, connectRate: g.ok + g.fails > 0 ? g.ok / (g.ok + g.fails) : null,
    avgAfter: afterN > 0 ? Math.round(afterSum / afterN) : null,
  });
  const list = (map, limit = 30) => [...map.values()].map(finishTv)
    .sort((a, b) => b.drops - a.drops || b.ok + b.fails - (a.ok + a.fails)).slice(0, limit);
  return {
    totals: finishTv(totals),
    models: list(groups.models),
    tvApps: list(groups.apps, 15),
    senders: list(groups.senders, 10),
    reasons: list(groups.reasons, 15),
    last24: last24.map((r) => ({ brand: r.brand, model: r.model, drops: Number(r.drops) || 0, ok: Number(r.ok) || 0,
      fails: Number(r.fails) || 0, installs: Number(r.installs) || 0 })),
    // Kurulum kimliği gösterilmez; yalnız aynı satırları ayırmak için özetin ilk 6 hanesi.
    alerts: flaps.map((r) => ({ id: String(r.install).slice(0, 6), platform: r.platform, brand: r.brand, model: r.model,
      tvApp: r.tv_app, hour: Number(r.hour) || 0, sixHours: Number(r.six) || 0, first: r.first, last: r.last,
      codes: String(r.codes ?? "").split(",").filter(Boolean) })),
  };
}
