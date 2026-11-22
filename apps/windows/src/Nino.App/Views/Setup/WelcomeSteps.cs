// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using Nino.App.Controls;
using Nino.App.Strings;
using Nino.Core.Data;
using Nino.Core.Translation;
using Nino.Shell;

namespace Nino.App.Views.Setup;

/// <summary>Hoş geldin (kurulum.md §2): konsol seçimi, gereksinimler, kısa yollar ve sağ üstte çeviri dili.</summary>
internal sealed class WelcomeStep : StepPage
{
    readonly WizardStep _layout;
    readonly RadioButton _ps5;
    readonly RadioButton _xbox;
    readonly TextBlock _xboxNeeds;
    readonly Card _ps5Needs;
    readonly ComboBox _language = new() { MinWidth = 190 };
    bool _syncing;

    public WelcomeStep(NinoController controller) : base(controller)
    {
        var group = "console-" + Guid.NewGuid().ToString("N");
        _ps5 = new RadioButton { Content = "PlayStation 5", GroupName = group, Margin = new Thickness(0, 4, 0, 12) };
        _xbox = new RadioButton { Content = L.Get("setup.welcome.consoleXbox"), GroupName = group };
        _ps5.Checked += (_, _) => Choose(StoredConsoleKind.PlayStation);
        _xbox.Checked += (_, _) => Choose(StoredConsoleKind.Xbox);
        var consoles = SetupUi.Card(SetupUi.Stack(_ps5, _xbox), L.Get("setup.welcome.chooseConsole"), SetupUi.Bottom(16));

        _xboxNeeds = SetupUi.Key("setup.welcome.xboxRequirements", "Text.Callout");
        _ps5Needs = SetupUi.Card(SetupUi.Stack(
            SetupUi.Key("setup.welcome.needPs5", "Text.Body", SetupUi.Bottom(8)),
            SetupUi.Key("setup.welcome.needLgTv", "Text.Body", SetupUi.Bottom(8)),
            SetupUi.Key("setup.welcome.needSecondAccount")), L.Get("setup.welcome.youWillNeed"));

        var remotePlay = SetupUi.Button(L.Get("setup.welcome.shortcutRemotePlay"), ButtonKind.Secondary,
            (_, _) => C.UseGameWindowHere(), SetupUi.M(0, 0, 12, 0));
        remotePlay.Padding = new Thickness(16, 0, 16, 0);
        var xboxWindow = SetupUi.Button(L.Get("setup.welcome.shortcutXbox"), ButtonKind.Secondary,
            (_, _) => C.UseXboxWindow(), SetupUi.M(0, 0, 12, 0));
        xboxWindow.Padding = new Thickness(16, 0, 16, 0);
        xboxWindow.ToolTip = L.Get("setup.welcome.shortcutXboxTooltip");
        var cardLabel = SetupUi.Text(L.Get("setup.welcome.shortcutCaptureCard"), "Text.Inherit", SetupUi.M(8, 0, 0, 0));
        cardLabel.VerticalAlignment = VerticalAlignment.Center;
        var cardContent = SetupUi.Row(SetupUi.Glyph(Glyphs.Connect, 16, "accentTextBrush"), cardLabel);
        var card = SetupUi.Button(cardContent, ButtonKind.Ghost, (_, _) => C.OpenCardGuide());
        card.ToolTip = L.Get("setup.welcome.shortcutCaptureCardTooltip");
        AutomationProperties.SetName(card, L.Get("setup.welcome.shortcutCaptureCard"));
        var shortcuts = new WrapPanel { Margin = SetupUi.Top(16) };
        shortcuts.Children.Add(remotePlay);
        shortcuts.Children.Add(xboxWindow);
        shortcuts.Children.Add(card);

        var content = SetupUi.Stack(consoles, _xboxNeeds, _ps5Needs, shortcuts,
            SetupUi.Key("setup.welcome.shortcutsHint", "Text.Callout", SetupUi.Top(8)));
        _layout = new WizardStep { Title = L.Get("setup.welcome.title"), Content = content };

        // Çeviri dili seçicisi: adım düzeninin üstünde, görünürde hep sağ üstte, her zaman soldan sağa.
        _language.FlowDirection = FlowDirection.LeftToRight;
        _language.HorizontalAlignment = L.IsRightToLeft ? HorizontalAlignment.Left : HorizontalAlignment.Right;
        _language.VerticalAlignment = VerticalAlignment.Top;
        // Sağdan sola düzende mantıksal sol görünürde sağdır: 4 px boşluk o yana.
        _language.Margin = L.IsRightToLeft ? new Thickness(4, 4, 0, 0) : new Thickness(0, 4, 4, 0);
        AutomationProperties.SetName(_language, L.Get("setup.welcome.translationLanguage"));
        _language.SelectionChanged += (_, _) => LanguageChosen();

        var root = new Grid();
        root.Children.Add(_layout);
        root.Children.Add(_language);
        Content = root;

        BuildLanguages();
        SyncConsole();
    }

    protected override void OnChanged(string property)
    {
        if (property is nameof(NinoController.IsXbox) or nameof(NinoController.ConsoleKindLocked)) SyncConsole();
        if (property == nameof(NinoController.Settings)) SyncLanguage();
    }

