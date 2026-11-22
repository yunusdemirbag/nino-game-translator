-- Nino: ücretsiz servislerin günlük kullanımı (src/free.js). Cloudflare Workers AI ücretli planda günlük ücretsiz
-- hakkı (10.000 nöron) aşınca para yazdığı için tahmini nöron burada sayılır; sınıra yaklaşınca o gün kullanılmaz.
CREATE TABLE IF NOT EXISTS free_usage (
  day   TEXT NOT NULL,   -- 'YYYY-MM-DD' (UTC; Workers AI hakkı 00:00 UTC'de yenilenir)
  id    TEXT NOT NULL,   -- FREE_CHAIN girdisi
  units REAL NOT NULL,   -- tahmini nöron
  PRIMARY KEY (day, id)
) WITHOUT ROWID;
