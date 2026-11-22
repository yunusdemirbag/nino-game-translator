# Çeviri

Okuma hattından gelen her yeni İngilizce cümle Türkçeye çevrilir. Kod:
`Sources/NinoCore/Translation/`.

## Sıra

Bir cümle için kaynaklara sırayla bakılır. İlk bulunan kullanılır.

1. **Yerel önbellek.** Daha önce çevrilmiş cümle diskten gelir. İnternet
   gerekmez.
2. **Oyun paketi.** Oyuna özel, hazır çeviri dosyası. Seçili oyunun paketi
   varsa önce ona bakılır.
3. **Çevirmen zinciri.** Ücretsiz çevirmen sağlayıcıları sırayla denenir.

Zincirden gelen çeviri önbelleğe yazılır. Paketten gelen yazılmaz (zaten
diskte).

## Anahtar (eşleştirme)

Önbellek ve paket aynı anahtarı kullanır:

- Küçük harf, baş/son boşluk kırpılır, iç boşluklar teke iner.
- Kıvrık tırnaklar düz tırnağa, `…` üç noktaya çevrilir.
- Noktalama korunur (`Run.` ile `Run?` farklı cümledir).

## Önbellek

- Disk üzerinde basit bir dosya (JSON satırları ya da SQLite; dış kütüphane
  yok).
- Her kayıt: anahtar, kaynak metin, çeviri, kaynak (`pack` / sağlayıcı adı),
  tarih.
- Üst sınır (ör. 50.000 kayıt). Dolunca en eski kullanılan silinir.
- Okuma hattı `isRepeat` dediyse çeviri her zaman önbellekten gelir.

## Oyun paketi

- Bir JSON dosyası: `{ "nino": 1, "game": "<oyun kimliği>", "lines": {
  "<anahtar>": "<çeviri>" }, "terms": { ... } }`.
- `game` alanı paketin hangi oyuna ait olduğunu söyler.
- Paket yalnız okunur, uygulama içinden değiştirilmez.

## Çevirmen zinciri

- Her sağlayıcı aynı arayüzü uygular: metin ve dil çifti (`en` → `tr`) alır,
  çeviri ya da hata döner.
- Sıra ayarlanabilir. Bir sağlayıcı **hata verirse, zaman aşımına uğrarsa
  (varsayılan 3 sn) ya da boş/aynı metin dönerse** sıradakine geçilir.
- Art arda 3 kez hata veren ya da zaman aşımına uğrayan sağlayıcı 60 sn
  dinlenmeye alınır, o sürede atlanır.
- Varsayılan zincir: cihaz içi çevirmen (varsa) + ayarlardaki HTTP sağlayıcıları.
- Hiçbiri çeviremezse İngilizce metin olduğu gibi döner ve "çevrilemedi"
  işaretlenir. Uygulama çökmez.
- Sağlayıcı adları kodda yalnız genel adlarla geçer; belge ve testlerde marka
  adı kullanılmaz.

## Terimlerin korunması

Oyun terimleri (karakter, yer, eşya adları) çevrilmez ya da sabit karşılıkla
çevrilir.

1. Paketin `terms` listesi ve kullanıcının kendi listesi birleşir.
2. Çeviriden önce metindeki terimler yer tutucuyla değiştirilir: `⟦0⟧`, `⟦1⟧`…
   En uzun terim önce eşleşir, kelime sınırına bakılır, büyük/küçük harf fark
   etmez.
3. Çeviri gelince yer tutucular terimin karşılığıyla geri konur.
4. Bir yer tutucu çeviride kaybolduysa o sağlayıcının sonucu geçersiz sayılır
   ve sıradakine geçilir.

## Yalnız terimden oluşan cümle

`Osk!` gibi yalnız terim ve noktalamadan oluşan cümle çevirmene gitmez; terim
karşılığıyla hemen döner.

## Türkçe son düzeltme

Çevirmenden gelen metin şu kurallarla toparlanır:

- `…` üç noktaya çevrilir, fazla boşluklar teke iner.
- Noktalamadan önceki boşluk silinir (`Tamam ,` → `Tamam,`).
- Virgül ve noktalı virgülden sonra harf geliyorsa boşluk konur.
- `..` tek noktaya, dört ve fazlası üç noktaya iner.
- Kaynak büyük harfle başlıyorsa ilk harf Türkçe kurala göre büyütülür
  (`i` → `İ`, `ı` → `I`).
- Kaynak `.`, `!`, `?` ya da `...` ile bitiyor ama çeviri noktalamasız
  bitiyorsa aynı işaret eklenir.

## Cihaz içi sağlayıcı

- Apple'ın Translation çerçevesi (macOS 26+, iOS 26+). Ücretsiz, internetsiz.
- Ayar `translation.useOnDevice` açıksa (varsayılan) zincirin **başına** konur.
- İngilizce→Türkçe dil paketi cihazda yüklü değilse hata verir; zincir
  sıradakine geçer. Yer tutucular (`⟦0⟧`) bu çevirmende korunuyor (denendi).
- Sağlayıcı adı: `device`.

## Dinlenme kuralı

Yalnız **hata** ve **zaman aşımı** dinlenme sayacını artırır. Boş, kaynakla aynı
ya da yer tutucusu kaybolmuş sonuç sıradakine geçer ama sağlayıcıyı dinlenmeye
almaz (`Hmm.` gibi satırlar haklı olarak aynı dönebilir).

## Önbelleğin diske yazılması

`Translator` her 20 yeni kayıtta bir ve `flush()` çağrılınca önbelleği diske
yazar. `NinoEngine.run` bitince de yazar.

## Genel HTTP sağlayıcısı

Kodda hiçbir hizmetin adı ya da anahtarı yoktur. Bir sağlayıcı ayarlarla tarif
edilir: ad, adres şablonu, yöntem (GET/POST), başlıklar, gövde şablonu ve
cevapta çeviriye giden yol (`["data", "0", "text"]`). Şablonlarda `{text}`,
`{source}`, `{target}`, `{key}` kullanılır. Anahtar Keychain'den gelir. Gövdede
değerler JSON için, adreste URL için kaçışlanır. Cevap parçalı dizi ise
(`["Mer", "haba"]`) birleştirilir.

## Sonuç

```
Translation
  source      İngilizce cümle
  text        Türkçe çeviri
  origin      cache | pack | provider(<genel ad>) | none
```
