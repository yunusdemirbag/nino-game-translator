// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
// Samsung giriş/sertifika akışı, sertifika uç noktaları ve Tizen kurulum hata kodlarının anlamı MIT lisanslı
// Jellyfin2Samsung (Samsung-Jellyfin-Installer) projesinden uyarlanmıştır.

using System.Formats.Asn1;
using System.Net.Http.Headers;
using System.Reflection;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Text;
using System.Text.Json;

namespace Nino.TvInstall.Samsung;

/// <summary>Samsung'un sertifika sunucusundan yazar ve dağıtıcı sertifikası alır, TV'nin klasörüne yazar.</summary>
public sealed class SamsungCertificates(HttpClient http, InstallLog log)
{
    public const string Server = "https://svdca.samsungqbe.com";
    public const string AuthorPath = "/apis/v3/authors";
    public const string ProfilePath = "/apis/v1/distributors";
    public const string DistributorPath = "/apis/v3/distributors";
    public const int PbeIterations = 2048;

    /// <summary>Gömülü ara sertifikaların arama sırası.</summary>
    public static readonly string[] CaFiles =
        ["vd_tizen_dev_author_ca.pem", "author_ca.pem", "vd_tizen_dev_public2.pem", "public2.pem"];

    /// <summary>Sunucunun kökü (testler kendi sunucusunu verir).</summary>
    public string BaseUrl { get; init; } = Server;

    /// <summary>Yeni sertifikaları alır ve <paramref name="folder"/>'a yazar.</summary>
    public async Task IssueAsync(SamsungAccount account, string duid, SamsungCertificateFolder folder, CancellationToken ct)
    {
        using var key = RSA.Create(2048);
        var authorCsr = AuthorRequest(key);
        var distCsr = DistributorRequest(key, duid, account.EmailAddress);

        var authorBytes = await PostAsync(AuthorPath, account, authorCsr, "author.csr", false, ct).ConfigureAwait(false);
        var profileBytes = await PostAsync(ProfilePath, account, distCsr, "distributor.csr", true, ct).ConfigureAwait(false);
        var distributorBytes = await PostAsync(DistributorPath, account, distCsr, "distributor.csr", true, ct).ConfigureAwait(false);

        using var authorCert = ReadIssued(authorBytes, "yazar");
        using var distributorCert = ReadIssued(distributorBytes, "dağıtıcı");

        var secret = Convert.ToHexString(RandomNumberGenerator.GetBytes(16));
        Directory.CreateDirectory(folder.Path);
        await File.WriteAllBytesAsync(folder.AuthorPath, BuildPkcs12(authorCert, key, secret), ct).ConfigureAwait(false);
        await File.WriteAllBytesAsync(folder.DistributorPath, BuildPkcs12(distributorCert, key, secret), ct).ConfigureAwait(false);
        await File.WriteAllBytesAsync(folder.DeviceProfilePath, profileBytes, ct).ConfigureAwait(false);
        await File.WriteAllTextAsync(Path.Combine(folder.Path, SamsungCertificateFolder.PasswordFile), secret, ct).ConfigureAwait(false);
        await File.WriteAllTextAsync(Path.Combine(folder.Path, SamsungCertificateFolder.DuidFile), duid, ct).ConfigureAwait(false);
    }

    /// <summary>Yazar CSR'ı (PEM): konu CN=Nino, SHA-256 + PKCS#1.</summary>
    public static string AuthorRequest(RSA key) =>
        new CertificateRequest("CN=Nino", key, HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1).CreateSigningRequestPem();

    /// <summary>Dağıtıcı CSR'ı (PEM): CN=TizenSDK (+ e-posta), konu alternatif adı Tizen paket ve cihaz URN'leri.</summary>
    public static string DistributorRequest(RSA key, string duid, string? email)
    {
        var name = new X500DistinguishedNameBuilder();
        name.AddCommonName("TizenSDK");
        if (!string.IsNullOrWhiteSpace(email)) name.AddEmailAddress(email.Trim());
        var request = new CertificateRequest(name.Build(), key, HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1);
        request.CertificateExtensions.Add(new X509Extension("2.5.29.17", SubjectAltName(duid), false));
        return request.CreateSigningRequestPem();
    }

    /// <summary>
    /// Konu alternatif adının DER'i: iki [6] (URI) IA5String. Hazır yardımcılar şemayı küçük harfe çevirdiği için elle yazılır.
    /// </summary>
    public static byte[] SubjectAltName(string duid)
    {
        var w = new AsnWriter(AsnEncodingRules.DER);
        using (w.PushSequence())
        {
            var uri = new Asn1Tag(TagClass.ContextSpecific, 6);
            w.WriteCharacterString(UniversalTagNumber.IA5String, "URN:tizen:packageid=", uri);
            w.WriteCharacterString(UniversalTagNumber.IA5String, "URN:tizen:deviceid=" + duid, uri);
        }
        return w.Encode();
    }

