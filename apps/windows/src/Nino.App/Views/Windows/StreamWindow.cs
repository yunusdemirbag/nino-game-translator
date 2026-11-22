// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.CompilerServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Effects;
using System.Windows.Threading;
using Nino.App.Strings;
using Nino.App.Theme;
using Nino.Core.Imaging;
using Nino.Core.Link;
using Nino.Core.Logging;
using Nino.Core.Reading;
using Nino.Core.Settings;
using Nino.Shell;
using Nino.Shell.Panels;

namespace Nino.App.Views;

/// <summary>
/// Yayıncı penceresi (kaynaklar tarifi §5): saydam pencere yakalayamayan yayın programları için altyazıyı tek renk zemin
/// (yeşil / siyah / mor) üstüne çizen olağan pencere; programda "Pencere yakalama" ile eklenir, zemin chroma key ile
/// silinir. Başlığı sabittir (yakalama listesinde bulunsun). Olaylar bilgisayardaki altyazı penceresinin yığın
/// kurallarıyla gösterilir; altyazı yalnız TV'deyken de satırları alır, çeviri durunca boşalır. Tek örnek; sahibi
/// yoktur (Ayarlar kapanınca kapanmaz), uygulama kapanınca kapanır.
/// </summary>
public sealed class StreamWindow : Window
{
    static readonly Color Yellow = Color.FromRgb(0xFF, 0xE1, 0x35);
    static StreamWindow? _open;

    readonly NinoController _c;
    readonly SubtitleStack _stack = new();
    readonly Stopwatch _clock = Stopwatch.StartNew();
    readonly Dictionary<long, Border> _lineBoxes = [];
    readonly HashSet<long> _fading = [];
    readonly Dictionary<string, (string Text, Box? Box)> _regions = [];
    readonly Grid _root = new();
    readonly StackPanel _lines = new() { VerticalAlignment = VerticalAlignment.Bottom, IsHitTestVisible = false };
    readonly StackPanel _regionPanel = new() { VerticalAlignment = VerticalAlignment.Top, IsHitTestVisible = false };
    readonly DispatcherTimer _timer = new();
    double? _screenUntil;
    bool _closed;
    bool _errorLogged;

    /// <summary>Açar; açıksa öne getirir (küçültülmüşse geri açar).</summary>
    public static StreamWindow Open(NinoController controller)
    {
        if (_open is { } existing)
        {
            if (existing.WindowState == WindowState.Minimized) existing.WindowState = WindowState.Normal;
            existing.Activate();
            return existing;
        }
        var window = new StreamWindow(controller);
        _open = window;
        window.Show();
        return window;
    }

    /// <summary>Ayarlar › OBS'teki yayıncı penceresi düğmesi bu pencereyi açar.</summary>
    [ModuleInitializer]
    internal static void Register() =>
        SettingsWindow.OpenStreamWindow ??= host =>
        {
            if (host is SettingsWindow settings) Open(settings.Controller);
        };

    public StreamWindow(NinoController controller)
    {
        _c = controller;
        Title = L.Get("source.streamWindow.title");
        Width = StreamWindowRules.WindowWidth;
        Height = StreamWindowRules.WindowHeight;
        MinWidth = StreamWindowRules.MinWidth;
        MinHeight = StreamWindowRules.MinHeight;
        ResizeMode = ResizeMode.CanResize;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        ShowInTaskbar = true;
        FlowDirection = FlowDirection.LeftToRight;
        FontFamily = NinoFonts.Text;
        UseLayoutRounding = true;
        // Gri tonlu yumuşatma: ClearType'ın renk saçağı chroma key'de kenar bırakır.
        TextOptions.SetTextRenderingMode(this, TextRenderingMode.Grayscale);
        TextOptions.SetTextFormattingMode(this, TextFormattingMode.Ideal);
        if (Application.Current?.MainWindow is { } main && !ReferenceEquals(main, this) && main.Icon is { } icon) Icon = icon;

        _root.Children.Add(_lines);
        _root.Children.Add(_regionPanel);
        Content = _root;
        ApplyBackground();

        _timer.Tick += (_, _) => Safe(() =>
        {
            _timer.Stop();
            Draw();
        });
        _root.SizeChanged += (_, e) => Safe(() =>
        {
            if (Math.Abs(e.NewSize.Height - e.PreviousSize.Height) < 0.5) return;
            Rebuild();
        });

        _c.StreamWindowEvent += OnEvent;
        _c.StreamWindowCleared += OnCleared;
        _c.PropertyChanged += OnControllerChanged;
        Closed += (_, _) => Detach();
        if (Application.Current is { } app) app.Exit += OnAppExit;
        Safe(Rebuild);
    }

    double Now => _clock.Elapsed.TotalSeconds;

