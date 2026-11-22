// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

namespace Nino.Core.Support;

/// <summary>
/// Nino'nun kendi sitesindeki rehber bağlantıları. Bütün "Rehberi aç" düğmeleri buradan geçer; site adresi değişirse
/// yalnız <see cref="SiteBase"/> değişir. Çapalar sitenin kendi bölüm kimlikleridir (Türkçe sayfa: kurulum, Android TV'ye
/// elle kurulum, İngilizce bölüm; Arapça rehber ayrı sayfa).
/// </summary>
public static class SiteLinks
{
    /// <summary>Sitenin kökü (sonunda "/"). Kesin alan adı yayın öncesi belirlenecek.</summary>
    public const string SiteBase = "https://yunusdemirbag.github.io/nino-game-translator/";

    /// <summary>Genel kurulum rehberi, arayüz diline göre.</summary>
    public static string Setup(string? uiLanguage) => SiteBase + LanguagePart(uiLanguage) switch
    {
        "tr" => "#kurulum",
        "ar" => "ar/kurulum",
        _ => "#english",
    };

    /// <summary>TV uygulamasını elle kurma rehberi. Android TV'nin kendi bölümü var (Türkçe sayfada).</summary>
    public static string TvApp(string? uiLanguage, bool androidTv) =>
        androidTv && LanguagePart(uiLanguage) == "tr" ? SiteBase + "#android-tv-elle" : Setup(uiLanguage);

    static string LanguagePart(string? language)
    {
        if (string.IsNullOrWhiteSpace(language)) return "";
        var dash = language.IndexOfAny(['-', '_']);
        return (dash > 0 ? language[..dash] : language).ToLowerInvariant();
    }
}
