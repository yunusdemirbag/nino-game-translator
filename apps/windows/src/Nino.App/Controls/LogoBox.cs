// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace Nino.App.Controls;

/// <summary>
/// Logo kutusu: <c>logo.png</c> (512 × 512) kare alana yüksek kaliteli küçültmeyle sığar; üstünde 1 px border renkli
/// çerçeve, köşe kenarın 0,225 katı (36'da 8,1). Koyu temada logonun kenarı zeminden ayrılsın diye.
/// Boyu Width/Height ile verin (kare).
/// </summary>
public class LogoBox : Grid
{
    /// <summary>Gömülü logo (bir kez çözülür).</summary>
    public static ImageSource Logo { get; } = Load();

    private readonly Border _frame;
    private readonly Image _image;

    public LogoBox()
    {
        FlowDirection = FlowDirection.LeftToRight;
        _image = new Image { Source = Logo, Stretch = Stretch.Uniform };
        RenderOptions.SetBitmapScalingMode(_image, BitmapScalingMode.HighQuality);
        _frame = new Border { BorderThickness = new Thickness(1), SnapsToDevicePixels = true };
        _frame.SetResourceReference(Border.BorderBrushProperty, "borderBrush");
        Children.Add(_image);
        Children.Add(_frame);
        SizeChanged += (_, e) => UpdateCorners(Math.Min(e.NewSize.Width, e.NewSize.Height));
    }

    private void UpdateCorners(double side)
    {
        var radius = side * 0.225;
        _frame.CornerRadius = new CornerRadius(radius);
        _image.Clip = new RectangleGeometry(new Rect(0, 0, side, side), radius, radius);
    }

    private static ImageSource Load()
    {
        var image = new BitmapImage();
        image.BeginInit();
        image.UriSource = new Uri("pack://application:,,,/Assets/logo.png", UriKind.Absolute);
        image.CacheOption = BitmapCacheOption.OnLoad;
        image.EndInit();
        image.Freeze();
        return image;
    }
}
