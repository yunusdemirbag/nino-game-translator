// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

namespace Nino.Core.Reading;

/// <summary>
/// Okuma hattının metin karşılaştırma kuralları: aynı altyazı mı, düzeltme mi, kötü yeniden okuma mı, uzama mı, anlam
/// işareti ekliyor mu ve çeviriye gönderme yardımcıları. Girdiler ham metin olabilir; her kural kendisi sadeleştirir.
/// </summary>
public static class TextCompare
{
    static readonly HashSet<string> Negations = new(StringComparer.Ordinal)
    {
        "not", "no", "never", "nothing", "nobody", "none", "nowhere", "neither", "nor", "cannot", "dont", "doesnt",
        "didnt", "cant", "wont", "isnt", "arent", "wasnt", "werent", "aint", "couldnt", "shouldnt", "wouldnt", "havent",
        "hasnt", "hadnt", "mustnt", "neednt",
    };

    static string[] KeyWords(string? text) => TextKey.Words(TextKey.Of(text));

    static bool IsAsciiNumber(string w) => w.Length > 0 && w.All(char.IsAsciiDigit);

    static string FoldDigits(string w)
    {
        var chars = w.ToCharArray();
        for (var i = 0; i < chars.Length; i++)
            chars[i] = chars[i] switch
            {
                '0' => 'o', '1' => 'i', '3' => 'e', '4' => 'a', '5' => 's', '7' => 't', '8' => 'b', _ => chars[i],
            };
        return new string(chars);
    }

    static bool SameGlyph(string a, string b) =>
        string.Equals(a, b, StringComparison.Ordinal) || (IsAsciiNumber(a) && FoldDigits(a) == b);

    static (List<string> Numbers, int Negations) Markers(string[] words)
    {
        var numbers = new List<string>();
        var negations = 0;
        string? previous = null;
        foreach (var raw in words)
        {
            string w;
            if (IsAsciiNumber(raw))
            {
                numbers.Add(raw);
                w = raw;
            }
            else w = raw.Any(char.IsDigit) ? FoldDigits(raw) : raw;
            if (Negations.Contains(w) || (w == "t" && previous is not null && Negations.Contains(previous + "t")))
                negations++;
            previous = w;
        }
        return (numbers, negations);
    }

    /// <summary>
    /// Yeni okuma gönderilene göre fazladan bir olumsuzluk ya da sayı taşıyor mu (harf farkı küçük, anlam farkı büyük).
    /// Eksilen işaret sayılmaz; rakam/harf glif karışıklıkları ("1" ~ "I") hizalanıp düşülür.
    /// </summary>
    public static bool AddsMeaningMarker(string? reading, string? sent)
    {
        var w = KeyWords(reading);
        var s = KeyWords(sent);
        var (wNumbers, wNeg) = Markers(w);
        var (sNumbers, sNeg) = Markers(s);
        if (wNeg > sNeg) return true;
        if (wNumbers.Count == 0) return false;
        void Drop(string word) => wNumbers.Remove(word);
        if (w.Length == s.Length)
        {
            for (var i = 0; i < w.Length; i++)
                if (w[i] != s[i] && SameGlyph(w[i], s[i])) Drop(w[i]);
        }
        else
        {
            var start = 0;
            while (start < w.Length && start < s.Length && SameGlyph(w[start], s[start]))
            {
                if (w[start] != s[start]) Drop(w[start]);
                start++;
            }
            int i = w.Length - 1, j = s.Length - 1;
            while (i >= start && j >= start && SameGlyph(w[i], s[j]))
            {
                if (w[i] != s[j]) Drop(w[i]);
                i--;
                j--;
            }
        }
        foreach (var n in wNumbers)
            if (!sNumbers.Remove(n)) return true;
        return false;
    }

    /// <summary>
    /// Uzama: yeni metin eskinin sonuna (ya da başı okunmamışsa başına) sözcük eklenmiş hali mi
    /// (bütün sadeleştirilmiş sözcüklerle).
    /// </summary>
    public static bool IsExtension(string? newer, string? older)
    {
        var n = KeyWords(newer);
        var o = KeyWords(older);
        if (o.Length == 0 || n.Length <= o.Length) return false;
        if (TextKey.StartsWith(n, o)) return true;
        return o.Length >= 2 && TextKey.EndsWith(n, o);
    }

