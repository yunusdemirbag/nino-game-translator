// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.ComponentModel;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Documents;
using System.Windows.Input;
using System.Windows.Threading;
using Nino.App.Controls;
using Nino.App.Strings;
using Nino.Core.Settings;
using Nino.Shell;
using Glyphs = Nino.App.Controls.Glyphs;

namespace Nino.App.Views;

/// <summary>
/// Ana ekran (ana-ekran §3): dört yandan 24 boşlukla başlık, orta alan (seçili arayüz + uyarı kartları, dikey
/// kaydırılır) ve alt şerit. Ekrandayken 5 sn'de bir bağlantılar denetlenir; açılınca (süreçte bir kez) güncelleme
/// denetlenir.
/// </summary>
public sealed class HomeView : UserControl, IDisposable
{
    static bool _updateChecked;

    readonly NinoController _controller;
    readonly ContentControl _stage = new() { Focusable = false, IsTabStop = false, Margin = new Thickness(0, 8, 0, 8) };
    readonly HomeCards _cards;
    readonly DispatcherTimer _connections = new() { Interval = TimeSpan.FromSeconds(5) };

    // Alt şerit
    readonly StatusDot _sourceDot = new() { Width = 7, Height = 7, Margin = new Thickness(0, 0, 7, 0) };
    readonly Run _sourceName = new() { FontWeight = FontWeights.SemiBold };
    readonly Run _sourceValue = new();
    readonly StatusDot _tvDot = new() { Width = 7, Height = 7, Margin = new Thickness(22, 0, 7, 0) };
    readonly TextBlock _tvText = new() { TextWrapping = TextWrapping.NoWrap, VerticalAlignment = VerticalAlignment.Center, Cursor = Cursors.Hand };
    readonly Run _tvValue = new();
    readonly Run _translationSource = new() { FontWeight = FontWeights.SemiBold };
    readonly TextBlock _translationLink = new() { TextWrapping = TextWrapping.NoWrap, VerticalAlignment = VerticalAlignment.Center, Cursor = Cursors.Hand, Focusable = false };
    HomeFooterState? _footer;
    (HomeStyle Style, bool Xbox)? _stageKind;
    bool _disposed;

