// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Imaging;
using Nino.Core.Settings;

namespace Nino.Core.Link;

/// <summary>TV'ye (ve OBS'e) giden olaylar. Hem eski 8787 çerçevesi hem yeni 47800 mesajı bunlardan üretilir.</summary>
public abstract record TvEvent;

/// <summary>Altyazı. Kutu: İngilizce satırın karedeki yeri (oran).</summary>
public sealed record SubtitleShown(
    string Text,
    int DurationMs = SubtitleShown.DefaultDurationMs,
    Box? Box = null,
    bool Paragraphs = false,
    bool Replace = false,
    string? Source = null) : TvEvent
{
    /// <summary>Süre verilmezse 15 sn.</summary>
    public const int DefaultDurationMs = 15000;
}

/// <summary>Ekrandaki altyazıyı kaldır.</summary>
public sealed record SubtitleCleared : TvEvent;

/// <summary>Çeviri başladı.</summary>
public sealed record TranslationStarted : TvEvent;

/// <summary>Çeviri durdu (rozet, altyazı, örtüler, kutular kalkar).</summary>
public sealed record TranslationStopped : TvEvent;

/// <summary>Tam ekran çevirisi sonuçları ya da sürekli örtüler (telefon/harita).</summary>
public sealed record ScreenShown(IReadOnlyList<ScreenItem> Items, int DurationMs, bool Overlay = false) : TvEvent;

/// <summary>Ekran çevirilerini/örtüleri kaldır (altyazıya dokunmaz).</summary>
public sealed record ScreenCleared : TvEvent;

/// <summary>Ek alan. Metin boşsa o alanın kutusu kalkar.</summary>
public sealed record RegionShown(string Id, string Text, Box? Box = null, double? Line = null) : TvEvent;

/// <summary>Bütün ek alan kutularını kaldır.</summary>
public sealed record RegionsCleared : TvEvent;

/// <summary>Görünüm.</summary>
public sealed record StyleChanged(TvStyle Style) : TvEvent;

/// <summary>Ekran çevirisinin bir öğesi. <see cref="Line"/>: satır yüksekliği, ekran yüksekliğine oranla.</summary>
public sealed record ScreenItem(Box Box, string Text)
{
    public double? Line { get; init; }
    public bool Plain { get; init; }
    public bool Italic { get; init; }
    /// <summary>Oyunun kutusunun zemin rengi, <c>#rrggbb</c>.</summary>
    public string? Fill { get; init; }
    /// <summary>Oyunun kutusunun yazı rengi, <c>#rrggbb</c>.</summary>
    public string? Ink { get; init; }
    public double? Angle { get; init; }
    public double? Alpha { get; init; }
    public bool Side { get; init; }
    public bool Backdrop { get; init; }
    public bool Card { get; init; }
}

/// <summary>TV'ye giden görünüm (değerler TV'nin beklediği küçük harfli adlarla).</summary>
public sealed record TvStyle
{
    public bool AutoSize { get; init; } = true;
    public int Background { get; init; } = 100;
    public string BackgroundShape { get; init; } = "fit";
    public bool Bold { get; init; }
    public int BottomPercent { get; init; } = 7;
    public string DisplayMode { get; init; } = "inApp";
    public string Font { get; init; } = "condensed";
    public int FontSize { get; init; } = 46;
    public string Placement { get; init; } = "cover";
    public bool StackPrevious { get; init; } = true;
    public string TextColor { get; init; } = "white";
    public bool Watermark { get; init; } = true;

    /// <summary>
    /// Kayıttaki stilden TV stili. Örtme yerleşiminde koyuluk 60'tan azsa 100 gider (örtme kutusu oyunun yazısını
    /// kapatmalı); başka yerleşimde 0–100'e kırpılır.
    /// </summary>
    public static TvStyle From(SubtitleStyle s)
    {
        var placement = s.Placement switch
        {
            SubtitlePlacement.Above => "above",
            SubtitlePlacement.Below => "below",
            SubtitlePlacement.Fixed => "fixed",
            _ => "cover",
        };
        var background = placement == "cover" && s.Background < 60 ? 100 : Math.Clamp(s.Background, 0, 100);
        return new TvStyle
        {
            AutoSize = s.EffectiveAutoSize,
            Background = background,
            BackgroundShape = s.BackgroundShape == SubtitleBackgroundShape.Band ? "band" : "fit",
            Bold = s.Bold,
            BottomPercent = s.BottomPercent,
            DisplayMode = s.DisplayMode == SubtitleDisplayMode.Overlay ? "overlay" : "inApp",
            Font = s.Font switch
            {
                SubtitleFont.Modern => "modern",
                SubtitleFont.Rounded => "rounded",
                SubtitleFont.System => "system",
                _ => "condensed",
            },
            FontSize = s.FontSize,
            Placement = placement,
            StackPrevious = s.StackPrevious,
            TextColor = s.TextColor == SubtitleTextColor.Yellow ? "yellow" : "white",
            Watermark = s.Watermark,
        };
    }
}

/// <summary>
/// Masaüstü altyazı penceresinin aldığı olay türü. <see cref="Overlay"/>: sürekli örtüler (telefon/harita panelleri);
/// öğeleriyle gelir, oyunun üstündeki panel katmanına çizilir, altyazı yığınına girmez. <see cref="ScreenClear"/>
/// örtüleri de kaldırır.
/// </summary>
public enum LocalEventKind { Subtitle, Clear, Screen, ScreenClear, Region, RegionClear, Overlay }

/// <summary>
/// Yerel dinleyiciye (bilgisayar penceresi) giden özet. Ağdan bağımsızdır; olay gönderildiği anda çağıranın iş
/// parçacığında verilir. <see cref="Box"/>: alanın yeri ya da altyazıda okunan İngilizce satırın karedeki yeri (varsa;
/// pencere oyunun kendi altyazısıyla üst üste binmesin diye). <see cref="Items"/>: yalnız <see cref="LocalEventKind.Overlay"/>.
/// </summary>
public sealed record LocalSubtitleEvent(
    LocalEventKind Kind,
    string Text = "",
    int DurationMs = 0,
    bool Paragraphs = false,
    bool Replace = false,
    string? RegionId = null,
    Box? Box = null,
    IReadOnlyList<ScreenItem>? Items = null);
