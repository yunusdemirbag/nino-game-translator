// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Shapes;
using Nino.App.Strings;
using Nino.Core.Imaging;
using Nino.Core.Settings;
using Nino.Shell.Panels;

namespace Nino.App.Views;

/// <summary>
/// Bölge seçici (ayarlar tarifi §8.4): oyun görüntüsünün üstünde çerçeve; kenarından boyutlandırılır, içinden
/// taşınır, dışarıdan yeniden çizilir. Altında sıfırlama düğmesi. Soldan sağa tutulur (Arapçada aynalanmaz).
/// Kodla bölge göstermenin iki yolu vardır: olaylı (kaydeder) ve olaysız (<see cref="Show"/>).
/// </summary>
public sealed class RegionPicker : StackPanel
{
    static readonly Brush FrameFill = Freeze(new SolidColorBrush(Color.FromArgb(36, 245, 184, 61)));

    readonly Border _box;
    readonly Canvas _canvas = new() { ClipToBounds = true, Background = Brushes.Transparent };
    readonly Image _image = new() { Stretch = Stretch.Fill };
    readonly TextBlock _placeholder;
    readonly Rectangle _frame = new() { StrokeThickness = 2 };
    readonly Rectangle[] _handles = new Rectangle[4];
    Region _region = RegionPresets.Bottom;
    Region _dragStart = RegionPresets.Bottom;
    RegionDragMode _mode;
    RegionEdges _edges;
    Point _down;
    int _frameWidth;
    int _frameHeight;

    public RegionPicker()
    {
        FlowDirection = FlowDirection.LeftToRight;
        _frame.Res(Shape.StrokeProperty, "accentBrush");
        _frame.Fill = FrameFill;
        _frame.IsHitTestVisible = false;
        _image.IsHitTestVisible = false;
        RenderOptions.SetBitmapScalingMode(_image, BitmapScalingMode.HighQuality);
        _placeholder = new TextBlock
        {
            Text = L.Get("settings.area.previewPlaceholder"),
            TextAlignment = TextAlignment.Center,
            TextWrapping = TextWrapping.Wrap,
            IsHitTestVisible = false,
        }.Styled("Text.Caption");
        _canvas.Children.Add(_image);
        _canvas.Children.Add(_placeholder);
        _canvas.Children.Add(_frame);
        for (var i = 0; i < 4; i++)
        {
            _handles[i] = new Rectangle { Width = 10, Height = 10, IsHitTestVisible = false };
            _handles[i].SetResourceReference(Shape.FillProperty, "accentBrush");
            _canvas.Children.Add(_handles[i]);
        }
        _box = new Border { CornerRadius = new(10), ClipToBounds = true, Child = _canvas, Height = 281 };
        _box.Res(Border.BackgroundProperty, "backgroundBrush");
        _box.SizeChanged += (_, e) =>
        {
            _box.Clip = new RectangleGeometry(new Rect(e.NewSize), 10, 10);
            UpdateHeight();
            Layout();
        };
        Children.Add(_box);

        var reset = Ui.Button(L.Get("settings.area.resetArea"), () => SetRegion(ResetRegion, raise: true)).At(0, 12, 0, 0);
        Children.Add(reset);

        _canvas.MouseLeftButtonDown += OnDown;
        _canvas.MouseMove += OnMove;
        _canvas.MouseLeftButtonUp += (_, e) => EndDrag(e.GetPosition(_canvas));
        _canvas.LostMouseCapture += (_, _) =>
        {
            if (_mode != RegionDragMode.None) EndDrag(null);
        };
        IsEnabledChanged += (_, _) => Opacity = IsEnabled ? 1 : 0.4;
    }

    /// <summary>Kullanıcı bölgeyi değiştirdi (ya da sıfırlama düğmesi).</summary>
    public event Action<Region>? RegionChanged;

    /// <summary>Gösterilen bölge.</summary>
    public Region Region => _region;

    /// <summary>Sıfırlama düğmesinin döndüğü bölge.</summary>
    public Region ResetRegion { get; set; } = RegionPresets.Bottom;

    /// <summary>Fareyle sürükleniyor mu (önizleme bu sırada yenilenmez).</summary>
    public bool IsDragging => _mode != RegionDragMode.None;

    /// <summary>Bölgeyi olay üretmeden gösterir.</summary>
    public void Show(Region region) => SetRegion(region, raise: false);

    /// <summary>Bölgeyi gösterir; <paramref name="raise"/> ise olay gelir.</summary>
    public void SetRegion(Region region, bool raise)
    {
        _region = region;
        Layout();
        if (raise) RegionChanged?.Invoke(region);
    }

