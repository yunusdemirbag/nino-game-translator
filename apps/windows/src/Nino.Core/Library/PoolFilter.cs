// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;

namespace Nino.Core.Library;

/// <summary>
/// Ortak havuza hangi satırın gideceği (havuz/paket tarifi §6.1): temizlik, gürültü, yarım okuma, Türkçe ve PS5 sistem
/// yazısı denetimi. Sunucudaki süzgeçle aynı ortak kurallar.
/// </summary>
public static partial class PoolFilter
{
    /// <summary>En çok kod noktası.</summary>
    public const int MaxLength = 500;

    static readonly HashSet<string> HalfEndings = new(StringComparer.Ordinal)
    {
        "the", "a", "an", "to", "of", "and", "or", "but", "with", "for", "from", "my", "your", "his", "her", "their",
        "our", "at", "in", "on", "by", "into", "than", "that", "if", "as", "is", "are", "was", "were",
    };

    static readonly string[] TurkishUiWords = (
        "icin|lutfen|bekleyin|oyunu|oyun|"
        + "oyunlar|kapat|ekran|ekranda|ekrani|"
        + "sistemini|yeniden|baslat|ayarlar|ayarlari|"
        + "kupalar|kupa|oturum|acti|kapatti|"
        + "secenekleri|sifirlama|tut|kesfet|ilgili|"
        + "takip|edin|ilerlemenizi|cikanlar|goruntusu|"
        + "kaydedildi|bildirimler|arkadaslar|medya|galerisi|"
        + "indiriliyor|guncelleme|kitaplik|denetleyici").Split('|');

    static readonly string[] SystemPhrases = (
        "signed in|signed out|earned a trophy|trophy earned|trophy unlocked|"
        + "screenshot saved|video clip saved|media gallery|is now online|joined the party|"
        + "left the party|remote play|controller battery|controller is disconnected|controller disconnected|"
        + "press the ps button|playstation network|download complete|installation complete|update available|"
        + "turn off your console|cloud save|do not quit|photo mode|story mode|"
        + "press any button|oturum acti|oturum kapatti|ekran ve video|oyunu kapat|"
        + "ana ekranda tut|yeniden baslat|sifirlama secenekleri|lutfen bekleyin|ilerlemenizi takip").Split('|');

    static readonly Lazy<string[]> FoldedUiWords = new(() => TurkishUiWords.Select(w => string.Join("", FoldWords(w))).ToArray());

    static readonly Lazy<string[]> FoldedPhrases = new(() =>
        SystemPhrases.Select(p => " " + string.Join(' ', FoldWords(p)) + " ").ToArray());

