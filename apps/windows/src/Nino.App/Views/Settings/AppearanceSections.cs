// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Shapes;
using Nino.App.Controls;
using Nino.App.Strings;
using Nino.App.Theme;
using Nino.Core.Settings;
using Nino.Core.Tv;
using Nino.Shell;
using Nino.Shell.Panels;
using Nino.Shell.Setup;

namespace Nino.App.Views;

/// <summary>Gizli Arayüz bölümü (Mac'te de gizli): ana ekran biçimi ve görünüm (tema).</summary>
internal sealed class InterfaceSection(SettingsWindow host) : SettingsSection(host)
{
    Button? _livingRoom;
    Button? _toggle;

    public override SettingsPage Page => SettingsPage.Interface;

    protected override void Build()
    {
        AddHeader();
        var grid = new Grid();
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        _livingRoom = HomeChoice(LivingRoomPreview(), "settings.home.livingRoom.name", "settings.home.livingRoom.description",
            HomeStyle.LivingRoom);
        _livingRoom.Margin = new(0, 0, 8, 0);
        _toggle = HomeChoice(TogglePreview(), "settings.home.toggle.name", "settings.home.toggle.description", HomeStyle.Toggle);
        _toggle.Margin = new(8, 0, 0, 0);
        Grid.SetColumn(_toggle, 1);
        grid.Children.Add(_livingRoom);
        grid.Children.Add(_toggle);
        AddCard(Ui.Card(L.Get("settings.home.title"), grid));
        MarkHome();

        var combo = Ui.Combo(200);
        combo.Items.Add(Ui.Item(Appearance.Dark, L.Get("settings.appearance.dark")));
        combo.Items.Add(Ui.Item(Appearance.Light, L.Get("settings.appearance.light")));
        combo.Items.Add(Ui.Item(Appearance.System, L.Get("settings.appearance.system")));
        combo.SelectTag(C.Settings.Appearance);
        combo.SelectionChanged += (_, _) =>
        {
            if (Guard.Busy || combo.SelectedTag() is not Appearance a) return;
            Write(s => s.Appearance = a);
            ThemeManager.Apply(a);
        };
        AddCard(Ui.Card(null, Ui.Labeled(L.Get("settings.appearance.label"), combo)));
    }

    Button HomeChoice(UIElement preview, string nameKey, string descriptionKey, HomeStyle style)
    {
        var content = new StackPanel();
        content.Children.Add(preview);
        content.Children.Add(new TextBlock { Text = L.Get(nameKey), FontWeight = FontWeights.SemiBold, Margin = new(0, 8, 0, 0), TextWrapping = TextWrapping.Wrap });
        content.Children.Add(Ui.Caption(L.Get(descriptionKey)));
        var button = new Button
        {
            Content = content,
            Padding = new(10),
            HorizontalAlignment = HorizontalAlignment.Stretch,
            HorizontalContentAlignment = HorizontalAlignment.Stretch,
            VerticalContentAlignment = VerticalAlignment.Top,
        }.Styled("Button.Secondary");
        AutomationNames.Set(button, L.Get(nameKey));
        button.Click += (_, _) =>
        {
            Write(s => s.HomeStyle = style);
            MarkHome();
        };
        return button;
    }

    void MarkHome()
    {
        var style = C.Settings.HomeStyle;
        foreach (var (button, value) in new[] { (_livingRoom, HomeStyle.LivingRoom), (_toggle, HomeStyle.Toggle) })
        {
            if (button is null) continue;
            var on = style == value;
            button.BorderThickness = new(on ? 2 : 1);
            button.Res(Control.BorderBrushProperty, on ? "accentBrush" : "borderBrush");
        }
    }

    static Border PreviewBox(UIElement content) => new()
    {
        Height = 130,
        CornerRadius = new(10),
        Background = Ui.Frozen(Color.FromRgb(0x0A, 0x14, 0x33)),
        Child = content,
        FlowDirection = FlowDirection.LeftToRight,
    };

    UIElement LivingRoomPreview()
    {
        var image = new Image
        {
            Source = new BitmapImage(new Uri(C.IsXbox ? "pack://application:,,,/Assets/living-room-xbox.png"
                : "pack://application:,,,/Assets/living-room.png", UriKind.Absolute)),
            Stretch = Stretch.Uniform,
            Margin = new(12),
        };
        RenderOptions.SetBitmapScalingMode(image, BitmapScalingMode.HighQuality);
        return PreviewBox(image);
    }

