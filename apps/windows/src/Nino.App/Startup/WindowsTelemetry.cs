// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Diagnostics;
using System.Windows;
using Nino.Core.Telemetry;
using Nino.Shell;
using Nino.Shell.Platform;

namespace Nino.App.Startup;

/// <summary>
/// Ölçümün Windows'a özgü kısmı (olcum.md): <c>ctx</c> değerleri (platform <c>windows</c>, <c>Windows 11 26100</c>
/// biçiminde sistem, BIOS'taki üretici modeli; bilgisayarın adı asla), kanal (Debug derlemesi <c>dev</c>), çökme anı ve
/// Windows oturumu kapanırken düzgün çıkış.
/// </summary>
public static class WindowsTelemetry
{
    /// <summary>Denetleyiciye verilecek kurulum.</summary>
    public static TelemetrySetup Setup(string dataFolder, IShellServices services)
    {
        var version = services.AppVersion;
        var v = Environment.OSVersion.Version;
        string device;
        try { device = services.DeviceAndSystem.Device; }
        catch (Exception) { device = Nino.Core.Data.DeviceInfo.FallbackModel; }
        return new TelemetrySetup
        {
            DataFolder = dataFolder,
            Platform = "windows",
            Os = TelemetryContext.WindowsOs(v.Major, v.Minor, v.Build),
            Device = device,
#if DEBUG
            Channel = TelemetryChannel.Dev,
#else
            Channel = TelemetryContext.ChannelFor(version),
#endif
            LaunchMs = LaunchMs(),
        };
    }

    /// <summary>Çökme ve oturum kapanışı kancaları.</summary>
    public static void Attach(Application app, NinoController controller)
    {
        if (controller.Telemetry is not { } telemetry) return;
        CrashGuard.Fatal = telemetry.RecordCrash;
        CrashGuard.Handled = _ => telemetry.Client.RecordError("app.unhandled");
        // Windows oturumu kapanırken pencere kapanışı beklenmeyebilir: bu çıkış çökme sayılmasın.
        app.SessionEnding += (_, e) =>
        {
            if (!e.Cancel) telemetry.Exiting();
        };
    }

    /// <summary>Sürecin başlangıcından denetleyicinin kurulmasına kadar geçen süre.</summary>
    static long? LaunchMs()
    {
        try
        {
            using var process = Process.GetCurrentProcess();
            var ms = (long)(DateTime.Now - process.StartTime).TotalMilliseconds;
            return ms is >= 0 and < 600_000 ? ms : null;
        }
        catch (Exception)
        {
            return null;
        }
    }
}
