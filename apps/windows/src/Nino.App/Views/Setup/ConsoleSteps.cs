// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.IO;
using System.Windows;
using System.Windows.Controls;
using Nino.App.Strings;
using Nino.Core.Data;
using Nino.Core.Logging;
using Nino.Shell;

namespace Nino.App.Views.Setup;

/// <summary>PS5'i bağla (kurulum.md §6): arama, elle adres, sekiz rakamlı kod, eşleştirme ve kendiliğinden ilerleme.</summary>
internal sealed class Ps5PairStep : StepPage
{
    readonly TextBlock _pairedName = SetupUi.Text("", "Text.Success", SetupUi.Bottom(16));
    readonly Button _search;
    readonly TextBlock _notFound = SetupUi.Key("setup.ps5.notFound", "Text.Callout", SetupUi.Bottom(8));
    readonly TextBox _manualHost = new() { Width = 320, HorizontalAlignment = HorizontalAlignment.Left };
    readonly StackPanel _found = new();
    readonly TextBox _code = new()
    {
        Width = 240,
        HorizontalAlignment = HorizontalAlignment.Left,
        FontSize = 22,
        FontWeight = FontWeights.SemiBold,
        MinHeight = 52,
        MaxLength = 16,
    };
    readonly Button _connect;
    readonly TextBlock _working = SetupUi.Key("setup.ps5.connecting", "Text.Callout", SetupUi.Top(12));
    readonly TextBlock _paired = SetupUi.Text("", "Text.Success", SetupUi.Top(12));
    readonly TextBlock _error = SetupUi.Text("", "Text.Error", SetupUi.Top(12));
    readonly Button _showLog;
    readonly string _group = "ps5-" + Guid.NewGuid().ToString("N");

    // Güvenlik duvarı kartının yeri (ana-ekran.md §3.5; kart ShellWindows.CreateFirewallCard ile gelir, yoksa boş).
    readonly ContentControl _firewall = new() { Focusable = false, Margin = SetupUi.Top(12) };

    string? _selected;
    bool _busy;

    public Ps5PairStep(NinoController controller) : base(controller)
    {
        _search = SetupUi.Button(L.Get("tv.search.again"), ButtonKind.Secondary, (_, _) => Fire.AndForget(SearchAsync));
        _connect = SetupUi.Button(L.Get("common.connect"), ButtonKind.Primary, (_, _) => Fire.AndForget(ConnectAsync), SetupUi.Top(16));
        _showLog = SetupUi.Button(L.Get("setup.showLogFile"), ButtonKind.Secondary, (_, _) => ShowLog(), SetupUi.Top(8));
        _code.SetResourceReference(Control.FontFamilyProperty, "font.text");
        _code.TextChanged += (_, _) =>
        {
            if (!_busy && _code.Text.Length > 0) _connect.IsEnabled = true;
        };
        SetupUi.OnEnter(_code, ConnectIfReady);
        SetupUi.OnEnter(_manualHost, ConnectIfReady);
        _notFound.Visibility = Visibility.Collapsed;
        _manualHost.Visibility = Visibility.Collapsed;
        _working.Visibility = Visibility.Collapsed;
        _paired.Visibility = Visibility.Collapsed;
        _showLog.Visibility = Visibility.Collapsed;

        var card = SetupUi.Card(SetupUi.Stack(
            SetupUi.TopRow(SetupUi.Key("status.console.titlePs5", "Text.Headline"), _search, SetupUi.Bottom(12)),
            _notFound, _manualHost, _found));

        Layout(L.Get("home.toggle.connectPs5"), L.Get("setup.ps5.description"), SetupUi.Stack(
            _pairedName, card,
            SetupUi.Key("setup.ps5.codeLabel", "Text.Callout", SetupUi.M(0, 20, 0, 6)),
            _code, _connect, _working, _paired, _error, _showLog, _firewall));
        _firewall.Content = ShellWindows.CreateFirewallCard(controller);
        RenderName();
        RenderError();
    }

    protected override void OnFirstShown() => Fire.AndForget(SearchAsync);

    protected override void OnChanged(string property)
    {
        if (property is nameof(NinoController.HasConsole) or nameof(NinoController.ConsoleName)) RenderName();
        if (property == nameof(NinoController.PairError)) RenderError();
    }

    void RenderName()
    {
        SetupUi.SetText(_pairedName, C.HasConsole ? (C.ConsoleName is { Length: > 0 } n ? n : "PS5") : null);
    }

    void RenderError()
    {
        SetupUi.SetText(_error, C.PairError);
        SetupUi.Show(_showLog, !string.IsNullOrEmpty(C.PairError));
    }

