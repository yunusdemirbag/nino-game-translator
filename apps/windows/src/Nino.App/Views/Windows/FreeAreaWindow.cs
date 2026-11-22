// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Shapes;
using System.Windows.Threading;
using Nino.App.Strings;
using Nino.App.Theme;
using Nino.Core.Imaging;
using Nino.Core.Settings;
using Nino.Shell;
using Nino.Shell.Panels;

namespace Nino.App.Views;

/// <summary>
/// Serbest seçim penceresi (yan pencereler tarifi §6): son kare donar, ekranı kaplar; fareyle seçilen yer bir kez
/// okunup çevrilir ve sonuç seçimin altında gösterilir. Esc (bırakınca) ya da sağ tık kapatır.
/// </summary>
public sealed class FreeAreaWindow : Window
{
    static readonly Brush SelectionFill = Ui.Frozen(Color.FromArgb(40, 245, 184, 61));

    readonly NinoController _c;
    readonly BgraFrame _frame;
    readonly Canvas _canvas;
    readonly Rectangle _selection;
    readonly Border _result;
    readonly TextBlock _resultText;
    Point _start;
    bool _dragging;
    int _sequence;
    bool _closed;
    bool _escapeDown;

    /// <summary>Denetleyicinin "serbest alan" isteğini karşılar: açıksa öne getirir, son kare yoksa bir şey yapmaz.</summary>
    public static void Request(NinoController controller)
    {
        var open = Application.Current?.Windows.OfType<FreeAreaWindow>().FirstOrDefault(w => w.IsVisible);
        if (open is not null)
        {
            open.Activate();
            return;
        }
        if (controller.LastFrame is not { } frame) return;
        new FreeAreaWindow(controller, frame).Show();
    }

    public FreeAreaWindow(NinoController controller, BgraFrame frame)
    {
        _c = controller;
        _frame = frame;
        Title = "Nino";
        WindowStyle = WindowStyle.None;
        ResizeMode = ResizeMode.NoResize;
        WindowState = WindowState.Maximized;
        Topmost = true;
        ShowInTaskbar = false;
        Background = Brushes.Black;
        Cursor = Cursors.Cross;
        FlowDirection = FlowDirection.LeftToRight;
        FontFamily = NinoFonts.Text;

        _canvas = new Canvas { Width = frame.Width, Height = frame.Height, Background = Brushes.Black };
        var image = new Image
        {
            Width = frame.Width,
            Height = frame.Height,
            Source = Bitmap(frame),
            IsHitTestVisible = false,
        };
        _canvas.Children.Add(image);
        _selection = new Rectangle
        {
            StrokeThickness = FreeAreaMath.BorderThickness(frame.Height),
            Fill = SelectionFill,
            Visibility = Visibility.Collapsed,
            IsHitTestVisible = false,
        };
        _selection.Res(Shape.StrokeProperty, "accentBrush");
        _canvas.Children.Add(_selection);
        _resultText = new TextBlock
        {
            Foreground = Brushes.White,
            FontSize = FreeAreaMath.FontSize(frame.Height),
            TextWrapping = TextWrapping.Wrap,
            MaxWidth = frame.Width / 2.0,
        };
        _result = new Border
        {
            Background = Ui.Frozen(Color.FromArgb(0xE6, 0, 0, 0)),
            CornerRadius = new(frame.Height * 0.012),
            Padding = new(frame.Height * 0.018),
            Child = _resultText,
            Visibility = Visibility.Collapsed,
            IsHitTestVisible = false,
        };
        _canvas.Children.Add(_result);

        var hint = new Border
        {
            Background = Ui.Frozen(Color.FromArgb(0xB3, 0, 0, 0)),
            Padding = new(16, 8, 16, 8),
            Margin = new(0, 12, 0, 0),
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Top,
            IsHitTestVisible = false,
            Child = new TextBlock { Text = L.Get("freeArea.hint"), Foreground = Brushes.White, FontSize = 15 },
        };
        var root = new Grid();
        root.Children.Add(new Viewbox { Stretch = Stretch.Uniform, Child = _canvas });
        root.Children.Add(hint);
        Content = root;

        _canvas.MouseLeftButtonDown += OnDown;
        _canvas.MouseMove += OnMove;
        _canvas.MouseLeftButtonUp += OnUp;
        MouseRightButtonUp += (_, _) => Close();
        PreviewKeyDown += (_, e) =>
        {
            if (e.Key != Key.Escape) return;
            e.Handled = true;
            _escapeDown = true;
        };
        PreviewKeyUp += (_, e) =>
        {
            if (e.Key != Key.Escape || !_escapeDown) return;
            e.Handled = true;
            Close();
        };
        Closed += (_, _) => _closed = true;
    }

    static BitmapSource? Bitmap(BgraFrame frame)
    {
        try
        {
            var b = BitmapSource.Create(frame.Width, frame.Height, 96, 96, PixelFormats.Bgra32, null, frame.Pixels, frame.Stride);
            b.Freeze();
            return b;
        }
        catch (Exception) { return null; }
    }

    Point Clamp(Point p) => new(Math.Clamp(p.X, 0, _frame.Width), Math.Clamp(p.Y, 0, _frame.Height));

