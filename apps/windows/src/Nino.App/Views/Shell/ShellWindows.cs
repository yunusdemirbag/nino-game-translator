// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Windows;
using Nino.Shell;

namespace Nino.App.Views;

/// <summary>Kabuğun açtığı sahipli pencereler.</summary>
public enum ShellWindowKind
{
    Settings,
    History,
    About,
    AskNino,
}

/// <summary>
/// Kabuğun öbür bölümlerden aldığı pencere ve görünümler. Her biri bir kısmi yöntemdir: gövdesi o pencereyi yazan
/// bölümde (kurulum, ayarlar ve yan pencereler) ya da birleştirmede yazılır, ör.
/// <code>static partial void CreateWindow(ShellWindowKind kind, NinoController c, ref Window? w) =>
///     w = kind switch { ShellWindowKind.Settings => new SettingsWindow(c), … };</code>
/// Yazılmamışsa o parça yoktur (düğme bir şey açmaz); kabuk yine derlenir ve çalışır.
/// </summary>
public static partial class ShellWindows
{
    static readonly Dictionary<ShellWindowKind, Window> Open = [];

    /// <summary>
    /// Sahipli, kipsiz tek pencere (ana-ekran §2.6): aynı türden görünür bir pencere varsa yenisi açılmaz, küçültülmüşse
    /// normale döndürülüp öne getirilir. Sahibi kapanınca o da kapanır.
    /// </summary>
    public static void Show(ShellWindowKind kind, Window owner, NinoController controller)
    {
        if (Open.TryGetValue(kind, out var existing) && existing.IsVisible)
        {
            if (existing.WindowState == WindowState.Minimized) existing.WindowState = WindowState.Normal;
            existing.Activate();
            return;
        }
        Window? window = null;
        CreateWindow(kind, controller, ref window);
        if (window is null) return;
        window.Owner = owner;
        Open[kind] = window;
        window.Closed += (_, _) =>
        {
            if (Open.TryGetValue(kind, out var w) && ReferenceEquals(w, window)) Open.Remove(kind);
        };
        window.Show();
    }

    /// <summary>Pencereyi kurar (gösterilmez; ekran dökümü de kullanır); yoksa null.</summary>
    public static Window? Create(ShellWindowKind kind, NinoController controller)
    {
        Window? window = null;
        CreateWindow(kind, controller, ref window);
        return window;
    }

    /// <summary>Kurulum sihirbazının görünümü (<c>SetupView</c>); yoksa null.</summary>
    public static FrameworkElement? CreateSetupView(NinoController controller)
    {
        FrameworkElement? view = null;
        CreateSetupView(controller, ref view);
        return view;
    }

    /// <summary>Ana ekrandaki güvenlik duvarı kartı (<c>FirewallCard</c>); yoksa null.</summary>
    public static FrameworkElement? CreateFirewallCard(NinoController controller)
    {
        FrameworkElement? card = null;
        CreateFirewallCard(controller, ref card);
        return card;
    }

    /// <summary>
    /// Pencereye bağlı yan işler (ana-ekran §2.5): bilgisayardaki altyazı penceresi, bilgisayarda gösterilen sonuç
    /// kutusu, serbest alan penceresi. Dönen nesneler kapanışta bırakılır. Altyazı penceresi kurulamazsa
    /// <paramref name="overlayFailed"/> hatayla çağrılır, uygulama onsuz sürer.
    /// </summary>
    public static IReadOnlyList<IDisposable> AttachSideWindows(Window owner, NinoController controller,
        Action<Exception> overlayFailed)
    {
        var links = new List<IDisposable>();
        try
        {
            IDisposable? overlay = null;
            AttachComputerOverlay(owner, controller, ref overlay);
            if (overlay is not null) links.Add(overlay);
        }
        catch (Exception e)
        {
            overlayFailed(e);
        }
        IDisposable? results = null;
        AttachComputerResults(owner, controller, ref results);
        if (results is not null) links.Add(results);
        IDisposable? freeArea = null;
        AttachFreeArea(owner, controller, ref freeArea);
        if (freeArea is not null) links.Add(freeArea);
        return links;
    }

    static partial void CreateWindow(ShellWindowKind kind, NinoController controller, ref Window? window);

    static partial void CreateSetupView(NinoController controller, ref FrameworkElement? view);

    static partial void CreateFirewallCard(NinoController controller, ref FrameworkElement? card);

    /// <summary>Masaüstündeki altyazı penceresi (<c>SubtitleOverlayWindow</c>); hata fırlatabilir.</summary>
    static partial void AttachComputerOverlay(Window owner, NinoController controller, ref IDisposable? link);

    /// <summary>Bilgisayarda gösterilecek çevirilerin küçük kutusu (<c>PcResultWindow</c>, <c>ComputerPopup</c>).</summary>
    static partial void AttachComputerResults(Window owner, NinoController controller, ref IDisposable? link);

    /// <summary>Serbest seçim penceresi (<c>FreeAreaWindow</c>, <c>FreeAreaRequested</c>).</summary>
    static partial void AttachFreeArea(Window owner, NinoController controller, ref IDisposable? link);
}
