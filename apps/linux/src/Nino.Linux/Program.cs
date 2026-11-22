// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Reflection;
using Nino.Linux.Core;
using Nino.Linux.Diagnostics;
using Nino.Core.Text;
using Nino.Linux.Engine;
using Nino.Shell;
using Nino.Shell.Platform;
using Nino.Linux.Hosting;
using Nino.Linux.Panel;

namespace Nino.Linux;

/// <summary>
/// Nino'nun Linux sunucusu. Ekranı yoktur: kurulum ve denetim aynı ağdaki bir tarayıcıdan açılan panelle yapılır
/// (<c>http://sunucu:8788</c>).
/// </summary>
public static class Program
{
    /// <summary>Derlemenin sürümü; kaynak denetimi eki ("+abc123") atılır.</summary>
    public static string Version { get; } = ReadVersion();

    private static string ReadVersion()
    {
        var full = typeof(Program).Assembly.GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion ?? "0";
        var plus = full.IndexOf('+');
        return plus < 0 ? full : full[..plus];
    }

    public static async Task<int> Main(string[] args)
    {
        Language.Code = Language.FromEnvironment();
        var data = DataFolder.FromEnvironment();
        var journal = Journal.Shared;

        if (RawFrameCommand.Matches(args))
        {
            using var tools = LinuxPlatform.Open(data, journal, Version);
            return await RawFrameCommand.RunAsync(args, () => new LinuxTools(tools), Console.Out, Console.Error);
        }

        using var stopping = new CancellationTokenSource();
        using var platform = LinuxPlatform.Open(data, journal, Version);
        platform.MoveLegacyOnlineKey();

        using var serial = new SerialWorker();
        var ocrInstalled = Ocr.TesseractReader.IsAvailable(platform.Settings.Load().SourceLanguage);
        // Denetleyicinin bütün durumu seri sırada değişir; kendi olaylarını da oraya aktarır.
        var controller = await serial.Invoke(() => new NinoController(platform.Services, platform.Secrets, platform.Settings,
            new NoSleepGuard(), TextCatalog.For(Language.Code), serial.Enqueue,
            new ShellOptions
            {
                Timers = new SystemShellTimers(),
                Logs = new LinuxShellLogs(platform),
                Telemetry = platform.TelemetrySetup(),
            }));
        var backend = new CoreBackend(controller, platform, ocrInstalled);
        // Yakalanmayan hata süreci düşürmeden önce ölçüme çökme olarak yazılır (sonraki açılışta gönderilir).
        AppDomain.CurrentDomain.UnhandledException += (_, e) => controller.Telemetry?.RecordCrash(e.ExceptionObject as Exception);
        // remoteplay.log satırları masaüstündeki gibi sağlık kaydına ve altyazı günlüğündeki duraklama izleyicisine de gider.
        using var tap = RemotePlayLogTap.Attach(platform.RemotePlayLog, controller.Health, platform.SubtitleLog.Write);

        var port = PanelServer.PortFromEnvironment();
        var app = PanelServer.Build(backend, serial, journal, port, args);
        app.Lifetime.ApplicationStopping.Register(() =>
        {
            stopping.Cancel();
            serial.Invoke(backend.ShutdownAsync).Wait(TimeSpan.FromSeconds(6));
        });

        journal.Write("panel", $"Nino {Version} çalışıyor; panel adresi http://{LocalAddress() ?? "localhost"}:{port}");
        journal.Write("panel", $"Veri klasörü {data.Root} · PS5 kütüphanesi {(LinuxPlatform.NativeAvailable ? "var" : "YOK")} · " +
                               $"yazı tanıma {(ocrInstalled ? "var" : "YOK")} · LG paketi {platform.Services.LgPackageVersion ?? "YOK"}");

        // PS5 ve TV bağlantısı birkaç saniyede bir denetlenir (masaüstündeki zamanlayıcının karşılığı).
        _ = KeepCheckingAsync(serial, controller, stopping.Token);

        // Sunucu yeniden başlayınca çeviri kendiliğinden sürsün istenirse; dinlenmedeki PS5'i de uyandırdığı için kapalıdır.
        if (Environment.GetEnvironmentVariable("NINO_AUTOSTART") == "1")
            _ = serial.Invoke(async () =>
            {
                if (controller.IsSetupComplete && controller.CanStart) await controller.StartAsync();
            });

        await app.RunAsync();
        return 0;
    }

    public const int CheckSeconds = 5;

    private static async Task KeepCheckingAsync(SerialWorker serial, NinoController controller, CancellationToken stopping)
    {
        using var timer = new PeriodicTimer(TimeSpan.FromSeconds(CheckSeconds));
        var sleep = new SleepWatch();
        try
        {
            while (await timer.WaitForNextTickAsync(stopping))
            {
                // Uyku önceden bildirilemez; uyanınca ikisi art arda söylenir ki teşhis aradaki kopmayı arıza saymasın
                // ve PS5/TV bağlantısı hemen yenilensin.
                if (sleep.Check() is { } slept)
                {
                    Journal.Shared.Write("panel", $"sunucu yaklaşık {slept.TotalMinutes:0} dakika uykudaydı; bağlantılar yenileniyor");
                    await serial.Invoke(() =>
                    {
                        controller.SystemSuspending();
                        controller.SystemResumed();
                    });
                }
                try { await serial.Invoke(controller.CheckConnectionsAsync); }
                catch (Exception error) { Journal.Shared.Write("panel", $"bağlantı denetimi: {error.Message}"); }
            }
        }
        catch (OperationCanceledException) { }
    }

    /// <summary>Ev ağındaki IPv4 adresi (geri döngü ve kapalı arabirimler hariç).</summary>
    public static string? LocalAddress()
    {
        try
        {
            return NetworkInterface.GetAllNetworkInterfaces()
                .Where(nic => nic.OperationalStatus == OperationalStatus.Up && nic.NetworkInterfaceType != NetworkInterfaceType.Loopback)
                .SelectMany(nic => nic.GetIPProperties().UnicastAddresses)
                .Select(entry => entry.Address)
                .FirstOrDefault(address => address.AddressFamily == AddressFamily.InterNetwork && !IPAddress.IsLoopback(address))
                ?.ToString();
        }
        catch (NetworkInformationException)
        {
            return null;
        }
    }
}

