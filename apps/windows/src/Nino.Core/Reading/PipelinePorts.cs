// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Imaging;

namespace Nino.Core.Reading;

/// <summary>Paket (ya da havuz) eşleşmesi.</summary>
/// <param name="Translation">Bilinen çeviri.</param>
/// <param name="PackId">Satır tek bir pakete özgü anahtarla geldiyse o paketin kimliği (oyun tanıma oyu); değilse null.</param>
/// <param name="PackName">Günlükte gösterilecek paket adı (biliniyorsa).</param>
public sealed record PackMatch(string Translation, string? PackId = null, string? PackName = null);

/// <summary>
/// Hattın paket araması (paket/havuz tarafı doldurur; önce oyun paketi, sonra havuz…). Metin olduğu gibi verilir
/// (anahtarı arayan kurar). Hızlı olmalı: hattın kilidi altında çağrılır.
/// </summary>
public interface ISubtitlePackLookup
{
    /// <summary>Metnin önceden bilinen çevirisi; yoksa null.</summary>
    PackMatch? Find(string text);
}

/// <summary>TV'ye giden bir altyazı.</summary>
/// <param name="Text">Çeviri (konuşan adı ve satır sonları içinde).</param>
/// <param name="DurationMs">Gösterim süresi.</param>
/// <param name="Box">İngilizce altyazının karedeki yeri (yoksa null).</param>
/// <param name="Paragraphs">Satır satır, sola yaslı gösterim (görev paneli gibi).</param>
/// <param name="Replace">Az önce gösterilenin uzamış/düzelmiş okuması: TV öncekinin yerine koyar.</param>
public sealed record SubtitleShow(string Text, int DurationMs, Box? Box, bool Paragraphs = false, bool Replace = false);

/// <summary>
/// Tam ekran çevirisi ya da telefon/harita örtüsünün bir öğesi (TV <c>screen</c> olayının öğesi). Görünüm alanları telefon
/// ve harita çevirilerinindir; "ekranı çevir" yalnız kaynak, metin, kutu ve satır yüksekliği verir.
/// </summary>
public sealed record ScreenItem(string Source, string Text, Box Box, double? LineHeight)
{
    /// <summary>Çeviride satır sonu varsa satır satır gösterilir.</summary>
    public bool Paragraphs => Text.Contains('\n');

    /// <summary>Harita görev kartı.</summary>
    public bool Card { get; init; }

    /// <summary>Balon oyunun kutusunun yanında.</summary>
    public bool Side { get; init; }

    /// <summary>Oyunun kutusunun yazı rengi (<c>#rrggbb</c>).</summary>
    public string? Ink { get; init; }

    /// <summary>Kutusuz, gölgeli sade yazı.</summary>
    public bool Plain { get; init; }

    /// <summary>Dönme açısı (derece).</summary>
    public double? Angle { get; init; }

    /// <summary>Yazısız zemin paneli.</summary>
    public bool Backdrop { get; init; }

    /// <summary>Eğik yazı.</summary>
    public bool Italic { get; init; }

    /// <summary>Zemin saydamlığı (0–1).</summary>
    public double? Alpha { get; init; }

    /// <summary>Oyunun kutusunun zemin rengi (<c>#rrggbb</c>).</summary>
    public string? Fill { get; init; }
}

/// <summary>
/// TV'ye (ve bilgisayardaki altyazı penceresine) çıkış. Altyazı ve temizle çağrıları hattın kilidi altında yapılır:
/// uygulama hızlı ve engellemeden döner, hatta geri çağrı yapmaz.
/// </summary>
public interface ISubtitleOutput
{
    /// <summary>Altyazı gösterir.</summary>
    void ShowSubtitle(SubtitleShow show);

    /// <summary>Ekrandaki altyazıyı kaldırır.</summary>
    void ClearSubtitle();

    /// <summary>Ekran öğelerini gösterir ("ekranı çevir" ya da sürekli örtü).</summary>
    void ShowScreen(IReadOnlyList<ScreenItem> items, int durationMs, bool overlay) { }

    /// <summary>Ekran öğelerini kaldırır (altyazıya dokunmaz).</summary>
    void ClearScreen() { }

    /// <summary>Ek alanın çevirisini gösterir; metin boşsa o alanın kutusu kalkar.</summary>
    void ShowRegion(string id, string text, Box? box, double? lineHeight) { }

    /// <summary>Ek alanların hepsini temizler.</summary>
    void ClearRegions() { }
}

/// <summary>Telefon/harita kancasına verilen, okumadan sonraki bilgiler.</summary>
/// <param name="Reading">Okuma (satır kutuları alana göre).</param>
/// <param name="RegionImage">Okunan alanın kesilmiş (maskelenmiş) görüntüsü.</param>
/// <param name="Area">Okunan alanın karedeki kutusu.</param>
/// <param name="MaskBox">Telefonun maske kutusu (karede; altı uzatılmış), yoksa null.</param>
/// <param name="PhoneFound">Telefon bu karede bulundu mu (yoksa maske "az önce görülen" telefondandır).</param>
public sealed record PhoneLineContext(OcrReading Reading, BgraFrame RegionImage, Box Area, Box? MaskBox, bool PhoneFound);

/// <summary>
/// Altyazı hattının telefon/harita kancaları (telefon/harita tarafı doldurur). Yoksa telefon aranmaz, harita yok sayılır.
/// <see cref="LocatePhone"/> ve <see cref="FilterLines"/> arka planda (iş parçacığı havuzunda) çağrılır.
/// </summary>
public interface IPhoneLineHooks
{
    /// <summary>Telefon aransın mı (telefon oyunu).</summary>
    bool SearchPhone { get; }

    /// <summary>Harita ekranı açık mı (açıksa altyazı yok sayılır).</summary>
    bool MapOpen { get; }

    /// <summary>Karede telefonu arar (takiple); bulunursa karedeki kutusu.</summary>
    Box? LocatePhone(BgraFrame frame);

    /// <summary>
    /// Telefonun yazılarını okumadan atar (maske içi, açık zeminde koyu yazı, telefon uygulaması yazısı, son mesajlar…).
    /// Hata verirse okuma olduğu gibi kalır.
    /// </summary>
    OcrReading FilterLines(PhoneLineContext context);
}
