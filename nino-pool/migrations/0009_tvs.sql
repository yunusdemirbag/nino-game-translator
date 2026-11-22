-- Panel: Nino TV uygulamasının kurulu olduğu TV'ler (marka ve model). TV uygulaması günde bir kez bildirir.
-- Kimlik TV'de üretilen rastgele bir sayıdır ve yalnız tuzlanmış özetiyle tutulur; kişisel veri yok.
CREATE TABLE tvs (
  tv         TEXT    PRIMARY KEY,   -- tuzlanmış özet
  brand      TEXT    NOT NULL,      -- androidtv | samsung | lg
  model      TEXT    NOT NULL,      -- ör. "TCL 98U95A", "QE55Q70CATXTK"
  app        TEXT    NOT NULL,      -- TV uygulamasının sürümü
  first_seen INTEGER NOT NULL,
  last_seen  INTEGER NOT NULL
);
CREATE INDEX tvs_model ON tvs (brand, model);
