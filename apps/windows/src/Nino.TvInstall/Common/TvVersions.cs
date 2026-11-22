// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

namespace Nino.TvInstall;

/// <summary>TV uygulaması sürümlerini karşılaştıran iki kural. İkisi de "a, b'den yeni mi" sorusunu cevaplar.</summary>
public static class TvVersions
{
    /// <summary>
    /// Katı karşılaştırma: iki taraf da 2–4 sayısal parçalı standart sürüm olmalı; değilse "yeni değil".
    /// LG kurulum kararı ve uygulamanın "kurduğum sürüm eskidi mi" sorusu bunu kullanır.
    /// </summary>
    public static bool IsNewerStrict(string? a, string? b)
    {
        if (!TryStrict(a, out var x) || !TryStrict(b, out var y)) return false;
        return Compare(x, y) > 0;
    }

    /// <summary>
    /// Esnek karşılaştırma: <c>.</c> ve <c>-</c> ile bölünür, sayı olmayan ya da eksik parça 0 sayılır.
    /// Samsung/Android kurucuları (TV'deki sürüm, Tizen kapısı) bunu kullanır.
    /// </summary>
    public static bool IsNewerLoose(string? a, string? b) => Compare(Loose(a), Loose(b)) > 0;

    static bool TryStrict(string? text, out long[] parts)
    {
        parts = [];
        if (text is null) return false;
        var pieces = text.Trim().Split('.');
        if (pieces.Length is < 2 or > 4) return false;
        var list = new long[pieces.Length];
        for (var i = 0; i < pieces.Length; i++)
        {
            if (pieces[i].Length == 0 || !pieces[i].All(char.IsAsciiDigit) || !long.TryParse(pieces[i], out list[i])) return false;
        }
        parts = list;
        return true;
    }

    static long[] Loose(string? text)
    {
        if (string.IsNullOrWhiteSpace(text)) return [];
        return text.Trim().Split('.', '-').Select(p => long.TryParse(p, out var n) ? n : 0).ToArray();
    }

    static int Compare(long[] x, long[] y)
    {
        var count = Math.Max(x.Length, y.Length);
        for (var i = 0; i < count; i++)
        {
            var a = i < x.Length ? x[i] : 0;
            var b = i < y.Length ? y[i] : 0;
            if (a != b) return a.CompareTo(b);
        }
        return 0;
    }
}
