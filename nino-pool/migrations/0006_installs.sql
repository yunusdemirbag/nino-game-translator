-- Panel için kurulumlar: hangi kurulum ne zaman ilk ve son görüldü (tuzlanmış kimlik; kişisel veri yok).
CREATE TABLE installs (
  install    TEXT    PRIMARY KEY,      -- tuzlanmış özet
  platform   TEXT    NOT NULL,
  app        TEXT    NOT NULL,
  first_seen INTEGER NOT NULL,
  last_seen  INTEGER NOT NULL,
  playing    INTEGER NOT NULL DEFAULT 0, -- son "buradayım" (çeviri sürüyor) zamanı
  game       TEXT    NOT NULL DEFAULT '',
  lang       TEXT    NOT NULL DEFAULT ''
);
CREATE INDEX installs_last ON installs (last_seen);
CREATE INDEX installs_playing ON installs (playing);

-- Var olan kullanıcılar: son 30 günün parçalarından (platform bilinmiyor).
INSERT OR IGNORE INTO installs (install, platform, app, first_seen, last_seen)
  SELECT install, '', '', MIN(received_at), MAX(received_at) FROM batches GROUP BY install;
