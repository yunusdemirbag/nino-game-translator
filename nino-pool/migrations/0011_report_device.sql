-- Bildirimlerde cihaz bilgileri: uygulamaların gönderdiği tek satırlık özet
-- ("app: 3.4.0 (19) | device: Mac16,1 | system: macOS 27.0 | tv: Samsung QE55Q70C | console: PS5").
-- Kişiyi tanıtan bilgi içermez (cihaz adı, seri numarası, IP yok). Eski sürümlerin bildirimlerinde boştur.
ALTER TABLE reports ADD COLUMN device TEXT NOT NULL DEFAULT '';
