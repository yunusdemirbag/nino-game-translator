// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Input;
using Nino.App.Controls;
using Nino.App.Strings;
using Nino.Shell;

namespace Nino.App.Views;

/// <summary>
/// Ana ekranın uyarı kartları yığını (ana-ekran §3.4), yukarıdan aşağı: yeni sürüm, oynanan oyun, güvenlik duvarı,
/// model eksik, dil desteklenmiyor, GPU, ücretsiz motor, çevrimiçi motor, yazı tanıma. İlki üstten 8, diğerleri 16
/// boşlukla; görünmeyen kart yer kaplamaz.
/// </summary>
internal sealed class HomeCards : IDisposable
{
    readonly NinoController _c;
    readonly Action _openSettings;
    readonly List<FrameworkElement> _order = [];

    // 1. Yeni sürüm
    readonly Card _update = new();
    readonly TextBlock _updateTitle;
    readonly ProgressBar _updateProgress = new() { Margin = new Thickness(0, 12, 0, 0) };
    readonly TextBlock _updateError;
    readonly Button _updateButton;

    // 2. Şu anki oyun
    readonly GameCard _game;

    // 3. Güvenlik duvarı (ayarlar bölümünün kartı)
    readonly FrameworkElement? _firewall;

    // 4. Model
    readonly Card _model = new();
    readonly FrameworkElement _modelDownloading;
    readonly ProgressBar _modelProgress = new();
    readonly Button _modelButton;

    // 5–9
    readonly Card _unsupported = new();
    readonly Card _gpu = new();
    readonly Card _engine = new();
    readonly Card _online = new();
    readonly TextBlock _onlineTitle;
    readonly TextBlock _onlineHint;
    readonly Card _ocr = new();
    readonly Button _ocrInstall;

    public HomeCards(NinoController controller, Action openSettings)
    {
        _c = controller;
        _openSettings = openSettings;

        // 1. Yeni sürüm
        _updateTitle = Warning("", "accentTextBrush");
        _updateError = HomeUi.Text("", "Text.Callout", new Thickness(0, 8, 0, 0)).Brush(TextBlock.ForegroundProperty, "dangerBrush");
        _updateButton = HomeUi.Button("", "Button.Primary", margin: new Thickness(0, 12, 0, 0));
        _updateButton.Click += async (_, _) =>
        {
            try { await _c.InstallUpdateAsync(); } catch (Exception) { }
        };
        _update.Content = Stack(_updateTitle, _updateProgress, _updateError, _updateButton);

        // 2. Şu anki oyun
        _game = new GameCard(controller);

        // 3. Güvenlik duvarı
        _firewall = ShellWindows.CreateFirewallCard(controller);

        // 4. Model
        var downloading = HomeUi.Text(L.Get("home.card.model.downloading"), "Text.Callout", new Thickness(0, 0, 0, 8));
        _modelDownloading = Stack(downloading, _modelProgress);
        _modelDownloading.Margin = new Thickness(0, 12, 0, 0);
        _modelButton = HomeUi.Button(L.Get("home.card.model.download"), margin: new Thickness(0, 12, 0, 0));
        _modelButton.Click += (_, _) => _c.StartModelDownload();
        _model.Content = Stack(Warning(L.Get("home.card.model.title")), _modelDownloading, _modelButton);

        // 5. Dil desteklenmiyor
        _unsupported.Content = Stack(Warning(L.Get("home.card.unsupportedLanguage.title")),
            Hint(L.Get("home.card.unsupportedLanguage.hint"), new Thickness(0, 8, 0, 12)), SettingsButton());

        // 6. GPU
        _gpu.Content = HomeUi.Text(L.Get("home.card.gpu.warning"), "Text.Error");

        // 7. Ücretsiz motor açılamadı
        _engine.Content = Stack(Warning(L.Get("home.card.engineFailed.title")),
            Hint(L.Get("home.card.engineFailed.hint"), new Thickness(0, 8, 0, 12)), SettingsButton());

        // 8. Çevrimiçi motor
        _onlineTitle = Warning("");
        _onlineHint = Hint("", new Thickness(0, 8, 0, 0));
        _online.Content = Stack(_onlineTitle, _onlineHint);

        // 9. Yazı tanıma dili eksik
        _ocrInstall = HomeUi.Button(L.Get("home.card.ocr.install"), margin: new Thickness(0, 0, 8, 8));
        _ocrInstall.Click += async (_, _) => await OcrInstaller.InstallAsync(_c, _ocrInstall);
        var openLanguage = HomeUi.Button(L.Get("home.card.ocr.openLanguageSettings"), margin: new Thickness(0, 0, 0, 8));
        openLanguage.Click += (_, _) => OcrInstaller.OpenLanguageSettings();
        var buttons = new WrapPanel();
        buttons.Children.Add(_ocrInstall);
        buttons.Children.Add(openLanguage);
        _ocr.Content = Stack(Warning(L.Get("home.card.ocr.title")),
            Hint(L.Get("home.card.ocr.hint"), new Thickness(0, 8, 0, 12)), buttons);

        _order.AddRange(new FrameworkElement?[] { _update, _game, _firewall, _model, _unsupported, _gpu, _engine, _online, _ocr }
            .OfType<FrameworkElement>());
        foreach (var card in _order) Panel.Children.Add(card);
    }