    public HomeView(NinoController controller)
    {
        _controller = controller;
        Focusable = false;
        _cards = new HomeCards(controller, OpenSettings);

        var root = new Grid { Margin = new Thickness(24) };
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });

        var header = BuildHeader();
        Grid.SetRow(header, 0);
        root.Children.Add(header);

        var middle = BuildMiddle();
        Grid.SetRow(middle, 1);
        root.Children.Add(middle);

        var footer = BuildFooter();
        Grid.SetRow(footer, 2);
        root.Children.Add(footer);

        Content = root;

        _connections.Tick += async (_, _) =>
        {
            try { await _controller.CheckConnectionsAsync(); } catch (Exception) { }
        };
        Loaded += OnLoaded;
        Unloaded += (_, _) => _connections.Stop();
        controller.PropertyChanged += OnControllerChanged;
        Refresh();
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
        try { await _controller.CheckForUpdateAsync(); } catch (Exception) { }
    }

    void OnControllerChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (!_disposed) Refresh();
    }

    void Refresh()
    {
        RefreshStage();
        RefreshFooter();
        _cards.Refresh();
    }

    // ---- Başlık (§3.1) ----

    FrameworkElement BuildHeader()
    {
        var header = new DockPanel { Margin = new Thickness(0, 0, 0, 16), LastChildFill = false };

        var buttons = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
        var historyText = L.Get("home.header.history");
        var history = HomeUi.Button(HomeUi.IconLabel(Glyphs.History, historyText), padding: new Thickness(16, 0, 16, 0),
            margin: new Thickness(0, 0, 8, 0));
        history.ToolTip = historyText;
        history.Click += (_, _) => OpenOwned(ShellWindowKind.History);
        var settingsText = L.Get("common.settings");
        var settings = HomeUi.Button(HomeUi.IconLabel(Glyphs.Settings, settingsText), padding: new Thickness(16, 0, 16, 0));
        settings.ToolTip = settingsText;
        settings.Click += (_, _) => OpenSettings();
        buttons.Children.Add(history);
        buttons.Children.Add(settings);
        DockPanel.SetDock(buttons, Dock.Right);
        header.Children.Add(buttons);

        var brand = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
        brand.Children.Add(new LogoBox { Width = 36, Height = 36, VerticalAlignment = VerticalAlignment.Center });
        var name = HomeUi.Text(L.Get("app.error.title"), "Text.Title", new Thickness(12, 0, 0, 0));
        name.VerticalAlignment = VerticalAlignment.Center;
        name.TextWrapping = TextWrapping.NoWrap;
        brand.Children.Add(name);
        DockPanel.SetDock(brand, Dock.Left);
        header.Children.Add(brand);
        return header;
    }

    // ---- Orta alan (§3.3) ----

    FrameworkElement BuildMiddle()
    {
        var scroll = new ScrollViewer
        {
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled,
            Focusable = false,
            IsTabStop = false,
        };
        var grid = new Grid();
        grid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        // İçi en az görünen alan kadar yüksek: arayüz kalan yerde ortalanır. Kaydırıcı yüksekliği sınırlamadığı için
        // sahne (yalnız küçülen Viewbox) kartlardan kalan yüksekliğe ayrıca sığdırılır.
        void Fit()
        {
            grid.MinHeight = scroll.ViewportHeight;
            _stage.MaxHeight = Math.Max(160, scroll.ViewportHeight - _stage.Margin.Top - _stage.Margin.Bottom
                - _cards.Panel.ActualHeight);
        }
        scroll.ScrollChanged += (_, _) => Fit();
        scroll.SizeChanged += (_, _) => Fit();
        _cards.Panel.SizeChanged += (_, _) => Fit();

        _stage.HorizontalAlignment = HorizontalAlignment.Center;
        _stage.VerticalAlignment = VerticalAlignment.Center;
        Grid.SetRow(_stage, 0);
        grid.Children.Add(_stage);

        _cards.Panel.MaxWidth = 640;
        _cards.Panel.HorizontalAlignment = HorizontalAlignment.Center;
        Grid.SetRow(_cards.Panel, 1);
        grid.Children.Add(_cards.Panel);

        scroll.Content = grid;
        return scroll;
    }

    /// <summary>
    /// Seçili arayüz (§3.3): ayardaki ana ekran biçimi ve salonun Xbox'lı mı olduğu değişince yeniden kurulur, aynıysa
    /// dokunulmaz.
    /// </summary>
    void RefreshStage()
    {
        var kind = (_controller.HomeStyle, _controller.HomeSceneIsXbox);
        if (_stageKind == kind) return;
        _stageKind = kind;
        if (_stage.Content is IDisposable old) old.Dispose();
        _stage.Content = kind.Item1 == HomeStyle.Toggle
            ? new GlassToggle(_controller)
            : new LivingRoomScene(_controller, kind.Item2);
    }

    // ---- Alt şerit (§3.2) ----

    FrameworkElement BuildFooter()
    {
        var border = new Border
        {
            Margin = new Thickness(0, 12, 0, 0),
            Padding = new Thickness(0, 10, 0, 0),
            BorderThickness = new Thickness(0, 1, 0, 0),
        };
        border.SetResourceReference(Border.BorderBrushProperty, "borderBrush");

        var dock = new DockPanel { LastChildFill = false };

        // Sağ: "Çeviri <kaynak> ›" bağlantısı (odak almaz, el imleci) → Ayarlar.
        var lead = new Run(L.Get("home.footer.translation"));
        lead.SetResourceReference(TextElement.ForegroundProperty, "textSecondaryBrush");
        var arrow = new Run("›");
        arrow.SetResourceReference(TextElement.ForegroundProperty, "textSecondaryBrush");
        _translationSource.SetResourceReference(TextElement.ForegroundProperty, "textPrimaryBrush");
        _translationLink.Inlines.Add(lead);
        _translationLink.Inlines.Add(new Run(" "));
        _translationLink.Inlines.Add(_translationSource);
        _translationLink.Inlines.Add(new Run(" "));
        _translationLink.Inlines.Add(arrow);
        _translationLink.MouseLeftButtonUp += (_, _) => OpenSettings();
        DockPanel.SetDock(_translationLink, Dock.Right);
        dock.Children.Add(_translationLink);

        // Sol: görüntü kaynağı ve TV.
        var left = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
        left.Children.Add(_sourceDot);
        // Uzun durum metni sağdaki bağlantıya taşmasın diye kısaltılır.
        var source = new TextBlock
        {
            TextWrapping = TextWrapping.NoWrap,
            TextTrimming = TextTrimming.CharacterEllipsis,
            MaxWidth = 560,
            VerticalAlignment = VerticalAlignment.Center,
        };
        _sourceValue.SetResourceReference(TextElement.ForegroundProperty, "textSecondaryBrush");
        source.Inlines.Add(_sourceName);
        source.Inlines.Add(new Run(" "));
        source.Inlines.Add(_sourceValue);
        left.Children.Add(source);
        left.Children.Add(_tvDot);
        _tvValue.SetResourceReference(TextElement.ForegroundProperty, "textSecondaryBrush");
        _tvText.Inlines.Add(new Run(L.Get("reading.target.tv")) { FontWeight = FontWeights.SemiBold });
        _tvText.Inlines.Add(new Run(" "));
        _tvText.Inlines.Add(_tvValue);
        _tvText.MouseLeftButtonUp += (_, _) =>
        {
            if (_footer?.TvClickOpensSetup == true) _controller.GoToStep(SetupStep.Tv);
        };
        left.Children.Add(_tvText);
        DockPanel.SetDock(left, Dock.Left);
        dock.Children.Add(left);

        border.Child = dock;
        return border;
    }

    void RefreshFooter()
    {
        var state = HomeFooter.Compute(HomeFooter.Read(_controller), _controller.Text);
        if (state == _footer) return;
        _footer = state;
        _sourceName.Text = state.SourceName;
        _sourceValue.Text = state.SourceValue;
        _sourceDot.Tone = state.SourceTone;
        _tvDot.Show(state.TvVisible);
        _tvText.Show(state.TvVisible);
        _tvValue.Text = state.TvValue;
        _tvDot.Tone = state.TvTone;
        _translationSource.Text = state.TranslationSource;
        AutomationProperties.SetName(_translationLink, L.Format("home.footer.translationLink", state.TranslationSource));
    }

    // ---- Pencereler ----

    void OpenSettings() => OpenOwned(ShellWindowKind.Settings);

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
        if (_stage.Content is IDisposable stage) stage.Dispose();
    }
}
