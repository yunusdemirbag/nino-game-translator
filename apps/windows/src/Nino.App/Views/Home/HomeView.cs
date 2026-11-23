// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.ComponentModel;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Documents;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Threading;
using Nino.App.Controls;
using Nino.App.Strings;
using Nino.App.Theme;
using Nino.Core.Settings;
using Nino.Shell;
using Glyphs = Nino.App.Controls.Glyphs;

namespace Nino.App.Views;

/// <summary>
/// Ana ekran, Mac'in ana ekranıyla aynı yapıda: başlık (logo, ad ve sürüm hapı, Geçmiş ve Ayarlar yuvarlak düğmeleri),
/// anahtar önerisi, orta alan (salon ya da cam anahtar) ve üç bölgeli alt şerit. Salonlu orta alan kaydırılmaz
/// (yeni sürüm şeridi, sahne, uyarılar; sahne kalan alana küçülür); cam anahtarlı orta alan kaydırılır, anahtar dikeyde
/// ortadadır. Ekrandayken 5 sn'de bir bağlantılar denetlenir; açılınca (süreçte bir kez) güncellemeye bakılır.
/// </summary>
public sealed class HomeView : UserControl, IDisposable
{
    static bool _updateChecked;

    // Windows'un simge yazısında (Segoe Fluent Icons / MDL2) kullanılan ek simgeler.
    const string KeyGlyph = "", CloseGlyph = "", RefreshGlyph = "", ChevronGlyph = "",
        UpdateGlyph = "";

    readonly NinoController _controller;
    readonly ContentControl _middle = new() { Focusable = false, IsTabStop = false };
    readonly HomeCards _cards;
    readonly DispatcherTimer _connections = new() { Interval = TimeSpan.FromSeconds(5) };
    readonly Grid _layers = new();
    GameRoomNameSheet? _gameRoomSheet;

    // Yeni sürüm şeridi
    readonly Border _banner = new();
    readonly TextBlock _bannerVersion = new();
    readonly TextBlock _bannerError = new();
    readonly Button _bannerButton;

    // Anahtar önerisi
    readonly Border _keySuggestion = new();
    readonly TextBlock _keyDetail = new();

    // Alt şerit
    readonly StatusDot _sourceDot = new() { Width = 7, Height = 7, Margin = new Thickness(0, 0, 7, 0) };
    readonly Run _sourceName = new() { FontWeight = FontWeights.SemiBold };
    readonly Run _sourceValue = new();
    readonly TextBlock _sourceText = new()
    {
        TextWrapping = TextWrapping.NoWrap,
        TextTrimming = TextTrimming.CharacterEllipsis,
        VerticalAlignment = VerticalAlignment.Center,
    };
    readonly StackPanel _sourceItem = new() { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center, Background = Brushes.Transparent };
    readonly Button _tvItem;
    readonly StatusDot _tvDot = new() { Width = 7, Height = 7, Margin = new Thickness(0, 0, 7, 0) };
    readonly Run _tvValue = new();
    readonly ContentControl _updateCenter = new() { Focusable = false, IsTabStop = false, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
    readonly Run _translationValue = new() { FontWeight = FontWeights.SemiBold };
    readonly Button _translationLink;
    HomeFooterState? _footer;
    UpdateCenterState? _center;
    (HomeStyle Style, bool Xbox)? _stageKind;
    bool _disposed;

    public HomeView(NinoController controller)
    {
        _controller = controller;
        Focusable = false;
        _cards = new HomeCards(controller, OpenSettings);
        _cards.Panel.MaxWidth = 640;
        _cards.Panel.HorizontalAlignment = HorizontalAlignment.Center;
        _bannerButton = HomeUi.Button(L.Get("home.update.download"), "Button.Primary");
        _tvItem = FlatButton();
        _translationLink = FlatButton();

        var root = new Grid();
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        Add(root, BuildHeader(), 0);
        Add(root, BuildKeySuggestion(), 1);
        BuildBanner();
        Add(root, _middle, 2);
        Add(root, BuildFooter(), 3);
        _layers.Children.Add(root);
        Content = _layers;

        _connections.Tick += async (_, _) =>
        {
            try { await _controller.CheckConnectionsAsync(); } catch (Exception) { }
        };
        Loaded += OnLoaded;
        Unloaded += (_, _) => _connections.Stop();
        controller.PropertyChanged += OnControllerChanged;
        Refresh();
    }

    /// <summary>Oyun odası adı sorusu: kurulum bittiyse, daha önce sorulmadıysa ve bölge uygunsa bir kez.</summary>
    void RefreshGameRoomQuestion()
    {
        if (_gameRoomSheet is not null || !_controller.ShouldAskGameRoomName) return;
        var sheet = new GameRoomNameSheet(_controller);
        sheet.Closed += () =>
        {
            _layers.Children.Remove(sheet);
            _gameRoomSheet = null;
        };
        _gameRoomSheet = sheet;
        _layers.Children.Add(sheet);
    }

    static void Add(Grid grid, UIElement element, int row)
    {
        Grid.SetRow(element, row);
        grid.Children.Add(element);
    }

    void OnLoaded(object sender, RoutedEventArgs e)
    {
        if (_disposed) return;
        _connections.Start();
        if (_updateChecked) return;
        _updateChecked = true;
        _ = CheckUpdateAsync();
    }

    async Task CheckUpdateAsync()
    {
        try { await _controller.CheckForUpdateFromHomeAsync(); } catch (Exception) { }
    }

    void OnControllerChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (!_disposed) Refresh();
    }

