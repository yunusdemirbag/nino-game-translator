// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Text;

namespace Nino.Core.Data;

/// <summary>Veri dosyaları için küçük, ortak dosya işlemleri.</summary>
public static class FileIo
{
    /// <summary>BOM yazmayan UTF-8. Nino'nun yazdığı her metin dosyası bununla yazılır.</summary>
    public static readonly UTF8Encoding Utf8 = new(encoderShouldEmitUTF8Identifier: false);

    /// <summary>
    /// <paramref name="path"/>.tmp'ye yazar, sonra asıl dosyanın üstüne taşır. Klasör yoksa oluşturur.
    /// <paramref name="ownerOnly"/> doğruysa (Windows dışı) geçici dosya baştan 0600 izniyle açılır; taşıma izni korur.
    /// </summary>
    public static void WriteAtomic(string path, ReadOnlySpan<byte> content, bool ownerOnly = false)
    {
        var dir = Path.GetDirectoryName(Path.GetFullPath(path));
        if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);
        var tmp = path + ".tmp";
        var options = new FileStreamOptions
        {
            Mode = FileMode.Create,
            Access = FileAccess.Write,
            Share = FileShare.None,
        };
        if (ownerOnly && !OperatingSystem.IsWindows())
            options.UnixCreateMode = UnixFileMode.UserRead | UnixFileMode.UserWrite;
        using (var stream = new FileStream(tmp, options))
        {
            stream.Write(content);
            stream.Flush(flushToDisk: true);
        }
        if (ownerOnly && !OperatingSystem.IsWindows())
            File.SetUnixFileMode(tmp, UnixFileMode.UserRead | UnixFileMode.UserWrite);
        File.Move(tmp, path, overwrite: true);
    }

    /// <summary>Metni BOM'suz UTF-8 olarak atomik yazar.</summary>
    public static void WriteAtomic(string path, string text, bool ownerOnly = false) =>
        WriteAtomic(path, Utf8.GetBytes(text), ownerOnly);

    /// <summary>Dosya sisteminden gelen ve işi durdurmaması gereken hata mı (G/Ç ya da izin).</summary>
    public static bool IsIoError(Exception error) => error is IOException or UnauthorizedAccessException;

    /// <summary>
    /// Okunamayan bir dosyayı silinmeden önce yanına <c>&lt;ad&gt;.bozuk-&lt;yyyyMMdd-HHmmss&gt;</c> adıyla kenara alır.
    /// Aynı adlı kopya varsa sonuna sayı eklenir. Başarısızsa null döner (dosya yerinde kalır).
    /// </summary>
    public static string? SetAside(string path, DateTimeOffset now)
    {
        try
        {
            if (!File.Exists(path)) return null;
            var stamp = now.ToLocalTime().ToString("yyyyMMdd-HHmmss", System.Globalization.CultureInfo.InvariantCulture);
            var target = $"{path}.bozuk-{stamp}";
            for (var i = 2; File.Exists(target) || Directory.Exists(target); i++)
                target = $"{path}.bozuk-{stamp}-{i}";
            File.Move(path, target);
            return target;
        }
        catch (Exception e) when (FileIo.IsIoError(e))
        {
            return null;
        }
    }
}
