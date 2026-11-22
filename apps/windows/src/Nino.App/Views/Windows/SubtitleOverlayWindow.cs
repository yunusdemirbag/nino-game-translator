// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Effects;
using System.Windows.Shapes;
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
/// Bilgisayardaki altyazı penceresi (yan pencereler tarifi §5): kenarsız, saydam, her şeyin üstünde, odak almaz.
/// Denetleyicinin bilgisayar olaylarını TV uygulamasıyla aynı yığın kuralıyla gösterir; ayar kipinde taşınır ve iki
/// yana eşit genişletilir. Her iş korumalıdır: hata olursa pencere gizlenir, bu oturumda bir daha iş yapmaz ve
/// kullanıcıya bir kez ileti gösterilir.
/// </summary>
public sealed class SubtitleOverlayWindow : Window, IDisposable
{
    static readonly Brush Yellow = Ui.Frozen(Color.FromRgb(0xFF, 0xE1, 0x35));
    static readonly Brush RegionFill = Ui.Frozen(Color.FromArgb(0xD9, 0, 0, 0));

    readonly NinoController _c;
    readonly SubtitleStack _stack = new();
    readonly Stopwatch _clock = Stopwatch.StartNew();
    readonly Dictionary<long, Border> _lineBoxes = [];
    readonly HashSet<long> _fading = [];
    readonly Dictionary<string, (string Text, Box? Box)> _regions = [];
    readonly StackPanel _lines = new() { VerticalAlignment = VerticalAlignment.Bottom };
    readonly StackPanel _regionPanel = new() { VerticalAlignment = VerticalAlignment.Top, IsHitTestVisible = false };
    readonly Grid _adjustLayer = new();
    readonly DispatcherTimer _timer = new();
    double? _screenUntil;
    readonly GamePanelWindow? _panels;
    Box? _english;
    OverlaySeat? _seat;
    bool _broken;
    bool _disposed;
    IntPtr _hwnd;

    public SubtitleOverlayWindow(NinoController controller)
    {
        _c = controller;
        Title = "Nino";
        WindowStyle = WindowStyle.None;
        AllowsTransparency = true;
        Background = Brushes.Transparent;
        Topmost = true;
        ShowInTaskbar = false;
        ShowActivated = false;
        Focusable = false;
        ResizeMode = ResizeMode.NoResize;
        FlowDirection = FlowDirection.LeftToRight;
        FontFamily = NinoFonts.Text;

        BuildAdjustLayer();
        var root = new Grid();
        root.Children.Add(_adjustLayer);
        root.Children.Add(_lines);
        root.Children.Add(_regionPanel);
        Content = root;

        _timer.Tick += (_, _) => Safe(() =>
        {
            _timer.Stop();
            Draw();
        });
        SourceInitialized += (_, _) => Safe(() =>
        {
            _hwnd = new WindowInteropHelper(this).Handle;
            ApplyStyles();
        });
        MouseLeftButtonDown += (_, e) => Safe(() =>
        {
            if (ClickThrough || e.OriginalSource is Thumb || IsInsideButton(e.OriginalSource as DependencyObject)) return;
            try { DragMove(); }
            catch (InvalidOperationException) { }
            SavePlacement();
        });

        try { _panels = new GamePanelWindow(); }
        catch (Exception) { _panels = null; }

        _c.ComputerOverlayEvent += OnEvent;
        _c.ComputerOverlayCleared += OnCleared;
        _c.PropertyChanged += OnControllerChanged;
        Safe(ApplySettings);
    }

    bool ClickThrough => _c.Settings.OverlayClickThrough && !_c.AdjustMode;

    // ---- Ayar katmanı (§5.6) ----

