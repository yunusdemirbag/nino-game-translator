// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Text.RegularExpressions;
using Nino.Core.Data;
using Nino.Core.Logging;

namespace Nino.Core.Support;

/// <summary>
/// Günlüklerdeki gizli değerleri <c>[gizlendi]</c> ile değiştirir: Bearer/Basic belirteçleri, anahtar/şifre atamaları,
/// bilinen anahtar kalıpları, uzun onaltılık diziler ve uzun belirteçler.
/// </summary>
public static partial class LogRedactor
{
    /// <summary>Gizlenen değerin yerine yazılan.</summary>
    public const string Mask = "[gizlendi]";

    [GeneratedRegex(@"(?<![A-Za-z])(Bearer|Basic)(\s+)[A-Za-z0-9._~+/=\-]{8,}", RegexOptions.IgnoreCase)]
    private static partial Regex AuthScheme();

    [GeneratedRegex(
        @"(?<![A-Za-z])(api[_\-]?key|access_token|refresh_token|client_secret|session_key|authorization|password|passcode|passwd|secret|cookie|npsso|token|auth|pwd|pin|key)(""?'?\s*[=:]\s*""?'?)([^\s""'&,;]+)",
        RegexOptions.IgnoreCase)]
    private static partial Regex Assignment();

    [GeneratedRegex(@"AIza[0-9A-Za-z_\-]{20,}")]
    private static partial Regex GoogleKey();

    [GeneratedRegex(@"(?<![A-Za-z0-9])sk-[A-Za-z0-9_\-]{16,}")]
    private static partial Regex SecretKey();

    [GeneratedRegex(@"gh[pousr]_[A-Za-z0-9]{20,}")]
    private static partial Regex GitHubToken();

    [GeneratedRegex(@"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}(:fx)?")]
    private static partial Regex Uuid();

    [GeneratedRegex(@"[0-9a-fA-F]{32,}")]
    private static partial Regex LongHex();

    [GeneratedRegex(@"(?<![A-Za-z0-9+/_\-])[A-Za-z0-9+/_\-]{40,}={0,2}")]
    private static partial Regex LongToken();

    /// <summary>Metni gizler.</summary>
    public static string Redact(string text)
    {
        if (string.IsNullOrEmpty(text)) return text;
        text = AuthScheme().Replace(text, m => m.Groups[1].Value + m.Groups[2].Value + Mask);
        text = Assignment().Replace(text, m =>
        {
            var value = m.Groups[3].Value;
            if (value.StartsWith(Mask, StringComparison.Ordinal)
                || value.Equals("Bearer", StringComparison.OrdinalIgnoreCase)
                || value.Equals("Basic", StringComparison.OrdinalIgnoreCase))
                return m.Value;
            return m.Groups[1].Value + m.Groups[2].Value + Mask;
        });
        text = GoogleKey().Replace(text, Mask);
        text = SecretKey().Replace(text, Mask);
        text = GitHubToken().Replace(text, Mask);
        text = Uuid().Replace(text, Mask);
        text = LongHex().Replace(text, Mask);
        text = LongToken().Replace(text, m =>
            m.Value.Any(char.IsAsciiDigit) && m.Value.Any(char.IsAsciiLetter) ? Mask : m.Value);
        return text;
    }
}

/// <summary>
/// Sorun bildirme penceresindeki günlük ekleme seçeneği: günlüklerin sonlarını toplar, gizler ve 60 000 karaktere keser.
/// </summary>
public static class LogCollector
{
    /// <summary>Dosyalar ve payları (her birinin sonundan, karakter), bu sırayla.</summary>
    public static IReadOnlyList<(string File, int Share)> Shares { get; } =
    [
        (LogNames.Error, 10_000),
        (LogNames.RemotePlay, 18_000),
        (LogNames.Subtitle, 24_000),
        (LogNames.TvInstall, 8_000),
    ];

    /// <summary>
    /// Veri klasöründeki günlüklerden bildirim günlüğü; hiçbiri yoksa null. Sınır 60 000'den küçükse paylar aynı oranla
    /// küçültülür (her dosyadan bir parça kalsın).
    /// </summary>
    public static string? Collect(string folder, int limit = SupportLimits.Log)
    {
        var total = Shares.Sum(s => s.Share);
        var pieces = new List<string>();
        foreach (var (file, share) in Shares)
        {
            var chars = limit >= total ? share : Math.Max(1, (int)((long)share * limit / total));
            if (ReadTail(Path.Combine(folder, file), chars) is not { } tail) continue;
            pieces.Add($"— {file} —\n{tail.TrimEnd()}");
        }
        if (pieces.Count == 0) return null;
        var joined = LogRedactor.Redact(string.Join("\n\n", pieces));
        return LastChars(joined, limit);
    }

    /// <summary>
    /// Dosyanın son <paramref name="chars"/> karakteri; yazılırken de okunabilsin diye paylaşımlı açılır. Ortadan
    /// başlandıysa ilk yarım satır atılır. Dosya yoksa ya da okunamazsa null.
    /// </summary>
    public static string? ReadTail(string path, int chars)
    {
        try
        {
            if (!File.Exists(path)) return null;
            using var stream = new FileStream(path, FileMode.Open, FileAccess.Read,
                FileShare.ReadWrite | FileShare.Delete);
            var maxBytes = (long)chars * 4;
            var start = Math.Max(0, stream.Length - maxBytes);
            stream.Seek(start, SeekOrigin.Begin);
            using var ms = new MemoryStream();
            stream.CopyTo(ms);
            var text = FileIo.Utf8.GetString(ms.GetBuffer(), 0, (int)ms.Length);
            if (start > 0)
            {
                var nl = text.IndexOf('\n');
                text = nl < 0 ? "" : text[(nl + 1)..];
            }
            return LastChars(text, chars);
        }
        catch (Exception e) when (FileIo.IsIoError(e))
        {
            return null;
        }
    }

    /// <summary>
    /// Son <paramref name="n"/> karakter; kesim satır ortasına düştüyse (ve ilk satır sonu son karakter değilse) o
    /// yarım satır atılır.
    /// </summary>
    public static string LastChars(string text, int n)
    {
        if (text.Length <= n) return text;
        var cut = SupportLimits.Tail(text, n);
        var midLine = text[text.Length - cut.Length - 1] != '\n';
        if (!midLine) return cut;
        var nl = cut.IndexOf('\n');
        return nl >= 0 && nl < cut.Length - 1 ? cut[(nl + 1)..] : cut;
    }

    /// <summary>Metnin son <paramref name="count"/> satırı (Ayrıntılar kutusu için).</summary>
    public static IReadOnlyList<string> LastLines(string? text, int count)
    {
        if (string.IsNullOrEmpty(text)) return [];
        var lines = text.Replace("\r\n", "\n").TrimEnd('\n').Split('\n');
        return lines.Length <= count ? lines : lines[^count..];
    }

    /// <summary>Dosyanın son <paramref name="maxBytes"/> baytındaki son satırlar; dosya yoksa null.</summary>
    public static IReadOnlyList<string>? LastLinesOfFile(string path, int count, int maxBytes = 64 * 1024) =>
        ReadTail(path, maxBytes / 4) is { } tail ? LastLines(tail, count) : null;
}
