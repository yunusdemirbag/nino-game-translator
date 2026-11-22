// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using Nino.App.Strings;
using Nino.Core.Data;
using Nino.Core.Settings;
using Nino.Shell;
using Nino.Shell.Panels;

namespace Nino.App.Views;

/// <summary>§10 OBS katmanı: tarayıcı kaynağı adresleri ve yayın penceresi.</summary>
internal sealed class ObsSection(SettingsWindow host) : SettingsSection(host)
{
    public override string SectionTitle => L.Get("settings.section.obs");

    protected override void Build()
    {
        AddHeader();
        var obs = new StackPanel();
        obs.Children.Add(Ui.Hint(L.Get("settings.obs.hint")).At(0, 0, 0, 12));
        obs.Children.Add(AddressRow(C.ObsLocalAddress));
        obs.Children.Add(Ui.Hint(L.Get("settings.obs.otherComputerHint")).At(0, 12, 0, 0));
        if (C.ObsNetworkAddress is { Length: > 0 } network)
        {
            obs.Children.Add(Ui.Hint(L.Get("settings.obs.networkAddressHint")).At(0, 12, 0, 8));
            obs.Children.Add(AddressRow(network));
        }
        AddCard(Ui.Card(null, obs));

        var stream = new StackPanel();
        stream.Children.Add(Ui.Hint(L.Format("settings.obs.streamWindowHint", L.Get("source.streamWindow.title"))).At(0, 0, 0, 12));
        var background = Ui.Combo(180);
        background.Width = 180;
        background.Items.Add(Ui.Item(StreamBackground.Green, L.Get("source.streamWindow.background.green")));
        background.Items.Add(Ui.Item(StreamBackground.Black, L.Get("source.streamWindow.background.black")));
        background.Items.Add(Ui.Item(StreamBackground.Magenta, L.Get("source.streamWindow.background.magenta")));
        background.SelectTag(C.StreamBackground);
        background.SelectionChanged += (_, _) =>
        {
            if (Guard.Busy || background.SelectedTag() is not StreamBackground b || b == C.StreamBackground) return;
            C.SetStreamBackground(b);
        };
        stream.Children.Add(Ui.Labeled(L.Get("settings.subtitle.background.label"), background, 12).At(0, 0, 0, 12));
        stream.Children.Add(Ui.Button(L.Get("settings.obs.openStreamWindow"), () => SettingsWindow.OpenStreamWindow?.Invoke(Host)));
        stream.Children.Add(Ui.Hint(L.Get("settings.obs.keepOpenHint")).At(0, 12, 0, 0));
        AddCard(Ui.Card(L.Get("settings.obs.streamWindow"), stream));
    }

    static Grid AddressRow(string address)
    {
        var box = new TextBox
        {
            Text = address,
            IsReadOnly = true,
            FontFamily = new FontFamily("Consolas"),
            VerticalContentAlignment = VerticalAlignment.Center,
        };
        Button? copy = null;
        copy = Ui.Button(L.Get("common.copy"), () =>
        {
            if (Ui.Copy(address)) copy!.Content = L.Get("common.copied");
        });
        return Ui.Split(box, copy);
    }
}

/// <summary>§11 Görüntünün kaynağı (konsol türüne göre PlayStation ya da Xbox kartı).</summary>
internal sealed class PictureSourceSection(SettingsWindow host) : SettingsSection(host)
{
    const string RemotePlayDownload = "https://remoteplay.dl.playstation.net/remoteplay/";
    const string ChiakiDownload = "https://github.com/chiaki-ng/chiaki-ng/releases/latest";

    readonly StackPanel _cards = new();
    bool _xbox;
    StackPanel? _windowRows;
    StackPanel? _chosenPane;
    TextBlock? _ps5Hint;
    FrameworkElement? _linkRow;
    ComboBox? _windows;
    TextBlock? _noWindows;
    StackPanel? _installRows;

    public override string SectionTitle => L.Get("settings.section.pictureSource");

    protected override void Build()
    {
        AddHeader();
        Children.Add(_cards);
        Render();
    }

