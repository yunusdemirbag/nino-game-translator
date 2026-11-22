// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Windows;
using Nino.Shell;

namespace Nino.App.Views;

// Ayarlar ve yan pencereler bölümünün kabuğa verdikleri: pencereler, güvenlik duvarı kartı, bilgisayardaki altyazı
// penceresi, bilgisayar sonuç kutusu ve serbest alan penceresi.
public static partial class ShellWindows
{
    static partial void CreateWindow(ShellWindowKind kind, NinoController controller, ref Window? window) =>
        window = kind switch
        {
            ShellWindowKind.Settings => new SettingsWindow(controller),
            ShellWindowKind.History => new HistoryWindow(controller),
            ShellWindowKind.About => new AboutWindow(controller),
            ShellWindowKind.AskNino => new AskNinoWindow(controller),
            _ => null,
        };

    static partial void CreateFirewallCard(NinoController controller, ref FrameworkElement? card) =>
        card = new FirewallCard(controller);

    static partial void AttachComputerOverlay(Window owner, NinoController controller, ref IDisposable? link)
    {
        var overlay = new SubtitleOverlayWindow(controller);
        link = overlay;
    }

    static partial void AttachComputerResults(Window owner, NinoController controller, ref IDisposable? link)
    {
        Action<PopupText> show = popup => PcResultWindow.Present(popup);
        controller.ComputerPopup += show;
        link = new Detach(() => controller.ComputerPopup -= show);
    }

    static partial void AttachFreeArea(Window owner, NinoController controller, ref IDisposable? link)
    {
        Action open = () => FreeAreaWindow.Request(controller);
        controller.FreeAreaRequested += open;
        link = new Detach(() => controller.FreeAreaRequested -= open);
    }

    sealed class Detach(Action undo) : IDisposable
    {
        Action? _undo = undo;

        public void Dispose()
        {
            _undo?.Invoke();
            _undo = null;
        }
    }
}
