// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Globalization;

namespace Nino.Core.Design;

/// <summary>"#RRGGBB" çözümleme ve WCAG 2 kontrast hesabı.</summary>
public static class ColorMath
{
    /// <summary>"#RRGGBB" → 0–1 aralığında üç kanal. Uzunluk 7 değilse, '#' yoksa ya da onaltılık değilse yanlış.</summary>
    public static bool TryParseHex(string? hex, out double red, out double green, out double blue)
    {
        var ok = TryReadChannels(hex, out var packed);
        red = Channel(packed, 2) / 255.0;
        green = Channel(packed, 1) / 255.0;
        blue = Channel(packed, 0) / 255.0;
        return ok;
    }

    /// <summary>"#RRGGBB" → bayt kanalları; geçersizse hata.</summary>
    public static (byte R, byte G, byte B) ParseBytes(string hex)
    {
        if (!TryReadChannels(hex, out var packed)) throw Invalid(hex);
        return ((byte)Channel(packed, 2), (byte)Channel(packed, 1), (byte)Channel(packed, 0));
    }

    /// <summary>Göreli parlaklık (WCAG 2).</summary>
    public static double RelativeLuminance(string hex)
    {
        if (!TryParseHex(hex, out var red, out var green, out var blue)) throw Invalid(hex);
        const double wr = 0.2126, wg = 0.7152, wb = 0.0722;
        return wr * Expand(red) + wg * Expand(green) + wb * Expand(blue);
    }

    /// <summary>İki renk arasındaki kontrast oranı (1–21).</summary>
    public static double ContrastRatio(string first, string second)
    {
        var one = RelativeLuminance(first);
        var two = RelativeLuminance(second);
        var lighter = one > two ? one : two;
        var darker = one > two ? two : one;
        return (lighter + 0.05) / (darker + 0.05);
    }

    // '#' ve altı onaltılık hane; değilse packed = 0.
    static bool TryReadChannels(string? hex, out int packed)
    {
        packed = 0;
        if (hex is not { Length: 7 } || !hex.StartsWith('#')) return false;
        if (int.TryParse(hex.AsSpan(1), NumberStyles.AllowHexSpecifier, CultureInfo.InvariantCulture, out var value))
        {
            packed = value;
            return true;
        }
        return false;
    }

    static int Channel(int packed, int index) => (packed >> (8 * index)) & 0xFF;

    static FormatException Invalid(string hex) => new("Geçersiz renk: " + hex);

    // sRGB kanalını doğrusal ışığa çevirir (WCAG 2 formülü).
    static double Expand(double channel)
    {
        if (channel > 0.03928) return Math.Pow((channel + 0.055) / 1.055, 2.4);
        return channel / 12.92;
    }
}
