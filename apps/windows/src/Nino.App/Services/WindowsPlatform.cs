// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.IO;
using System.Globalization;
using System.Net.Http;
using System.Reflection;
using System.Windows.Threading;
using Microsoft.Win32;
using Nino.Core.Data;
using Nino.Core.Library;
using Nino.Core.Link;
using Nino.Core.Logging;
using Nino.Core.Settings;
using Nino.RemotePlay;
using Nino.Shell.Platform;
using RpLog = Nino.RemotePlay.RemotePlayLog;
using Nino.Translation.Local;

namespace Nino.App.Services;

/// <summary>Denetleyicinin Windows parçaları.</summary>
/// <param name="Services">Ağ, cihaz ve dosya işleri.</param>
/// <param name="Secrets">DPAPI'li <c>secure.dat</c>.</param>
/// <param name="Settings"><c>settings.json</c>.</param>
/// <param name="Sleep">Uyku engeli.</param>
public sealed record WindowsPlatformParts(IShellServices Services, ISecretStore Secrets, ISettingsStore Settings, ISleepGuard Sleep)
{
    /// <summary>Saat ve zamanlayıcılar (arayüz iş parçacığında tikler).</summary>
    public IShellTimers? Timers { get; init; }

    /// <summary>Tarayıcıda açma (AllowSetForegroundWindow + kabuk).</summary>
    public IBrowser? Browser { get; init; }

    /// <summary>Genel kısayollar (ana pencere hazır olunca <see cref="GlobalHotkeys.Attach"/>).</summary>
    public GlobalHotkeys? Hotkeys { get; init; }

    /// <summary>Uykudan uyanma bildirimi (ana pencere <c>controller.SystemResumed()</c>'a bağlar).</summary>
    public PowerResumeWatch? Resume { get; init; }
}

/// <summary>Kurulumun isteğe bağlı parçaları (açılışın açtığı günlükler, sürüm).</summary>
public sealed record WindowsPlatformOptions
{
    /// <summary>Nino'nun sürümü; yoksa derlemenin bilgi sürümünden.</summary>
    public string? AppVersion { get; init; }

    /// <summary><c>remoteplay.log</c> (yerel köprü satırları dahil, tek yazan).</summary>
    public RpLog? RemotePlayLog { get; init; }

    /// <summary><c>hata.log</c>.</summary>
    public ErrorLog? Errors { get; init; }

    /// <summary><c>altyazi.log</c> (kaynak günlük satırları).</summary>
    public SubtitleLog? Subtitles { get; init; }

    /// <summary><c>tvinstall.log</c>.</summary>
    public TvInstallLog? TvInstall { get; init; }

    /// <summary>Arayüz iş parçacığı; yoksa açılış iş parçacığınınki.</summary>
    public Dispatcher? Dispatcher { get; init; }

    /// <summary>Paylaşılan HTTP istemcisi; yoksa kurulur.</summary>
    public HttpClient? Http { get; init; }
}

/// <summary>Bütün Windows hizmetlerini bağlayan kurulum.</summary>
public static class WindowsPlatform
{
    /// <summary>Kurar. Veri klasörü <c>NinoDataFolder</c> kararıdır; <paramref name="post"/> arayüze aktarır.</summary>
    public static WindowsPlatformParts Create(string dataFolder, Action<Action> post) => Create(dataFolder, post, null);

