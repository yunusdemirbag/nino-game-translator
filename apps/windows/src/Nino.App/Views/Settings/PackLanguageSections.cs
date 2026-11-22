// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using Microsoft.Win32;
using Nino.App.Controls;
using Nino.App.Strings;
using Nino.Core.Library;
using Nino.Core.Settings;
using Nino.Core.Translation;
using Nino.Shell;
using Nino.Shell.Panels;

namespace Nino.App.Views;

/// <summary>§6 Paketler: açıklama, içe aktarma, paket karoları ve seçenekler kartı.</summary>
internal sealed class GamePacksSection(SettingsWindow host) : SettingsSection(host)
{
    Pill? _pill;
    readonly StackPanel _list = new();
    Button? _import;
    bool _closed;

    public override string SectionTitle => L.Get("pack.settings.title");

    protected override void Build()
    {
        _pill = new Pill { VerticalAlignment = VerticalAlignment.Center };
        Children.Add(Ui.Split(Ui.Display(SectionTitle), _pill).At(0, 0, 0, 8));
        Children.Add(Ui.Secondary(L.Get("settings.packs.description")).At(0, 0, 0, 16));
        _import = Ui.Button(L.Get("settings.packs.import"), () => _ = ImportAsync()).At(0, 0, 0, 16);
        Children.Add(_import);
        Children.Add(_list);
        RenderList();

        var options = new StackPanel();
        AddOption(options, "settings.packs.useGamePacks", null, s => s.GamePacks, (s, v) => s.GamePacks = v, first: true);
        AddOption(options, "settings.packs.sharePool", "settings.packs.sharePoolHint", s => s.SharePool, (s, v) => s.SharePool = v);
        AddOption(options, "settings.packs.askGame", "settings.packs.askGameHint", s => s.AskGame, (s, v) => s.AskGame = v);
        AddOption(options, "settings.packs.speakerNames", "settings.packs.speakerNamesHint", s => s.ShowSpeakerNames,
            (s, v) => s.ShowSpeakerNames = v);
        Children.Add(new Card { Content = options, Padding = new(20, 4, 20, 4) });
    }

    void AddOption(StackPanel into, string titleKey, string? hintKey, Func<AppSettings, bool> read, Action<AppSettings, bool> write,
        bool first = false)
    {
        if (!first) into.Children.Add(new Separator { Margin = new(-20, 0, -20, 0) });
        var text = Ui.Column(Ui.Headline(L.Get(titleKey)));
        if (hintKey is not null) text.Children.Add(Ui.Hint(L.Get(hintKey)).At(0, 4, 0, 0));
        text.VerticalAlignment = VerticalAlignment.Center;
        var toggle = Ui.Toggle();
        toggle.IsChecked = read(C.Settings);
        toggle.VerticalAlignment = VerticalAlignment.Center;
        AutomationNames.Set(toggle, L.Get(titleKey));
        toggle.Checked += (_, _) => Write(s => write(s, true));
        toggle.Unchecked += (_, _) => Write(s => write(s, false));
        var row = Ui.Split(text, toggle, 16);
        row.MinHeight = 44;
        row.Margin = new(0, 8, 0, 8);
        into.Children.Add(row);
    }

    void RenderList()
    {
        var packs = C.Packs;
        if (_pill is not null)
        {
            _pill.Text = L.Format("settings.packs.pill", packs.Count);
            _pill.Shown(packs.Count > 0);
        }
        _list.Children.Clear();
        if (TargetLanguages.Code(C.Settings.TargetLanguage) != "tr")
            _list.Children.Add(Ui.Hint(L.Get("settings.packs.turkishOnly")).At(0, 0, 0, 8));
        if (packs.Count == 0)
        {
            _list.Children.Add(Ui.Hint(L.Get("settings.packs.none")).At(0, 0, 0, 8));
            return;
        }
        var grid = new UniformGrid { Columns = 2, Margin = new(-8, 0, -8, 8) };
        foreach (var pack in packs)
        {
            var mono = new GameMonogram { Text = SettingsPanelRules.PackInitials(pack.Title), FontSize = 13, VerticalAlignment = VerticalAlignment.Center };
            var name = Ui.Headline(pack.Title);
            var lines = Ui.Caption(L.Format("settings.packs.lines", SettingsPanelRules.Thousands(pack.EntryCount, L.Catalog.Culture)))
                .At(0, 4, 0, 0);
            var text = Ui.Column(name, lines);
            text.VerticalAlignment = VerticalAlignment.Center;
            text.Margin = new(16, 0, 0, 0);
            var row = new DockPanel();
            DockPanel.SetDock(mono, Dock.Left);
            row.Children.Add(mono);
            row.Children.Add(text);
            grid.Children.Add(new Card { Content = row, Margin = new(8) });
        }
        _list.Children.Add(grid);
    }

