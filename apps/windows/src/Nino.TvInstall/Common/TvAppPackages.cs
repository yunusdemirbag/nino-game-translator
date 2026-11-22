// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

namespace Nino.TvInstall;

/// <summary>Uygulamanın yanında gelen bir TV uygulaması paketi.</summary>
public sealed record TvAppPackage(string Path, string Version);

/// <summary>
/// Uygulama klasöründeki <c>tv-app</c> klasöründe LG (*.ipk), Samsung (*.wgt) ve Android TV (*.apk) paketlerini bulur.
/// Sürümü okunamayan paket yok sayılır.
/// </summary>
public static class TvAppPackages
{
    public const string FolderName = "tv-app";

    public static TvAppPackage? FindLg(string tvAppFolder) => Find(tvAppFolder, "*.ipk", LgVersion);

    public static TvAppPackage? FindSamsung(string tvAppFolder) => Find(tvAppFolder, "*.wgt", SuffixVersion);

    public static TvAppPackage? FindAndroid(string tvAppFolder) => Find(tvAppFolder, "*.apk", SuffixVersion);

    /// <summary>LG: <c>com.ninotranslator.tv_0.6.1_all.ipk</c> → <c>0.6.1</c> (en az üç <c>_</c> parçası ve .ipk).</summary>
    public static string? LgVersion(string fileName)
    {
        var name = System.IO.Path.GetFileName(fileName);
        if (!name.EndsWith(".ipk", StringComparison.OrdinalIgnoreCase)) return null;
        var parts = name.Split('_');
        return parts.Length >= 3 && parts[1].Length > 0 ? parts[1] : null;
    }

    /// <summary>Samsung/Android: uzantısız adın son <c>_</c>'ından sonrası (<c>nino-androidtv_0.7.0.apk</c> → <c>0.7.0</c>).</summary>
    public static string? SuffixVersion(string fileName)
    {
        var stem = System.IO.Path.GetFileNameWithoutExtension(fileName);
        var at = stem.LastIndexOf('_');
        if (at <= 0 || at == stem.Length - 1) return null;
        return stem[(at + 1)..];
    }

    static TvAppPackage? Find(string folder, string pattern, Func<string, string?> version)
    {
        try
        {
            if (!Directory.Exists(folder)) return null;
            var first = Directory.GetFiles(folder, pattern).OrderBy(f => f, StringComparer.Ordinal).FirstOrDefault();
            if (first is null) return null;
            var v = version(first);
            return v is null ? null : new TvAppPackage(first, v);
        }
        catch (IOException) { return null; }
        catch (UnauthorizedAccessException) { return null; }
    }
}
