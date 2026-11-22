// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Threading;
using Nino.App.Strings;
using Nino.Core.Health;
using Nino.Core.Support;
using Nino.Shell;
using Nino.Shell.Panels;

namespace Nino.App.Views;

/// <summary>
/// Sorun bildirme penceresi (yan pencereler tarifi §10): Nino'nun gördükleri, açıklama, en çok 3 fotoğraf, iletişim,
/// günlük ve otomatik bildirim anahtarları; gönderim ve teşekkür ekranı. Taslak saklanmaz.
/// </summary>
public sealed class ReportProblemWindow : Window
{
    readonly NinoController _c;
    readonly PhotoAttachments _photos = new(SupportLimits.ReportPhotoBytes);
    readonly TextBox _description;
    readonly TextBox _contact;
    readonly CheckBox _includeLog;
    readonly WrapPanel _photoRow = new() { Margin = new(0, 16, 0, 0) };
    readonly TextBlock _error;
    readonly ProgressBar _progress;
    readonly Button _send;
    readonly Button _sendProblems;
    bool _sending;
    bool _closed;

    /// <summary>Tek pencere kuralıyla açar.</summary>
    public static ReportProblemWindow Open(NinoController controller, Window? owner) =>
        Ui.ShowSingle(owner, () => new ReportProblemWindow(controller));

    public ReportProblemWindow(NinoController controller)
    {
        _c = controller;
        Ui.Prepare(this, L.Get("settings.about.reportProblem"));
        Width = 540;
        SizeToContent = SizeToContent.Height;
        ResizeMode = ResizeMode.NoResize;

        var form = new StackPanel { Margin = new(28) };
        form.Children.Add(Ui.Title(L.Get("settings.about.reportProblem")).At(0, 0, 0, 16));

        // Nino'nun gördükleri.
        var noticed = new StackPanel();
        noticed.Children.Add(Ui.Headline(L.Get("report.noticed.title")).At(0, 0, 0, 8));
        var cause = HealthCauses.FirstTitle(_c.Health.Snapshot(), _c.Network, L.Catalog);
        var problems = SettingsPanelRules.NoticedProblems(_c.ProblemRecords(), DateTimeOffset.UtcNow);
        if (cause is null && problems.Count == 0) noticed.Children.Add(Ui.Hint(L.Get("report.noticed.empty")).At(0, 4, 0, 0));
        if (cause is not null) noticed.Children.Add(new TextBlock { Text = cause, FontWeight = FontWeights.SemiBold, TextWrapping = TextWrapping.Wrap });
        foreach (var p in problems)
        {
            var time = p.Date.ToLocalTime().ToString("t", L.Catalog.Culture);
            noticed.Children.Add(Ui.Secondary(L.Format("report.noticed.problemLine", time, p.ShortName(L.Catalog))).At(0, 4, 0, 0));
        }
        _sendProblems = Ui.Primary(L.Get("report.sendProblems"), () => _ = SendAsync());
        _sendProblems.MinWidth = 120;
        _sendProblems.HorizontalAlignment = HorizontalAlignment.Right;
        _sendProblems.Margin = new(0, 12, 0, 0);
        noticed.Children.Add(_sendProblems);
        var box = new Border { BorderThickness = new(1), CornerRadius = new(12), Padding = new(16), Child = noticed };
        box.Res(Border.BorderBrushProperty, "borderBrush");
        form.Children.Add(box);

        form.Children.Add(Ui.Headline(L.Get("report.moreTitle")).At(0, 20, 0, 8));
        _description = new TextBox
        {
            AcceptsReturn = true,
            TextWrapping = TextWrapping.Wrap,
            Height = 140,
            MaxLength = SupportLimits.Text,
            Padding = new(12, 10, 12, 10),
            VerticalContentAlignment = VerticalAlignment.Top,
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
        };
        form.Children.Add(Ui.WithPlaceholder(_description, L.Get("report.descriptionPlaceholder"), top: true));

        form.Children.Add(_photoRow);
        form.Children.Add(Ui.Hint(L.Get("report.photosHint")).At(0, 4, 0, 0));

        _contact = new TextBox { MaxLength = SupportLimits.Contact };
        form.Children.Add(Ui.WithPlaceholder(_contact, L.Get("report.contactPlaceholder"), top: false).At(0, 16, 0, 0));

        _includeLog = Ui.Toggle();
        _includeLog.IsChecked = true;
        form.Children.Add(SwitchRow("report.includeLog.title", "report.includeLog.hint", _includeLog).At(0, 16, 0, 0));
        var auto = Ui.Toggle();
        auto.IsChecked = _c.Settings.AutoReport;
        auto.Checked += (_, _) => SetAutoReport(true);
        auto.Unchecked += (_, _) => SetAutoReport(false);
        form.Children.Add(SwitchRow("report.autoReport.title", "report.autoReport.hint", auto).At(0, 16, 0, 0));
        form.Children.Add(Ui.Caption(L.Get("report.privacy")).At(0, 16, 0, 0));
        _error = Ui.Error().At(0, 12, 0, 0).Shown(false);
        form.Children.Add(_error);
        _progress = new ProgressBar { IsIndeterminate = true, Height = 3, Margin = new(0, 12, 0, 0), Visibility = Visibility.Collapsed };
        form.Children.Add(_progress);

        var cancel = Ui.Button(L.Get("common.cancel"), Close).At(0, 0, 12, 0);
        cancel.MinWidth = 100;
        cancel.IsCancel = true;
        _send = Ui.Primary(L.Get("common.send"), () => _ = SendAsync());
        _send.MinWidth = 120;
        var buttons = Ui.Row(cancel, _send);
        buttons.HorizontalAlignment = HorizontalAlignment.Right;
        buttons.Margin = new(0, 20, 0, 0);
        form.Children.Add(buttons);

        Content = new ScrollViewer
        {
            Content = form,
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled,
            MaxHeight = Math.Max(300, SystemParameters.WorkArea.Height - 80),
        };

        _photos.Blocked = () => _sending;
        _photos.Changed += RenderPhotos;
        _photos.Error += message =>
        {
            if (message is null) _error.Shown(false);
            else ShowError(message);
        };
        _photos.Attach(this);
        PreviewKeyDown += (_, e) => _photos.TryPaste(e);
        RenderPhotos();
        Loaded += (_, _) => _description.Focus();
        Closed += (_, _) => _closed = true;
    }