    /// <summary>Önizleme karesi (yoksa yer tutucu yazı).</summary>
    public void SetFrame(BgraFrame? frame)
    {
        if (frame is null || frame.Width <= 0 || frame.Height <= 0)
        {
            _image.Source = null;
            _frameWidth = _frameHeight = 0;
        }
        else
        {
            try
            {
                var bitmap = BitmapSource.Create(frame.Width, frame.Height, 96, 96, PixelFormats.Bgra32, null, frame.Pixels, frame.Stride);
                bitmap.Freeze();
                _image.Source = bitmap;
                _frameWidth = frame.Width;
                _frameHeight = frame.Height;
            }
            catch (Exception)
            {
                _image.Source = null;
                _frameWidth = _frameHeight = 0;
            }
        }
        _placeholder.Visibility = _image.Source is null ? Visibility.Visible : Visibility.Collapsed;
        UpdateHeight();
        Layout();
    }

    void UpdateHeight()
    {
        var height = RegionPickerMath.PreviewHeight(_box.ActualWidth, _frameWidth, _frameHeight);
        if (Math.Abs(_box.Height - height) > 0.5) _box.Height = height;
    }

    void Layout()
    {
        var w = _canvas.ActualWidth;
        var h = _canvas.ActualHeight;
        if (w <= 0 || h <= 0) return;
        _image.Width = w;
        _image.Height = h;
        _placeholder.Width = Math.Max(0, w - 48);
        _placeholder.Measure(new Size(_placeholder.Width, double.PositiveInfinity));
        Canvas.SetLeft(_placeholder, 24);
        Canvas.SetTop(_placeholder, Math.Max(24, (h - _placeholder.DesiredSize.Height) / 2));
        var left = _region.Left * w;
        var top = _region.Top * h;
        var right = _region.Right * w;
        var bottom = _region.Bottom * h;
        Canvas.SetLeft(_frame, left);
        Canvas.SetTop(_frame, top);
        _frame.Width = Math.Max(0, right - left);
        _frame.Height = Math.Max(0, bottom - top);
        Point[] corners = [new(left, top), new(right, top), new(left, bottom), new(right, bottom)];
        for (var i = 0; i < 4; i++)
        {
            Canvas.SetLeft(_handles[i], corners[i].X - 5);
            Canvas.SetTop(_handles[i], corners[i].Y - 5);
        }
    }

    void OnDown(object sender, MouseButtonEventArgs e)
    {
        if (!IsEnabled) return;
        var p = e.GetPosition(_canvas);
        _mode = RegionPickerMath.ModeAt(_region, p.X, p.Y, _canvas.ActualWidth, _canvas.ActualHeight, out _edges);
        _dragStart = _region;
        _down = p;
        _canvas.CaptureMouse();
        e.Handled = true;
    }

    void OnMove(object sender, MouseEventArgs e)
    {
        var p = e.GetPosition(_canvas);
        var w = _canvas.ActualWidth;
        var h = _canvas.ActualHeight;
        if (_mode == RegionDragMode.None)
        {
            _canvas.Cursor = !IsEnabled ? Cursors.Arrow : RegionPickerMath.CursorAt(_region, p.X, p.Y, w, h) switch
            {
                RegionCursor.Move => Cursors.SizeAll,
                RegionCursor.WestEast => Cursors.SizeWE,
                RegionCursor.NorthSouth => Cursors.SizeNS,
                RegionCursor.NorthWestSouthEast => Cursors.SizeNWSE,
                RegionCursor.NorthEastSouthWest => Cursors.SizeNESW,
                _ => Cursors.Cross,
            };
            return;
        }
        _region = Track(p, w, h);
        Layout();
    }

    Region Track(Point p, double w, double h)
    {
        var x = RegionPickerMath.Unit(p.X, w);
        var y = RegionPickerMath.Unit(p.Y, h);
        return _mode switch
        {
            RegionDragMode.Draw => RegionPickerMath.Draw(RegionPickerMath.Unit(_down.X, w), RegionPickerMath.Unit(_down.Y, h), x, y),
            RegionDragMode.Move => RegionPickerMath.Move(_dragStart, (p.X - _down.X) / Math.Max(1, w), (p.Y - _down.Y) / Math.Max(1, h)),
            RegionDragMode.Resize => RegionPickerMath.Resize(_dragStart, _edges, x, y),
            _ => _region,
        };
    }

    void EndDrag(Point? at)
    {
        if (_mode == RegionDragMode.None) return;
        var mode = _mode;
        if (at is { } p) _region = Track(p, _canvas.ActualWidth, _canvas.ActualHeight);
        _mode = RegionDragMode.None;
        if (_canvas.IsMouseCaptured) _canvas.ReleaseMouseCapture();
        _region = RegionPickerMath.Finish(mode, _dragStart, _region);
        Layout();
        if (!RegionPickerMath.Same(_region, _dragStart)) RegionChanged?.Invoke(_region);
    }

    static Brush Freeze(SolidColorBrush b)
    {
        b.Freeze();
        return b;
    }
}
