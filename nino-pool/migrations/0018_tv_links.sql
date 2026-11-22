-- SPDX-License-Identifier: AGPL-3.0-only
-- Nino ölçüm: TV bağlantıları (src/events.js). tv_connect / tv_drop olaylarından TV markası, modeli (ör. "TCL 98U95A"),
-- TV uygulamasının sürümü, gönderen platform (mac, android… ya da TV'nin kendisi) ve sonuç / kopma nedeni.

-- Günlük toplam: deneme / kopma sayısı ve kopmadan önceki bağlı kalma süresi (saniye). Kurulum kimliği yok. 400 gün.
CREATE TABLE IF NOT EXISTS ev_tv_daily (
  day       INTEGER NOT NULL,
  platform  TEXT    NOT NULL,   -- gönderen platform
  brand     TEXT    NOT NULL,   -- androidtv | samsung | lg | ''
  model     TEXT    NOT NULL,
  tv_app    TEXT    NOT NULL,   -- TV uygulamasının sürümü
  kind      TEXT    NOT NULL,   -- connect | drop
  code      TEXT    NOT NULL,   -- connect: ok ya da hata kodu; drop: kopma nedeni
  n         INTEGER NOT NULL,
  after_sum INTEGER NOT NULL,
  after_n   INTEGER NOT NULL,
  PRIMARY KEY (day, platform, brand, model, tv_app, kind, code)
) WITHOUT ROWID;

-- Son 3 günün olayları tek tek: "son 24 saatte en çok kopan modeller" ve "kısa sürede çok kopan kurulum" uyarısı.
-- install: tuzlanmış özet (hız sınırıyla aynı), 3 gün sonra silinir.
CREATE TABLE IF NOT EXISTS ev_tv_raw (
  id       INTEGER PRIMARY KEY,
  at       INTEGER NOT NULL,
  install  TEXT    NOT NULL,
  platform TEXT    NOT NULL,
  brand    TEXT    NOT NULL,
  model    TEXT    NOT NULL,
  tv_app   TEXT    NOT NULL,
  kind     TEXT    NOT NULL,
  code     TEXT    NOT NULL,
  after    INTEGER
);
CREATE INDEX IF NOT EXISTS ev_tv_raw_at ON ev_tv_raw (at);
CREATE INDEX IF NOT EXISTS ev_tv_raw_install ON ev_tv_raw (install, at);