    void BuildAdjustLayer()
    {
        var frame = new Rectangle
        {
            StrokeThickness = 2,
            StrokeDashArray = [4, 3],
            RadiusX = 14,
            RadiusY = 14,
            Fill = Ui.Frozen(Color.FromArgb(0x59, 0, 0, 0)),
            Stroke = Ui.Frozen(Color.FromRgb(0xFF, 0xC8, 0x3D)),
        };
        frame.Res(Shape.StrokeProperty, "accentBrush");
        _adjustLayer.Children.Add(frame);
        var text = new TextBlock
        {
            Text = L.Get("overlay.adjust.hint"),
            Foreground = Brushes.White,
            FontWeight = FontWeights.SemiBold,
            VerticalAlignment = VerticalAlignment.Center,
            TextWrapping = TextWrapping.Wrap,
        };
        var done = Ui.Primary(L.Get("common.done"), () => Safe(() => _c.AdjustMode = false)).At(12, 0, 0, 0);
        var top = Ui.Row(text, done);
        top.HorizontalAlignment = HorizontalAlignment.Center;
        top.VerticalAlignment = VerticalAlignment.Top;
        top.Margin = new(12);
        _adjustLayer.Children.Add(top);
        _adjustLayer.Children.Add(Handle(left: true));
        _adjustLayer.Children.Add(Handle(left: false));
        _adjustLayer.Visibility = Visibility.Collapsed;
    }

    Thumb Handle(bool left)
    {
        var template = new ControlTemplate(typeof(Thumb));
        var border = new FrameworkElementFactory(typeof(Border));
        border.SetValue(Border.CornerRadiusProperty, new CornerRadius(3));
        border.SetResourceReference(Border.BackgroundProperty, "accentBrush");
        template.VisualTree = border;
        var thumb = new Thumb
        {
            Width = 6,
            Height = 48,
            Template = template,
            Cursor = Cursors.SizeWE,
            HorizontalAlignment = left ? HorizontalAlignment.Left : HorizontalAlignment.Right,
            VerticalAlignment = VerticalAlignment.Center,
            Margin = new(6),
        };
        thumb.DragDelta += (_, e) => Safe(() =>
        {
            var delta = left ? -e.HorizontalChange : e.HorizontalChange;
            var (newLeft, width) = OverlayDrawing.ResizeFromCenter(Left, Width, delta, Screens());
            Width = width;
            Left = newLeft;
        });
        thumb.DragCompleted += (_, _) => Safe(SavePlacement);
        return thumb;
    }

    static bool IsInsideButton(DependencyObject? d)
    {
        while (d is not null)
        {
            if (d is ButtonBase) return true;
            d = d is Visual ? VisualTreeHelper.GetParent(d) : LogicalTreeHelper.GetParent(d);
        }
        return false;
    }

    void SavePlacement() => _c.SaveOverlayPlacement(Left, Top, Width);

    // ---- Yer ve stiller ----

    static IReadOnlyList<ScreenRect> Screens()
    {
        var w = SystemParameters.VirtualScreenWidth;
        var h = SystemParameters.VirtualScreenHeight;
        return double.IsFinite(w) && w > 0 && double.IsFinite(h) && h > 0
            ? [new ScreenRect(SystemParameters.VirtualScreenLeft, SystemParameters.VirtualScreenTop, w, h)]
            : [];
    }

    static double Scale => OverlayLayout.Scale(SystemParameters.PrimaryScreenHeight);