    /// <summary>
    /// Temizlik: denetim ve görünmez karakterler boşluk olur, boşluklar teklenir, baş/son kırpılır.
    /// </summary>
    public static string Clean(string? text)
    {
        if (string.IsNullOrEmpty(text)) return "";
        var sb = new StringBuilder(text.Length);
        foreach (var r in LineKey.SafeRunes(text))
        {
            var v = r.Value;
            var invisible = v is <= 0x1F or >= 0x7F and <= 0x9F or >= 0x200B and <= 0x200F or 0x2028 or 0x2029 or 0xFEFF;
            sb.Append(invisible ? " " : r.ToString());
        }
        return string.Join(' ', sb.ToString().Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries));
    }

    /// <summary>Temizlenmiş satır havuza gidebilir mi.</summary>
    public static bool Accepts(string cleaned)
    {
        if (cleaned.Length == 0) return false;
        var runes = LineKey.SafeRunes(cleaned).ToList();
        if (runes.Count > MaxLength || !runes.Any(Rune.IsLetter)) return false;
        if (IsNoise(cleaned)) return false;
        if (IsHalfRead(cleaned)) return false;
        if (LooksTurkish(cleaned)) return false;
        if (IsSystemText(cleaned)) return false;
        return true;
    }

    /// <summary>Temizleyip denetler; geçerse temiz metni, geçmezse null döner.</summary>
    public static string? Prepare(string? text)
    {
        var cleaned = Clean(text);
        return Accepts(cleaned) ? cleaned : null;
    }

    /// <summary>Gürültü: OCR çöpü temizliği metni değiştiriyorsa ya da görünür karakterlerin yarısından azı harfse.</summary>
    public static bool IsNoise(string text)
    {
        if (LineKey.Canon(OcrJunk.Clean(text)) != LineKey.Canon(text)) return true;
        var letters = 0;
        var visible = 0;
        foreach (var r in LineKey.SafeRunes(text))
        {
            if (Rune.IsWhiteSpace(r)) continue;
            visible++;
            if (Rune.IsLetter(r)) letters++;
        }
        return letters * 2 < visible;
    }

    static bool IsHalfRead(string text)
    {
        var t = text.Trim();
        var words = t.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries).Where(w => w.Any(char.IsLetter)).ToList();
        var stripped = t.TrimEnd('"', '\'', '”', '’', '»', ')', ']');
        var hasEnd = stripped.Length > 0 && stripped[^1] is '.' or '!' or '?' or '…';
        if (!hasEnd && (words.Count < 3 || new StringInfo(t).LengthInTextElements < 15)) return true;
        if (t.Length > 0 && char.IsLower(t[0])) return true;
        if (hasEnd) return false;
        if (words.Count > 0)
        {
            var last = new string(words[^1].Where(char.IsLetter).ToArray()).ToLowerInvariant();
            if (HalfEndings.Contains(last)) return true;
        }
        var letters = t.Where(char.IsLetter).ToList();
        if (letters.Count > 0 && !letters.Any(char.IsLower) && words.Count <= 6) return true;
        return false;
    }

    static bool LooksTurkish(string text)
    {
        if (text.IndexOfAny(['ğ', 'Ğ', 'ş', 'Ş', 'ı', 'İ']) >= 0) return true;
        if (text.Count(c => c is 'ü' or 'Ü' or 'ö' or 'Ö' or 'ç' or 'Ç') >= 2) return true;
        var near = 0;
        foreach (var word in FoldWords(text))
            if (FoldedUiWords.Value.Any(w => Near(word, w)) && ++near >= 2) return true;
        return false;
    }

    static bool IsSystemText(string text)
    {
        var joined = " " + string.Join(' ', FoldWords(text)) + " ";
        return FoldedPhrases.Value.Any(p => joined.Contains(p, StringComparison.Ordinal));
    }

    static bool Near(string a, string b)
    {
        if (a == b) return true;
        if (a.Length < 6 || b.Length < 6 ||
            Math.Abs(a.Length - b.Length) > 1) return false;
        return OneEdit(a, b);
    }

    static bool OneEdit(string a, string b)
    {
        if (a.Length == b.Length) return a.Zip(b).Count(p => p.First != p.Second) == 1;
        if (a.Length > b.Length) (a, b) = (b, a);
        var i = 0;
        while (i < a.Length && a[i] == b[i]) i++;
        return a.AsSpan(i).SequenceEqual(b.AsSpan(i + 1));
    }

    /// <summary>Süzgecin katlaması: küçük harf, aksansız, <c>q→c</c>, <c>l/1→i</c>; harf/rakam dışı ayraç.</summary>
    internal static List<string> FoldWords(string text)
    {
        var lowered = text.ToLowerInvariant().Replace('ı', 'i');
        var nfd = LineKey.SafeNormalize(lowered, NormalizationForm.FormD);
        var words = new List<string>();
        var sb = new StringBuilder();
        foreach (var r in nfd.EnumerateRunes())
        {
            if (Rune.GetUnicodeCategory(r) == UnicodeCategory.NonSpacingMark) continue;
            if (!Rune.IsLetterOrDigit(r))
            {
                if (sb.Length > 0) words.Add(sb.ToString());
                sb.Clear();
                continue;
            }
            var v = r.Value switch
            {
                'q' => 'c',
                'l' or '1' => 'i',
                var x => x,
            };
            sb.Append(new Rune(v).ToString());
        }
        if (sb.Length > 0) words.Add(sb.ToString());
        return words;
    }
}

/// <summary>
/// Satır içi OCR çöpü temizliği (okuma hattı tarifi §7.3). Okuma hattının kendi kopyası henüz olmadığı için havuz
/// süzgecinin gürültü denetimi bu iç kopyayı kullanır.
/// </summary>
internal static partial class OcrJunk
{
    const string Symbols = "$@#%^*_=|\\~<>{}¢£¥§©®°±µ¶¤";

    [GeneratedRegex(@"^(?:[A-Za-z]{1,4}\d{1,4}|\d+(?:st|nd|rd|th|s|k|K|m|km|kg|cm|mm|p|x|fps|hp|HP|XP|xp|v|V|D|d)|[xX]\d{1,3}|\d+[.,]\d+[A-Za-z]{0,3}|\d{1,2}[:.]\d{2}(?:am|pm|AM|PM)?)$")]
    private static partial Regex OrdinaryMix();

    [GeneratedRegex(@"^\d+(?:m|km|ft|yd)?[.?!:;]?$")]
    private static partial Regex LeadingCounter();

    static bool IsSymbol(char c) => Symbols.Contains(c);

    static bool IsEdge(char c)
    {
        if (IsSymbol(c)) return false;
        if (c is '"' or '\'' or '“' or '”' or '‘' or '’' or '«' or '»' or '(' or ')' or '[' or ']') return true;
        return char.IsPunctuation(c) || char.IsSymbol(c);
    }

    static (string Head, string Core, string Tail) Parts(string token)
    {
        var start = 0;
        while (start < token.Length && IsEdge(token[start])) start++;
        var end = token.Length;
        while (end > start &&
            IsEdge(token[end - 1])) end--;
        return (token[..start],
            token[start..end], token[end..]);
    }