    /// <summary>Kurar (açılışın günlükleriyle).</summary>
    public static WindowsPlatformParts Create(string dataFolder, Action<Action> post, WindowsPlatformOptions? options)
    {
        options ??= new WindowsPlatformOptions();
        var dispatcher = options.Dispatcher ?? Dispatcher.CurrentDispatcher;
        var version = options.AppVersion ?? CurrentVersion();
        var errors = options.Errors ?? new ErrorLog(Path.Combine(dataFolder, LogNames.Error));
        var tvInstall = options.TvInstall ?? new TvInstallLog(Path.Combine(dataFolder, LogNames.TvInstall));
        var http = options.Http ?? new HttpClient { Timeout = TimeSpan.FromSeconds(100) };

        var secrets = FileSecretStore.ForWindows(dataFolder, new DpapiProtector());
        var settings = new JsonFileSettingsStore(Path.Combine(dataFolder, JsonFileSettingsStore.FileName),
            () => CultureInfo.CurrentUICulture.Name, (message, e) => errors.Write(message, e));
        var sleep = new WindowsSleepGuard(dispatcher);
        var browser = new BrowserLauncher(errors, tvInstall);

        var poolEndpoint = PoolEndpoint.Resolve(dataFolder);
        var core = new CoreShellServicesOptions
        {
            DataFolder = dataFolder,
            Secrets = secrets,
            Http = http,
            AppVersion = version,
            TvAppFolder = TvAppFolder(),
            KeepLegacyTurkish = false,
            RemotePlayLog = options.RemotePlayLog ?? new RpLog(Path.Combine(dataFolder, RpLog.FileName)),
            Identity = new SenderIdentity { Client = "nino-windows/" + version },
            PoolEndpoint = poolEndpoint,
            // Paketler havuz sunucusundadır (v1/packs?lang=); ortam değişkeni ya da derleme meta verisi başka adres verebilir.
            PackServer = PackUpdater.ResolveAddress(Environment.GetEnvironmentVariable("NINO_PACKS_URL"), BuildMetadata("NinoPacksUrl"))
                ?? PackUpdater.ResolveAddress(null, poolEndpoint.ToString()),
            OpenBrowser = browser.Open,
            CudaDriverPresent = NvidiaDriverPresent,
            // Arapça gibi ONNX'li diller ayrı süreçte: ONNX Runtime'daki yerel bir hata Nino'yu kapatmasın.
            OnnxWorker = Environment.ProcessPath is { } exe
                ? (folder, token) => OnnxWorkerRuntime.Start(exe, folder, token)
                : null,
            ErrorLog = (m, e) => { try { errors.Write(m, e); } catch (Exception) { } },
        };
        Action<string> sourceLog = line =>
        {
            try { options.Subtitles?.Write(line); } catch (Exception) { }
        };
        var services = new WindowsShellServices(core, new WindowsServiceParts
        {
            Dispatcher = dispatcher,
            Sleep = sleep,
            SourceLog = sourceLog,
            ErrorLog = (m, e) => { try { errors.Write(m, e); } catch (Exception) { } },
            Updater = new VelopackUpdater(http, version),
            Firewall = new WindowsFirewall(log: m => { try { errors.Write(m); } catch (Exception) { } }),
        });
        return new WindowsPlatformParts(services, secrets, settings, sleep)
        {
            Timers = new DispatcherTimers(dispatcher),
            Browser = browser,
            Hotkeys = new GlobalHotkeys(dispatcher, line => { try { errors.Write(line); } catch (Exception) { } }),
            Resume = new PowerResumeWatch(post),
        };
    }

    /// <summary>Nino'nun sürümü: bilgi sürümünün <c>+</c> öncesi; okunamazsa 0.0.0.</summary>
    public static string CurrentVersion() =>
        AppVersion.FromInformational(Assembly.GetEntryAssembly()?
            .GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion);

    static string? BuildMetadata(string key) =>
        Assembly.GetEntryAssembly()?.GetCustomAttributes<AssemblyMetadataAttribute>()
            .FirstOrDefault(a => a.Key == key)?.Value;

    /// <summary>NVIDIA sürücüsü kurulu mu (<c>%WINDIR%\System32\nvcuda.dll</c>; çeviri tarifi §8.5).</summary>
    static bool NvidiaDriverPresent()
    {
        try { return File.Exists(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "nvcuda.dll")); }
        catch (Exception) { return false; }
    }

    static string? TvAppFolder()
    {
        var tvApps = Path.Combine(AppContext.BaseDirectory, "tv-app");
        return Directory.Exists(tvApps) ? tvApps : null;
    }
}

/// <summary>Uykudan uyanma: sistem güç olayı "sürdür" gelince arayüze aktarılıp bildirilir.</summary>
public sealed class PowerResumeWatch : IDisposable
{
    readonly Action<Action> _post;
    bool _listening;

    /// <summary>Bilgisayar uykudan uyandı (arayüz iş parçacığında).</summary>
    public event Action? Resumed;

    /// <summary>Bilgisayar uykuya geçiyor (arayüz iş parçacığında; teşhis bekçisi bu sırada susar).</summary>
    public event Action? Suspending;

    /// <param name="post">Arayüze aktarma.</param>
    public PowerResumeWatch(Action<Action> post)
    {
        _post = post;
        try
        {
            SystemEvents.PowerModeChanged += OnPower;
            _listening = true;
        }
        catch (Exception) { }
    }

    void OnPower(object? sender, PowerModeChangedEventArgs e)
    {
        if (e.Mode == PowerModes.Resume) _post(() => Resumed?.Invoke());
        else if (e.Mode == PowerModes.Suspend) _post(() => Suspending?.Invoke());
    }

    /// <inheritdoc />
    public void Dispose()
    {
        if (!_listening) return;
        _listening = false;
        try { SystemEvents.PowerModeChanged -= OnPower; } catch (Exception) { }
    }
}