    static UIElement TogglePreview()
    {
        var fill = Ui.Frozen(Color.FromRgb(0x5C, 0x6E, 0x99));
        var canvas = new Canvas { Width = 160, Height = 50, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
        var pill = new Rectangle { Width = 150, Height = 40, RadiusX = 20, RadiusY = 20, Fill = fill };
        Canvas.SetLeft(pill, 5);
        Canvas.SetTop(pill, 5);
        var knob = new Ellipse { Width = 50, Height = 50, Fill = fill, StrokeThickness = 1.5, Stroke = Ui.Frozen(Color.FromArgb(0xCC, 0xFF, 0xFF, 0xFF)) };
        canvas.Children.Add(pill);
        canvas.Children.Add(knob);
        return PreviewBox(canvas);
    }

    public override void ControllerChanged(string property)
    {
        if (property == nameof(NinoController.Settings)) MarkHome();
    }
}

/// <summary>
/// Bağlantı (Mac'le aynı): ayrıntılı bağlantı kartı, ardından Windows'a özgü görüntü kaynağı / Xbox kartı, Televizyon
/// bölümü ve Windows Güvenlik Duvarı kartı.
/// </summary>
internal sealed class ConnectionSection(SettingsWindow host) : SettingsSection(host)
{
    PictureSourcePart? _source;
    TvSettingsCard? _tv;

    public override SettingsPage Page => SettingsPage.Connection;

    protected override void Build()
    {
        AddHeader();
        AddCard(new SubtitleOutputCard(C, detailed: true));
        _source = AddCard(new PictureSourcePart(C, Host));
        _tv = AddCard(new TvSettingsCard(C, Host));
        AddCard(new FirewallSettingsCard(C));
    }

    public override void Shown()
    {
        _source?.Shown();
        _tv?.Shown();
    }

    public override void ControllerChanged(string property)
    {
        _source?.ControllerChanged(property);
        _tv?.ControllerChanged(property);
    }
}

/// <summary>
/// Bağlantı › Televizyon (Mac'le aynı): eşli TV ve bağlantı durumu, TV uygulamasının kartı, TV'deki Nino eskiyse
/// "Yeni Sürümü Kur", Android TV'de "Görüntü gelmiyorsa: Katman kipi" (displayMode overlay/inApp) ve "TV kurulumunu aç".
/// </summary>
internal sealed class TvSettingsCard : Card
{
    readonly NinoController _c;
    readonly Window _host;
    readonly StackPanel _body = new();
    readonly LoadGuard _guard = new();
    TvAppCard? _app;

    public TvSettingsCard(NinoController controller, Window host)
    {
        _c = controller;
        _host = host;
        SetResourceReference(StyleProperty, typeof(Card));
        Content = _body;
        Render();
    }

    void Render() => _guard.Run(() =>
    {
        _body.Children.Clear();
        _body.Children.Add(Ui.Caption(L.Get("settings.tv.header")).Fg("textSecondaryBrush").At(0, 0, 0, 8));
        if (_c.Tv is { } tv)
        {
            var dot = new StatusDot { Tone = TvSettingsRules.Tone(_c.ConnectedTvs), VerticalAlignment = VerticalAlignment.Center };
            var name = Ui.Headline(tv.Name).At(8, 0, 0, 0);
            name.VerticalAlignment = VerticalAlignment.Center;
            var state = Ui.Hint(L.Get(TvSettingsRules.StateKey(_c.ConnectedTvs)));
            state.VerticalAlignment = VerticalAlignment.Center;
            _body.Children.Add(Ui.Split(Ui.Row(dot, name), state));
            _app?.RemoveFromParent();
            _app ??= new TvAppCard(_c);
            _app.Margin = new(0, 8, 0, 0);
            _body.Children.Add(_app);
            var update = _c.TvUpdate;
            if (update.Kind is TvUpdateKind.Outdated or TvUpdateKind.Installing)
            {
                var title = Ui.Body(L.Get("about.tv.outdated"));
                title.VerticalAlignment = VerticalAlignment.Center;
                var install = Ui.Button(L.Get("about.tv.install"), () => _ = _c.InstallTvUpdateAsync());
                install.IsEnabled = update.Kind == TvUpdateKind.Outdated;
                _body.Children.Add(Ui.Split(title, install).At(0, 12, 0, 0));
            }
            if (TvSettingsRules.ShowsOverlaySwitch(tv))
            {
                var overlay = Ui.Toggle(L.Get("settings.tv.overlay")).At(0, 12, 0, 0);
                overlay.IsChecked = TvSettingsRules.OverlayOn(_c.Settings.Style);
                overlay.Checked += (_, _) => SetOverlay(true);
                overlay.Unchecked += (_, _) => SetOverlay(false);
                _body.Children.Add(overlay);
                _body.Children.Add(Ui.Hint(L.Get("settings.tv.overlayHint")).At(0, 6, 0, 0));
            }
        }
        else _body.Children.Add(Ui.Hint(L.Get("settings.tv.none")));
        var setup = Ui.Button(L.Get("settings.tv.openSetup"), () =>
        {
            _host.Close();
            _c.GoToStep(SetupStep.Tv);
        }).At(0, 12, 0, 0);
        setup.HorizontalAlignment = HorizontalAlignment.Left;
        _body.Children.Add(setup);
    });

