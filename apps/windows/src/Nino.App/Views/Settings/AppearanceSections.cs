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

namespace Nino.App.Views;

/// <summary>§2 Arayüz: ana ekran biçimi ve görünüm (tema).</summary>
internal sealed class InterfaceSection(SettingsWindow host) : SettingsSection(host)
{
    Button? _livingRoom;
    Button? _toggle;

    public override string SectionTitle => L.Get("settings.section.interface");

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

/// <summary>§3 Bağlantı: ayrıntılı altyazı çıkışı kartı.</summary>
internal sealed class ConnectionSection(SettingsWindow host) : SettingsSection(host)
{
    public override string SectionTitle => L.Get("settings.section.connection");

    protected override void Build()
    {
        AddHeader();
        AddCard(new SubtitleOutputCard(C, detailed: true));
    }
}

/// <summary>§4 Görünüm: görünüm kartı ve Windows Güvenlik Duvarı kartı.</summary>
internal sealed class SubtitleAppearanceSection(SettingsWindow host) : SettingsSection(host)
{
    Card? _card;
    CheckBox? _autoSize;
    SliderRow? _size;
    StackPanel? _placementPane;
    TextBlock? _followsHint;
    StackPanel? _positionPane;
    StackPanel? _computerPane;
    StackPanel? _displayModePane;
    ComboBox? _placement;

    public override string SectionTitle => L.Get("settings.section.subtitleAppearance");

