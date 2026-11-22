// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.IO.Compression;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Text.Encodings.Web;
using System.Text.Json;
using Nino.TvInstall;
using Nino.TvInstall.Android;
using Nino.TvInstall.Samsung;
using TizenSdb.SigningManager;

namespace Nino.TvHelper;

/// <summary>
/// Mac uygulamasının Samsung ve Android TV kurulumu için çağırdığı komut satırı yardımcısı (<c>nino-tv-helper</c>).
/// Her olay standart çıktıya tek satır JSON olarak yazılır.
/// </summary>
public static class Program
{
    const string Usage =
        "kullanım: nino-tv-helper android-scan | android-install --host IP --package APK --version V --key-dir DİZİN | " +
        "samsung-install --host IP --package WGT --version V --profiles DİZİN [--log DOSYA] | self-test";

    const int CancelledExit = 130;

    public static async Task<int> Main(string[] args)
    {
        var command = args.Length > 0 ? args[0] : "";
        if (command is not ("android-scan" or "android-install" or "samsung-install" or "self-test"))
        {
            Console.Error.WriteLine(Usage);
            return 2;
        }

        var options = ParseOptions(args.Skip(1).ToArray(), out var exitWithInput);
        using var cts = new CancellationTokenSource();
        Console.CancelKeyPress += (_, e) =>
        {
            e.Cancel = true;
            try { cts.Cancel(); } catch (ObjectDisposedException) { }
        };
        _ = Task.Run(() => DrainInput(exitWithInput, cts));

        var events = new EventWriter(Console.OpenStandardOutput());
        var log = new InstallLog(options.GetValueOrDefault("--log"));
        try
        {
            switch (command)
            {
                case "android-scan":
                    events.Found(await AndroidTvAppInstaller.ScanAsync(cts.Token));
                    break;
                case "android-install":
                    {
                        var installer = new AndroidTvAppInstaller();
                        var result = await installer.InstallAsync(Required(options, "--host"), Required(options, "--package"),
                            NullIfEmpty(Required(options, "--version")), Required(options, "--key-dir"), events.Approve, cts.Token);
                        events.Done(result.Version, result.Installed);
                        break;
                    }
                case "samsung-install":
                    {
                        var host = Required(options, "--host");
                        var package = Required(options, "--package");
                        var version = NullIfEmpty(Required(options, "--version"));
                        var profiles = Required(options, "--profiles");
                        using var http = new HttpClient { Timeout = TimeSpan.FromMinutes(1) };
                        var login = new SamsungLogin();
                        var result = await new SamsungInstaller(http).InstallAsync(new SamsungInstallRequest
                        {
                            Host = host,
                            PackagePath = package,
                            PackageVersion = version,
                            ProfilesRoot = profiles,
                            Log = log,
                            OnProgress = events.Progress,
                            SignInAsync = ct => login.RunAsync(url =>
                            {
                                log.Write("Oturum sayfasını açması için Mac uygulamasına iletildi: " + url);
                                events.Login(url);
                            }, ct),
                        }, cts.Token);
                        events.Done(result.Version, result.Installed);
                        break;
                    }
                default:
                    await SelfTestAsync();
                    events.Done("self-test", false);
                    break;
            }
            return 0;
        }
        catch (OperationCanceledException) when (cts.IsCancellationRequested)
        {
            return CancelledExit;
        }
        catch (TvInstallException e)
        {
            var message = command == "samsung-install"
                ? (e.Detail.Length > 0 ? e.Detail : e.Failure.ToString())
                : e.Message;
            events.Error(e.Failure.ToString(), message);
            return 1;
        }
        catch (Exception e)
        {
            log.Write($"Yardımcıda beklenmeyen hata: {e}");
            events.Error(nameof(TvInstallFailure.InstallFailed), $"{e.GetType().Name}: {e.Message}");
            return 1;
        }
    }

    static Dictionary<string, string> ParseOptions(string[] args, out bool exitWithInput)
    {
        exitWithInput = false;
        var result = new Dictionary<string, string>(StringComparer.Ordinal);
        for (var i = 0; i < args.Length; i++)
        {
            if (args[i] == "--exit-with-input") { exitWithInput = true; continue; }
            if (args[i].StartsWith("--", StringComparison.Ordinal) && i + 1 < args.Length)
            {
                result[args[i]] = args[i + 1];
                i++;
            }
        }
        return result;
    }

    static string Required(Dictionary<string, string> options, string name) =>
        options.TryGetValue(name, out var v) ? v : throw new ArgumentException($"{name} eksik");

