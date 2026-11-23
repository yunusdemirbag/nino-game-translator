// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.App.Views;
using Nino.Shell;

namespace Nino.App.Startup;

// Ekran dökümüne Ayarlar ve Hakkında dışındaki yan pencereler ve kurulumun ara ekranları (eski araçta yoktu; dosya
// adları yeni). Ek parametre isteyen pencereler (oyun paketi içe aktarma, serbest alan, PSN girişi) dökülmez.
public static partial class ScreenCatalog
{
    static partial void AddScreens(List<ScreenEntry> list)
    {
        // Kurulum: karşılama adımında açılan HDMI yakalama kartı rehberi.
        list.Add(new ScreenEntry("adim-kart-rehberi", MainWindow.DefaultWidth, MainWindow.DefaultHeight, false, c =>
        {
            c.OpenCardGuide();
            return ShellWindows.CreateSetupView(c);
        }));
        list.Add(new ScreenEntry("gecmis", 640, 640, true, c => ShellWindows.Create(ShellWindowKind.History, c)));
        list.Add(new ScreenEntry("sor", 440, 680, true, c => ShellWindows.Create(ShellWindowKind.AskNino, c)));
        list.Add(new ScreenEntry("sorun-bildir", 640, 672, true, c => new ReportProblemWindow(c)));
        list.Add(new ScreenEntry("sistem-sagligi", 720, 720, true, c => new SystemHealthWindow(c)));
        list.Add(new ScreenEntry("kart-rehberi", 760, 760, true, c => new CaptureCardGuideWindow(c)));
        list.Add(new ScreenEntry("yayin", 1280, 720, true, c => new StreamWindow(c)));
        // Ana ekranın ikinci arayüzü (cam anahtar); salonlu hâli "ana".
        list.Add(new ScreenEntry("ana-anahtar", MainWindow.DefaultWidth, MainWindow.DefaultHeight, true, c =>
        {
            var settings = c.Settings.Clone();
            settings.HomeStyle = Nino.Core.Settings.HomeStyle.Toggle;
            c.UpdateSettings(settings);
            return new HomeView(c);
        }));
        // Ayarlar'ın bölüm sayfaları (liste görünümü "ayarlar"): ayarlar-<bölüm kimliği>, gizli bölümler dahil.
        foreach (var page in Enum.GetValues<Nino.Shell.Panels.SettingsPage>())
        {
            if (Nino.Shell.Panels.SettingsPages.Opens(page) != Nino.Shell.Panels.SettingsPageOpens.Page) continue;
            list.Add(new ScreenEntry("ayarlar-" + Nino.Shell.Panels.SettingsPages.Id(page), 1000, 720, true,
                c => new SettingsWindow(c, page)));
        }
    }
}
