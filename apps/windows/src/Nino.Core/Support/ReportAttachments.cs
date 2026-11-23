// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Text;

namespace Nino.Core.Support;

// Hata bildirimi'in ekleri: resim (sığdırılmış JPEG) ya da düz yazı dosyası (.txt, .log). Sunucu `images` için en çok 3
// resim kabul eder ve bilinmeyen alanları atar; bu yüzden yazı dosyaları `log` alanının sonuna "— ek: ad —" başlığıyla
// eklenir (ek yoksa gövde aynı kalır).

/// <summary>Bildirime eklenen bir dosya: resim (JPEG baytları) ya da yazı.</summary>
/// <param name="Id">Ekin kimliği (çıkarmak için).</param>
/// <param name="Name">Dosya adı (ekranda ve yazı ekinin başlığında).</param>
/// <param name="Jpeg">Resimse JPEG baytları.</param>
/// <param name="Text">Yazı dosyasıysa içeriği.</param>
public sealed record ReportAttachment(Guid Id, string Name, byte[]? Jpeg, string? Text)
{
    /// <summary>Resim eki.</summary>
    public static ReportAttachment Image(string name, byte[] jpeg) => new(Guid.NewGuid(), name, jpeg, null);

    /// <summary>Yazı eki.</summary>
    public static ReportAttachment TextFile(string name, string text) => new(Guid.NewGuid(), name, null, text);

    /// <summary>Resim mi.</summary>
    public bool IsImage => Jpeg is not null;

    /// <summary>Gönderilecek bayt (resimde JPEG, yazıda UTF-8).</summary>
    public int ByteCount => Jpeg?.Length ?? Encoding.UTF8.GetByteCount(Text ?? "");
}

/// <summary>Bir ekin eklenememe nedeni.</summary>
public enum ReportAttachmentFailure
{
    /// <summary>Açılamadı ya da desteklenmeyen tür.</summary>
    Unreadable,

    /// <summary>Sınır aşıldı (sayı ya da boyut).</summary>
    Limit,
}

/// <summary>Hata bildirimi eklerinin sınırları ve kuralları.</summary>
public static class ReportAttachments
{
    /// <summary>Bildirim başına en çok dosya.</summary>
    public const int MaxFiles = 5;

    /// <summary>En çok resim (sunucu <c>images</c> için 3 kabul eder).</summary>
    public const int MaxImages = SupportLimits.Images;

    /// <summary>Resim başına (sığdırılmış JPEG) en çok bayt.</summary>
    public const int MaxImageBytes = 1_000_000;

    /// <summary>Bütün eklerin toplamı (base64 resmi 4/3 büyütür; 4 MB gövdeye günlükle birlikte sığsın).</summary>
    public const int MaxTotalBytes = 2_800_000;

    /// <summary>Bundan büyük yazı dosyası okunmaz.</summary>
    public const int MaxTextFileBytes = 1_000_000;

    /// <summary>Bir yazı dosyasından gönderilen (sonundan) UTF-16 birimi.</summary>
    public const int MaxTextUnitsPerFile = 15_000;

    /// <summary>Bütün yazı eklerinin toplamı (<c>log</c> 60 000 tutar).</summary>
    public const int MaxTextUnitsTotal = 30_000;

    /// <summary>Yazı dosyası sayılan uzantılar.</summary>
    public static IReadOnlyList<string> TextExtensions { get; } = ["txt", "log", "text"];

    /// <summary>Uzantıya göre yazı dosyası mı.</summary>
    public static bool IsTextFile(string? path)
    {
        var ext = Path.GetExtension(path ?? "").TrimStart('.');
        return ext.Length > 0 && TextExtensions.Any(e => string.Equals(e, ext, StringComparison.OrdinalIgnoreCase));
    }

    /// <summary>Eklenebilecek dosya mı (resim ya da yazı).</summary>
    public static bool IsAccepted(string? path) => PhotoFit.IsImageFile(path) || IsTextFile(path);