    void Render() => Guard.Run(() =>
    {
        _xbox = C.IsXbox;
        _cards.Children.Clear();
        if (_xbox)
        {
            var toggle = Ui.Toggle(L.Get("settings.source.xboxLegacyFrameRate"));
            toggle.IsChecked = C.Settings.XboxLegacyFrameRate;
            toggle.Checked += (_, _) => Write(s => s.XboxLegacyFrameRate = true);
            toggle.Unchecked += (_, _) => Write(s => s.XboxLegacyFrameRate = false);
            _cards.Children.Add(Ui.Card(null, toggle, Ui.Hint(L.Get("settings.source.xboxLegacyFrameRateHint")).At(0, 6, 0, 0)));
            var quality = Ui.Combo(260);
            quality.Items.Add(Ui.Item(XboxStreamQuality.Auto, L.Get("settings.source.xboxQuality.auto")));
            quality.Items.Add(Ui.Item(XboxStreamQuality.P720, L.Get("settings.source.xboxQuality.p720")));
            quality.SelectTag(C.Settings.XboxStreamQuality);
            quality.SelectionChanged += (_, _) =>
            {
                if (quality.SelectedTag() is XboxStreamQuality q) Write(x => x.XboxStreamQuality = q);
            };
            _cards.Children.Add(Ui.Card(null, Ui.Labeled(L.Get("settings.source.xboxQuality"), quality),
                Ui.Hint(L.Get("settings.source.xboxQualityHint")).At(0, 6, 0, 0)));
            return;
        }
        var s = C.Settings;
        var body = new StackPanel();
        var frame = Ui.Combo(260);
        frame.Items.Add(Ui.Item(FrameSource.Ps5, L.Get("settings.source.frame.ps5")));
        frame.Items.Add(Ui.Item(FrameSource.RemotePlayWindow, L.Get("settings.source.frame.remotePlayWindow")));
        frame.Items.Add(Ui.Item(FrameSource.ChosenWindow, L.Get("settings.source.frame.captureWindow")));
        frame.SelectTag(s.FrameSource);
        frame.SelectionChanged += (_, _) =>
        {
            if (frame.SelectedTag() is not FrameSource f) return;
            Write(x => x.FrameSource = f);
            UpdatePanes();
        };
        body.Children.Add(Ui.Labeled(L.Get("settings.source.readFrom"), frame));

        _windowRows = new StackPanel();
        var app = Ui.Combo(260);
        app.Items.Add(Ui.Item(RemotePlayApp.Automatic, L.Get("settings.source.remotePlayApp.automatic")));
        app.Items.Add(Ui.Item(RemotePlayApp.SonyRemotePlay, "PS Remote Play (Sony)"));
        app.Items.Add(Ui.Item(RemotePlayApp.Chiaki, "chiaki-ng"));
        app.SelectTag(s.RemotePlayApp);
        app.SelectionChanged += (_, _) =>
        {
            if (app.SelectedTag() is RemotePlayApp a) Write(x => x.RemotePlayApp = a);
        };
        _windowRows.Children.Add(Ui.Labeled(L.Get("settings.source.remotePlayApp.label"), app).At(0, 12, 0, 0));
        _windowRows.Children.Add(Ui.Hint(L.Get("settings.source.windowHint")).At(0, 12, 0, 0));
        body.Children.Add(_windowRows);

        _chosenPane = new StackPanel { Margin = new(0, 12, 0, 0) };
        _chosenPane.Children.Add(Ui.Hint(L.Get("settings.source.captureWindowHint")).At(0, 0, 0, 8));
        _windows = Ui.Combo(250);
        _windows.SelectionChanged += (_, _) =>
        {
            if (Guard.Busy || _windows.SelectedTag() is not CaptureWindowItem item) return;
            Write(x => x.CaptureWindow = new CaptureWindowChoice { ProcessName = item.ProcessName, Title = item.Title });
        };
        _chosenPane.Children.Add(Ui.Split(_windows, Ui.Button(L.Get("settings.source.refreshWindows"), FillWindows), 10));
        _noWindows = Ui.Hint(L.Get("settings.source.noWindows")).At(0, 8, 0, 0);
        _chosenPane.Children.Add(_noWindows);
        body.Children.Add(_chosenPane);

        _installRows = new StackPanel();
        body.Children.Add(_installRows);

        _ps5Hint = Ui.Hint(L.Get("settings.source.ps5Hint")).At(0, 12, 0, 0);
        body.Children.Add(_ps5Hint);
        var linkText = Ui.Body(L.Get("settings.source.notLinked"));
        linkText.VerticalAlignment = VerticalAlignment.Center;
        _linkRow = Ui.Split(linkText, Ui.Button(L.Get("settings.source.linkAccount"), () =>
        {
            C.LinkAccount();
            Host.Close();
        }), 12).At(0, 12, 0, 0);
        body.Children.Add(_linkRow);
        _cards.Children.Add(Ui.Card(null, body));
        UpdatePanes();
    });

