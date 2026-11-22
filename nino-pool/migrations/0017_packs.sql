-- SPDX-License-Identifier: AGPL-3.0-only
-- Copyright (C) 2026 Nino contributors
-- Nino: havuzun kendi çevirilerinden üretilen oyun paketleri (src/packs.js). Uygulamalar `GET /v1/packs` listesine
-- bakar, değişen paketi `GET /v1/packs/<id>` ile indirir. Paket üretimde bir kez gzip'lenip burada saklanır; istekte
-- yeniden sıkıştırılmaz (listedeki sha256 ile inen dosya hep aynı kalsın).

CREATE TABLE packs (
  lang     TEXT    NOT NULL,           -- hedef dil (uygulamalar bugün yalnız 'tr' paketlerini kullanır)
  id       TEXT    NOT NULL,           -- paket kimliği: 'pool-' + oyun kimliği (^[a-z0-9][a-z0-9-]{0,63}$)
  game     TEXT    NOT NULL,           -- havuzdaki oyun kimliği (birden çoğu aynı kimliğe düştüyse ilki)
  title    TEXT    NOT NULL,           -- oyun adı (uygulama oyunu bununla da eşler)
  version  INTEGER NOT NULL,           -- içeriğin değiştiği üretimin zamanı (unix saniye)
  sha256   TEXT    NOT NULL,           -- gzip'li dosyanın SHA-256'sı (64 küçük hex)
  content  TEXT    NOT NULL,           -- gzip'siz JSON'un SHA-256'sı: içerik değişmediyse dosyaya dokunulmaz
  entries  INTEGER NOT NULL,           -- satır sayısı
  bytes    INTEGER NOT NULL,           -- gzip'li boy
  parts    INTEGER NOT NULL,           -- pack_parts'taki parça sayısı
  built    INTEGER NOT NULL,           -- son üretim (unix saniye)
  PRIMARY KEY (lang, id)
) WITHOUT ROWID;

-- Gzip'li dosya parçaları (D1'de bir satır en çok ~2 MB olabildiği için 1 MB'lık parçalar).
CREATE TABLE pack_parts (
  lang TEXT    NOT NULL,
  id   TEXT    NOT NULL,
  part INTEGER NOT NULL,
  data BLOB    NOT NULL,
  PRIMARY KEY (lang, id, part)
) WITHOUT ROWID;
