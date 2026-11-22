// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Globalization;
using System.Net.Sockets;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using Renci.SshNet;
using Renci.SshNet.Common;

namespace Nino.Core.Tv;

/// <summary>Bir kabuk komutunun sonucu: çıkış kodu (yoksa −1) ve standart çıktı + hata çıktısı.</summary>
public sealed record ShellResult(int ExitCode, string Output);

/// <summary>LG TV'nin geliştirici kabuğu.</summary>
public interface ILgShell
{
    /// <summary>
    /// Komutu çalıştırır. <paramref name="inputFile"/> verildiyse komutun girişine akıtılıp giriş kapatılır.
    /// Bağlanamazsa <see cref="TvError.Unreachable"/>, anahtar kabul edilmezse <see cref="TvError.KeyRejected"/>.
    /// </summary>
    Task<ShellResult> RunAsync(string command, string? inputFile = null, TimeSpan? timeout = null, CancellationToken ct = default);
}

/// <summary>SSH.NET ile LG geliştirici kabuğu: <c>prisoner@adres:9922</c>, yalnız özel anahtar.</summary>
public sealed class SshLgShell(string host, string privateKeyPem, int port = LgDevMode.SshPort) : ILgShell
{
    /// <summary>SSH bağlanma süresi (iptal bundan 2 sn sonra).</summary>
    public TimeSpan ConnectTimeout { get; init; } = TimeSpan.FromSeconds(6.0);
    public TimeSpan DefaultCommandTimeout { get; init; } = TimeSpan.FromMinutes(2);

    public async Task<ShellResult> RunAsync(string command, string? inputFile = null, TimeSpan? timeout = null,
        CancellationToken ct = default)
    {
        var keyFile = Path.Combine(Path.GetTempPath(), "nino-" + Guid.NewGuid().ToString("N"));
        try
        {
            await using (var fs = PrivateFile.Create(keyFile))
                await fs.WriteAsync(Encoding.UTF8.GetBytes(privateKeyPem), ct).ConfigureAwait(false);

            PrivateKeyFile key;
            try { key = new PrivateKeyFile(keyFile); }
            catch (Exception e) { throw new TvException(TvError.KeyRejected, "anahtar okunamadı: " + e.Message, e); }

            using (key)
            {
                var info = new ConnectionInfo(host, port, "prisoner", new PrivateKeyAuthenticationMethod("prisoner", key))
                {
                    Timeout = ConnectTimeout,
                };
                using var client = new SshClient(info);
                using (var connect = CancellationTokenSource.CreateLinkedTokenSource(ct))
                {
                    connect.CancelAfter(ConnectTimeout + TimeSpan.FromSeconds(2));
                    try { await client.ConnectAsync(connect.Token).ConfigureAwait(false); }
                    catch (SshAuthenticationException e) { throw new TvException(TvError.KeyRejected, e.Message, e); }
                    catch (Exception e) when (e is SocketException or SshException or TimeoutException
                        or OperationCanceledException or IOException)
                    {
                        ct.ThrowIfCancellationRequested();
                        throw new TvException(TvError.Unreachable, e.Message, e);
                    }
                }

                try
                {
                    return await Task.Run(() => Execute(client, command, inputFile, timeout ?? DefaultCommandTimeout), ct)
                        .ConfigureAwait(false);
                }
                catch (Exception e) when (e is SocketException or SshException or IOException)
                {
                    throw new TvException(TvError.Unreachable, e.Message, e);
                }
                finally
                {
                    try { client.Disconnect(); } catch (Exception) { }
                }
            }
        }
        finally
        {
            try { File.Delete(keyFile); } catch (Exception) { }
        }
    }

    static ShellResult Execute(SshClient client, string command, string? inputFile, TimeSpan timeout)
    {
        using var cmd = client.CreateCommand(command);
        cmd.CommandTimeout = timeout;
        var started = cmd.BeginExecute();
        if (inputFile is not null)
        {
            using var input = cmd.CreateInputStream();
            using var file = File.OpenRead(inputFile);
            file.CopyTo(input);
        }
        cmd.EndExecute(started);
        return new ShellResult(cmd.ExitStatus ?? -1, (cmd.Result ?? "") + (cmd.Error ?? ""));
    }
}

