-- Panel: dışarıdan alınan sayıların (GitHub indirme sayıları) son bilinen değeri. GitHub isteği sınıra takılınca ya da
-- sunucu yeni açılınca panel boş kalmasın diye saklanır.
CREATE TABLE stats_cache (
  key   TEXT    PRIMARY KEY,
  value TEXT    NOT NULL,
  at    INTEGER NOT NULL
);
