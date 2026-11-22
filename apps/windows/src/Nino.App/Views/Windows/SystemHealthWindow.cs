// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Text;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Shapes;
using System.Windows.Threading;
using Nino.App.Controls;
using Nino.App.Strings;
using Nino.Core.Data;
using Nino.Core.Health;
using Nino.Core.Logging;
using Nino.Core.Support;
using Nino.Shell;
using Nino.Shell.Panels;

namespace Nino.App.Views;

/// <summary>
/// Sağlık sayfası (yan pencereler tarifi §4): görsel ağaçtayken 2 sn'de bir yenilenir. Kartlar: muhtemel sebep,
/// denetimler, son sorunlar, (TV uygulaması kartı ana oturumda bağlanır), ayrıntılar, cihaz bilgileri.
/// </summary>
public sealed class SystemHealthPage : StackPanel
{
    readonly NinoController _c;
    readonly DispatcherTimer _timer = new() { Interval = TimeSpan.FromSeconds(2) };
    readonly Card _causeCard = new();
    readonly StackPanel _cause = new();
    readonly StackPanel _checks = new();
    readonly Card _recentCard;
    readonly StackPanel _recent = new();
    readonly TextBox _details;
    readonly Button _copyDetails;
    readonly TextBlock _detailsError;
    readonly StackPanel _deviceRows = new();
    readonly Button _copyDevice;
    string? _deviceSummary;
    DateTime? _deviceCopiedAt;
    NetworkKind? _network;
    bool _reading;

    /// <summary>TV uygulaması kartının yeri (kurulum sihirbazındaki kartın aynısı).</summary>
    public ContentControl TvAppSlot { get; } = new() { Focusable = false };

    public SystemHealthPage(NinoController controller)
    {
        _c = controller;
        _causeCard.Content = _cause;
        Children.Add(_causeCard);
        Children.Add(new Card { Content = _checks, Margin = new(0, 16, 0, 0) });
        _recentCard = new Card { Header = L.Get("health.recent.title"), Content = _recent, Margin = new(0, 16, 0, 0) };
        Children.Add(_recentCard);
        TvAppSlot.Margin = new(0, 16, 0, 0);
        TvAppSlot.Content = new TvAppCard(controller);
        Children.Add(TvAppSlot);

        _details = new TextBox
        {
            IsReadOnly = true,
            FontFamily = new FontFamily("Consolas"),
            FontSize = 12,
            Height = 260,
            TextWrapping = TextWrapping.NoWrap,
            AcceptsReturn = true,
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            HorizontalScrollBarVisibility = ScrollBarVisibility.Auto,
            VerticalContentAlignment = VerticalAlignment.Top,
            Margin = new(0, 12, 0, 0),
        };
        _copyDetails = Ui.Button(L.Get("health.details.copy"), () =>
        {
            if (Ui.Copy(_details.Text)) _copyDetails!.Content = L.Get("common.copied");
        }).At(0, 0, 8, 0);
        var zip = Ui.Button(L.Get("health.details.saveZip"), SaveZip);
        _detailsError = Ui.Error().At(0, 8, 0, 0).Shown(false);
        var expander = new Expander
        {
            Header = new TextBlock { Text = L.Get("common.details"), FontWeight = FontWeights.SemiBold },
            IsExpanded = false,
            Content = Ui.Column(_details, Ui.Row(_copyDetails, zip).At(0, 12, 0, 0), _detailsError,
                Ui.Hint(L.Get("health.details.privacy")).At(0, 8, 0, 0)),
        };
        expander.Res(Control.ForegroundProperty, "textPrimaryBrush");
        expander.Expanded += (_, _) =>
        {
            _copyDetails.Content = L.Get("health.details.copy");
            UpdateDetails();
        };
        Children.Add(new Card { Content = expander, Margin = new(0, 16, 0, 0) });

        _copyDevice = Ui.Button(L.Get("device.copy"), () =>
        {
            if (_deviceSummary is not null && Ui.Copy(_deviceSummary))
            {
                _copyDevice!.Content = L.Get("common.copied");
                _deviceCopiedAt = DateTime.UtcNow;
            }
        }).At(0, 12, 0, 0);
        Children.Add(new Card
        {
            Header = L.Get("device.title"),
            Content = Ui.Column(Ui.Hint(L.Get("device.hint")).At(0, 0, 0, 12), _deviceRows, _copyDevice),
            Margin = new(0, 16, 0, 0),
        });

        _timer.Tick += (_, _) => Refresh();
        Loaded += (_, _) =>
        {
            Refresh();
            _timer.Start();
        };
        Unloaded += (_, _) => _timer.Stop();
    }