    void SetAutoReport(bool on)
    {
        var s = _c.Settings;
        if (s.AutoReport == on) return;
        s.AutoReport = on;
        _c.UpdateSettings(s);
    }

    static Grid SwitchRow(string titleKey, string hintKey, CheckBox toggle)
    {
        var text = Ui.Column(Ui.Headline(L.Get(titleKey)), Ui.Hint(L.Get(hintKey)));
        AutomationNames.Set(toggle, L.Get(titleKey));
        toggle.VerticalAlignment = VerticalAlignment.Center;
        return Ui.Split(text, toggle, 16);
    }

    void RenderPhotos()
    {
        _photoRow.Children.Clear();
        foreach (var photo in _photos.Photos)
        {
            var image = new Image { Source = PhotoTools.Thumbnail(photo, 176), Stretch = Stretch.UniformToFill, Width = 88, Height = 88 };
            image.Clip = new RectangleGeometry(new Rect(0, 0, 88, 88), 12, 12);
            var frame = new Border { Width = 88, Height = 88, CornerRadius = new(12), BorderThickness = new(1), Child = image };
            frame.Res(Border.BorderBrushProperty, "borderBrush");
            var remove = new Button
            {
                Content = "✕",
                FontSize = 12,
                Width = 26,
                Height = 26,
                MinHeight = 0,
                Padding = new(0),
                HorizontalAlignment = HorizontalAlignment.Right,
                VerticalAlignment = VerticalAlignment.Top,
                Margin = new(0, 4, 4, 0),
                ToolTip = L.Get("common.photo.remove"),
                IsEnabled = !_sending,
            }.Styled("Button.Secondary");
            AutomationNames.Set(remove, L.Get("common.photo.remove"));
            var captured = photo;
            remove.Click += (_, _) => _photos.Remove(captured);
            var cell = new Grid { Margin = new(0, 0, 8, 8) };
            cell.Children.Add(frame);
            cell.Children.Add(remove);
            _photoRow.Children.Add(cell);
        }
        if (!_photos.IsFull)
        {
            var add = new Button
            {
                Content = "+",
                FontSize = 28,
                Width = 88,
                Height = 88,
                Padding = new(0),
                Margin = new(0, 0, 8, 8),
                ToolTip = L.Get("report.addPhoto"),
                IsEnabled = !_sending,
            }.Styled("Button.Secondary");
            AutomationNames.Set(add, L.Get("report.addPhoto"));
            add.Click += (_, _) => _photos.Pick(this, L.Get("report.addPhoto"));
            _photoRow.Children.Add(add);
        }
    }

    void ShowError(string text)
    {
        _error.Text = text;
        _error.Shown(true);
    }

    void SetSending(bool on)
    {
        _sending = on;
        _send.Content = L.Get(on ? "report.sending" : "common.send");
        _send.IsEnabled = !on;
        _sendProblems.IsEnabled = !on;
        _description.IsReadOnly = on;
        _contact.IsReadOnly = on;
        _includeLog.IsEnabled = !on;
        _progress.Shown(on);
        Cursor = on ? Cursors.AppStarting : null;
        RenderPhotos();
    }

    async Task SendAsync()
    {
        if (_sending) return;
        _error.Shown(false);
        if (_c.DataFolder is null)
        {
            ShowError(L.Get("report.error.failed"));
            return;
        }
        SetSending(true);
        ReportResult result;
        try
        {
            result = await _c.SendProblemReportAsync(_description.Text, _contact.Text, _includeLog.IsChecked == true, _photos.Photos);
        }
        catch (Exception) { result = ReportResult.Failed; }
        if (_closed) return;
        SetSending(false);
        switch (result.Status)
        {
            case ReportStatus.Sent: ShowThanks(); break;
            case ReportStatus.Limited: ShowError(L.Get("report.error.dailyLimit")); break;
            case ReportStatus.TooLarge: ShowError(L.Get("report.error.tooLarge")); break;
            case ReportStatus.Rejected: ShowError(L.Get("report.error.rejected")); break;
            default: ShowError(L.Get("report.error.failed")); break;
        }
    }

    void ShowThanks()
    {
        var panel = new StackPanel { Margin = new(28, 36, 28, 28) };
        var tick = new TextBlock { Text = "✓", FontSize = 40, HorizontalAlignment = HorizontalAlignment.Center };
        tick.Res(TextBlock.ForegroundProperty, "successBrush");
        panel.Children.Add(tick);
        var title = Ui.Headline(L.Get("report.thanks")).At(0, 8, 0, 20);
        title.TextAlignment = TextAlignment.Center;
        panel.Children.Add(title);
        var close = Ui.Primary(L.Get("common.close"), Close);
        close.MinWidth = 120;
        close.IsDefault = true;
        close.IsCancel = true;
        close.HorizontalAlignment = HorizontalAlignment.Center;
        panel.Children.Add(close);
        Content = panel;
        close.Focus();
        var timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(2.5) };
        timer.Tick += (_, _) =>
        {
            timer.Stop();
            if (!_closed) Close();
        };
        timer.Start();
    }
}
