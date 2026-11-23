// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using Nino.App.Strings;
using Nino.Core.Settings;
using Nino.Core.Text;
using Nino.Shell;
using Nino.Shell.Panels;

namespace Nino.App.Views;

/// <summary>
/// §9 Kısayollar: her işin iki yuvası; bir yuvaya tıklayıp yeni tuşlara basılır (Geri silme kaldırır, Esc vazgeçer).
/// Kayıt sürerken genel kısayollar bırakılır ve pencereye gelen her tuş buraya gelir.
/// </summary>
internal sealed class ShortcutsSection(SettingsWindow host) : SettingsSection(host)
{
    readonly Dictionary<(HotkeyAction Action, int Slot), Button> _buttons = [];
    (HotkeyAction Action, int Slot)? _waiting;
    TextBlock? _info;
    TextBlock? _error;

    public override SettingsPage Page => SettingsPage.Shortcuts;

    protected override void Build()
    {
        AddHeader();
        var body = new StackPanel();
        body.Children.Add(Ui.Hint(L.Get("settings.shortcuts.intro")).At(0, 0, 0, 16));
        var grid = new Grid();
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var row = 0;
        foreach (var action in ShortcutText.DisplayOrder)
        {
            grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            var name = Ui.Body(L.Get(ShortcutText.ActionKey(action))).At(0, 0, 16, 8);
            name.VerticalAlignment = VerticalAlignment.Center;
            Grid.SetRow(name, row);
            grid.Children.Add(name);
            for (var slot = 0; slot < 2; slot++)
            {
                var key = (action, slot);
                var button = Ui.Button("").At(slot == 0 ? 0 : 8, 0, 0, 8);
                button.MinWidth = 160;
                button.Click += (_, _) => Toggle(key);
                button.LostKeyboardFocus += (_, _) =>
                {
                    if (_waiting == key) Release();
                };
                Grid.SetRow(button, row);
                Grid.SetColumn(button, slot + 1);
                grid.Children.Add(button);
                _buttons[key] = button;
            }
            row++;
        }
        body.Children.Add(grid);
        _info = Ui.Hint("").At(0, 12, 0, 0).Shown(false);
        _error = Ui.Error().At(0, 12, 0, 0).Shown(false);
        body.Children.Add(_info);
        body.Children.Add(_error);
        body.Children.Add(Ui.Button(L.Get("settings.restoreDefaults"), () =>
        {
            Release();
            HideLines();
            Write(s => s.Hotkeys = []);
            UpdateButtons();
        }).At(0, 16, 0, 0));
        body.Children.Add(Ui.Hint(L.Get("settings.shortcuts.workOnlyWhileTranslating")).At(0, 12, 0, 0));
        AddCard(Ui.Card(null, body));
        UpdateButtons();
    }

    void HideLines()
    {
        _info?.Shown(false);
        _error?.Shown(false);
    }

    void UpdateButtons()
    {
        var bindings = C.Settings.Hotkeys;
        foreach (var ((action, slot), button) in _buttons)
        {
            if (_waiting == (action, slot))
            {
                button.Content = L.Get("settings.shortcuts.pressKeys");
                continue;
            }
            var key = Hotkeys.KeyFor(bindings, action, slot);
            button.Content = key is null ? L.Get("settings.shortcuts.notSet") : Hotkeys.DisplayName(key);
        }
    }

    void Toggle((HotkeyAction, int) key)
    {
        if (_waiting == key)
        {
            Release();
            return;
        }
        Release();
        HideLines();
        _waiting = key;
        C.WaitingForHotkey = true;
        Host.Capturing = this;
        UpdateButtons();
        _buttons[key].Focus();
    }

    void Release()
    {
        if (_waiting is null) return;
        _waiting = null;
        if (Host.Capturing == this) Host.Capturing = null;
        C.WaitingForHotkey = false;
        UpdateButtons();
    }

    /// <summary>Kayıt sırasında pencereye gelen tuş (pencere olayı yutar).</summary>
    public void CaptureKey(KeyEventArgs e)
    {
        if (_waiting is not { } slot) return;
        var key = KeyInput.Real(e);
        var vk = KeyInterop.VirtualKeyFromKey(key);
        var mods = Keyboard.Modifiers;
        var windows = mods.HasFlag(ModifierKeys.Windows) || Keyboard.IsKeyDown(Key.LWin) || Keyboard.IsKeyDown(Key.RWin);
        var step = HotkeyCapture.Decide(vk, mods.HasFlag(ModifierKeys.Control), mods.HasFlag(ModifierKeys.Alt),
            mods.HasFlag(ModifierKeys.Shift), windows);
        switch (step.Kind)
        {
            case CaptureStepKind.Wait:
                return;
            case CaptureStepKind.Cancel:
                Release();
                return;
            case CaptureStepKind.Clear:
                Assign(slot, null);
                return;
            case CaptureStepKind.Error:
                _info!.Shown(false);
                _error!.Text = L.Get(HotkeyCapture.ProblemKey(step.Problem));
                _error.Shown(true);
                return;
            default:
                Assign(slot, step.Key);
                return;
        }
    }

    void Assign((HotkeyAction Action, int Slot) slot, HotkeyKey? key)
    {
        // Genel kısayollar bırakılmışken Windows'a bir kez kaydettirilerek denenir; alınamıyorsa başka uygulama tutuyor.
        var busy = key is not null && !ProbeFree(key);
        var assignment = Hotkeys.Assign(C.Settings.Hotkeys, slot.Action, slot.Slot, key);
        Release();
        Write(s => s.Hotkeys = assignment.Bindings);
        UpdateButtons();
        HideLines();
        if (key is not null && assignment.Displaced is { } moved)
        {
            _info!.Text = L.Format("settings.shortcuts.movedHere", Hotkeys.DisplayName(key), L.Get(ShortcutText.ActionKey(moved)));
            _info.Shown(true);
        }
        if (busy)
        {
            _error!.Text = L.Format("settings.shortcuts.busy", Hotkeys.DisplayName(key!));
            _error.Shown(true);
        }
    }

    bool ProbeFree(HotkeyKey key)
    {
        try
        {
            var handle = new WindowInteropHelper(Host).Handle;
            if (handle == IntPtr.Zero) return true;
            const int probeId = 0xBFF0;
            if (!NativeHotkeys.RegisterHotKey(handle, probeId, (uint)key.Modifiers | 0x4000, (uint)key.VirtualKey)) return false;
            NativeHotkeys.UnregisterHotKey(handle, probeId);
            return true;
        }
        catch (Exception) { return true; }
    }

    public override void ControllerChanged(string property)
    {
        if (property == nameof(NinoController.Settings) && _waiting is null) UpdateButtons();
    }

    public override void Hidden() => Release();

    public override void WindowClosed() => Release();
}

/// <summary>Kısayol "meşgul mü" denemesi için Windows kısayol kaydı.</summary>
internal static class NativeHotkeys
{
    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool RegisterHotKey(IntPtr hWnd, int id, uint modifiers, uint vk);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool UnregisterHotKey(IntPtr hWnd, int id);
}
