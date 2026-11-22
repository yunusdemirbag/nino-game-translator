// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;

namespace Nino.Core.Translation;

/// <summary>Türkçe ekin terime göre yeniden kurulması (çeviri tarifi §6.3).</summary>
public static class TurkishSuffix
{
    static readonly CultureInfo Turkish = CultureInfo.GetCultureInfo("tr-TR");

    const string AllVowels = "aeıioöuü";
    const string VoicelessConsonants = "fstkçşhp";
    const int LongestSuffix = 12;

    // Ünlü özellikleri: kalın (a ı o u), yuvarlak (o ö u ü), dar (ı i u ü).
    static bool IsVowel(char c) => AllVowels.Contains(c);

    static bool IsBack(char v) => v is 'a' or 'ı' or 'o' or 'u';

    static bool IsRounded(char v) => v is 'o' or 'ö' or 'u' or 'ü';

    static bool IsHigh(char v) => v is 'ı' or 'i' or 'u' or 'ü';

    // İki yönlü uyum: a/e.
    static char LowFor(char seed) => IsBack(seed) ? 'a' : 'e';

    // Dört yönlü uyum: ı/i/u/ü (kalınlık × yuvarlaklık).
    static char HighFor(char seed) => "iüıu"[(IsBack(seed) ? 2 : 0) + (IsRounded(seed) ? 1 : 0)];

    /// <summary>Terimin sonundaki sözcüğün eki etkileyen özellikleri.</summary>
    readonly record struct Ending(string Word, char Final, char? FinalVowel, bool Compound)
    {
        public bool OpenSyllable => FinalVowel is null || IsVowel(Final);

        public bool Voiceless => !OpenSyllable && VoicelessConsonants.Contains(Final);

        public static Ending Of(string term)
        {
            var word = term[(term.LastIndexOf(' ') + 1)..].ToLower(Turkish);
            var final = word.Length == 0 ? ' ' : word[^1];
            var at = word.LastIndexOfAny(AllVowels.ToCharArray());
            char? vowel = at < 0 ? null : word[at];
            var compound = word.Length >= 3 && IsHigh(final) && term.Contains(' ');
            return new Ending(word, final, vowel, compound);
        }
    }

    /// <summary>Terimin Türkçesine eki ekler. Özel adda kesme kullanılır, cins adda ek bitişir.</summary>
    public static string Attach(string term, string suffix, char apostrophe = '\'')
    {
        if (suffix.Length == 0 || term.Length == 0) return term;

        var lowered = suffix.ToLower(Turkish);
        var plausible = lowered.Length <= LongestSuffix && lowered.All(char.IsLetter);
        if (!plausible) return string.Concat(term, apostrophe.ToString(), suffix);

        var ending = Ending.Of(term);
        var body = DropBufferLetter(lowered).ToCharArray();
        var glue = PickBuffer(body, ending);
        Harmonize(body, ending.FinalVowel ?? 'e');
        var tail = glue + new string(body);

        if (char.IsUpper(term[0])) return string.Concat(term, apostrophe.ToString(), tail);
        var softens = glue.Length == 0 && IsVowel(body[0]);
        return (softens ? Soften(term, ending.Word) : term) + tail;
    }

    // Çevirinin ekin başına koyduğu kaynaştırma harfini atar: "yla/yle/yı…" → "la/le/ı…", "nın/nin…" → "ın/in…".
    static string DropBufferLetter(string s)
    {
        if (s.Length < 2) return s;
        if (s[0] == 'y') return IsVowel(s[1]) || s[1] == 'l' ? s[1..] : s;
        var nasal = s.Length >= 3 && s[0] == 'n' && IsHigh(s[1]) && s[2] == 'n';
        return nasal ? s[1..] : s;
    }

    // Kaynaştırma harfini seçer; d/t ile başlayan ekin ilk harfini de terimin sonuna göre ayarlar.
    static string PickBuffer(char[] body, in Ending ending)
    {
        var first = body[0];

        if (first is 'd' or 't')
        {
            body[0] = ending.Voiceless && !ending.Compound ? 't' : 'd';
            return ending.Compound ? "n" : "";
        }

        if (IsVowel(first))
        {
            if (ending.Compound) return "n";
            if (!ending.OpenSyllable) return "";
            return IsGenitive(body) ? "n" : "y";
        }

        return IsWithCase(body) && (ending.OpenSyllable || ending.Compound) ? "y" : "";
    }

