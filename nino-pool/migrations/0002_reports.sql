-- SPDX-License-Identifier: AGPL-3.0-only
-- Nino: uygulamalardaki "Sorun Bildir": kullanıcının açıklaması, isteğe bağlı iletişim bilgisi ve uygulama günlüğü,
-- en çok 3 ekran görüntüsü (uygulamada küçültülmüş JPEG). IP adresi yazılmaz; kurulum kimliği tuzlanmış özet olarak tutulur.
CREATE TABLE reports (
  id TEXT PRIMARY KEY,
  created INTEGER NOT NULL,
  install TEXT NOT NULL,
  app TEXT NOT NULL,
  platform TEXT NOT NULL,
  language TEXT NOT NULL DEFAULT '',
  text TEXT NOT NULL,
  contact TEXT NOT NULL DEFAULT '',
  log TEXT NOT NULL DEFAULT '',
  images INTEGER NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'new'
);
CREATE INDEX reports_created ON reports (created DESC);
CREATE INDEX reports_install ON reports (install, created);

CREATE TABLE report_images (
  report TEXT NOT NULL,
  idx INTEGER NOT NULL,
  mime TEXT NOT NULL,
  data BLOB NOT NULL,
  PRIMARY KEY (report, idx)
);
