-- Nino: ücretsiz çeviri zinciri (src/free.js). Hakkı dolan servis (429) bu zamana kadar atlanır; bütün sunucu örnekleri görür.
CREATE TABLE IF NOT EXISTS free_pause (
  id    TEXT PRIMARY KEY,   -- "servis:model" (FREE_CHAIN girdisi)
  until INTEGER NOT NULL    -- unix saniye
) WITHOUT ROWID;
