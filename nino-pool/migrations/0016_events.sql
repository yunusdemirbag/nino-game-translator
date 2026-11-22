-- SPDX-License-Identifier: AGPL-3.0-only
-- Nino ölçüm (src/events.js, tarif: NinoCore docs/tarif/olcum.md): uygulamaların hata ve hız istatistikleri.
-- Özet tablolarında kurulum kimliği yok; altyazı metni, IP ya da kişisel bilgi hiçbir tabloda yok.
-- `day`: Türkiye saatiyle günün başı (Unix saniye), panelin öbür tablolarıyla aynı.

-- Aynı parça (yeniden deneme) iki kez sayılmasın. 7 gün tutulur.
CREATE TABLE IF NOT EXISTS ev_batches (
  batch TEXT    PRIMARY KEY,
  at    INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS ev_batches_at ON ev_batches (at);

-- Hız sınırı: kurulum başına günlük olay ve parça sayısı (install: tuzlanmış özet; '*' bütün kurulumlar). 3 gün tutulur.
CREATE TABLE IF NOT EXISTS ev_quota (
  day     INTEGER NOT NULL,
  install TEXT    NOT NULL,
  events  INTEGER NOT NULL,
  batches INTEGER NOT NULL,
  PRIMARY KEY (day, install)
) WITHOUT ROWID;

-- Günlük sayılar: tür (launch, session, crash, error, ps5_connect, ps5_drop, tv_connect, tv_drop), kod (hata kodu ya da
-- "ok"), ek boyut (TV markası, PS5 bağlantı yolu, HTTP durumu, oturum kaynağı).
CREATE TABLE IF NOT EXISTS ev_daily (
  day      INTEGER NOT NULL,
  platform TEXT    NOT NULL,
  app      TEXT    NOT NULL,
  kind     TEXT    NOT NULL,
  code     TEXT    NOT NULL,
  dim      TEXT    NOT NULL,
  n        INTEGER NOT NULL,
  PRIMARY KEY (day, platform, app, kind, code, dim)
) WITHOUT ROWID;

-- Süre ölçümleri: adet, toplam, en büyük (ms; "session" ölçümü saniye) ve kova adetleri (yüzdelikler bunlardan).
CREATE TABLE IF NOT EXISTS ev_timing (
  day      INTEGER NOT NULL,
  platform TEXT    NOT NULL,
  app      TEXT    NOT NULL,
  metric   TEXT    NOT NULL,
  n        INTEGER NOT NULL,
  total    INTEGER NOT NULL,          -- değerlerin toplamı
  peak     INTEGER NOT NULL,          -- en büyük değer
  PRIMARY KEY (day, platform, app, metric)
) WITHOUT ROWID;

CREATE TABLE IF NOT EXISTS ev_hist (
  day      INTEGER NOT NULL,
  platform TEXT    NOT NULL,
  app      TEXT    NOT NULL,
  metric   TEXT    NOT NULL,
  bucket   INTEGER NOT NULL,
  n        INTEGER NOT NULL,
  PRIMARY KEY (day, platform, app, metric, bucket)
) WITHOUT ROWID;

-- Oyunlar: oturum sayısı ve toplam süre (saniye).
CREATE TABLE IF NOT EXISTS ev_games (
  day      INTEGER NOT NULL,
  game     TEXT    NOT NULL,
  sessions INTEGER NOT NULL,
  seconds  INTEGER NOT NULL,
  PRIMARY KEY (day, game)
) WITHOUT ROWID;

-- Son çökme ve hatalar (panelde liste). Kurulum kimliği yok. 30 gün tutulur.
CREATE TABLE IF NOT EXISTS ev_recent (
  id       INTEGER PRIMARY KEY,
  at       INTEGER NOT NULL,
  platform TEXT    NOT NULL,
  app      TEXT    NOT NULL,
  os       TEXT    NOT NULL,
  device   TEXT    NOT NULL,
  kind     TEXT    NOT NULL,
  code     TEXT    NOT NULL,
  detail   TEXT    NOT NULL
);
CREATE INDEX IF NOT EXISTS ev_recent_at ON ev_recent (at DESC);
