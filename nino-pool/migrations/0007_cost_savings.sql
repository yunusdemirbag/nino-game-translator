-- Nino: çeviri masrafını düşürmek için.

-- Benzer satır bulma: ekran okumasının bozduğu kopyalar ("Oh heyl Jason" / "Oh hey Jason") Claude'a yeniden sorulmasın.
-- Her çeviri için sadeleştirilmiş metnin baştaki ve sondaki parçası; aynı parçayı taşıyan satırlar karşılaştırılır.
CREATE TABLE translation_blocks (
  lang  TEXT NOT NULL,
  block TEXT NOT NULL,                 -- "p" + ilk 10 harf ya da "s" + son 10 harf (src/fuzzy.js)
  key   TEXT NOT NULL,
  PRIMARY KEY (lang, block, key)
) WITHOUT ROWID;

-- Gözden geçirme toplu işlem (Batch, yarı fiyat) ile yapılır; cevap gelene kadar satırlar yeniden gönderilmesin.
CREATE TABLE review_batches (
  id      TEXT    PRIMARY KEY,         -- Anthropic toplu işlem kimliği
  model   TEXT    NOT NULL,
  chunks  TEXT    NOT NULL,            -- JSON: [{ id, lang, game, keys:[…] }]
  created INTEGER NOT NULL
);
CREATE TABLE review_pending (
  lang  TEXT NOT NULL,
  key   TEXT NOT NULL,
  batch TEXT NOT NULL,
  PRIMARY KEY (lang, key)
) WITHOUT ROWID;
