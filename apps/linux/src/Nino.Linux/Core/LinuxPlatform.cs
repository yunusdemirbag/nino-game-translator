// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Runtime.InteropServices;
using Nino.Core.Data;
using Nino.Core.Library;
using Nino.Core.Settings;
using Nino.Core.Telemetry;
using Nino.Linux.Hosting;
using Nino.RemotePlay.Bridge;
using Nino.Core.Logging;
using RemotePlayFileLog = Nino.RemotePlay.RemotePlayLog;

namespace Nino.Linux.Core;

/// <summary>
/// Sunucunun Linux'a özgü parçaları tek yerde: veri klasörü, gizli kasa (secure.json, 0600), ayar dosyası,
/// günlükler, Tesseract okuyucusu, ölçüm ve çekirdeğin platform hizmetleri (<see cref="LinuxShellServices"/>).
/// Ortak denetleyici bunlarla kurulur.
/// </summary>
public sealed class LinuxPlatform : IDisposable
{
    public const string PlatformName = "linux";

    private LinuxPlatform(DataFolder data, Journal journal, string version, HttpClient http)
    {
        Data = data;
        Journal = journal;
        Version = version;
        Http = http;
        data.Ensure();
        Secrets = FileSecretStore.ForLinux(data.Root);
        Settings = new JsonFileSettingsStore(data.SettingsFile, () => Hosting.Language.Code,
            (what, error) => journal.Write("ayar", $"{what}: {error.Message}"));
        RemotePlayLog = new RemotePlayFileLog(data.RemotePlayLog);
        RemotePlayLog.LineAdded += ForwardRemotePlayLine;
        Readers = new ReaderCache(new CoreOcrRules(), journal);
        SubtitleLog = new SubtitleLog(data.File(LogNames.Subtitle)) { Enabled = true };
        ErrorLog = new ErrorLog(data.File(LogNames.Error));
        InstallId = InstallIdFile.ReadOrCreateGuid(Path.Combine(data.Root, "pool-translations", "install"));
        Services = new LinuxShellServices(this);
    }

    public static LinuxPlatform Open(DataFolder data, Journal journal, string version) =>
        new(data, journal, version, new HttpClient { Timeout = TimeSpan.FromMinutes(10) });

    public DataFolder Data { get; }
    public Journal Journal { get; }
    public string Version { get; }
    public HttpClient Http { get; }
    public ISecretStore Secrets { get; }
    public ISettingsStore Settings { get; }
    public RemotePlayFileLog RemotePlayLog { get; }
    public ReaderCache Readers { get; }
    public SubtitleLog SubtitleLog { get; }
    public ErrorLog ErrorLog { get; }
    public LinuxShellServices Services { get; }
    public string InstallId { get; }

    /// <summary>PS5 bağlantı kütüphanesi (nino_native.so) bulunabiliyor mu.</summary>
    public static bool NativeAvailable => NativeBridge.Shared.IsAvailable();

    /// <summary>Bilgi düzeyinde olmayan PS5 satırları panel günlüğüne de düşer.</summary>
    private void ForwardRemotePlayLine(string line)
    {
        if (!line.StartsWith("[chiaki info]", StringComparison.Ordinal)) Journal.Write("ps5", line);
    }

    /// <summary>
    /// Ölçümün kurulumu: istemciyi ortak denetleyici açar ve yönetir (açılış, çökme, oturum, gönderim). Linux yalnız
    /// platform adını, dağıtım bilgisini, kurulum kimliğini ve gönderim adresini verir; ayarlarda kapatma yoktur.
    /// </summary>
    public Nino.Shell.TelemetrySetup TelemetrySetup() => new()
    {
        DataFolder = Data.Root,
        Platform = PlatformName,
        Os = OsName(),
        Device = DeviceName(),
        Channel = TelemetryContext.ChannelFor(Version),
        Install = InstallId,
        Sender = new HttpTelemetrySender(Http, TelemetryEndpoint),
    };

    /// <summary>Ölçüm adresi: havuz sunucusu (<c>NINO_POOL_URL</c> ile değiştirilebilir) + /v1/events.</summary>
    public Uri TelemetryEndpoint => HttpTelemetrySender.EndpointFor(PoolEndpoint.Resolve(Data.Root));

    /// <summary>
    /// Eski Linux sunucusu her çevrimiçi anahtarı <c>deepLKey</c>'de tutardı (Claude anahtarı da). Yeni düzende
    /// Claude anahtarı kendi yerinde durur ve seçili motor ayarda yazılıdır; açılışta bir kez taşınır.
    /// </summary>
    public void MoveLegacyOnlineKey()
    {
        if (Secrets.Get<string>(SecretKeys.DeepLKey) is not { } key || !OnlineKeys.IsClaude(key)) return;
        Secrets.Set(SecretKeys.ClaudeKey, key.Trim());
        Secrets.Remove(SecretKeys.DeepLKey);
        var settings = Settings.Load();
        settings.OnlineEngine = OnlineEngine.Claude;
        Settings.Save(settings);
        Journal.Write("ayar", "Claude anahtarı yeni yerine taşındı.");
    }

    /// <summary>Ölçüm bağlamı: platform, sürüm, dağıtım adı, cihaz türü.</summary>
    public static TelemetryContext Context(string version) => new(
        PlatformName, version, OsName(), DeviceName(), Nino.Core.Telemetry.TvBrand.None, TelemetryContext.ChannelFor(version));

    /// <summary><c>/etc/os-release</c>'teki ad + çekirdek sürümü ("Ubuntu 24.04 · 6.8").</summary>
    public static string OsName(string osRelease = "/etc/os-release")
    {
        string? name = null;
        try
        {
            foreach (var line in File.ReadLines(osRelease))
            {
                if (line.StartsWith("PRETTY_NAME=", StringComparison.Ordinal)) name = line["PRETTY_NAME=".Length..].Trim('"');
            }
        }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
        var kernel = Environment.OSVersion.Version;
        return $"{name ?? RuntimeInformation.OSDescription} · {kernel.Major}.{kernel.Minor}";
    }

    /// <summary>Docker içinde mi, değil mi; ayrıca işlemci mimarisi.</summary>
    public static string DeviceName() =>
        $"{(File.Exists("/.dockerenv") ? "Docker" : "Linux")} {RuntimeInformation.OSArchitecture.ToString().ToLowerInvariant()}";

    public void Dispose()
    {
        RemotePlayLog.LineAdded -= ForwardRemotePlayLine;
        RemotePlayLog.Dispose();
        Services.Dispose();
        SubtitleLog.Dispose();
        Readers.Dispose();
        Http.Dispose();
    }
}
