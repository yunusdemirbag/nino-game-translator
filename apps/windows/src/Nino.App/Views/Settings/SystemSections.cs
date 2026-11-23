// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using Nino.App.Controls;
using Nino.App.Strings;
using Nino.Core.Data;
using Nino.Core.Settings;
using Nino.Shell;
using Nino.Shell.Panels;

namespace Nino.App.Views;

/// <summary>OBS katmanı (Mac'le aynı): tarayıcı kaynağı adresleri ve video penceresi kartı.</summary>
internal sealed class ObsSection(SettingsWindow host) : SettingsSection(host)
{
    Button? _open;

    public override SettingsPage Page => SettingsPage.Obs;

    protected override void Build()
    {
        AddHeader();
        var obs = new StackPanel();
        obs.Children.Add(Ui.Hint(L.Get("settings.obs.hint")).At(0, 0, 0, 12));
        obs.Children.Add(AddressRow(C.ObsLocalAddress));
        obs.Children.Add(Ui.Hint(L.Get("settings.obs.otherComputerHint")).At(0, 12, 0, 0));
        if (C.ObsNetworkAddress is { Length: > 0 } network)
        {
            obs.Children.Add(Ui.Hint(L.Get("settings.obs.noLocalhost")).At(0, 12, 0, 8));
            obs.Children.Add(AddressRow(network));
        }
        AddCard(Ui.Card(null, obs));

        var stream = new StackPanel();
        stream.Children.Add(Ui.Hint(L.Get("settings.obs.streamHint")).At(0, 0, 0, 12));
        stream.Children.Add(Ui.Caption(L.Get("settings.obs.background")).Fg("textSecondaryBrush").At(0, 0, 0, 8));
        var backgrounds = new[] { StreamBackground.Green, StreamBackground.Black, StreamBackground.Magenta };
        var bar = new SegmentBar(true, L.Get("settings.obs.green"), L.Get("settings.obs.black"), L.Get("settings.obs.magenta"))
        {
            Margin = new(0, 0, 0, 12),
        };
        bar.Selected = Array.IndexOf(backgrounds, C.StreamBackground);
        bar.Changed += i =>
        {
            if (backgrounds[i] != C.StreamBackground) C.SetStreamBackground(backgrounds[i]);
        };
        stream.Children.Add(bar);
        _open = Ui.Button(L.Get(StreamOpen ? "settings.obs.close" : "settings.obs.open"), ToggleStream);
        _open.HorizontalAlignment = HorizontalAlignment.Left;
        stream.Children.Add(_open);
        stream.Children.Add(Ui.Hint(L.Get("settings.obs.keepOpen")).At(0, 12, 0, 0));
        AddCard(Ui.Card(L.Get("settings.obs.stream"), stream));
    }

    static bool StreamOpen => Application.Current?.Windows.OfType<StreamWindow>().Any(w => w.IsVisible) == true;

    void ToggleStream()
    {
        if (StreamOpen)
        {
            foreach (var w in Application.Current!.Windows.OfType<StreamWindow>().ToList()) w.Close();
        }
        else SettingsWindow.OpenStreamWindow?.Invoke(Host);
        Dispatcher.BeginInvoke(() =>
        {
            if (_open is not null) _open.Content = L.Get(StreamOpen ? "settings.obs.close" : "settings.obs.open");
        });
    }

    public override void Shown()
    {
        if (_open is not null) _open.Content = L.Get(StreamOpen ? "settings.obs.close" : "settings.obs.open");
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
        copy = Ui.Button(L.Get("settings.obs.copy"), () =>
        {
            if (Ui.Copy(address)) copy!.Content = L.Get("settings.obs.copied");
        });
        return Ui.Split(box, copy, 8);
    }
}

/// <summary>
/// Bağlantı sayfasında bağlantı kartının altındaki Windows'a özgü kart (Mac'te karşılığı yok): Xbox'ta yayın görüntüsü
/// (1080p/720p) ve eski kare hızı; PS5'te görüntünün kaynağı (PS5, bu bilgisayardaki Remote Play penceresi ya da seçilen
/// pencere), hangi Remote Play uygulaması, pencere listesi ve uygulama indirme satırları.
/// </summary>
internal sealed class PictureSourcePart : StackPanel
{
    readonly NinoController C;
    readonly Window Host;
    readonly LoadGuard Guard = new();

    public PictureSourcePart(NinoController controller, Window host)
    {
        C = controller;
        Host = host;
        Children.Add(_cards);
        Render();
    }

    void Write(Action<AppSettings> change)
    {
        if (Guard.Busy) return;
        var s = C.Settings;
        change(s);
        C.UpdateSettings(s);
    }

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

    bool IsXbox => C.IsXbox || C.Settings.GameConsole == GameConsole.Xbox;

