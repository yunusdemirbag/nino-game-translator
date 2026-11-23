// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Net;
using System.Text.RegularExpressions;

namespace Nino.TvInstall.Android;

/// <summary>Android TV'ye ağ üzerinden ADB ile kurulum (tek bağlantıda; TV onayı en çok bir kez sorulur).</summary>
public sealed partial class AndroidTvAppInstaller
{
    public const int AdbPort = 5555;
    public const string Package = "com.ninotranslator.tv";
    public const string LaunchCommand = "shell:am start -n com.ninotranslator.tv/.MainActivity";

    [GeneratedRegex(@"versionName=(\S+)")]
    private static partial Regex VersionNameRegex();

    public int Port { get; init; } = AdbPort;
    public TimeSpan ApprovalTimeout { get; init; } = AdbSession.DefaultApprovalTimeout;

    /// <summary>
    /// TV'deki sürüm paketten eski değilse dokunmaz (katman izni verir, çalışmıyorsa açar); değilse kurar. Her iki yolda
    /// da yeni uygulama hazır olduktan sonra eski adlı TV uygulaması varsa kaldırılır: yanında kalırsa o da bağlanıp kendi
    /// altyazısını çizer (çift altyazı) ya da TV'de yalnız o açılır. Yalnız eski uygulama varsa yenisi kurulur.
    /// </summary>
    public async Task<TvInstallResult> InstallAsync(string host, string apkPath, string? packageVersion, string keyFolder,
        Action? onApprovalNeeded = null, CancellationToken ct = default)
    {
        using var key = AdbKey.LoadOrCreate(keyFolder);
        await using var adb = await AdbSession.ConnectAsync(host, Port, key, onApprovalNeeded, ApprovalTimeout, ct).ConfigureAwait(false);

        var installed = ParseVersion(await adb.RunAsync("shell:dumpsys package " + Package, null, ct).ConfigureAwait(false));
        if (installed is not null && !TvVersions.IsNewerLoose(packageVersion, installed))
        {
            await GrantOverlayAsync(adb, ct).ConfigureAwait(false);
            var pid = await adb.RunAsync("shell:pidof " + Package, null, ct).ConfigureAwait(false);
            await RemoveLegacyAsync(adb, ct).ConfigureAwait(false);
            if (pid.Trim().Length == 0) await adb.RunAsync(LaunchCommand, null, ct).ConfigureAwait(false);
            return new TvInstallResult(installed, false);
        }

        if (installed is not null) await adb.RunAsync("shell:pm uninstall " + Package, null, ct).ConfigureAwait(false);
        var output = await PushApkAsync(adb, apkPath, ct).ConfigureAwait(false);
        if (output.Contains("INSTALL_FAILED_UPDATE_INCOMPATIBLE", StringComparison.Ordinal) ||
            output.Contains("INSTALL_FAILED_VERSION_DOWNGRADE", StringComparison.Ordinal))
        {
            await adb.RunAsync("shell:pm uninstall " + Package, null, ct).ConfigureAwait(false);
            output = await PushApkAsync(adb, apkPath, ct).ConfigureAwait(false);
        }
        if (!output.Contains("Success", StringComparison.Ordinal))
            throw new TvInstallException(TvInstallFailure.InstallFailed, output.Trim());
        await GrantOverlayAsync(adb, ct).ConfigureAwait(false);
        await RemoveLegacyAsync(adb, ct).ConfigureAwait(false);
        await adb.RunAsync(LaunchCommand, null, ct).ConfigureAwait(false);
        return new TvInstallResult(packageVersion ?? "", true);
    }

    /// <summary>Eski adlı TV uygulaması kuruluysa kaldırır; döner: kaldırıldı mı.</summary>
    static async Task<bool> RemoveLegacyAsync(AdbSession adb, CancellationToken ct)
    {
        var legacy = LegacyNames.AndroidTvPackage;
        var list = await adb.RunAsync("shell:pm list packages " + legacy, null, ct).ConfigureAwait(false);
        if (!list.Split('\n').Any(l => l.Trim() == "package:" + legacy)) return false;
        var r = await adb.RunAsync("shell:pm uninstall " + legacy, null, ct).ConfigureAwait(false);
        return r.Contains("Success", StringComparison.Ordinal);
    }

    static async Task<string> PushApkAsync(AdbSession adb, string apkPath, CancellationToken ct)
    {
        await using var file = File.OpenRead(apkPath);
        return await adb.RunAsync($"exec:cmd package install -r -S {file.Length}", file, ct).ConfigureAwait(false);
    }

    /// <summary><c>dumpsys package</c> çıktısındaki <c>versionName</c>; yoksa null.</summary>
    public static string? ParseVersion(string output)
    {
        var m = VersionNameRegex().Match(output);
        return m.Success ? m.Groups[1].Value : null;
    }

    /// <summary>"Hata gibi": Error, Exception, Unknown ya da not allowed (harf duyarsız). Boş çıktı başarıdır.</summary>
    public static bool LooksLikeError(string output) =>
        output.Contains("Error", StringComparison.OrdinalIgnoreCase) ||
        output.Contains("Exception", StringComparison.OrdinalIgnoreCase) ||
        output.Contains("Unknown", StringComparison.OrdinalIgnoreCase) ||
        output.Contains("not allowed", StringComparison.OrdinalIgnoreCase);

    /// <summary>"Diğer uygulamaların üzerinde göster" izni; verilemezse kurulum yine başarılıdır.</summary>
    static async Task<bool> GrantOverlayAsync(AdbSession adb, CancellationToken ct)
    {
        try
        {
            var r = await adb.RunAsync($"shell:appops set {Package} SYSTEM_ALERT_WINDOW allow", null, ct).ConfigureAwait(false);
            if (!LooksLikeError(r)) return true;
            r = await adb.RunAsync($"shell:pm grant {Package} android.permission.SYSTEM_ALERT_WINDOW", null, ct).ConfigureAwait(false);
            return !LooksLikeError(r);
        }
        catch (Exception e) when (e is not OperationCanceledException)
        {
            return false;
        }
    }

    /// <summary>TCP 5555 açık mı (varsayılan 1 sn).</summary>
    public static Task<bool> IsReachableAsync(string host, TimeSpan? timeout = null, CancellationToken ct = default) =>
        IPAddress.TryParse(host, out var ip)
            ? LanScan.IsPortOpenAsync(ip, AdbPort, timeout ?? TimeSpan.FromSeconds(1), ct)
            : Task.FromResult(false);

    /// <summary>Yerel bilgisayarın özel ağlarında ADB'si açık cihazlar (aynı anda 64, her biri 700 ms), son bayta göre sıralı.</summary>
    public static async Task<IReadOnlyList<string>> ScanAsync(CancellationToken ct = default)
    {
        var hosts = await LanScan.OpenHostsAsync(LanScan.Targets(LanScan.LocalPrivateAddresses()), AdbPort,
            TimeSpan.FromMilliseconds(700), 64, ct).ConfigureAwait(false);
        return hosts.Select(h => h.ToString()).ToList();
    }
}
