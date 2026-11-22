// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Text.RegularExpressions;

namespace Nino.Core.Reading;

/// <summary>
/// Navigasyonun dönüş/mesafe satırları ("Turn Left 120 ft 95 ft") konuşma değildir; ne çevrilir ne gösterilir.
/// Kurallar kültürden bağımsızdır.
/// </summary>
public static partial class Directions
{
    const string Crumbs = @"[\s\-–—'""‘’.,·•]*";
    const string Number = @"(?:[0-9]+(?:[.,][0-9]+)?|[Oo])";
    const string Units = "(?:ft|mi|yd|km|m)";

    [GeneratedRegex("^" + Crumbs + @"(?:make\s+an?\s+)?(?:u[\s-]?turn|turn|keep|bear)(?:\s*(?:left|right))?"
        + @"(?:\s+" + Number + @"\s?" + Units + @"\b)*\s*[.!]?$",
        RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)]
    private static partial Regex SingleCommand();

    [GeneratedRegex("^" + Crumbs + @"(?:u[\s-]?turn|turn|keep)\s+(?:left|right)\b(?<rest>.*)$",
        RegexOptions.IgnoreCase | RegexOptions.CultureInvariant | RegexOptions.Singleline)]
    private static partial Regex TurnWithDistance();

    // Yön + mesafe kalıbında birim küçük harf olmalı.
    [GeneratedRegex(Number + @"\s?" + Units + @"\b", RegexOptions.CultureInvariant)]
    private static partial Regex Distance();

    /// <summary>Satır bir yol tarifi mi.</summary>
    public static bool IsDirection(string? line)
    {
        var text = (line ?? "").Trim();
        if (text.Length == 0) return false;
        if (SingleCommand().IsMatch(text)) return true;
        var m = TurnWithDistance().Match(text);
        if (!m.Success) return false;
        var rest = m.Groups["rest"].Value;
        if (!Distance().IsMatch(rest)) return false;
        var left = Distance().Replace(rest, " ");
        return left.Count(char.IsLetterOrDigit) <= 2;
    }

    /// <summary>Okumadan yol tarifi satırlarını atar (hiçbiri atılmadıysa aynı nesne).</summary>
    public static OcrReading Remove(OcrReading reading) => reading.Where(l => !IsDirection(l.Text));
}
