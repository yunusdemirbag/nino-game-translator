// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Text;
using System.Text.RegularExpressions;

namespace Nino.Core.Reading;

/// <summary>
/// OCR çöpü: süslü yazı tipinde ya da kararsız görüntüde tanıyıcının ürettiği anlamsız harf-rakam-simge dizileri.
/// Satır içi temizlik (<see cref="Clean(string)"/>), gürültü puanı (<see cref="Score"/>), "çöp gibi mi"
/// (<see cref="LooksLikeGarbage"/>) ve "bozuk okuma" izi (<see cref="IsMisread"/>). Hepsi platformdan bağımsızdır.
/// </summary>
public static partial class OcrJunk
{
    const string SymbolChars = "$@#%^*_=|\\~<>{}¢£¥§©®°±µ¶¤";
    const string QuoteBrackets = "\"'“”‘’«»()[]";

    /// <summary>Simge mi (<c>$ @ # % ^ * _ = | \ ~ &lt; &gt; { } ¢ £ ¥ § © ® ° ± µ ¶ ¤</c>).</summary>
    public static bool IsSymbol(char c) => SymbolChars.Contains(c);

    /// <summary>Kenar karakteri: simge olmayan ve (noktalama/sembol sınıfında ya da tırnak/parantez) olan.</summary>
    public static bool IsEdge(char c)
    {
        if (IsSymbol(c)) return false;
        if (QuoteBrackets.Contains(c)) return true;
        return char.IsPunctuation(c) || char.IsSymbol(c);
    }

    /// <summary>Parçanın baş kenarı, çekirdeği ve son kenarı.</summary>
    public readonly record struct Token(string Lead, string Core, string Trail);

    /// <summary>Boşlukla ayrılmış parçayı baş/çekirdek/son diye ayırır.</summary>
    public static Token Split(string part)
    {
        var start = 0;
        while (start < part.Length && IsEdge(part[start])) start++;
        if (start == part.Length) return new(part, "", "");
        var end = part.Length;
        while (end > start && IsEdge(part[end - 1])) end--;
        return new(part[..start], part[start..end], part[end..]);
    }

    [GeneratedRegex("^(?:[A-Za-z]{1,4}[0-9]{1,4}"
        + "|[0-9]+(?:st|nd|rd|th|s|k|K|m|km|kg|cm|mm|p|x|fps|hp|HP|XP|xp|v|V|D|d)"
        + "|[xX][0-9]{1,3}"
        + "|[0-9]+[.,][0-9]+[A-Za-z]{0,3}"
        + "|[0-9]{1,2}[:.][0-9]{2}(?:am|pm|AM|PM)?)$", RegexOptions.CultureInvariant)]
    private static partial Regex OrdinaryMix();

    /// <summary>Olağan harf-rakam karışımı mı ("PS5", "2nd", "4K", "x2", "9.5kg", "3:00pm", "R2-D2").</summary>
    public static bool IsOrdinaryMix(string core) =>
        core.Split('-').Where(p => p.Any(char.IsAsciiDigit)).All(p => OrdinaryMix().IsMatch(p));

    /// <summary>
    /// Sözcüğün çekirdeğinin temizliği. Harf yoksa, simge ve rakam yoksa ya da simgesiz olağan karışımsa aynen.
    /// Değilse baştaki harf/<c>'</c>/<c>’</c>/<c>-</c> dizisi; bu dizide en az 3 harf yoksa sözcük tamamen çöptür (null).
    /// </summary>
    public static string? CleanCore(string core)
    {
        if (!core.Any(char.IsLetter)) return core;
        var hasSymbol = core.Any(IsSymbol);
        var hasDigit = core.Any(char.IsDigit);
        if (!hasSymbol && !hasDigit) return core;
        if (!hasSymbol && IsOrdinaryMix(core)) return core;
        var n = 0;
        while (n < core.Length && (char.IsLetter(core[n]) || core[n] is '\'' or '’' or '-')) n++;
        var head = core[..n];
        return head.Count(char.IsLetter) >= 3 ? head : null;
    }

    static readonly string[] IContractions = ["m", "ll", "ve", "d"];

    // l / | ile başlayan yanlış okunmuş "I": düzeltilmiş hali ve kısaltma mı.
    static (string Fixed, bool Contraction)? MisreadI(string core)
    {
        if (core is not ['l' or '|', ..]) return null;
        if (core.Length == 1) return ("I", false);
        if (core[1] is '\'' or '’' && IContractions.Contains(core[2..], StringComparer.Ordinal))
            return ("I" + core[1..], true);
        return null;
    }

    static bool IsStrayPunctuation(string part) =>
        part.Length > 0 && part.All(c => c is '?' or '!' or '.' or ',' or ';' or ':')
        && !(part.Length >= 2 && part.All(c => c == '.'));

    [GeneratedRegex(@"^[0-9]+(?:m|km|ft|yd)?[.?!:;]?$", RegexOptions.CultureInvariant)]
    private static partial Regex GaugeNumber();