    public override void ControllerChanged(string property)
    {
        if (property is nameof(NinoController.Packs) or nameof(NinoController.Settings)) RenderList();
    }

    public override void WindowClosed() => _closed = true;

    async Task ImportAsync()
    {
        var title = L.Get("pack.import.title");
        var dialog = new OpenFileDialog
        {
            Title = title,
            Filter = L.Get("settings.packs.importFilter") + "|*.json;*.txt;*.srt",
            CheckFileExists = true,
        };
        if (dialog.ShowDialog(Host) != true) return;
        var path = dialog.FileName;
        _import!.IsEnabled = false;
        PackImportPreview? preview = null;
        string? problem = null;
        try { preview = await Task.Run(() => PackImporter.Read(path)); }
        catch (PackImportException) { problem = "settings.packs.importInvalid"; }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or System.Security.SecurityException)
        {
            problem = "settings.packs.importUnreadable";
        }
        catch (Exception) { problem = "settings.packs.importInvalid"; }
        _import.IsEnabled = true;
        if (_closed || !Host.IsVisible) return;
        if (problem is not null)
        {
            MessageBox.Show(Host, L.Get(problem), title, MessageBoxButton.OK, MessageBoxImage.Error);
            return;
        }
        var window = new GamePackImportWindow(C, preview!, path) { Owner = Host };
        if (window.ShowDialog() == true) C.ReloadPacks();
    }
}

/// <summary>§7 Dil: oyunun dili ve çeviri dili.</summary>
internal sealed class LanguageSection(SettingsWindow host) : SettingsSection(host)
{
    static readonly string[] Sources = ["en", "ja", "de", "fr", "es"];
    TextBlock? _hint;

    public override string SectionTitle => L.Get("settings.section.language");

    protected override void Build()
    {
        AddHeader();
        var s = C.Settings;
        var body = new StackPanel();
        var game = Ui.Combo();
        foreach (var code in Sources.Where(C.CanTranslateFrom))
            game.Items.Add(Ui.Item(code, L.Get("settings.language.source." + code)));
        game.SelectTag(TargetLanguages.Code(s.SourceLanguage));
        if (game.SelectedIndex < 0 && game.Items.Count > 0) game.SelectedIndex = 0;
        game.SelectionChanged += (_, _) =>
        {
            if (game.SelectedTag() is string code) Write(x => x.SourceLanguage = code);
        };
        if (game.Items.Count > 1) body.Children.Add(Ui.Labeled(L.Get("settings.language.gameLanguage"), game).At(0, 0, 0, 12));

        var target = Ui.Combo();
        // Bayraklı satır veri şablonuyla çizilir (seçim kutusunda da görünsün diye öğe denetim değil, dil kodu).
        var label = new FrameworkElementFactory(typeof(LanguageLabel));
        label.SetBinding(LanguageLabel.CodeProperty, new System.Windows.Data.Binding());
        target.ItemTemplate = new DataTemplate { VisualTree = label };
        foreach (var language in TargetLanguages.All) target.Items.Add(language.Code);
        target.SelectedItem = TargetLanguages.Find(s.TargetLanguage)?.Code ?? "tr";
        target.SelectionChanged += (_, _) =>
        {
            if (target.SelectedItem is not string code) return;
            Write(x => x.TargetLanguage = code);
            UpdateHint();
        };
        body.Children.Add(Ui.Labeled(L.Get("setup.welcome.translationLanguage"), target));
        _hint = Ui.Hint(L.Get("settings.language.nonTurkishHint")).At(0, 12, 0, 0);
        body.Children.Add(_hint);
        UpdateHint();
        AddCard(Ui.Card(null, body));
    }

    void UpdateHint() => _hint?.Shown(TargetLanguages.Code(C.Settings.TargetLanguage) != "tr");

    public override void ControllerChanged(string property)
    {
        if (property == nameof(NinoController.Settings)) UpdateHint();
    }
}
