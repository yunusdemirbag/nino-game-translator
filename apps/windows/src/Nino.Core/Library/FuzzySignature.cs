// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Globalization;
using System.Numerics;
using System.Text;

namespace Nino.Core.Library;

/// <summary>
/// OCR'a dayanıklı arama için katlama, üçlü Bloom imzası, benzerlik ve "bozuk okuma" izi (havuz/paket tarifi §3.2,
/// §3.4). Paket betiğiyle birebir aynı olmalı.
/// </summary>
public static class FuzzySignature
{
    /// <summary>İmza için en kısa katlanmış uzunluk.</summary>
    public const int MinLength = 16;

    /// <summary>Uzunluğun üst sınırı (tek bayt).</summary>
    public const int MaxLength = 255;

    /// <summary>Ayırma payı.</summary>
    public const double Margin = 5;

    const ulong FnvOffset = 0xcbf29ce484222325;
    const ulong FnvPrime = 0x100000001b3;

    /// <summary>canon'un katlanmış kod noktaları (boşluklar atılmış, OCR'ın karıştırdığı harfler birleştirilmiş).</summary>
    public static int[] FoldCanon(string canon)
    {
        var result = new List<int>(canon.Length);
        foreach (var rune in canon.EnumerateRunes())
        {
            var v = rune.Value;
            if (v == ' ') continue;
            result.Add(v switch
            {
                'l' or '1' or 'ı' or 'j' => 'i',
                '0' => 'o',
                '5' => 's',
                'æ' => 'a',
                'ø' or 'œ' => 'o',
                'ß' => 's',
                _ => v,
            });
        }
        return result.ToArray();
    }

    /// <summary>Ham metnin katlanmış hâli.</summary>
    public static int[] Fold(string text) => FoldCanon(LineKey.Canon(text));

    /// <summary>Katlanmış diziyi metin olarak yazar (test ve günlük için).</summary>
    public static string ToText(int[] folded)
    {
        var sb = new StringBuilder(folded.Length);
        foreach (var v in folded) sb.Append(new Rune(v).ToString());
        return sb.ToString();
    }

    /// <summary>Uzunluk: en çok 255.</summary>
    public static int LengthOf(int[] folded) => Math.Min(folded.Length, MaxLength);

    /// <summary>Bit sayısı (64, 128 ya da 256).</summary>
    public static int BitsFor(int length)
    {
        var bits = 64;
        while (bits < 256 && length * 3 > bits) bits *= 2;
        return bits;
    }

    /// <summary>Ardışık üçlülerin FNV-1a 64 özetleri (tekrarsız).</summary>
    public static ulong[] Trigrams(int[] folded)
    {
        var set = new HashSet<ulong>();
        Span<byte> buffer = stackalloc byte[12];
        for (var i = 0; i + 2 < folded.Length; i++)
        {
            var n = 0;
            for (var k = 0; k < 3; k++) n += new Rune(folded[i + k]).EncodeToUtf8(buffer[n..]);
            var hash = FnvOffset;
            for (var b = 0; b < n; b++)
            {
                hash ^= buffer[b];
                hash *= FnvPrime;
            }
            set.Add(hash);
        }
        return set.ToArray();
    }

    /// <summary>Özetlerden Bloom sözcükleri.</summary>
    public static ulong[] Bloom(IEnumerable<ulong> trigrams, int bits)
    {
        var words = new ulong[bits / 64];
        foreach (var hash in trigrams)
        {
            var b = hash & (ulong)(bits - 1);
            words[b >> 6] |= 1UL << (int)(b & 63);
        }
        return words;
    }

    /// <summary>Bloom'un bayt dizisi (sözcükler küçük sonlu).</summary>
    public static byte[] ToBytes(ulong[] words)
    {
        var bytes = new byte[words.Length * 8];
        for (var i = 0; i < words.Length; i++)
            System.Buffers.Binary.BinaryPrimitives.WriteUInt64LittleEndian(bytes.AsSpan(i * 8), words[i]);
        return bytes;
    }

    /// <summary>Metnin imzası; katlanmış hâli 16'dan kısaysa null.</summary>
    public static (int Length, int Bits, ulong[] Words)? Signature(string text)
    {
        var folded = Fold(text);
        if (folded.Length < MinLength) return null;
        var length = LengthOf(folded);
        var bits = BitsFor(length);
        return (length, bits, Bloom(Trigrams(folded), bits));
    }

    /// <summary>1 bit sayısı.</summary>
    public static int PopCount(ReadOnlySpan<ulong> words)
    {
        var n = 0;
        foreach (var w in words) n += BitOperations.PopCount(w);
        return n;
    }