    void SetOverlay(bool on)
    {
        if (_guard.Busy) return;
        var s = _c.Settings;
        TvSettingsRules.SetOverlay(s, on);
        _c.UpdateSettings(s);
    }

    /// <summary>Kart boşsa TV uygulamasının sürümü sorulur (eski sürüm kuruluysa "Yeni Sürümü Kur" çıkar).</summary>
    public void Shown()
    {
        if (_c.TvPaired && _c.TvApp.Kind == TvAppKind.Unknown) _ = _c.RecheckTvAppAsync();
    }

    public void ControllerChanged(string property)
    {
        if (property is nameof(NinoController.Tv) or nameof(NinoController.ConnectedTvs) or nameof(NinoController.TvUpdate)
            or nameof(NinoController.Settings))
            Dispatcher.BeginInvoke(Render);
    }
}

/// <summary>
/// Görünüş bölümü (Mac'le aynı, 900 genişlik): solda 470 × 264 canlı önizleme, sağda üç seçenekli kart: yazı boyu
/// (otomatik + kaydırıcı), arka planın koyuluğu, konuşanın adı. Yazı tipi, renk, kalınlık, zemin şekli, satır yığma,
/// filigran ve yerleşim seçimleri Mac'teki gibi kalktı (kayıtlı değerler dosyada durur); Android TV'nin katman kipi
/// Bağlantı › Televizyon'da.
/// </summary>
internal sealed class SubtitleAppearanceSection(SettingsWindow host) : SettingsSection(host)
{
    SubtitlePreview? _preview;
    TextBlock? _title;
    TextBlock? _autoHint;
    SliderRow? _background;

    public override SettingsPage Page => SettingsPage.Appearance;