    void Refresh()
    {
        ReadNetwork();
        var snapshot = _c.Health.Snapshot();
        var network = _network ?? NetworkKind.Unknown;
        RenderCause(snapshot, network);
        RenderChecks(snapshot);
        RenderRecent();
        if (!_details.IsKeyboardFocusWithin) UpdateDetails(snapshot, network);
        RenderDevice();
    }

    void ReadNetwork()
    {
        if (_reading) return;
        _reading = true;
        Task.Run(() =>
        {
            try { return NetworkKindDetector.Read(); }
            catch (Exception) { return NetworkKind.Unknown; }
        }).ContinueWith(t => Dispatcher.BeginInvoke(() =>
        {
            _reading = false;
            var first = _network is null;
            _network = t.Result;
            if (first) Refresh();
        }), TaskScheduler.Default);
    }

    void RenderCause(HealthSnapshot snapshot, NetworkKind network)
    {
        var card = HealthCauseCard.Build(snapshot, network);
        _causeCard.Shown(card.Visible);
        _cause.Children.Clear();
        if (card.Causes.Count > 0)
        {
            var first = card.Causes[0];
            _cause.Children.Add(Ui.Headline("⚠  " + first.Title(L.Catalog)));
            _cause.Children.Add(Ui.Body(first.Advice(L.Catalog)).At(0, 6, 0, 0));
            foreach (var other in card.Causes.Skip(1))
                _cause.Children.Add(Ui.Secondary("• " + other.Title(L.Catalog)).At(0, 4, 0, 0));
        }
        else if (card.AllGood) _cause.Children.Add(Ui.Headline("✓  " + L.Get("health.allGood")));
    }

    static string LevelBrush(HealthLevel level) => level switch
    {
        HealthLevel.Good => "successBrush",
        HealthLevel.Warning => "warningBrush",
        HealthLevel.Problem => "dangerBrush",
        _ => "textSecondaryBrush",
    };

    void RenderChecks(HealthSnapshot snapshot)
    {
        _checks.Children.Clear();
        if (HealthChecks.Hint(snapshot, L.Catalog) is { } hint) _checks.Children.Add(Ui.Secondary(hint).At(0, 0, 0, 12));
        var rows = HealthChecks.Build(_c.HealthInput(_network), L.Catalog);
        for (var i = 0; i < rows.Count; i++)
        {
            var row = rows[i];
            if (i > 0) _checks.Children.Add(new Separator { Margin = new(0, 8, 0, 8) });
            var name = new TextBlock { Text = row.Name, FontWeight = FontWeights.SemiBold, TextWrapping = TextWrapping.Wrap };
            var dot = new Ellipse { Width = 8, Height = 8, Margin = new(0, 0, 6, 0), VerticalAlignment = VerticalAlignment.Center };
            dot.Res(Shape.FillProperty, LevelBrush(row.Level));
            var level = new TextBlock { Text = row.LevelText(L.Catalog), FontWeight = FontWeights.SemiBold, TextWrapping = TextWrapping.NoWrap };
            level.Res(TextBlock.ForegroundProperty, LevelBrush(row.Level));
            var top = Ui.Split(name, Ui.Row(dot, level), 12);
            var block = Ui.Column(top, Ui.Secondary(row.Value));
            if (row.Level.AtLeastWarning() && row.Advice is { Length: > 0 } advice) block.Children.Add(Ui.Body(advice).At(0, 4, 0, 0));
            _checks.Children.Add(block);
        }
    }

    void RenderRecent()
    {
        var records = SettingsPanelRules.RecentProblems(_c.ProblemRecords());
        _recentCard.Shown(records.Count > 0);
        _recent.Children.Clear();
        if (records.Count == 0) return;
        var culture = L.Catalog.Culture;
        foreach (var r in records)
        {
            var local = r.Date.ToLocalTime();
            var date = Ui.Secondary(local.ToString("d", culture) + " " + local.ToString("t", culture));
            date.Width = 150;
            var name = Ui.Body(r.ShortName(L.Catalog)).At(12, 0, 0, 0);
            var row = new DockPanel { Margin = new(0, 0, 0, 6) };
            DockPanel.SetDock(date, Dock.Left);
            row.Children.Add(date);
            row.Children.Add(name);
            _recent.Children.Add(row);
        }
        _recent.Children.Add(Ui.Secondary(L.Get(_c.Settings.AutoReport ? "health.recent.autoOn" : "health.recent.autoOff")).At(0, 6, 0, 0));
    }

    void UpdateDetails() => UpdateDetails(_c.Health.Snapshot(), _network ?? NetworkKind.Unknown);

    void UpdateDetails(HealthSnapshot snapshot, NetworkKind network)
    {
        try { _details.Text = DetailsText(snapshot, network); }
        catch (Exception) { }
    }