    async Task SearchAsync()
    {
        _search.IsEnabled = false;
        _found.Children.Clear();
        try { await C.SearchPs5Async(); }
        finally { _search.IsEnabled = true; }
        var list = C.FoundConsoles;
        if (_selected is null && list.Count > 0) _selected = list[0].Host;
        _found.Children.Clear();
        foreach (var ps5 in list)
        {
            var host = ps5.Host;
            var radio = new RadioButton
            {
                Content = $"{ps5.Name} — {ps5.Host}",
                GroupName = _group,
                IsChecked = host == _selected,
            };
            radio.Checked += (_, _) => _selected = host;
            _found.Children.Add(radio);
        }
        SetupUi.Show(_notFound, list.Count == 0);
        SetupUi.Show(_manualHost, list.Count == 0);
    }

    string Address => _selected ?? _manualHost.Text.Trim();

    void ConnectIfReady()
    {
        if (!_busy && _connect.IsEnabled) Fire.AndForget(ConnectAsync);
    }

    async Task ConnectAsync()
    {
        if (_busy) return;
        _busy = true;
        _connect.IsEnabled = false;
        SetupUi.Show(_working, true);
        SetupUi.Show(_paired, false);
        bool ok;
        try { ok = await C.PairPs5Async(Address, _code.Text); }
        finally
        {
            _busy = false;
            SetupUi.Show(_working, false);
        }
        _connect.IsEnabled = !ok;
        RenderError();
        if (!ok) return;
        _paired.Text = L.Format("setup.ps5.paired", C.PairedMessage);
        SetupUi.Show(_paired, true);
        _code.Text = "";
        _connect.IsEnabled = false; // yeni kod yazılınca açılır
        _paired.BringIntoView();
        await Task.Delay(1000);
        if (IsLoaded) C.ContinueAfterPairing();
    }

    void ShowLog()
    {
        var path = C.RemotePlayLogPath ?? Path.Combine(SetupUi.DataFolder, LogNames.RemotePlay);
        SetupUi.ShowInExplorer(path);
    }
}

/// <summary>Ev Xbox'ını seç (kurulum.md §7).</summary>
internal sealed class XboxConsoleStep : StepPage
{
    readonly Button _find;
    readonly TextBlock _status = SetupUi.Text("", "Text.Callout", SetupUi.M(0, 16, 0, 8));
    readonly StackPanel _list = new();
    readonly TextBlock _error = SetupUi.Text("", "Text.Error", SetupUi.Top(12));
    readonly string _group = "xbox-" + Guid.NewGuid().ToString("N");

    public XboxConsoleStep(NinoController controller) : base(controller)
    {
        _find = SetupUi.Button(L.Get("setup.xbox.findConsoles"), ButtonKind.Primary, (_, _) => Fire.AndForget(FindAsync));
        SetupUi.SetText(_status, null);
        SetupUi.SetText(_error, null);
        Layout(L.Get("setup.xbox.title"), L.Get("setup.xbox.description"), SetupUi.Stack(_find, _status, _list, _error));
    }

    protected override void OnFirstShown() => Fire.AndForget(FindAsync);

    async Task FindAsync()
    {
        if (!_find.IsEnabled) return;
        _find.IsEnabled = false;
        SetupUi.SetText(_error, null);
        SetupUi.SetText(_status, L.Get("setup.xbox.searching"));
        _list.Children.Clear();
        try
        {
            await C.FindXboxConsolesAsync();
            if (C.XboxError is { Length: > 0 } error)
            {
                SetupUi.SetText(_error, error);
                SetupUi.SetText(_status, L.Get("setup.xbox.loadFailed"));
                return;
            }
            var consoles = C.XboxConsoles;
            SetupUi.SetText(_status, L.Get(consoles.Count == 0 ? "setup.xbox.noneFound" : "setup.xbox.chooseOne"));
            foreach (var console in consoles) _list.Children.Add(Radio(console));
        }
        finally { _find.IsEnabled = true; }
    }

    RadioButton Radio(StoredXboxConsole console)
    {
        var text = console.StreamingEnabled
            ? L.Format("source.common.messageWithDetail", console.Name, console.Model)
            : L.Format("setup.xbox.consoleItemRemoteOff", console.Name, console.Model);
        var radio = new RadioButton
        {
            Content = text,
            GroupName = _group,
            IsEnabled = console.StreamingEnabled,
            IsChecked = C.XboxConsole?.Id == console.Id,
            Margin = new Thickness(0, 4, 0, 12),
        };
        radio.Checked += (_, _) => C.SelectXboxConsole(console);
        return radio;
    }
}