    double ContentHeight => _root.ActualHeight > 0 ? _root.ActualHeight : StreamWindowRules.ContentHeight;

    // ---- Zemin ve yeniden kurma ----

    void ApplyBackground()
    {
        var rgb = StreamBackgroundColors.Rgb(_c.StreamBackground);
        var brush = Ui.Frozen(Color.FromRgb((byte)(rgb >> 16), (byte)(rgb >> 8), (byte)rgb));
        // İçeriğin kendisi de boyanır (ekran dökümü pencerenin içeriğini çizer).
        Background = brush;
        _root.Background = brush;
    }

    /// <summary>Stil, zemin ya da boy değişince kutular yeniden kurulur.</summary>
    void Rebuild()
    {
        var height = ContentHeight;
        var scale = StreamWindowRules.Scale(height);
        var side = StreamWindowRules.SidePadding(scale);
        _lines.Margin = new(side, 0, side, StreamWindowRules.BottomPadding(height));
        _regionPanel.Margin = new(side, StreamWindowRules.RegionTop(scale), side, 0);
        _stack.StackPrevious = _c.Settings.Style.StackPrevious;
        _lineBoxes.Clear();
        _fading.Clear();
        Draw();
    }

    // ---- Olaylar (bilgisayardaki altyazı penceresiyle aynı kurallar) ----

    void OnEvent(LocalSubtitleEvent e) => Safe(() =>
    {
        var now = Now;
        _stack.StackPrevious = _c.Settings.Style.StackPrevious;
        switch (e.Kind)
        {
            case LocalEventKind.Subtitle:
                _screenUntil = null;
                _stack.Show(e.Text, e.DurationMs, e.Paragraphs, now, e.Replace);
                break;
            case LocalEventKind.Screen:
                _stack.Show(e.Text, e.DurationMs, true, now);
                _screenUntil = now + e.DurationMs / 1000.0;
                break;
            case LocalEventKind.ScreenClear:
                if (_screenUntil is { } until && now < until) _stack.Hide();
                _screenUntil = null;
                break;
            case LocalEventKind.Region:
                // Ek alan olayı altyazıya dokunmaz.
                if (e.RegionId is not { } id) return;
                _regions.Remove(id);
                if (e.Text.Trim().Length > 0) _regions[id] = (e.Text, e.Box);
                break;
            case LocalEventKind.RegionClear:
                _regions.Clear();
                break;
            case LocalEventKind.Clear:
                if (_screenUntil is null || now >= _screenUntil) _stack.Clear(now);
                break;
        }
        Draw();
    });

    void OnCleared() => Safe(() =>
    {
        _stack.Hide();
        _regions.Clear();
        _screenUntil = null;
        Draw();
    });

    void OnControllerChanged(object? sender, PropertyChangedEventArgs e) => Safe(() =>
    {
        switch (e.PropertyName)
        {
            case nameof(NinoController.StreamBackground):
                ApplyBackground();
                Rebuild();
                break;
            case nameof(NinoController.Settings):
                Rebuild();
                break;
        }
    });

    // ---- Çizim ----

    void Draw()
    {
        if (_closed) return;
        var now = Now;
        var style = _c.Settings.Style;
        var scale = StreamWindowRules.Scale(ContentHeight);
        var lines = _stack.Lines(now).ToList();

        var keep = lines.Select(l => l.Id).ToHashSet();
        foreach (var gone in _lineBoxes.Keys.Where(k => !keep.Contains(k)).ToList())
        {
            _lineBoxes.Remove(gone);
            _fading.Remove(gone);
        }
        _lines.Children.Clear();
        foreach (var line in lines)
        {
            // Satır yığında yer değiştirince (şimdiki → önceki) boyu, boşluğu ve soluklığı değişir: kutu yeniden kurulur.
            if (!_lineBoxes.TryGetValue(line.Id, out var box) || !Equals(box.Tag, line.Role))
            {
                box = LineBox(line, style, scale);
                _lineBoxes[line.Id] = box;
                _fading.Remove(line.Id);
            }
            if (line.Fading && _fading.Add(line.Id))
                box.BeginAnimation(OpacityProperty, new DoubleAnimation(1, 0, TimeSpan.FromSeconds(SubtitleStack.Fade)));
            _lines.Children.Add(box);
        }

        _regionPanel.Children.Clear();
        foreach (var (_, (text, area)) in _regions.OrderBy(r => r.Value.Box?.Top ?? 0))
            _regionPanel.Children.Add(RegionBox(text, area, style, scale));

        if (_stack.NextChange(now) is { } next)
        {
            _timer.Interval = TimeSpan.FromSeconds(Math.Max(0.01, next - now));
            _timer.Start();
        }
    }

