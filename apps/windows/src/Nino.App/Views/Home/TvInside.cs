// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Effects;
using System.Windows.Shapes;
using System.Windows.Threading;
using Nino.App.Controls;
using Nino.App.Strings;
using Nino.App.Theme;
using Nino.Shell;

namespace Nino.App.Views;

// TV ekranının içi (ana-ekran §5), salon ve cam anahtarda ortak. Temadan bağımsız; aynalanmaz.

/// <summary>Bekleme ekranı (§5.1): siyah zemin, ortada büyük harfli "fişi prize sürükleyin" yazısı.</summary>
internal sealed class TvIdleScreen : Border
{
    static readonly FontFamily IdleFont = new("Consolas, Courier New");

    public TvIdleScreen(double screenScale)
    {
        Background = Brushes.Black;
        FlowDirection = FlowDirection.LeftToRight;
        Child = new TextBlock
        {
            Text = L.Upper("home.tv.idle"),
            FontFamily = IdleFont,
            FontWeight = FontWeights.SemiBold,
            FontSize = 13 * screenScale,
            Foreground = HomeUi.Solid(0x66, 0xFF, 0xFF, 0xFF),
            TextWrapping = TextWrapping.Wrap,
            TextAlignment = TextAlignment.Center,
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center,
            Margin = new Thickness(40 * screenScale, 0, 40 * screenScale, 0),
        };
    }
}

/// <summary>
/// Canlı ekran (§5.2): koyu degrade zemin, (salonda, havuz öncelikli oyunda) gün batımı fonu, yanıp sönen CANLI rozeti
/// ve altta ortalı satır kutusu.
/// </summary>
internal sealed class TvLiveScreen : Grid
{
    readonly double _fontSize;
    readonly Border _lineBox;
    readonly TextBlock _line;
    readonly UIElement? _sunset;
    string? _shownText;
    bool? _shownSubtitle;

    /// <param name="width">Ekran genişliği.</param>
    /// <param name="height">Ekran yüksekliği.</param>
    /// <param name="fontSize">Satırın yazı boyu (salonda 46, cam anahtarda 30).</param>
    /// <param name="withSunset">Gün batımı fonu katmanı olsun mu (yalnız salonda).</param>
    public TvLiveScreen(double width, double height, double fontSize, bool withSunset)
    {
        _fontSize = fontSize;
        Width = width;
        Height = height;
        FlowDirection = FlowDirection.LeftToRight;
        ClipToBounds = true;
        Background = new LinearGradientBrush(HomeUi.Rgb(0x171F3D), HomeUi.Rgb(0x26172E), new Point(0, 0), new Point(1, 1));

        if (withSunset)
        {
            var sunset = new Grid { Visibility = Visibility.Collapsed, IsHitTestVisible = false };
            sunset.Children.Add(new Rectangle
            {
                Fill = new LinearGradientBrush(new GradientStopCollection
                {
                    new(Color.FromRgb(26, 20, 87), 0),
                    new(Color.FromRgb(117, 41, 158), 0.40),
                    new(Color.FromRgb(237, 74, 153), 0.74),
                    new(Color.FromRgb(255, 140, 122), 1),
                }, new Point(0, 0), new Point(0, 1)),
            });
            sunset.Children.Add(new Rectangle { Fill = HomeUi.Solid(0x47, 0, 0, 0) });
            _sunset = sunset;
            Children.Add(sunset);
        }

        // CANLI rozeti.
        var h = height;
        var dot = new Ellipse
        {
            Width = h * 0.025,
            Height = h * 0.025,
            Fill = HomeUi.Solid(0xE30A17),
            Margin = new Thickness(0, 0, h * 0.02, 0),
            VerticalAlignment = VerticalAlignment.Center,
        };
        dot.BeginAnimation(OpacityProperty, new DoubleAnimation(1, 0.3, TimeSpan.FromSeconds(1))
        {
            AutoReverse = true,
            RepeatBehavior = RepeatBehavior.Forever,
        });
        var badgeRow = new StackPanel { Orientation = Orientation.Horizontal };
        badgeRow.Children.Add(dot);
        badgeRow.Children.Add(new TextBlock
        {
            Text = L.Get("home.tv.live"),
            Foreground = Brushes.White,
            FontWeight = FontWeights.Bold,
            FontSize = h * 0.035,
            TextWrapping = TextWrapping.NoWrap,
            VerticalAlignment = VerticalAlignment.Center,
        });
        Children.Add(new Border
        {
            Background = HomeUi.Solid(0x66, 0, 0, 0),
            CornerRadius = new CornerRadius(h * 0.04),
            Padding = new Thickness(h * 0.03, h * 0.012, h * 0.03, h * 0.012),
            Margin = new Thickness(h * 0.05, h * 0.05, 0, 0),
            HorizontalAlignment = HorizontalAlignment.Left,
            VerticalAlignment = VerticalAlignment.Top,
            Child = badgeRow,
        });

        // Satır.
        var f = fontSize;
        _line = new TextBlock
        {
            FontSize = fontSize,
            TextWrapping = TextWrapping.Wrap,
            TextAlignment = TextAlignment.Center,
            Foreground = Brushes.White,
        };
        _lineBox = new Border
        {
            CornerRadius = new CornerRadius(0.2 * f),
            Padding = new Thickness(0.5 * f, 0.2 * f, 0.5 * f, 0.2 * f),
            Margin = new Thickness(0.06 * width, 0, 0.06 * width, 0.08 * height),
            MaxWidth = width * 0.88,
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Bottom,
            Child = _line,
        };
        Children.Add(_lineBox);
    }

