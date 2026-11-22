// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Globalization;
using System.Text.Json;

namespace Nino.Core.Data;

/// <summary>
/// Toplam indirme sayacı (<c>pool-translations\downloads.txt</c>): sunucunun <c>/v1/config</c> cevabındaki
/// <c>downloads</c> alanı; değişince düz sayı olarak yazılır.
/// </summary>
public sealed class DownloadCounter
{
    /// <summary>Klasör içindeki dosya adı.</summary>
    public const string DownloadsFile = "downloads.txt";

    readonly string? _path;
    readonly object _gate = new();

    /// <param name="path">Dosya yolu; null ise yalnız bellek.</param>
    public DownloadCounter(string? path)
    {
        _path = path;
        Value = ReadFile(path);
    }

    /// <summary>Son bilinen sayı; hiç alınamadıysa null (gösterge gizli).</summary>
    public long? Value { get; private set; }

    /// <summary>Sunucu cevabından gelen sayıyı uygular; değiştiyse dosyaya yazar. Geçersiz cevap bir şey değiştirmez.</summary>
    public bool Update(string? configJson)
    {
        if (Parse(configJson) is not { } count) return false;
        lock (_gate)
        {
            if (Value == count) return false;
            Value = count;
            if (_path is not null)
            {
                try { FileIo.WriteAtomic(_path, count.ToString(CultureInfo.InvariantCulture)); }
                catch (Exception e) when (FileIo.IsIoError(e)) { }
            }
            return true;
        }
    }

    /// <summary>Yerel binlik ayırıcıyla ("3.439" tr, "3,439" en).</summary>
    public static string Format(long count, CultureInfo culture) => count.ToString("#,0", culture);

    /// <summary>
    /// Kök nesnede <c>downloads</c> &gt; 0 tam sayı (kesirsiz ondalık da) ise o; değilse null.
    /// </summary>
    public static long? Parse(string? json)
    {
        if (string.IsNullOrWhiteSpace(json)) return null;
        try
        {
            using var doc = JsonDocument.Parse(json);
            if (doc.RootElement.ValueKind != JsonValueKind.Object
                || !doc.RootElement.TryGetProperty("downloads", out var d) || d.ValueKind != JsonValueKind.Number)
                return null;
            if (d.TryGetInt64(out var n)) return n > 0 ? n : null;
            if (d.TryGetDecimal(out var m) && m == decimal.Truncate(m) && m > 0 && m <= long.MaxValue) return (long)m;
            return null;
        }
        catch (JsonException) { return null; }
    }

    static long? ReadFile(string? path)
    {
        if (path is null) return null;
        try
        {
            if (!File.Exists(path)) return null;
            var text = File.ReadAllText(path, FileIo.Utf8).Trim();
            return text.Length > 0 && text.All(char.IsAsciiDigit)
                   && long.TryParse(text, NumberStyles.None, CultureInfo.InvariantCulture, out var n) && n > 0
                ? n
                : null;
        }
        catch (Exception e) when (FileIo.IsIoError(e)) { return null; }
    }
}

/// <summary>Tek satırlık kuruluş kimliği dosyaları.</summary>
public static class InstallIdFile
{
    /// <summary>Sorun bildirme / Nino'ya Sor kimliğinin dosya adı (veri klasöründe).</summary>
    public const string ReportFileName = "report-install.txt";

    /// <summary>
    /// Çeviri havuzu kimliği (<c>pool-translations\install</c>): kırpılmış içerik geçerli GUID ise o (küçük harf,
    /// tireli), değilse yeni üretilip yazılır. Yazılamazsa üretilen kimlik yine döner.
    /// </summary>
    public static string ReadOrCreateGuid(string path)
    {
        if (ReadTrimmed(path) is { } text && Guid.TryParse(text, out var existing)) return existing.ToString("D");
        return WriteNew(path, Guid.NewGuid().ToString("D"));
    }

    /// <summary>
    /// Sorun bildirme kimliği: havuz kimliği 8–64 karakterse o; değilse <c>report-install.txt</c> 8–64 karakterse o;
    /// değilse yeni GUID (32 onaltılık, tiresiz) üretilip yazılır.
    /// </summary>
    public static string ReadOrCreateReportId(string path, string? poolInstallId)
    {
        if (poolInstallId is { Length: >= 8 and <= 64 }) return poolInstallId;
        if (ReadTrimmed(path) is { Length: >= 8 and <= 64 } text) return text;
        return WriteNew(path, Guid.NewGuid().ToString("N"));
    }

    static string? ReadTrimmed(string path)
    {
        try { return File.Exists(path) ? File.ReadAllText(path, FileIo.Utf8).Trim() : null; }
        catch (Exception e) when (FileIo.IsIoError(e)) { return null; }
    }

    static string WriteNew(string path, string id)
    {
        try { FileIo.WriteAtomic(path, id); }
        catch (Exception e) when (FileIo.IsIoError(e)) { }
        return id;
    }
}
