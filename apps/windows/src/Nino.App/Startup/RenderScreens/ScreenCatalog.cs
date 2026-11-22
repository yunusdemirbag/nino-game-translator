// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Windows;
using Nino.App.Views;
using Nino.Shell;

namespace Nino.App.Startup;

/// <summary>Ekran dökümündeki bir ekran.</summary>
/// <param name="FileStem">Dosya adının tema soneki öncesi (ör. "ana", "adim-3-PsnLogin"); dosya
/// <c>&lt;FileStem&gt;-acik.png</c> / <c>-koyu.png</c>.</param>
/// <param name="Width">Genişlik (px).</param>
/// <param name="Height">Yükseklik (px).</param>
/// <param name="SetupDone">Sahte denetleyicide kurulum bitmiş mi saklansın.</param>
/// <param name="Create">Kurucu: sahte denetleyiciden çizilecek görünüm (<see cref="FrameworkElement"/>) ya da pencere
/// (<see cref="Window"/>; içeriği çizilir). Null dönerse ekran atlanır ve <c>errors.txt</c>'ye yazılır.</param>
public sealed record ScreenEntry(string FileStem, double Width, double Height, bool SetupDone,
    Func<NinoController, object?> Create);

/// <summary>
/// Ekran dökümü kipinin ekran listesi (ana-ekran §11; eskisiyle aynı dosya adları). Kurulum adımları, ana ekran,
/// ana pencere, Ayarlar ve Hakkında burada; başka bölümler kendi pencerelerini <see cref="AddScreens"/> kısmi
/// yöntemiyle ekler, ör.
/// <code>static partial void AddScreens(List&lt;ScreenEntry&gt; list) =>
///     list.Add(new("gecmis", 720, 640, true, c => new HistoryWindow(c)));</code>
/// </summary>
public static partial class ScreenCatalog
{
    /// <summary>Kurulum adımları sırasıyla ve dosya adlarındaki İngilizce adları (adımın kendi adı değil).</summary>
    public static IReadOnlyList<(SetupStep Step, string Name)> SetupSteps { get; } =
    [
        (SetupStep.Welcome, "Welcome"),
        (SetupStep.SecondAccount, "SecondAccount"),
        (SetupStep.PsnSignIn, "PsnLogin"),
        (SetupStep.Console, "Console"),
        (SetupStep.Tv, "Tv"),
        (SetupStep.Model, "Translation"),
        (SetupStep.Test, "Test"),
        (SetupStep.BetterTranslation, "BetterTranslation"),
    ];

    /// <summary>Bütün ekranlar.</summary>
    public static IReadOnlyList<ScreenEntry> All()
    {
        var list = new List<ScreenEntry>();
        for (var i = 0; i < SetupSteps.Count; i++)
        {
            var (step, name) = SetupSteps[i];
            list.Add(new ScreenEntry($"adim-{i + 1}-{name}", MainWindow.DefaultWidth, MainWindow.DefaultHeight, false, c =>
            {
                c.GoToStep(step);
                return ShellWindows.CreateSetupView(c);
            }));
        }
        list.Add(new ScreenEntry("ana", MainWindow.DefaultWidth, MainWindow.DefaultHeight, true, c => new HomeView(c)));
        list.Add(new ScreenEntry("pencere", MainWindow.DefaultWidth, MainWindow.DefaultHeight, true, c => new MainWindow(c, live: false)));
        list.Add(new ScreenEntry("ayarlar", 1000, 720, true, c => ShellWindows.Create(ShellWindowKind.Settings, c)));
        list.Add(new ScreenEntry("hakkinda", 460, 640, true, c => ShellWindows.Create(ShellWindowKind.About, c)));
        AddScreens(list);
        return list;
    }

    /// <summary>Öbür bölümlerin ekranları (yan pencereler, rehberler …).</summary>
    static partial void AddScreens(List<ScreenEntry> list);
}
