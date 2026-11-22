// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.ComponentModel;
using System.Globalization;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using Nino.App.Controls;
using Nino.App.Strings;
using Nino.Core.Data;
using Nino.Core.Library;
using Nino.Shell;

namespace Nino.App.Views;

/// <summary>
/// Geçmiş penceresi (yan pencereler tarifi §2): son 200 çevrilen satır, en yenisi üstte; satır ve tümünü kopyalama,
/// onaysız temizleme. Açık kaldıkça geçmiş değişince hemen yeniden çizilir.
/// </summary>
public sealed class HistoryWindow : Window
{
    readonly NinoController _c;
    readonly StackPanel _list = new();
    readonly ScrollViewer _scroll;
    readonly TextBlock _empty;
    readonly Button _copyAll;
    readonly Button _clear;

    /// <summary>Tek pencere kuralıyla açar.</summary>
    public static HistoryWindow Open(NinoController controller, Window? owner) => Ui.ShowSingle(owner, () => new HistoryWindow(controller));

    public HistoryWindow(NinoController controller)
    {
        _c = controller;
        Ui.Prepare(this, L.Get("home.header.history"));
        Width = 640;
        Height = 640;
        MinWidth = 480;
        MinHeight = 400;

        var root = new Grid { Margin = new(24) };
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });

        var top = Ui.Column(Ui.Display(L.Get("home.header.history")),
            Ui.Hint(L.Format("history.subtitle", (long)SubtitleHistory.MaxEntries)).At(0, 4, 0, 0));
        top.Margin = new(0, 0, 0, 16);
        root.Children.Add(top);

        _empty = Ui.Hint(L.Get("history.empty"));
        _scroll = new ScrollViewer
        {
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled,
            Content = _list,
        };
        var cardBody = new Grid();
        cardBody.Children.Add(_empty);
        cardBody.Children.Add(_scroll);
        var card = new Card { Content = cardBody, VerticalContentAlignment = VerticalAlignment.Stretch };
        Grid.SetRow(card, 1);
        root.Children.Add(card);

        _copyAll = Ui.Button(L.Get("history.copyAll")).At(0, 0, 8, 0);
        _copyAll.Click += (_, _) =>
        {
            if (Ui.Copy(SubtitleHistory.CopyText(Ordered()))) _copyAll.Content = L.Get("common.copied");
        };
        _clear = Ui.Button(L.Get("history.clear"), () => _c.ClearHistory());
        var close = Ui.Primary(L.Get("common.close"), Close);
        close.IsCancel = true;
        var bottom = Ui.Split(Ui.Row(_copyAll, _clear), close);
        bottom.Margin = new(0, 16, 0, 0);
        Grid.SetRow(bottom, 2);
        root.Children.Add(bottom);
        Content = root;

        Render();
        _c.PropertyChanged += OnChanged;
        Closed += (_, _) => _c.PropertyChanged -= OnChanged;
    }

    void OnChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(NinoController.History)) Render();
    }

    IReadOnlyList<HistoryEntry> Ordered() => _c.History.OrderByDescending(h => h.Date).ThenByDescending(h => h.Id).ToList();

    void Render()
    {
        var entries = Ordered();
        _list.Children.Clear();
        _copyAll.Content = L.Get("history.copyAll");
        _empty.Shown(entries.Count == 0);
        _scroll.Shown(entries.Count > 0);
        _copyAll.IsEnabled = _clear.IsEnabled = entries.Count > 0;
        foreach (var entry in entries) _list.Children.Add(Row(entry));
    }

    static FrameworkElement Row(HistoryEntry entry)
    {
        var local = entry.Date.ToLocalTime();
        var source = entry.Origin == HistoryOrigin.Pack ? L.Get("history.source.pack") : L.Get("translation.engine.title");
        var header = Ui.Caption(local.ToString("HH:mm:ss", CultureInfo.InvariantCulture) + "  ·  " + source);
        header.Typography.NumeralAlignment = FontNumeralAlignment.Tabular;
        var text = Ui.Column(header, Ui.Headline(entry.Translation).At(0, 4, 0, 0), Ui.Caption(entry.Source).At(0, 4, 0, 0));
        Button? copy = null;
        copy = Ui.Button(L.Get("common.copy"), () =>
        {
            if (Ui.Copy(entry.Translation + "\n" + entry.Source)) copy!.Content = L.Get("common.copied");
        });
        copy.Padding = new(12, 0, 12, 0);
        copy.VerticalAlignment = VerticalAlignment.Top;
        var row = Ui.Split(text, copy, 12);
        var line = new Border { Padding = new(0, 12, 0, 12), BorderThickness = new(0, 0, 0, 1), Child = row };
        line.Res(Border.BorderBrushProperty, "borderBrush");
        return line;
    }
}

