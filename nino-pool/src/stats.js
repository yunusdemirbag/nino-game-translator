// SPDX-License-Identifier: AGPL-3.0-only
// Nino paneli: kaç kişi şu an oynuyor, kaç kurulum var, kaç indirme, kaç satır ve kelime çevrildi, ne harcandı.
// Kurulum kimliği yalnız tuzlanmış özetiyle tutulur; IP ve kişisel veri yok.
import { canonicalGame, mergeGameRows } from "./games.js";

import { saltedDigest } from "./key.js";
import { assistantStats } from "./assistant.js";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const PLATFORMS = new Set(["mac", "windows", "linux", "android", "ios", "tv"]);
const GAME = /^[a-z0-9][a-z0-9._-]{0,63}$/;
/** "Şu an oynuyor": son "buradayım" bu kadar saniye içindeyse (uygulama dakikada bir bildirir). */
export const PLAYING_WINDOW = 150;

/** Kurulumu kaydeder ya da son görülme zamanını yeniler. `playing`: çeviri sürüyor. */
export async function touchInstall(db, env, raw, now, { platform = "", app = "", playing = false, game = "", lang = "" } = {}) {
  if (typeof raw !== "string" || !UUID.test(raw)) return;
  const install = await saltedDigest(raw.toLowerCase(), env.INSTALL_SALT ?? "");
  const plat = PLATFORMS.has(platform) ? platform : "";
  const version = typeof app === "string" ? app.slice(0, 40) : "";
  const g = typeof game === "string" && GAME.test(game) ? canonicalGame(game) : "";
  const l = typeof lang === "string" ? lang.toLowerCase().slice(0, 8) : "";
  await db.prepare(
    `INSERT INTO installs (install, platform, app, first_seen, last_seen, playing, game, lang) VALUES (?1, ?2, ?3, ?4, ?4, ?5, ?6, ?7)
     ON CONFLICT (install) DO UPDATE SET
       platform = CASE WHEN ?2 <> '' THEN ?2 ELSE platform END,
       app = CASE WHEN ?3 <> '' THEN ?3 ELSE app END,
       last_seen = max(last_seen, ?4),
       playing = CASE WHEN ?5 > 0 THEN ?5 ELSE playing END,
       game = CASE WHEN ?5 > 0 AND ?6 <> '' THEN ?6 ELSE game END,
       lang = CASE WHEN ?7 <> '' THEN ?7 ELSE lang END`,
  ).bind(install, plat, version, now, playing ? now : 0, g, l).run();
}

/** Geçmiş ölçümleri arasındaki en kısa süre (saniye); her "buradayım"da sayım yapılmasın diye. */
export const SAMPLE_EVERY = 60;
/** Günler Türkiye saatiyle sayılır (UTC+3, yaz saati yok): kullanıcıların çoğu orada, gün gece yarısı dönsün. */
const DAY_OFFSET = 3 * 3600;
export function localDayStart(now) {
  return now - ((now + DAY_OFFSET) % 86400);
}
const LOCAL_DAY_SQL = (column) => `((${column} + ${DAY_OFFSET}) / 86400) * 86400 - ${DAY_OFFSET}`;

// Son ölçüm zamanı (sunucu örneği başına; birkaç örnek aynı dakikada ölçerse en yükseği kalır, zararı yok).
let lastSample = 0;

/**
 * "Şu an oynayan" sayısını o saatin en yükseğine, bugün açan ve oynayan kurulum sayısını güne yazar. Dakikada en çok
 * bir kez (`force` dışında). Tablolar henüz yoksa ya da yazılamazsa sessizce geçer: panel geçmişi, uygulamaların
 * "buradayım" isteğini asla bozmamalı.
 */
