// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
// Samsung giriş/sertifika akışı, sertifika uç noktaları ve Tizen kurulum hata kodlarının anlamı MIT lisanslı
// Jellyfin2Samsung (Samsung-Jellyfin-Installer) projesinden uyarlanmıştır.

using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Text;

namespace Nino.TvInstall.Samsung;

/// <summary>
/// Bir Samsung TV'nin sertifika klasörü: <c>author.p12</c>, <c>distributor.p12</c>, <c>password.txt</c>, <c>duid.txt</c>,
/// <c>device-profile.xml</c>.
/// </summary>
public sealed class SamsungCertificateFolder(string path)
{
    public const string AuthorFile = "author.p12";
    public const string DistributorFile = "distributor.p12";
    public const string PasswordFile = "password.txt";
    public const string DuidFile = "duid.txt";
    public const string DeviceProfileFile = "device-profile.xml";

    public string Path { get; } = path;
    public string AuthorPath => System.IO.Path.Combine(Path, AuthorFile);
    public string DistributorPath => System.IO.Path.Combine(Path, DistributorFile);
    public string DeviceProfilePath => System.IO.Path.Combine(Path, DeviceProfileFile);

    /// <summary>Kökün altında bu DUID'in klasörü (harf, rakam, _ ve - dışı karakterler _ olur).</summary>
    public static SamsungCertificateFolder ForDuid(string root, string duid) =>
        new(System.IO.Path.Combine(root, SafeName(duid)));

    public static string SafeName(string duid)
    {
        var sb = new StringBuilder(duid.Length);
        foreach (var c in duid) sb.Append(char.IsAsciiLetterOrDigit(c) || c is '_' or '-' ? c : '_');
        return sb.ToString();
    }

    /// <summary>Parola (kırpılmış); okunamazsa boş.</summary>
    public string Password
    {
        get
        {
            try { return File.Exists(System.IO.Path.Combine(Path, PasswordFile)) ? File.ReadAllText(System.IO.Path.Combine(Path, PasswordFile)).Trim() : ""; }
            catch (Exception x) when (x is IOException or UnauthorizedAccessException) { return ""; }
        }
    }

    /// <summary>İki p12 var ve parola boş değil.</summary>
    public bool Exists => File.Exists(AuthorPath) && File.Exists(DistributorPath) && Password.Length > 0;

    /// <summary>Var ve iki sertifika da (bir günlük payla) şu an geçerli. Okunamazsa geçersiz.</summary>
    public bool IsValid(DateTimeOffset now)
    {
        if (!Exists) return false;
        try
        {
            using var a = LoadCertificate(AuthorPath, Password);
            using var d = LoadCertificate(DistributorPath, Password);
            return Covers(a, now) && Covers(d, now);
        }
        catch (CryptographicException) { return false; }
        catch (IOException) { return false; }
    }

    static bool Covers(X509Certificate2 cert, DateTimeOffset now)
    {
        var t = now.UtcDateTime.AddDays(1);
        return cert.NotBefore.ToUniversalTime() <= t && cert.NotAfter.ToUniversalTime() >= t;
    }

    /// <summary>Bu TV'nin mi: <c>duid.txt</c> yoksa evet; varsa içerik DUID'e eşitse evet; okunamazsa hayır.</summary>
    public bool BelongsTo(string duid)
    {
        var file = System.IO.Path.Combine(Path, DuidFile);
        try { return !File.Exists(file) || File.ReadAllText(file).Trim() == duid; }
        catch (Exception x) when (x is UnauthorizedAccessException or IOException) { return false; }
    }

    /// <summary>Günlük için durum yazısı.</summary>
    public string Describe(string duid, DateTimeOffset now)
    {
        if (!Exists) return "yok";
        try
        {
            using var a = LoadCertificate(AuthorPath, Password);
            using var d = LoadCertificate(DistributorPath, Password);
            var state = !BelongsTo(duid) ? "farklı bir TV'ye ait" : IsValid(now) ? "geçerli" : "süresi dolmuş";
            return $"{state}; yazar {a.NotBefore.ToUniversalTime():yyyy-MM-dd HH:mm}–{a.NotAfter.ToUniversalTime():yyyy-MM-dd} UTC, " +
                   $"dağıtıcı {d.NotBefore.ToUniversalTime():yyyy-MM-dd HH:mm}–{d.NotAfter.ToUniversalTime():yyyy-MM-dd} UTC, " +
                   $"dağıtıcıyı veren {d.GetNameInfo(X509NameType.SimpleName, true)}";
        }
        catch (Exception e) when (e is CryptographicException or IOException)
        {
            return $"okunamadı ({e.Message})";
        }
    }

    /// <summary>Reddedilen klasörü <c>klasör.rejected-yyyyMMddHHmmss</c> adına taşır; olmazsa siler; o da olmazsa bırakır.</summary>
    public void SetAside(DateTimeOffset now)
    {
        if (!Directory.Exists(Path)) return;
        var target = Path.TrimEnd(System.IO.Path.DirectorySeparatorChar, System.IO.Path.AltDirectorySeparatorChar) +
                     ".rejected-" + now.UtcDateTime.ToString("yyyyMMddHHmmss");
        try { Directory.Move(Path, target); return; }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
        try { Directory.Delete(Path, true); }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
    }

    /// <summary>p12'yi açar. macOS geçici anahtar kümesini desteklemez; orada o seçenek verilmez.</summary>
    public static X509Certificate2 LoadCertificate(string p12Path, string password)
    {
        var flags = OperatingSystem.IsMacOS() ? X509KeyStorageFlags.DefaultKeySet : X509KeyStorageFlags.EphemeralKeySet;
        return X509CertificateLoader.LoadPkcs12FromFile(p12Path, password, flags);
    }
}