    void UpdatePanes() => Guard.Run(() =>
    {
        if (_xbox || _windowRows is null) return;
        var s = C.Settings;
        var window = s.FrameSource == FrameSource.RemotePlayWindow;
        var chosen = s.FrameSource == FrameSource.ChosenWindow;
        var ps5 = s.FrameSource == FrameSource.Ps5;
        _windowRows.Shown(window);
        _chosenPane!.Shown(chosen);
        _ps5Hint!.Shown(ps5);
        _linkRow!.Shown(ps5 && (!C.HasAccount || !C.HasConsole));
        _installRows!.Children.Clear();
        if (window)
        {
            _installRows.Children.Add(InstallRow("PS Remote Play (Sony)", RemotePlayApp.SonyRemotePlay,
                "setup.psnAccount.downloadRemotePlay", RemotePlayDownload).At(0, 12, 0, 0));
            _installRows.Children.Add(InstallRow("chiaki-ng", RemotePlayApp.Chiaki, "setup.psnAccount.downloadChiaki", ChiakiDownload)
                .At(0, 8, 0, 0));
        }
        if (chosen) FillWindows();
    });

    FrameworkElement InstallRow(string name, RemotePlayApp app, string downloadKey, string url)
    {
        var label = Ui.Body(name);
        label.VerticalAlignment = VerticalAlignment.Center;
        FrameworkElement right = C.IsRemotePlayAppInstalled(app)
            ? Ui.Hint(L.Get("translation.model.installed"))
            : Ui.Button(L.Get(downloadKey), () => Ui.Open(url));
        right.VerticalAlignment = VerticalAlignment.Center;
        return Ui.Split(label, right);
    }

    void FillWindows() => Guard.Run(() =>
    {
        if (_windows is null) return;
        var (items, selected) = SettingsPanelRules.CaptureWindows(C.VisibleWindows(), C.Settings.CaptureWindow);
        _windows.Items.Clear();
        foreach (var item in items)
        {
            var text = item.NotOpen
                ? L.Format("settings.source.windowNotOpen", item.Title, item.ProcessName)
                : $"{item.Title} ({item.ProcessName})";
            _windows.Items.Add(Ui.Item(item, text));
        }
        _windows.SelectedIndex = selected;
        _noWindows!.Shown(items.Count == 0);
    });

    public override void Shown()
    {
        if (C.IsXbox != _xbox) Render();
        else if (!_xbox && C.Settings.FrameSource == FrameSource.ChosenWindow) FillWindows();
    }

    public override void ControllerChanged(string property)
    {
        if (property is nameof(NinoController.IsXbox)) Render();
        else if (property is nameof(NinoController.HasAccount) or nameof(NinoController.HasConsole) && _linkRow is not null)
            _linkRow.Shown(C.Settings.FrameSource == FrameSource.Ps5 && (!C.HasAccount || !C.HasConsole));
    }
}

/// <summary>§12 PS5 oturum şifresi (yalnız PlayStation).</summary>
internal sealed class PasscodeSection(SettingsWindow host) : SettingsSection(host)
{
    readonly StackPanel _body = new();

