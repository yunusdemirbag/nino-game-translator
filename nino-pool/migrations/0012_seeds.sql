-- Nino: hazır çeviri tohumu. Başka bir kaynaktan (açık yayınlanmış oyun paketi) gelen "anahtar → çeviri" çiftleri.
-- Havuzda olmayan bir satır istendiğinde Claude'dan önce buraya bakılır; bulunursa para harcanmaz ve satır İngilizcesiyle
-- birlikte translations'a yazılır (sonra gözden geçirilebilir). Toplu indirmeye (GET /v1/translations) girmez.
CREATE TABLE IF NOT EXISTS seeds (
  lang TEXT NOT NULL,
  key  TEXT NOT NULL,           -- PackKey (translations.key ile aynı)
  text TEXT NOT NULL,
  PRIMARY KEY (lang, key)
) WITHOUT ROWID;
