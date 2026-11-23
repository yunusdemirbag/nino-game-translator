// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.ComponentModel;
using System.IO;
using System.Reflection;
using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Shapes;
using Nino.App.Controls;
using Nino.App.Strings;
using Nino.Shell;

namespace Nino.App.Views;

/// <summary>
/// Hakkında içeriği (Mac'in Hakkında sayfasıyla aynı sıra): logo ve sürüm, geliştirici ve destek verenler, güncelleme
/// denetimi (uygulama + eşli TV), kaynak kodu / ölçüm / gizlilik / lisans ve telif / açık kaynak bileşenler, marka
/// uyarıları. Hakkında penceresi bunu gösterir; Ayarlar da kendi içine koyabilir.
/// </summary>
public sealed class AboutContent : StackPanel
{
    public const string SourceUrl = "https://github.com/yunusdemirbag/nino-game-translator";

    /// <summary>Gizlilik metni (herkese açık depoda).</summary>
    public const string PrivacyUrl = SourceUrl + "/blob/main/PRIVACY.md";

    /// <summary>Windows'la gelen açık kaynak bileşenler ve lisansları (çevrilmez).</summary>
    public static IReadOnlyList<(string Name, string License)> Components { get; } =
    [
        ("chiaki-ng", "AGPL-3.0"),
        ("OpenSSL", "Apache-2.0"),
        ("json-c", "MIT"),
        ("libevent", "BSD-3-Clause"),
        ("miniupnpc", "BSD-3-Clause"),
        ("curl", "curl"),
        ("FFmpeg", "LGPL-2.1+"),
        ("ONNX Runtime, Microsoft.ML.Tokenizers", "MIT"),
        ("Velopack, SSH.NET, TizenSdb", "MIT"),
        ("WebView2", "BSD-3-Clause"),
        ("Barlow, Nunito", "SIL OFL 1.1"),
    ];

    /// <summary>Yalnız iki ad: rol anahtarı, simge, ad (adlar bütün dillerde aynı yazılır).</summary>
    public static IReadOnlyList<(string RoleKey, string Glyph, string Name)> People { get; } =
    [
        ("about.role.developer", "", "Yunus Demirbağ"),
        ("about.role.supporters", "", "M. Akif Demirbağ"),
    ];

    /// <summary>NOTICE okunamazsa telif satırı.</summary>
    const string FallbackCopyright = "Nino © 2026 Yunus Demirbağ.";

    /// <summary>chiaki-ng'nin telif bildirimi (çevrilmez).</summary>
    const string ChiakiCopyright = "Chiaki © Florian Märkl and contributors.";

    readonly NinoController _c;
    readonly ContentControl _update = new() { Focusable = false };
    AppUpdateState? _shownApp;
    TvUpdateState? _shownTv;
    bool _shownChecking;

    public AboutContent(NinoController controller)
    {
        _c = controller;
        Children.Add(Header());
        Children.Add(PeopleCard().At(0, 16, 0, 0));
        Children.Add(_update.At(0, 16, 0, 0));
        Children.Add(LinksCard().At(0, 16, 0, 0));
        var sony = Ui.Caption(L.Get("about.sonyTrademark")).At(0, 16, 0, 0);
        sony.TextAlignment = TextAlignment.Center;
        Children.Add(sony);
        var ms = Ui.Caption(L.Get("about.microsoftTrademark")).At(0, 4, 0, 0);
        ms.TextAlignment = TextAlignment.Center;
        Children.Add(ms);
        RenderUpdate();
        _c.PropertyChanged += OnChanged;
        Unloaded += (_, _) => _c.PropertyChanged -= OnChanged;
        Loaded += (_, _) =>
        {
            _c.PropertyChanged -= OnChanged;
            _c.PropertyChanged += OnChanged;
            RenderUpdate();
        };
    }