    /// <summary>Ortak 1 bit sayısı.</summary>
    public static int CommonBits(ReadOnlySpan<ulong> a, ReadOnlySpan<ulong> b)
    {
        var n = 0;
        for (var i = 0; i < a.Length; i++) n += BitOperations.PopCount(a[i] & b[i]);
        return n;
    }

    /// <summary>İki yönlü kapsama: (sorgunun kapsanması, adayın kapsanması).</summary>
    public static (double Query, double Candidate) Coverage(int common, int queryBits, int candidateBits, int bits)
    {
        if (queryBits == 0 || candidateBits == 0) return (0, 0);
        var ds = (double)queryBits / bits;
        var da = (double)candidateBits / bits;
        if (ds >= 1 || da >= 1) return (0, 0);
        var query = 100 * (((double)common / queryBits - da) / (1 - da));
        var candidate = 100 * (((double)common / candidateBits - ds) / (1 - ds));
        return (query, candidate);
    }

    /// <summary>Benzerlik: iki kapsamanın küçüğü.</summary>
    public static double Similarity(ReadOnlySpan<ulong> query, ReadOnlySpan<ulong> candidate)
    {
        var bits = query.Length * 64;
        var (q, c) = Coverage(CommonBits(query, candidate), PopCount(query), PopCount(candidate), bits);
        return Math.Min(q, c);
    }

    /// <summary>Kabul eşiği (uzunluğa ve bozukluğa göre).</summary>
    public static double Threshold(int length, bool damaged)
    {
        if (!damaged) return length < 24 ? 90 : 80;
        if (length < 24) return 70;
        return length < 40 ? 60 : 55;
    }

    static bool IsTypographic(int v) => v is '’' or '‘' or '“' or '”' or '—' or '–' or '…';

    static bool IsTrimMark(int v) =>
        v is '.' or ',' or '!' or '?' or ';' or ':' or '\'' or '"' or '(' or ')' or '[' or ']' or '-' or '…' or '“'
            or '”' or '’' or '‘';

    static bool IsDigit(Rune r) => r.IsBmp && CharUnicodeInfo.GetDecimalDigitValue((char)r.Value) >= 0;

    /// <summary>OCR izi: satırın ham metninde bozuk okuma işaretleri var mı.</summary>
    public static bool LooksDamaged(string text)
    {
        foreach (var r in LineKey.SafeRunes(text))
            if (r.Value > 127 && !IsTypographic(r.Value)) return true;

        foreach (var raw in text.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries))
        {
            var runes = LineKey.SafeRunes(raw).ToList();
            var start = 0;
            var end = runes.Count;
            while (start < end && IsTrimMark(runes[start].Value)) start++;
            while (end > start && IsTrimMark(runes[end - 1].Value)) end--;
            var word = runes.GetRange(start, end - start);
            if (word.Count == 0) continue;
            if (word.Count > 14) return true;
            if (word.Count == 1)
            {
                var only = word[0];
                if (Rune.IsLetter(only) && only.Value is not ('a' or 'A' or 'I' or 'o' or 'O')) return true;
            }
            for (var i = 0; i < word.Count; i++)
            {
                var r = word[i];
                if (i > 0 && i + 1 < word.Count && !Rune.IsLetter(r) && r.Value is not ('\'' or '’' or '-')
                    && Rune.IsLetter(word[i - 1]) && Rune.IsLetter(word[i + 1]))
                    return true;
                if (i + 1 < word.Count)
                {
                    var next = word[i + 1];
                    if ((Rune.IsLetter(r) && IsDigit(next)) || (IsDigit(r) && Rune.IsLetter(next))) return true;
                }
            }
        }
        return false;
    }
}

/// <summary>Fazlalıklı okumada yan cümle bölme ve denetimi (havuz/paket tarifi §3.6).</summary>
public static class FuzzyClauses
{
    /// <summary>Kısa parça sınırı (katlanmış harf).</summary>
    public const int MinClause = 6;

    static bool IsMark(int v) => v is '.' or '!' or '?' or '…' or ',' or ';' or ':';

    static bool IsClosing(int v) => v is '"' or '\'' or '”' or '’' or ')' or ']';