    void OnDown(object sender, MouseButtonEventArgs e)
    {
        _start = Clamp(e.GetPosition(_canvas));
        _dragging = true;
        _result.Visibility = Visibility.Collapsed;
        _selection.Visibility = Visibility.Visible;
        Place(_start, _start);
        _canvas.CaptureMouse();
        e.Handled = true;
    }

    void OnMove(object sender, MouseEventArgs e)
    {
        if (_dragging) Place(_start, Clamp(e.GetPosition(_canvas)));
    }

    void Place(Point a, Point b)
    {
        Canvas.SetLeft(_selection, Math.Min(a.X, b.X));
        Canvas.SetTop(_selection, Math.Min(a.Y, b.Y));
        _selection.Width = Math.Abs(a.X - b.X);
        _selection.Height = Math.Abs(a.Y - b.Y);
    }

    async void OnUp(object sender, MouseButtonEventArgs e)
    {
        if (!_dragging) return;
        _dragging = false;
        _canvas.ReleaseMouseCapture();
        var end = Clamp(e.GetPosition(_canvas));
        var left = Math.Min(_start.X, end.X);
        var top = Math.Min(_start.Y, end.Y);
        var width = Math.Abs(_start.X - end.X);
        var height = Math.Abs(_start.Y - end.Y);
        if (FreeAreaMath.TooSmall(width, height, _frame.Width, _frame.Height))
        {
            _selection.Visibility = Visibility.Collapsed;
            return;
        }
        var sequence = ++_sequence;
        ShowResult(L.Get("freeArea.translating"), left, top, top + height);
        var box = new Box(left / _frame.Width, top / _frame.Height, (left + width) / _frame.Width, (top + height) / _frame.Height);
        FreeAreaResult result;
        try { result = await _c.TranslateFreeAreaAsync(_frame, box); }
        catch (Exception) { result = new FreeAreaResult(OneShotResult.Failed); }
        if (_closed || sequence != _sequence) return;
        var text = result.Result switch
        {
            OneShotResult.Shown => result.Translation ?? "",
            OneShotResult.NoText => L.Get("status.area.noText"),
            OneShotResult.Busy => L.Get("freeArea.translating"),
            _ => L.Get("freeArea.failed"),
        };
        ShowResult(text, left, top, top + height);
        if (result.Result == OneShotResult.Shown && _c.Settings.FreeAreaTarget == ResultTarget.Tv)
        {
            var timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(700) };
            timer.Tick += (_, _) =>
            {
                timer.Stop();
                if (!_closed && sequence == _sequence) Close();
            };
            timer.Start();
        }
    }

    void ShowResult(string text, double selLeft, double selTop, double selBottom)
    {
        _resultText.Text = RightToLeft.PrepareText(text);
        _resultText.FlowDirection = RightToLeft.ForText(text);
        _result.Visibility = Visibility.Visible;
        _result.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity));
        var size = _result.DesiredSize;
        var (x, y) = FreeAreaMath.ResultPosition(selLeft, selTop, selBottom, size.Width, size.Height, _frame.Width, _frame.Height);
        Canvas.SetLeft(_result, x);
        Canvas.SetTop(_result, y);
    }
}

/// <summary>
/// Bilgisayar sonuç kutusu (yan pencereler tarifi §7): ek bölge çevirisi bilgisayarda gösterilecekse çalışma alanının
/// altında ortalı, kenarsız kutu. Tıklanınca ya da süre dolunca kapanır; yenisi gelince öncekinin yerini alır.
/// </summary>
public sealed class PcResultWindow : Window
{
    static PcResultWindow? _current;

    /// <summary>Kutuyu gösterir (önceki kapanır).</summary>
    public static void Present(PopupText popup)
    {
        _current?.Close();
        var window = new PcResultWindow(popup);
        _current = window;
        window.Closed += (_, _) =>
        {
            if (_current == window) _current = null;
        };
        window.Show();
    }

    PcResultWindow(PopupText popup)
    {
        Title = "Nino";
        WindowStyle = WindowStyle.None;
        AllowsTransparency = true;
        Background = Brushes.Transparent;
        Topmost = true;
        ShowInTaskbar = false;
        ShowActivated = false;
        ResizeMode = ResizeMode.NoResize;
        SizeToContent = SizeToContent.WidthAndHeight;
        Cursor = Cursors.Hand;
        FontFamily = NinoFonts.Text;
        var work = SystemParameters.WorkArea;
        MaxWidth = work.Width * 0.7;
        var text = RightToLeft.PrepareText(popup.Text);
        Content = new Border
        {
            Background = Ui.Frozen(Color.FromArgb(0xEE, 0, 0, 0)),
            CornerRadius = new(12),
            Padding = new(20, 14, 20, 14),
            Child = new TextBlock
            {
                Text = text,
                Foreground = Brushes.White,
                FontSize = 24,
                TextWrapping = TextWrapping.Wrap,
                FlowDirection = RightToLeft.ForText(text),
            },
        };
        MouseLeftButtonUp += (_, _) => Close();
        ContentRendered += (_, _) =>
        {
            Left = work.Left + (work.Width - ActualWidth) / 2;
            Top = work.Bottom - 40 - ActualHeight;
        };
        var timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(Math.Max(1500, popup.DurationMs)) };
        timer.Tick += (_, _) =>
        {
            timer.Stop();
            Close();
        };
        Loaded += (_, _) => timer.Start();
        Closed += (_, _) => timer.Stop();
    }
}