    void OnChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName is nameof(NinoController.AppUpdate) or nameof(NinoController.TvUpdate)
            or nameof(NinoController.CheckingForUpdates) or nameof(NinoController.TvApp))
            RenderUpdate();
    }

    // ---- Parçalar ----

    StackPanel Header()
    {
        var panel = new StackPanel { HorizontalAlignment = HorizontalAlignment.Center };
        var logo = new LogoBox { Width = 96, Height = 96, HorizontalAlignment = HorizontalAlignment.Center };
        logo.Effect = new System.Windows.Media.Effects.DropShadowEffect { BlurRadius = 36, ShadowDepth = 0, Opacity = 0.35 };
        if (TryFindResource("accentColor") is Color accent && logo.Effect is System.Windows.Media.Effects.DropShadowEffect fx)
            fx.Color = accent;
        panel.Children.Add(logo);
        var title = Ui.Display("Nino Game Translator").At(0, 8, 0, 0);
        title.FontWeight = FontWeights.Bold;
        title.TextAlignment = TextAlignment.Center;
        panel.Children.Add(title);
        var version = Ui.Hint(UpdateRules.VersionLine(AboutWindow.Version(_c))).At(0, 4, 0, 0);
        version.TextAlignment = TextAlignment.Center;
        version.FlowDirection = FlowDirection.LeftToRight;
        panel.Children.Add(version);
        return panel;
    }

    Card PeopleCard()
    {
        var rows = new StackPanel();
        for (var i = 0; i < People.Count; i++)
        {
            var (roleKey, glyph, name) = People[i];
            if (i > 0) rows.Children.Add(Line());
            var role = Ui.Secondary(L.Get(roleKey));
            role.VerticalAlignment = VerticalAlignment.Center;
            role.Margin = new(12, 0, 12, 0);
            var who = Ui.Body(name);
            who.FontWeight = FontWeights.Bold;
            who.VerticalAlignment = VerticalAlignment.Center;
            rows.Children.Add(Row(Badge(glyph), role, who, 50));
        }
        return new Card { Content = rows, Padding = new(16, 0, 16, 0) };
    }

    /// <summary>Sol simge + orta (genişler) + sağ; en az <paramref name="minHeight"/> yükseklik.</summary>
    static Grid Row(UIElement badge, UIElement middle, UIElement? right, double minHeight)
    {
        var g = new Grid { MinHeight = minHeight };
        g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        Grid.SetColumn(middle, 1);
        g.Children.Add(badge);
        g.Children.Add(middle);
        if (right is not null)
        {
            Grid.SetColumn(right, 2);
            g.Children.Add(right);
        }
        return g;
    }

    static Border Line()
    {
        var line = new Border { Height = 1, Margin = new(40, 0, 0, 0), Opacity = 0.6 };
        line.Res(Border.BackgroundProperty, "borderBrush");
        return line;
    }

    /// <summary>Simge zemini: açık vurgudan koyu laciverte geçen 28'lik kare (köşe 8), içi beyaz.</summary>
    Border Badge(string glyph)
    {
        var top = TryFindResource("accentHiColor") is Color c ? c : Color.FromRgb(0x1A, 0x86, 0xE8);
        var fill = new LinearGradientBrush(top, Color.FromRgb(0x00, 0x30, 0x85), 90);
        fill.Freeze();
        var icon = new TextBlock { Text = glyph, FontSize = 13, Foreground = Brushes.White }.Styled("Text.Icon");
        icon.Foreground = Brushes.White;
        icon.HorizontalAlignment = HorizontalAlignment.Center;
        icon.VerticalAlignment = VerticalAlignment.Center;
        return new Border
        {
            Width = 28,
            Height = 28,
            CornerRadius = new(8),
            Background = fill,
            Child = icon,
            VerticalAlignment = VerticalAlignment.Center,
        };
    }

    // ---- Güncelleme kartı ----

    void RenderUpdate()
    {
        var app = _c.AppUpdate;
        var tv = _c.TvUpdate;
        var checking = _c.CheckingForUpdates;
        if (app == _shownApp && tv == _shownTv && checking == _shownChecking && _update.Content is not null) return;
        _shownApp = app;
        _shownTv = tv;
        _shownChecking = checking;
        var rows = new StackPanel();
        rows.Children.Add(AppRow(app, tv, checking));
        if (tv.Kind != TvUpdateKind.None)
        {
            rows.Children.Add(Line());
            rows.Children.Add(TvRow(tv));
        }
        _update.Content = new Card { Content = rows, Padding = new(16, 0, 16, 0) };
    }

    Grid AppRow(AppUpdateState app, TvUpdateState tv, bool checking)
    {
        var status = new StackPanel { VerticalAlignment = VerticalAlignment.Center, Margin = new(12, 8, 12, 8) };
        switch (app.Kind)
        {
            case AppUpdateKind.Checking:
                status.Children.Add(Busy(L.Get("about.update.checking")));
                break;
            case AppUpdateKind.UpToDate:
                status.Children.Add(Ok(L.Get(tv.IsCurrentOrAbsent && tv.Kind != TvUpdateKind.None
                    ? "about.update.allUpToDate" : "about.update.upToDate")));
                break;
            case AppUpdateKind.Available:
                var available = Ui.Body(L.Format("about.update.available", app.Version ?? ""));
                available.FontWeight = FontWeights.SemiBold;
                status.Children.Add(available);
                break;
            case AppUpdateKind.Downloading:
                status.Children.Add(Ui.Secondary(L.Format("about.update.downloading", app.Version ?? "")));
                status.Children.Add(new ProgressBar
                {
                    Minimum = 0,
                    Maximum = 1,
                    Value = app.Progress,
                    Height = 4,
                    Margin = new(0, 6, 0, 0),
                });
                break;
            case AppUpdateKind.Failed:
                status.Children.Add(Ui.Secondary(app.Error ?? L.Get("about.update.failed")));
                break;
            default:
                var line = Ui.Secondary(UpdateRules.VersionLine(AboutWindow.Version(_c)));
                line.FlowDirection = FlowDirection.LeftToRight;
                line.HorizontalAlignment = HorizontalAlignment.Left;
                status.Children.Add(line);
                break;
        }
        FrameworkElement? action = app.Kind switch
        {
            AppUpdateKind.Available => Ui.Primary(L.Get("about.update.install"), () => _ = _c.InstallUpdateAsync()),
            AppUpdateKind.Downloading => null,
            _ => CheckButton(checking),
        };
        if (action is not null) action.VerticalAlignment = VerticalAlignment.Center;
        return Row(Badge(""), status, action, 58);
    }

    Button CheckButton(bool checking)
    {
        var b = Ui.Button(L.Get("about.update.check"), () => _ = _c.CheckForUpdatesNowAsync());
        b.IsEnabled = !checking;
        return b;
    }

    Grid TvRow(TvUpdateState tv)
    {
        var text = new StackPanel { VerticalAlignment = VerticalAlignment.Center, Margin = new(12, 8, 12, 8) };
        FrameworkElement? action = null;
        switch (tv.Kind)
        {
            case TvUpdateKind.Checking:
                text.Children.Add(Busy(L.Get("about.tv.checking")));
                break;
            case TvUpdateKind.UpToDate:
                text.Children.Add(Ok(L.Format("about.tv.upToDate", tv.Installed ?? "")));
                break;
            case TvUpdateKind.Outdated:
                var title = Ui.Body(L.Get("about.tv.outdated"));
                title.FontWeight = FontWeights.SemiBold;
                text.Children.Add(title);
                var versions = Ui.Caption(UpdateRules.Versions(tv.Installed, tv.Bundled));
                versions.FlowDirection = FlowDirection.LeftToRight;
                versions.HorizontalAlignment = HorizontalAlignment.Left;
                versions.Res(TextBlock.ForegroundProperty, "textSecondaryBrush");
                text.Children.Add(versions.At(0, 2, 0, 0));
                action = Ui.Primary(L.Get("about.tv.install"), () => _ = _c.InstallTvUpdateAsync());
                break;
            case TvUpdateKind.Unreachable:
                text.Children.Add(Ui.Secondary(L.Get("about.tv.off")));
                break;
            case TvUpdateKind.AppClosed:
                text.Children.Add(Ui.Secondary(L.Get("about.tv.appClosed")));
                break;
            case TvUpdateKind.Installing:
                text.Children.Add(Busy(L.Get("about.tv.installing")));
                break;
            case TvUpdateKind.ContinueInSettings:
                text.Children.Add(Ui.Secondary(L.Get("about.tv.continue")));
                // Parola, onay ya da hata: kurulum Ayarlar'daki TV uygulaması kartında sürer.
                action = Ui.Button(L.Get("about.tv.openSettings"), () => SettingsWindow.Open(_c, Window.GetWindow(this), Nino.Shell.Panels.SettingsPage.Connection));
                break;
        }
        if (action is not null) action.VerticalAlignment = VerticalAlignment.Center;
        return Row(Badge(""), text, action, 58);
    }

    static StackPanel Ok(string text)
    {
        var tick = Ui.Icon("", 14, "successBrush");
        tick.VerticalAlignment = VerticalAlignment.Center;
        tick.Margin = new(0, 0, 6, 0);
        var label = Ui.Body(text);
        label.VerticalAlignment = VerticalAlignment.Center;
        return Ui.Row(tick, label);
    }

    static StackPanel Busy(string text)
    {
        var label = Ui.Secondary(text);
        label.VerticalAlignment = VerticalAlignment.Center;
        return Ui.Row(Spinner().At(0, 0, 6, 0), label);
    }

    /// <summary>Küçük dönen yay (14 px).</summary>
    internal static FrameworkElement Spinner()
    {
        var arc = new System.Windows.Shapes.Path
        {
            Data = Geometry.Parse("M 7,1 A 6,6 0 1 1 1.3,9"),
            StrokeThickness = 2,
            Width = 14,
            Height = 14,
            StrokeStartLineCap = PenLineCap.Round,
            StrokeEndLineCap = PenLineCap.Round,
            VerticalAlignment = VerticalAlignment.Center,
            RenderTransformOrigin = new Point(0.5, 0.5),
        };
        arc.SetResourceReference(Shape.StrokeProperty, "textSecondaryBrush");
        var spin = new RotateTransform();
        arc.RenderTransform = spin;
        if (!SystemParameters.ClientAreaAnimation) return arc;
        spin.BeginAnimation(RotateTransform.AngleProperty,
            new DoubleAnimation(0, 360, TimeSpan.FromSeconds(0.9)) { RepeatBehavior = RepeatBehavior.Forever });
        return arc;
    }

    // ---- Bağlantılar, lisans, bileşenler ----

    Card LinksCard()
    {
        var panel = new StackPanel();
        panel.Children.Add(LinkButton(L.Get("about.sourceCode"), "", SourceUrl));
        panel.Children.Add(Ui.Caption(L.Get("about.telemetry")).Fg("textSecondaryBrush").At(0, 12, 0, 0));
        panel.Children.Add(LinkButton(L.Get("about.privacy"), "", PrivacyUrl).At(0, 12, 0, 0));
        var license = new TextBlock
        {
            Text = string.Join(" ", L.Get("about.license"), CopyrightLine(), ChiakiCopyright),
            FontSize = 11,
            TextWrapping = TextWrapping.Wrap,
            Margin = new(0, 12, 0, 0),
        };
        license.Res(TextBlock.ForegroundProperty, "textSecondaryBrush");
        panel.Children.Add(license);
        var divider = new Border { Height = 1, Margin = new(0, 12, 0, 12) };
        divider.Res(Border.BackgroundProperty, "tileBorderBrush");
        panel.Children.Add(divider);
        var head = Ui.Caption(L.Get("about.components")).Fg("textSecondaryBrush");
        head.FontWeight = FontWeights.SemiBold;
        panel.Children.Add(head);
        foreach (var (name, lic) in Components)
        {
            var left = Ui.Hint(name);
            left.Res(TextBlock.ForegroundProperty, "textPrimaryBrush");
            var right = Ui.Caption(lic).Fg("textSecondaryBrush");
            right.FlowDirection = FlowDirection.LeftToRight;
            var row = new DockPanel { Margin = new(0, 6, 0, 0), LastChildFill = true };
            DockPanel.SetDock(right, Dock.Right);
            row.Children.Add(right);
            row.Children.Add(left);
            panel.Children.Add(row);
        }
        // Windows'a özgü emek bildirimleri (Remote Play, Xbox, çeviri modeli).
        panel.Children.Add(Ui.Caption(L.Get("about.remotePlayCredit")).Fg("textSecondaryBrush").At(0, 12, 0, 0));
        panel.Children.Add(Ui.Caption(L.Get("about.xboxCredit")).Fg("textSecondaryBrush").At(0, 4, 0, 0));
        panel.Children.Add(Ui.Caption(L.Get("about.modelCredit")).Fg("textSecondaryBrush").At(0, 4, 0, 0));
        return new Card { Content = panel };
    }

    static Button LinkButton(string text, string glyph, string url)
    {
        var icon = Ui.Icon(glyph, 14, "accentTextBrush");
        icon.Margin = new(0, 0, 8, 0);
        icon.VerticalAlignment = VerticalAlignment.Center;
        var label = new TextBlock { Text = text, FontWeight = FontWeights.SemiBold, VerticalAlignment = VerticalAlignment.Center };
        label.Res(TextBlock.ForegroundProperty, "accentTextBrush");
        var b = new Button
        {
            Content = Ui.Row(icon, label),
            ToolTip = url,
            HorizontalAlignment = HorizontalAlignment.Left,
            Cursor = System.Windows.Input.Cursors.Hand,
        }.Styled("Button.Ghost");
        b.Padding = new(0);
        b.MinHeight = 0;
        AutomationNames.Set(b, text);
        b.Click += (_, _) => Ui.Open(url);
        return b;
    }

    /// <summary>"Nino © 2026 ‹sahibi›.": NOTICE'taki ilk "Copyright (C) ‹yıl› ‹sahibi›" satırından; okunamazsa sabit.</summary>
    public static string CopyrightLine()
    {
        if (AboutWindow.ReadNotice() is { } notice)
        {
            var m = Regex.Match(notice, @"^\s*Copyright\s*\(C\)\s*(?<year>\d{4})\s+(?<owner>[^\r\n,]+?)\s*$", RegexOptions.Multiline);
            if (m.Success) return $"Nino © {m.Groups["year"].Value} {m.Groups["owner"].Value}.";
        }
        return FallbackCopyright;
    }
}