    void Refresh()
    {
        RefreshGameRoomQuestion();
        RefreshStage();
        RefreshBanner();
        RefreshKeySuggestion();
        RefreshFooter();
        RefreshUpdateCenter();
        _cards.Refresh();
    }

    // ---- Başlık (Mac §3.1) ----

    FrameworkElement BuildHeader()
    {
        var header = new DockPanel { Margin = new Thickness(24, 12, 24, 0), LastChildFill = false };

        var buttons = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
        var history = RoundIconButton(Glyphs.History, L.Get("home.header.history"));
        history.Margin = new Thickness(0, 0, 8, 0);
        history.Click += (_, _) => OpenOwned(ShellWindowKind.History);
        var settings = RoundIconButton(Glyphs.Settings, L.Get("common.settings"));
        settings.Click += (_, _) => OpenSettings();
        buttons.Children.Add(history);
        buttons.Children.Add(settings);
        DockPanel.SetDock(buttons, Dock.Right);
        header.Children.Add(buttons);

        var brand = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
        brand.Children.Add(new LogoBox { Width = 46, Height = 46, VerticalAlignment = VerticalAlignment.Center });
        var words = new StackPanel { Margin = new Thickness(8, 0, 0, 0), VerticalAlignment = VerticalAlignment.Center };
        var name = new TextBlock { Text = "Nino", FontSize = 24, FontWeight = FontWeights.Bold, LineHeight = 26, LineStackingStrategy = LineStackingStrategy.BlockLineHeight };
        name.SetResourceReference(TextBlock.FontFamilyProperty, "font.display");
        name.SetResourceReference(TextBlock.ForegroundProperty, "textPrimaryBrush");
        var tagline = new TextBlock { Text = "GAME TRANSLATOR", FontSize = 8, FontWeight = FontWeights.SemiBold, Margin = new Thickness(1, 0, 0, 0) };
        tagline.SetResourceReference(TextBlock.FontFamilyProperty, "font.display");
        tagline.SetResourceReference(TextBlock.ForegroundProperty, "textSecondaryBrush");
        Typography.SetCapitals(tagline, FontCapitals.Normal);
        var mark = new StackPanel();
        mark.Children.Add(name);
        mark.Children.Add(tagline);
        AutomationProperties.SetName(mark, "Nino Game Translator");
        words.Children.Add(mark);

        // Sürüm hapı: kısa ad ("V4.0"), ipucunda tam sürüm.
        var full = _controller.AppVersion;
        var pill = new Border
        {
            CornerRadius = new CornerRadius(999),
            Padding = new Thickness(7, 2, 7, 2),
            Margin = new Thickness(0, 5, 0, 0),
            HorizontalAlignment = HorizontalAlignment.Left,
            Background = new SolidColorBrush(Color.FromArgb(0x1F, 0x80, 0x80, 0x80)),
            ToolTip = VersionLabel.Tooltip(full),
            Child = new TextBlock { Text = VersionLabel.Short(full), FontSize = 10, FontWeight = FontWeights.Bold },
        };
        ((TextBlock)pill.Child).SetResourceReference(TextBlock.ForegroundProperty, "textSecondaryBrush");
        AutomationProperties.SetName(pill, L.Format("home.version", full));
        words.Children.Add(pill);
        brand.Children.Add(words);
        DockPanel.SetDock(brand, Dock.Left);
        header.Children.Add(brand);
        return header;
    }

