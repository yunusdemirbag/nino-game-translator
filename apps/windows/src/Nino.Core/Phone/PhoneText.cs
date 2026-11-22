// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Globalization;
using System.Text;
using Nino.Core.Reading;

namespace Nino.Core.Phone;

/// <summary>
/// Telefon ve harita kartının ortak metin kuralları (kültürden bağımsız): benzerlik, cümle/ad sınamaları, çeviri
/// sonucunun temizlenmesi.
/// </summary>
public static class PhoneText
{
    /// <summary>Telefon mesajlarının benzerlik eşiği.</summary>
    public const double SimilarRatio = 0.75;

    /// <summary>Sadeleştirme (<see cref="TextKey.Of"/>).</summary>
    public static string Key(string? text) => TextKey.Of(text);

    /// <summary>Boşluklardan bölünmüş, boşları atılmış sözcükler.</summary>
    public static string[] Words(string? text) => TextKey.Words(text);

    /// <summary>Yalnız boşluk karakterini kırpar.</summary>
    public static string TrimSpaces(string? text) => (text ?? "").Trim(' ');

    /// <summary>Metinde harf var mı.</summary>
    public static bool HasLetter(string? text) => (text ?? "").Any(char.IsLetter);

    /// <summary>Harf sayısı.</summary>
    public static int LetterCount(string? text) => (text ?? "").Count(char.IsLetter);

    /// <summary>İlk karakter büyük harf mi.</summary>
    public static bool StartsUpper(string? text) => !string.IsNullOrEmpty(text) && char.IsUpper(text[0]);

    /// <summary>İlk karakter küçük harf mi.</summary>
    public static bool StartsLower(string? text) => !string.IsNullOrEmpty(text) && char.IsLower(text[0]);

    /// <summary>Metin (kırpılmış) verilen karakterlerden biriyle bitiyor mu.</summary>
    public static bool EndsWithAny(string? text, string chars)
    {
        var t = TrimSpaces(text);
        return t.Length > 0 && chars.Contains(t[^1]);
    }

    /// <summary>Metin <c>...</c> ya da <c>…</c> ile bitiyor mu.</summary>
    public static bool EndsWithEllipsis(string? text)
    {
        var t = TrimSpaces(text);
        return t.EndsWith("...", StringComparison.Ordinal) || t.EndsWith('…');
    }

    /// <summary>
    /// İki sadeleştirilmiş metin benzer mi: aynı; ya da biri ötekinin başı ya da sonu; ya da oran ≥ 0,75. Boş metin
    /// hiçbir metne benzemez.
    /// </summary>
    public static bool SimilarKeys(string a, string b)
    {
        if (a.Length == 0 || b.Length == 0) return false;
        if (a == b) return true;
        if (a.StartsWith(b, StringComparison.Ordinal) || b.StartsWith(a, StringComparison.Ordinal)) return true;
        if (a.EndsWith(b, StringComparison.Ordinal) || b.EndsWith(a, StringComparison.Ordinal)) return true;
        return TextKey.Ratio(a, b) >= SimilarRatio;
    }

    /// <summary>Metin (ham) sadeleştirilmiş kümedeki bir öğeye benziyor mu.</summary>
    public static bool SimilarToAny(string? text, IEnumerable<string> keys)
    {
        var k = Key(text);
        return keys.Any(s => SimilarKeys(k, s));
    }

    /// <summary>
    /// "Aynı mesajlar": okunanlar (ham) sadeleştirilir, boşlar atılır; okunan ya da gösterilen boşsa,
    /// <c>okunan × 2 &lt; gösterilen</c> ya da <c>okunan &gt; gösterilen + 1</c> ise hayır; değilse her okunan
    /// gösterilenlerden birine benzer mi.
    /// </summary>
    public static bool SameMessages(IEnumerable<string> read, IReadOnlyCollection<string> shown)
    {
        var keys = read.Select(Key).Where(k => k.Length > 0).ToArray();
        if (keys.Length == 0 || shown.Count == 0) return false;
        if (keys.Length * 2 < shown.Count || keys.Length > shown.Count + 1) return false;
        return keys.All(k => shown.Any(s => SimilarKeys(k, s)));
    }

    /// <summary>
    /// Çevrilmeye değer mi: çevirinin sadeleştirilmişi boş değil, kaynağınkinden farklı, ve (çeviri kaynağı içeriyor
    /// ve kaynak tek sözcük) değil.
    /// </summary>
    public static bool WorthShowing(string? source, string? translation)
    {
        var a = Key(source);
        var b = Key(translation);
        if (b.Length == 0 || a == b) return false;
        return !(b.Contains(a, StringComparison.Ordinal) && Words(a).Length == 1);
    }

    /// <summary>HTML varlıklarını sırayla çözer (yalnız metinde <c>&amp;</c> varsa).</summary>
    public static string DecodeEntities(string text)
    {
        if (!text.Contains('&')) return text;
        return text.Replace("&amp;", "&").Replace("&#39;", "'").Replace("&quot;", "\"").Replace("&lt;", "<")
            .Replace("&gt;", ">").Replace("&apos;", "'");
    }

    /// <summary>
    /// Simge temizliği: varlıklar çözülür; "diğer simge", "matematik simgesi" ve "özel kullanım" türündeki karakterler
    /// atılır; beyaz boşluklar teke iner, baş/son atılır.
    /// </summary>
    public static string StripSymbols(string? text)
    {
        var t = DecodeEntities(text ?? "");
        var sb = new StringBuilder(t.Length);
        foreach (var rune in t.EnumerateRunes())
        {
            var cat = Rune.GetUnicodeCategory(rune);
            if (cat is UnicodeCategory.OtherSymbol or UnicodeCategory.MathSymbol or UnicodeCategory.PrivateUse) continue;
            sb.Append(rune.ToString());
        }
        return string.Join(" ", Words(sb.ToString()));
    }