    // "ın/in/un/ün" (ardından ünlü gelmeyen).
    static bool IsGenitive(char[] s) =>
        s.Length >= 2 && IsHigh(s[0]) && s[1] == 'n' && (s.Length == 2 || !IsVowel(s[2]));

    // "la/le" ("lar/ler" çoğul değil).
    static bool IsWithCase(char[] s) =>
        s.Length >= 2 && s[0] == 'l' && (s[1] == 'a' || s[1] == 'e') && (s.Length == 2 || s[2] != 'r');

    // Ekteki ünlüleri bir önceki ünlüye uydurur; sondaki "ki" olduğu gibi kalır.
    static void Harmonize(char[] letters, char seed)
    {
        var last = letters.Length - 1;
        for (var n = 0; n < letters.Length; n++)
        {
            var ch = letters[n];
            var frozenKi = n == last && n > 0 && ch == 'i' && letters[n - 1] == 'k';
            if (frozenKi) return;
            if (!IsVowel(ch)) continue;

            if (ch == 'a' || ch == 'e') ch = LowFor(seed);
            else if (IsHigh(ch)) ch = HighFor(seed);
            letters[n] = ch;
            seed = ch;
        }
    }

    // Ünsüz yumuşaması (cins adda, ünlüyle başlayan ek doğrudan bitişince).
    static readonly Dictionary<char, char> Softer = new() { ['k'] = 'ğ', ['p'] = 'b', ['ç'] = 'c' };

    static string Soften(string term, string lastWord)
    {
        if (term.Length < 2) return term;
        var head = term[..^1];
        if (lastWord.EndsWith("nk", StringComparison.Ordinal)) return head + "g";
        var syllables = lastWord.Count(IsVowel);
        if (syllables >= 2 && Softer.TryGetValue(term[^1], out var soft)) return head + soft;
        return term;
    }

    /// <summary>İlk harfi Türkçe kültürüyle büyütür.</summary>
    public static string Capitalize(string text)
    {
        if (text.Length == 0) return text;
        return string.Concat(char.ToUpper(text[0], Turkish).ToString(), text.AsSpan(1));
    }
}

/// <summary>Uydurma adla korunmuş bir metin.</summary>
/// <param name="Text">Korunmuş metin.</param>
/// <param name="Names">Bu metinde kullanılan adlar (ilk geçiş sırasıyla, tekrarsız).</param>
public sealed record ShieldedText(string Text, IReadOnlyList<string> Names);

/// <summary>
/// Sözlük terimlerini çeviriden önce uydurma adlarla değiştirir ve çeviriden sonra Türkçe ekleriyle geri koyar
/// (çeviri tarifi §6.1–§6.2).
/// </summary>
public sealed class TermShield
{
    /// <summary>Uydurma adlar (sırayla).</summary>
    public static readonly IReadOnlyList<string> PlaceholderNames =
        ["Zarmon", "Velkor", "Dorvan", "Kelmar", "Tolvar", "Brandur", "Halvor", "Feldor"];

    // Cümle başı sayılırken geriye doğru atlanan açılış işaretleri.
    const string Openers = "\"“'‘(-–—¡¿";

    readonly Glossary _glossary;
    readonly Queue<string> _unused;
    readonly Dictionary<string, string> _byEnglish = new(StringComparer.Ordinal);
    readonly Dictionary<string, GlossaryTerm> _byPlaceholder = new(StringComparer.Ordinal);
    readonly Dictionary<string, Regex> _patterns = new(StringComparer.Ordinal);

    /// <param name="glossary">Sözlük.</param>
    /// <param name="sources">Kaynak metinler: bunlarda geçen adlar kullanılmaz.</param>
    public TermShield(Glossary glossary, params string?[] sources)
    {
        _glossary = glossary;
        _unused = new Queue<string>();
        foreach (var candidate in PlaceholderNames)
        {
            var clashes = sources.Any(src => src?.Contains(candidate, StringComparison.OrdinalIgnoreCase) == true);
            if (!clashes) _unused.Enqueue(candidate);
        }
    }

