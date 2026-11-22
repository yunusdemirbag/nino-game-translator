// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Globalization;

namespace Nino.Core.Text;

/// <summary>
/// Arayüz dili. Windows'ta (ve Linux'ta) arayüz dili işletim sisteminin dilidir, çeviri dili değil; uygulama açıkken
/// değişmez. Desteklenmeyen her dil İngilizceye düşer.
/// </summary>
public static class UiLanguage
{
    /// <summary>İngilizce dışındaki desteklenen arayüz dilleri (katalog dosya adları).</summary>
    public static IReadOnlyList<string> Translated { get; } = ["tr", "ar", "hi", "id", "th", "vi", "ur", "bn", "ms", "fil", "nl"];

    /// <summary>Bütün katalog dilleri: İngilizce + <see cref="Translated"/>.</summary>
    public static IReadOnlyList<string> All { get; } = ["en", .. Translated];

    /// <summary>
    /// Kültür adından arayüz dili: küçük harfe çevrilir; "fil" ile başlıyorsa ya da "tl" ise "fil"; değilse ilk iki
    /// harf desteklenen listede ise o; değilse "en". Örnek: "de" → "en", "tr-TR" → "tr", "tl" → "fil".
    /// </summary>
    public static string FromCultureName(string? cultureName)
    {
        var code = (cultureName ?? "").Trim().ToLowerInvariant();
        if (code.StartsWith("fil", StringComparison.Ordinal) || code == "tl" || code.StartsWith("tl-", StringComparison.Ordinal))
            return "fil";
        if (code.Length < 2) return "en";
        var two = code[..2];
        return Translated.Contains(two) ? two : "en";
    }

    /// <summary>Sistemin arayüz kültüründen arayüz dili.</summary>
    public static string FromSystem() => FromCultureName(CultureInfo.CurrentUICulture.Name);

    /// <summary>Arayüz sağdan sola mı (yalnız Arapça ve Urduca).</summary>
    public static bool IsRightToLeft(string language) => language is "ar" or "ur";

    /// <summary>Dilin kültürü (büyük harf ve sayı biçimi için); yoksa sabit kültür.</summary>
    public static CultureInfo CultureFor(string language)
    {
        try
        {
            return CultureInfo.GetCultureInfo(language);
        }
        catch (CultureNotFoundException)
        {
            return CultureInfo.InvariantCulture;
        }
    }
}
