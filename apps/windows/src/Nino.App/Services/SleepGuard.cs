// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Runtime.InteropServices;
using System.Windows.Threading;
using Nino.Shell.Platform;
using Nino.Shell.WindowsRules;

namespace Nino.App.Services;

/// <summary>
/// Uyku engeli (kimlikler-veri §12.2): SetThreadExecutionState sürekli bayrakla her seferinde baştan verilir. Yürütme
/// durumu iş parçacığına bağlı olduğu için hep arayüz iş parçacığında çağrılır. Çevirinin isteği ile yakalama kartı
/// oyun penceresinin ekran isteği birleştirilir.
/// </summary>
public sealed class WindowsSleepGuard(Dispatcher dispatcher) : ISleepGuard
{
    [DllImport("kernel32.dll")]
    static extern uint SetThreadExecutionState(uint flags);

    readonly object _gate = new();
    bool _translating;
    bool _display;
    bool _card;

    /// <inheritdoc />
    public void Begin(bool keepDisplayOn)
    {
        lock (_gate)
        {
            _translating = true;
            _display = keepDisplayOn;
        }
        Apply();
    }

    /// <inheritdoc />
    public void End()
    {
        lock (_gate)
        {
            _translating = false;
            _display = false;
        }
        Apply();
    }

    /// <summary>Oyun bu bilgisayarda gösterilirken (yakalama kartı) ekranı ayrıca açık tutar.</summary>
    public void HoldDisplayForCard(bool on)
    {
        lock (_gate) _card = on;
        Apply();
    }

    void Apply()
    {
        uint flags;
        lock (_gate) flags = ExecutionStateRules.Flags(_translating, _display, _card);
        if (dispatcher.CheckAccess()) Set(flags);
        else dispatcher.BeginInvoke(() => Set(flags));
    }

    static void Set(uint flags)
    {
        try { SetThreadExecutionState(flags); }
        catch (Exception e) when (e is DllNotFoundException or EntryPointNotFoundException) { }
    }
}