    /// <summary>
    /// Satır içi OCR çöpü temizliği: yanlış okunmuş "I", başıboş noktalama, çöp sözcükler, satıra yapışmış gösterge
    /// sayısı. Parçalar tek boşlukla birleşir.
    /// </summary>
    public static string Clean(string line)
    {
        var parts = TextKey.Words(line);
        var output = new List<string>();
        for (var i = 0; i < parts.Length; i++)
        {
            var part = parts[i];
            var t = Split(part);
            if (MisreadI(t.Core) is { } fix)
            {
                var nextLower = i + 1 < parts.Length && parts[i + 1].FirstOrDefault(char.IsLetter) is var ch
                    && ch != default && char.IsLower(ch);
                if (fix.Contraction || nextLower || t.Trail.Contains('?') || t.Trail.Contains('!'))
                    output.Add(t.Lead + fix.Fixed + t.Trail);
                continue;
            }
            if (t.Core.Length == 0 && IsStrayPunctuation(part))
            {
                if (output.Count > 0 && output[^1].Length > 0 && !".?!…,;:".Contains(output[^1][^1]))
                    output[^1] += part;
                continue;
            }
            var cleaned = CleanCore(t.Core);
            if (cleaned is not null) output.Add(t.Lead + cleaned + t.Trail);
            else if (t.Trail.Length > 0 && output.Count > 0) output[^1] += t.Trail;
        }
        if (output.Count >= 3 && GaugeNumber().IsMatch(output[0]) && output[1].Length > 0 && char.IsUpper(output[1][0]))
            output.RemoveAt(0);
        return string.Join(" ", output);
    }

    /// <summary>Okumanın her satırını temizler; boş kalan satır okumadan kalkar.</summary>
    public static OcrReading Clean(OcrReading reading)
    {
        var changed = false;
        var lines = new List<OcrLine>(reading.Lines.Count);
        foreach (var l in reading.Lines)
        {
            var c = Clean(l.Text);
            if (!string.Equals(c, l.Text, StringComparison.Ordinal)) changed = true;
            lines.Add(l with { Text = c });
        }
        return changed ? new OcrReading(lines) : reading;
    }

    const string Vowels = "aeiouyäöüıàáâèéêìíîòóôùúû";
    static readonly HashSet<string> Interjections = new(StringComparer.Ordinal)
    {
        "hm", "m", "sh", "br", "gr", "pst", "pft", "tsk", "hrm", "z", "pht",
    };

    /// <summary>Olağan büyük/küçük harf düzeni ("WORD", "Word", "word", "McDonald", "iPhone").</summary>
    public static bool HasOrdinaryCase(string letters)
    {
        if (letters.Length <= 1) return true;
        if (letters.All(char.IsUpper)) return true;
        var rest = letters[1..];
        if (rest.All(char.IsLower)) return true;
        return rest.Count(char.IsUpper) == 1 && rest.Count(char.IsLower) >= 2;
    }

    /// <summary>Ünlüsüz mü (ünlem dışı; "Gtt", "Wrrk" evet; "Hmm", "Shh", "FBI" hayır).</summary>
    public static bool IsVowelless(string letters)
    {
        if (letters.Length < 3 || letters.All(char.IsUpper)) return false;
        var lower = letters.ToLowerInvariant();
        if (lower.Any(c => Vowels.Contains(c))) return false;
        var collapsed = new StringBuilder();
        foreach (var c in lower)
            if (collapsed.Length == 0 || collapsed[^1] != c) collapsed.Append(c);
        return !Interjections.Contains(collapsed.ToString());
    }

    static IEnumerable<(string Letters, bool Good)> LetterParts(string text)
    {
        foreach (var part in TextKey.Words(text))
        {
            var core = Split(part).Core;
            var letters = string.Concat(core.Where(char.IsLetter));
            if (letters.Length == 0) continue;
            var good = string.Equals(CleanCore(core), core, StringComparison.Ordinal)
                && HasOrdinaryCase(letters)
                && core.IndexOfAny(['[', ']', '(', ')']) < 0
                && !IsVowelless(letters);
            yield return (letters, good);
        }
    }

    /// <summary>
    /// Gürültü (OCR çöpü) puanı: düzgün parça harf sayısı kadar artı, değilse 2 × harf sayısı eksi. Aynı karenin
    /// iki okumasından iyisini seçmeye yarar (büyük olan iyi).
    /// </summary>
    public static int Score(string? text) =>
        LetterParts(text ?? "").Sum(p => p.Good ? p.Letters.Length : -2 * p.Letters.Length);

    /// <summary>Çöp gibi mi: kötü harfler × 6 &gt; bütün harfler.</summary>
    public static bool LooksLikeGarbage(string? text)
    {
        int good = 0, bad = 0;
        foreach (var p in LetterParts(text ?? ""))
            if (p.Good) good += p.Letters.Length;
            else bad += p.Letters.Length;
        return bad * 6 > good + bad;
    }

    const string TraceTrim = ".,!?;:'\"()[]-…“”’‘";
    const string AllowedHigh = "’‘“”—–…";

    /// <summary>
    /// OCR izi ("bozuk okuma" kuralı; paket bekletmesi için): ASCII dışı izinsiz karakter, sözcük içinde harfler
    /// arasında yabancı karakter, yan yana harf-rakam, tek harfli tuhaf sözcük ya da 14'ten uzun sözcük.
    /// </summary>
    public static bool IsMisread(string? text)
    {
        var t = text ?? "";
        if (t.Any(c => c > 127 && !AllowedHigh.Contains(c))) return true;
        foreach (var raw in TextKey.Words(t))
        {
            var w = raw.Trim(TraceTrim.ToCharArray());
            if (w.Length == 0) continue;
            for (var i = 1; i < w.Length - 1; i++)
                if (char.IsLetter(w[i - 1]) && char.IsLetter(w[i + 1])
                    && !(char.IsLetter(w[i]) || w[i] is '\'' or '’' or '-')) return true;
            for (var i = 1; i < w.Length; i++)
                if ((char.IsLetter(w[i - 1]) && char.IsDigit(w[i])) || (char.IsDigit(w[i - 1]) && char.IsLetter(w[i])))
                    return true;
            if (w.Length == 1 && char.IsLetter(w[0]) && w[0] is not ('a' or 'A' or 'I' or 'o' or 'O')) return true;
            if (w.Length > 14) return true;
        }
        return false;
    }

}
