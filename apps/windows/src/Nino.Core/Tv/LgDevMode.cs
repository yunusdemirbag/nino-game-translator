// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Diagnostics;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;

namespace Nino.Core.Tv;

/// <summary>LG geliştirici modu: açık mı, Key Server'dan anahtar alma.</summary>
public static partial class LgDevMode
{
    public const int SshPort = 9922;
    public const int KeyServerPort = 9991;

    /// <summary>SSH (9922) ya da Key Server (9991) 2 sn içinde bağlantı kabul ediyorsa açık (ikisi aynı anda denenir).</summary>
    public static async Task<bool> IsOpenAsync(string host, CancellationToken ct = default)
    {
        var ssh = LocalNetwork.IsPortOpenAsync(host, SshPort, TimeSpan.FromSeconds(2), ct);
        var keys = LocalNetwork.IsPortOpenAsync(host, KeyServerPort, TimeSpan.FromSeconds(2), ct);
        var results = await Task.WhenAll(ssh, keys).ConfigureAwait(false);
        return results[0] || results[1];
    }

    /// <summary>
    /// <c>http://adres:9991/webos_rsa</c>'yı indirir (5 sn) ve TV'nin gösterdiği parolayla parolasız PEM'e çevirir.
    /// Eski şifreli PEM uygulamanın içinde çözülür; değilse sistemin <c>ssh-keygen</c>'i denenir.
    /// </summary>
    public static async Task<string> FetchKeyAsync(string host, string passphrase, HttpClient? http = null,
        CancellationToken ct = default)
    {
        http ??= new HttpClient();
        string pem;
        using (var cts = CancellationTokenSource.CreateLinkedTokenSource(ct))
        {
            cts.CancelAfter(TimeSpan.FromSeconds(5));
            try { pem = await http.GetStringAsync($"http://{host}:{KeyServerPort}/webos_rsa", cts.Token).ConfigureAwait(false); }
            catch (Exception e) when (!ct.IsCancellationRequested) { throw new TvException(TvError.KeyServerClosed, e.Message, e); }
        }
        return await UnlockAsync(pem, passphrase, ct).ConfigureAwait(false);
    }

    /// <summary>İndirilmiş anahtarı parolayla açar (büyük harfli parola da denenir).</summary>
    public static async Task<string> UnlockAsync(string pem, string passphrase, CancellationToken ct = default)
    {
        var pass = passphrase.Trim();
        if (LegacyPem.IsEncrypted(pem))
        {
            try { return LegacyPem.Decrypt(pem, pass); }
            catch (TvException e) when (e.Error == TvError.WrongPassphrase && pass.ToUpperInvariant() != pass)
            {
                return LegacyPem.Decrypt(pem, pass.ToUpperInvariant());
            }
        }
        return await SshKeygen.RemovePassphraseAsync(pem, pass, ct).ConfigureAwait(false);
    }
}

/// <summary>OpenSSL'in eski şifreli PEM biçimi (<c>Proc-Type: 4,ENCRYPTED</c> + <c>DEK-Info</c>).</summary>
public static partial class LegacyPem
{
    [GeneratedRegex(@"-----BEGIN ([A-Z ]+) PRIVATE KEY-----")]
    private static partial Regex BeginLine();

    [GeneratedRegex(@"DEK-Info:\s*([^,\s]+)\s*,\s*([0-9A-Fa-f]+)")]
    private static partial Regex DekInfo();

    public static bool IsEncrypted(string pem) => pem.Contains("Proc-Type: 4,ENCRYPTED", StringComparison.Ordinal);

    /// <summary>Çözer ve parolasız PEM döner. Hata: kurulamadı (biçim) ya da parola yanlış.</summary>
    public static string Decrypt(string pem, string password)
    {
        var begin = BeginLine().Match(pem);
        var dek = DekInfo().Match(pem);
        if (!begin.Success || !dek.Success) throw new TvException(TvError.InstallFailed, "PEM başlığı okunamadı");
        var kind = begin.Groups[1].Value;
        var bodyStart = pem.IndexOf('\n', dek.Index);
        var end = pem.IndexOf("-----END", dek.Index, StringComparison.Ordinal);
        if (end < 0 || bodyStart < 0 || bodyStart > end) throw new TvException(TvError.InstallFailed, "PEM sonu bulunamadı");
        byte[] body;
        try { body = Convert.FromBase64String(new string(pem[bodyStart..end].Where(c => !char.IsWhiteSpace(c)).ToArray())); }
        catch (FormatException) { throw new TvException(TvError.InstallFailed, "PEM gövdesi okunamadı"); }

        var cipher = dek.Groups[1].Value.ToUpperInvariant();
        var keyLength = cipher switch
        {
            "DES-EDE3-CBC" => 24,
            "AES-128-CBC" => 16,
            "AES-192-CBC" => 24,
            "AES-256-CBC" => 32,
            _ => throw new TvException(TvError.InstallFailed, $"Desteklenmeyen şifre: {dek.Groups[1].Value}"),
        };
        var iv = Convert.FromHexString(dek.Groups[2].Value);
        if (iv.Length < 8) throw new TvException(TvError.InstallFailed, "PEM başlığı okunamadı");
        var key = DeriveKey(Encoding.UTF8.GetBytes(password), iv.AsSpan(0, 8), keyLength);

        byte[] der;
        try
        {
            using SymmetricAlgorithm alg = cipher == "DES-EDE3-CBC" ? TripleDES.Create() : Aes.Create();
            alg.Key = key;
            der = alg.DecryptCbc(body, iv, PaddingMode.PKCS7);
        }
        catch (CryptographicException) { throw new TvException(TvError.WrongPassphrase); }
        if (!LooksLikeDer(der)) throw new TvException(TvError.WrongPassphrase);

        var sb = new StringBuilder($"-----BEGIN {kind} PRIVATE KEY-----\n");
        var b64 = Convert.ToBase64String(der);
        for (var i = 0; i < b64.Length; i += 64) sb.Append(b64.AsSpan(i, Math.Min(64, b64.Length - i))).Append('\n');
        return sb.Append($"-----END {kind} PRIVATE KEY-----\n").ToString();
    }