export async function samplePlayers(db, now, { force = false } = {}) {
  if (!force && now - lastSample < SAMPLE_EVERY && now >= lastSample) return false;
  lastSample = now;
  const hour = now - (now % 3600);
  const day = localDayStart(now);
  try {
    await db.batch([
      db.prepare(
        `INSERT INTO player_hours (hour, peak, samples) VALUES (?1, (SELECT COUNT(*) FROM installs WHERE playing > ?2), 1)
         ON CONFLICT (hour) DO UPDATE SET peak = max(peak, excluded.peak), samples = samples + 1`,
      ).bind(hour, now - PLAYING_WINDOW),
      db.prepare(
        `INSERT INTO player_days (day, active, played) VALUES (?1,
           (SELECT COUNT(*) FROM installs WHERE last_seen >= ?1), (SELECT COUNT(*) FROM installs WHERE playing >= ?1))
         ON CONFLICT (day) DO UPDATE SET active = max(active, excluded.active), played = max(played, excluded.played)`,
      ).bind(day),
    ]);
    return true;
  } catch {
    return false;
  }
}

/** GET /v1/ping: uygulama çeviri sürerken dakikada bir "buradayım" der. */
export async function handlePing(db, env, params, now) {
  await touchInstall(db, env, params.get("install") ?? "", now, {
    platform: params.get("platform") ?? "", app: params.get("app") ?? "", playing: true,
    game: params.get("game") ?? "", lang: params.get("lang") ?? "",
  });
  await samplePlayers(db, now);
  return { status: 204 };
}

const TV_BRANDS = new Set(["androidtv", "samsung", "lg"]);

/** Model adını saklanacak biçime getirir: yazdırılabilir karakterler, tek boşluk, en çok 60 karakter. */
export function cleanTvModel(raw) {
  if (typeof raw !== "string") return "";
  return raw.replace(/[^\p{L}\p{N} ._()\/+-]/gu, " ").replace(/\s+/g, " ").trim().slice(0, 60);
}

/** GET /v1/tv: TV uygulaması günde bir kez markasını ve modelini bildirir. */
export async function handleTv(db, env, params, now) {
  const raw = params.get("install") ?? "";
  const brand = params.get("brand") ?? "";
  const model = cleanTvModel(params.get("model") ?? "");
  if (!UUID.test(raw) || !TV_BRANDS.has(brand) || !model) return { status: 204 };
  const tv = await saltedDigest(raw.toLowerCase(), env.INSTALL_SALT ?? "");
  const app = (params.get("app") ?? "").replace(/[^0-9A-Za-z. ()-]/g, "").slice(0, 24);
  try {
    await db.prepare(
      `INSERT INTO tvs (tv, brand, model, app, first_seen, last_seen) VALUES (?1, ?2, ?3, ?4, ?5, ?5)
       ON CONFLICT (tv) DO UPDATE SET brand = ?2, model = ?3, app = CASE WHEN ?4 <> '' THEN ?4 ELSE app END, last_seen = ?5`,
    ).bind(tv, brand, model, app, now).run();
  } catch {
    // Tablo henüz yoksa TV'nin isteği yine sessizce biter.
  }
  return { status: 204 };
}

/** Panelin TV bölümü: kaç TV, markalara ve modellere göre. Tablo yoksa boş döner. */
async function tvStats(db) {
  try {
    const all = async (sql) => (await db.prepare(sql).all()).results;
    const [byBrand, models, versions] = await Promise.all([
      all("SELECT brand, COUNT(*) AS n FROM tvs GROUP BY brand ORDER BY n DESC"),
      all("SELECT brand, model, COUNT(*) AS n FROM tvs GROUP BY brand, model ORDER BY n DESC, model LIMIT 150"),
      all("SELECT app, COUNT(*) AS n FROM tvs WHERE app <> '' GROUP BY app ORDER BY n DESC LIMIT 6"),
    ]);
    return { total: byBrand.reduce((sum, row) => sum + row.n, 0), byBrand, models, versions };
  } catch {
    return { total: 0, byBrand: [], models: [], versions: [] };
  }
}