    void ApplySettings()
    {
        var s = _c.Settings;
        _stack.StackPrevious = s.Style.StackPrevious;
        var height = OverlayLayout.Height(s.Style.FontSize, Scale);
        var bottom = Top + Height;
        var wasPlaced = double.IsFinite(Top) && Height > 0 && IsVisible;
        Rect place;
        OverlaySeat? seat = null;
        if (_c.UsesCaptureCard && _c.GameArea is { } card && !_c.AdjustMode)
        {
            // Kartta: kullanıcının yeri ya da okunan İngilizcenin üstü/altı (kullanıcı hatası: hep altta sabitti).
            seat = CardSeat(card, height);
            var r = seat.Value.Rect;
            place = new Rect(r.X, r.Y, r.Width, r.Height);
        }
        else if (_c.UsesGameWindow && _c.GameArea is { } game && !_c.AdjustMode)
        {
            var dpi = VisualTreeHelper.GetDpi(this).PixelsPerInchX;
            var onGame = OverlayDrawing.OnGame(game, dpi, height);
            place = new Rect(onGame.X, onGame.Y, onGame.Width, onGame.Height);
        }
        else
        {
            var work = SystemParameters.WorkArea;
            var r = OverlayLayout.Place(s.Overlay, height, Screens(), new ScreenRect(work.X, work.Y, work.Width, work.Height), Scale);
            place = new Rect(r.X, r.Y, r.Width, r.Height);
            if (wasPlaced && s.Overlay is not null && Math.Abs(Height - height) > 0.5) place.Y = bottom - height;
        }
        Width = place.Width;
        Height = place.Height;
        Left = place.X;
        Top = place.Y;
        _seat = seat;
        Align(seat?.TopAligned ?? false);
        UpdatePanels();
        _lineBoxes.Clear();
        _fading.Clear();
        ApplyStyles();
        Draw();
    }

    OverlaySeat CardSeat(Nino.Shell.Platform.PixelRect card, double height)
    {
        var s = _c.Settings;
        var work = SystemParameters.WorkArea;
        var dpi = VisualTreeHelper.GetDpi(this).PixelsPerInchX;
        return CardOverlaySeat.Place(card, dpi, height, CardOverlaySeat.TextBlockHeight(s.Style.FontSize, Scale), _english,
            s.Style.Placement, s.Overlay, Screens(), new ScreenRect(work.X, work.Y, work.Width, work.Height), Scale, _seat);
    }

    /// <summary>Satırlar üste (İngilizcenin altına oturunca) ya da alta yaslı; bölge kutuları öbür uçta.</summary>
    void Align(bool top)
    {
        _lines.VerticalAlignment = top ? VerticalAlignment.Top : VerticalAlignment.Bottom;
        _lines.Margin = top ? new(24 * Scale, 0, 24 * Scale, 0) : new(24 * Scale, 0, 24 * Scale, 8 * Scale);
        _regionPanel.VerticalAlignment = top ? VerticalAlignment.Bottom : VerticalAlignment.Top;
        _regionPanel.Margin = top ? new(24 * Scale, 0, 24 * Scale, 8 * Scale) : new(24 * Scale, 8 * Scale, 24 * Scale, 0);
    }

    /// <summary>Yeni İngilizce satır geldi: kartta pencere çakışıyorsa yalnız yeri değişir (kutular yeniden kurulmaz).</summary>
    void Reseat()
    {
        if (!_c.UsesCaptureCard || _c.GameArea is not { } card || _c.AdjustMode || _seat is null) return;
        var next = CardSeat(card, Height);
        if (next == _seat) return;
        _seat = next;
        Left = next.Rect.X;
        Top = next.Rect.Y;
        Width = next.Rect.Width;
        Align(next.TopAligned);
    }

    /// <summary>Örtü katmanı oyunun alanının üstünde (alan bilinmiyorsa ya da altyazı bilgisayarda değilse çizilmez).</summary>
    void UpdatePanels()
    {
        if (_panels is null) return;
        ScreenRect? area = null;
        if ((_c.UsesGameWindow || _c.UsesCaptureCard) && _c.ShowsOnComputer && _c.GameArea is { } game)
            area = ScreenPanelLayout.AreaOnScreen(game, VisualTreeHelper.GetDpi(this).PixelsPerInchX);
        _panels.SetArea(area, _c.UsesGameWindow && _c.IsTranslating);
    }

    void ApplyStyles()
    {
        UpdatePanels();
        if (_hwnd == IntPtr.Zero) return;
        var ex = GetWindowLong(_hwnd, GwlExStyle);
        ex |= WsExNoActivate | WsExToolWindow;
        if (ClickThrough) ex |= WsExTransparent;
        else ex &= ~WsExTransparent;
        SetWindowLong(_hwnd, GwlExStyle, ex);
        var hide = _c.UsesGameWindow && _c.IsTranslating;
        try { SetWindowDisplayAffinity(_hwnd, hide ? WdaExcludeFromCapture : 0); }
        catch (Exception) { }
        _adjustLayer.Visibility = _c.AdjustMode ? Visibility.Visible : Visibility.Collapsed;
    }