    /// <summary>Dosya seçici süzgecinin kalıbı (resimler ve yazı dosyaları).</summary>
    public static string FilterPattern =>
        PhotoFit.FilterPattern + ";" + string.Join(";", TextExtensions.Select(e => "*." + e));

    /// <summary>
    /// Yazı dosyasının baytlarını çözer: UTF-16 (BOM'lu), olmazsa UTF-8 (BOM'lu da), olmazsa Latin-1. NUL içeren
    /// (ikili) dosya okunmaz: null.
    /// </summary>
    public static string? Decode(byte[] data)
    {
        if (data.Length >= 2 && data[0] == 0xFF && data[1] == 0xFE) return Encoding.Unicode.GetString(data, 2, data.Length - 2);
        if (data.Length >= 2 && data[0] == 0xFE && data[1] == 0xFF)
            return Encoding.BigEndianUnicode.GetString(data, 2, data.Length - 2);
        if (Array.IndexOf(data, (byte)0) >= 0) return null;
        try
        {
            var text = new UTF8Encoding(false, true).GetString(data);
            return text.Length > 0 && text[0] == '﻿' ? text[1..] : text;
        }
        catch (DecoderFallbackException)
        {
            return Encoding.Latin1.GetString(data);
        }
    }

    /// <summary>
    /// <paramref name="existing"/>'e <paramref name="added"/>'den sığanlar sırayla eklenir (en çok 5 dosya, 3 resim,
    /// toplam 2,8 MB); sığmayan varsa <c>Limited</c> doğru.
    /// </summary>
    public static (IReadOnlyList<ReportAttachment> Attachments, bool Limited) Merge(IReadOnlyList<ReportAttachment> existing,
        IEnumerable<ReportAttachment> added)
    {
        var list = existing.ToList();
        var limited = false;
        foreach (var item in added)
        {
            var images = list.Count(a => a.IsImage);
            var total = list.Sum(a => a.ByteCount);
            if (list.Count >= MaxFiles || (item.IsImage && images >= MaxImages) || total + item.ByteCount > MaxTotalBytes
                || (item.IsImage && item.ByteCount > MaxImageBytes))
            {
                limited = true;
                continue;
            }
            list.Add(item);
        }
        return (list, limited);
    }

    /// <summary>
    /// <c>log</c> alanının sonuna eklenen yazı dosyaları: her biri "— ek: ad —" başlığıyla ve sonundan en çok 15 000
    /// birim; hepsi birlikte sonundan en çok 30 000. Yazı eki yoksa boş.
    /// </summary>
    public static string TextBlock(IEnumerable<ReportAttachment> attachments)
    {
        var parts = attachments.Where(a => a.Text is not null)
            .Select(a => "— ek: " + a.Name + " —\n" + SupportLimits.Tail(a.Text!, MaxTextUnitsPerFile))
            .ToList();
        return parts.Count == 0 ? "" : SupportLimits.Tail(string.Join("\n\n", parts), MaxTextUnitsTotal);
    }

    /// <summary>Günlüğün sonuna yazı eklerini koyar (günlük <c>log</c>'un sonundan kesildiği için ekler korunur).</summary>
    public static string? AppendToLog(string? log, string textBlock)
    {
        if (textBlock.Length == 0) return log;
        return string.IsNullOrEmpty(log) ? textBlock : log + "\n\n" + textBlock;
    }

    /// <summary>Kayıtlı gizli değerleri (anahtarlar) metinden çıkarır: her biri <see cref="LogRedactor.Mask"/> olur.</summary>
    public static string WithoutSecrets(string text, IEnumerable<string?> secrets)
    {
        foreach (var secret in secrets)
        {
            var s = secret?.Trim();
            if (string.IsNullOrEmpty(s) || s.Length < 4) continue;
            text = text.Replace(s, LogRedactor.Mask, StringComparison.Ordinal);
        }
        return text;
    }
}
