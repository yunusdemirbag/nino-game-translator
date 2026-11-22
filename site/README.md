# Nino web sitesi

Nino'nun tanıtım sayfası ve gizlilik politikası. Düz HTML; derleme adımı, dış yazı tipi, CDN, izleme ya da analiz kodu yok.

## `public/` içinde ne var

| Dosya | Ne işe yarar |
|---|---|
| `index.html` | Tanıtım sayfası (Türkçe, sonunda kısa İngilizce bölüm). CSS sayfanın içinde. |
| `gizlilik.html` | Gizlilik politikası (Türkçe + İngilizce). İçeriği depo kökündeki `PRIVACY.md` ile aynıdır; `PRIVACY.md` değişince bu sayfa da güncellenmeli. Mağazalar `<site>/gizlilik` adresine bağlanır, bu adres değişmemeli. |
| `ar/kurulum.html` | Arapça kurulum rehberi (`/ar/kurulum`): beş adım, TV listesi, video yeri. Görseller iOS uygulamasının Arapça ekranları. |
| `rehber/index.html` | Eski rehber adresleri için yönlendirme: `/rehber/` → `#kurulum`, `#samsung` ve `#lg` → `#tv`, `#android-tv` → `#android-tv-elle`, `#iphone` → `#kurulum`, `#fis` → `#nasil`. |
| `.htaccess` | Apache için: `/gizlilik` → `gizlilik.html`, `/x.html` → `/x` yönlendirmesi, güvenlik başlıkları, `/img/` için uzun önbellek. |
| `_headers` | Aynı başlıklar Cloudflare Pages biçiminde. |
| `img/` | Sitenin görselleri (`docs/nino/v4`, `docs/nino/ekranlar` ve `nino/brand` kaynaklı; webp). `og.png` paylaşım görseli (1200×630). |

## Yerelde bakmak

```bash
python3 -m http.server 8000 -d site/public
```

Sonra tarayıcıda `http://localhost:8000/` açın. Python'un basit sunucusu uzantısız adresleri tanımaz:
gizlilik sayfası yerelde `http://localhost:8000/gizlilik.html` adresindedir (`/gizlilik` yalnız gerçek sunucuda çalışır).

## Yayın

Sitenin nerede barındırılacağına (Apache ya da Cloudflare Pages vb.) ve nasıl yükleneceğine proje sahibi karar verecek.
Bu klasörde sunucu adresi ya da yükleme betiği yoktur.


## Kurulum videosu

Ana sayfadaki `#kurulum` bölümünde ve `ar/kurulum.html`'de `.video` kutusu yer tutucudur (HTML yorumu `KURULUM VİDEOSU`). Video
hazır olunca kutunun yerine `<video controls>` ya da gömülü oynatıcı konur.

## Yayın adresi

Varsayılan: şimdiki canlı adres, GitHub Pages proje sitesi `https://yunusdemirbag.github.io/nino-game-translator/`
(açık depodaki `gh-pages` dalı). Bütün bağlantılar göreli; site hem bu alt klasörde hem bir alan adının kökünde çalışır.
Yalnız `og:image` ve `hreflang` adresleri tam adres olarak bu siteyi gösterir; başka adrese taşınırsa onlar da değişmeli.

Yayınlarken `public/` içeriği `gh-pages` dalının köküne konur. O dalda duran `tv.apk` (Android TV indirmesi,
is.gd/ninotvapk buraya gider) ve `.nojekyll` silinmemeli. GitHub Pages `/gizlilik` adresinde `gizlilik.html`'i,
`/ar/kurulum` adresinde `ar/kurulum.html`'i verir; `.htaccess` ve `_headers` orada kullanılmaz (başka bir sunucu için durur).
