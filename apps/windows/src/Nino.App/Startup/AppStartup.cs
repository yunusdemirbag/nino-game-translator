// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.ComponentModel;
using System.Windows;
using System.Windows.Threading;
using Nino.App.Strings;
using Nino.App.Theme;
using Nino.App.Views;
using Nino.Core.Data;
using Nino.Shell;
using Nino.Shell.Platform;

namespace Nino.App.Startup;

/// <summary>
/// Asıl açılış (ana-ekran.md §1, kimlikler-veri.md §3.4): WPF uygulaması (ortak stiller ve sağdan sola kuralı
/// <see cref="App"/>'in kurucusunda, ilk pencereden önce) → hata gözcüsü → günlükler → Windows hizmetleri →
/// denetleyici → görünüm → ana pencere. Herhangi bir hata, hatayı anlatan iletiyle çıkış kodu 3'te biter.
/// </summary>
public static class AppStartup
{
    /// <summary>Uygulamayı çalıştırır; çıkış kodunu verir.</summary>
    /// <param name="renderFolder">Ekran dökümü kipinde PNG klasörü; normal açılışta null.</param>
    public static int Run(string? renderFolder)
    {
        var app = new App();
        if (renderFolder is not null) return ScreenRenderer.Run(app, renderFolder);

        CrashGuard.Install(app);
        NinoController controller;
        MainWindow window;
        AppLogs logs;
        RemotePlayLogTap? tap = null;
        try
        {
            var dataFolder = NinoDataFolder.Current.Path;
            logs = AppLogs.Open(dataFolder);
            logs.RemotePlay.Nino("Nino açıldı");

            var dispatcher = app.Dispatcher;
            Action<Action> post = a => dispatcher.BeginInvoke(DispatcherPriority.Normal, a);

            var pieces = AppParts.CreatePlatform(dataFolder, post)
                ?? throw new InvalidOperationException("Windows hizmetleri bu derlemede yok.");
            var platform = AppParts.Platform;
            controller = new NinoController(pieces.Services, pieces.Secrets, pieces.Settings, pieces.Sleep, L.Catalog, post,
                new ShellOptions
                {
                    Logs = logs,
                    Timers = platform?.Timers,
                    Browser = platform?.Browser,
                    Hotkeys = platform?.Hotkeys,
                    PsnWindow = AppParts.CreatePsnSignInWindow(),
                    Telemetry = WindowsTelemetry.Setup(dataFolder, pieces.Services),
                });
            WindowsTelemetry.Attach(app, controller);
            // Önceki çalışma yerel bir hatayla kapandıysa Windows olay günlüğündeki iz hata.log'a ve ölçüme.
            var telemetry = controller.Telemetry;
            CrashEvidence.ReportInBackground(dataFolder, logs.Errors, code => telemetry?.Client.RecordError(code));

            // remoteplay.log satırları sağlık kaydına ve altyazı günlüğündeki duraklama izleyicisine de gider.
            tap = RemotePlayLogTap.Attach(logs.RemotePlay, controller.Health, logs.Subtitle);

            // Görünüm ilk pencereden önce; ayar değişince yeniden (aynı görünüm ikinci kez kurulmaz).
            ThemeManager.Apply(controller.Settings.Appearance);
            controller.PropertyChanged += (_, e) => OnControllerChanged(controller, e);

            window = new MainWindow(controller, live: true);
            app.MainWindow = window;
            RightToLeft.ApplyTo(window);
            window.Show();
        }
        catch (Exception e)
        {
            StartupErrorLog.Write("Açılış hatası", e);
            try { MessageBox.Show(ErrorText.Startup(e), StartupMessages.Title, MessageBoxButton.OK, MessageBoxImage.Error); }
            catch (Exception shown) { StartupErrorLog.Write("İleti gösterilemedi", shown); }
            return Program.FailedExitCode;
        }

        var code = app.Run();
        tap?.Dispose();
        CaptureCardDevicesStop();
        logs.Dispose();
        return code;
    }

    static void CaptureCardDevicesStop()
    {
        try { Services.CaptureCardDevices.Current?.Dispose(); } catch (Exception) { }
    }

    static void OnControllerChanged(NinoController controller, PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(NinoController.Settings)) ThemeManager.Apply(controller.Settings.Appearance);
    }
}