    /// <summary>Kartların yığını.</summary>
    public StackPanel Panel { get; } = new();

    /// <summary>Durumları denetleyiciden yeniden okur.</summary>
    public void Refresh()
    {
        // 1
        _update.Show(_c.UpdateVersion is not null);
        if (_c.UpdateVersion is { } version) _updateTitle.Text = L.Format("home.card.update.title", version);
        _updateProgress.Show(_c.Updating);
        _updateProgress.Value = _c.UpdateProgress;
        _updateError.Text = _c.UpdateError ?? "";
        _updateError.Show(!string.IsNullOrEmpty(_c.UpdateError));
        _updateButton.Content = L.Get(_c.CanSelfUpdate ? "home.card.update.updateNow" : "translation.model.download");
        _updateButton.IsEnabled = !_c.Updating;

        // 2
        _game.Show(_c.IsTranslating);
        _game.Refresh();

        // 4
        _model.Show(!_c.ModelInstalled);
        _modelDownloading.Show(_c.ModelDownloading);
        _modelProgress.Value = _c.ModelProgress;
        _modelButton.Show(!_c.ModelDownloading);

        // 5–7
        _unsupported.Show(_c.TranslatorStatus == TranslatorStatus.Unsupported);
        _gpu.Show(_c.GpuFellBack);
        _engine.Show(_c.TranslatorStatus == TranslatorStatus.EngineFailed);

        // 8
        var online = _c.IsTranslating && _c.OnlineProblem is not null;
        _online.Show(online);
        if (online)
        {
            _onlineTitle.Text = L.Format("home.card.online.title", _c.OnlineEngineName);
            _onlineHint.Text = (_c.OnlineProblemText ?? "") + " " + L.Get("home.card.online.fallback");
        }

        // 9
        _ocr.Show(_c.OcrMissing);

        // Boşluklar: ilk görünen üstten 8, diğerleri 16.
        var first = true;
        foreach (var card in _order)
        {
            if (card.Visibility != Visibility.Visible) continue;
            card.Margin = new Thickness(0, first ? 8 : 16, 0, 0);
            first = false;
        }
    }

    public void Dispose()
    {
        _game.Dispose();
        if (_firewall is IDisposable firewall) firewall.Dispose();
    }

    Button SettingsButton()
    {
        var button = HomeUi.Button(L.Get("common.settings"));
        button.Click += (_, _) => _openSettings();
        return button;
    }

    static TextBlock Warning(string text, string brush = "warningBrush")
    {
        var title = HomeUi.Text(text, "Text.Body").Brush(TextBlock.ForegroundProperty, brush);
        title.FontWeight = FontWeights.SemiBold;
        return title;
    }

    static TextBlock Hint(string text, Thickness margin) => HomeUi.Text(text, "Text.Callout", margin);

    static StackPanel Stack(params UIElement[] children)
    {
        var panel = new StackPanel();
        foreach (var child in children) panel.Children.Add(child);
        return panel;
    }
}

/// <summary>
/// "Şu anki oyun" kartı (ana-ekran §3.4 kart 2), yalnız çeviri sürerken. Normal hâlde oyunun adı ve Seç/Değiştir;
/// denetleyici oyunu soruyorsa arama alanı, en çok 5 öneri ve "listede yok" düğmesi.
/// </summary>
internal sealed class GameCard : Card, IDisposable
{
    readonly NinoController _c;
    readonly Grid _normal = new();
    readonly TextBlock _name;
    readonly Button _choose;
    readonly StackPanel _question = new();
    readonly TextBox _search = new();
    readonly StackPanel _suggestions = new() { Margin = new Thickness(0, 8, 0, 0) };
    readonly Button _useTyped;
    bool? _asking;
    string? _shownFor;