/// <summary>LG kurulum sonucunun TV tarafındaki görünüşü.</summary>
public enum LgInstallOutcome { Unknown, Installed, Failed }

/// <summary>LG geliştirici kabuğu üzerinden TV'deki Nino'yu kurma ve sürüm okuma.</summary>
public sealed partial class LgInstaller(ILgShell shell)
{
    public const string RemoteFolder = "/media/developer/temp";
    const string AppInfo = "/media/developer/apps/usr/palm/applications/" + TvRecord.LgAppId + "/appinfo.json";

    [GeneratedRegex("\"version\"\\s*:\\s*\"([^\"]*)\"")]
    private static partial Regex VersionField();

    [GeneratedRegex(@"(not enough|insufficient) (free )?(space|storage)|lack of (space|storage)|(no|out of) space|(disk|storage) (is )?full|ENOSPC", RegexOptions.IgnoreCase)]
    private static partial Regex SpaceProblem();

    /// <summary>TV'nin "kurulum bitti" yanıtını bekleme süresi (saniye, tavan; en az 1).</summary>
    public TimeSpan InstallWait { get; init; } = TimeSpan.FromSeconds(180);

    /// <summary>Doğrulama sınırı: TV "kuruldu" dediyse / belirsizse.</summary>
    public TimeSpan VerifyAfterInstalled { get; init; } = TimeSpan.FromSeconds(30);
    public TimeSpan VerifyAfterUnknown { get; init; } = TimeSpan.FromSeconds(60);
    public TimeSpan VerifyEvery { get; init; } = TimeSpan.FromSeconds(2);

    /// <summary>TV'deki sürüm; kurulu değilse <c>null</c>. Kabuk hatası çağırana gider.</summary>
    public async Task<string?> InstalledVersionAsync(CancellationToken ct = default)
    {
        var r = await shell.RunAsync($"cat {AppInfo}", ct: ct).ConfigureAwait(false);
        return ParseVersion(r.Output);
    }

    public static string? ParseVersion(string appInfo)
    {
        var m = VersionField().Match(appInfo);
        return m.Success ? m.Groups[1].Value : null;
    }

    /// <summary>Paketi TV'ye gönderip kurar ve TV'de beklenen sürümü görene kadar doğrular.</summary>
    public async Task InstallAsync(string packagePath, string expectedVersion, CancellationToken ct = default)
    {
        var remote = $"{RemoteFolder}/{Path.GetFileName(packagePath)}";
        var localSize = new FileInfo(packagePath).Length;

        var upload = await shell.RunAsync(
            $"mkdir -p {RemoteFolder} && rm -f {RemoteFolder}/{TvRecord.LgAppId}_*.ipk {RemoteFolder}/nino.ipk && cat > '{remote}'",
            packagePath, ct: ct).ConfigureAwait(false);
        if (upload.ExitCode != 0)
            throw Failure($"yükleme çıkış kodu {upload.ExitCode}: {Short(upload.Output)}", upload.Output);

        var size = await shell.RunAsync($"wc -c < '{remote}'", ct: ct).ConfigureAwait(false);
        if (long.TryParse(size.Output.Trim(), NumberStyles.Integer, CultureInfo.InvariantCulture, out var remoteSize)
            && remoteSize != localSize)
            throw new TvException(TvError.InstallFailed, $"TV'deki paket boyu tutmuyor (yarım ya da bozuk aktarım): {remoteSize}/{localSize} bayt");

        var wait = Math.Max(1, (int)Math.Ceiling(InstallWait.TotalSeconds));
        var install = await shell.RunAsync(InstallCommand(remote, wait), timeout: TimeSpan.FromMinutes(5), ct: ct)
            .ConfigureAwait(false);
        var (outcome, reason) = ParseInstallReply(install.Output);
        if (outcome == LgInstallOutcome.Failed)
        {
            await RemoveAsync(remote, ct).ConfigureAwait(false);
            var message = string.IsNullOrEmpty(reason) ? $"kurulum başarısız: {Short(install.Output)}" : reason;
            throw Failure(message, install.Output);
        }

        var limit = outcome == LgInstallOutcome.Installed ? VerifyAfterInstalled : VerifyAfterUnknown;
        var deadline = DateTime.UtcNow + limit;
        while (true)
        {
            var version = await InstalledVersionAsync(ct).ConfigureAwait(false);
            if (version == expectedVersion)
            {
                await RemoveAsync(remote, ct).ConfigureAwait(false);
                return;
            }
            if (DateTime.UtcNow >= deadline) break;
            await Task.Delay(VerifyEvery, ct).ConfigureAwait(false);
        }
        if (outcome == LgInstallOutcome.Installed) await RemoveAsync(remote, ct).ConfigureAwait(false);
        throw new TvException(TvError.InstallFailed,
            $"kurulumdan sonra TV {expectedVersion} sürümünü göstermiyor; kurucunun çıkışı ({install.ExitCode}): {Short(install.Output)}");
    }