    /// <summary>Harf içeren ve bir öncekiyle (büyük/küçük harf gözetmeden) aynı olan sözcükleri atar.</summary>
    public static string RemoveRepeats(string? text)
    {
        var words = Words(text);
        var kept = new List<string>(words.Length);
        string? previous = null;
        foreach (var w in words)
        {
            if (previous is not null && HasLetter(w)
                && string.Equals(w.ToLowerInvariant(), previous.ToLowerInvariant(), StringComparison.Ordinal))
            {
                previous = w;
                continue;
            }
            kept.Add(w);
            previous = w;
        }
        return string.Join(" ", kept);
    }

    /// <summary>Telefonda çeviri sonucunun temizliği: simgeler (varlıklar dahil), kırpma, tekrarlar.</summary>
    public static string CleanTranslation(string? text) => RemoveRepeats(StripSymbols(text).Trim());

    /// <summary>
    /// Cümle mi (harf içeren sözcükler sayılır): ≥ 2 sözcük ve <c>. ! ?</c> ile bitiyor; ya da <c>!</c>/<c>?</c>
    /// içeriyor ve ≥ 2 sözcük; ya da ≥ 3 sözcük ve ilkinden sonraki sözcüklerden biri küçük harfle başlıyor.
    /// </summary>
    public static bool IsSentence(string? text)
    {
        var t = TrimSpaces(text);
        var words = Words(t).Where(HasLetter).ToArray();
        if (words.Length >= 2 && t.Length > 0 && t[^1] is '.' or '!' or '?') return true;
        if (words.Length >= 2 && (t.Contains('!') || t.Contains('?'))) return true;
        return words.Length >= 3 && words.Skip(1).Any(StartsLower);
    }

    static bool HasAny(string text, string chars) => text.Any(chars.Contains);

    /// <summary>
    /// Kişi adı: uzunluk 2–30; 1–4 sözcük; her sözcük büyük harfle ya da <c>&amp;</c> ile başlar; her sözcükte ilk
    /// harften sonra en çok 1 büyük harf; küçük harf var; <c>. , ! ? : ; … "</c> yok.
    /// </summary>
    public static bool IsPersonName(string? text)
    {
        var t = TrimSpaces(text);
        if (t.Length is < 2 or > 30) return false;
        var words = Words(t);
        if (words.Length is < 1 or > 4) return false;
        if (HasAny(t, ".,!?:;…\"")) return false;
        if (!t.Any(char.IsLower)) return false;
        foreach (var w in words)
        {
            if (!(char.IsUpper(w[0]) || w[0] == '&')) return false;
            if (w.Skip(1).Count(char.IsUpper) > 1) return false;
        }
        return true;
    }

    /// <summary>
    /// Ad gibi (sohbet başlığı): kişi adı ya da (uzunluk ≥ 2, ≤ 5 sözcük, yalnız harf ve <c>, . ' ’ &amp; -</c> ve
    /// boşluk, en az bir harf).
    /// </summary>
    public static bool IsTitleLike(string? text)
    {
        var t = TrimSpaces(text);
        if (IsPersonName(t)) return true;
        if (t.Length < 2 || Words(t).Length > 5) return false;
        return t.All(c => char.IsLetter(c) || c == ' ' || ",.'’&-".Contains(c)) && HasLetter(t);
    }

    /// <summary>Sözcükleri büyük harfle başlayan, n sözcüğe kadar, verilen işaretleri içermeyen kısa ad.</summary>
    static bool IsCapitalizedShort(string? text, int maxWords, string forbidden)
    {
        var t = TrimSpaces(text);
        var words = Words(t);
        if (words.Length < 1 || words.Length > maxWords) return false;
        return words.All(StartsUpper) && !HasAny(t, forbidden);
    }

    /// <summary>Sohbet listesindeki ad: 1–3 sözcük, hepsi büyük harfle başlar, <c>. , ! ? : …</c> yok.</summary>
    public static bool IsListName(string? text) => IsCapitalizedShort(text, 3, ".,!?:…");

    /// <summary>Gönderen adı (grup sohbeti): 1–2 sözcük, hepsi büyük harfle başlar, <c>. , ! ? …</c> yok.</summary>
    public static bool IsSenderName(string? text) => IsCapitalizedShort(text, 2, ".,!?…");

    /// <summary>Bir metnin <c>Baş Harfleri Büyük</c> hâli (küçük harfe çevrilir, sözcük başları büyür; kültürden bağımsız).</summary>
    public static string TitleCase(string text)
    {
        var chars = text.ToLowerInvariant().ToCharArray();
        for (var i = 0; i < chars.Length; i++)
            if (i == 0 || char.IsWhiteSpace(chars[i - 1])) chars[i] = char.ToUpperInvariant(chars[i]);
        return new string(chars);
    }

    /// <summary>Türkçe kurallarla büyük harf (<c>i</c> → <c>İ</c>, <c>ı</c> → <c>I</c>); kültür ayarından bağımsız.</summary>
    public static string TurkishUpper(string text) =>
        text.Replace('i', 'İ').Replace('ı', 'I').ToUpperInvariant();

    /// <summary>Kısaltma (günlük için): en çok <paramref name="max"/> karakter.</summary>
    public static string Short(string? text, int max = 40)
    {
        var t = (text ?? "").Replace('\n', ' ');
        return t.Length <= max ? t : t[..(max - 1)] + "…";
    }
}