    /// <summary>OpenSSL'in eski anahtar türetmesi: Dᵢ = MD5(Dᵢ₋₁ ‖ parola ‖ tuz), tek tur.</summary>
    public static byte[] DeriveKey(byte[] password, ReadOnlySpan<byte> salt, int length)
    {
        var output = new byte[length];
        var filled = 0;
        byte[] digest = [];
        while (filled < length)
        {
            digest = MD5.HashData([.. digest, .. password, .. salt]);
            var take = Math.Min(digest.Length, length - filled);
            digest.AsSpan(0, take).CopyTo(output.AsSpan(filled));
            filled += take;
        }
        return output;
    }

    /// <summary>DER SEQUENCE gibi mi: 0x30, kısa ya da 1–3 baytlık uzun boy, toplam boya tam eşit.</summary>
    public static bool LooksLikeDer(byte[] d)
    {
        if (d.Length < 4 || d[0] != 0x30) return false;
        int header, length;
        if (d[1] < 0x80)
        {
            header = 2;
            length = d[1];
        }
        else
        {
            var n = d[1] & 0x7F;
            if (n is < 1 or > 3 || d.Length < 2 + n) return false;
            length = 0;
            for (var i = 0; i < n; i++) length = (length << 8) | d[2 + i];
            header = 2 + n;
        }
        return header + length == d.Length;
    }
}

/// <summary>Yedek yol: sistemin <c>ssh-keygen</c> aracıyla parolayı kaldırmak.</summary>
public static class SshKeygen
{
    /// <summary>Araç yeri: Windows'ta <c>Sistem\OpenSSH\ssh-keygen.exe</c>, başka yerde <c>/usr/bin/ssh-keygen</c>.</summary>
    public static string ToolPath => OperatingSystem.IsWindows()
        ? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "OpenSSH", "ssh-keygen.exe")
        : "/usr/bin/ssh-keygen";

    public static async Task<string> RemovePassphraseAsync(string pem, string passphrase, CancellationToken ct = default,
        string? tool = null)
    {
        var file = Path.Combine(Path.GetTempPath(), "nino-" + Guid.NewGuid().ToString("N"));
        try
        {
            await using (var fs = PrivateFile.Create(file))
                await fs.WriteAsync(Encoding.UTF8.GetBytes(pem), ct).ConfigureAwait(false);

            var psi = new ProcessStartInfo(tool ?? ToolPath)
            {
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
            };
            foreach (var a in new[] { "-q", "-p", "-P", passphrase, "-N", "", "-f", file }) psi.ArgumentList.Add(a);
            Process process;
            try { process = Process.Start(psi) ?? throw new InvalidOperationException(); }
            catch (Exception e) when (e is not OperationCanceledException) { throw new TvException(TvError.ToolMissing, e.Message, e); }
            using (process)
            {
                var stdout = process.StandardOutput.ReadToEndAsync(ct);
                var stderr = process.StandardError.ReadToEndAsync(ct);
                await process.WaitForExitAsync(ct).ConfigureAwait(false);
                var output = (await stdout.ConfigureAwait(false)) + (await stderr.ConfigureAwait(false));
                if (process.ExitCode != 0)
                {
                    var lower = output.ToLowerInvariant();
                    if (lower.Contains("passphrase") && (lower.Contains("incorrect") || lower.Contains("bad")))
                        throw new TvException(TvError.WrongPassphrase);
                    throw new TvException(TvError.InstallFailed, output.Trim());
                }
            }
            return await File.ReadAllTextAsync(file, ct).ConfigureAwait(false);
        }
        finally
        {
            try { File.Delete(file); } catch (Exception) { }
        }
    }
}

/// <summary>Yalnız sahibinin okuyabildiği yeni geçici dosya (Windows'ta düz; dosya varsa hata).</summary>
static class PrivateFile
{
    public static FileStream Create(string path)
    {
        var mode = new FileStreamOptions { Mode = FileMode.CreateNew, Access = FileAccess.Write, Share = FileShare.None };
        if (!OperatingSystem.IsWindows()) mode.UnixCreateMode = UnixFileMode.UserRead | UnixFileMode.UserWrite;
        return new FileStream(path, mode);
    }
}
