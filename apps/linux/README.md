<!-- SPDX-License-Identifier: AGPL-3.0-only -->
<!-- Copyright (C) 2026 Nino contributors -->

# Nino Linux sunucusu

Ekranı olmayan bir Linux makinesinde (çoğunlukla Docker ile) çalışan Nino. Kurulum ve denetim aynı ağdaki bir
tarayıcıdan açılan panelle yapılır: `http://<sunucu adresi>:8788`.

Davranışın tamamı: [docs/yeni/linux/tarif.md](../../docs/yeni/linux/tarif.md). Durum:
[docs/yeni/linux/ilerleme.md](../../docs/yeni/linux/ilerleme.md).

## Kurulum

```bash
./apps/linux/build.sh
docker compose -f apps/linux/compose.yml up -d
```

- Sunucu ev ağına doğrudan bağlı çalışır (`network_mode: host`); PS5 ve TV böyle bulunur.
- 8788 panel (parolasız; yalnız ev ağında açık tutun), 8787 eski TV uygulamaları, 47800 yeni TV protokolü.
- Veriler `nino-data` biriminde (`/data`): anahtarlar (`secure.json`, 0600), ayarlar, çeviri modeli, günlükler.

Ortam değişkenleri: `NINO_LANG` (tr/en), `NINO_PANEL_PORT`, `NINO_AUTOSTART=1` (açılışta çeviriyi başlatır;
dinlenmedeki PS5'i de uyandırır), `NINO_OCR_STRONG`, `NINO_OCR_MIN_WORD`, `NINO_OCR_DUMP` (Tesseract'a giden
görüntüleri bir klasöre döker).

## Tanı

- Panelde **Günlük** ve **Bu alanı şimdi oku**.
- Konsol bağlamadan, ham bir BGRA karesi üzerinde okumayı ve çeviriyi sınamak için:

```bash
docker run --rm -v "$PWD:/in" nino-linux --read-raw /in/kare.bgra 1920 1080 --translate
```

## Geliştirme

```bash
~/.dotnet/dotnet test apps/linux/Nino.Linux.slnx
./apps/linux/check-headers.sh
```
