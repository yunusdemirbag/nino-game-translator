// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Windows;
using Nino.App.Startup;
using Nino.App.Strings;
using Nino.Shell;

namespace Nino.App.Views;

/// <summary>Salonun ve cam anahtarın ortak aç/kapat'ı (ana-ekran §4.11).</summary>
public static class HomeActions
{
    static readonly TimeSpan StartingPoll = TimeSpan.FromMilliseconds(50);

    /// <summary>
    /// Çeviri açılıyorsa açılış bitene kadar 50 ms aralıkla beklenir, bitince açıksa durdurulur (hazırlıkta verilen
    /// kapatma kaybolmaz). Açıksa durdur; başlatılabiliyorsa başlat; değilse kurulumun TV ya da konsol adımı.
    /// Fiş balonuna "kullanıldı" bildirilir. Beklenmeyen hata günlüğe yazılır ve hatayı anlatan uyarı gösterilir.
    /// </summary>
    public static async Task ToggleAsync(NinoController controller)
    {
        // Fiş balonu: her kullanımda (yalnız kurulumu açsa da) 2 sn görünür; ilk kullanım kalıcı yazılır.
        PlugHintState.PlugUsed();
        try
        {
            if (controller.IsStarting)
            {
                while (controller.IsStarting) await Task.Delay(StartingPoll);
                if (controller.IsTranslating) controller.Stop();
                return;
            }
            var action = HomeToggleRule.Decide(controller.IsTranslating, controller.CanStart, controller.UsesCaptureCard,
                controller.ShowsOnTv);
            switch (action)
            {
                case HomeToggleAction.Stop:
                    controller.Stop();
                    break;
                case HomeToggleAction.Start:
                    await controller.StartAsync();
                    break;
                default:
                    controller.GoToStep(HomeToggleRule.StepFor(action));
                    break;
            }
        }
        catch (Exception e)
        {
            AppLogs.Current?.Error("Çeviri açılıp kapatılamadı", e);
            try
            {
                var text = ErrorText.Unhandled(e);
                if (Application.Current?.MainWindow is { } owner)
                    MessageBox.Show(owner, text, L.Get("app.error.title"), MessageBoxButton.OK, MessageBoxImage.Warning);
                else MessageBox.Show(text, L.Get("app.error.title"), MessageBoxButton.OK, MessageBoxImage.Warning);
            }
            catch (Exception shown) { AppLogs.Current?.Error("İleti gösterilemedi", shown); }
        }
    }
}