    static Brush TextBrush(SubtitleStyle style, double alpha)
    {
        var color = style.TextColor == SubtitleTextColor.Yellow ? Yellow : Colors.White;
        color.A = (byte)Math.Round(255 * Math.Clamp(alpha, 0, 1));
        return Ui.Frozen(color);
    }

    static void ApplyFont(TextBlock t, SubtitleStyle style)
    {
        if (NinoFonts.ForSubtitle(style.Font) is { } family) t.FontFamily = family;
    }

    static Border LineBox(StackLine line, SubtitleStyle style, double scale)
    {
        var current = line.Role == StackRole.Current;
        var boxed = StreamWindowRules.HasBox(style.Background);
        var (wrapped, wrapScale) = SubtitleStack.Visible(line.Text, line.Paragraphs);
        var text = RightToLeft.PrepareText(wrapped);
        var size = OverlayDrawing.LineFontSize(style.FontSize, scale, current, wrapScale);
        var block = new TextBlock
        {
            Text = text,
            FontSize = size,
            FontWeight = style.Bold ? FontWeights.Bold : FontWeights.SemiBold,
            TextWrapping = TextWrapping.Wrap,
            TextAlignment = line.Paragraphs ? TextAlignment.Left : TextAlignment.Center,
            LineHeight = size * 1.3,
            LineStackingStrategy = LineStackingStrategy.BlockLineHeight,
            FlowDirection = RightToLeft.ForText(text),
            Foreground = TextBrush(style, StreamWindowRules.TextAlpha(line.Role, boxed)),
        };
        if (!boxed)
            block.Effect = new DropShadowEffect { Color = Colors.Black, Direction = 270, ShadowDepth = 2 * scale, BlurRadius = 4 * scale, Opacity = 1 };
        ApplyFont(block, style);
        return new Border
        {
            Tag = line.Role,
            Child = block,
            // Yarı geçirgen kutu chroma key'i bozar: kutu ya tam siyah ya hiç.
            Background = boxed ? Brushes.Black : Brushes.Transparent,
            CornerRadius = new(10 * scale),
            HorizontalAlignment = HorizontalAlignment.Center,
            Padding = current ? new(26 * scale, 10 * scale, 26 * scale, 10 * scale) : new(20 * scale, 6 * scale, 20 * scale, 6 * scale),
            Margin = new(0, 14 * scale, 0, 0),
        };
    }

    static Border RegionBox(string text, Box? area, SubtitleStyle style, double scale)
    {
        var prepared = RightToLeft.PrepareText(text);
        var size = OverlayDrawing.RegionFontSize(style.FontSize, scale);
        var block = new TextBlock
        {
            Text = prepared,
            FontSize = size,
            FontWeight = FontWeights.SemiBold,
            TextWrapping = TextWrapping.Wrap,
            LineHeight = size * 1.25,
            LineStackingStrategy = LineStackingStrategy.BlockLineHeight,
            FlowDirection = RightToLeft.ForText(prepared),
            Foreground = TextBrush(style, 1),
        };
        ApplyFont(block, style);
        return new Border
        {
            Child = block,
            Background = Brushes.Black,
            CornerRadius = new(8 * scale),
            Padding = new(14 * scale, 6 * scale, 14 * scale, 6 * scale),
            Margin = new(0, 0, 0, 10 * scale),
            HorizontalAlignment = OverlayDrawing.RegionAlignment(area?.CenterX) switch
            {
                -1 => HorizontalAlignment.Left,
                1 => HorizontalAlignment.Right,
                _ => HorizontalAlignment.Center,
            },
        };
    }

    // ---- Koruma ve kapanış ----

    /// <summary>Her iş korumalıdır: yayın penceresindeki bir hata bilgisayar penceresini ve denetleyiciyi düşürmez.</summary>
    void Safe(Action action)
    {
        if (_closed) return;
        try { action(); }
        catch (Exception e)
        {
            // Süren bir çizim hatası her olayda yinelenir: hata.log'a bir kez yazılır.
            if (_errorLogged) return;
            _errorLogged = true;
            try
            {
                if (_c.DataFolder is { } folder) new ErrorLog(System.IO.Path.Combine(folder, LogNames.Error)).Write("Yayıncı penceresi", e);
            }
            catch (Exception) { }
        }
    }

    void OnAppExit(object? sender, ExitEventArgs e) => Detach();

    void Detach()
    {
        if (_closed) return;
        _closed = true;
        _timer.Stop();
        _c.StreamWindowEvent -= OnEvent;
        _c.StreamWindowCleared -= OnCleared;
        _c.PropertyChanged -= OnControllerChanged;
        if (Application.Current is { } app) app.Exit -= OnAppExit;
        if (ReferenceEquals(_open, this)) _open = null;
    }
}