    /// <summary>Bu koruyucunun bütün metinlerde verdiği adlar.</summary>
    public IReadOnlyCollection<string> AllNames => _byPlaceholder.Keys;

    /// <summary>Metindeki terimleri adlarla değiştirir.</summary>
    public ShieldedText Protect(string text)
    {
        var hits = _glossary.FindTerms(text);
        if (hits.Count == 0) return new ShieldedText(text, []);

        var used = new List<string>();
        var result = new StringBuilder(text.Length);
        var copied = 0;
        foreach (var hit in hits)
        {
            if (!TryPlaceholderFor(hit.Term, out var placeholder)) continue;
            result.Append(text.AsSpan(copied, hit.Index - copied));
            result.Append(placeholder);
            copied = hit.Index + hit.Length;
            if (!used.Contains(placeholder)) used.Add(placeholder);
        }
        result.Append(text.AsSpan(copied));
        return new ShieldedText(result.ToString(), used);
    }

    // Terimin adı; ilk kez görülüyorsa sıradaki boş ad verilir (kalmadıysa terim korunmaz).
    bool TryPlaceholderFor(GlossaryTerm term, out string placeholder)
    {
        var english = term.English.ToLowerInvariant();
        if (_byEnglish.TryGetValue(english, out placeholder!)) return true;
        if (!_unused.TryDequeue(out placeholder!)) return false;
        _byEnglish.Add(english, placeholder);
        _byPlaceholder[placeholder] = term;
        return true;
    }

    // Ad, isteğe bağlı kesme ve ek (s grubu); önünde ve ardında harf/rakam olmamalı.
    Regex PatternFor(string placeholder)
    {
        if (_patterns.TryGetValue(placeholder, out var cached)) return cached;
        const string Guard = @"[\p{L}\p{N}]";
        var source = "(?<!" + Guard + ")" + Regex.Escape(placeholder)
            + @"(?:(?: ?['’`´](?<s>\p{L}+))|(?<s>\p{L}+))?" + "(?!" + Guard + ")";
        var built = new Regex(source, RegexOptions.CultureInvariant | RegexOptions.IgnoreCase);
        _patterns[placeholder] = built;
        return built;
    }

    /// <summary>
    /// Adları terimlerin Türkçesiyle (ekleri kurularak) geri koyar. Beklenen bir ad çıktıda yoksa ya da başka metnin
    /// adı çıktıda kaldıysa null (geçersiz).
    /// </summary>
    public string? Restore(string output, IReadOnlyList<string> expected, IReadOnlyCollection<string>? all = null,
        char apostrophe = '\'')
    {
        var others = all ?? [];
        if (expected.Count == 0 && others.Count == 0) return output;
        if (others.Any(o => !expected.Contains(o) && PatternFor(o).IsMatch(output))) return null;

        var edits = new List<(int Start, int Length, string Replacement)>();
        foreach (var placeholder in expected)
        {
            if (!_byPlaceholder.TryGetValue(placeholder, out var term)) return null;
            var found = PatternFor(placeholder).Matches(output);
            if (found.Count == 0) return null;
            foreach (Match hit in found) edits.Add((hit.Index, hit.Length, Rebuild(output, hit, term, apostrophe)));
        }
        return Apply(output, edits);
    }

    static string Rebuild(string output, Match hit, GlossaryTerm term, char apostrophe)
    {
        var word = TurkishSuffix.Attach(term.Turkish, hit.Groups["s"].Value, apostrophe);
        var needsCapital = word.Length > 0 && char.IsLower(word[0]) && StartsSentence(output, hit.Index);
        return needsCapital ? TurkishSuffix.Capitalize(word) : word;
    }

    // Soldan sağa uygular; öncekiyle çakışan düzenleme atlanır.
    static string Apply(string text, List<(int Start, int Length, string Replacement)> edits)
    {
        var sb = new StringBuilder(text.Length);
        var cursor = 0;
        foreach (var edit in edits.OrderBy(e => e.Start))
        {
            if (edit.Start < cursor) continue;
            sb.Append(text.AsSpan(cursor, edit.Start - cursor)).Append(edit.Replacement);
            cursor = edit.Start + edit.Length;
        }
        return sb.Append(text.AsSpan(cursor)).ToString();
    }

