# Oyun çeviri paketi

Oyuna özel, hazır çeviri dosyası. Çeviri sırasında önbellekten sonra, çevirmen
zincirinden önce bakılır. Kod: `Sources/NinoCore/Packs/`.

## Dosya

Uzantı `.ninopack.json`. UTF-8 JSON.

```json
{
  "nino": 1,
  "game": { "id": "ornek-oyun", "title": "Örnek Oyun", "version": "1.0" },
  "languages": { "source": "en", "target": "tr" },
  "terms": [
    { "source": "Osk" },
    { "source": "Vale Harbor", "target": "Vale Limanı" }
  ],
  "lines": [
    { "source": "Come here.", "target": "Buraya gel.", "speaker": "Osk" }
  ]
}
```

| Alan | Zorunlu | Anlamı |
|---|---|---|
| `nino` | evet | Biçim sürümü. Şimdilik `1`. |
| `game.id` | evet | Oyun kimliği: küçük harf, rakam, `-`, `.`. |
| `game.title` | hayır | Görünen ad. |
| `game.version` | hayır | Paketin sürümü. |
| `languages` | hayır | Varsayılan `en` → `tr`. |
| `terms` | hayır | Korunacak terimler. `target` yoksa olduğu gibi kalır. |
| `lines` | evet | Satırlar. `source` ve `target` boş olamaz. `speaker` isteğe bağlı. |

Bilinmeyen alanlar yok sayılır.

## Doğrulama

- `nino` 1 değilse paket yüklenmez (`unsupportedVersion`).
- `game.id` boşsa ya da izin verilmeyen karakter varsa yüklenmez (`badGameID`).
- Boş `source`/`target` olan satır atlanır ve uyarı olarak sayılır.
- Aynı anahtar iki kez geçerse **ilki** kalır, ikincisi uyarı olur.

## Eşleme

1. **Tam eşleme:** cümlenin anahtarı (bkz. `ceviri.md`) paketteki bir satırın
   anahtarına eşitse o satır döner.
2. **Bulanık eşleme:** OCR hatalarını yakalamak için. Yalnız şu durumda denenir:
   - Cümlenin benzerlik anahtarı (harf/rakam) en az **12 karakter**.
   - Aday satırla en az yarı yarıya ortak kelime var.
   - Boyları birbirinin %80–%125'i arasında.
   - Son işaret aynı türde (soru `?` ile soru olmayan eşleşmez).
   - Benzerlik **0.90** ve üstü.
   Birden çok aday varsa en benzeri, eşitse paketteki ilk satır seçilir.
3. Hiçbiri yoksa `nil`.

## Kütüphane

- Paketler veri klasöründeki `packs/` altında durur.
- Kütüphane klasördeki tüm `.ninopack.json` dosyalarını yükler; bozuk olanları
  atlar ve hatasını listeler.
- Aynı `game.id` iki dosyada varsa `game.version` büyük olan kalır.
- Seçili oyunun paketi `pack(for:)` ile alınır.