    protected override void Build()
    {
        AddHeader();
        var style = C.Settings.Style;
        var body = new StackPanel();

        _autoSize = Ui.Toggle(L.Get("settings.subtitle.autoSize")).At(0, 0, 0, 4);
        _autoSize.IsChecked = style.EffectiveAutoSize;
        _autoSize.Checked += (_, _) => WriteStyle(x => x.AutoSize = true);
        _autoSize.Unchecked += (_, _) => WriteStyle(x => x.AutoSize = false);
        body.Children.Add(_autoSize);
        body.Children.Add(Ui.Hint(L.Get("settings.subtitle.autoSizeHint")).At(0, 0, 0, 12));

        body.Children.Add(Ui.Body(L.Get("settings.subtitle.textSize.label")).At(0, 0, 0, 8));
        _size = new SliderRow(L.Get("settings.subtitle.textSize.small"), L.Get("settings.subtitle.textSize.large"), 16, 90, true)
        { Margin = new(0, 0, 0, 16) };
        _size.Slider.IsSnapToTickEnabled = true;
        _size.Slider.TickFrequency = 1;
        _size.Slider.SmallChange = 1;
        _size.Slider.LargeChange = 4;
        _size.Slider.Value = Math.Clamp(style.FontSize, 16, 90);
        _size.ValueText!.Text = ((int)_size.Slider.Value).ToString(L.Catalog.Culture);
        _size.Slider.ValueChanged += (_, e) =>
        {
            _size.ValueText.Text = ((int)Math.Round(e.NewValue)).ToString(L.Catalog.Culture);
            if (Guard.Busy) return;
            var size = (int)Math.Round(e.NewValue);
            WriteStyle(x =>
            {
                x.FontSize = size;
                x.AutoSize = false;
            });
            Guard.Run(() => _autoSize.IsChecked = false);
        };
        _size.Slider.PreviewMouseLeftButtonDown += (_, _) => SendTest();
        body.Children.Add(_size);

        _placementPane = new StackPanel();
        _placementPane.Children.Add(Ui.Body(L.Get("settings.subtitle.placement.label")).At(0, 0, 0, 8));
        _placement = Ui.Combo(240).At(0, 0, 0, 8);
        _placement.Items.Add(Ui.Item(SubtitlePlacement.Cover, L.Get("settings.subtitle.placement.cover")));
        _placement.Items.Add(Ui.Item(SubtitlePlacement.Above, L.Get("settings.subtitle.placement.above")));
        _placement.Items.Add(Ui.Item(SubtitlePlacement.Below, L.Get("settings.subtitle.placement.below")));
        _placement.Items.Add(Ui.Item(SubtitlePlacement.Fixed, L.Get("settings.subtitle.placement.fixed")));
        _placement.SelectTag(style.Placement);
        _placement.SelectionChanged += (_, _) =>
        {
            if (_placement.SelectedTag() is SubtitlePlacement p) WriteStyle(x => x.Placement = p);
            UpdateVisibility();
        };
        _placementPane.Children.Add(_placement);
        _followsHint = Ui.Hint(L.Get("settings.subtitle.placementFollowsHint")).At(0, 0, 0, 16);
        _placementPane.Children.Add(_followsHint);
        _positionPane = new StackPanel();
        _positionPane.Children.Add(Ui.Body(L.Get("settings.subtitle.position.label")).At(0, 0, 0, 8));
        var position = new SliderRow(L.Get("reading.areaPreset.bottom"), L.Get("reading.areaPreset.top"), 0, 85, false);
        position.Slider.Value = Math.Clamp(style.BottomPercent, 0, 85);
        position.Slider.ValueChanged += (_, e) =>
        {
            var value = (int)Math.Round(e.NewValue);
            WriteStyle(x => x.BottomPercent = value);
        };
        position.Slider.PreviewMouseLeftButtonDown += (_, _) => SendTest();
        _positionPane.Children.Add(position);
        _positionPane.Children.Add(Ui.Hint(L.Get("settings.subtitle.positionHint")).At(0, 12, 0, 16));
        _placementPane.Children.Add(_positionPane);
        body.Children.Add(_placementPane);

        _computerPane = new StackPanel { Margin = new(0, 0, 0, 16) };
        _computerPane.Children.Add(Ui.Hint(L.Get("settings.subtitle.computerHint")));
        var adjust = Ui.Button(L.Get("settings.connection.adjustSubtitleWindow"), () => C.AdjustMode = true).At(0, 8, 0, 0);
        _computerPane.Children.Add(adjust);
        body.Children.Add(_computerPane);

        body.Children.Add(Ui.Body(L.Get("settings.subtitle.background.label")).At(0, 0, 0, 8));
        var background = new SliderRow(L.Get("common.none"), L.Get("settings.subtitle.background.solid"), 0, 100, false)
        { Margin = new(0, 0, 0, 16) };
        background.Slider.Value = Math.Clamp(style.Background, 0, 100);
        background.Slider.ValueChanged += (_, e) =>
        {
            var value = (int)Math.Round(e.NewValue);
            WriteStyle(x => x.Background = value);
        };
        background.Slider.PreviewMouseLeftButtonDown += (_, _) => SendTest();
        body.Children.Add(background);

        body.Children.Add(Ui.Body(L.Get("settings.subtitle.backgroundShape.label")).At(0, 0, 0, 8));
        var shape = Ui.Combo(240).At(0, 0, 0, 8);
        shape.Items.Add(Ui.Item(SubtitleBackgroundShape.Fit, L.Get("settings.subtitle.backgroundShape.fit")));
        shape.Items.Add(Ui.Item(SubtitleBackgroundShape.Band, L.Get("settings.subtitle.backgroundShape.band")));
        shape.SelectTag(style.BackgroundShape);
        shape.SelectionChanged += (_, _) =>
        {
            if (shape.SelectedTag() is SubtitleBackgroundShape v) WriteStyle(x => x.BackgroundShape = v);
        };
        body.Children.Add(shape);
        body.Children.Add(Ui.Hint(L.Get("settings.subtitle.backgroundShapeHint")).At(0, 0, 0, 16));

        var bold = Ui.Toggle(L.Get("settings.subtitle.bold")).At(0, 0, 0, 16);
        bold.IsChecked = style.Bold;
        bold.Checked += (_, _) => WriteStyle(x => x.Bold = true);
        bold.Unchecked += (_, _) => WriteStyle(x => x.Bold = false);
        body.Children.Add(bold);

        var stack = Ui.Toggle(L.Get("settings.subtitle.stackPrevious")).At(0, 0, 0, 4);
        stack.IsChecked = style.StackPrevious;
        stack.Checked += (_, _) => WriteStyle(x => x.StackPrevious = true);
        stack.Unchecked += (_, _) => WriteStyle(x => x.StackPrevious = false);
        body.Children.Add(stack);
        body.Children.Add(Ui.Hint(L.Get("settings.subtitle.stackPreviousHint")).At(0, 0, 0, 16));

        body.Children.Add(Ui.Body(L.Get("settings.subtitle.font.label")).At(0, 0, 0, 8));
        var font = Ui.Combo(240).At(0, 0, 0, 16);
        foreach (var (value, key) in new[]
                 {
                     (SubtitleFont.Condensed, "settings.subtitle.font.condensed"), (SubtitleFont.Modern, "settings.subtitle.font.modern"),
                     (SubtitleFont.Rounded, "settings.subtitle.font.rounded"), (SubtitleFont.System, "settings.subtitle.font.system"),
                 })
        {
            var item = Ui.Item(value, L.Get(key));
            if (NinoFonts.ForSubtitle(value) is { } family)
            {
                item.FontFamily = family;
                item.FontWeight = FontWeights.SemiBold;
            }
            font.Items.Add(item);
        }
        font.SelectTag(style.Font);
        font.SelectionChanged += (_, _) =>
        {
            if (font.SelectedTag() is SubtitleFont v) WriteStyle(x => x.Font = v);
        };
        body.Children.Add(font);

        body.Children.Add(Ui.Body(L.Get("settings.subtitle.textColor.label")).At(0, 0, 0, 8));
        var color = Ui.Combo(240).At(0, 0, 0, 16);
        color.Items.Add(Ui.Item(SubtitleTextColor.White, L.Get("settings.subtitle.textColor.white")));
        color.Items.Add(Ui.Item(SubtitleTextColor.Yellow, L.Get("settings.subtitle.textColor.yellow")));
        color.SelectTag(style.TextColor);
        color.SelectionChanged += (_, _) =>
        {
            if (color.SelectedTag() is SubtitleTextColor v) WriteStyle(x => x.TextColor = v);
        };
        body.Children.Add(color);

        _displayModePane = new StackPanel();
        _displayModePane.Children.Add(Ui.Body(L.Get("settings.subtitle.displayMode.label")).At(0, 0, 0, 8));
        var mode = Ui.Combo(240).At(0, 0, 0, 8);
        mode.Items.Add(Ui.Item(SubtitleDisplayMode.InApp, L.Get("settings.subtitle.displayMode.inApp")));
        mode.Items.Add(Ui.Item(SubtitleDisplayMode.Overlay, L.Get("settings.subtitle.displayMode.overlay")));
        mode.SelectTag(style.DisplayMode);
        mode.SelectionChanged += (_, _) =>
        {
            if (mode.SelectedTag() is SubtitleDisplayMode v) WriteStyle(x => x.DisplayMode = v);
        };
        _displayModePane.Children.Add(mode);
        _displayModePane.Children.Add(Ui.Hint(L.Get("settings.subtitle.displayModeHint")).At(0, 0, 0, 16));
        body.Children.Add(_displayModePane);

        var watermark = Ui.Toggle(L.Get("settings.subtitle.watermark")).At(0, 0, 0, 4);
        watermark.IsChecked = style.Watermark;
        watermark.Checked += (_, _) => WriteStyle(x => x.Watermark = true);
        watermark.Unchecked += (_, _) => WriteStyle(x => x.Watermark = false);
        body.Children.Add(watermark);
        body.Children.Add(Ui.Hint(L.Get("settings.subtitle.watermarkHint")).At(0, 0, 0, 16));

        body.Children.Add(Ui.Button(L.Get("setup.try.sendSample"), SendTest));

        _card = new Card { Content = body };
        AddCard(_card);
        AddCard(new FirewallSettingsCard(C));
        UpdateVisibility();
    }

    void WriteStyle(Action<SubtitleStyle> change) => Write(s => change(s.Style));

    void SendTest() => _ = C.SendTestSubtitleAsync();

    void UpdateVisibility()
    {
        if (_card is null) return;
        var s = C.Settings;
        _card.Header = L.Get(s.Output == SubtitleOutput.Tv ? "settings.area.target.tv" : "settings.section.subtitleAppearance");
        var fixedPlace = (_placement?.SelectedTag() as SubtitlePlacement? ?? s.Style.Placement) == SubtitlePlacement.Fixed;
        _placementPane!.Shown(C.ShowsOnTv);
        _followsHint!.Shown(C.ShowsOnTv && !fixedPlace);
        _positionPane!.Shown(C.ShowsOnTv && fixedPlace);
        _computerPane!.Shown(C.ShowsOnComputer);
        _displayModePane!.Shown(C.ShowsOnTv && C.Tv?.Brand == TvBrand.AndroidTv);
    }

    public override void ControllerChanged(string property)
    {
        if (property is nameof(NinoController.Settings) or nameof(NinoController.ShowsOnTv) or nameof(NinoController.ShowsOnComputer)
            or nameof(NinoController.Tv))
            UpdateVisibility();
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