    protected override void Build()
    {
        AddHeader();
        var style = C.Settings.Style;
        var grid = new Grid();
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        _preview = new SubtitlePreview(470, 264) { VerticalAlignment = VerticalAlignment.Top };
        _preview.Apply(style);
        grid.Children.Add(_preview);

        var body = new StackPanel();
        _title = Ui.Headline("").At(0, 0, 0, 8);
        body.Children.Add(_title);
        var auto = Ui.Toggle(L.Get("settings.style.autoSize"));
        auto.IsChecked = style.EffectiveAutoSize;
        auto.Checked += (_, _) => WriteStyle(x => x.AutoSize = true);
        auto.Unchecked += (_, _) => WriteStyle(x => x.AutoSize = false);
        body.Children.Add(auto);

        body.Children.Add(Ui.Body(L.Get("settings.style.size")).At(0, 8, 0, 2));
        var size = new SliderRow(L.Get("settings.style.size.small"), L.Get("settings.style.size.large"),
            SubtitleLookRules.SizeMin, SubtitleLookRules.SizeMax, false);
        size.Slider.IsSnapToTickEnabled = true;
        size.Slider.TickFrequency = 1;
        size.Slider.SmallChange = 1;
        size.Slider.LargeChange = 4;
        size.Slider.Value = SubtitleLookRules.ClampSize(style.FontSize);
        size.Slider.ValueChanged += (_, e) => WriteStyle(x => x.FontSize = SubtitleLookRules.ClampSize(e.NewValue));
        size.Slider.PreviewMouseLeftButtonDown += (_, _) => SendTest();
        body.Children.Add(size);
        _autoHint = Small("settings.style.autoSizeHint");
        body.Children.Add(_autoHint);
        body.Children.Add(new Separator { Margin = new(0, 8, 0, 8) });

        body.Children.Add(Ui.Body(L.Get("settings.style.background")).At(0, 0, 0, 2));
        var (min, max) = SubtitleLookRules.BackgroundRange(style.Placement);
        _background = new SliderRow(L.Get(SubtitleLookRules.BackgroundMinKey(style.Placement)),
            L.Get("settings.style.background.solid"), min, max, false);
        _background.Slider.Value = SubtitleLookRules.ClampBackground(style.Background, style.Placement);
        _background.Slider.ValueChanged += (_, e) =>
            WriteStyle(x => x.Background = SubtitleLookRules.ClampBackground(e.NewValue, x.Placement));
        _background.Slider.PreviewMouseLeftButtonDown += (_, _) => SendTest();
        body.Children.Add(_background);
        body.Children.Add(new Separator { Margin = new(0, 8, 0, 8) });

        var speaker = Ui.Toggle(L.Get("settings.style.speaker"));
        speaker.IsChecked = C.Settings.ShowSpeakerNames;
        speaker.Checked += (_, _) => Write(s => s.ShowSpeakerNames = true);
        speaker.Unchecked += (_, _) => Write(s => s.ShowSpeakerNames = false);
        body.Children.Add(speaker);
        body.Children.Add(Small("settings.style.speakerHint"));

        var card = new Card { Content = body, Padding = new(12), Margin = new(12, 0, 0, 0), VerticalAlignment = VerticalAlignment.Top };
        Grid.SetColumn(card, 1);
        grid.Children.Add(card);
        Children.Add(grid);
        Update();
    }

    static TextBlock Small(string key)
    {
        var t = Ui.Hint(L.Get(key)).At(0, 4, 0, 0);
        t.FontSize = 11;
        return t;
    }

    void WriteStyle(Action<SubtitleStyle> change) => Write(s => change(s.Style));

    void SendTest() => _ = C.SendTestSubtitleAsync();

    void Update()
    {
        if (_title is null) return;
        var s = C.Settings;
        _title.Text = L.Get(SubtitleLookRules.TitleKey(s.Output));
        _autoHint!.Shown(s.Style.EffectiveAutoSize);
        _preview?.Apply(s.Style);
    }

    public override void ControllerChanged(string property)
    {
        if (property is nameof(NinoController.Settings)) Update();
    }
}

/// <summary>
/// §4.2 Windows Güvenlik Duvarı ayar kartı: pencere açılırken durum sorulur; hizmet yoksa hiç görünmez. Kural yoksa
/// "izin ver" düğmesi; ağ Ortak ise uyarı. Durum yalnız açılışta ve düğmeden sonra sorulur.
/// </summary>
public sealed class FirewallSettingsCard : Card
{
    readonly NinoController _c;
    readonly StackPanel _body = new();

    public FirewallSettingsCard(NinoController controller)
    {
        _c = controller;
        SetResourceReference(StyleProperty, typeof(Card));
        Header = L.Get("firewall.settings.title");
        Content = _body;
        Visibility = Visibility.Collapsed;
        Loaded += async (_, _) => await RefreshAsync();
    }

    bool _asked;

    async Task RefreshAsync(bool force = false)
    {
        if (_asked && !force) return;
        _asked = true;
        FirewallInfo? info;
        try { info = await _c.FirewallInfoAsync(); }
        catch (Exception) { info = null; }
        if (info is null)
        {
            Visibility = Visibility.Collapsed;
            return;
        }
        Visibility = Visibility.Visible;
        _body.Children.Clear();
        _body.Children.Add(Ui.Hint(L.Get(info.HasRule ? "firewall.settings.ready" : "firewall.settings.configure")));
        if (info.PublicNetwork) _body.Children.Add(Ui.Error(L.Get("firewall.card.hintPublicNetwork")).At(0, 8, 0, 0));
        if (!info.HasRule)
        {
            Button? allow = null;
            allow = Ui.Button(L.Get("firewall.card.allow"), async () =>
            {
                allow!.IsEnabled = false;
                try { await _c.AllowFirewallAsync(); }
                catch (Exception) { }
                allow.IsEnabled = true;
                await RefreshAsync(force: true);
            }).At(0, 12, 0, 0);
            _body.Children.Add(allow);
        }
    }
}
