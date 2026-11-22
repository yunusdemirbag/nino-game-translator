// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Documents;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Effects;
using System.Windows.Threading;
using Nino.Core.Link;
using Nino.Shell;
using Nino.Shell.Panels;
using Nino.Shell.Platform;

namespace Nino.App.Views;

/// <summary>
/// Sürekli örtülerin (telefon/harita panelleri) bilgisayardaki katmanı: oyunun ekrandaki alanının (oyun penceresi ya da
/// kart oynatıcısı) tam üstünde duran, kenarsız, saydam, tıklamaları geçiren, odak almayan pencere. Öğeler oyunun
/// alanına oranla gelir (<see cref="ScreenPanelLayout"/>). Oyunun alanı bilinmiyorsa hiçbir şey çizmez. Oyun
/// penceresinden okunurken ekran kopyalarından gizlenir (Nino kendi panelini yeniden okumasın). Altyazı penceresi
/// kurar ve kapatır; hatalar altyazı penceresinin korumasına düşer.
/// </summary>
public sealed class GamePanelWindow : Window
{
    readonly Canvas _canvas = new() { IsHitTestVisible = false, ClipToBounds = true };
    readonly DispatcherTimer _expire = new();
    IReadOnlyList<ScreenItem> _items = [];
    ScreenRect? _area;
    bool _hideFromCapture;
    IntPtr _hwnd;

    public GamePanelWindow()
    {
        Title = "Nino";
        WindowStyle = WindowStyle.None;
        AllowsTransparency = true;
        Background = Brushes.Transparent;
        Topmost = true;
        ShowInTaskbar = false;
        ShowActivated = false;
        Focusable = false;
        IsHitTestVisible = false;
        ResizeMode = ResizeMode.NoResize;
        FlowDirection = FlowDirection.LeftToRight;
        FontFamily = Theme.NinoFonts.Text;
        Content = _canvas;
        _expire.Tick += (_, _) =>
        {
            _expire.Stop();
            Clear();
        };
        SourceInitialized += (_, _) =>
        {
            _hwnd = new WindowInteropHelper(this).Handle;
            ApplyStyles();
        };
    }

    /// <summary>Örtüleri gösterir (öncekilerin yerine); süre dolunca kendiliğinden kalkar.</summary>
    public void ShowItems(IReadOnlyList<ScreenItem>? items, int durationMs)
    {
        _items = items ?? [];
        _expire.Stop();
        if (_items.Count > 0 && durationMs > 0)
        {
            _expire.Interval = TimeSpan.FromMilliseconds(durationMs);
            _expire.Start();
        }
        Draw();
    }

    /// <summary>Örtüleri kaldırır.</summary>
    public void Clear()
    {
        _items = [];
        _expire.Stop();
        Draw();
    }

    /// <summary>
    /// Oyunun ekrandaki alanı (WPF birimi) ya da yok; <paramref name="hideFromCapture"/>: ekran kopyalarından gizlensin mi.
    /// </summary>
    public void SetArea(ScreenRect? area, bool hideFromCapture)
    {
        _area = area is { Width: > 1, Height: > 1 } a ? a : null;
        if (_hideFromCapture != hideFromCapture)
        {
            _hideFromCapture = hideFromCapture;
            ApplyStyles();
        }
        Draw();
    }

    void ApplyStyles()
    {
        if (_hwnd == IntPtr.Zero) return;
        var ex = GetWindowLong(_hwnd, GwlExStyle);
        SetWindowLong(_hwnd, GwlExStyle, ex | WsExNoActivate | WsExToolWindow | WsExTransparent | WsExLayered);
        try { SetWindowDisplayAffinity(_hwnd, _hideFromCapture ? WdaExcludeFromCapture : 0); }
        catch (Exception) { }
    }

    void Draw()
    {
        _canvas.Children.Clear();
        if (_area is not { } area || _items.Count == 0)
        {
            if (IsVisible) Hide();
            return;
        }
        Left = area.X;
        Top = area.Y;
        Width = area.Width;
        Height = area.Height;
        foreach (var v in ScreenPanelLayout.LayoutAll(_items, area.Width, area.Height))
            _canvas.Children.Add(Build(v));
        if (!IsVisible) Show();
    }

