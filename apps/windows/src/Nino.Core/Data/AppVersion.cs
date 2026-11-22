// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Globalization;

namespace Nino.Core.Data;

/// <summary>Sürüm numarası karşılaştırma (<c>v4.0.1</c>, <c>0.1.0-beta.10</c>, <c>1.2.3+abc</c>).</summary>
public static class AppVersion
{
    /// <summary>Bilgi sürümünün <c>+</c> öncesi; boşsa <c>0.0.0</c>.</summary>
    public static string FromInformational(string? informational)
    {
        var text = (informational ?? "").Trim();
        var plus = text.IndexOf('+');
        if (plus >= 0) text = text[..plus];
        return text.Length == 0 ? "0.0.0" : text;
    }

    /// <summary>a &lt; b ise negatif, eşitse 0, büyükse pozitif.</summary>
    public static int Compare(string? a, string? b)
    {
        var (coreA, preA) = Split(a);
        var (coreB, preB) = Split(b);
        var parts = Math.Max(coreA.Length, coreB.Length);
        for (var i = 0; i < parts; i++)
        {
            var left = coreA.ElementAtOrDefault(i);
            var right = coreB.ElementAtOrDefault(i);
            if (left != right) return left < right ? -1 : 1;
        }
        if (preA.Length == 0 || preB.Length == 0) return preB.Length.CompareTo(0) - preA.Length.CompareTo(0);
        for (var i = 0; ; i++)
        {
            if (i >= preA.Length || i >= preB.Length) return preA.Length.CompareTo(preB.Length);
            var na = long.TryParse(preA[i], NumberStyles.None, CultureInfo.InvariantCulture, out var va);
            var nb = long.TryParse(preB[i], NumberStyles.None, CultureInfo.InvariantCulture, out var vb);
            int c;
            if (na && nb) c = va.CompareTo(vb);
            else if (na) c = -1;
            else if (nb) c = 1;
            else c = string.CompareOrdinal(preA[i], preB[i]);
            if (c != 0) return Math.Sign(c);
        }
    }

    /// <summary><paramref name="candidate"/>, <paramref name="current"/>'ten yeni mi.</summary>
    public static bool IsNewer(string? candidate, string? current) => Compare(candidate, current) > 0;

    static (long[] Core, string[] Pre) Split(string? version)
    {
        var text = (version ?? "").Trim();
        while (text.StartsWith('v') || text.StartsWith('V')) text = text[1..];
        var plus = text.IndexOf('+');
        if (plus >= 0) text = text[..plus];
        var dash = text.IndexOf('-');
        var core = dash >= 0 ? text[..dash] : text;
        var pre = dash >= 0 ? text[(dash + 1)..] : "";
        var numbers = core.Split('.').Select(p =>
            long.TryParse(p, NumberStyles.None, CultureInfo.InvariantCulture, out var n) ? n : 0).ToArray();
        return (numbers, pre.Length == 0 ? [] : pre.Split('.'));
    }
}

/// <summary>
/// Kendiliğinden güncelleme deneme sayacı (<c>auto-update-tried.txt</c>: <c>&lt;sürüm&gt;\n&lt;sayı&gt;\n</c>).
/// Sürüm başına en çok <see cref="MaxAttempts"/> kendiliğinden deneme.
/// </summary>
public sealed class AutoUpdateAttempts
{
    /// <summary>Dosya adı.</summary>
    public const string FileName = "auto-update-tried.txt";

    /// <summary>Sürüm başına kendiliğinden deneme hakkı.</summary>
    public const int MaxAttempts = 2;

    readonly string? _path;
    readonly object _gate = new();
    string? _memoryVersion;
    int _memoryCount;

    /// <param name="path">Dosya yolu; null ise yalnız bellek (testler).</param>
    public AutoUpdateAttempts(string? path) => _path = path;

    /// <summary>Bu sürüm için yapılmış deneme sayısı: max(bellek, dosya).</summary>
    public int Count(string version)
    {
        lock (_gate) return Math.Max(MemoryCount(version), FileCount(version));
    }

    /// <summary>Hak tükendi mi.</summary>
    public bool Exhausted(string version) => Count(version) >= MaxAttempts;

    /// <summary>Bir deneme kaydeder. Dosya yazılamazsa false (bellekteki sayım sürer).</summary>
    public bool Record(string version)
    {
        lock (_gate)
        {
            var next = Math.Max(MemoryCount(version), FileCount(version)) + 1;
            _memoryVersion = version;
            _memoryCount = next;
            if (_path is null) return true;
            try
            {
                FileIo.WriteAtomic(_path, $"{version}\n{next}\n");
                return true;
            }
            catch (Exception e) when (FileIo.IsIoError(e)) { return false; }
        }
    }

    int MemoryCount(string version) => _memoryVersion == version ? _memoryCount : 0;

    int FileCount(string version)
    {
        if (_path is null) return 0;
        try
        {
            if (!File.Exists(_path)) return 0;
            var lines = File.ReadAllLines(_path, FileIo.Utf8).Select(l => l.Trim()).Where(l => l.Length > 0).ToArray();
            if (lines.FirstOrDefault() != version) return 0;
            return lines.Length > 1 && int.TryParse(lines[1], NumberStyles.None, CultureInfo.InvariantCulture, out var n)
                                    && n > 0
                ? n
                : 1;
        }
        catch (Exception e) when (FileIo.IsIoError(e)) { return 0; }
    }
}