    // ---- Olaylar (§5.4) ----

    double Now => _clock.Elapsed.TotalSeconds;

    void OnEvent(LocalSubtitleEvent e) => Safe(() =>
    {
        var now = Now;
        _stack.StackPrevious = _c.Settings.Style.StackPrevious;
        switch (e.Kind)
        {
            case LocalEventKind.Subtitle:
                _screenUntil = null;
                if (e.Box is { } english)
                {
                    _english = english;
                    Reseat();
                }
                _stack.Show(e.Text, e.DurationMs, e.Paragraphs, now, e.Replace);
                break;
            case LocalEventKind.Overlay:
                _panels?.ShowItems(e.Items, e.DurationMs);
                return;
            case LocalEventKind.Screen:
                _stack.Show(e.Text, e.DurationMs, true, now);
                _screenUntil = now + e.DurationMs / 1000.0;
                break;
            case LocalEventKind.ScreenClear:
                if (_screenUntil is { } until && now < until) _stack.Hide();
                _screenUntil = null;
                _panels?.Clear();
                break;
            case LocalEventKind.Region:
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
        _panels?.Clear();
        _screenUntil = null;
        Draw();
    });

    void OnControllerChanged(object? sender, PropertyChangedEventArgs e) => Safe(() =>
    {
        switch (e.PropertyName)
        {
            case nameof(NinoController.Settings):
            case nameof(NinoController.AdjustMode):
            case nameof(NinoController.GameArea):
            case nameof(NinoController.UsesGameWindow):
            case nameof(NinoController.UsesCaptureCard):
                ApplySettings();
                break;
            case nameof(NinoController.IsTranslating):
                ApplyStyles();
                break;
            case nameof(NinoController.ShowsOnComputer):
                if (!_c.ShowsOnComputer)
                {
                    _stack.Hide();
                    _regions.Clear();
                    _panels?.Clear();
                }
                UpdatePanels();
                Draw();
                break;
        }
    });

    // ---- Çizim (§5.5) ----

    void Draw()
    {
        if (_broken || _disposed) return;
        var now = Now;
        var s = _c.Settings;
        var style = s.Style;
        var scale = Scale;
        var lines = _stack.Lines(now).ToList();
        if (_c.AdjustMode && lines.Count == 0) lines.Add(new StackLine(-1, L.Get("overlay.sample"), StackRole.Current, false, false));

        var keep = lines.Select(l => l.Id).ToHashSet();
        foreach (var gone in _lineBoxes.Keys.Where(k => !keep.Contains(k)).ToList())
        {
            _lineBoxes.Remove(gone);
            _fading.Remove(gone);
        }
        _lines.Children.Clear();
        foreach (var line in lines)
        {
            // Satır yığında yer değiştirince (şimdiki → önceki) boyu, boşluğu ve zemini değişir: kutu yeniden kurulur.
            if (!_lineBoxes.TryGetValue(line.Id, out var box) || !Equals(box.Tag, line.Role))
            {
                box = LineBox(line, style, scale);
                _lineBoxes[line.Id] = box;
                _fading.Remove(line.Id);
            }
            box.Opacity = line.Role switch
            {
                StackRole.Current => SubtitleStack.CurrentOpacity,
                StackRole.Previous => SubtitleStack.PreviousOpacity,
                _ => SubtitleStack.SecondPreviousOpacity,
            };
            if (line.Fading && _fading.Add(line.Id))
                box.BeginAnimation(OpacityProperty, new DoubleAnimation(box.Opacity, 0, TimeSpan.FromSeconds(SubtitleStack.Fade)));
            _lines.Children.Add(box);
        }

        _regionPanel.Children.Clear();
        foreach (var (_, (text, area)) in _regions.OrderBy(r => r.Value.Box?.Top ?? 0))
            _regionPanel.Children.Add(RegionBox(text, area, style, scale));

        var visible = _c.ShowsOnComputer && (lines.Count > 0 || _regions.Count > 0);
        if (visible && !IsVisible) Show();
        else if (!visible && IsVisible) Hide();

        if (_stack.NextChange(now) is { } next)
        {
            _timer.Interval = TimeSpan.FromSeconds(Math.Max(0.01, next - now));
            _timer.Start();
        }
    }

    static void ApplyFont(TextBlock t, SubtitleStyle style)
    {
        if (NinoFonts.ForSubtitle(style.Font) is { } family) t.FontFamily = family;
        t.Foreground = style.TextColor == SubtitleTextColor.Yellow ? Yellow : Brushes.White;
    }

    static Border LineBox(StackLine line, SubtitleStyle style, double scale)
    {
        var current = line.Role == StackRole.Current;
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
            Effect = new DropShadowEffect { Color = Colors.Black, Direction = 270, ShadowDepth = 2 * scale, BlurRadius = 4 * scale, Opacity = 1 },
        };
        ApplyFont(block, style);
        var band = style.BackgroundShape == SubtitleBackgroundShape.Band;
        return new Border
        {
            Tag = line.Role,
            Child = block,
            Background = Ui.Frozen(Color.FromArgb((byte)Math.Round(255 * OverlayDrawing.LineBackground(style.Background, current)), 0, 0, 0)),
            CornerRadius = new(band ? 0 : 10 * scale),
            HorizontalAlignment = band ? HorizontalAlignment.Stretch : HorizontalAlignment.Center,
            Padding = current ? new(26 * scale, 10 * scale, 26 * scale, 10 * scale) : new(20 * scale, 6 * scale, 20 * scale, 6 * scale),
            Margin = new(band ? -24 * scale : 0, 14 * scale, band ? -24 * scale : 0, 0),
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
        };
        ApplyFont(block, style);
        return new Border
        {
            Child = block,
            Background = RegionFill,
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

    // ---- Hata koruması (§5.8) ----

    void Safe(Action action)
    {
        if (_broken || _disposed) return;
        try { action(); }
        catch (Exception e) { Break(e); }
    }

    void Break(Exception e)
    {
        _broken = true;
        try
        {
            if (_c.DataFolder is { } folder) new ErrorLog(System.IO.Path.Combine(folder, LogNames.Error)).Write("Altyazı penceresi", e);
        }
        catch (Exception) { }
        try
        {
            _timer.Stop();
            Hide();
            _panels?.Hide();
        }
        catch (Exception) { }
        try
        {
            MessageBox.Show(L.Get("overlay.error.message") + "\n\n" + e.GetType().Name + ": " + e.Message, L.Get("app.error.title"),
                MessageBoxButton.OK, MessageBoxImage.Warning);
        }
        catch (Exception) { }
    }

    /// <summary>Ana pencere kapanınca: aboneliği çözer ve pencereyi kapatır.</summary>
    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        _timer.Stop();
        _c.ComputerOverlayEvent -= OnEvent;
        _c.ComputerOverlayCleared -= OnCleared;
        _c.PropertyChanged -= OnControllerChanged;
        try { _panels?.Close(); }
        catch (Exception) { }
        try { Close(); }
        catch (Exception) { }
    }

    // ---- Windows ----

    const int GwlExStyle = -20;
    const int WsExTransparent = 0x20;
    const int WsExToolWindow = 0x80;
    const int WsExNoActivate = 0x08000000;
    const uint WdaExcludeFromCapture = 0x11;

    [DllImport("user32.dll", EntryPoint = "GetWindowLongW")]
    static extern int GetWindowLong(IntPtr hwnd, int index);

    [DllImport("user32.dll", EntryPoint = "SetWindowLongW")]
    static extern int SetWindowLong(IntPtr hwnd, int index, int value);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    static extern bool SetWindowDisplayAffinity(IntPtr hwnd, uint affinity);
}