    static bool StartsSentence(string text, int index)
    {
        var p = index;
        while (p > 0 && (char.IsWhiteSpace(text[p - 1]) || Openers.Contains(text[p - 1]))) p--;
        if (p == 0) return true;
        return text[p - 1] is '.' or '!' or '?' or '…';
    }
}

/// <summary>Ücretsiz çevirinin Türkçe düzeltmesi (çeviri tarifi §6.4) ve hitap kuralı (§6.5).</summary>
public static partial class TurkishPolish
{
    static readonly CultureInfo Turkish = CultureInfo.GetCultureInfo("tr-TR");

    // Satır içi boşluk: boşluk, sekme, bölünmez boşluk.
    [GeneratedRegex(@"[  \t]+(?=[,.!?;:…])")]
    private static partial Regex GapBeforeMark();

    [GeneratedRegex(@"[\t  ]{2,}")]
    private static partial Regex WideGap();

    [GeneratedRegex(@"[^\p{L}]+")]
    private static partial Regex WordBreaks();

    const string Terminals = ".!?…";
    const string Closers = "\"'”’)]»";

    /// <summary>Tek cümlenin çevirisini kaynağa göre düzeltir.</summary>
    public static string Polish(string source, string translation)
    {
        if (!translation.Any(char.IsLetter)) return translation;

        var text = NormalizeQuotes(translation, Uses(source, '“', '”'), Uses(source, '’', '‘'));
        text = GapBeforeMark().Replace(text, "");
        text = WideGap().Replace(text, " ").Trim('\t', ' ', ' ');
        return MatchEnding(source, text);
    }

    static bool Uses(string source, char a, char b) => source.Contains(a) || source.Contains(b);

    // Kaynakta kıvrık tırnak varsa düz tırnaklar kıvrılır (açılış/kapanış), yoksa kıvrıklar düzleşir.
    static string NormalizeQuotes(string text, bool curlyDouble, bool curlySingle)
    {
        var chars = text.ToCharArray();
        for (var n = 0; n < chars.Length; n++)
        {
            var ch = chars[n];
            var opens = n == 0 || IsOpeningContext(chars[n - 1]);
            chars[n] = ch switch
            {
                '"' when curlyDouble => opens ? '“' : '”',
                '“' or '”' or '„' or '‟' when !curlyDouble => '"',
                '\'' when curlySingle => opens ? '‘' : '’',
                '’' or '‘' when !curlySingle => '\'',
                _ => ch,
            };
        }
        return new string(chars);
    }

    static bool IsOpeningContext(char before) => char.IsWhiteSpace(before) || before is '(' or '[' or '-' or '–' or '—';

    // Metnin sonu: gövde + bitiş işaretleri + kapanış işaretleri (tırnak, ayraç).
    static (string Body, string Mark, string Closing) Tail(string text)
    {
        var trimmed = text.TrimEnd();
        var closeAt = trimmed.Length;
        while (closeAt > 0 && Closers.Contains(trimmed[closeAt - 1])) closeAt--;
        var markAt = closeAt;
        while (markAt > 0 && Terminals.Contains(trimmed[markAt - 1])) markAt--;
        return (trimmed[..markAt], trimmed[markAt..closeAt], trimmed[closeAt..]);
    }

    static bool IsEmphatic(string mark)
    {
        if (mark.Length == 0) return false;
        if (mark == "...") return true;
        return mark.IndexOfAny(['!', '?', '…']) >= 0;
    }

    // Kaynak ünlem/soru/üç noktayla bitiyorsa çeviri de aynı işaretle biter (yalnız güvenli durumlarda).
    static string MatchEnding(string source, string translation)
    {
        var want = Tail(source.Trim());
        if (!IsEmphatic(want.Mark)) return translation;

        var have = Tail(translation);
        var sameClosing = want.Closing.Length > 0 == have.Closing.Length > 0;
        if (!sameClosing || have.Mark == want.Mark) return translation;

        var replaceable = have.Mark.Length == 0 || have.Mark == "." || IsEmphatic(have.Mark);
        if (!replaceable || !have.Body.Any(char.IsLetter)) return translation;
        return have.Body + want.Mark + have.Closing;
    }

