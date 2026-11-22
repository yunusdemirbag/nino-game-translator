// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;

namespace Nino.Core.Library;

/// <summary>Oyun adlarını karşılaştırma anahtarları.</summary>
public static partial class GameNames
{
    // ii → 2 … xvi → 16 (dizideki yeri + 2).
    static readonly string[] RomanNumerals =
        ["ii", "iii", "iv", "v", "vi", "vii", "viii", "ix", "x", "xi", "xii", "xiii", "xiv", "xv", "xvi"];

    static readonly Dictionary<string, string> RomanToArabic = RomanNumerals
        .Select((numeral, index) => (numeral, value: (index + 2).ToString(CultureInfo.InvariantCulture)))
        .ToDictionary(p => p.numeral, p => p.value, StringComparer.Ordinal);

    // Sırayla uygulanır ("ea sports fc" önce, "ea sports" sonra).
    static readonly (Regex Pattern, string Short)[] Abbreviations =
    [
        (WholePhrase("grand theft auto"), "gta"),
        (WholePhrase("call of duty"), "cod"),
        (WholePhrase("red dead redemption"), "rdr"),
        (WholePhrase("ea sports fc"), "fc"),
        (WholePhrase("ea sports"), ""),
    ];

    const string TrademarkSigns = "™®©";
    const int MaxKeyLength = 80;
    const int MaxSlugLength = 64;

    enum RunKind { None, Letters, Digits }

    static Regex WholePhrase(string phrase) => new(@"\b" + phrase + @"\b", RegexOptions.CultureInvariant);

    [GeneratedRegex(" +")]
    private static partial Regex Spaces();

    /// <summary>
    /// Oyun adı anahtarı (havuz/paket tarifi §2.5; sunucudakiyle aynı): <c>Grand Theft Auto VI</c> → <c>gta 6</c>.
    /// </summary>
    public static string Key(string? name)
    {
        if (string.IsNullOrEmpty(name)) return "";

        var plain = new string(name.Select(c => TrademarkSigns.Contains(c) ? ' ' : c).ToArray());
        var folded = LineKey.SafeNormalize(plain, NormalizationForm.FormKD).ToLowerInvariant();

        var parts = Tokenize(folded);
        for (var i = 0; i < parts.Count; i++)
            if (RomanToArabic.TryGetValue(parts[i], out var arabic)) parts[i] = arabic;
        if (parts.Count >= 2 && parts[0] == "the") parts.RemoveAt(0);

        var key = string.Join(' ', parts);
        foreach (var rule in Abbreviations) key = rule.Pattern.Replace(key, rule.Short);
        key = Spaces().Replace(key, " ").Trim();
        return (key.Length <= MaxKeyLength ? key : key[..MaxKeyLength]).Trim();
    }

    // Harf ve rakam öbeklerine böler: işaretler ve kesme imleri yutulur, "&" ayrı "and" olur, harf↔rakam geçişi böler.
    static List<string> Tokenize(string text)
    {
        var found = new List<string>();
        var run = new StringBuilder();
        var kind = RunKind.None;

        void Close()
        {
            if (run.Length > 0) found.Add(run.ToString());
            run.Clear();
            kind = RunKind.None;
        }

        foreach (var original in text.EnumerateRunes())
        {
            if (IsCombiningMark(original) || original.Value is '\'' or '’' or '`') continue;
            if (original.Value == '&')
            {
                Close();
                found.Add("and");
                continue;
            }

            var rune = original.Value == 'ı' ? new Rune('i') : original;
            if (!Rune.IsLetterOrDigit(rune))
            {
                Close();
                continue;
            }

            var next = Rune.IsDigit(rune) ? RunKind.Digits : RunKind.Letters;
            if (kind != RunKind.None && kind != next) Close();
            run.Append(rune.ToString());
            kind = next;
        }

        Close();
        return found;
    }

    static bool IsCombiningMark(Rune rune) => Rune.GetUnicodeCategory(rune) switch
    {
        UnicodeCategory.NonSpacingMark => true,
        UnicodeCategory.SpacingCombiningMark => true,
        UnicodeCategory.EnclosingMark => true,
        _ => false,
    };

    /// <summary>
    /// Sunucunun beklediği oyun kimliği (havuz/paket tarifi §7.1): küçük harf, ASCII harf/rakam ve <c>. _ -</c> dışı
    /// <c>-</c>, ardışık <c>-</c> tek, baş/son <c>- . _</c> atılır, en çok 64; boşsa null.
    /// </summary>
    public static string? Slug(string? name)
    {
        if (name is null) return null;

        var output = new StringBuilder(name.Length);
        var dashPending = false;
        foreach (var source in name.ToLowerInvariant())
        {
            var allowed = char.IsAsciiLetterLower(source) || char.IsAsciiDigit(source) || source is '.' or '_';
            if (allowed)
            {
                output.Append(source);
                dashPending = false;
            }
            else if (!dashPending)
            {
                // izin verilmeyen her şey (ve '-') tek bir tireye iner
                output.Append('-');
                dashPending = true;
            }
        }

        var slug = output.ToString().Trim('-', '.', '_');
        if (slug.Length == 0) return null;
        return slug.Length > MaxSlugLength ? slug[..MaxSlugLength] : slug;
    }
}
