// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.ComponentModel;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using Nino.App.Strings;
using Nino.Shell;
using Nino.Shell.Platform;

namespace Nino.App.Services;

/// <summary>
/// HDMI yakalama kartının oyununu bu bilgisayarda gösteren pencere (kaynaklar §3.5): siyah zemin, tam ekran (Esc ile
/// aç/kapat), üstte 4 sn sonra sönen ipucu, fare durunca 2,5 sn sonra gizlenen imleç. Kart her kareyi
/// <see cref="Push"/> ile verir; ekran her yenilemede yalnız en son kareyi çizer. Kullanıcı kapatırsa
/// <see cref="UserClosed"/>; çeviri durunca <see cref="CloseSilently"/>.
/// </summary>
public sealed class CardPlayerWindow : Window
{
    readonly Image _image = new() { Stretch = Stretch.Uniform };
    readonly Grid _surface = new() { Background = Brushes.Black };
    readonly Border _hint;
    readonly DispatcherTimer _cursorTimer;
    WriteableBitmap? _bitmap;
    (byte[] Pixels, int Width, int Height)? _latest;
    readonly object _frameGate = new();
    bool _silent;
    bool _fullScreen;
    Rect? _savedBounds;
    PixelRect? _area;

    /// <summary>Kullanıcı pencereyi kapattı.</summary>
    public event Action? UserClosed;

    /// <summary>Oyun alanının ekrandaki yeri (ekran pikseli) ya da yok; yalnız değişince.</summary>
    public event Action<PixelRect?>? AreaChanged;

