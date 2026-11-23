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
/// Ana ekranın uyarı kartları yığını (Mac'in uyarılarıyla aynı yerde: sahnenin/anahtarın altında, en çok 640 geniş,
/// aralık 12), yukarıdan aşağı: güvenlik duvarı, model eksik, dil desteklenmiyor, GPU, ücretsiz motor, çevrimiçi motor,
/// yazı tanıma. Başlıklar uyarı renginde, simgeli. Yeni sürüm kartı yerine üstte yeni sürüm şeridi ve alt şeritte durum
/// var; oyun kartı Mac'teki gibi yok (oyun alt şeritteki çeviri bağlantısında yazar). Görünmeyen kart yer kaplamaz.
/// </summary>
internal sealed class HomeCards : IDisposable
{
    readonly NinoController _c;
    readonly Action _openSettings;
    readonly List<FrameworkElement> _order = [];

    // Güvenlik duvarı (ayarlar bölümünün kartı)
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

        // Güvenlik duvarı
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

        _order.AddRange(new FrameworkElement?[] { _firewall, _model, _unsupported, _gpu, _engine, _online, _ocr }
            .OfType<FrameworkElement>());
        foreach (var card in _order) Panel.Children.Add(card);
    }

    /// <summary>Kartların yığını.</summary>
    public StackPanel Panel { get; } = new();

    /// <summary>Durumları denetleyiciden yeniden okur.</summary>
    public void Refresh()
    {
        // Model
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
            if (_onlineTitle.Inlines.LastInline is System.Windows.Documents.Run titleRun)
                titleRun.Text = L.Format("home.card.online.title", _c.OnlineEngineName);
            _onlineHint.Text = (_c.OnlineProblemText ?? "") + " " + L.Get("home.card.online.fallback");
        }

        // 9
        _ocr.Show(_c.OcrMissing);

        // Boşluklar: kartlar arası 12 (ilk kartın üstü yığının dışında).
        var first = true;
        foreach (var card in _order)
        {
            if (card.Visibility != Visibility.Visible) continue;
            card.Margin = new Thickness(0, first ? 0 : 12, 0, 0);
            first = false;
        }
        Panel.Show(!first);
    }

    public void Dispose()
    {
        if (_firewall is IDisposable firewall) firewall.Dispose();
    }

    Button SettingsButton()
    {
        var button = HomeUi.Button(L.Get("common.settings"));
        button.Click += (_, _) => _openSettings();
        return button;
    }

    /// <summary>Uyarı başlığı: body yarı kalın, warning renginde, önünde uyarı simgesi (Mac'in uyarı kartı gibi).</summary>
    static TextBlock Warning(string text, string brush = "warningBrush")
    {
        var title = HomeUi.Text("", "Text.Body").Brush(TextBlock.ForegroundProperty, brush);
        title.FontWeight = FontWeights.SemiBold;
        var icon = new System.Windows.Documents.Run(Glyphs.Warning + "  ");
        icon.SetResourceReference(System.Windows.Documents.TextElement.FontFamilyProperty, "font.icon");
        title.Inlines.Add(icon);
        title.Inlines.Add(new System.Windows.Documents.Run(text));
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
