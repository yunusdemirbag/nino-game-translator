// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Reading;

namespace Nino.Core.Phone;

/// <summary>GTA 6 harita ekranının tanınması: menü temizliği, harita tuşları, harita ekranı kararı, ekrandan oyun tanıma.</summary>
public static class MapScreen
{
    /// <summary>Harita tuşları (dar liste; telefon okuyucusu bunları görünce örtüyü kaldırır).</summary>
    public static IReadOnlySet<string> MapButtons { get; } = new HashSet<string>(StringComparer.Ordinal)
    {
        "recenter", "2d view", "3d view", "add marker", "remove marker", "set destination", "remove destination",
        "close menu",
    };

    /// <summary>Harita ekranını tanıyan tuşlar: dar liste + işaretçi görünümünün tuşları.</summary>
    public static IReadOnlySet<string> ScreenButtons { get; } =
        new HashSet<string>(MapButtons.Concat(["view on map", "markers", "cinematic"]), StringComparer.Ordinal);

    /// <summary>Harita ekranı için gereken farklı tuş sayısı.</summary>
    public const int ButtonsNeeded = 2;

    /// <summary>
    /// Menü temizliği (simge kırıntıları): baştaki harfsiz ya da (≤ 2 karakter ve tamamı harf olmayan) sözcükler,
    /// sonra büyük harfli sözcükten önceki küçük simge sanılan kısa sözcük (<c>i</c>, <c>ii</c>, <c>Il</c>, <c>II</c>),
    /// sonra sondaki harf/rakam içermeyen sözcükler atılır.
    /// </summary>
    public static string CleanMenu(string? text)
    {
        var tokens = PhoneText.Words(text).ToArray();
        int first = 0, stop = tokens.Length;

        // 1) Baştaki kırıntılar: hiç harf yok ya da kısa ve karışık.
        while (first < stop && IsLeadingCrumb(tokens[first])) first++;

        // 2) Büyük harfli sözcükten önce simge sanılan kısa sözcük.
        while (stop - first > 1 && LooksLikeIcon(tokens[first]) && PhoneText.StartsUpper(tokens[first + 1])) first++;

        // 3) Sondaki noktalama yığınları.
        while (stop > first && !tokens[stop - 1].Any(char.IsLetterOrDigit)) stop--;

        return string.Join(' ', tokens[first..stop]);
    }

    static bool IsLeadingCrumb(string token)
    {
        if (!PhoneText.HasLetter(token)) return true;
        return token.Length <= 2 && token.Any(c => !char.IsLetter(c));
    }

    static bool LooksLikeIcon(string token)
    {
        if (token.Length > 2) return false;
        if (token == "Il" || token == "II") return true;
        return !token.Any(char.IsUpper);
    }

    static string Button(string text) => CleanMenu(text).ToLowerInvariant();

    /// <summary>Satır harita tuşu mu (temizlenmiş küçük hâli dar listede).</summary>
    public static bool IsMapButton(string? text) => MapButtons.Contains(Button(text ?? ""));

    /// <summary>Harita ekranı mı: satırlarda ekran tuşlarından en az 2 farklısı var.</summary>
    public static bool IsMapScreen(IEnumerable<string> lines) =>
        lines.Select(Button).Where(ScreenButtons.Contains).Distinct(StringComparer.Ordinal).Count() >= ButtonsNeeded;

    /// <summary>Okumada GTA 6'ya özgü yazı var mı (harita ekranı, telefonun yazıları…).</summary>
    public static bool ShowsGta6(IReadOnlyList<string> lines) =>
        Gta6Markers.Detect(lines, l => IsMapScreen(l), CleanMenu);
}