    /// <summary>Kurar (arayüz iş parçacığında).</summary>
    public CardPlayerWindow()
    {
        Title = "Nino";
        Background = Brushes.Black;
        SetValue(FlowDirectionProperty, FlowDirection.LeftToRight);
        try
        {
            Icon = BitmapFrame.Create(new Uri("pack://application:,,,/Assets/Nino.ico"));
        }
        catch (Exception) { }
        RenderOptions.SetBitmapScalingMode(_image, BitmapScalingMode.Linear);
        _surface.Children.Add(_image);
        _hint = new Border
        {
            Background = new SolidColorBrush(Color.FromArgb(150, 0, 0, 0)),
            CornerRadius = new CornerRadius(18),
            Padding = new Thickness(18, 9, 18, 9),
            Margin = new Thickness(0, 28, 0, 0),
            HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Top,
            IsHitTestVisible = false,
            Child = new TextBlock
            {
                Text = L.Get("source.card.gameWindow.hint"),
                Foreground = Brushes.White,
                FontSize = 15,
                TextWrapping = TextWrapping.Wrap,
            },
        };
        _surface.Children.Add(_hint);
        Content = _surface;
        _cursorTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(2.5) };
        _cursorTimer.Tick += (_, _) =>
        {
            _cursorTimer.Stop();
            Cursor = Cursors.None;
        };
        MouseMove += (_, _) =>
        {
            Cursor = null;
            _cursorTimer.Stop();
            _cursorTimer.Start();
        };
        KeyDown += (_, e) =>
        {
            if (e.Key != Key.Escape) return;
            e.Handled = true;
            ToggleFullScreen();
        };
        Loaded += (_, _) =>
        {
            FadeHint();
            _cursorTimer.Start();
        };
        SizeChanged += (_, _) => ReportArea();
        LocationChanged += (_, _) => ReportArea();
        StateChanged += (_, _) => ReportArea();
        CompositionTarget.Rendering += OnRendering;
    }

    void FadeHint()
    {
        var fade = new DoubleAnimation(1, 0, TimeSpan.FromSeconds(0.8)) { BeginTime = TimeSpan.FromSeconds(4) };
        _hint.BeginAnimation(OpacityProperty, fade);
    }

    /// <summary>Tam ekranda açar.</summary>
    public void ShowFullScreen()
    {
        Show();
        EnterFullScreen();
    }

    /// <summary>Tam ekranı açar ya da kapatır (küçültülmüşse önce normal).</summary>
    public void ToggleFullScreen()
    {
        if (WindowState is WindowState.Minimized) WindowState = WindowState.Normal;
        if (_fullScreen) LeaveFullScreen();
        else EnterFullScreen();
    }

    void EnterFullScreen()
    {
        if (IsLoaded && WindowState == WindowState.Normal && !_fullScreen) _savedBounds = new Rect(Left, Top, Width, Height);
        _fullScreen = true;
        WindowState = WindowState.Normal;
        Chrome(full: true);
        var work = SystemParameters.WorkArea;
        Left = work.Left;
        Top = work.Top;
        Width = Math.Max(640, work.Width / 2);
        Height = Math.Max(360, work.Height / 2);
        WindowState = WindowState.Maximized;
    }

    void Chrome(bool full)
    {
        WindowStyle = full ? WindowStyle.None : WindowStyle.SingleBorderWindow;
        ResizeMode = full ? ResizeMode.NoResize : ResizeMode.CanResize;
    }

    void LeaveFullScreen()
    {
        _fullScreen = false;
        WindowState = WindowState.Normal;
        Chrome(full: false);
        if (_savedBounds is { } b)
        {
            Left = b.Left;
            Top = b.Top;
            Width = b.Width;
            Height = b.Height;
            return;
        }
        var work = SystemParameters.WorkArea;
        var w = Math.Min(1280, work.Width * 0.8);
        var h = w * 9 / 16 + SystemParameters.WindowCaptionHeight + 2 * SystemParameters.ResizeFrameHorizontalBorderHeight;
        Width = w;
        Height = h;
        Left = work.Left + (work.Width - w) / 2;
        Top = work.Top + (work.Height - h) / 2;
    }

    /// <summary>Kartın son karesi (herhangi bir iş parçacığından; sıkı BGRA).</summary>
    public void Push(byte[] pixels, int width, int height)
    {
        lock (_frameGate) _latest = (pixels, width, height);
    }

    /// <summary>Son kareyi ve görüntüyü siler.</summary>
    public void Clear()
    {
        lock (_frameGate) _latest = null;
        _bitmap = null;
        _image.Source = null;
    }

    void OnRendering(object? sender, EventArgs e)
    {
        (byte[] Pixels, int Width, int Height)? frame;
        lock (_frameGate)
        {
            frame = _latest;
            _latest = null;
        }
        if (frame is not { } f) return;
        try
        {
            if (_bitmap is null || _bitmap.PixelWidth != f.Width || _bitmap.PixelHeight != f.Height)
            {
                _bitmap = new WriteableBitmap(f.Width, f.Height, 96, 96, PixelFormats.Bgr32, null);
                _image.Source = _bitmap;
            }
            _bitmap.WritePixels(new Int32Rect(0, 0, f.Width, f.Height), f.Pixels, f.Width * 4, 0);
        }
        catch (Exception) { }
    }

    void ReportArea()
    {
        PixelRect? area = null;
        try
        {
            if (IsLoaded && WindowState != WindowState.Minimized && _surface.ActualWidth > 0 && _surface.ActualHeight > 0)
            {
                var topLeft = _surface.PointToScreen(new Point(0, 0));
                var bottomRight = _surface.PointToScreen(new Point(_surface.ActualWidth, _surface.ActualHeight));
                var w = (int)Math.Round(bottomRight.X - topLeft.X);
                var h = (int)Math.Round(bottomRight.Y - topLeft.Y);
                var a = GameWindowRules.GameArea(w, h);
                area = new PixelRect((int)Math.Round(topLeft.X) + a.X, (int)Math.Round(topLeft.Y) + a.Y, a.Width, a.Height);
            }
        }
        catch (InvalidOperationException) { }
        SetArea(area);
    }

    void SetArea(PixelRect? area)
    {
        if (area == _area) return;
        _area = area;
        AreaChanged?.Invoke(area);
    }

    /// <summary>Olay yaymadan kapatır (çeviri durdu).</summary>
    public void CloseSilently()
    {
        _silent = true;
        Close();
    }

    /// <inheritdoc />
    protected override void OnClosing(CancelEventArgs e)
    {
        base.OnClosing(e);
        if (e.Cancel) return;
        CompositionTarget.Rendering -= OnRendering;
        _cursorTimer.Stop();
        SetArea(null);
        if (!_silent) UserClosed?.Invoke();
    }
}
