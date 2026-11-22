-- Nino çeviri havuzu: oyun satırlarının sunucuda yapılan çevirileri. Her (satır anahtarı, dil) bir kez çevrilir ve
-- herkese dağıtılır; birkaç saatte bir bağlamla gözden geçirilip iyileştirilir.

CREATE TABLE translations (
  key      TEXT    NOT NULL,           -- satır anahtarı (PackKey; lines.key ile aynı)
  lang     TEXT    NOT NULL,           -- hedef dil: tr, ar, hi, id, th, vi, ur, bn, ms, tl, nl
  game     TEXT    NOT NULL DEFAULT '',-- ilk istendiği oyun (toplu indirmede oyuna göre süzmek için)
  source   TEXT    NOT NULL,           -- çevrilen İngilizce metin
  text     TEXT    NOT NULL,           -- çeviri
  tier     INTEGER NOT NULL,           -- 1: anında (hızlı model), 2: bağlamla gözden geçirilmiş
  created  INTEGER NOT NULL,           -- unix saniye
  updated  INTEGER NOT NULL,           -- son değişiklik; istemciler bundan yenisini çeker
  PRIMARY KEY (key, lang)
) WITHOUT ROWID;
CREATE INDEX translations_lang_updated ON translations (lang, updated);
CREATE INDEX translations_review ON translations (tier, lang, game, created);

-- Çeviri harcaması (mikro dolar), yardımcının harcamasından ayrı.
CREATE TABLE translate_cost (
  day       TEXT    PRIMARY KEY,       -- 'YYYY-MM-DD' (UTC)
  micro_usd INTEGER NOT NULL
);
