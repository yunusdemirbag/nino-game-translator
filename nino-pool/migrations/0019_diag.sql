-- SPDX-License-Identifier: AGPL-3.0-only
-- Nino otomatik teşhis (src/diag.js, tarif: NinoCore docs/tarif/otomatik-teshis.md): uygulamaların bekçisinin
-- gönderdiği "diag" olayları. Serbest metin yok; yalnız kural, sebep kodu, sayısal durum ve kodlu iz.
-- İmza: kural + platform + uygulama sürümü + model. Grup (yeni sorun için): kural + platform + model.

-- Günlük toplam (kurulum kimliği yok). 400 gün.
CREATE TABLE IF NOT EXISTS diag_daily (
  day      INTEGER NOT NULL,
  rule     TEXT    NOT NULL,
  platform TEXT    NOT NULL,
  app      TEXT    NOT NULL,
  model    TEXT    NOT NULL,
  cause    TEXT    NOT NULL,
  n        INTEGER NOT NULL,
  PRIMARY KEY (day, rule, platform, app, model, cause)
) WITHOUT ROWID;

-- Sınırlar ve "kaç farklı kurulum": install tuzlanmış özet, 3 gün.
CREATE TABLE IF NOT EXISTS diag_seen (
  day      INTEGER NOT NULL,
  install  TEXT    NOT NULL,
  rule     TEXT    NOT NULL,
  platform TEXT    NOT NULL,
  app      TEXT    NOT NULL,
  model    TEXT    NOT NULL,
  n        INTEGER NOT NULL,
  PRIMARY KEY (day, install, rule, platform, app, model)
) WITHOUT ROWID;

-- Örnek bildirimler (imza başına günde en çok 3; kurulum kimliği yok). 30 gün.
CREATE TABLE IF NOT EXISTS diag_samples (
  id       INTEGER PRIMARY KEY,
  at       INTEGER NOT NULL,
  day      INTEGER NOT NULL,
  rule     TEXT    NOT NULL,
  cause    TEXT    NOT NULL,
  sev      TEXT    NOT NULL,
  platform TEXT    NOT NULL,
  app      TEXT    NOT NULL,
  model    TEXT    NOT NULL,
  os       TEXT    NOT NULL,
  tv       TEXT    NOT NULL,   -- JSON {brand, model, app}
  game     TEXT    NOT NULL,
  state    TEXT    NOT NULL,   -- JSON
  trail    TEXT    NOT NULL,   -- JSON
  ver      TEXT    NOT NULL    -- JSON
);
CREATE INDEX IF NOT EXISTS diag_samples_sig ON diag_samples (day, rule, platform, app, model);
CREATE INDEX IF NOT EXISTS diag_samples_at ON diag_samples (at);

-- Sürümden bağımsız gruplar: ilk / son görülme ve yardımcı modelin kısa Türkçe özeti.
CREATE TABLE IF NOT EXISTS diag_groups (
  rule       TEXT    NOT NULL,
  platform   TEXT    NOT NULL,
  model      TEXT    NOT NULL,
  first_seen INTEGER NOT NULL,
  last_seen  INTEGER NOT NULL,
  first_app  TEXT    NOT NULL,
  total      INTEGER NOT NULL,
  summary    TEXT    NOT NULL DEFAULT '',
  summary_at INTEGER NOT NULL DEFAULT 0,
  summary_n  INTEGER NOT NULL DEFAULT 0,  -- özet yazıldığında toplam kaçtı (değişti mi?)
  PRIMARY KEY (rule, platform, model)
) WITHOUT ROWID;