    /// <summary>Gün batımı fonu görünür mü (havuz öncelikli oyun).</summary>
    public void SetSunset(bool visible) => _sunset?.Show(visible);

    /// <summary>
    /// Satırı yazar: gösterilecek (sağdan sola işaretli) metin aynıysa dokunulmaz. Altyazıysa yarı kalın beyaz, koyu kutu;
    /// değilse soluk normal yazı, saydam kutu. Her değişimde kutu 300 ms'de belirir.
    /// </summary>
    public void SetLine(LiveLine line)
    {
        var text = RightToLeft.PrepareText(line.Text);
        if (text == _shownText && line.IsSubtitle == _shownSubtitle) return;
        _shownText = text;
        _shownSubtitle = line.IsSubtitle;
        _line.Text = text;
        _line.FlowDirection = RightToLeft.ForText(text);
        if (line.IsSubtitle)
        {
            _line.Foreground = Brushes.White;
            _line.FontWeight = FontWeights.SemiBold;
            _lineBox.Background = HomeUi.Solid(0xB0, 0, 0, 0);
        }
        else
        {
            _line.Foreground = HomeUi.Solid(0xAA, 0xFF, 0xFF, 0xFF);
            _line.FontWeight = FontWeights.Normal;
            _lineBox.Background = Brushes.Transparent;
        }
        _lineBox.BeginAnimation(OpacityProperty, new DoubleAnimation(0, 1, TimeSpan.FromMilliseconds(300)));
    }

    /// <summary>Satırın yazı boyu.</summary>
    public double LineFontSize => _fontSize;
}

/// <summary>
/// Nino açılışı (§5.3, fiş takılınca; sahne pikseli, ölçeksiz): ışınsal zemin, mavi ışık, yaylanarak beliren logo,
/// "Nino" ve alt yazı; 2350 ms sonra 450 ms'de söner, bitince <see cref="Finished"/>. Hareketi azalt'a bakmaz.
/// </summary>
internal sealed class TvSplashScreen : Grid
{
    /// <summary>Açılış bitti (sönme tamamlandı).</summary>
    public event Action? Finished;

    public TvSplashScreen()
    {
        FlowDirection = FlowDirection.LeftToRight;
        ClipToBounds = true;
        Background = new RadialGradientBrush(HomeUi.Rgb(0x10265C), HomeUi.Rgb(0x040816));
        IsHitTestVisible = false;

        Children.Add(new Ellipse
        {
            Width = 360,
            Height = 360,
            Fill = HomeUi.Solid(0x55, 0x1F, 0x5C, 0xFF),
            Effect = new BlurEffect { Radius = 80 },
            VerticalAlignment = VerticalAlignment.Center,
            HorizontalAlignment = HorizontalAlignment.Center,
            Margin = new Thickness(0, 0, 0, 120),
        });

        var logoScale = new ScaleTransform { ScaleX = 0.72, ScaleY = 0.72 };
        var logo = new Image
        {
            Source = LogoBox.Logo,
            Width = 230,
            Height = 230,
            Stretch = Stretch.Uniform,
            VerticalAlignment = VerticalAlignment.Center,
            HorizontalAlignment = HorizontalAlignment.Center,
            Margin = new Thickness(0, 0, 0, 120),
            RenderTransformOrigin = new Point(0.5, 0.5),
            RenderTransform = logoScale,
            Opacity = 0,
        };
        RenderOptions.SetBitmapScalingMode(logo, BitmapScalingMode.HighQuality);
        Children.Add(logo);

        var texts = new StackPanel
        {
            VerticalAlignment = VerticalAlignment.Center,
            HorizontalAlignment = HorizontalAlignment.Center,
            Margin = new Thickness(0, 300, 0, 0),
            Opacity = 0,
        };
        texts.Children.Add(new TextBlock
        {
            Text = L.Get("app.error.title"),
            FontSize = 64,
            FontWeight = FontWeights.Bold,
            Foreground = Brushes.White,
            TextAlignment = TextAlignment.Center,
            HorizontalAlignment = HorizontalAlignment.Center,
        });
        texts.Children.Add(new TextBlock
        {
            Text = L.Get("home.tv.splashTagline"),
            FontSize = 26,
            Foreground = HomeUi.Solid(0xAA, 0xFF, 0xFF, 0xFF),
            TextAlignment = TextAlignment.Center,
            TextWrapping = TextWrapping.Wrap,
            HorizontalAlignment = HorizontalAlignment.Center,
        });
        Children.Add(texts);

        Loaded += (_, _) =>
        {
            var pop = new DoubleAnimation(0.72, 1, TimeSpan.FromMilliseconds(900))
            {
                EasingFunction = new BackEase { Amplitude = 0.3, EasingMode = EasingMode.EaseOut },
            };
            logoScale.BeginAnimation(ScaleTransform.ScaleXProperty, pop);
            logoScale.BeginAnimation(ScaleTransform.ScaleYProperty, pop);
            var logoFade = new DoubleAnimation(0, 1, TimeSpan.FromMilliseconds(700));
            logo.BeginAnimation(OpacityProperty, logoFade);
            texts.BeginAnimation(OpacityProperty, new DoubleAnimation(0, 1, TimeSpan.FromMilliseconds(600))
            {
                BeginTime = TimeSpan.FromMilliseconds(650),
            });
            var exit = new DoubleAnimation(1, 0, TimeSpan.FromMilliseconds(450)) { BeginTime = TimeSpan.FromMilliseconds(2350) };
            exit.Completed += (_, _) => Finished?.Invoke();
            BeginAnimation(OpacityProperty, exit);
        };
    }
}

