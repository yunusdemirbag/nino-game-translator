// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
// Samsung giriş/sertifika akışı, sertifika uç noktaları ve Tizen kurulum hata kodlarının anlamı MIT lisanslı
// Jellyfin2Samsung (Samsung-Jellyfin-Installer) projesinden uyarlanmıştır.

using System.Text.RegularExpressions;

namespace Nino.TvInstall.Samsung;

/// <summary>Tizen kurulum çıktısının sınıfı.</summary>
public enum SamsungInstallProblem
{
    None,
    ConnectionLost,
    NotEligible,
    NoSpace,
    CertificateRejected,
    TvClockBehind,
    OldCopyOtherCertificate,
    OldRegistration,
    Other,
}

/// <summary>sdb kabuk çıktılarını okuyan saf işlevler.</summary>
public static partial class SamsungInstallOutput
{
    public const string NinoAppId = "NinoTVApps.Nino";
    public const string NinoPackageId = "NinoTVApps";

    [GeneratedRegex(@"^[\s-]*([A-Za-z_]+)\s*=\s*(.*?)[\s-]*$")]
    private static partial Regex FieldRegex();

    [GeneratedRegex(@"^[A-Za-z0-9_\-+=/]{8,}$")]
    private static partial Regex DuidRegex();

    /// <summary><c>0 vd_applist</c> çıktısında Nino'nun sürümü; yoksa null.</summary>
    public static string? AppListVersion(string? output)
    {
        if (string.IsNullOrEmpty(output)) return null;
        var block = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (var raw in output.Split('\n'))
        {
            var line = raw.TrimEnd('\r');
            if (!line.Contains('=') && line.Contains("----"))
            {
                block.Clear();
                continue;
            }
            var m = FieldRegex().Match(line);
            if (!m.Success) continue;
            block[m.Groups[1].Value] = m.Groups[2].Value;
            if (IsNino(block, "app_tizen_id") || IsNino(block, "app_id"))
            {
                if (block.TryGetValue("app_version", out var v) && v.Trim().Length > 0) return v.Trim();
            }
        }
        return null;
    }

    static bool IsNino(Dictionary<string, string> block, string key) =>
        block.TryGetValue(key, out var id) &&
        (id.Trim().Equals(NinoAppId, StringComparison.OrdinalIgnoreCase) || id.Trim().Equals(NinoPackageId, StringComparison.OrdinalIgnoreCase));

    /// <summary><c>0 getduid</c> çıktısının ilk satırı DUID biçimindeyse o; değilse null.</summary>
    public static string? ParseDuid(string? output)
    {
        var first = (output ?? "").Split('\n')[0].Trim();
        return DuidRegex().IsMatch(first) ? first : null;
    }

    static bool Has(string text, string part) => text.Contains(part, StringComparison.OrdinalIgnoreCase);

    /// <summary>Kurulum çıktısını sınıflar (ilk tutan kural).</summary>
    public static SamsungInstallProblem Classify(string? output)
    {
        var o = output ?? "";
        var connection = Has(o, "transport connection") || Has(o, "connection reset by peer") || Has(o, "broken pipe");
        var failed = connection || Has(o, "install failed") || Has(o, "val[fail]") || Has(o, "not enough space") ||
                     Has(o, "download failed[116]");
        if (!failed) return SamsungInstallProblem.None;
        if (connection) return SamsungInstallProblem.ConnectionLost;
        if (Has(o, "install failed[118, -4]") || Has(o, "install failed[118, -19]") || Has(o, "install failed[118019]"))
            return SamsungInstallProblem.NotEligible;
        if (Has(o, "download failed[116]") || Has(o, "not enough space")) return SamsungInstallProblem.NoSpace;
        var certCode = Has(o, "install failed[118, -12]") || Has(o, "[118012]") || Has(o, "[118, -11]") || Has(o, "[118011]");
        if (certCode && Has(o, "Check certificate error") && !Has(o, "same id and different certificate"))
            return Has(o, "not valid yet") ? SamsungInstallProblem.TvClockBehind : SamsungInstallProblem.CertificateRejected;
        if (certCode || Has(o, "Author certificate not match")) return SamsungInstallProblem.OldCopyOtherCertificate;
        if (Has(o, "install failed[118, -22]") || Has(o, "[118022]")) return SamsungInstallProblem.OldRegistration;
        return SamsungInstallProblem.Other;
    }

    /// <summary>Sorunun ortak hata türü.</summary>
    public static TvInstallFailure FailureOf(SamsungInstallProblem problem) => problem switch
    {
        SamsungInstallProblem.ConnectionLost => TvInstallFailure.ConnectionLost,
        SamsungInstallProblem.NoSpace => TvInstallFailure.NotEnoughSpace,
        SamsungInstallProblem.OldCopyOtherCertificate => TvInstallFailure.CertificateMismatch,
        SamsungInstallProblem.CertificateRejected => TvInstallFailure.CertificateRejected,
        SamsungInstallProblem.TvClockBehind => TvInstallFailure.TvClockWrong,
        SamsungInstallProblem.OldRegistration => TvInstallFailure.PackageBlocked,
        _ => TvInstallFailure.InstallFailed,
    };

    /// <summary>Eski kopyayı kaldırmak işe yarayabilecek sorunlar.</summary>
    public static bool UninstallMayHelp(SamsungInstallProblem p) =>
        p is SamsungInstallProblem.OldCopyOtherCertificate or SamsungInstallProblem.OldRegistration or SamsungInstallProblem.Other;

    /// <summary>Kullanıcıya gösterilecek kısa özet (en çok 400 karakter).</summary>
    public static string Summary(string? output)
    {
        if (string.IsNullOrWhiteSpace(output)) return "TV'den cevap gelmedi";
        var lines = output.Split('\n').Select(l => l.Trim()).Where(l => l.Length > 0).ToList();
        var picked = lines.Where(l => Has(l, "fail") || Has(l, "error") || Has(l, "reason") || Has(l, "not match") || Has(l, "space"))
            .Distinct().Take(3).ToList();
        if (picked.Count == 0) picked = lines.Skip(Math.Max(0, lines.Count - 3)).ToList();
        var text = string.Join(" | ", picked);
        return text.Length > 400 ? text[..400] + "…" : text;
    }
}
