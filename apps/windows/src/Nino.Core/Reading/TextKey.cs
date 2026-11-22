// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Globalization;
using System.Text;

namespace Nino.Core.Reading;

/// <summary>Okuma hattının ortak metin işlemleri (kültürden bağımsız).</summary>
public static class TextKey
{
    /// <summary>Varsayılan benzerlik eşiği.</summary>
    public const double DefaultThreshold = 0.85;

    /// <summary>
    /// Sadeleştirme (anahtar): kültürden bağımsız küçük harf; harf, birleşen işaret ve sayı karakterleri kalır, öteki
    /// her şey boşluk olur; boşluklar teke iner, baş/son boşluk gider.
    /// <c>Mira: Keep YOUR head down, rookie.</c> → <c>mira keep your head down rookie</c>.
    /// </summary>
    public static string Of(string? text)
    {
        if (string.IsNullOrEmpty(text)) return "";
        var lower = text.ToLowerInvariant();
        var sb = new StringBuilder(lower.Length);
        var pendingSpace = false;
        foreach (var rune in lower.EnumerateRunes())
        {
            if (IsKept(rune))
            {
                if (pendingSpace && sb.Length > 0) sb.Append(' ');
                pendingSpace = false;
                sb.Append(rune.ToString());
            }
            else pendingSpace = true;
        }
        return sb.ToString();
    }

    static bool IsKept(Rune rune) => Rune.IsLetter(rune) || Rune.IsNumber(rune)
        || Rune.GetUnicodeCategory(rune) is UnicodeCategory.NonSpacingMark or UnicodeCategory.SpacingCombiningMark
            or UnicodeCategory.EnclosingMark;

    /// <summary>Satır satır sadeleştirme: her satır ayrı sadeleşir, boş kalanlar atılır, <c>\n</c> ile birleşir.</summary>
    public static string OfLines(string? text) =>
        string.Join("\n", (text ?? "").Replace("\r\n", "\n").Split('\n').Select(Of).Where(s => s.Length > 0));

    /// <summary>Boşluk karakterlerinden bölünmüş, boşları atılmış sözcükler.</summary>
    public static string[] Words(string? text) =>
        (text ?? "").Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries);

    /// <summary>Karakter düzenleme uzaklığı (ekleme, silme, değiştirme birer).</summary>
    public static int EditDistance(string a, string b)
    {
        if (a.Length == 0) return b.Length;
        if (b.Length == 0) return a.Length;
        var prev = new int[b.Length + 1];
        var cur = new int[b.Length + 1];
        for (var j = 0; j <= b.Length; j++) prev[j] = j;
        for (var i = 1; i <= a.Length; i++)
        {
            cur[0] = i;
            for (var j = 1; j <= b.Length; j++)
            {
                var cost = a[i - 1] == b[j - 1] ? 0 : 1;
                cur[j] = Math.Min(Math.Min(cur[j - 1] + 1, prev[j] + 1), prev[j - 1] + cost);
            }
            (prev, cur) = (cur, prev);
        }
        return prev[b.Length];
    }

    /// <summary>Sözcük dizileri arasındaki düzenleme uzaklığı.</summary>
    public static int EditDistance(IReadOnlyList<string> a, IReadOnlyList<string> b)
    {
        if (a.Count == 0) return b.Count;
        if (b.Count == 0) return a.Count;
        var prev = new int[b.Count + 1];
        var cur = new int[b.Count + 1];
        for (var j = 0; j <= b.Count; j++) prev[j] = j;
        for (var i = 1; i <= a.Count; i++)
        {
            cur[0] = i;
            for (var j = 1; j <= b.Count; j++)
            {
                var cost = string.Equals(a[i - 1], b[j - 1], StringComparison.Ordinal) ? 0 : 1;
                cur[j] = Math.Min(Math.Min(cur[j - 1] + 1, prev[j] + 1), prev[j - 1] + cost);
            }
            (prev, cur) = (cur, prev);
        }
        return prev[b.Count];
    }

    /// <summary>Benzerlik oranı: <c>1 − uzaklık / uzun_olanın_uzunluğu</c> (ikisi boşsa 1).</summary>
    public static double Ratio(string a, string b)
    {
        var max = Math.Max(a.Length, b.Length);
        return max == 0 ? 1 : 1 - (double)EditDistance(a, b) / max;
    }

    /// <summary>Sözcük düzeyinde benzerlik oranı.</summary>
    public static double WordRatio(IReadOnlyList<string> a, IReadOnlyList<string> b)
    {
        var max = Math.Max(a.Count, b.Count);
        return max == 0 ? 1 : 1 - (double)EditDistance(a, b) / max;
    }

    /// <summary>
    /// Benzer mi: biri boşsa hayır; birebir aynıysa evet; değilse oran ≥ eşik.
    /// </summary>
    public static bool Similar(string a, string b, double threshold = DefaultThreshold)
    {
        if (a.Length == 0 || b.Length == 0) return false; // boş metin hiçbir metne benzemez
        if (string.Equals(a, b, StringComparison.Ordinal)) return true;
        return Ratio(a, b) >= threshold;
    }

    const string ClosingMarks = "\"'”’»)]";

    /// <summary>
    /// Cümle sonu: metin kırpılır, sondaki <c>" ' ” ’ » ) ]</c> atılır; kalanın son karakteri <c>. ! ? …</c> ise evet.
    /// </summary>
    public static bool EndsSentence(string? text)
    {
        var t = (text ?? "").Trim().TrimEnd(ClosingMarks.ToCharArray());
        if (t.Length == 0) return false;
        return t[^1] is '.' or '!' or '?' or '…';
    }

    /// <summary>
    /// "Temiz sözcükler": sadeleştirilmiş metnin sözcüklerinden 1 karakterden uzun ve hiç sayı karakteri
    /// içermeyenler.
    /// </summary>
    public static string[] CleanWords(string? text) =>
        Words(Of(text)).Where(w => w.Length > 1 && !w.EnumerateRunes().Any(Rune.IsNumber)).ToArray();

    /// <summary>Ortak sözcük sayısı (çoklu küme: her eşleşen sözcük bir kez tüketilir).</summary>
    public static int CommonCount(IEnumerable<string> a, IEnumerable<string> b)
    {
        var bag = new Dictionary<string, int>(StringComparer.Ordinal);
        foreach (var w in b) bag[w] = bag.GetValueOrDefault(w) + 1;
        var common = 0;
        foreach (var w in a)
            if (bag.TryGetValue(w, out var n) && n > 0)
            {
                bag[w] = n - 1;
                common++;
            }
        return common;
    }

    /// <summary>Dizinin ilk k sözcüğü öteki diziye birebir eşit mi (a, b ile başlıyor mu).</summary>
    public static bool StartsWith(IReadOnlyList<string> a, IReadOnlyList<string> b)
    {
        if (b.Count > a.Count) return false;
        for (var i = 0; i < b.Count; i++)
            if (!string.Equals(a[i], b[i], StringComparison.Ordinal)) return false;
        return true;
    }

    /// <summary>a, b ile bitiyor mu (sözcük dizisi olarak).</summary>
    public static bool EndsWith(IReadOnlyList<string> a, IReadOnlyList<string> b)
    {
        if (b.Count > a.Count) return false;
        var o = a.Count - b.Count;
        for (var i = 0; i < b.Count; i++)
            if (!string.Equals(a[o + i], b[i], StringComparison.Ordinal)) return false;
        return true;
    }
}