    static string? NullIfEmpty(string value) => string.IsNullOrWhiteSpace(value) ? null : value.Trim();

    /// <summary>Standart giriş sonuna kadar okunup atılır; kapanınca yalnız bayrak varsa iptal edilir.</summary>
    static void DrainInput(bool exitWithInput, CancellationTokenSource cts)
    {
        try
        {
            using var input = Console.OpenStandardInput();
            var buffer = new byte[4096];
            while (input.Read(buffer, 0, buffer.Length) > 0) { }
        }
        catch (IOException) { }
        if (exitWithInput)
        {
            try { cts.Cancel(); } catch (ObjectDisposedException) { }
        }
    }

    static void Fail(string reason) => throw new InvalidOperationException(reason);

    /// <summary>Yayın derlemesinde imzanın AOT ile çalıştığını sınar.</summary>
    static async Task SelfTestAsync()
    {
        var dir = Path.Combine(Path.GetTempPath(), "nino-self-test-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        try
        {
            using var key = RSA.Create(2048);
            CertificateRequest selfRequest = new("CN=Nino self-test", key, HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1);
            using var signed = selfRequest.CreateSelfSigned(DateTimeOffset.UtcNow.AddDays(-1), DateTimeOffset.UtcNow.AddDays(1));
            using var publicOnly = X509CertificateLoader.LoadCertificate(signed.RawData);
            var p12 = SamsungCertificates.BuildPkcs12(publicOnly, key, "x");
            var folder = new SamsungCertificateFolder(Path.Combine(dir, "profile"));
            Directory.CreateDirectory(folder.Path);
            await File.WriteAllBytesAsync(folder.AuthorPath, p12);
            await File.WriteAllBytesAsync(folder.DistributorPath, p12);
            await File.WriteAllTextAsync(Path.Combine(folder.Path, SamsungCertificateFolder.PasswordFile), "x");
            if (!folder.IsValid(DateTimeOffset.UtcNow.AddHours(-23)))
                Fail("kayıtlı sertifika okunamadı");

            var wgt = Path.Combine(dir, "self-test.wgt");
            using (var zip = ZipFile.Open(wgt, ZipArchiveMode.Create))
            {
                var entry = zip.CreateEntry("config.xml");
                await using var w = new StreamWriter(entry.Open());
                await w.WriteAsync("<widget/>");
            }
            await TizenWgtSigner.ReSignWgtWithCertsInPlace(wgt, folder.AuthorPath, folder.DistributorPath, "x", null!);
            using (var zip = ZipFile.OpenRead(wgt))
            {
                var names = zip.Entries.Select(e => e.FullName).ToHashSet(StringComparer.Ordinal);
                if (!names.Contains("author-signature.xml") || !names.Contains("signature1.xml"))
                    Fail("imza dosyaları oluşmadı");
            }
        }
        finally
        {
            try { Directory.Delete(dir, true); } catch (IOException) { } catch (UnauthorizedAccessException) { }
        }
    }
}

/// <summary>Olayları gerçek standart çıktıya satır satır JSON olarak yazar (kilitli, hemen boşaltılır).</summary>
sealed class EventWriter(Stream stdout)
{
    static readonly JsonWriterOptions Options = new() { Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping };
    readonly Lock _gate = new();

    void Emit(string name, Action<Utf8JsonWriter> fields)
    {
        using var buffer = new MemoryStream();
        using (var w = new Utf8JsonWriter(buffer, Options))
        {
            w.WriteStartObject();
            w.WriteString("event", name);
            fields(w);
            w.WriteEndObject();
        }
        buffer.WriteByte((byte)'\n');
        lock (_gate)
        {
            stdout.Write(buffer.GetBuffer(), 0, (int)buffer.Length);
            stdout.Flush();
        }
    }

    public void Progress(string step) => Emit("progress", w => w.WriteString("step", step));
    public void Login(string url) => Emit("login", w => w.WriteString("url", url));
    public void Approve() => Emit("approve", _ => { });

    public void Done(string version, bool installed) => Emit("done", w =>
    {
        w.WriteString("version", version);
        w.WriteBoolean("installed", installed);
    });

    public void Found(IEnumerable<string> hosts) => Emit("found", w =>
    {
        w.WriteStartArray("hosts");
        foreach (var h in hosts) w.WriteStringValue(h);
        w.WriteEndArray();
    });

    public void Error(string code, string message) => Emit("error", w =>
    {
        w.WriteString("code", code);
        w.WriteString("message", message);
    });
}
