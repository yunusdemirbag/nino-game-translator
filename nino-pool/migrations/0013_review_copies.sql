-- Nino: gözden geçirme masrafı. Benzer satırdan (bozuk kopya) ve hazır tohumdan gelen çeviriler Opus'a ayrıca
-- gönderilmez: kopya, aslı gözden geçirilince onun yeni metnini alır; tohum olduğu gibi kalır.
-- copy_of: NULL = kendi çevirisi (Claude); 'seed' = hazır tohum; '?' = eski kopya (aslı bilinmiyor); öbürü = aslının anahtarı.
ALTER TABLE translations ADD COLUMN copy_of TEXT;
CREATE INDEX IF NOT EXISTS translations_copy_of ON translations (lang, copy_of) WHERE copy_of IS NOT NULL;

-- Günlük masrafın gözden geçirmeye giden kısmı (micro_usd toplamın içindedir).
ALTER TABLE translate_cost ADD COLUMN review_micro_usd INTEGER NOT NULL DEFAULT 0;
