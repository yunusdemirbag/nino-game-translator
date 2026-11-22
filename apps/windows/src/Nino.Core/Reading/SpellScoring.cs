// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Text.RegularExpressions;

namespace Nino.Core.Reading;

/// <summary>
/// Sözlük: bir sözcük yazım denetleyicisinin sözlüğünde mi. Windows'ta işletim sisteminin yazım denetleyicisi (en-US,
/// COM) doldurur; denetleyici yoksa ya da hata verirse her sözcük sözlükte sayılmalıdır. Önbellek ve kilit uygulamadadır.
/// </summary>
public interface ISpellDictionary
{
    /// <summary>Sözcük sözlükte mi.</summary>
    bool Contains(string word);
}

/// <summary>
/// Yazım denetimine dayanan "okuma bozuk mu" kararı ve okuma puanı (platformdan bağımsız mantık). Yalnız İngilizce
/// oyunlarda kullanılır (denetleyici yalnız İngilizce bilir).
/// </summary>
public sealed partial class SpellScoring(ISpellDictionary dictionary)
{
    static readonly HashSet<string> Slang = new((
        "gonna wanna gotta kinda sorta lemme gimme ya yo nah yeah yep nope ain't homie homies y'all dunno outta lotta " +
        "cuz 'cause em 'em huh uh um hmm mm ok okay whaddya c'mon ma'am bro dude fuckin motherfucker motherfuckers " +
        "dumbass").Split(' '), StringComparer.OrdinalIgnoreCase);

    [GeneratedRegex("[A-Za-z][A-Za-z'’]*", RegexOptions.CultureInvariant)]
    private static partial Regex LetterWord();

    /// <summary>Metindeki desen sözcükleri (baş/son kesmeleri atılmış).</summary>
    public static IEnumerable<string> PatternWords(string text) =>
        LetterWord().Matches(text).Select(m => m.Value.Trim('\'', '’')).Where(w => w.Length > 0);

    static bool IsSlang(string word) => Slang.Contains(word);

    /// <summary>
    /// Sözcük doğru mu (genel): 2 harften kısa, özel ad/bağırış biçimi ("Vinewood", "MICHAEL"), sokak ağzı,
    /// "-in" ile kısaltılmış sözcük ("somethin", "starin") ya da sözlükte.
    /// </summary>
    public bool IsWordOk(string word)
    {
        if (word.Length < 2) return true;
        if (char.IsUpper(word[0]) && (word[1..].All(c => !char.IsLetter(c) || char.IsLower(c)) || word.All(c => !char.IsLetter(c) || char.IsUpper(c))))
            return true;
        if (IsSlang(word)) return true;
        if (word.EndsWith("in", StringComparison.OrdinalIgnoreCase))
        {
            var g = word + "g";
            if (IsSlang(g) || dictionary.Contains(g)) return true;
        }
        return dictionary.Contains(word);
    }

    static int Letters(string w) => w.Count(char.IsLetter);

    bool LineStartOk(string word) => IsWordOk(word.ToLowerInvariant()) || dictionary.Contains(word);

    /// <summary>
    /// Okuma bozuk mu: bir sözcük bile doğru değilse. Satırın ilk sözcüğü (2+ harfliyse) küçük harfli haliyle de
    /// denenir: satır başındaki büyük harf ad belirtisi değildir ("Arfgfit man" bozuktur).
    /// </summary>
    public bool IsMisread(string? text)
    {
        foreach (var line in (text ?? "").Replace("\r\n", "\n").Split('\n'))
        {
            var first = true;
            foreach (var w in PatternWords(line))
            {
                var ok = first && Letters(w) >= 2 ? LineStartOk(w) : IsWordOk(w);
                first = false;
                if (!ok) return true;
            }
        }
        return false;
    }

    const string CoreTrim = ".,!?;:\"'“”‘’()[]…-—–";

    bool ReallyInDictionary(string word)
    {
        var lower = word.ToLowerInvariant();
        if (IsSlang(lower) || dictionary.Contains(word) || dictionary.Contains(lower)) return true;
        return lower.EndsWith("in", StringComparison.Ordinal)
            && (IsSlang(lower + "g") || dictionary.Contains(lower + "g"));
    }

    /// <summary>
    /// Okuma puanı: her parçanın puanı toplanır (temiz sözcük harf sayısı kadar; bozuk parça eksi; özel ad ya da
    /// "Dihnnr" gibi okuma 0). Eksik sözcüklü okuma tam okumanın gerisinde kalır.
    /// </summary>
    public int Score(string? text)
    {
        var total = 0;
        foreach (var line in (text ?? "").Replace("\r\n", "\n").Split('\n'))
        {
            var lineStart = true;
            foreach (var token in TextKey.Words(line))
            {
                total += TokenScore(token, lineStart);
                lineStart = false;
            }
        }
        return total;
    }

    int TokenScore(string token, bool lineStart)
    {
        var core = token.Trim(CoreTrim.ToCharArray());
        if (core.Length == 0) return 0;
        var letters = Letters(core);
        var words = PatternWords(core).ToArray();
        var clean = core.All(c => char.IsLetter(c) || c is '\'' or '’' or '-') && core.All(c => c < 128 || c == '’');
        if (clean)
        {
            for (var i = 0; i < words.Length; i++)
            {
                var w = words[i];
                var ok = lineStart && i == 0 && Letters(w) >= 2
                    ? dictionary.Contains(w.ToLowerInvariant()) || dictionary.Contains(w) || IsWordOk(w.ToLowerInvariant())
                    : IsWordOk(w);
                if (!ok)
                {
                    clean = false;
                    break;
                }
            }
        }
        if (letters == 0) return core.Any(char.IsDigit) ? 0 : -2 * core.Length;
        if (!clean) return -2 * Math.Max(core.Length, letters);
        if (words.Any(w => Letters(w) >= 2 && char.IsUpper(w[0]) && !ReallyInDictionary(w))) return 0;
        return letters;
    }
}
