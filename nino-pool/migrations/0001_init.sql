-- Nino ortak altyazı havuzu: ilk şema.
-- Kişisel veri yok: kurulum kimliği sunucuda tuzlanmış özet olarak tutulur, IP adresi hiç yazılmaz.

-- Oyun başına satırlar. game = '' : hangi oyundan geldiği bilinmiyor.
CREATE TABLE lines (
  game       TEXT    NOT NULL,
  key        TEXT    NOT NULL,           -- PackKey: sadeleştirilmiş metnin SHA-256'sının ilk 8 baytı (hex), sunucuda hesaplanır
  text       TEXT    NOT NULL,           -- ilk gelen yazılış
  seen       INTEGER NOT NULL,           -- toplam görülme
  installs   INTEGER NOT NULL DEFAULT 0, -- kaç ayrı kurulumda görüldü
  first_seen INTEGER NOT NULL,           -- unix saniye
  last_seen  INTEGER NOT NULL,
  PRIMARY KEY (game, key)
) WITHOUT ROWID;

-- Ayrı kurulum sayısı için (kurulum özeti, satır başına bir kez).
CREATE TABLE line_installs (
  game    TEXT NOT NULL,
  key     TEXT NOT NULL,
  install TEXT NOT NULL,
  PRIMARY KEY (game, key, install)
) WITHOUT ROWID;

-- Aynı anahtarın farklı yazılışları (büyük-küçük harf, noktalama); dışa aktarmada en çok görüleni seçilir.
CREATE TABLE line_texts (
  key  TEXT    NOT NULL,
  text TEXT    NOT NULL,
  seen INTEGER NOT NULL,
  PRIMARY KEY (key, text)
) WITHOUT ROWID;

-- Oyunu bilinmeyen satırların hangi oyun oturumunda görüldüğü (oturum = uygulamanın her açılışta ürettiği rastgele kimlik).
-- Aynı oturumda görülen satırlar aynı oyundandır; sonradan topluca bir oyuna atanabilir.
CREATE TABLE line_sessions (
  session TEXT NOT NULL,
  key     TEXT NOT NULL,
  PRIMARY KEY (session, key)
) WITHOUT ROWID;

-- Oturumların hangi oyun ipucuyla görüldüğü (oyunu bilinmeyen satırları çözmek için).
CREATE TABLE sessions (
  session    TEXT    NOT NULL,
  game       TEXT    NOT NULL,
  lines      INTEGER NOT NULL,
  first_seen INTEGER NOT NULL,
  last_seen  INTEGER NOT NULL,
  PRIMARY KEY (session, game)
) WITHOUT ROWID;

-- İşlenmiş parçalar: yanıtı kaybolup yeniden gönderilen parça ikinci kez sayılmaz. 30 gün tutulur.
CREATE TABLE batches (
  id          TEXT    PRIMARY KEY,
  install     TEXT    NOT NULL,
  received_at INTEGER NOT NULL,
  lines       INTEGER NOT NULL
);
CREATE INDEX batches_install_time ON batches (install, received_at);
CREATE INDEX batches_time ON batches (received_at);

-- Günlük kullanım (ücretsiz katman sınırı için).
CREATE TABLE usage (
  day     TEXT    PRIMARY KEY,           -- 'YYYY-MM-DD' (UTC)
  lines   INTEGER NOT NULL,
  batches INTEGER NOT NULL
);