    static Button RoundIconButton(string glyph, string label)
    {
        var button = HomeUi.Button(glyph, "Button.Icon");
        button.Resources["radius.control"] = new CornerRadius(20);
        button.ToolTip = label;
        AutomationProperties.SetName(button, label);
        return button;
    }

    // ---- Anahtar önerisi (Mac HomeKeySuggestion) ----

    FrameworkElement BuildKeySuggestion()
    {
        var row = new DockPanel { LastChildFill = true };
        var close = new Button
        {
            Content = CloseGlyph,
            Width = 22,
            Height = 22,
            Padding = new Thickness(0),
            FontSize = 11,
            Margin = new Thickness(10, 0, 0, 0),
            VerticalAlignment = VerticalAlignment.Center,
            ToolTip = L.Get("home.keySuggestion.dismiss"),
        };
        close.SetResourceReference(StyleProperty, "Button.Ghost");
        close.SetResourceReference(FontFamilyProperty, "font.icon");
        AutomationProperties.SetName(close, L.Get("home.keySuggestion.dismiss"));
        close.Click += (_, _) => _controller.DismissKeySuggestion();
        DockPanel.SetDock(close, Dock.Right);
        row.Children.Add(close);

        var body = new DockPanel { LastChildFill = true };
        var key = new TextBlock { Text = KeyGlyph, FontSize = 16, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 8, 0) };
        key.SetResourceReference(TextBlock.FontFamilyProperty, "font.icon");
        key.SetResourceReference(TextBlock.ForegroundProperty, "accentBrush");
        DockPanel.SetDock(key, Dock.Left);
        body.Children.Add(key);
        var texts = new StackPanel();
        var title = HomeUi.Text(L.Get("home.keySuggestion.title"), "Text.Callout").Brush(TextBlock.ForegroundProperty, "accentTextBrush");
        title.FontWeight = FontWeights.SemiBold;
        texts.Children.Add(title);
        _keyDetail.SetResourceReference(StyleProperty, "Text.Caption");
        _keyDetail.SetResourceReference(TextBlock.ForegroundProperty, "textSecondaryBrush");
        _keyDetail.TextWrapping = TextWrapping.Wrap;
        _keyDetail.MaxHeight = 34;
        _keyDetail.TextTrimming = TextTrimming.CharacterEllipsis;
        _keyDetail.Margin = new Thickness(0, 1, 0, 0);
        texts.Children.Add(_keyDetail);
        body.Children.Add(texts);
        var open = FlatButton();
        open.Content = body;
        open.HorizontalContentAlignment = HorizontalAlignment.Stretch;
        open.Click += (_, _) => OpenSettingsAt(Nino.Shell.Panels.SettingsPage.Translation);
        row.Children.Add(open);

