// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Windows.Threading;
using Microsoft.Win32;
using Nino.Core.Data;
using Nino.Core.Settings;
using Nino.RemotePlay;
using Nino.Shell.Platform;
using Nino.Shell.WindowsRules;

namespace Nino.App.Services;

/// <summary>Windows hizmetlerinin platforma özgü parçaları.</summary>
public sealed record WindowsServiceParts
{
    /// <summary>Arayüz iş parçacığı (kart oyun penceresi orada kurulur).</summary>
    public required Dispatcher Dispatcher { get; init; }

    /// <summary>Uyku engeli (kart oyun penceresinin ekran isteği).</summary>
    public WindowsSleepGuard? Sleep { get; init; }

    /// <summary>Kaynakların altyazı günlüğü satırları.</summary>
    public Action<string>? SourceLog { get; init; }

    /// <summary>Hata günlüğü.</summary>
    public Action<string, Exception?>? ErrorLog { get; init; }

    /// <summary>Güncelleyici.</summary>
    public IAppUpdater? Updater { get; init; }

    /// <summary>Güvenlik duvarı.</summary>
    public IFirewall? Firewall { get; init; }
}

/// <summary>
/// Windows'un hizmetleri: platformdan bağımsız bağlantılar <see cref="CoreShellServices"/>'ten; burada yazı tanıma,
/// pencere ve kart kaynakları, güncelleyici, güvenlik duvarı ve cihaz bilgisi. Xbox hizmeti bu sürümde yok.
/// </summary>
public sealed class WindowsShellServices : CoreShellServices, IShellServices
{
    readonly WindowsServiceParts _parts;
    readonly Lazy<WindowsOcrReaderFactory> _readers;

    /// <summary>Kurar.</summary>
    public WindowsShellServices(CoreShellServicesOptions options, WindowsServiceParts parts) : base(options)
    {
        _parts = parts;
        _readers = new(() => new WindowsOcrReaderFactory(Packs is { } packs ? t => packs.FindExact(t) is not null : null));
    }

    Action<string> Log => _parts.SourceLog ?? (_ => { });

    /// <inheritdoc />
    public override ITextReaderFactory Readers => _readers.Value;

    /// <inheritdoc cref="IShellServices.Updater" />
    public IAppUpdater? Updater => _parts.Updater;

    /// <inheritdoc cref="IShellServices.Firewall" />
    public IFirewall? Firewall => _parts.Firewall;

    /// <inheritdoc cref="IShellServices.CreateGameWindowSource" />
    public IGameWindowSource? CreateGameWindowSource(GameConsole console) => new GameWindowCapture(console, Log);

    /// <inheritdoc cref="IShellServices.CreateCaptureCardSource" />
    public ICaptureCardSource? CreateCaptureCardSource(bool showGameHere, string? preferredDeviceId) =>
        new CaptureCardCapture(new CaptureCardOptions
        {
            ShowGameHere = showGameHere,
            PreferredDeviceId = preferredDeviceId,
            Dispatcher = _parts.Dispatcher,
            Log = Log,
            HoldDisplay = on => _parts.Sleep?.HoldDisplayForCard(on),
        });

    /// <inheritdoc cref="IShellServices.CreateRemotePlayWindowSource" />
    public IVideoSource CreateRemotePlayWindowSource(RemotePlayApp app) => GraphicsCaptureSource.ForApp(app, Log);

    /// <inheritdoc cref="IShellServices.CreateChosenWindowSource" />
    public IVideoSource CreateChosenWindowSource(CaptureWindowChoice window) => GraphicsCaptureSource.ForWindow(window, Log);

    /// <inheritdoc cref="IShellServices.VisibleWindows" />
    public IReadOnlyList<VisibleWindow> VisibleWindows() => NativeWindows.Listing();

    /// <inheritdoc cref="IShellServices.IsRemotePlayAppInstalled" />
    public bool IsRemotePlayAppInstalled(RemotePlayApp app) => GraphicsCaptureSource.InstalledPath(app) is not null;

    /// <inheritdoc cref="IShellServices.DeviceAndSystem" />
    public (string Device, string System) DeviceAndSystem
    {
        get
        {
            string model;
            try
            {
                using var bios = Registry.LocalMachine.OpenSubKey(@"HARDWARE\DESCRIPTION\System\BIOS");
                model = DeviceInfo.ComputerModel(bios?.GetValue("SystemManufacturer") as string,
                    bios?.GetValue("SystemProductName") as string);
            }
            catch (Exception)
            {
                model = DeviceInfo.FallbackModel;
            }
            var v = Environment.OSVersion.Version;
            return (model, DeviceInfo.WindowsName(v.Major, v.Minor, v.Build));
        }
    }

    /// <summary>Windows'un "Ülke veya bölge" ayarı (biçim dilinden bağımsız).</summary>
    public string? RegionCode
    {
        get
        {
            try
            {
                var buffer = new char[16];
                var n = GetUserDefaultGeoName(buffer, buffer.Length);
                return n > 1 ? new string(buffer, 0, n - 1) : null;
            }
            catch (Exception) { return null; }
        }
    }

    /// <summary>Hesabın görünen adı (ör. Microsoft hesabındaki ad); yoksa null.</summary>
    public string? AccountName
    {
        get
        {
            try
            {
                var size = 256u;
                var buffer = new char[size];
                return GetUserNameExW(3, buffer, ref size) && size > 0 ? new string(buffer, 0, (int)size) : null;
            }
            catch (Exception) { return null; }
        }
    }

    [System.Runtime.InteropServices.DllImport("kernel32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
    static extern int GetUserDefaultGeoName([System.Runtime.InteropServices.Out] char[] geoName, int geoNameCount);

    [System.Runtime.InteropServices.DllImport("secur32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
    [return: System.Runtime.InteropServices.MarshalAs(System.Runtime.InteropServices.UnmanagedType.U1)]
    static extern bool GetUserNameExW(int nameFormat, [System.Runtime.InteropServices.Out] char[] name, ref uint size);
}
