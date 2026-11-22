-- SPDX-License-Identifier: AGPL-3.0-only
-- Nino yardımcısı: günlük harcama (milyonda bir dolar) ve hazır cevaplar.
-- Hazır cevap: bir sohbetin ilk sorusu (resimsiz) aynı dil ve platformda daha önce sorulduysa modele gitmeden verilir.
CREATE TABLE assistant_cost (
  day INTEGER PRIMARY KEY,
  micro_usd INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE assistant_answers (
  key TEXT PRIMARY KEY,
  reply TEXT NOT NULL,
  created INTEGER NOT NULL,
  hits INTEGER NOT NULL DEFAULT 0
);
