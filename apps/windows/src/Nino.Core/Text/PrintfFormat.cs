// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Globalization;
using System.Text;

namespace Nino.Core.Text;

/// <summary>
/// Katalog metinlerindeki yer tutucuları doldurur: <c>%@</c>, <c>%d</c>, <c>%lld</c>, konumlu <c>%1$@</c>, <c>%%</c>.
/// Uzunluk harfleri (l, h, q, z) atlanır; tür harfleri <c>@ d D i u U x X f g s</c>. Sıralı belirteçler sıfırdan sayar;
/// konumlu <c>%n$</c> n'inci değeri alır ve sayacı ilerletmez. Tanınmayan belirteç olduğu gibi kalır, eksik değer boş
/// yazılır, değerler verilen kültürle yazıya çevrilir.
/// </summary>
public static class PrintfFormat
{
    private const string Types = "@dDiuUxXfgs";
    private const string Lengths = "lhqz";

    /// <summary>Metni değerlerle doldurur.</summary>
    public static string Apply(string pattern, CultureInfo culture, params object?[] values)
    {
        if (pattern.IndexOf('%') < 0) return pattern;
        var sb = new StringBuilder(pattern.Length + 16);
        var next = 0;
        var i = 0;
        while (i < pattern.Length)
        {
            var ch = pattern[i];
            if (ch != '%' || i + 1 >= pattern.Length)
            {
                sb.Append(ch);
                i++;
                continue;
            }
            if (pattern[i + 1] == '%')
            {
                sb.Append('%');
                i += 2;
                continue;
            }
            if (!TryParse(pattern, i, out var end, out var position, out var type))
            {
                sb.Append(ch);
                i++;
                continue;
            }
            var index = position ?? next++;
            sb.Append(index >= 0 && index < values.Length ? Render(values[index], type, culture) : "");
            i = end;
        }
        return sb.ToString();
    }

    /// <summary>Metindeki yer tutucuların listesi (ör. "%1$@", "%lld"); <c>%%</c> sayılmaz. Testler ve denetim için.</summary>
    public static IReadOnlyList<string> Placeholders(string pattern)
    {
        var list = new List<string>();
        var i = 0;
        while (i < pattern.Length)
        {
            if (pattern[i] == '%' && i + 1 < pattern.Length)
            {
                if (pattern[i + 1] == '%') { i += 2; continue; }
                if (TryParse(pattern, i, out var end, out _, out _))
                {
                    list.Add(pattern[i..end]);
                    i = end;
                    continue;
                }
            }
            i++;
        }
        return list;
    }

    // pattern[start] == '%'. Başarıda end belirtecin bittiği yerin bir sonrası; position 0 tabanlı (konumluysa).
    private static bool TryParse(string pattern, int start, out int end, out int? position, out char type)
    {
        end = start;
        position = null;
        type = '\0';
        var i = start + 1;
        var digitsStart = i;
        while (i < pattern.Length && char.IsAsciiDigit(pattern[i])) i++;
        if (i > digitsStart)
        {
            if (i >= pattern.Length || pattern[i] != '$') return false;
            if (!int.TryParse(pattern.AsSpan(digitsStart, i - digitsStart), NumberStyles.None, CultureInfo.InvariantCulture, out var n) || n < 1)
                return false;
            position = n - 1;
            i++;
        }
        while (i < pattern.Length && Lengths.Contains(pattern[i])) i++;
        if (i >= pattern.Length || !Types.Contains(pattern[i])) return false;
        type = pattern[i];
        end = i + 1;
        return true;
    }

    private static string Render(object? value, char type, CultureInfo culture)
    {
        if (value is null) return "";
        if (type is 'x' or 'X')
        {
            try
            {
                var number = Convert.ToInt64(value, CultureInfo.InvariantCulture);
                return number.ToString(type == 'x' ? "x" : "X", CultureInfo.InvariantCulture);
            }
            catch (Exception e) when (e is FormatException or InvalidCastException or OverflowException)
            {
                // Sayı değilse düz yazı.
            }
        }
        return value is IFormattable f ? f.ToString(null, culture) : value.ToString() ?? "";
    }
}