    static readonly HashSet<string> SenWords =
        new(["senle", "seninle", "senden", "sende", "senin", "sana", "seni", "sen"], StringComparer.Ordinal);

    static readonly HashSet<string> SizWords =
        new(["sizler", "sizinle", "sizden", "sizde", "sizin", "size", "sizi", "siz"], StringComparer.Ordinal);

    // "siz"li emir → "sen"li emir. Kalıplar birbirinin içinde eşleşmez; sıra sonucu değiştirmez.
    static readonly (string Polite, string Plain)[] Commands =
    [
        ("acele edin", "acele et"), ("ateş edin", "ateş et"), ("dikkat edin", "dikkat et"),
        ("takip edin", "takip et"), ("yardım edin", "yardım et"),
        ("hazır olun", "hazır ol"), ("sakin olun", "sakin ol"), ("sessiz olun", "sessiz ol"),
        ("atlayın", "atla"), ("bakın", "bak"), ("bekleyin", "bekle"), ("bırakın", "bırak"),
        ("çekilin", "çekil"), ("dinleyin", "dinle"), ("dövüşün", "dövüş"), ("durdurun", "durdur"),
        ("durun", "dur"), ("eğilin", "eğil"), ("gelin", "gel"), ("getirin", "getir"),
        ("gidin", "git"), ("gösterin", "göster"), ("kaçın", "kaç"), ("kalkın", "kalk"),
        ("koşun", "koş"), ("odaklanın", "odaklan"), ("saklanın", "saklan"), ("savaşın", "savaş"),
        ("söyleyin", "söyle"), ("tutun", "tut"), ("uzaklaşın", "uzaklaş"), ("yaklaşın", "yaklaş"),
    ];

    // Emir, sözcük başında ve ardından yalnız boşluk + noktalama ya da metin sonu gelirse.
    static readonly Regex[] CommandPatterns = Array.ConvertAll(Commands, c =>
        new Regex(@"(?<!\p{L})" + Regex.Escape(c.Polite) + @"(?=\s*(?:[!.,?…]|$))", RegexOptions.CultureInvariant));

    static bool Mentions(string sentence, HashSet<string> words)
    {
        foreach (var word in WordBreaks().Split(sentence.ToLower(Turkish)))
            if (words.Contains(word)) return true;
        return false;
    }

    /// <summary>
    /// Hitap: cümlelerden birinde "sen" sözcüğü varsa, "siz" sözcüğü geçmeyen her cümlede bilinen "siz"li emirler
    /// "sen"li olur.
    /// </summary>
    public static IReadOnlyList<string> UnifyAddress(IReadOnlyList<string> sentences)
    {
        var informal = sentences.Any(s => s.Length > 0 && Mentions(s, SenWords));
        if (!informal) return sentences;

        var unified = new List<string>(sentences.Count);
        foreach (var sentence in sentences)
        {
            var keep = sentence.Length == 0 || Mentions(sentence, SizWords);
            unified.Add(keep ? sentence : ToInformal(sentence));
        }
        return unified.ToArray();
    }

    static string ToInformal(string sentence)
    {
        var current = sentence;
        for (var c = 0; c < Commands.Length; c++)
        {
            var lower = current.ToLower(Turkish);
            // Küçültme uzunluğu değiştirdiyse konumlar tutmaz; olduğu gibi bırak.
            if (lower.Length != current.Length) return current;
            var hits = CommandPatterns[c].Matches(lower);
            if (hits.Count > 0) current = Swap(current, hits, Commands[c].Plain);
        }
        return current;
    }

    static string Swap(string text, MatchCollection hits, string plain)
    {
        var sb = new StringBuilder(text.Length);
        var from = 0;
        foreach (Match hit in hits)
        {
            sb.Append(text.AsSpan(from, hit.Index - from));
            sb.Append(char.IsUpper(text[hit.Index]) ? TurkishSuffix.Capitalize(plain) : plain);
            from = hit.Index + hit.Length;
        }
        return sb.Append(text.AsSpan(from)).ToString();
    }
}