    static Color ToColor(PanelColor c, double alpha = 1) =>
        Color.FromArgb((byte)Math.Round(255 * Math.Clamp(alpha, 0, 1)), c.R, c.G, c.B);

    static FrameworkElement Build(PanelVisual v)
    {
        var text = new TextBlock
        {
            FontSize = v.FontSize,
            FontWeight = FontWeights.SemiBold,
            FontStyle = v.Italic ? FontStyles.Italic : FontStyles.Normal,
            Foreground = new SolidColorBrush(ToColor(v.Ink)),
            TextWrapping = TextWrapping.Wrap,
            TextAlignment = v.Kind is PanelKind.Card or PanelKind.Backdrop ? TextAlignment.Left : TextAlignment.Center,
            LineHeight = v.FontSize * 1.2,
            LineStackingStrategy = LineStackingStrategy.BlockLineHeight,
            Width = Math.Max(1, v.Rect.Width - 2 * v.Padding),
        };
        var accent = new SolidColorBrush(ToColor(ScreenPanelLayout.Accent));
        var first = true;
        foreach (var run in v.Runs)
        {
            var parts = run.Text.Split('\n');
            for (var i = 0; i < parts.Length; i++)
            {
                if (i > 0)
                {
                    text.Inlines.Add(new LineBreak());
                    first = false;
                }
                if (parts[i].Length == 0) continue;
                var r = new Run(parts[i]);
                if (run.Highlight) r.Foreground = accent;
                if (v.BoldFirstLine && first) r.FontWeight = FontWeights.Bold;
                text.Inlines.Add(r);
            }
        }
        if (v.Shadow)
            text.Effect = new DropShadowEffect { Color = Colors.Black, Direction = 270, ShadowDepth = 1.5, BlurRadius = 4, Opacity = 0.8 };
        var fit = new Viewbox
        {
            Stretch = Stretch.Uniform,
            StretchDirection = StretchDirection.DownOnly,
            Child = text,
            VerticalAlignment = v.VerticalCenter ? VerticalAlignment.Center : VerticalAlignment.Top,
            HorizontalAlignment = HorizontalAlignment.Center,
        };
        var inner = new Grid();
        if (v.AccentBar)
            inner.Children.Add(new Border
            {
                Height = Math.Max(2, v.FontSize * 0.14),
                Background = accent,
                VerticalAlignment = VerticalAlignment.Top,
                Margin = new Thickness(-v.Padding, -v.Padding * 0.6, -v.Padding, 0),
            });
        inner.Children.Add(fit);
        var box = new Border
        {
            Width = v.Rect.Width,
            Height = v.Rect.Height,
            CornerRadius = new CornerRadius(v.CornerRadius),
            Background = v.Fill is { } fill && v.FillAlpha > 0 ? new SolidColorBrush(ToColor(fill, v.FillAlpha)) : Brushes.Transparent,
            Padding = new Thickness(v.Padding, v.Padding * 0.6, v.Padding, v.Padding * 0.6),
            Child = inner,
            ClipToBounds = v.Kind == PanelKind.Card,
        };
        if (v.Kind == PanelKind.Side)
            box.Effect = new DropShadowEffect { Color = Colors.Black, Direction = 270, ShadowDepth = 2, BlurRadius = 8, Opacity = 0.35 };
        if (v.Angle != 0) box.RenderTransform = new RotateTransform(v.Angle, v.Rect.Width / 2, v.Rect.Height / 2);
        Canvas.SetLeft(box, v.Rect.X);
        Canvas.SetTop(box, v.Rect.Y);
        return box;
    }

    // ---- Windows ----

    const int GwlExStyle = -20;
    const int WsExTransparent = 0x20;
    const int WsExToolWindow = 0x80;
    const int WsExLayered = 0x80000;
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