    async Task RemoveAsync(string remote, CancellationToken ct)
    {
        try { await shell.RunAsync($"rm -f '{remote}'", ct: ct).ConfigureAwait(false); }
        catch (Exception) when (!ct.IsCancellationRequested) { }
    }

    static TvException Failure(string message, string evidence) =>
        new(SpaceProblem().IsMatch(message) || SpaceProblem().IsMatch(evidence) ? TvError.NotEnoughSpace : TvError.InstallFailed,
            message);

    /// <summary>Yer sorunu deseni.</summary>
    public static bool IsSpaceProblem(string text) => SpaceProblem().IsMatch(text);

    /// <summary>Kurulum komutu: abonelik giriş açık kaldıkça sürer; sonuç günlükten okunur.</summary>
    public static string InstallCommand(string remote, int waitSeconds)
    {
        const string log = RemoteFolder + "/nino-install.log";
        string[] parts =
        [
            $"rm -f {log}",
            $"sleep {waitSeconds + 30} </dev/null 2>/dev/null | /usr/bin/luna-send-pub -i 'luna://com.webos.appInstallService/dev/install' "
                + $"'{{\"id\":\"com.ares.defaultName\",\"ipkUrl\":\"{remote}\",\"subscribe\":true}}' >{log} 2>&1 & L=$!",
            "i=0",
            $"while [ $i -lt {waitSeconds} ]; do grep -q -i -e '\"state\" *: *\"installed' -e 'failed' -e '\"returnValue\" *: *false' "
                + $"-e '\"state\" *: *\"success' {log} 2>/dev/null && break; kill -0 $L 2>/dev/null || break; sleep 1; i=$((i+1)); done",
            $"cat {log}",
            "kill $L 2>/dev/null",
            $"rm -f {log}",
        ];
        return string.Join("; ", parts);
    }

    /// <summary>luna-send çıktısını satır satır okur (yarım JSON sonraki satırla birleşir).</summary>
    public static (LgInstallOutcome Outcome, string Reason) ParseInstallReply(string output)
    {
        var pending = new StringBuilder();
        foreach (var raw in output.Split('\n'))
        {
            var line = raw.Trim();
            if (line.Length == 0) continue;
            pending.Append(line);
            var text = pending.ToString();
            if (!text.StartsWith('{'))
            {
                pending.Clear();
                continue;
            }
            JsonElement root;
            try
            {
                using var doc = JsonDocument.Parse(text);
                root = doc.RootElement.Clone();
            }
            catch (JsonException) { continue; }
            pending.Clear();
            if (root.ValueKind != JsonValueKind.Object) continue;

            if (root.TryGetProperty("returnValue", out var rv) && rv.ValueKind == JsonValueKind.False)
            {
                var reason = Text(root, "errorText") ?? Text(root, "errorMessage") ?? "";
                if (Text(root, "errorCode") is { } code) reason += $" (errorCode {code})";
                return (LgInstallOutcome.Failed, reason.Trim());
            }
            if (root.TryGetProperty("details", out var details) && details.ValueKind == JsonValueKind.Object)
            {
                var phase = Text(details, "state") ?? "";
                if (phase.Contains("failed", StringComparison.OrdinalIgnoreCase))
                {
                    var reason = Text(details, "reason") ?? Text(details, "errorText") ?? phase;
                    if ((Text(details, "errorCode") ?? Text(root, "errorCode")) is { } code) reason += $" (errorCode {code})";
                    return (LgInstallOutcome.Failed, reason);
                }
                if (phase.Contains("installed", StringComparison.OrdinalIgnoreCase)
                    || phase.StartsWith("success", StringComparison.OrdinalIgnoreCase))
                    return (LgInstallOutcome.Installed, "");
            }
        }
        return (LgInstallOutcome.Unknown, "");
    }