/// <summary>
/// TV'nin sağ üstündeki toplam indirme göstergesi (§5.4): büyük harfli başlık ve binlik ayırıcılı sayı, siyah çerçeve
/// ve derinlik kopyalarıyla, eğik. Canlı ekrana yeni girilince 1-2-3 ve hızlanan sayma, sonunda vuruş ve yeşil ışık.
/// </summary>
internal sealed class TvDownloadBadge : StackPanel, IDisposable
{
    static readonly Color Green = Color.FromRgb(0x7B, 0xE8, 0x7B);

    readonly long _total;
    readonly List<TextBlock> _numberLayers = [];
    readonly Grid _number;
    readonly ScaleTransform _punch = new(1, 1);
    readonly DispatcherTimer? _timer;
    readonly DateTime _started;
    TextBlock? _glow;

    /// <param name="total">Toplam indirme.</param>
    /// <param name="scale">Ekran ölçeği.</param>
    /// <param name="countUp">Sayma gösterisi oynasın mı.</param>
    public TvDownloadBadge(long total, double scale, bool countUp)
    {
        _total = total;
        FlowDirection = FlowDirection.LeftToRight;
        IsHitTestVisible = false;
        HorizontalAlignment = HorizontalAlignment.Right;
        VerticalAlignment = VerticalAlignment.Top;
        Margin = new Thickness(0, 18 * scale, 18 * scale, 0);

        var impact = NinoFonts.IsInstalled("Impact");
        var family = new FontFamily(impact ? "Impact" : "Segoe UI");
        var weight = impact ? FontWeights.Normal : FontWeights.Black;

        var title = L.Upper("home.tv.totalDownloads");
        var titleLayers = new List<TextBlock>();
        Children.Add(Outlined(title, 11 * scale, Brushes.White, 1 * scale, scale, family, weight, titleLayers));

        _number = Outlined(DownloadCountUp.Format(countUp ? 1 : total, System.Globalization.CultureInfo.CurrentCulture),
            27 * scale, Frozen(Green), 1.5 * scale, scale, family, weight, _numberLayers);
        _number.Margin = new Thickness(0, 1 * scale, 0, 0);
        _number.HorizontalAlignment = HorizontalAlignment.Right;
        _number.RenderTransformOrigin = new Point(1, 0.5);
        _number.RenderTransform = _punch;
        Children.Add(_number);

        if (!title.EnumerateRunes().Any(r => Nino.Core.Translation.TargetLanguages.IsArabicLetter(r.Value)))
            RenderTransform = new MatrixTransform(1, 0, -0.12, 1, 3 * scale, 0);

        if (countUp)
        {
            foreach (var layer in _numberLayers) System.Windows.Documents.Typography.SetNumeralAlignment(layer, FontNumeralAlignment.Tabular);
            _started = DateTime.UtcNow;
            _timer = new DispatcherTimer(DispatcherPriority.Render) { Interval = TimeSpan.FromMilliseconds(16) };
            _timer.Tick += OnTick;
            Loaded += (_, _) => _timer.Start();
        }
        Unloaded += (_, _) => _timer?.Stop();
    }