/// <summary>
/// Oyun paketi içe aktarma penceresi (yan pencereler tarifi §3): ad, sayımlar, hata satırı, Vazgeç / yükleme düğmesi.
/// Kalıcı (modal) açılır; "yüklendi" ile kapanırsa <c>DialogResult</c> doğrudur.
/// </summary>
public sealed class GamePackImportWindow : Window
{
    readonly NinoController _c;
    readonly PackImportPreview _preview;
    readonly string _sourcePath;
    readonly TextBox _title;
    readonly TextBlock _error;
    readonly Button _install;

    public GamePackImportWindow(NinoController controller, PackImportPreview preview, string sourcePath)
    {
        _c = controller;
        _preview = preview;
        _sourcePath = sourcePath;
        Ui.Prepare(this, L.Get("pack.import.title"));
        Width = 460;
        SizeToContent = SizeToContent.Height;
        ResizeMode = ResizeMode.NoResize;

        var panel = new StackPanel { Margin = new(24) };
        panel.Children.Add(Ui.Headline(L.Get("packImport.gameTitle")).At(0, 0, 0, 8));
        _title = new TextBox { Text = preview.SuggestedTitle ?? Path.GetFileNameWithoutExtension(sourcePath) };
        AutomationNames.Set(_title, L.Get("packImport.gameTitle"));
        panel.Children.Add(_title);

        var table = new Grid { Margin = new(0, 16, 0, 0) };
        table.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        table.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var counts = new[]
        {
            ("packImport.usable", preview.Entries.Count), ("packImport.invalid", preview.Invalid),
            ("packImport.duplicates", preview.Duplicates), ("packImport.conflicts", preview.Conflicts),
        };
        for (var i = 0; i < counts.Length; i++)
        {
            table.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            var label = Ui.Body(L.Get(counts[i].Item1)).At(0, i == 0 ? 0 : 6, 12, 0);
            var value = Ui.Body(counts[i].Item2.ToString("#,0", L.Catalog.Culture)).At(0, i == 0 ? 0 : 6, 0, 0);
            value.TextAlignment = TextAlignment.Right;
            value.Typography.NumeralAlignment = FontNumeralAlignment.Tabular;
            Grid.SetRow(label, i);
            Grid.SetRow(value, i);
            Grid.SetColumn(value, 1);
            table.Children.Add(label);
            table.Children.Add(value);
        }
        panel.Children.Add(table);

        _error = Ui.Error().At(0, 12, 0, 0).Shown(false);
        System.Windows.Automation.AutomationProperties.SetLiveSetting(_error, System.Windows.Automation.AutomationLiveSetting.Polite);
        panel.Children.Add(_error);

        var cancel = Ui.Button(L.Get("common.cancel"), Close).At(0, 0, 8, 0);
        cancel.IsCancel = true;
        _install = Ui.Primary(L.Get("packImport.install"), Install);
        _install.IsDefault = true;
        var buttons = Ui.Row(cancel, _install);
        buttons.HorizontalAlignment = HorizontalAlignment.Right;
        buttons.Margin = new(0, 16, 0, 0);
        panel.Children.Add(buttons);
        Content = panel;

        _title.TextChanged += (_, _) => UpdateInstall();
        UpdateInstall();
        if (preview.Entries.Count == 0) ShowError(L.Get("packImport.noUsable"));
        Loaded += (_, _) =>
        {
            _title.Focus();
            _title.SelectAll();
        };
    }

    void UpdateInstall() => _install.IsEnabled = _preview.Entries.Count > 0 && _title.Text.Trim().Length > 0;

    void ShowError(string text)
    {
        _error.Text = text;
        _error.Shown(true);
    }

    void Install()
    {
        var title = _title.Text.Trim();
        if (title.Length == 0 || _preview.Entries.Count == 0) return;
        _error.Shown(false);
        if (_c.UserPacksFolder is not { } folder)
        {
            ShowError(L.Get("packImport.installFailed"));
            return;
        }
        var target = PackImporter.TargetPath(folder, title);
        if (PackImporter.IsSameFile(_sourcePath, target))
        {
            ShowError(L.Get("packImport.sameLocation"));
            return;
        }
        var replace = false;
        if (File.Exists(target))
        {
            var answer = MessageBox.Show(this, L.Get("packImport.replace.message"), L.Get("packImport.replace.title"),
                MessageBoxButton.YesNo, MessageBoxImage.Warning, MessageBoxResult.No);
            if (answer != MessageBoxResult.Yes) return;
            replace = true;
        }
        try
        {
            PackImporter.Write(_preview, title, folder, _sourcePath, replace);
            DialogResult = true;
        }
        catch (PackImportException e) when (e.Error == PackImportError.SourceIsTarget)
        {
            ShowError(L.Get("packImport.sameLocation"));
        }
        catch (Exception e) when (e is PackImportException or IOException or UnauthorizedAccessException)
        {
            ShowError(L.Get("packImport.installFailed"));
        }
    }
}