/// <summary>
/// Hakkında penceresi (Mac'in 520'lik Hakkında sayfası): içerik kayar, Kapat altta sabit. Boyu Ayarlar penceresiyle aynı.
/// </summary>
public sealed class AboutWindow : Window
{
    public const string SourceUrl = AboutContent.SourceUrl;

    /// <summary>Gizlilik metni (sitedeki gizlilik sayfasının yayın adresi).</summary>
    public const string PrivacyUrl = AboutContent.PrivacyUrl;

    public AboutWindow(NinoController controller)
    {
        Ui.Prepare(this, L.Get("settings.section.about"));
        Width = 520;
        Height = Math.Min(720, Math.Max(480, SystemParameters.WorkArea.Height - 40));
        ResizeMode = ResizeMode.NoResize;

        var root = new Grid();
        root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        var scroll = new ScrollViewer
        {
            Content = new AboutContent(controller) { Margin = new(32, 32, 32, 16) },
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled,
            Focusable = false,
        };
        root.Children.Add(scroll);
        var divider = new Border { Height = 1 };
        divider.Res(Border.BackgroundProperty, "tileBorderBrush");
        Grid.SetRow(divider, 1);
        root.Children.Add(divider);
        var close = Ui.Primary(L.Get("common.close"), Close);
        close.MinWidth = 120;
        close.MinHeight = 44;
        close.IsDefault = true;
        close.IsCancel = true;
        close.HorizontalAlignment = HorizontalAlignment.Center;
        close.Margin = new(24);
        Grid.SetRow(close, 2);
        root.Children.Add(close);
        Content = root;
    }

    /// <summary>Uygulamanın bilgi sürümü, "+" ve sonrası atılmış (güncelleme denetimiyle aynı değer).</summary>
    public static string Version(NinoController? controller = null)
    {
        var info = Assembly.GetEntryAssembly()?.GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion;
        if (string.IsNullOrWhiteSpace(info)) info = controller?.AppVersion ?? "";
        var plus = info.IndexOf('+');
        return plus >= 0 ? info[..plus] : info;
    }

    /// <summary>NOTICE dosyası: uygulama klasöründe (yoksa geliştirmede üst klasörlerde) aranır.</summary>
    internal static string? ReadNotice()
    {
        try
        {
            var dir = new DirectoryInfo(AppContext.BaseDirectory);
            for (var i = 0; dir is not null && i < 10; i++, dir = dir.Parent)
            {
                var path = System.IO.Path.Combine(dir.FullName, "NOTICE");
                if (File.Exists(path)) return File.ReadAllText(path);
            }
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or System.Security.SecurityException) { }
        return null;
    }
}