    void Render() => Guard.Run(() =>
    {
        _xbox = IsXbox;
        _cards.Children.Clear();
        if (_xbox)
        {
            var toggle = Ui.Toggle(L.Get("settings.source.xboxLegacyFrameRate"));
            toggle.IsChecked = C.Settings.XboxLegacyFrameRate;
            toggle.Checked += (_, _) => Write(s => s.XboxLegacyFrameRate = true);
            toggle.Unchecked += (_, _) => Write(s => s.XboxLegacyFrameRate = false);
            var legacyHint = Ui.Hint(L.Get("settings.source.xboxLegacyFrameRateHint")).At(0, 6, 0, 0);
            var quality = Ui.Combo(260);
            quality.Items.Add(Ui.Item(XboxStreamQuality.Auto, L.Get("settings.source.xboxQuality.auto")));
            quality.Items.Add(Ui.Item(XboxStreamQuality.P720, L.Get("settings.source.xboxQuality.p720")));
            quality.SelectTag(C.Settings.XboxStreamQuality);
            quality.SelectionChanged += (_, _) =>
            {
                if (quality.SelectedTag() is XboxStreamQuality q) Write(x => x.XboxStreamQuality = q);
            };
            // Xbox: 720p ayarı ve eski kare hızı tek kartta ("Xbox", çevrilmez).
            _cards.Children.Add(Ui.Card("Xbox", Ui.Labeled(L.Get("settings.source.xboxQuality"), quality),
                Ui.Hint(L.Get("settings.source.xboxQualityHint")).At(0, 6, 0, 16), toggle, legacyHint));
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
        _cards.Children.Add(Ui.Card(L.Get("settings.source.readFrom"), body));
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

    public void Shown()
    {
        if (IsXbox != _xbox) Render();
        else if (!_xbox && C.Settings.FrameSource == FrameSource.ChosenWindow) FillWindows();
    }

    public void ControllerChanged(string property)
    {
        if (property is nameof(NinoController.IsXbox) or nameof(NinoController.Settings) && IsXbox != _xbox) Render();
        else if (property is nameof(NinoController.HasAccount) or nameof(NinoController.HasConsole) && _linkRow is not null)
            _linkRow.Shown(C.Settings.FrameSource == FrameSource.Ps5 && (!C.HasAccount || !C.HasConsole));
    }
}


/// <summary>PS5 şifre bölümü (Mac'le aynı): ipucu, gizli alan + Kaydet ya da kayıtlı satırı + Şifreyi sil.</summary>
internal sealed class PasscodeSection(SettingsWindow host) : SettingsSection(host)
{
    readonly StackPanel _body = new();

    public override SettingsPage Page => SettingsPage.Passcode;

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
        if (!C.HasLoginPasscode)
        {
            var invalid = Ui.Hint(L.Get("settings.passcode.invalid")).At(0, 8, 0, 0).Shown(false);
            var box = Ui.Secret(220, 4);
            AutomationNames.Set(box, L.Get("settings.passcode.placeholder"));
            Button? save = null;
            void Save()
            {
                if (box.Password.Trim().Length == 0) return;
                if (C.SaveLoginPasscode(box.Password))
                {
                    box.Clear();
                    Render();
                }
                else invalid.Shown(true);
            }
            save = Ui.Button(L.Get("settings.passcode.save"), Save).At(8, 0, 0, 0);
            save.IsEnabled = false;
            box.PasswordChanged += (_, _) => save.IsEnabled = box.Password.Trim().Length > 0;
            box.Tag = (Action)Save;
            _body.Children.Add(Ui.Row(Ui.SecretWithPlaceholder(box, L.Get("settings.passcode.placeholder")), save));
            _body.Children.Add(invalid);
        }
        else
        {
            var saved = Ui.Body(L.Get("settings.passcode.saved"));
            saved.VerticalAlignment = VerticalAlignment.Center;
            _body.Children.Add(Ui.Split(saved, Ui.Button(L.Get("settings.passcode.remove"), () =>
            {
                C.RemoveLoginPasscode();
                Render();
            })));
        }
    }
}

/// <summary>
/// Güncellemeler (Mac'le aynı): logo, "Nino Game Translator", sürüm, "Güncellemelere bak"; altında durum (yeni sürüm
/// hazır + İndir, indiriliyor + ilerleme, en yenisi, hata) ve kendiliğinden güncelleme ipucu. Durum denetleyicinin
/// <see cref="NinoController.AppUpdate"/>'ından gelir (Hakkında'daki denetimle aynı).
/// </summary>
internal sealed class UpdatesSection(SettingsWindow host) : SettingsSection(host)
{
    readonly StackPanel _status = new();
    Button? _check;

    public override SettingsPage Page => SettingsPage.Updates;

    protected override void Build()
    {
        AddHeader();
        var logo = new LogoBox { Width = 44, Height = 44, VerticalAlignment = VerticalAlignment.Center };
        var name = Ui.Headline("Nino Game Translator");
        var version = Ui.Hint(L.Format("settings.updates.version", AboutWindow.Version(C)));
        var text = Ui.Column(name, version.At(0, 2, 0, 0));
        text.VerticalAlignment = VerticalAlignment.Center;
        text.Margin = new(12, 0, 12, 0);
        _check = Ui.Button(L.Get("settings.updates.check"), () => _ = C.CheckForUpdatesNowAsync());
        _check.VerticalAlignment = VerticalAlignment.Center;
        var head = new DockPanel();
        DockPanel.SetDock(logo, Dock.Left);
        DockPanel.SetDock(_check, Dock.Right);
        head.Children.Add(logo);
        head.Children.Add(_check);
        head.Children.Add(text);
        _status.Margin = new(0, 12, 0, 0);
        AddCard(Ui.Card(null, head, _status, Ui.Hint(L.Get("settings.updates.auto")).At(0, 12, 0, 0)));
        Render();
    }

    void Render()
    {
        if (_check is null) return;
        var state = C.AppUpdate;
        var checking = C.CheckingForUpdates;
        _check.Content = L.Get(checking ? "settings.updates.checking" : "settings.updates.check");
        _check.IsEnabled = !checking && state.Kind != AppUpdateKind.Downloading;
        _status.Children.Clear();
        switch (state.Kind)
        {
            case AppUpdateKind.Available:
                var ready = Ui.Body(L.Format("settings.updates.ready", state.Version ?? ""));
                ready.FontWeight = FontWeights.Bold;
                ready.VerticalAlignment = VerticalAlignment.Center;
                _status.Children.Add(Ui.Split(ready, Ui.Primary(L.Get("settings.updates.download"), () => _ = C.InstallUpdateAsync())));
                _status.Children.Add(Ui.Hint(L.Get("settings.updates.installHint")).At(0, 8, 0, 0));
                break;
            case AppUpdateKind.Downloading:
                _status.Children.Add(Ui.Hint(L.Format("settings.updates.downloading", state.Version ?? "")));
                _status.Children.Add(new ProgressBar { Height = 6, Maximum = 1, Value = state.Progress, Margin = new(0, 8, 0, 0) });
                break;
            case AppUpdateKind.UpToDate:
                _status.Children.Add(Ui.Success(L.Get("settings.updates.upToDate")));
                break;
            case AppUpdateKind.Failed:
                _status.Children.Add(Ui.Error(L.Get("settings.updates.failed")));
                break;
        }
        _status.Shown(_status.Children.Count > 0);
    }

    public override void ControllerChanged(string property)
    {
        if (property is nameof(NinoController.AppUpdate) or nameof(NinoController.CheckingForUpdates)
            or nameof(NinoController.UpdateVersion) or nameof(NinoController.Updating) or nameof(NinoController.UpdateProgress))
            Render();
    }
}

/// <summary>Sıfırla (Mac'le aynı): açıklama, "Kurulumu TV adımından yinele" ve onaylı "Tümünü sıfırla".</summary>
internal sealed class ResetSection(SettingsWindow host) : SettingsSection(host)
{
    public override SettingsPage Page => SettingsPage.Reset;

    protected override void Build()
    {
        AddHeader();
        var fromTv = Ui.Button(L.Get("settings.reset.fromTV"), () =>
        {
            C.ResetFromTv();
            Host.Close();
        });
        fromTv.Margin = new(0, 0, 12, 0);
        var everything = Ui.Button(L.Get("settings.reset.everything"), () =>
        {
            var answer = MessageBox.Show(Host, L.Get("settings.reset.confirmMessage"), L.Get("settings.reset.confirmTitle"),
                MessageBoxButton.OKCancel, MessageBoxImage.Warning, MessageBoxResult.Cancel);
            if (answer != MessageBoxResult.OK) return;
            C.ResetEverything();
            Host.Close();
        }, "Button.Danger");
        AddCard(Ui.Card(null, Ui.Secondary(L.Get("settings.reset.hint")).At(0, 0, 0, 16), Ui.Wrap(fromTv, everything)));
    }
}

/// <summary>Hakkında (Mac'teki gibi Ayarlar'ın içinde bir bölüm): Hakkında penceresinin içeriği, 560 genişlikte.</summary>
internal sealed class AboutSection(SettingsWindow host) : SettingsSection(host)
{
    public override SettingsPage Page => SettingsPage.About;

    protected override void Build() => Children.Add(new AboutContent(C));
}