    /// <summary>Dizge ya da sayı alanı metin olarak.</summary>
    static string? Text(JsonElement e, string name)
    {
        if (!e.TryGetProperty(name, out var v)) return null;
        return v.ValueKind switch
        {
            JsonValueKind.String => v.GetString(),
            JsonValueKind.Number => v.GetRawText(),
            _ => null,
        };
    }

    /// <summary>En çok 500 karakter (kırpılmış; aşarsa sonuna "…").</summary>
    public static string Short(string text)
    {
        var t = text.Trim();
        return t.Length <= 500 ? t : t[..500] + "…";
    }
}

/// <summary>LG geliştirici modu süresini (1000 saat) uzatma.</summary>
public static partial class LgDevSession
{
    [GeneratedRegex(@"(\d{1,4}):\d{2}:\d{2}")]
    private static partial Regex Remaining();

    /// <summary>Son uzatmadan bu yana bundan fazla geçtiyse uzatılır.</summary>
    public static readonly TimeSpan RenewEvery = TimeSpan.FromHours(20);

    public static string ResetUrl(string token) =>
        "https://developer.lge.com/secure/ResetDevModeSession.dev?sessionToken=" + Uri.EscapeDataString(token);

    public static string CheckUrl(string token) =>
        "https://developer.lge.com/secure/CheckDevModeSession.dev?sessionToken=" + Uri.EscapeDataString(token);

    /// <summary>Kalan saat (<c>999:58:40</c> → 999); yoksa <c>null</c>.</summary>
    public static int? ParseRemainingHours(string text)
    {
        var m = Remaining().Match(text);
        return m.Success ? int.Parse(m.Groups[1].Value, CultureInfo.InvariantCulture) : null;
    }

    /// <summary>Uzatma zamanı geldi mi (kayıt yoksa evet).</summary>
    public static bool IsDue(DateTimeOffset? lastRenewed, DateTimeOffset now) =>
        lastRenewed is not { } last || now - last > RenewEvery;

    /// <summary>
    /// Oturum jetonunu TV'den okuyup LG'nin sunucusunda süreyi baştan başlatır; kalan saati döner. Her türlü hata
    /// sessizce <c>null</c> ("bilinmiyor"). Başarıda çağıran anı <c>devSessionRenewed.&lt;adres&gt;</c> olarak saklar.
    /// </summary>
    public static async Task<int?> RenewAsync(ILgShell shell, HttpClient http, CancellationToken ct = default)
    {
        try
        {
            var r = await shell.RunAsync("cat /var/luna/preferences/devmode_enabled", ct: ct).ConfigureAwait(false);
            var token = r.Output.Trim();
            if (token.Length == 0 || token.Any(char.IsWhiteSpace)) return null;
            using var cts = CancellationTokenSource.CreateLinkedTokenSource(ct);
            cts.CancelAfter(TimeSpan.FromSeconds(15));
            var reset = await http.GetStringAsync(ResetUrl(token), cts.Token).ConfigureAwait(false);
            if (!reset.Contains("success", StringComparison.OrdinalIgnoreCase)) return null;
            var check = await http.GetStringAsync(CheckUrl(token), cts.Token).ConfigureAwait(false);
            return ParseRemainingHours(check);
        }
        catch (Exception) when (!ct.IsCancellationRequested)
        {
            return null;
        }
    }
}