    /// <summary>
    /// Aynı altyazı mı: okuma, gönderilmiş satırın (satır satır olabilir) yeniden okuması mı. Uzayan metin ve anlam
    /// işareti ekleyen okuma yenidir; yarım okuma yalnız tam satırlar okunduysa aynıdır.
    /// </summary>
    public static bool SameSubtitle(string? reading, string? sent)
    {
        var sentLines = TextKey.OfLines(sent).Split('\n', StringSplitOptions.RemoveEmptyEntries);
        var flat = string.Join(" ", sentLines);
        var key = TextKey.Of(reading);
        if (AddsMeaningMarker(key, flat)) return false;
        var x = TextKey.CleanWords(key);
        var y = TextKey.CleanWords(flat);
        if (y.Length > 0 && x.Length > y.Length && (TextKey.StartsWith(x, y) || TextKey.EndsWith(x, y))) return false;
        if (TextKey.Similar(key, flat)) return true;
        if (x.Length > 0 && x.Length < y.Length)
        {
            var fromStart = TextKey.StartsWith(y, x);
            if (fromStart || TextKey.EndsWith(y, x))
            {
                var counts = sentLines.Select(l => TextKey.CleanWords(l).Length);
                if (!fromStart) counts = counts.Reverse();
                var total = 0;
                foreach (var c in counts)
                {
                    total += c;
                    if (total == x.Length) return true;
                    if (total > x.Length) return false;
                }
                return false;
            }
        }
        var common = TextKey.CommonCount(x, y);
        if (x.Length >= 4 && x.Length <= y.Length && common >= x.Length * 0.85) return true;
        var shorter = Math.Min(x.Length, y.Length);
        var longer = Math.Max(x.Length, y.Length);
        if (shorter < 6 || shorter < longer * 0.75) return false;
        return (double)common / longer >= 0.75;
    }

    /// <summary>Düzeltme mi: yeni metin eskinin büyümüş ya da düzeltilmiş hali mi (TV "yerine koy" kararı).</summary>
    public static bool IsCorrection(string? newer, string? older)
    {
        var a = TextKey.Of(newer);
        var b = TextKey.Of(older);
        if (a.Length == 0 || b.Length == 0) return false; // boşla düzeltme olmaz
        if (IsExtension(a, b) || IsExtension(b, a)) return true;
        if (TextKey.Similar(a, b, 0.8)) return true;
        var x = TextKey.CleanWords(a);
        var y = TextKey.CleanWords(b);
        if (Math.Min(x.Length, y.Length) < 5) return false;
        if (TextKey.WordRatio(x, y) >= 0.65) return true;
        return (double)TextKey.CommonCount(x, y) / Math.Max(x.Length, y.Length) >= 0.7;
    }

    /// <summary>
    /// Kötü yeniden okuma mı: yeni okuma, gönderilmiş cümlenin daha kötü (ya da eşit) bozuk kopyası mı. Burada her zaman
    /// gürültü puanı (<see cref="OcrJunk.Score"/>) kullanılır.
    /// </summary>
    public static bool IsWorseReread(string? reading, string? sent)
    {
        var x = TextKey.CleanWords(reading);
        var y = TextKey.CleanWords(sent);
        if (x.Length < 5 || y.Length == 0) return false;
        if (IsExtension(reading, sent) || IsExtension(sent, reading) || AddsMeaningMarker(reading, sent)) return false;
        var reads = TextKey.WordRatio(x, y) >= 0.65 || TextKey.Similar(TextKey.Of(reading), TextKey.Of(sent), 0.75);
        return reads && OcrJunk.Score(reading) < OcrJunk.Score(sent) + 4;
    }

    /// <summary>Tam görünüyor: boş olmayan her satırın ilk harfi büyük ve satır cümle bitiriyor.</summary>
    public static bool LooksComplete(string? text)
    {
        var lines = (text ?? "").Replace("\r\n", "\n").Split('\n').Where(l => l.Trim().Length > 0).ToArray();
        if (lines.Length == 0) return false;
        foreach (var l in lines)
        {
            var first = l.FirstOrDefault(char.IsLetter);
            if (first == default || !char.IsUpper(first) || !TextKey.EndsSentence(l)) return false;
        }
        return true;
    }

    /// <summary>Parça eşleşmesi: tam görünmeyen kaynak, önceki metnin içinde sözcük sınırlarıyla geçen kısa bir parça mı.</summary>
    public static bool IsPackFragment(string? source, string? previous)
    {
        var s = TextKey.Of(source);
        var p = TextKey.Of(previous);
        return !LooksComplete(source) && s.Length > 0 && s.Length < p.Length && (" " + p + " ").Contains(" " + s + " ", StringComparison.Ordinal);
    }