    void OnTick(object? sender, EventArgs e)
    {
        var elapsed = (DateTime.UtcNow - _started).TotalMilliseconds;
        SetNumber(DownloadCountUp.Shown(elapsed, _total));
        if (!DownloadCountUp.Finished(elapsed)) return;
        _timer!.Stop();
        SetNumber(_total);
        Punch();
    }

    void SetNumber(long value)
    {
        var text = DownloadCountUp.Format(value, System.Globalization.CultureInfo.CurrentCulture);
        foreach (var layer in _numberLayers) layer.Text = text;
        if (_glow is not null) _glow.Text = text;
    }

    /// <summary>Sayı sağ-orta noktasından büyür ve yeşil ışık yanıp söner.</summary>
    void Punch()
    {
        var grow = new DoubleAnimationUsingKeyFrames();
        grow.KeyFrames.Add(new EasingDoubleKeyFrame(1.32, KeyTime.FromTimeSpan(TimeSpan.FromMilliseconds(220)),
            new BackEase { Amplitude = 0.5, EasingMode = EasingMode.EaseOut }));
        grow.KeyFrames.Add(new LinearDoubleKeyFrame(1.32, KeyTime.FromTimeSpan(TimeSpan.FromMilliseconds(260))));
        grow.KeyFrames.Add(new EasingDoubleKeyFrame(1, KeyTime.FromTimeSpan(TimeSpan.FromMilliseconds(710)),
            new BackEase { Amplitude = 0.3, EasingMode = EasingMode.EaseOut }));
        grow.FillBehavior = FillBehavior.Stop;
        _punch.BeginAnimation(ScaleTransform.ScaleXProperty, grow);
        _punch.BeginAnimation(ScaleTransform.ScaleYProperty, grow);

        var top = _numberLayers[^1];
        _glow = new TextBlock
        {
            Text = top.Text,
            FontFamily = top.FontFamily,
            FontWeight = top.FontWeight,
            FontSize = top.FontSize,
            Foreground = Frozen(Green),
            Opacity = 0,
            Effect = new DropShadowEffect { Color = Green, ShadowDepth = 0, BlurRadius = 28, Opacity = 1 },
        };
        _number.Children.Add(_glow);
        var light = new DoubleAnimationUsingKeyFrames();
        light.KeyFrames.Add(new EasingDoubleKeyFrame(0.95, KeyTime.FromTimeSpan(TimeSpan.FromMilliseconds(220)),
            new QuadraticEase { EasingMode = EasingMode.EaseOut }));
        light.KeyFrames.Add(new LinearDoubleKeyFrame(0.95, KeyTime.FromTimeSpan(TimeSpan.FromMilliseconds(260))));
        light.KeyFrames.Add(new LinearDoubleKeyFrame(0, KeyTime.FromTimeSpan(TimeSpan.FromMilliseconds(710))));
        light.FillBehavior = FillBehavior.Stop;
        var glow = _glow;
        light.Completed += (_, _) =>
        {
            _number.Children.Remove(glow);
            if (ReferenceEquals(_glow, glow)) _glow = null;
        };
        glow.BeginAnimation(OpacityProperty, light);
    }

    /// <summary>
    /// Siyah çerçeveli yazı: önce derinlik (dd = w + s; dx ∈ {−w, 0, w} için (dx, w + dd) ve (dx, w + dd/2)'de siyah
    /// %90), sonra sekiz yöne tam siyah, en üstte renkli yazı.
    /// </summary>
    static Grid Outlined(string text, double size, Brush fill, double w, double s, FontFamily family, FontWeight weight,
        List<TextBlock> layers)
    {
        var stack = new Grid { HorizontalAlignment = HorizontalAlignment.Right };
        var depth = HomeUi.Solid(0xE6, 0, 0, 0);
        var dd = w + s;
        foreach (var dx in new[] { -w, 0, w })
        {
            Add(dx, w + dd, depth);
            Add(dx, w + dd / 2, depth);
        }
        foreach (var dx in new[] { -w, 0, w })
            foreach (var dy in new[] { -w, 0, w })
                if (dx != 0 || dy != 0) Add(dx, dy, Brushes.Black);
        Add(0, 0, fill);
        return stack;

        void Add(double x, double y, Brush brush)
        {
            var block = new TextBlock
            {
                Text = text,
                FontFamily = family,
                FontWeight = weight,
                FontSize = size,
                Foreground = brush,
                TextWrapping = TextWrapping.NoWrap,
                HorizontalAlignment = HorizontalAlignment.Right,
                RenderTransform = new TranslateTransform(x, y),
            };
            layers.Add(block);
            stack.Children.Add(block);
        }
    }

    static SolidColorBrush Frozen(Color color)
    {
        var brush = new SolidColorBrush(color);
        brush.Freeze();
        return brush;
    }

    public void Dispose() => _timer?.Stop();
}
