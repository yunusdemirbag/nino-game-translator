// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Globalization;
using System.Text;

namespace Nino.Core.Design;

/// <summary>Tabelanın yazı biçimi: Latin (eğik, dar, büyük harf) ya da Arapça (Kufi, sağdan sola).</summary>
public enum GameRoomScript
{
    Latin,
    Arabic,
}

/// <summary>Tabelada çizilecek metin ve biçimi.</summary>
public readonly record struct GameRoomSignText(string Text, GameRoomScript Script);

/// <summary>
/// Ana ekranda TV'nin üstündeki neon "oyun odası" tabelası: ad temizleme, ne zaman sorulacağı, tabela metni ve renkleri.
/// Platformdan bağımsız; çizim platformundur.
/// </summary>
public static class GameRoomSign
{
    /// <summary>Oda adı en çok bu kadar karakter (harf kümesi sayılır).</summary>
    public const int MaxNameLength = 16;

    /// <summary>Fiş çıkıkken tabelanın saydamlığı.</summary>
    public const double DimOpacity = 0.35;

    /// <summary>Parlak ↔ soluk geçişi.</summary>
    public static readonly TimeSpan FadeDuration = TimeSpan.FromMilliseconds(400);

    /// <summary>Tabela genişliğinin TV genişliğine oranı (yaklaşık).</summary>
    public const double WidthOfTv = 0.40;

    /// <summary>Soldan sağa dolgu renkleri (RGB) ve konumları.</summary>
    public static IReadOnlyList<(double Offset, uint Rgb)> Gradient { get; } =
        [(0.0, 0xFF6AD5), (0.45, 0xC774FF), (1.0, 0x45C2FF)];

    /// <summary>Pembe ışıma: renk (ARGB) ve bulanıklık yarıçapı.</summary>
    public static (uint Argb, double Radius) PinkGlow { get; } = (0x8CFF5AD2, 10);

    /// <summary>Mavi ışıma: renk (ARGB) ve bulanıklık yarıçapı.</summary>
    public static (uint Argb, double Radius) BlueGlow { get; } = (0x7350AAFF, 24);

    /// <summary>Latin kalıbının sonu (her dilde İngilizce).</summary>
    const string LatinTail = "'S GAMING ROOM";

    /// <summary>Arapça kalıbın başı.</summary>
    const string ArabicHead = "غرفة ألعاب ";

    // Arapça konuşulan bölgeler (ISO 3166 iki harf).
    static readonly HashSet<string> ArabicRegions = new(StringComparer.OrdinalIgnoreCase)
    {
        "SA", "AE", "EG", "QA", "KW", "BH", "OM", "JO", "LB", "SY", "IQ", "YE", "PS", "LY", "TN", "DZ", "MA", "SD", "MR",
    };

    /// <summary>
    /// Ad sorusu bu kullanıcıya gösterilir mi: bölge Türkiye, ya da arayüz dili Arapça, ya da bölge Arapça konuşulan
    /// bir ülke.
    /// </summary>
    public static bool AsksName(string? regionCode, string? uiLanguage)
    {
        var region = regionCode?.Trim() ?? "";
        if (region.Equals("TR", StringComparison.OrdinalIgnoreCase)) return true;
        if (string.Equals(uiLanguage, "ar", StringComparison.OrdinalIgnoreCase)) return true;
        return ArabicRegions.Contains(region);
    }

    /// <summary>
    /// Adı temizler: baş/son boşluk atılır, iç boşluklar teke iner, denetim karakterleri atılır, en çok
    /// <see cref="MaxNameLength"/> harf kümesi kalır. Boş kalırsa null.
    /// </summary>
    public static string? CleanName(string? name)
    {
        if (string.IsNullOrWhiteSpace(name)) return null;
        var flat = new StringBuilder(name.Length);
        var space = false;
        foreach (var ch in name)
        {
            if (char.IsWhiteSpace(ch))
            {
                space = flat.Length > 0;
                continue;
            }
            if (char.IsControl(ch)) continue;
            if (space) flat.Append(' ');
            space = false;
            flat.Append(ch);
        }
        if (flat.Length == 0) return null;
        var text = flat.ToString();
        var info = new StringInfo(text);
        if (info.LengthInTextElements > MaxNameLength) text = info.SubstringByTextElements(0, MaxNameLength).TrimEnd();
        return text.Length == 0 ? null : text;
    }

    /// <summary>
    /// Hesap adından önerilen oda adı: ilk sözcük (boşluk, nokta, alt çizgi, tire ya da @ ile ayrılmış). Tamamı küçük
    /// harfse ilk harfi büyütülür. Uygun sözcük yoksa null.
    /// </summary>
    public static string? SuggestedName(string? accountName)
    {
        if (string.IsNullOrWhiteSpace(accountName)) return null;
        var slash = accountName.LastIndexOf('\\');
        if (slash >= 0) accountName = accountName[(slash + 1)..];
        var first = accountName.Split([' ', '.', '_', '-', '@', '\t'], StringSplitOptions.RemoveEmptyEntries)
            .FirstOrDefault(w => w.Any(char.IsLetter));
        if (first is null) return null;
        if (first.All(c => !char.IsLetter(c) || char.IsLower(c)))
            first = char.ToUpperInvariant(first[0]) + first[1..];
        return CleanName(first);
    }

    static readonly char[] TurkishLetters = ['ı', 'İ', 'ğ', 'Ğ', 'ş', 'Ş'];

    /// <summary>Adda Arapça harf var mı.</summary>
    public static bool HasArabicLetters(string name) =>
        name.Any(c => (c >= '؀' && c <= 'ۿ') || (c >= 'ݐ' && c <= 'ݿ') ||
                      (c >= 'ࢠ' && c <= 'ࣿ') || (c >= 'ﭐ' && c <= '﷿') ||
                      (c >= 'ﹰ' && c <= '﻿'));

    /// <summary>
    /// Tabela metni. Ad Arapça harfliyse "غرفة ألعاب {ad}", değilse "{AD}'S GAMING ROOM" (büyük harf; arayüz Türkçe
    /// ya da adda Türkçeye özgü harf varsa Türkçe kuralla: i → İ). Ad boşsa null.
    /// </summary>
    public static GameRoomSignText? Text(string? name, string? uiLanguage = null)
    {
        var clean = CleanName(name);
        if (clean is null) return null;
        if (HasArabicLetters(clean)) return new GameRoomSignText(ArabicHead + clean, GameRoomScript.Arabic);
        var turkish = string.Equals(uiLanguage, "tr", StringComparison.OrdinalIgnoreCase) || clean.IndexOfAny(TurkishLetters) >= 0;
        var upper = clean.ToUpper(turkish ? CultureInfo.GetCultureInfo("tr-TR") : CultureInfo.InvariantCulture);
        return new GameRoomSignText(upper + LatinTail, GameRoomScript.Latin);
    }
}
