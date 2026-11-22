// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Text;
using System.Text.RegularExpressions;

namespace Nino.Core.Translation;

/// <summary>
/// Tümü büyük harfli cümleyi olağan yazıma çevirir (çeviri tarifi §3.3): modeller büyük harfli sözcükleri ad sanıp
/// çevirmiyordu. Bilinen adlar (konuşmacı etiketlerinden öğrenilenler, sözlüğün büyük kalacak sözcükleri) baş harfi
/// büyük kalır.
/// </summary>
public static class CapsNormalizer
{
    /// <summary>Cümleyi düzenler; düzenlenecek değilse aynen döner.</summary>
    public static string Normalize(string sentence, IReadOnlySet<string>? knownNames = null)
    {
        if (sentence.Any(char.IsLower)) return sentence;
        if (sentence.Count(char.IsLetter) < 2) return sentence;
        if (!sentence.Trim().Contains(' ')) return sentence;

        var sb = new StringBuilder(sentence.Length);
        var sentenceStart = true;
        var i = 0;
        while (i < sentence.Length)
        {
            var c = sentence[i];
            if (!IsWordChar(c))
            {
                sb.Append(c);
                if (c is '.' or '!' or '?' or '…') sentenceStart = true;
                i++;
                continue;
            }
            var j = i;
            while (j < sentence.Length && IsWordChar(sentence[j])) j++;
            var word = sentence[i..j].ToLowerInvariant();
            if (sentenceStart || word == "i" || (knownNames?.Contains(word) ?? false))
                word = char.ToUpperInvariant(word[0]) + word[1..];
            sb.Append(word);
            sentenceStart = false;
            i = j;
        }
        return sb.ToString();
    }

    static bool IsWordChar(char c) => char.IsLetter(c) || c is '\'' or '’';
}

/// <summary>
/// Oyun ve asker deyimlerini çeviriden önce sade İngilizceye çevirir (çeviri tarifi §4.2; her hedef dilde).
/// </summary>
public static class GameIdioms
{
    static readonly (Regex Pattern, string Plain)[] Rules =
    [
        (Rule(@"friendlies"), "allies"),
        (Rule(@"I(?:['’]ve)? got your six"), "I've got your back"),
        (Rule(@"check your six"), "watch behind you"),
        (Rule(@"heads up"), "watch out"),
        (Rule(@"took you long enough"), "you're late"),
        (Rule(@"we['’]ve got company"), "enemies are coming"),
        (Rule(@"lock and load"), "get ready"),
        (Rule(@"sitting ducks"), "easy targets"),
        (Rule(@"moving in"), "going in"),
    ];

    static Regex Rule(string pattern) =>
        new(@"\b" + pattern + @"\b", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);

    /// <summary>Deyimleri değiştirir.</summary>
    public static string Apply(string text)
    {
        foreach (var (pattern, plain) in Rules)
            text = pattern.Replace(text, m => MatchCase(m.Value, plain));
        return text;
    }

    /// <summary>Eşleşmenin ilk harfi büyükse karşılığın ilk harfi büyütülür (kültürden bağımsız).</summary>
    internal static string MatchCase(string matched, string replacement) =>
        matched.Length > 0 && char.IsUpper(matched[0]) && replacement.Length > 0
            ? char.ToUpperInvariant(replacement[0]) + replacement[1..]
            : replacement;
}
