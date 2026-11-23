// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Effects;
using System.Windows.Shapes;
using System.Windows.Threading;
using Nino.App.Theme;
using Nino.Core.Settings;
using Nino.Shell.Panels;

namespace Nino.App.Views;

/// <summary>
/// Görünüş bölümünün canlı önizlemesi (Mac'le aynı): koyu oyun sahnesi (üç renkli geçiş, bulanık turuncu ve mavi
/// daire) üstünde demo satırları; önce İngilizce satır 0,9 sn, sonra çevirisi 2,6 sn, 0,5 sn boşluk. Hareket
/// azaltılmışsa yalnız çeviri sabit görünür. Ekran okuyucudan gizlidir.
/// </summary>
internal sealed class SubtitlePreview : Border
{
    readonly Grid _scene = new();
    readonly TextBlock _english;
    readonly Border _box;
    readonly TextBlock _translated;
    readonly DispatcherTimer _timer = new();
    SubtitleStyle _style = new();
    int _index;
    int _phase; // 0 çeviri, 1 boşluk, 2 İngilizce

    public SubtitlePreview(double width, double height)
    {
        Width = width;
        Height = height;
        CornerRadius = new(14);
        BorderThickness = new(1);
        this.Res(BorderBrushProperty, "tileBorderBrush");
        ClipToBounds = true;
        FlowDirection = FlowDirection.LeftToRight;
        Focusable = false;
        System.Windows.Automation.AutomationProperties.SetIsOffscreenBehavior(this, System.Windows.Automation.IsOffscreenBehavior.Offscreen);

        _scene.Background = new LinearGradientBrush(new GradientStopCollection
        {
            new(Color.FromRgb(26, 36, 71), 0),
            new(Color.FromRgb(61, 36, 56), 0.5),
            new(Color.FromRgb(15, 20, 36), 1),
        }, new Point(0, 0), new Point(1, 1));
        _scene.Children.Add(Blob(Color.FromArgb(115, 255, 165, 0), width * 0.40, width * 0.78, height * 0.22, width * 0.08));
        _scene.Children.Add(Blob(Color.FromArgb(102, 0, 0, 255), width * 0.45, width * 0.12, height * 0.55, width * 0.09));

        _english = new TextBlock
        {
            Foreground = new SolidColorBrush(Color.FromArgb(235, 255, 255, 255)),
            FontWeight = FontWeights.Medium,
            TextAlignment = TextAlignment.Center,
            TextWrapping = TextWrapping.Wrap,
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Bottom,
            Effect = new DropShadowEffect { Color = Colors.Black, Opacity = 0.8, BlurRadius = 4, ShadowDepth = 1 },
        };
        _translated = new TextBlock
        {
            Foreground = Brushes.White,
            TextAlignment = TextAlignment.Center,
            TextWrapping = TextWrapping.Wrap,
            FontFamily = NinoFonts.ForSubtitle(SubtitleFont.Condensed) ?? NinoFonts.Text,
            FontWeight = FontWeights.SemiBold,
        };
        _box = new Border
        {
            Child = _translated,
            CornerRadius = new(6),
            Padding = new(10, 4, 10, 4),
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Bottom,
        };
        _scene.Children.Add(_english);
        _scene.Children.Add(_box);
        Child = _scene;

        _timer.Tick += (_, _) => Step();
        Loaded += (_, _) => Restart();
        Unloaded += (_, _) => _timer.Stop();
        Show();
    }

    static Ellipse Blob(Color color, double size, double centerX, double centerY, double blur)
    {
        var e = new Ellipse
        {
            Width = size,
            Height = size,
            Fill = new SolidColorBrush(color),
            HorizontalAlignment = HorizontalAlignment.Left,
            VerticalAlignment = VerticalAlignment.Top,
            Margin = new(centerX - size / 2, centerY - size / 2, 0, 0),
            Effect = new BlurEffect { Radius = blur },
            IsHitTestVisible = false,
        };
        return e;
    }

    /// <summary>Görünüm değişti: önizleme yeniden çizilir.</summary>
    public void Apply(SubtitleStyle style)
    {
        _style = style;
        Show();
    }

    void Restart()
    {
        _timer.Stop();
        _phase = 0;
        Show();
        if (Motion.IsReduced) return;
        _timer.Interval = TimeSpan.FromSeconds(2.6);
        _timer.Start();
    }

    void Step()
    {
        switch (_phase)
        {
            case 0:
                _phase = 1;
                _timer.Interval = TimeSpan.FromSeconds(0.5);
                break;
            case 1:
                _index++;
                _phase = 2;
                _timer.Interval = TimeSpan.FromSeconds(0.9);
                break;
            default:
                _phase = 0;
                _timer.Interval = TimeSpan.FromSeconds(2.6);
                break;
        }
        Show();
    }

    void Show()
    {
        var (source, translated) = SubtitleLookRules.DemoLines[_index % SubtitleLookRules.DemoLines.Count];
        var size = SubtitleLookRules.PreviewFontSize(_style, Width);
        var bottom = _style.Placement == SubtitlePlacement.Fixed
            ? Math.Max(10, Height * _style.BottomPercent / 100.0)
            : Height * 0.08;
        _english.Text = source;
        _english.FontSize = size;
        _english.Margin = new(12, 0, 12, bottom);
        _translated.Text = translated;
        _translated.FontSize = size;
        _box.Margin = new(12, 0, 12, bottom);
        var alpha = (byte)Math.Round(Math.Clamp(_style.Background, 0, 100) / 100.0 * 255);
        _box.Background = new SolidColorBrush(Color.FromArgb(alpha, 0, 0, 0));
        _box.HorizontalAlignment = _style.BackgroundShape == SubtitleBackgroundShape.Band
            ? HorizontalAlignment.Stretch
            : HorizontalAlignment.Center;
        _english.Visibility = _phase == 2 ? Visibility.Visible : Visibility.Collapsed;
        _box.Visibility = _phase == 0 ? Visibility.Visible : Visibility.Collapsed;
    }
}
