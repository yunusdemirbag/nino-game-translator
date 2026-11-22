// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.ComponentModel;
using System.Diagnostics;
using System.Windows.Controls;
using Nino.App.Startup;
using Nino.Shell;

namespace Nino.App.Views;

/// <summary>
/// Yazı tanıma dil paketi (ana-ekran §3.4 kart 9, §8): yönetici izniyle ("runas") gizli bir PowerShell, profilsiz,
/// oyun dilinin henüz kurulmamış ilk <c>Language.OCR~~~&lt;dil&gt;-*</c> Windows yeteneğini çevrimiçi kurar. Kullanıcı
/// izni reddederse sessizce vazgeçilir. Çeviri sürüyorsa yeni paketle okusun diye durdurulup yeniden başlatılır.
/// </summary>
internal static class OcrInstaller
{
    const int Cancelled = 1223;

    /// <summary>Paketi kurar; bu sürede düğme devre dışıdır.</summary>
    public static async Task InstallAsync(NinoController controller, Button button)
    {
        var pattern = OcrLanguageCode.CapabilityPattern(controller.SourceLanguage);
        if (pattern is null) return;
        button.IsEnabled = false;
        try
        {
            var installed = await Task.Run(() => RunElevated(pattern));
            if (installed && controller.IsTranslating)
            {
                controller.Stop();
                await controller.StartAsync();
            }
        }
        catch (Exception e)
        {
            AppLogs.Current?.Error("Yazı tanıma paketi kurulamadı", e);
        }
        finally
        {
            button.IsEnabled = true;
        }
    }

    /// <summary>Windows'un "Saat ve dil › Dil ve bölge" sayfası.</summary>
    public static void OpenLanguageSettings()
    {
        try
        {
            using var _ = Process.Start(new ProcessStartInfo("ms-settings:regionlanguage") { UseShellExecute = true });
        }
        catch (Exception e)
        {
            AppLogs.Current?.Error("Dil ayarları açılamadı", e);
        }
    }

    /// <summary>PowerShell'i yönetici olarak çalıştırıp bitmesini bekler; izin reddedilirse false.</summary>
    static bool RunElevated(string pattern)
    {
        // Kalıp yalnız harf, rakam, tire, '~', '.' ve '*' içerir (OcrLanguageCode denetler); tek tırnak içinde güvenli.
        var script =
            "$c = Get-WindowsCapability -Online | Where-Object { $_.Name -like '" + pattern + "' -and $_.State -ne 'Installed' } " +
            "| Select-Object -First 1; if ($c) { Add-WindowsCapability -Online -Name $c.Name | Out-Null }";
        var start = new ProcessStartInfo("powershell.exe")
        {
            UseShellExecute = true,
            Verb = "runas",
            WindowStyle = ProcessWindowStyle.Hidden,
            CreateNoWindow = true,
        };
        foreach (var arg in new[] { "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden", "-Command", script })
            start.ArgumentList.Add(arg);
        try
        {
            using var process = Process.Start(start);
            if (process is null) return false;
            process.WaitForExit();
            return process.ExitCode == 0;
        }
        catch (Win32Exception e) when (e.NativeErrorCode == Cancelled)
        {
            return false;
        }
    }
}