    public GameCard(NinoController controller)
    {
        _c = controller;
        // Örtük kart stili yalnız tam Card türüne uyar; alt tür de aynı stili alsın.
        SetResourceReference(StyleProperty, typeof(Card));

        // Normal hâl
        _normal.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        _normal.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var labels = new StackPanel();
        labels.Children.Add(HomeUi.Text(L.Get("home.card.game.label"), "Text.Caption"));
        _name = HomeUi.Text("", "Text.Headline", new Thickness(0, 4, 0, 0));
        _name.TextWrapping = TextWrapping.NoWrap;
        _name.TextTrimming = TextTrimming.CharacterEllipsis;
        labels.Children.Add(_name);
        _normal.Children.Add(labels);
        _choose = HomeUi.Button("", padding: new Thickness(16, 0, 16, 0));
        _choose.VerticalAlignment = VerticalAlignment.Center;
        _choose.Margin = new Thickness(12, 0, 0, 0);
        _choose.Click += (_, _) => _c.ChangeGame();
        Grid.SetColumn(_choose, 1);
        _normal.Children.Add(_choose);

        // Soru hâli
        var top = new DockPanel { LastChildFill = true };
        var dontAsk = HomeUi.Button(L.Get("reading.gamePicker.dontAsk"), padding: new Thickness(12, 0, 12, 0));
        dontAsk.VerticalAlignment = VerticalAlignment.Top;
        dontAsk.Margin = new Thickness(12, 0, 0, 0);
        dontAsk.Click += (_, _) => _c.DismissGamePicker();
        DockPanel.SetDock(dontAsk, Dock.Right);
        top.Children.Add(dontAsk);
        top.Children.Add(HomeUi.Text(L.Get("reading.gamePicker.title"), "Text.Headline"));
        _question.Children.Add(top);
        _question.Children.Add(HomeUi.Text(L.Get("home.card.game.hint"), "Text.Callout", new Thickness(0, 8, 0, 12)));
        _question.Children.Add(HomeUi.Text(L.Get("home.card.game.search"), "Text.Caption", new Thickness(0, 0, 0, 4)));
        AutomationProperties.SetName(_search, L.Get("home.card.game.search"));
        _search.TextChanged += (_, _) => RefreshSuggestions(force: true);
        _search.KeyDown += (_, e) =>
        {
            if (e.Key != Key.Enter) return;
            var typed = _search.Text.Trim();
            if (typed.Length > 0)
            {
                e.Handled = true;
                _c.ChooseGame(typed);
            }
        };
        _question.Children.Add(_search);
        _question.Children.Add(_suggestions);
        _useTyped = HomeUi.Button("", padding: new Thickness(16, 0, 16, 0), margin: new Thickness(0, 8, 0, 0));
        _useTyped.Click += (_, _) => _c.ChooseGame(_search.Text.Trim());
        _question.Children.Add(_useTyped);

        var content = new Grid();
        content.Children.Add(_normal);
        content.Children.Add(_question);
        Content = content;
    }

    public void Refresh()
    {
        var asking = _c.GamePickerOpen;
        if (asking != _asking)
        {
            _asking = asking;
            _normal.Show(!asking);
            _question.Show(asking);
            if (!asking) _search.Text = "";
            RefreshSuggestions(force: true);
        }
        var game = _c.PlayingGame;
        _name.Text = string.IsNullOrEmpty(game) ? L.Get("home.card.game.unknown") : game;
        _choose.Content = L.Get(string.IsNullOrEmpty(game) ? "tv.choose" : "common.change");
    }

    void RefreshSuggestions(bool force)
    {
        if (_asking != true)
        {
            _suggestions.Children.Clear();
            _useTyped.Show(false);
            _shownFor = null;
            return;
        }
        var typed = _search.Text;
        if (!force && typed == _shownFor) return;
        _shownFor = typed;
        var all = _c.GameSuggestions(typed);
        var shown = GamePickerRule.Shown(all);
        var last = _c.LastChosenGame;
        _suggestions.Children.Clear();
        foreach (var name in shown)
        {
            var row = new DockPanel { LastChildFill = true };
            if (!string.IsNullOrEmpty(last) && string.Equals(name, last, StringComparison.Ordinal))
            {
                var tag = HomeUi.Text(L.Get("home.card.game.lastPlayed"), "Text.Caption", new Thickness(12, 0, 0, 0));
                tag.VerticalAlignment = VerticalAlignment.Center;
                tag.TextWrapping = TextWrapping.NoWrap;
                DockPanel.SetDock(tag, Dock.Right);
                row.Children.Add(tag);
            }
            row.Children.Add(new TextBlock
            {
                Text = name,
                TextWrapping = TextWrapping.NoWrap,
                TextTrimming = TextTrimming.CharacterEllipsis,
                VerticalAlignment = VerticalAlignment.Center,
            });
            var button = HomeUi.Button(row, "Button.Ghost", margin: new Thickness(0, 2, 0, 2));
            button.HorizontalAlignment = HorizontalAlignment.Stretch;
            button.HorizontalContentAlignment = HorizontalAlignment.Stretch;
            var chosen = name;
            button.Click += (_, _) => _c.ChooseGame(chosen);
            _suggestions.Children.Add(button);
        }
        var offer = GamePickerRule.OffersTyped(typed, all);
        _useTyped.Show(offer);
        if (offer) _useTyped.Content = L.Format("home.card.game.useTyped", typed.Trim());
    }

    public void Dispose() { }
}