/** Panelin geçmiş bölümü: en yüksek oyuncu sayıları, son 48 saat ve son 14 gün. Tablolar yoksa boş döner. */
async function playerHistory(db, now, playingNow) {
  const all = async (sql, ...args) => (await db.prepare(sql).bind(...args).all()).results;
  const first = (sql, ...args) => db.prepare(sql).bind(...args).first();
  const today = localDayStart(now);
  const since = today - 13 * 86400;
  try {
    const [hours, best, dayPeaks, days, fresh] = await Promise.all([
      all("SELECT hour, peak FROM player_hours WHERE hour > ? ORDER BY hour", now - 48 * 3600),
      first("SELECT hour, peak FROM player_hours ORDER BY peak DESC, hour DESC LIMIT 1"),
      all(`SELECT ${LOCAL_DAY_SQL("hour")} AS day, MAX(peak) AS peak FROM player_hours WHERE hour >= ? GROUP BY day`, since),
      all("SELECT day, active, played FROM player_days WHERE day >= ? ORDER BY day", since),
      all(`SELECT ${LOCAL_DAY_SQL("first_seen")} AS day, COUNT(*) AS n FROM installs WHERE first_seen >= ? GROUP BY day`, since),
    ]);
    const peakOf = new Map(dayPeaks.map((r) => [r.day, r.peak]));
    const dayOf = new Map(days.map((r) => [r.day, r]));
    const freshOf = new Map(fresh.map((r) => [r.day, r.n]));
    const daily = [];
    for (let day = since; day <= today; day += 86400) {
      const row = dayOf.get(day);
      daily.push({ day, active: row?.active ?? null, played: row?.played ?? null, peak: peakOf.get(day) ?? null, fresh: freshOf.get(day) ?? 0 });
    }
    const todayPeak = Math.max(peakOf.get(today) ?? 0, playingNow);
    const weekPeak = Math.max(playingNow, ...daily.slice(-7).map((d) => d.peak ?? 0));
    const allTime = Math.max(best?.peak ?? 0, playingNow);
    return {
      peak: {
        today: todayPeak,
        week: weekPeak,
        allTime,
        // En yüksek değer şu anki sayıysa saat de şimdiki saattir.
        allTimeHour: best && best.peak >= playingNow ? best.hour : now - (now % 3600),
        since: (await first("SELECT MIN(hour) AS hour FROM player_hours"))?.hour ?? null,
      },
      hourly: hours,
      daily,
    };
  } catch {
    return { peak: { today: playingNow, week: playingNow, allTime: playingNow, allTimeHour: null, since: null }, hourly: [], daily: [] };
  }
}

// GitHub indirme sayıları (sürüm dosyaları); sunucu örneği içinde 10 dakika tutulur.
let downloadsCache = { at: 0, value: null };

async function githubDownloads(db, now, fetcher = fetch) {
  if (downloadsCache.value && now - downloadsCache.at < 600) return downloadsCache.value;
  const fresh = await fetchGithubDownloads(fetcher);
  if (fresh) {
    downloadsCache = { at: now, value: fresh };
    // Son bilinen değer saklanır: GitHub isteği sınıra takılınca (sunucunun paylaşılan adresi yüzünden sık olur) ya da
    // sunucu yeni açılınca panel "alınamadı" demek yerine bunu gösterir.
    try {
      await db.prepare("INSERT INTO stats_cache (key, value, at) VALUES ('downloads', ?1, ?2) ON CONFLICT (key) DO UPDATE SET value = ?1, at = ?2")
        .bind(JSON.stringify(fresh), now).run();
    } catch { /* tablo yoksa yalnız bellekte kalır */ }
    return fresh;
  }
  if (downloadsCache.value) return downloadsCache.value;
  try {
    const row = await db.prepare("SELECT value, at FROM stats_cache WHERE key = 'downloads'").first();
    if (row?.value) {
      const stored = { ...JSON.parse(row.value), asOf: row.at };
      // Bir dakika sonra yeniden denenir; o zamana kadar saklanan değer verilir.
      downloadsCache = { at: now - 540, value: stored };
      return stored;
    }
  } catch { /* saklanan değer yok */ }
  return null;
}