    static string? CleanCore(string core)
    {
        if (!core.Any(char.IsLetter)) return core;
        var hasSymbol = core.Any(IsSymbol);
        if (!hasSymbol && !core.Any(char.IsDigit)) return core;
        if (!hasSymbol && core.Split('-').Where(p => p.Any(char.IsDigit)).All(p => OrdinaryMix().IsMatch(p))) return core;
        var i = 0;
        while (i < core.Length && (char.IsLetter(core[i]) || core[i] is '\'' or '’' or '-')) i++;
        var lead = core[..i];
        return lead.Count(char.IsLetter) >= 3 ? lead : null;
    }

    static string? MisreadI(string core)
    {
        if (core.Length == 0 || core[0]
            is not ('l' or '|')) return null;
        if (core.Length == 1) return "I";
        if (core[1] is '\'' or '’' && core[2..] is "m" or "ll" or "ve" or "d") return "I" + core[1..];
        return null;
    }

    /// <summary>Satırı temizler.</summary>
    public static string Clean(string line)
    {
        var tokens = line.Split((char[]?)null,
            StringSplitOptions.RemoveEmptyEntries);
        var output = new List<string>();
        for (var k = 0; k < tokens.Length; k++)
        {
            var token = tokens[k];
            var (head, core, tail) = Parts(token);
            if (MisreadI(core) is { } fixedI)
            {
                var next = k + 1 < tokens.Length ? tokens[k + 1].FirstOrDefault(char.IsLetter) : '\0';
                if (fixedI.Length > 1 || char.IsLower(next) || tail.Contains('?') || tail.Contains('!'))
                    output.Add(head + fixedI + tail);
                continue;
            }
            if (core.Length == 0 && token.All(c => c is '?' or '!' or '.' or ',' or ';' or ':')
                && !(token.Length >= 2 && token.All(c => c == '.')))
            {
                if (output.Count > 0 && output[^1].Length > 0 && output[^1][^1] is not ('.' or '?' or '!' or '…' or ',' or ';' or ':'))
                    output[^1] += token;
                continue;
            }
            var cleaned = CleanCore(core);
            if (cleaned is not null) output.Add(head + cleaned + tail);
            else if (tail.Length > 0 && output.Count > 0) output[^1] += tail;
        }
        if (output.Count >= 3 && LeadingCounter().IsMatch(output[0]) && output[1].Length > 0 && char.IsUpper(output[1][0]))
            output.RemoveAt(0);
        return string.Join(' ', output);
    }
}

/// <summary>Ortak havuz sunucusunun adresi (havuz/paket tarifi §6).</summary>
public static class PoolEndpoint
{
    /// <summary>Canlı sunucu.</summary>
    public const string Live = "https://nino-pool.y-demirbag2506.workers.dev";

    /// <summary>Ortam değişkeninin adı.</summary>
    public const string EnvironmentVariable = "NINO_POOL_URL";

    /// <summary>Adres seçimi: ortam değişkeni, <c>pool\endpoint.txt</c>, canlı. Geçersiz değer atlanır.</summary>
    public static Uri Resolve(string? environment, string? endpointFile)
    {
        foreach (var candidate in new[] { environment, endpointFile, Live })
            if (Parse(candidate) is { } uri) return uri;
        return new Uri(Live);
    }

    /// <summary>Veri klasöründen okur.</summary>
    public static Uri Resolve(string dataFolder)
    {
        string? file = null;
        try
        {
            var path = Path.Combine(dataFolder, "pool", "endpoint.txt");
            if (File.Exists(path)) file = File.ReadAllText(path);
        }
        catch (Exception e) when (e is IOException
            or UnauthorizedAccessException) { }
        return Resolve(Environment.GetEnvironmentVariable(EnvironmentVariable), file);
    }

    /// <summary>Mutlak http/https adresi mi.</summary>
    public static Uri? Parse(string? value)
    {
        var text = value?.Trim();
        if (string.IsNullOrEmpty(text)) return null;
        return Uri.TryCreate(text, UriKind.Absolute, out var uri)
               && (uri.Scheme == Uri.UriSchemeHttp || uri.Scheme == Uri.UriSchemeHttps) && uri.Host.Length > 0
            ? uri
            : null;
    }

    /// <summary>Uç noktanın tam adresi (<c>v1/…</c> göreli yol).</summary>
    public static Uri Combine(Uri baseUri, string relative)
    {
        var text = baseUri.ToString();
        if (!text.EndsWith('/')) text += "/";
        return new Uri(text + relative);
    }

    /// <summary>Havuz isteklerinin User-Agent'ı.</summary>
    public static string UserAgent(string appVersion) => $"nino-pool/1 (windows; {appVersion})";
}
