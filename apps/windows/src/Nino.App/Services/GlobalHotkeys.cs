// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Runtime.InteropServices;
using System.Windows.Interop;
using System.Windows.Threading;
using Nino.Core.Settings;
using Nino.Shell.Platform;
using Nino.Shell.WindowsRules;

namespace Nino.App.Services;

/// <summary>
/// Genel kısayollar (kimlikler-veri §12.1): ana pencerenin tutamağına bağlı RegisterHotKey, tekrar etmeme bayrağıyla.
/// Kimlik: tablo sırasındaki n'inci kısayol için 0x4353 + n. Pencere tutamağı denetleyiciden sonra hazır olur:
/// <see cref="Attach"/> geç çağrılır; o zamana kadar istenen tablo saklanır ve bağlanınca tutulur. Tutulamayan tuş
/// sessizce atlanır; başarısız liste değişince bir kez hata günlüğüne yazılır.
/// </summary>
public sealed class GlobalHotkeys(Dispatcher dispatcher, Action<string>? log = null) : IHotkeyHost, IDisposable
{
    [DllImport("user32.dll", SetLastError = true)]
    static extern bool RegisterHotKey(IntPtr hWnd, int id, uint modifiers, uint vk);

    [DllImport("user32.dll", SetLastError = true)]
    static extern bool UnregisterHotKey(IntPtr hWnd, int id);

    readonly Dictionary<int, HotkeyAction> _held = [];
    readonly HotkeyFailureNote _failures = new();
    IReadOnlyList<ResolvedHotkey>? _wanted;
    HwndSource? _source;
    IntPtr _hwnd;
    Action<HotkeyAction>? _pressed;

    /// <summary>
    /// Ana pencereye bağlar. <paramref name="pressed"/> arayüz iş parçacığında çağrılır (ana pencere burada
    /// <c>controller.RunHotkeyAsync</c>'i çağırır).
    /// </summary>
    public void Attach(IntPtr windowHandle, Action<HotkeyAction> pressed)
    {
        Run(() =>
        {
            Detach();
            _hwnd = windowHandle;
            _pressed = pressed;
            _source = HwndSource.FromHwnd(windowHandle);
            _source?.AddHook(Hook);
            if (_wanted is { } table) Register(table);
        });
    }

    /// <summary>Pencereden ayırır (kısayollar bırakılır).</summary>
    public void Detach()
    {
        Run(() =>
        {
            UnregisterAll();
            _source?.RemoveHook(Hook);
            _source = null;
            _hwnd = IntPtr.Zero;
        });
    }

    /// <inheritdoc />
    public void Hold(IReadOnlyList<ResolvedHotkey> hotkeys)
    {
        Run(() =>
        {
            _wanted = hotkeys;
            if (_hwnd != IntPtr.Zero) Register(hotkeys);
        });
    }

    /// <inheritdoc />
    public void Release()
    {
        Run(() =>
        {
            _wanted = null;
            UnregisterAll();
        });
    }

    /// <summary>
    /// Tuş şu an alınabilir mi ("meşgul" uyarısı için): 0x43FF kimliğiyle kısa süre alınıp bırakılır. Nino kendi
    /// kısayollarını tutuyorsa (Ayarlar tuş beklerken tutmaz) bunlar da "meşgul" görünür.
    /// </summary>
    public bool IsFree(HotkeyKey key)
    {
        var free = false;
        Run(() =>
        {
            if (_hwnd == IntPtr.Zero) return;
            free = RegisterHotKey(_hwnd, HotkeyIds.Probe, HotkeyIds.Modifiers(key.Modifiers), (uint)key.VirtualKey);
            if (free) UnregisterHotKey(_hwnd, HotkeyIds.Probe);
        });
        return free;
    }

    void Register(IReadOnlyList<ResolvedHotkey> table)
    {
        UnregisterAll();
        var failed = new List<HotkeyKey>();
        foreach (var h in table)
        {
            var id = HotkeyIds.For(h.Index);
            if (RegisterHotKey(_hwnd, id, HotkeyIds.Modifiers(h.Key.Modifiers), (uint)h.Key.VirtualKey)) _held[id] = h.Action;
            else failed.Add(h.Key);
        }
        if (_failures.Update(failed) is { } line) log?.Invoke(line);
    }

    void UnregisterAll()
    {
        if (_hwnd != IntPtr.Zero)
            foreach (var id in _held.Keys) UnregisterHotKey(_hwnd, id);
        _held.Clear();
    }

    IntPtr Hook(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (msg != HotkeyIds.WmHotkey) return IntPtr.Zero;
        var id = wParam.ToInt32();
        if (!_held.TryGetValue(id, out var action)) return IntPtr.Zero;
        handled = true;
        try { _pressed?.Invoke(action); } catch (Exception) { }
        return IntPtr.Zero;
    }

    void Run(Action a)
    {
        if (dispatcher.CheckAccess()) a();
        else dispatcher.Invoke(a);
    }

    /// <inheritdoc />
    public void Dispose() => Detach();
}
