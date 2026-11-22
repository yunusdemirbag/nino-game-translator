// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

namespace Nino.Core.Data;

/// <summary>
/// Bu oturumda açık duran, bu süreçle aynı adı taşıyan öbür süreçler. <see cref="OwnPath"/> bu sürecin exe yolu
/// (bilinmiyorsa null); <see cref="Others"/> öbürlerinin exe yolları (yolu okunamayan süreç için null).
/// </summary>
public sealed record RunningCopies(string? OwnPath, IReadOnlyList<string?> Others);

/// <summary>Açık aynı adlı süreçleri bulan platform hizmeti (Windows'ta süreç listesi; başka yerde boş).</summary>
public interface IRunningCopyProbe
{
    /// <summary>Süreç listesi hiç alınamazsa null döner (sonuç "yok" sayılır).</summary>
    RunningCopies? Find();
}

/// <summary>Açık öbür kopyaların sınıfı.</summary>
public enum OtherCopyKind
{
    /// <summary>Başka kopya yok.</summary>
    None,
    /// <summary>Bu uygulamanın (aynı klasörden çalışan) ikinci kopyası ya da emin olunamayan bir süreç.</summary>
    ThisApp,
    /// <summary>Başka bir klasörden çalışan, aynı adlı başka bir uygulama.</summary>
    OtherApp,
}

/// <summary>Açık kopyaları sınıflandıran saf kurallar (veri klasörü taşıma kararı için).</summary>
public static class RunningCopyRules
{
    /// <summary>
    /// Velopack başlatıcısının yolu: exe'nin iki üst klasörü + aynı dosya adı
    /// (<c>…\K\current\Nino.exe</c> → <c>…\K\Nino.exe</c>). Üst klasör yoksa null.
    /// </summary>
    public static string? LauncherPath(string? exePath)
    {
        if (string.IsNullOrWhiteSpace(exePath)) return null;
        var (dir, file) = Split(exePath);
        if (dir is null || file.Length == 0) return null;
        var (parent, _) = Split(dir);
        if (string.IsNullOrEmpty(parent)) return null;
        return parent + Separator(exePath) + file;
    }

    /// <summary>Kendi yolumuz ve öbürlerinin yollarıyla sınıflandırır.</summary>
    public static OtherCopyKind Classify(string? ownPath, IReadOnlyList<string?> others)
    {
        if (others.Count == 0) return OtherCopyKind.None;
        if (string.IsNullOrWhiteSpace(ownPath)) return OtherCopyKind.ThisApp;
        var launcher = LauncherPath(ownPath);
        var ownDir = Split(ownPath).Dir;
        var other = false;
        foreach (var path in others)
        {
            if (string.IsNullOrWhiteSpace(path)) return OtherCopyKind.ThisApp;
            if (launcher is not null && SamePath(path, launcher)) continue;
            var dir = Split(path).Dir;
            if (dir is not null && ownDir is not null && SamePath(dir, ownDir)) return OtherCopyKind.ThisApp;
            other = true;
        }
        return other ? OtherCopyKind.OtherApp : OtherCopyKind.None;
    }

    // Windows yolları Mac'te koşan testlerde de bölünebilsin diye iki ayırıcı da tanınır.
    static (string? Dir, string File) Split(string path)
    {
        var trimmed = path.TrimEnd('\\', '/');
        var cut = trimmed.LastIndexOfAny(['\\', '/']);
        return cut < 0 ? (null, trimmed) : (trimmed[..cut], trimmed[(cut + 1)..]);
    }

    static char Separator(string path) => path.Contains('\\') ? '\\' : '/';

    static bool SamePath(string a, string b) =>
        string.Equals(Normalize(a), Normalize(b), StringComparison.OrdinalIgnoreCase);

    static string Normalize(string p) => p.Replace('/', '\\').TrimEnd('\\');
}
