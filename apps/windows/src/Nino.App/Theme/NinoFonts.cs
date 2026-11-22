// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Windows;
using System.Windows.Media;
using Nino.Core.Settings;

namespace Nino.App.Theme;

/// <summary>
/// Yazı tipleri. Arayüz: Segoe UI Variable (yoksa Segoe UI). Simgeler: Segoe Fluent Icons (yoksa Segoe MDL2 Assets).
/// Altyazı yazıları uygulamaya gömülüdür (<c>Fonts/</c>, sisteme kurulmaz). Kaynak adları: <c>font.text</c>,
/// <c>font.display</c>, <c>font.icon</c>.
/// </summary>
public static class NinoFonts
{
    /// <summary>Gömülü ailelerde olmayan harfler (Arapça, Tayca, Hintçe, Bengalce) için sistem yazıları.</summary>
    public const string FallbackChain = "Segoe UI, Segoe UI Historic, Nirmala UI, Leelawadee UI";

    public static FontFamily Text { get; } = new("Segoe UI Variable Text, Segoe UI");
    public static FontFamily Display { get; } = new("Segoe UI Variable Display, Segoe UI");
    public static FontFamily Icon { get; } = new("Segoe Fluent Icons, Segoe MDL2 Assets");

    private static readonly Uri FontBase = new("pack://application:,,,/");

    private static FontFamily Embedded(string family) => new(FontBase, $"./Fonts/#{family}, {FallbackChain}");

    /// <summary>"Nino Action" (Barlow Condensed'in yeniden adlandırılmış kopyası), SemiBold ve Bold.</summary>
    public static FontFamily Action { get; } = Embedded("Nino Action");

    /// <summary>"Barlow", SemiBold ve Bold.</summary>
    public static FontFamily Modern { get; } = Embedded("Barlow");

    /// <summary>"Nunito", SemiBold ve Bold (değişken dosya WPF'te ince çizildiği için iki sabit dosya).</summary>
    public static FontFamily Rounded { get; } = Embedded("Nunito");

    /// <summary>Altyazı yazı tipi seçimi; Sade/Sistem için null (yazı bloğu kendi yazı tipiyle kalır).</summary>
    public static FontFamily? ForSubtitle(SubtitleFont font) => font switch
    {
        SubtitleFont.Condensed => Action,
        SubtitleFont.Modern => Modern,
        SubtitleFont.Rounded => Rounded,
        _ => null,
    };

    /// <summary>Belirteç kalınlığı → WPF kalınlığı: bold 700, semibold 600, medium 500, diğerleri 400.</summary>
    public static FontWeight Weight(string weight) => weight.ToLowerInvariant() switch
    {
        "bold" => FontWeights.Bold,
        "semibold" => FontWeights.SemiBold,
        "medium" => FontWeights.Medium,
        _ => FontWeights.Normal,
    };

    /// <summary>Sistemde verilen adla bir yazı tipi var mı (ör. TV indirme sayacı için "Impact"); okunamazsa yok.</summary>
    public static bool IsInstalled(string familyName)
    {
        try
        {
            return Fonts.SystemFontFamilies.Any(f => string.Equals(f.Source, familyName, StringComparison.OrdinalIgnoreCase));
        }
        catch (Exception)
        {
            return false;
        }
    }

    internal static void AddResources(ResourceDictionary into)
    {
        into["font.text"] = Text;
        into["font.display"] = Display;
        into["font.icon"] = Icon;
        into["font.subtitle.action"] = Action;
        into["font.subtitle.modern"] = Modern;
        into["font.subtitle.rounded"] = Rounded;
    }
}
