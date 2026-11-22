-- Panel geçmişi: "şu an oynayan" sayısı saklanmıyordu, en çok kaç kişinin aynı anda oynadığı bilinemiyordu.
-- Saat başına en yüksek değer ve gün başına (Türkiye saatiyle) açan / oynayan kurulum sayısı tutulur. Kişisel veri yok.
CREATE TABLE player_hours (
  hour    INTEGER PRIMARY KEY,          -- saat başı (epoch saniye)
  peak    INTEGER NOT NULL,             -- o saatte aynı anda oynayan en çok kurulum
  samples INTEGER NOT NULL DEFAULT 1    -- kaç kez ölçüldü
);

CREATE TABLE player_days (
  day    INTEGER PRIMARY KEY,           -- gün başı (Türkiye saati, epoch saniye)
  active INTEGER NOT NULL DEFAULT 0,    -- o gün uygulamayı açan farklı kurulum
  played INTEGER NOT NULL DEFAULT 0     -- o gün çeviri başlatan farklı kurulum
);
