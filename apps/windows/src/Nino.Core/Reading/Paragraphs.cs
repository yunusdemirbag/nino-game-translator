// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

namespace Nino.Core.Reading;

/// <summary>Ek alan ve "ekranı çevir" için ortak satır kuralları.</summary>
public static class Paragraphs
{
    /// <summary>Yazı satırı mı: en az 2 harf ve en az 2 harfli bir boşluk sözcüğü ("23m", "9", "+" değil).</summary>
    public static bool IsText(string text) =>
        text.Count(char.IsLetter) >= 2 && TextKey.Words(text).Any(w => w.Count(char.IsLetter) >= 2);

    /// <summary>
    /// Satırları paragraflara toplar: her satır son parçaya eklenir (araya boşluk); yalnız son parça cümle bitiriyorsa
    /// ya da satır büyük harfle başlıyor ve son parça en çok 3 sözcüklü ve virgülle bitmiyorsa (kısa başlık/menü
    /// satırı) yeni parça başlar.
    /// </summary>
    public static IReadOnlyList<string> Build(IEnumerable<string> lines)
    {
        var parts = new List<string>();
        foreach (var raw in lines)
        {
            var line = raw.Trim();
            if (line.Length == 0) continue;
            if (parts.Count == 0)
            {
                parts.Add(line);
                continue;
            }
            var last = parts[^1];
            var newPart = TextKey.EndsSentence(last)
                || (char.IsUpper(line[0]) && TextKey.Words(last).Length <= 3 && !last.TrimEnd().EndsWith(','));
            if (newPart) parts.Add(line);
            else parts[^1] = last + " " + line;
        }
        return parts;
    }

    /// <summary>Sıralı listenin üst ortancası (n/2. eleman); boşsa null.</summary>
    public static double? UpperMedian(IEnumerable<double> values)
    {
        var sorted = values.OrderBy(v => v).ToArray();
        return sorted.Length == 0 ? null : sorted[sorted.Length / 2];
    }
}