/**
 * Uygulamalara gösterilen toplam indirme (GET /v1/config → downloads): yalnız saklanan son değer okunur, GitHub'a
 * gidilmez (uygulama isteği GitHub sınırına takılıp beklemesin). Değeri zamanlanmış iş yarım saatte bir yeniler
 * (bkz. `refreshDownloads`). Hiç alınamadıysa null: uygulama kendi son bildiğini gösterir.
 */
export async function storedDownloadTotal(db) {
  try {
    const row = await db.prepare("SELECT value FROM stats_cache WHERE key = 'downloads'").first();
    const total = Number(JSON.parse(row?.value ?? "null")?.total);
    return Number.isFinite(total) && total > 0 ? Math.floor(total) : null;
  } catch {
    return null;
  }
}

/** Zamanlanmış iş: indirme sayısını GitHub'dan yeniler ve saklar (alınamazsa eski değer kalır). */
export async function refreshDownloads(db, now, fetcher = fetch) {
  return githubDownloads(db, now, fetcher);
}

async function fetchGithubDownloads(fetcher) {
  try {
    const response = await fetcher("https://api.github.com/repos/yunusdemirbag/nino-game-translator/releases?per_page=100", {
      headers: { "user-agent": "nino-pool", accept: "application/vnd.github+json" },
    });
    if (!response.ok) return null;
    const releases = await response.json();
    const byFile = { mac: 0, windows: 0, android: 0, tv: 0 };
    let latest = null;
    for (const release of releases) {
      if (!latest && !release.draft && !release.prerelease) latest = release.tag_name;
      for (const asset of release.assets ?? []) {
        const name = String(asset.name ?? "");
        const n = Number(asset.download_count) || 0;
        if (/mac\.zip$/i.test(name)) byFile.mac += n;
        else if (/setup\.exe$/i.test(name)) byFile.windows += n;
        else if (/telefon\.apk$|mobile.*\.apk$/i.test(name)) byFile.android += n;
        else if (/tv\.apk$|androidtv.*\.apk$/i.test(name)) byFile.tv += n;
      }
    }
    return { ...byFile, total: byFile.mac + byFile.windows + byFile.android + byFile.tv, latest };
  } catch {
    return null;
  }
}

function dayStart(now) {
  return now - (now % 86400);
}

