// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Globalization;
using System.Security.Cryptography;
using System.Text;

namespace Nino.Core.Library;

/// <summary>
/// Paket ve havuz satır anahtarı (havuz/paket tarifi §1): metin sadeleştirilir ("canon"), UTF-8 SHA-256'sının ilk
/// 8 baytı 16 haneli küçük hex olur. Sunucu, öbür platformlar ve paket betiğiyle bayt bayt aynı olmalı.
/// </summary>
public static class LineKey
{
    /// <summary>Etiket içinin en çok kod noktası sayısı.</summary>
    public const int MaxTagInner = 40;

    /// <summary>Sadeleştirilmiş metin (boş olabilir). Hiçbir girdide hata vermez.</summary>
    public static string Canon(string? text)
    {
        if (string.IsNullOrEmpty(text)) return "";
        var stripped = text.Contains('<') ? StripTags(text, " ") : text;
        var nfkc = SafeNormalize(stripped, NormalizationForm.FormKC);
        var lowered = nfkc.Replace("İ", "i̇").ToLowerInvariant();
        var nfd = SafeNormalize(lowered, NormalizationForm.FormD);

        var sb = new StringBuilder(nfd.Length);
        var pendingSpace = false;
        foreach (var rune in nfd.EnumerateRunes())
        {
            switch (Rune.GetUnicodeCategory(rune))
            {
                case UnicodeCategory.NonSpacingMark:
                case UnicodeCategory.SpacingCombiningMark:
                case UnicodeCategory.EnclosingMark:
                    break;
                case UnicodeCategory.UppercaseLetter:
                case UnicodeCategory.LowercaseLetter:
                case UnicodeCategory.TitlecaseLetter:
                case UnicodeCategory.ModifierLetter:
                case UnicodeCategory.OtherLetter:
                case UnicodeCategory.DecimalDigitNumber:
                case UnicodeCategory.LetterNumber:
                case UnicodeCategory.OtherNumber:
                    if (pendingSpace && sb.Length > 0) sb.Append(' ');
                    pendingSpace = false;
                    sb.Append(rune.ToString());
                    break;
                default:
                    pendingSpace = true;
                    break;
            }
        }
        return sb.ToString();
    }

    /// <summary>Anahtar (16 küçük hex); metin harf/rakam içermiyorsa null.</summary>
    public static string? Compute(string? text)
    {
        var canon = Canon(text);
        return canon.Length == 0 ? null : HashCanon(canon);
    }

    /// <summary>Anahtarın sayı hâli; metin harf/rakam içermiyorsa null.</summary>
    public static ulong? ComputeValue(string? text)
    {
        var canon = Canon(text);
        if (canon.Length == 0) return null;
        Span<byte> digest = stackalloc byte[32];
        SHA256.HashData(Encoding.UTF8.GetBytes(canon), digest);
        return System.Buffers.Binary.BinaryPrimitives.ReadUInt64BigEndian(digest);
    }

    /// <summary>Sadeleştirilmiş metnin anahtarı.</summary>
    public static string HashCanon(string canon)
    {
        Span<byte> digest = stackalloc byte[32];
        SHA256.HashData(Encoding.UTF8.GetBytes(canon), digest);
        return Convert.ToHexStringLower(digest[..8]);
    }

    /// <summary>Tam 16 haneli geçerli hex ise sayı (büyük/küçük harf fark etmez).</summary>
    public static bool TryParse(string? hex, out ulong value)
    {
        value = 0;
        if (hex is null || hex.Length != 16) return false;
        foreach (var c in hex)
            if (!char.IsAsciiHexDigit(c)) return false;
        return ulong.TryParse(hex, NumberStyles.AllowHexSpecifier, CultureInfo.InvariantCulture, out value);
    }

    /// <summary>Sayıyı 16 haneli küçük hex yazar.</summary>
    public static string Format(ulong value) => value.ToString("x16", CultureInfo.InvariantCulture);

    /// <summary>
    /// <c>&lt;</c> + en çok 40 kod noktası (içinde <c>&lt; &gt;</c> yok) + <c>&gt;</c> biçimli etiketleri
    /// <paramref name="replacement"/> ile değiştirir.
    /// </summary>
    public static string StripTags(string text, string replacement)
    {
        if (!text.Contains('<')) return text;
        var runes = new List<Rune>(text.Length);
        foreach (var r in SafeRunes(text)) runes.Add(r);
        var sb = new StringBuilder(text.Length);
        var i = 0;
        while (i < runes.Count)
        {
            if (runes[i].Value == '<')
            {
                var end = -1;
                for (var j = i + 1; j < runes.Count && j <= i + MaxTagInner + 1; j++)
                {
                    var v = runes[j].Value;
                    if (v == '<') break;
                    if (v == '>')
                    {
                        end = j;
                        break;
                    }
                }
                if (end > 0)
                {
                    sb.Append(replacement);
                    i = end + 1;
                    continue;
                }
            }
            sb.Append(runes[i].ToString());
            i++;
        }
        return sb.ToString();
    }

    /// <summary>Normalleştirir; eşsiz vekil varsa önce onları U+FFFD yapar.</summary>
    internal static string SafeNormalize(string text, NormalizationForm form)
    {
        try
        {
            return text.Normalize(form);
        }
        catch (ArgumentException)
        {
            var sb = new StringBuilder(text.Length);
            foreach (var r in SafeRunes(text)) sb.Append(r.ToString());
            return sb.ToString().Normalize(form);
        }
    }

    /// <summary>Kod noktaları; eşsiz vekiller U+FFFD olur.</summary>
    internal static IEnumerable<Rune> SafeRunes(string text)
    {
        var i = 0;
        while (i < text.Length)
        {
            Rune.DecodeFromUtf16(text.AsSpan(i), out var rune, out var used);
            yield return rune;
            i += Math.Max(1, used);
        }
    }
}