    /// <summary>Okumayı yan cümlelere böler ve kısa parçaları birleştirir.</summary>
    public static List<string> Split(string text)
    {
        var runes = LineKey.SafeRunes(text).ToArray();
        var parts = new List<string>();
        var start = 0;
        var i = 0;
        while (i < runes.Length)
        {
            if (!IsMark(runes[i].Value))
            {
                i++;
                continue;
            }
            var soft = false;
            var dots = 0;
            while (i < runes.Length && IsMark(runes[i].Value))
            {
                var v = runes[i].Value;
                if (v is ',' or ';' or ':' or '…') soft = true;
                if (v == '.') dots++;
                i++;
            }
            while (i < runes.Length && IsClosing(runes[i].Value)) i++;
            var groupEnd = i;
            while (i < runes.Length && Rune.IsWhiteSpace(runes[i])) i++;
            var hadSpace = i > groupEnd;
            if (hadSpace && i < runes.Length && (soft || dots > 1 || Rune.IsUpper(runes[i])))
            {
                parts.Add(Join(runes, start, groupEnd));
                start = i;
            }
        }
        if (start < runes.Length) parts.Add(Join(runes, start, runes.Length));

        var trimmed = parts.Select(p => p.Trim()).Where(p => p.Length > 0).ToList();
        var merged = new List<string>();
        string? carry = null;
        for (var k = 0; k < trimmed.Count; k++)
        {
            var part = carry is null ? trimmed[k] : carry + " " + trimmed[k];
            carry = null;
            var isLast = k == trimmed.Count - 1;
            if (FuzzySignature.Fold(part).Length < MinClause)
            {
                if (!isLast)
                {
                    carry = part;
                    continue;
                }
                if (merged.Count > 0)
                {
                    merged[^1] = merged[^1] + " " + part;
                    continue;
                }
            }
            merged.Add(part);
        }
        return merged;
    }

    static string Join(Rune[] runes, int from, int to)
    {
        var sb = new StringBuilder();
        for (var i = from; i < to; i++) sb.Append(runes[i].ToString());
        return sb.ToString();
    }

    /// <summary>Köşe yazısına benziyor mu: <c>•</c> var ya da 1–4 sözcük ve her biri büyük harfle başlayıp harf/rakam.</summary>
    public static bool LooksLikeCorner(string part)
    {
        if (part.Contains('•')) return true;
        var words = part.Split(' ', StringSplitOptions.RemoveEmptyEntries);
        return words.Length is >= 1 and <= 4 && words.All(IsCapitalWord);
    }

    static bool IsCapitalWord(string word) =>
        word.Length > 0 && char.IsUpper(word[0]) && word.All(char.IsLetterOrDigit);

    /// <summary>
    /// Denetlenecek yan cümleler: her biri için seçeneklerin üçlü özetleri. Parça sayısı 2'den azsa null (denetim
    /// yok, geçer).
    /// </summary>
    public static List<List<ulong[]>>? CheckList(string reading)
    {
        var parts = Split(reading);
        if (parts.Count < 2) return null;
        var result = new List<List<ulong[]>>();
        for (var p = 0; p < parts.Count; p++)
        {
            var part = parts[p];
            if (LooksLikeCorner(part)) continue;
            var options = new
                List<string> { part };
            var words = part.Split(' ', StringSplitOptions.RemoveEmptyEntries);
            if (p == 0)
                for (var k = 1; k <= 3 && k < words.Length; k++)
                {
                    if (!words.Take(k).All(IsCapitalWord)) break;
                    options.Add(string.Join(' ', words.Skip(k)));
                }
            if (p == parts.Count - 1)
                for (var k = 1; k <= 3 && k < words.Length; k++)
                {
                    if (!words.Skip(words.Length - k).All(IsCapitalWord)) break;
                    options.Add(string.Join(' ', words.Take(words.Length - k)));
                }
            var folded = options.Select(FuzzySignature.Fold).ToList();
            if (folded.Any(f => f.Length < MinClause)) continue;
            result.Add(folded.Select(FuzzySignature.Trigrams).ToList());
        }
        return result;
    }

    /// <summary>Her denetlenen parçanın en az bir seçeneği adayda kapsanıyor mu (≥ 30).</summary>
    public static bool Passes(List<List<ulong[]>> checks, ReadOnlySpan<ulong> candidate)
    {
        var bits = candidate.Length * 64;
        var a = FuzzySignature.PopCount(candidate);
        var d = (double)a / bits;
        if (d >= 1) return false;
        foreach (var options in checks)
        {
            var any = false;
            foreach (var trigrams in options)
            {
                var bloom = FuzzySignature.Bloom(trigrams, bits);
                var c = FuzzySignature.PopCount(bloom);
                if (c == 0)
                {
                    any = true;
                    break;
                }
                var common = FuzzySignature.CommonBits(bloom, candidate);
                if (100 * (((double)common / c - d) / (1 - d)) >= 30)
                {
                    any = true;
                    break;
                }
            }
            if (!any) return false;
        }
        return true;
    }
}