/** GET /v1/stats (yönetici): panelin bütün sayıları. */
export async function collectStats(db, env, now, fetcher) {
  const today = dayStart(now);
  const day = (t) => new Date(t * 1000).toISOString().slice(0, 10);
  const first = (sql, ...args) => db.prepare(sql).bind(...args).first();
  const all = async (sql, ...args) => (await db.prepare(sql).bind(...args).all()).results;

  // Panel açıkken de ölçülür: kimse oynamıyorken "buradayım" gelmez, o saat boş kalmasın.
  await samplePlayers(db, now);
  const [playing, byPlatformNow, games, active24, newToday, total, byPlatform, versions, userLangs] = await Promise.all([
    first("SELECT COUNT(*) AS n FROM installs WHERE playing > ?", now - PLAYING_WINDOW),
    all("SELECT platform, COUNT(*) AS n FROM installs WHERE playing > ? GROUP BY platform ORDER BY n DESC", now - PLAYING_WINDOW),
    // Eski kayıtlarda aynı oyun farklı kimlikle durabilir (grand-theft-auto-vi / gta-6): asıl kimlikte toplanır.
    all("SELECT game, COUNT(*) AS n FROM installs WHERE playing > ? GROUP BY game ORDER BY n DESC LIMIT 40", now - PLAYING_WINDOW),
    first("SELECT COUNT(*) AS n FROM installs WHERE last_seen > ?", now - 86400),
    first("SELECT COUNT(*) AS n FROM installs WHERE first_seen >= ?", today),
    first("SELECT COUNT(*) AS n FROM installs"),
    all("SELECT platform, COUNT(*) AS n FROM installs GROUP BY platform ORDER BY n DESC"),
    all("SELECT app, COUNT(*) AS n FROM installs WHERE last_seen > ? AND app <> '' GROUP BY app ORDER BY n DESC LIMIT 6", now - 7 * 86400),
    all("SELECT lang, COUNT(*) AS n FROM installs WHERE lang <> '' GROUP BY lang ORDER BY n DESC LIMIT 8"),
  ]);
  const history = await playerHistory(db, now, playing?.n ?? 0);

  const [tr, trToday, byLang, lines, cost, assistantCost, questions, reports, hourly] = await Promise.all([
    first(`SELECT COUNT(*) AS n, SUM(tier = 2) AS reviewed,
                  SUM(length(source) - length(replace(source, ' ', '')) + 1) AS words FROM translations WHERE text <> ''`),
    first(`SELECT COUNT(*) AS n, SUM(length(source) - length(replace(source, ' ', '')) + 1) AS words
           FROM translations WHERE created >= ? AND text <> ''`, today),
    all("SELECT lang, COUNT(*) AS n FROM translations GROUP BY lang ORDER BY n DESC"),
    first("SELECT COUNT(*) AS n, COALESCE(SUM(seen), 0) AS seen FROM lines"),
    all("SELECT day, micro_usd FROM translate_cost WHERE day >= ? ORDER BY day", day(now - 6 * 86400)),
    first("SELECT micro_usd FROM assistant_cost WHERE day = ?", Math.floor(now / 86400)),
    first("SELECT COALESCE(SUM(count), 0) AS n FROM assistant_usage WHERE day = ?", Math.floor(now / 86400)),
    first("SELECT COUNT(*) AS n, SUM(status = 'new') AS fresh FROM reports"),
    all(`SELECT (created / 3600) * 3600 AS hour, COUNT(*) AS n FROM translations WHERE created > ? GROUP BY hour ORDER BY hour`,
      now - 24 * 3600),
  ]);

  const translateCap = Number(env.TRANSLATE_DAILY_USD ?? 6);
  const spentToday = (cost.find((c) => c.day === day(now))?.micro_usd ?? 0) / 1e6;
  return {
    ok: true,
    now,
    players: {
      now: playing?.n ?? 0,
      byPlatform: byPlatformNow,
      games: mergeGameRows(games).slice(0, 8),
      active24h: active24?.n ?? 0,
      newToday: newToday?.n ?? 0,
      installs: total?.n ?? 0,
      installsByPlatform: byPlatform,
      versions,
      langs: userLangs,
      peak: history.peak,
      hourly: history.hourly,
      daily: history.daily,
    },
    downloads: env.STATS_GITHUB === "0" ? null : await githubDownloads(db, now, fetcher),
    translations: {
      lines: tr?.n ?? 0,
      words: tr?.words ?? 0,
      reviewed: tr?.reviewed ?? 0,
      today: trToday?.n ?? 0,
      wordsToday: trToday?.words ?? 0,
      byLang,
      hourly,
    },
    pool: { lines: lines?.n ?? 0, seen: lines?.seen ?? 0 },
    spend: {
      translateToday: spentToday,
      translateCap,
      assistantToday: (assistantCost?.micro_usd ?? 0) / 1e6,
      week: cost.map((c) => ({ day: c.day, usd: c.micro_usd / 1e6 })),
    },
    assistant: { questionsToday: questions?.n ?? 0, ...(await assistantStats(db, env, now)) },
    reports: { total: reports?.n ?? 0, fresh: reports?.fresh ?? 0 },
    tvs: await tvStats(db),
  };
}