    /// <summary>İlgili mi: ortak sözcük var mı (kısa olan tek sözcükse 1, değilse en az 2 ve kısanın yarısı).</summary>
    public static bool Related(string? a, string? b)
    {
        var x = KeyWords(a);
        var y = KeyWords(b);
        if (x is [] || y is []) return false;
        var common = TextKey.CommonCount(x, y);
        var shorter = Math.Min(x.Length, y.Length);
        return shorter <= 1 ? common >= 1 : common >= 2 && common * 2 >= shorter;
    }

    /// <summary>
    /// Yeni okuma eskinin yeniden okuması mı (aynı cümlenin bozuk ya da eksik okunuşu).
    /// <paramref name="isMisread"/> hattın "okuma bozuk mu" ölçüsüdür.
    /// </summary>
    public static bool IsRereadOf(string? newer, string? older, Func<string, bool> isMisread)
    {
        if (AddsMeaningMarker(newer, older)) return false;
        var nk = TextKey.Of(newer);
        var ok = TextKey.Of(older);
        var n = TextKey.Words(nk);
        var o = TextKey.Words(ok);
        if (nk.Length >= 4 && n.Length == o.Length && TextKey.Similar(nk, ok, 0.75)) return true;
        if (n.Length == o.Length && n.Length >= 2)
        {
            var differing = Enumerable.Range(0, n.Length).Where(i => n[i] != o[i]).ToArray();
            if (differing.Length >= 1 && differing.Length * 2 <= n.Length && differing.All(i => isMisread(n[i])))
                return true;
        }
        if (isMisread(newer ?? "") || isMisread(older ?? "")) return Related(newer, older);
        if (n.Length == 0 || n.Length > o.Length) return false;
        if (n.Length >= 2 && n.Length < o.Length)
        {
            var positions = new List<int>();
            var at = 0;
            foreach (var w in n)
            {
                while (at < o.Length && o[at] != w) at++;
                if (at == o.Length) break;
                positions.Add(at++);
            }
            if (positions.Count == n.Length && positions[^1] - positions[0] + 1 > n.Length) return true;
        }
        var trimmed = (newer ?? "").Trim();
        var startsLower = trimmed.Length > 0 && !char.IsUpper(trimmed[0]);
        if (TextKey.EndsSentence(newer) && !(startsLower && n.Length < o.Length)) return false;
        for (var i = 0; i + n.Length <= o.Length; i++)
            if (TextKey.StartsWith(o[i..], n)) return true;
        return false;
    }

    static string[] LinesOf(string? text) => (text ?? "").Replace("\r\n", "\n").Split('\n');

    /// <summary>Satır önceki metin tarafından örtülüyor mu (boş, yeniden okuması ya da satırlarından birinin tekrarı).</summary>
    public static bool IsCovered(string? line, string? previous, Func<string, bool> isMisread)
    {
        var key = TextKey.Of(line);
        if (key.Length == 0) return true;
        if (IsRereadOf(line, (previous ?? "").Replace("\r\n", " ").Replace('\n', ' '), isMisread)) return true;
        foreach (var p in LinesOf(previous))
            if (TextKey.Of(p) == key || IsRereadOf(line, p, isMisread)) return true;
        return false;
    }

    /// <summary>Boş olmayan satırlar var ve hepsi önceki metin tarafından örtülü.</summary>
    public static bool AllLinesCovered(string? text, string? previous, Func<string, bool> isMisread)
    {
        var lines = LinesOf(text).Where(l => l.Trim().Length > 0).ToArray();
        return lines.Length > 0 && lines.All(l => IsCovered(l, previous, isMisread));
    }

    /// <summary>
    /// Eksik satırları koru: eskinin boş olmayan, bozuk olmayan, daha iyide örtülü olmayan ve daha iyinin hiçbir
    /// satırının "anlam ekleyen ve 0,85 benzer" düzeltmesi olmadığı satırları daha iyinin sonuna eklenir.
    /// </summary>
    public static string KeepMissingLines(string better, string? older, Func<string, bool> isMisread)
    {
        var betterLines = LinesOf(better);
        var keep = LinesOf(older).Where(l => l.Trim().Length > 0 && !isMisread(l) && !IsCovered(l, better, isMisread)
            && !betterLines.Any(b => AddsMeaningMarker(b, l) && TextKey.Similar(TextKey.Of(b), TextKey.Of(l))))
            .ToArray();
        return keep.Length == 0 ? better : better.TrimEnd() + "\n" + string.Join("\n", keep);
    }

    /// <summary>Sıradakinin yerini alır: yeni, sıradakinin düzeltmesi ve sıradaki yeninin uzaması değil.</summary>
    public static bool ReplacesQueued(string? newer, string? queued) =>
        IsCorrection(newer, queued) && !IsExtension(queued, newer);
}
