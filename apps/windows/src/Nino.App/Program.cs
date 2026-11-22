// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.IO;
using System.Runtime.CompilerServices;
using System.Windows;
using Nino.App.Startup;

namespace Nino.App;

/// <summary>
/// Giriş noktası (kimlikler-veri.md §3.1). Sıra: güvenlik duvarı yardımcısı (tek argüman) → Velopack kancaları →
/// veri klasörü → eksik dosya denetimi → WPF. Her adım ayrı, satır içine alınmayan bir yöntemdedir: bir DLL eksikse
/// yalnız o adımın derlenmesi düşer, <see cref="Main"/> ve eksik dosya iletisi .NET'in kendi türleriyle çalışmayı sürdürür.
/// </summary>
public static partial class Program
{
    /// <summary>Güvenlik duvarı kurallarını yazan yönetici yardımcısının argümanı.</summary>
    public const string FirewallArgument = "--configure-local-firewall";

    /// <summary>Ekran dökümü kipinin argümanı (ardından klasör).</summary>
    public const string RenderArgument = "--render-screens";

    /// <summary>Açılamayan uygulamanın çıkış kodu.</summary>
    public const int FailedExitCode = 3;

    [STAThread]
    public static int Main(string[] args)
    {
        if (args.Length == 1 && args[0] == FirewallArgument) return RunFirewallHelper();

        RunVelopackHooks(args);

        var renderFolder = args.Length == 2 && args[0] == RenderArgument ? args[1] : null;
        if (renderFolder is null) PrepareDataFolderSafely();

        var missing = StartupFiles.FindMissing(AppContext.BaseDirectory);
        if (missing.Count > 0)
        {
            ReportMissingFiles(missing, renderFolder);
            return FailedExitCode;
        }

        return RunApplication(renderFolder);
    }

    // ---- 1. Güvenlik duvarı yardımcısı (UAC ile yönetici; arayüz yok, veri klasörüne dokunmaz) ----

    [MethodImpl(MethodImplOptions.NoInlining)]
    static int RunFirewallHelper()
    {
        var exitCode = 1;
        try { ConfigureLocalFirewall(ref exitCode); }
        catch (Exception) { exitCode = 1; }
        return exitCode;
    }

    /// <summary>
    /// Kuralları yazar (kimlikler-veri.md §11.4); başarıda <paramref name="exitCode"/> 0. Gövdesi Windows hizmetlerinde
    /// (güvenlik duvarı) yazılır; yazılmamışsa yardımcı 1 ile biter.
    /// </summary>
    static partial void ConfigureLocalFirewall(ref int exitCode);

    /// <summary>Velopack kaldırma öncesi kancası: bu exe'nin yönettiği güvenlik duvarı kuralları sessizce silinir (§11.5).</summary>
    static partial void RemoveFirewallRulesBeforeUninstall();

    // ---- 2. Velopack ----

    [MethodImpl(MethodImplOptions.NoInlining)]
    static void RunVelopackHooks(string[] args)
    {
        try { VelopackStep(args); }
        catch (Exception e) when (e is FileNotFoundException or FileLoadException or TypeLoadException)
        {
            // Velopack DLL'i eksikse eksik dosya denetimi anlatır.
        }
    }

    [MethodImpl(MethodImplOptions.NoInlining)]
    static void VelopackStep(string[] args) =>
        Velopack.VelopackApp.Build()
            .OnBeforeUninstallFastCallback(_ =>
            {
                try { RemoveFirewallRulesBeforeUninstall(); }
                catch (Exception) { }
            })
            .SetArgs(args)
            .Run();

    // ---- 3. Veri klasörü ----

    [MethodImpl(MethodImplOptions.NoInlining)]
    static void PrepareDataFolderSafely()
    {
        try { DataFolderStep.Prepare(); }
        catch (Exception e) when (e is FileNotFoundException or FileLoadException or TypeLoadException)
        {
            StartupErrorLog.Write("Veri klasörü hazırlanamadı", e);
        }
        catch (Exception e)
        {
            StartupErrorLog.Write("Veri klasörü hazırlanamadı", e);
        }
    }

    // ---- 4. Eksik dosyalar ----

    [MethodImpl(MethodImplOptions.NoInlining)]
    static void ReportMissingFiles(IReadOnlyList<string> missing, string? renderFolder)
    {
        var turkish = StartupMessages.Turkish;
        var text = StartupMessages.MissingFiles(missing, turkish);
        StartupErrorLog.Write(text);
        if (renderFolder is not null)
        {
            RenderErrors.Append(renderFolder, text);
            return;
        }
        try { MessageBox.Show(text, StartupMessages.Title, MessageBoxButton.OK, MessageBoxImage.Error); }
        catch (Exception e) { StartupErrorLog.Write("İleti gösterilemedi", e); }
    }

    // ---- 5. WPF ----

    [MethodImpl(MethodImplOptions.NoInlining)]
    static int RunApplication(string? renderFolder)
    {
        try { return AppStartup.Run(renderFolder); }
        catch (Exception e)
        {
            // Uygulama kurulamadıysa (App ya da kaynaklar) iletiyi .NET türleriyle göster.
            StartupErrorLog.Write("Açılış hatası", e);
            var text = StartupMessages.StartupError(e, StartupErrorLog.DisplayPath, StartupMessages.Turkish);
            if (renderFolder is not null) RenderErrors.Append(renderFolder, text);
            else
            {
                try { MessageBox.Show(text, StartupMessages.Title, MessageBoxButton.OK, MessageBoxImage.Error); }
                catch (Exception shown) { StartupErrorLog.Write("İleti gösterilemedi", shown); }
            }
            return FailedExitCode;
        }
    }
}