    async Task<byte[]> PostAsync(string path, SamsungAccount account, string csr, string fileName, bool distributor, CancellationToken ct)
    {
        using var form = new MultipartFormDataContent();
        var fields = new List<(string Name, string Value)>
            { ("access_token", account.AccessToken), ("user_id", account.UserId), ("platform", "VD") };
        if (distributor) fields.AddRange([("privilege_level", "public"), ("developer_type", "Individual")]);
        foreach (var (fieldName, fieldValue) in fields) form.Add(new StringContent(fieldValue), fieldName);
        var file = new ByteArrayContent(Encoding.ASCII.GetBytes(csr));
        file.Headers.ContentType = new MediaTypeHeaderValue("application/octet-stream");
        form.Add(file, "csr", fileName);

        using var cts = CancellationTokenSource.CreateLinkedTokenSource(ct);
        cts.CancelAfter(TimeSpan.FromMinutes(1));
        HttpResponseMessage response;
        byte[] bytes;
        try
        {
            response = await http.PostAsync(BaseUrl + path, form, cts.Token).ConfigureAwait(false);
            bytes = await response.Content.ReadAsByteArrayAsync(cts.Token).ConfigureAwait(false);
        }
        catch (Exception e) when (!ct.IsCancellationRequested && e is HttpRequestException or OperationCanceledException or IOException)
        {
            throw new TvInstallException(TvInstallFailure.CertificateFailed,
                $"Samsung sertifika sunucusu (svdca.samsungqbe.com) yanıt vermedi: {e.Message}", e);
        }
        using (response)
        {
            var code = (int)response.StatusCode;
            log.Write($"Sertifika sunucusu {path}: {code} {response.ReasonPhrase}, {bytes.Length} bayt");
            if (!response.IsSuccessStatusCode)
                throw new TvInstallException(TvInstallFailure.CertificateFailed,
                    $"Samsung sertifika sunucusu {path}: {code} {response.ReasonPhrase} {ServerError(Encoding.UTF8.GetString(bytes))}".TrimEnd());
        }
        return bytes;
    }

    static readonly string[] ErrorFields = ["code", "errorCode", "error", "message", "errorMessage", "error_description"];

    /// <summary>Sunucunun hata metni: JSON nesnesinde bilinen alanlar "ad=değer", değilse kırpılmış metin (en çok 300).</summary>
    public static string ServerError(string text)
    {
        try
        {
            using var doc = JsonDocument.Parse(text);
            if (doc.RootElement.ValueKind == JsonValueKind.Object)
            {
                var parts = new List<string>();
                foreach (var name in ErrorFields)
                {
                    if (!doc.RootElement.TryGetProperty(name, out var v)) continue;
                    if (v.ValueKind == JsonValueKind.String) parts.Add($"{name}={v.GetString()}");
                    else if (v.ValueKind == JsonValueKind.Number) parts.Add($"{name}={v.GetRawText()}");
                }
                if (parts.Count != 0) return string.Join(", ", parts);
            }
        }
        catch (JsonException) { }
        var t = text.Trim();
        return t.Length > 300 ? t[..300] + "…" : t;
    }

    /// <summary>Gelen sertifikayı okur (PEM ya da DER). Okunamazsa sertifika verilmedi.</summary>
    public static X509Certificate2 ReadIssued(byte[] bytes, string kind)
    {
        var text = Encoding.UTF8.GetString(bytes);
        try
        {
            return text.Contains("-----BEGIN CERTIFICATE-----", StringComparison.Ordinal)
                ? X509Certificate2.CreateFromPem(text)
                : X509CertificateLoader.LoadCertificate(bytes);
        }
        catch (CryptographicException)
        {
            throw new TvInstallException(TvInstallFailure.CertificateFailed,
                $"Samsung {kind} sertifikası vermedi: {ServerError(text)}");
        }
    }

    /// <summary>Sertifika + özel anahtar + (varsa) ara sertifika; 3DES PBE, SHA-1, 2048 tur.</summary>
    public static byte[] BuildPkcs12(X509Certificate2 cert, RSA key, string password)
    {
        using var withKey = cert.CopyWithPrivateKey(key);
        var collection = new X509Certificate2Collection { withKey };
        var ca = FindIntermediate(cert);
        if (ca is not null) collection.Add(ca);
        try
        {
            return collection.ExportPkcs12(
                new PbeParameters(PbeEncryptionAlgorithm.TripleDes3KeyPkcs12, HashAlgorithmName.SHA1, PbeIterations), password);
        }
        finally { ca?.Dispose(); }
    }

    /// <summary>Konusu sertifikanın verenine tam eşit, kendinden imzalı olmayan ilk gömülü ara sertifika.</summary>
    public static X509Certificate2? FindIntermediate(X509Certificate2 cert)
    {
        foreach (var ca in EmbeddedCas())
        {
            if (ca.Subject == cert.Issuer && ca.Subject != ca.Issuer) return ca;
            ca.Dispose();
        }
        return null;
    }

    /// <summary>Gömülü ara sertifikalar, arama sırasıyla.</summary>
    public static IEnumerable<X509Certificate2> EmbeddedCas()
    {
        var asm = typeof(SamsungCertificates).Assembly;
        foreach (var file in CaFiles)
        {
            using var stream = asm.GetManifestResourceStream("SamsungCa." + file);
            if (stream is null) continue;
            using var reader = new StreamReader(stream);
            var pem = reader.ReadToEnd();
            yield return X509Certificate2.CreateFromPem(pem);
        }
    }
}