    string DetailsText(HealthSnapshot snapshot, NetworkKind network)
    {
        var folder = _c.DataFolder;
        var tvApp = _c.TvApp;
        return HealthDetailsText.Build(new HealthDetailsText.Input(
            _c.AppVersion,
            Environment.OSVersion.Version.ToString(),
            Environment.ProcessorCount,
            _c.OnlineEnabled ? _c.Settings.OnlineEngine.ToString() : null,
            _c.IsTranslating,
            _c.SessionStatus.Phase.ToString(),
            _c.Tv?.Brand.ToString(),
            _c.ConnectedTvs,
            tvApp.Kind.ToString(),
            tvApp.Version,
            tvApp.Error?.ToString(),
            HealthSummary.Lines(snapshot, network),
            folder is null ? null : LogCollector.LastLinesOfFile(System.IO.Path.Combine(folder, LogNames.Subtitle), 40),
            folder is null ? null : LogCollector.LastLinesOfFile(System.IO.Path.Combine(folder, LogNames.TvInstall), 8)));
    }

    void RenderDevice()
    {
        if (_deviceCopiedAt is { } at && DateTime.UtcNow - at >= TimeSpan.FromSeconds(3))
        {
            _deviceCopiedAt = null;
            _copyDevice.Content = L.Get("device.copy");
        }
        IReadOnlyList<DeviceInfoLine> lines;
        try { lines = _c.DeviceInfoLines(); }
        catch (Exception) { return; }
        var summary = DeviceInfo.Summary(lines);
        if (summary == _deviceSummary) return;
        _deviceSummary = summary;
        _deviceRows.Children.Clear();
        for (var i = 0; i < lines.Count; i++)
        {
            if (i > 0) _deviceRows.Children.Add(new Separator { Margin = new(0, 8, 0, 8) });
            var key = SettingsPanelRules.DeviceLabelKey(lines[i].Id);
            var label = new TextBlock
            {
                Text = key.Length == 0 ? "TV" : L.Get(key),
                FontWeight = FontWeights.SemiBold,
                TextWrapping = TextWrapping.Wrap,
                Width = 190,
                Margin = new(0, 0, 12, 0),
            };
            var row = new DockPanel();
            DockPanel.SetDock(label, Dock.Left);
            row.Children.Add(label);
            row.Children.Add(Ui.Secondary(lines[i].Value));
            _deviceRows.Children.Add(row);
        }
    }

    void SaveZip()
    {
        _detailsError.Shown(false);
        try
        {
            var folder = _c.DataFolder ?? throw new IOException(L.Get("common.unknown"));
            var downloads = System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads");
            Directory.CreateDirectory(downloads);
            var path = System.IO.Path.Combine(downloads, SettingsPanelRules.LogZipName(DateTime.Now));
            var text = DetailsText(_c.Health.Snapshot(), _network ?? NetworkKind.Unknown);
            using (var stream = new FileStream(path, FileMode.Create, FileAccess.Write, FileShare.None))
            using (var archive = new ZipArchive(stream, ZipArchiveMode.Create))
            {
                foreach (var file in Directory.EnumerateFiles(folder).Where(f => System.IO.Path.GetFileName(f).Contains(".log", StringComparison.OrdinalIgnoreCase)))
                {
                    var entry = archive.CreateEntry(System.IO.Path.GetFileName(file), CompressionLevel.Optimal);
                    using var source = new FileStream(file, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
                    using var target = entry.Open();
                    source.CopyTo(target);
                }
                var details = archive.CreateEntry("ayrintilar.txt", CompressionLevel.Optimal);
                using var writer = new StreamWriter(details.Open(), new UTF8Encoding(false));
                writer.Write(text);
            }
            try { Process.Start(new ProcessStartInfo("explorer.exe", $"/select,\"{path}\"") { UseShellExecute = true }); }
            catch (Exception) { }
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or InvalidDataException or System.Security.SecurityException)
        {
            _detailsError.Text = L.Format("health.details.saveFailed", e.Message);
            _detailsError.Shown(true);
        }
    }
}

/// <summary>Sağlık sayfasını ayrı pencerede gösterir (Ayarlar dışından açmak için).</summary>
public sealed class SystemHealthWindow : Window
{
    /// <summary>Sayfa (TV uygulaması kartı <see cref="SystemHealthPage.TvAppSlot"/>'a konabilir).</summary>
    public SystemHealthPage Page { get; }

    public SystemHealthWindow(NinoController controller)
    {
        Ui.Prepare(this, L.Get("settings.section.systemHealth"));
        Width = 720;
        Height = 720;
        MinWidth = 480;
        MinHeight = 400;
        Page = new SystemHealthPage(controller) { Margin = new(24) };
        Content = new ScrollViewer
        {
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled,
            Content = Ui.Column(Ui.Display(L.Get("settings.section.systemHealth")).At(24, 24, 24, 0), Page),
        };
    }
}