    void Choose(StoredConsoleKind kind)
    {
        if (_syncing || !IsLoaded) return;
        C.SetConsoleKind(kind);
        SyncConsole();
    }

    void SyncConsole()
    {
        _syncing = true;
        try
        {
            var xbox = C.IsXbox;
            _ps5.IsChecked = !xbox;
            _xbox.IsChecked = xbox;
            _ps5.IsEnabled = _xbox.IsEnabled = !C.ConsoleKindLocked;
            _layout.Description = L.Get(xbox ? "setup.welcome.descriptionXbox" : "setup.welcome.descriptionPs5");
            SetupUi.Show(_xboxNeeds, xbox);
            SetupUi.Show(_ps5Needs, !xbox);
        }
        finally { _syncing = false; }
    }

    // Liste sabittir: bir kez kurulur; ayarlar değişince yalnız seçim eşitlenir (seçim olayının içinde liste
    // silinmesin).
    void BuildLanguages()
    {
        _syncing = true;
        try
        {
            foreach (var language in TargetLanguages.All)
            {
                var name = SetupUi.Text(language.NativeName, "Text.Inherit", new Thickness(10, 0, 0, 0));
                name.VerticalAlignment = VerticalAlignment.Center;
                var flag = new LanguageFlag { Code = language.Code, VerticalAlignment = VerticalAlignment.Center };
                var row = SetupUi.Row(flag, name);
                row.FlowDirection = FlowDirection.LeftToRight;
                var item = new ComboBoxItem { Content = row, Tag = language.Code };
                AutomationProperties.SetName(item, language.NativeName);
                _language.Items.Add(item);
            }
        }
        finally { _syncing = false; }
        SyncLanguage();
    }

    void SyncLanguage()
    {
        var current = TargetLanguages.Code(C.Settings.TargetLanguage);
        _syncing = true;
        try
        {
            foreach (ComboBoxItem item in _language.Items)
                if (item.Tag is string code && code == current && !ReferenceEquals(_language.SelectedItem, item))
                    _language.SelectedItem = item;
        }
        finally { _syncing = false; }
    }

    void LanguageChosen()
    {
        if (_syncing || _language.SelectedItem is not ComboBoxItem { Tag: string code }) return;
        var settings = C.Settings;
        if (TargetLanguages.Code(settings.TargetLanguage) == code) return;
        settings.TargetLanguage = code;
        C.UpdateSettings(settings);
    }
}

/// <summary>İkinci bir PSN hesabı (kurulum.md §3; Xbox'ta yok).</summary>
internal sealed class SecondAccountStep : StepPage
{
    public SecondAccountStep(NinoController controller) : base(controller)
    {
        var steps = SetupUi.Stack(
            SetupUi.Numbered(1, L.Get("setup.psnAccount.step1")),
            SetupUi.Numbered(2, L.Get("setup.psnAccount.step2")),
            SetupUi.Numbered(3, L.Get("setup.psnAccount.step3")),
            SetupUi.Numbered(4, L.Get("setup.psnAccount.step4")));

        var remotePlay = SetupUi.Stack(
            SetupUi.TopRow(SetupUi.Strong(L.Get("setup.psnAccount.remotePlayWindowTitle")),
                SetupUi.Button(L.Get("setup.select"), ButtonKind.Secondary, (_, _) => C.UseRemotePlayWindow())),
            SetupUi.Key("setup.psnAccount.remotePlayWindowHint", "Text.Callout", SetupUi.Top(8)));
        if (C.IsRemotePlayAppMissing())
        {
            var downloads = SetupUi.Row(
                SetupUi.Button(L.Get("setup.psnAccount.downloadRemotePlay"), ButtonKind.Secondary,
                    (_, _) => SetupUi.Open("https://remoteplay.dl.playstation.net/remoteplay/"), SetupUi.M(0, 0, 8, 0)),
                SetupUi.Button(L.Get("setup.psnAccount.downloadChiaki"), ButtonKind.Secondary,
                    (_, _) => SetupUi.Open("https://github.com/chiaki-ng/chiaki-ng/releases/latest")));
            downloads.Margin = SetupUi.Top(8);
            var section = SetupUi.Stack(SetupUi.Key("setup.psnAccount.noRemotePlayApp", "Text.Callout"), downloads);
            section.Margin = SetupUi.Top(12);
            remotePlay.Children.Add(section);
        }

        var captureWindow = SetupUi.Stack(
            SetupUi.TopRow(SetupUi.Strong(L.Get("setup.psnAccount.captureWindowTitle")),
                SetupUi.Button(L.Get("setup.select"), ButtonKind.Secondary, (_, _) => C.UseChosenWindow())),
            SetupUi.Key("setup.psnAccount.captureWindowHint", "Text.Callout", SetupUi.Top(8)));

        Layout(L.Get("setup.psnAccount.title"), L.Get("setup.psnAccount.description"), SetupUi.Stack(
            steps,
            SetupUi.Key("setup.psnAccount.mainAccountHint", "Text.Callout", SetupUi.Top(8)),
            SetupUi.Card(remotePlay, margin: SetupUi.Top(16)),
            SetupUi.Card(captureWindow, margin: SetupUi.Top(12))));
    }
}
