<!-- SPDX-License-Identifier: AGPL-3.0-only -->
<!-- Copyright (C) 2026 Nino contributors -->

# Web TV'lerde Nino Bağlantı Protokolü

Esas tarif: `~/Desktop/NinoCore/docs/tarif/protokol.md` (sürüm 1).

## Sorun

Protokolde TV dinler (sunucu), gönderici bağlanır. LG webOS ve Samsung Tizen uygulamaları web sayfasıdır:
bağlantı **açabilir** (WebSocket, HTTP) ama **dinleyemez**. Bu yüzden TV'nin sunucu olması bu iki TV'de mümkün değil.

## Çözüm: ters arama (TV arar, mesajlar aynı)

Yalnız bağlantıyı kimin açtığı değişir; mesajların sırası ve anlamı protokoldekiyle aynıdır.

1. Gönderici (Mac, telefon) **47800**'de bir HTTP sunucusu açar:
   - `GET /nino/info` → `{"app":"nino","type":"info","version":1,"versions":[1],"name":"Mac","id":"…","role":"sender"}`
     ve `Access-Control-Allow-Origin: *` başlığı (TV sayfası başka kökenden sorar).
   - `GET /nino/ws` → WebSocket.
2. TV, göndericinin adresine `ws://<adres>:47800/nino/ws` ile bağlanır.
3. Bağlantı açılınca **gönderici** ilk mesaj olarak `hello` yollar (protokoldeki gibi). TV `welcome` ya da `error`
   döner. `welcome`'da TV'nin kalıcı rastgele bağlantı kimliği (`id`, ilk açılışta üretilip saklanan UUID) gider;
   gönderici aynı TV'nin yeniden bağlandığını bundan anlar. Bu kimlik ölçümdeki kurulum kimliğinden bilerek ayrıdır
   (ev ağındaki gönderici onu görse de TV'nin ölçümleriyle eşleştiremez). Bundan sonrası protokolle aynı: `show`, `clear`, `ping`/`pong`, `error`.
4. TV'nin kuralları protokoldeki gösterici kurallarıdır: 5 sn içinde `hello` yoksa kapatır; `hello`'dan önce başka
   mesaj ya da `app` ≠ `nino` → `bad_handshake`; desteklenmeyen sürüm → `version_unsupported` + `versions`;
   16 KB'tan büyük mesaj → `too_large` ve kapatır; bilinmeyen `type` yok sayılır; 20 sn hiç mesaj yoksa ekran
   temizlenir. TV tek göndericiye bağlıdır. Gönderici bir bağlantıyı, yerini başka bir bağlantı aldığı için (aynı TV yeniden bağlandı
   ya da TV başka göndericiye geçti) kapatırken `error` (`code: "replaced"`) yollayabilir; TV bunu yalnız ölçüm için
   kopma nedeni olarak kaydeder.
5. Kopunca TV 1, 2, 4, 8 sn bekleyerek (en çok 8) yeniden bağlanır.

## Göndericiyi bulma

- Açılış parametresi: `{"link": "ws://192.168.0.20:47800/nino/ws"}` ya da `{"server": "http://192.168.0.20:47800"}`.
  Gönderici TV uygulamasını açarken verir; TV kaydeder.
- Yoksa kayıtlı adres; o da yoksa ya da art arda 3 kez cevap vermezse ağ taraması: TV'nin kendi ağı ve kayıtlı
  adresin ağı, `.1–.254`, `GET http://<ip>:47800/nino/info` (cevapta `"app":"nino"`).

## Nino uzantıları (isteğe bağlı alanlar ve türler)

Protokol bilinmeyen alanları ve türleri yok saydığı için sürüm artmaz. Uygulamanın tam görünümü için:

- `show` içinde: `box` (`{left,top,right,bottom}`, 0–1), `paragraphs` (bool), `replace` (bool), `light` (0–1),
  `cover` (base64 JPEG). `durationMs` yoksa ya da 0 ise yazı `clear` gelene kadar kalır.
- Yeni türler: `style` (biçim alanları, tarif §3.5), `screen` (`items`, `durationMs`: > 0 ms, açıkça `0` = `screen-clear`
  ya da yeni `screen` gelene kadar, yoksa 20 sn; `overlay`), `screen-clear`,
  `region` (`id`, `text`, `box`, `line`), `region-clear`, `started`, `stopped`.

**Boyut sınırı:** protokol 16 KB der; TV'ler (LG, Samsung, Android TV) buzlu zemin görseli (`show.cover`) için
512 KB'a kadar kabul eder, aşan mesajda `too_large` yollayıp kapatır. Göndericiler `cover` taşımayan mesajları 16 KB
altında tutar. Ortak karar: `side-session-notes/protokol-karari-tv.md`.

**Yerel köprü (Android TV):** Android TV dinleyebildiği için el sıkışmayı kendisi yapar ve hazır mesajları sayfaya
`window.nino.receive({type, ...})` ile verir; sayfa bunları aynı ekran işlerine gönderir.

## Eski göndericiler

Şimdiki Mac/Windows/Android Nino'su 8787'de `/hello` ve `/events` (SSE) sunar. Yeni TV uygulaması bunu da anlar:
adres 8787 ise (ya da açılış parametresi eski biçimdeyse) eski yolla bağlanır; tarama 47800'den sonra 8787'yi de
yoklar. Eski olaylar aynı ekran işlerine gider.

## Göndericiler için yapılacak (NinoCore)

`NinoDisplayServer` TV tarafıdır; web TV'ler için göndericinin de dinlemesi gerekir: 47800'de `/nino/info`
(CORS başlığıyla) ve `/nino/ws` sunan, bağlanan TV'ye `NinoSender` gibi davranan küçük bir "arama kabul" sunucusu.