        _keySuggestion.Child = row;
        _keySuggestion.Padding = new Thickness(12, 8, 12, 8);
        _keySuggestion.Margin = new Thickness(24, 6, 24, 0);
        _keySuggestion.MaxWidth = 520;
        _keySuggestion.HorizontalAlignment = HorizontalAlignment.Center;
        Glass(_keySuggestion);
        return _keySuggestion;
    }

    void RefreshKeySuggestion()
    {
        var game = _controller.KeySuggestionGame;
        _keySuggestion.Show(game is not null);
        if (game is not null) _keyDetail.Text = L.Format("home.keySuggestion.detail", game);
    }

    // ---- Yeni sürüm şeridi (Mac §6.3) ----

    void BuildBanner()
    {
        var row = new DockPanel { LastChildFill = true };
        _bannerButton.Margin = new Thickness(12, 0, 0, 0);
        _bannerButton.VerticalAlignment = VerticalAlignment.Center;
        _bannerButton.Click += async (_, _) =>
        {
            try { await _controller.InstallUpdateAsync(); } catch (Exception) { }
        };
        DockPanel.SetDock(_bannerButton, Dock.Right);
        row.Children.Add(_bannerButton);
        var icon = new TextBlock { Text = UpdateGlyph, FontSize = 22, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 12, 0) };
        icon.SetResourceReference(TextBlock.FontFamilyProperty, "font.icon");
        icon.SetResourceReference(TextBlock.ForegroundProperty, "accentBrush");
        DockPanel.SetDock(icon, Dock.Left);
        row.Children.Add(icon);
        var texts = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
        var title = HomeUi.Text(L.Get("home.update.bannerTitle"), "Text.Callout");
        title.FontWeight = FontWeights.SemiBold;
        texts.Children.Add(title);
        _bannerVersion.SetResourceReference(StyleProperty, "Text.Caption");
        _bannerVersion.SetResourceReference(TextBlock.ForegroundProperty, "textSecondaryBrush");
        _bannerVersion.Margin = new Thickness(0, 2, 0, 0);
        texts.Children.Add(_bannerVersion);
        _bannerError.SetResourceReference(StyleProperty, "Text.Caption");
        _bannerError.SetResourceReference(TextBlock.ForegroundProperty, "dangerBrush");
        _bannerError.TextWrapping = TextWrapping.Wrap;
        _bannerError.Margin = new Thickness(0, 2, 0, 0);
        texts.Children.Add(_bannerError);
        row.Children.Add(texts);
        _banner.Child = row;
        _banner.Padding = new Thickness(12);
        _banner.MaxWidth = 640;
        _banner.HorizontalAlignment = HorizontalAlignment.Stretch;
        Glass(_banner);
    }

    void RefreshBanner()
    {
        var version = _controller.UpdateVersion;
        _banner.Show(version is not null);
        _bannerVersion.Text = "Nino " + version;
        _bannerError.Text = _controller.UpdateError ?? "";
        _bannerError.Show(!string.IsNullOrEmpty(_controller.UpdateError));
        _bannerButton.IsEnabled = !_controller.Updating;
    }

    // ---- Orta alan (Mac §4.1 / §5.1) ----

    /// <summary>
    /// Seçili arayüz: ayardaki ana ekran biçimi ve salonun Xbox'lı mı olduğu değişince yeniden kurulur, aynıysa dokunulmaz.
    /// </summary>
    void RefreshStage()
    {
        var kind = (_controller.HomeStyle, _controller.HomeSceneIsXbox);
        if (_stageKind == kind) return;
        _stageKind = kind;
        if (_middle.Content is FrameworkElement oldLayout) DisposeStages(oldLayout);
        Detach(_banner);
        Detach(_cards.Panel);
        _middle.Content = kind.Item1 == HomeStyle.Toggle ? ToggleLayout() : LivingRoomLayout(kind.Item2);
    }

    /// <summary>Salon: kaydırılmaz; yeni sürüm şeridi, sahne (kalan alanın tamamı), uyarılar; aralık 12.</summary>
    FrameworkElement LivingRoomLayout(bool xbox)
    {
        var grid = new Grid { Margin = new Thickness(24, 12, 24, 12) };
        grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        grid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        _banner.Margin = new Thickness(0, 0, 0, 12);
        Add(grid, _banner, 0);
        Add(grid, new LivingRoomScene(_controller, xbox), 1);
        _cards.Panel.Margin = new Thickness(0, 12, 0, 0);
        Add(grid, _cards.Panel, 2);
        return grid;
    }

    /// <summary>Cam anahtar: kaydırılır (çubuk gizli); şerit, esnek boşluk, anahtar, uyarılar, esnek boşluk; aralık 16.</summary>
    FrameworkElement ToggleLayout()
    {
        var scroll = new ScrollViewer
        {
            VerticalScrollBarVisibility = ScrollBarVisibility.Hidden,
            HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled,
            Focusable = false,
            IsTabStop = false,
        };
        var grid = new Grid { Margin = new Thickness(24, 0, 24, 0) };
        grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        grid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        grid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        _banner.Margin = new Thickness(0, 12, 0, 0);
        Add(grid, _banner, 0);
        Add(grid, new GlassToggle(_controller) { Margin = new Thickness(0, 16, 0, 0) }, 2);
        _cards.Panel.Margin = new Thickness(0, 16, 0, 16);
        Add(grid, _cards.Panel, 3);
        void Fit() => grid.MinHeight = scroll.ViewportHeight;
        scroll.ScrollChanged += (_, _) => Fit();
        scroll.SizeChanged += (_, _) => Fit();
        scroll.Content = grid;
        return scroll;
    }

    static void Detach(FrameworkElement element)
    {
        if (element.Parent is Panel panel) panel.Children.Remove(element);
    }

    static void DisposeStages(FrameworkElement layout)
    {
        var grid = layout as Grid ?? (layout as ScrollViewer)?.Content as Grid;
        if (grid is null) return;
        foreach (var child in grid.Children.OfType<IDisposable>().ToArray()) child.Dispose();
    }

    // ---- Alt şerit (Mac §6) ----

    FrameworkElement BuildFooter()
    {
        var strip = new DockPanel { LastChildFill = true };
        var line = new Border { Height = 1 };
        line.SetResourceReference(Border.BackgroundProperty, "borderBrush");
        DockPanel.SetDock(line, Dock.Top);
        strip.Children.Add(line);

        var grid = new Grid { Height = 44, Margin = new Thickness(24, 0, 24, 0) };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto, MaxWidth = 300 });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

        // Sol: görüntü kaynağı ve (altyazı TV'ye gidiyorsa) TV; uzun kaynak metni kısalır.
        _sourceValue.SetResourceReference(TextElement.ForegroundProperty, "textSecondaryBrush");
        _sourceName.SetResourceReference(TextElement.ForegroundProperty, "textPrimaryBrush");
        _sourceText.Inlines.Add(_sourceName);
        _sourceText.Inlines.Add(new Run(" "));
        _sourceText.Inlines.Add(_sourceValue);
        _sourceText.SetResourceReference(StyleProperty, "Text.Caption");
        _sourceText.MaxWidth = 300;
        _sourceItem.Children.Add(_sourceDot);
        _sourceItem.Children.Add(_sourceText);

        var tv = new StackPanel { Orientation = Orientation.Horizontal };
        tv.Children.Add(_tvDot);
        var tvText = new TextBlock { TextWrapping = TextWrapping.NoWrap, VerticalAlignment = VerticalAlignment.Center };
        tvText.SetResourceReference(StyleProperty, "Text.Caption");
        tvText.Inlines.Add(new Run("TV") { FontWeight = FontWeights.SemiBold });
        tvText.Inlines.Add(new Run(" "));
        _tvValue.SetResourceReference(TextElement.ForegroundProperty, "textSecondaryBrush");
        tvText.Inlines.Add(_tvValue);
        tv.Children.Add(tvText);
        _tvItem.Content = tv;
        _tvItem.Margin = new Thickness(22, 0, 0, 0);
        _tvItem.VerticalAlignment = VerticalAlignment.Center;
        // TV hazırken de tıklanır: kurulumun TV adımını açar (Mac'teki gibi).
        _tvItem.Click += (_, _) => _controller.GoToStep(SetupStep.Tv);

        var leftRow = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            VerticalAlignment = VerticalAlignment.Center,
            HorizontalAlignment = HorizontalAlignment.Left,
            Margin = new Thickness(0, 0, 16, 0),
        };
        leftRow.Children.Add(_sourceItem);
        leftRow.Children.Add(_tvItem);
        Grid.SetColumn(leftRow, 0);
        grid.Children.Add(leftRow);

        // Orta: güncelleme durumu.
        Grid.SetColumn(_updateCenter, 1);
        grid.Children.Add(_updateCenter);

        // Sağ: "Çeviri <değer> ›" → Ayarlar.
        var link = new TextBlock { TextWrapping = TextWrapping.NoWrap, TextTrimming = TextTrimming.CharacterEllipsis, VerticalAlignment = VerticalAlignment.Center };
        link.SetResourceReference(StyleProperty, "Text.Caption");
        var lead = new Run(L.Get("home.footer.translation"));
        lead.SetResourceReference(TextElement.ForegroundProperty, "textSecondaryBrush");
        _translationValue.SetResourceReference(TextElement.ForegroundProperty, "textPrimaryBrush");
        var chevron = new Run(" " + ChevronGlyph) { FontSize = 9, FontWeight = FontWeights.SemiBold };
        chevron.SetResourceReference(TextElement.FontFamilyProperty, "font.icon");
        chevron.SetResourceReference(TextElement.ForegroundProperty, "textSecondaryBrush");
        link.Inlines.Add(lead);
        link.Inlines.Add(new Run(" "));
        link.Inlines.Add(_translationValue);
        link.Inlines.Add(chevron);
        _translationLink.Content = link;
        _translationLink.HorizontalAlignment = HorizontalAlignment.Right;
        _translationLink.VerticalAlignment = VerticalAlignment.Center;
        _translationLink.Margin = new Thickness(16, 0, 0, 0);
        _translationLink.Click += (_, _) => OpenSettingsAt(Nino.Shell.Panels.SettingsPage.Translation);
        Grid.SetColumn(_translationLink, 2);
        grid.Children.Add(_translationLink);

        strip.Children.Add(grid);
        return strip;
    }

    void RefreshFooter()
    {
        var state = HomeFooter.Compute(HomeFooter.Read(_controller), _controller.Text);
        if (state == _footer) return;
        _footer = state;
        _sourceName.Text = state.SourceName;
        _sourceValue.Text = state.SourceValue;
        _sourceDot.Tone = state.SourceTone;
        _sourceItem.ToolTip = string.IsNullOrEmpty(state.SourceHelp) ? null : state.SourceHelp;
        AutomationProperties.SetName(_sourceItem, state.SourceName + " " + state.SourceValue);
        AutomationProperties.SetHelpText(_sourceItem, state.SourceHelp);
        _tvItem.Show(state.TvVisible);
        _tvValue.Text = state.TvValue;
        _tvDot.Tone = state.TvTone;
        _tvItem.ToolTip = state.TvHelp;
        AutomationProperties.SetName(_tvItem, "TV " + state.TvValue);
        AutomationProperties.SetHelpText(_tvItem, state.TvHelp);
        _translationValue.Text = state.TranslationValue;
        _translationLink.ToolTip = state.TranslationValue;
        AutomationProperties.SetName(_translationLink, L.Get("home.footer.translation") + " " + state.TranslationValue);
    }

    // ---- Alt şeridin ortası: güncelleme (Mac §6.3) ----

    void RefreshUpdateCenter()
    {
        var state = _controller.UpdateCenter;
        if (state == _center) return;
        _center = state;
        var row = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
        var text = state.Version is null ? L.Get(state.TextKey) : L.Format(state.TextKey, state.Version);
        switch (state.Kind)
        {
            case UpdateCenterKind.NewVersion:
                row.Children.Add(Pill(Glyphs.Download, text));
                break;
            case UpdateCenterKind.Downloading:
                row.Children.Add(Caption(Glyphs.Download + " ", icon: true));
                row.Children.Add(Caption(text));
                break;
            default:
                if (state.Kind == UpdateCenterKind.UpToDate) row.Children.Add(Caption(Glyphs.CheckMark + " ", icon: true));
                row.Children.Add(Caption(text));
                row.Children.Add(RecheckButton(spinning: state.Kind == UpdateCenterKind.Checking));
                break;
        }
        _updateCenter.Content = row;
    }

    static TextBlock Caption(string text, bool icon = false)
    {
        var block = new TextBlock { Text = text, TextWrapping = TextWrapping.NoWrap, TextTrimming = TextTrimming.CharacterEllipsis, VerticalAlignment = VerticalAlignment.Center };
        block.SetResourceReference(StyleProperty, "Text.Caption");
        block.SetResourceReference(TextBlock.ForegroundProperty, "textSecondaryBrush");
        if (icon)
        {
            block.SetResourceReference(TextBlock.FontFamilyProperty, "font.icon");
            block.FontSize = 10;
            block.FontWeight = FontWeights.Bold;
        }
        return block;
    }

    Button Pill(string glyph, string text)
    {
        var content = new TextBlock { TextWrapping = TextWrapping.NoWrap, TextTrimming = TextTrimming.CharacterEllipsis, Foreground = Brushes.White };
        content.SetResourceReference(StyleProperty, "Text.Caption");
        content.FontWeight = FontWeights.SemiBold;
        var icon = new Run(glyph + "  ") { FontSize = 11, FontWeight = FontWeights.Bold };
        icon.SetResourceReference(TextElement.FontFamilyProperty, "font.icon");
        content.Inlines.Add(icon);
        content.Inlines.Add(new Run(text));
        var border = new Border { CornerRadius = new CornerRadius(999), Padding = new Thickness(12, 5, 12, 5), Child = content };
        border.SetResourceReference(Border.BackgroundProperty, "accentBrush");
        var button = FlatButton();
        button.Content = border;
        AutomationProperties.SetName(button, text);
        button.Click += async (_, _) =>
        {
            try { await _controller.InstallUpdateAsync(); } catch (Exception) { }
        };
        return button;
    }

    Button RecheckButton(bool spinning)
    {
        var glyph = new TextBlock
        {
            Text = RefreshGlyph,
            FontSize = 10,
            FontWeight = FontWeights.Bold,
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center,
            RenderTransformOrigin = new Point(0.5, 0.5),
        };
        glyph.SetResourceReference(TextBlock.FontFamilyProperty, "font.icon");
        glyph.SetResourceReference(TextBlock.ForegroundProperty, "textSecondaryBrush");
        var circle = new Border
        {
            Width = 22,
            Height = 22,
            CornerRadius = new CornerRadius(11),
            Background = new SolidColorBrush(Color.FromArgb(0x1A, 0x80, 0x80, 0x80)),
            Child = glyph,
        };
        var button = FlatButton();
        button.Content = circle;
        button.Margin = new Thickness(6, 0, 0, 0);
        button.IsEnabled = !spinning;
        var label = L.Get("home.update.check");
        button.ToolTip = label;
        AutomationProperties.SetName(button, label);
        button.MouseEnter += (_, _) =>
        {
            circle.Background = new SolidColorBrush(Color.FromArgb(0x2E, 0x80, 0x80, 0x80));
            glyph.SetResourceReference(TextBlock.ForegroundProperty, "textPrimaryBrush");
        };
        button.MouseLeave += (_, _) =>
        {
            circle.Background = new SolidColorBrush(Color.FromArgb(0x1A, 0x80, 0x80, 0x80));
            glyph.SetResourceReference(TextBlock.ForegroundProperty, "textSecondaryBrush");
        };
        button.Click += async (_, _) =>
        {
            try { await _controller.CheckForUpdateFromHomeAsync(); } catch (Exception) { }
        };
        if (spinning && !Motion.IsReduced)
        {
            var turn = new RotateTransform();
            glyph.RenderTransform = turn;
            turn.BeginAnimation(RotateTransform.AngleProperty,
                new DoubleAnimation(0, 360, TimeSpan.FromSeconds(0.9)) { RepeatBehavior = RepeatBehavior.Forever });
        }
        return button;
    }

    // ---- Yardımcılar ----

    /// <summary>Çerçevesiz, yalnız içeriğini gösteren düğme (alt şerit ögeleri, öneri kartı); el imleci.</summary>
    static Button FlatButton()
    {
        var button = new Button
        {
            Template = new ControlTemplate(typeof(Button)) { VisualTree = new FrameworkElementFactory(typeof(ContentPresenter)) },
            Background = Brushes.Transparent,
            BorderThickness = new Thickness(0),
            Padding = new Thickness(0),
            Cursor = Cursors.Hand,
            HorizontalContentAlignment = HorizontalAlignment.Left,
        };
        return button;
    }

    /// <summary>Mac'in cam zeminine Windows karşılığı: surface zemin, ince çerçeve, köşe 22.</summary>
    static void Glass(Border border)
    {
        border.CornerRadius = new CornerRadius(22);
        border.BorderThickness = new Thickness(1);
        border.SetResourceReference(Border.BackgroundProperty, "surfaceBrush");
        border.SetResourceReference(Border.BorderBrushProperty, "tileBorderBrush");
    }

    // ---- Pencereler ----

    void OpenSettings() => OpenOwned(ShellWindowKind.Settings);

    /// <summary>Ayarlar doğrudan bir bölümde açılır (liste atlanır).</summary>
    void OpenSettingsAt(Nino.Shell.Panels.SettingsPage page) => SettingsWindow.Open(_controller, Window.GetWindow(this), page);

    void OpenOwned(ShellWindowKind kind)
    {
        if (Window.GetWindow(this) is { } owner) ShellWindows.Show(kind, owner, _controller);
    }

    /// <summary>Ekrandan kalkınca: zamanlayıcılar durur, denetleyiciden ayrılır.</summary>
    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        _connections.Stop();
        _controller.PropertyChanged -= OnControllerChanged;
        _cards.Dispose();
        if (_middle.Content is FrameworkElement layout) DisposeStages(layout);
    }
}
