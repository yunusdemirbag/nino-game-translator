# Nino ortak altyazı havuzu

Uygulamaların okuduğu, hiçbir oyun paketinde bulunmayan İngilizce altyazı satırlarını toplar. Bu satırlardan oyun
çeviri paketleri hazırlanır. Sıfırdan yazıldı; Cloudflare Workers + D1 üzerinde, ücretsiz katmanda çalışır.

## Neden Cloudflare Workers + D1

- Ücretsiz katman: günde 100 000 istek, D1'de 5 GB, günde 5 milyon satır okuma ve 100 000 satır yazma.
- Supabase'in ücretsiz projesi bir hafta kullanılmayınca duraklatılıyor; havuz ise aylarca sessiz kalıp bir gün
  binlerce satır alabilir. Workers'ta uyku yok, soğuk başlangıç yok denecek kadar kısa.
- Sunucu tek bir JavaScript dosyası ve SQLite şeması; bakımı yok, kendi makinende `wrangler dev` ile birebir çalışır.

Sınır: ücretsiz katmanın günlük **yazma** sınırı. Bir satır yaklaşık 4-5 satır yazımı tutar, bu yüzden sunucu günde
`DAILY_LINE_BUDGET` (varsayılan 15 000) satır kabul eder. Bütçe dolunca 429 + `Retry-After` döner: uygulamalar
satırları cihazda saklar ve ertesi gün gönderir, **hiçbir satır kaybolmaz**. Daha çok satır gerekirse Workers Paid
(aylık 5 $) ile sınır 50 milyon yazıma çıkar; o zaman yalnız bu sayı büyütülür.

## Biçim

`POST /v1/batches` (gövde en çok 512 KB, en çok 500 satır)

```json
{
  "v": 1,
  "batch": "3f6c…-uuid",          // parça kimliği; yeniden gönderimde aynı kalır
  "install": "a1b2…-uuid",        // kuruluma özgü rastgele kimlik (sunucuda tuzlanmış özet olarak tutulur)
  "app": "0.1.6",
  "platform": "mac",              // mac | windows | linux | android | ios | tv
  "lines": [
    {"text": "Get down!", "game": "gta-v", "session": "…-uuid", "count": 3, "first": 1763300000, "last": 1763300100}
  ]
}
```

- `game` isteğe bağlı: uygulamanın bildiği oyun ipucu (son eşleşen paketin kimliği). Yoksa satır "oyunu bilinmeyen"
  olarak `session` ile birlikte saklanır; aynı oturumda görülen satırlar sonradan topluca bir oyuna atanabilir.
- Yanıt `200 {"ok":true,"batch":"…","accepted":N,"rejected":[{"i":3,"reason":"too_long"}],"duplicate":false}`.
  Uygulama parçayı yalnız bu yanıtı (kendi parça kimliğiyle) alınca siler.
- Aynı parça kimliği ikinci kez gelirse hiçbir şey yeniden sayılmaz (`duplicate: true`).
- Satır anahtarı sunucuda metinden hesaplanır (oyun paketlerindeki anahtarın aynısı); "Get down!" ile "GET DOWN" tek satırdır.
- Bozuk satır tek başına reddedilir, parçanın geri kalanı yazılır. Parça bozuksa `400`, çok büyükse `413`.
- Kurulum başına saatte `INSTALL_HOURLY_BATCHES` (60) parça; aşılırsa `429` + `Retry-After`.

Dışa aktarma (`Authorization: Bearer <EXPORT_TOKEN>`):

- `GET /v1/games`: oyunlar, satır ve görülme sayıları (`game: ""` oyunu bilinmeyen).
- `GET /v1/export?game=gta-v&min_installs=1&limit=1000&after=<önceki next>`: oyunun satırları; her satırda anahtar,
  en çok görülen yazılış, toplam görülme, kaç ayrı kurulumda görüldüğü, ilk/son görülme. Sayfalı.
- `GET /v1/sessions`: oyunu bilinmeyen satırların oturumları ve o oturumdaki oyun ipucu;
  `GET /v1/export?game=&session=<oturum>` o oturumun satırları.

Gizlilik: IP adresi hiçbir yere yazılmaz; kurulum kimliği `INSTALL_SALT` ile tuzlanıp kısaltılarak saklanır.

## Yerelde çalıştırma (hesap gerekmez)

```bash
cd nino-pool
npm install
cp .dev.vars.example .dev.vars
npx wrangler d1 migrations apply nino-pool --local
npx wrangler dev --local --port 8787
```

Mac uygulamasını yerel sunucuya bağlamak: `defaults write <uygulama kimliği> ninoPoolURL http://localhost:8787`
ya da `NINO_POOL_URL=http://localhost:8787` ortam değişkeni. Windows'ta `NINO_POOL_URL` ya da
`%LOCALAPPDATA%\…\pool\endpoint.txt` dosyası.

Testler: `npm test` (Node'un yerleşik SQLite'ı ile, hesap ve ağ gerekmez).
Mac istemcisinden gerçek gönderim: `cd core && NINO_POOL_E2E_URL=http://localhost:8787 swift test --filter testE2ELocalServer`.

## Canlı sunucu

- Adres: `https://nino-pool.y-demirbag2506.workers.dev` (uygulamalardaki `liveEndpoint` / `LiveEndpoint` / `LIVE_ENDPOINT`).
- Veritabanı: D1 `nino-pool` (`2d7c0031-0899-4f72-ad6a-802580e34369`, EEUR).
- Gizli değerler (`EXPORT_TOKEN`, `INSTALL_SALT`) Cloudflare'de; kopyası proje sahibinin Mac'inde
  `~/.config/nino-pool/secrets` dosyasında (depoya girmez). `INSTALL_SALT` değiştirilmemeli.
- Dışa aktarma örneği: `set -a; . ~/.config/nino-pool/secrets; set +a;
  curl -H "authorization: Bearer $EXPORT_TOKEN" "$POOL_URL/v1/export?game=gta-v"`.
- Güncelleme: `npx wrangler deploy` (şema değişirse önce `npx wrangler d1 migrations apply nino-pool --remote`).

## Canlıya alma (ilk kurulumda yapılanlar)

1. Ücretsiz Cloudflare hesabı aç (kart gerekmez).
2. `npx wrangler login`
3. `npx wrangler d1 create nino-pool` → çıkan `database_id` değerini `wrangler.toml`'a yaz.
4. `npx wrangler d1 migrations apply nino-pool --remote`
5. Gizli değerler: `npx wrangler secret put EXPORT_TOKEN` (uzun rastgele bir dize) ve `npx wrangler secret put INSTALL_SALT`
   (bir kez seç, sonra değiştirme: değişirse ayrı kurulum sayıları baştan başlar).
6. `npx wrangler deploy` → adres `https://nino-pool.<hesap-adı>.workers.dev` olur (alan adı gerekmez).
7. Uygulamalarda canlı adresi yaz: Mac `NinoPool.liveEndpoint`, Windows `NinoPool.LiveEndpoint`, Android
   `NinoPool.LIVE_ENDPOINT`. O sürüme kadar biriken satırlar ilk açılışta gönderilir.
