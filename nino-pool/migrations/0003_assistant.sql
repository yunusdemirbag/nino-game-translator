-- SPDX-License-Identifier: AGPL-3.0-only
-- Nino yardımcısı: kurulum başına günlük soru sayısı ve günlük toplam (maliyet sınırı). İçerik saklanmaz.
CREATE TABLE assistant_usage (
  install TEXT NOT NULL,
  day INTEGER NOT NULL,
  count INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (install, day)
);