    public override string SectionTitle => L.Get("settings.section.passcode");

    public override bool Available => !C.IsXbox;

    protected override void Build()
    {
        AddHeader();
        AddCard(Ui.Card(null, _body));
        Render();
    }

    void Render()
    {
        _body.Children.Clear();
        _body.Children.Add(Ui.Hint(L.Get("settings.passcode.hint")).At(0, 0, 0, 12));
        var error = Ui.Error(L.Get("settings.passcode.error")).At(0, 8, 0, 0).Shown(false);
        if (!C.HasLoginPasscode)
        {
            var box = Ui.Secret(160, 4);
            AutomationNames.Set(box, L.Get("settings.section.passcode"));
            var save = Ui.Button(L.Get("common.save"), () =>
            {
                if (C.SaveLoginPasscode(box.Password))
                {
                    box.Clear();
                    Render();
                }
                else error.Shown(true);
            }).At(12, 0, 0, 0);
            _body.Children.Add(Ui.Row(box, save));
        }
        else
        {
            var saved = Ui.Success(L.Get("settings.passcode.saved"));
            saved.VerticalAlignment = VerticalAlignment.Center;
            _body.Children.Add(Ui.Split(saved, Ui.Button(L.Get("settings.passcode.remove"), () =>
            {
                C.RemoveLoginPasscode();
                Render();
            })));
        }
        _body.Children.Add(error);
    }
}

/// <summary>§13 Sağlık: gömülü sayfa (yalnız görünürken yenilenir).</summary>
internal sealed class SystemHealthSection(SettingsWindow host) : SettingsSection(host)
{
    public override string SectionTitle => L.Get("settings.section.systemHealth");

    protected override void Build()
    {
        AddHeader();
        Children.Add(new SystemHealthPage(C));
    }
}

/// <summary>§14 Nino Hakkında: Hakkında, sorun bildirme, Nino'ya Sor.</summary>
internal sealed class AboutSection(SettingsWindow host) : SettingsSection(host)
{
    public override string SectionTitle => L.Get("settings.section.about");

    protected override void Build()
    {
        AddHeader();
        var wrap = new WrapPanel();
        wrap.Children.Add(Ui.Button(L.Get("settings.section.about"), () => ShellWindows.Show(ShellWindowKind.About, Host, C)).At(0, 0, 12, 0));
        wrap.Children.Add(Ui.Button(L.Get("settings.about.reportProblem"), () => ReportProblemWindow.Open(C, Host)).At(0, 0, 12, 0));
        wrap.Children.Add(Ui.Button(L.Get("home.robot.askNino"), () => ShellWindows.Show(ShellWindowKind.AskNino, Application.Current?.MainWindow ?? Host, C)));
        AddCard(Ui.Card(null, wrap));
    }
}

/// <summary>§15 Sıfırla: TV'den itibaren ya da her şeyi.</summary>
internal sealed class ResetSection(SettingsWindow host) : SettingsSection(host)
{
    public override string SectionTitle => L.Get("common.reset");

    protected override void Build()
    {
        AddHeader();
        var fromTv = Ui.Button(L.Get("settings.reset.fromTv"), () =>
        {
            C.ResetFromTv();
            Host.Close();
        });
        fromTv.Padding = new(16, 0, 16, 0);
        fromTv.Margin = new(0, 0, 12, 0);
        var everything = Ui.Button(L.Get("settings.reset.everything"), () =>
        {
            var answer = MessageBox.Show(Host, L.Get("settings.reset.confirmMessage"), L.Get("settings.reset.confirmTitle"),
                MessageBoxButton.OKCancel, MessageBoxImage.Warning, MessageBoxResult.Cancel);
            if (answer != MessageBoxResult.OK) return;
            C.ResetEverything();
            Host.Close();
        });
        everything.Padding = new(16, 0, 16, 0);
        everything.Fg("dangerBrush");
        AddCard(Ui.Card(null, Ui.Secondary(L.Get("settings.reset.description")).At(0, 0, 0, 16), Ui.Wrap(fromTv, everything)));
    }
}
