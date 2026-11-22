// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.ComponentModel;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Effects;
using System.Windows.Shapes;
using Nino.App.Controls;
using Nino.App.Strings;
using Nino.Shell;

namespace Nino.App.Views;

/// <summary>
/// Cam anahtar (ana-ekran §6): kapalıyken soğuk mavi-gri; açılınca küre sağa kayar, iz bayrak kırmızısına döner,
/// kürenin içinde ay-yıldız belirir; çeviri açıkken üstte canlı TV durur. Tamamı soldan sağa kalır; temadan bağımsız
/// (açıklama ve kaynak satırı hariç).
/// </summary>
public sealed class GlassToggle : StackPanel, IDisposable
{
    const double TrackWidth = 400, TrackHeight = 92, Knob = 116;
    static readonly TimeSpan Slide = TimeSpan.FromMilliseconds(550);
    static readonly Color FlagRed = Color.FromRgb(0xE3, 0x0A, 0x17);

    readonly NinoController _c;
    readonly FrameworkElement _tv;
    readonly TvLiveScreen _live;
    readonly TextBlock _source;
    readonly TextBlock _description;
    readonly Border _redTrack;
    readonly StackPanel _offText;
    readonly TextBlock _offTitle;
    readonly TextBlock _offSubtitle;
    readonly StackPanel _onText;
    readonly TranslateTransform _knobSlide = new();
    readonly Ellipse _disc;
    readonly TextBlock _power;
    readonly FrameworkElement _crescent;
    bool? _on;
    bool _disposed;

    public GlassToggle(NinoController controller)
    {
        _c = controller;
        FlowDirection = FlowDirection.LeftToRight;
        HorizontalAlignment = HorizontalAlignment.Center;
        VerticalAlignment = VerticalAlignment.Center;

        // ---- Canlı TV (§6.1) ----
        _live = new TvLiveScreen(580, 326, 30, withSunset: false);
        var inner = new Border { CornerRadius = new CornerRadius(12), ClipToBounds = true, Child = _live };
        var frame = new Border
        {
            Background = HomeUi.Solid(0x0D0D12),
            CornerRadius = new CornerRadius(18),
            Padding = new Thickness(7),
            Child = inner,
            HorizontalAlignment = HorizontalAlignment.Center,
        };
        var tv = new StackPanel { Margin = new Thickness(0, 0, 0, 24), HorizontalAlignment = HorizontalAlignment.Center };
        tv.Children.Add(frame);
        tv.Children.Add(new Rectangle { Width = 34, Height = 14, Fill = HomeUi.Solid(0x1F1F26), HorizontalAlignment = HorizontalAlignment.Center });
        tv.Children.Add(new Rectangle
        {
            Width = 150,
            Height = 6,
            RadiusX = 3,
            RadiusY = 3,
            Fill = HomeUi.Solid(0x1F1F26),
            HorizontalAlignment = HorizontalAlignment.Center,
        });
        _source = HomeUi.Text("", "Text.Secondary", new Thickness(0, 10, 0, 0));
        _source.FontStyle = FontStyles.Italic;
        _source.TextAlignment = TextAlignment.Center;
        _source.TextWrapping = TextWrapping.NoWrap;
        _source.TextTrimming = TextTrimming.CharacterEllipsis;
        _source.MaxWidth = 580;
        _source.HorizontalAlignment = HorizontalAlignment.Center;
        tv.Children.Add(_source);
        _tv = tv;
        Children.Add(tv);

        // ---- Anahtar (§6.2) ----
        var track = new Grid { Width = TrackWidth, Height = TrackHeight, Cursor = Cursors.Hand, Background = Brushes.Transparent };
        track.Children.Add(new Border
        {
            CornerRadius = new CornerRadius(46),
            Background = new LinearGradientBrush(HomeUi.Rgb(0x788CB3), HomeUi.Rgb(0x4D5C85), 90),
            BorderBrush = HomeUi.Solid(0x73, 0xFF, 0xFF, 0xFF),
            BorderThickness = new Thickness(1),
            Effect = new DropShadowEffect { Color = HomeUi.Rgb(0x4D5C85), BlurRadius = 30, ShadowDepth = 8, Opacity = 0.3 },
        });
        _redTrack = new Border
        {
            CornerRadius = new CornerRadius(46),
            Background = new LinearGradientBrush(FlagRed, HomeUi.Rgb(0xA80514), 90),
            Opacity = 0,
            Effect = new DropShadowEffect { Color = FlagRed, BlurRadius = 40, ShadowDepth = 6, Opacity = 0.6 },
        };
        track.Children.Add(_redTrack);
        track.Children.Add(new Border
        {
            CornerRadius = new CornerRadius(46),
            Margin = new Thickness(3),
            Background = new LinearGradientBrush(Color.FromArgb(0x59, 0xFF, 0xFF, 0xFF), Colors.Transparent, 90),
            IsHitTestVisible = false,
        });

        _offTitle = new TextBlock { FontSize = 22, FontWeight = FontWeights.SemiBold, Foreground = Brushes.White, TextAlignment = TextAlignment.Right, TextWrapping = TextWrapping.NoWrap };
        _offSubtitle = new TextBlock { FontSize = 12, Foreground = HomeUi.Solid(0xCC, 0xFF, 0xFF, 0xFF), TextAlignment = TextAlignment.Right, TextWrapping = TextWrapping.NoWrap };
        _offText = new StackPanel
        {
            HorizontalAlignment = HorizontalAlignment.Right,
            VerticalAlignment = VerticalAlignment.Center,
            Margin = new Thickness(0, 0, 30, 0),
            IsHitTestVisible = false,
        };
        _offText.Children.Add(_offTitle);
        _offText.Children.Add(_offSubtitle);
        track.Children.Add(_offText);

        _onText = new StackPanel
        {
            HorizontalAlignment = HorizontalAlignment.Left,
            VerticalAlignment = VerticalAlignment.Center,
            Margin = new Thickness(34, 0, 0, 0),
            Opacity = 0,
            IsHitTestVisible = false,
        };
        _onText.Children.Add(new TextBlock { Text = L.Get("home.toggle.turkish"), FontSize = 26, FontWeight = FontWeights.Bold, Foreground = Brushes.White, TextWrapping = TextWrapping.NoWrap });
        _onText.Children.Add(new TextBlock { Text = L.Get("home.toggle.subtitlesOn"), FontSize = 12, Foreground = HomeUi.Solid(0xD9, 0xFF, 0xFF, 0xFF), TextWrapping = TextWrapping.NoWrap });
        track.Children.Add(_onText);

        // Küre
        var knob = new Grid
        {
            Width = Knob,
            Height = Knob,
            HorizontalAlignment = HorizontalAlignment.Left,
            VerticalAlignment = VerticalAlignment.Center,
            Margin = new Thickness(-(Knob - TrackHeight) / 2, -(Knob - TrackHeight) / 2, 0, -(Knob - TrackHeight) / 2),
            RenderTransform = _knobSlide,
            IsHitTestVisible = false,
            Effect = new DropShadowEffect { BlurRadius = 18, ShadowDepth = 8, Opacity = 0.2 },
        };
        _disc = new Ellipse { Width = Knob * 0.62, Height = Knob * 0.62, Fill = HomeUi.Solid(0x5C6E99) };
        knob.Children.Add(_disc);
        _power = new TextBlock
        {
            Text = Glyphs.PowerButton,
            FontSize = 30,
            Foreground = Brushes.White,
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center,
        };
        _power.SetResourceReference(FrameworkElement.StyleProperty, "Text.Icon");
        knob.Children.Add(_power);
        _crescent = CrescentAndStar(Knob * 0.45);
        _crescent.Opacity = 0;
        knob.Children.Add(_crescent);
        knob.Children.Add(new Ellipse { Fill = HomeUi.Solid(0x30, 0xFF, 0xFF, 0xFF) });
        knob.Children.Add(new Ellipse
        {
            StrokeThickness = 2,
            Stroke = new LinearGradientBrush(Color.FromArgb(0xF2, 0xFF, 0xFF, 0xFF), Color.FromArgb(0x60, 0xFF, 0xFF, 0xFF),
                new Point(0, 0), new Point(1, 1)),
        });
        knob.Children.Add(new Ellipse
        {
            Width = Knob * 0.55,
            Height = Knob * 0.28,
            HorizontalAlignment = HorizontalAlignment.Left,
            VerticalAlignment = VerticalAlignment.Top,
            Margin = new Thickness(0.1 * Knob, 0.08 * Knob, 0, 0),
            Fill = new LinearGradientBrush(Color.FromArgb(0xA6, 0xFF, 0xFF, 0xFF), Colors.Transparent, 90),
        });
        track.Children.Add(knob);
        track.MouseLeftButtonUp += (_, e) =>
        {
            e.Handled = true;
            _ = HomeActions.ToggleAsync(_c);
        };
        track.HorizontalAlignment = HorizontalAlignment.Center;
        Children.Add(track);

        // ---- Açıklama (§6.4) ----
        _description = HomeUi.Text(L.Get("home.toggle.description"), "Text.Secondary", new Thickness(0, 28, 0, 0));
        _description.TextAlignment = TextAlignment.Center;
        _description.MaxWidth = 440;
        _description.HorizontalAlignment = HorizontalAlignment.Center;
        Children.Add(_description);

        controller.PropertyChanged += OnControllerChanged;
        Apply();
    }

    void OnControllerChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (!_disposed) Apply();
    }

    /// <summary>Durumu uygular (§6.5); yalnız açık/kapalı değiştiyse animasyonlu (550 ms, hareketi azalt'a bakmaz).</summary>
    void Apply()
    {
        var on = _c.IsTranslating || _c.IsStarting;
        _offTitle.Text = L.Get(GlassToggleText.TitleKey(_c.IsStarting, _c.CanStart));
        _offSubtitle.Text = L.Get(GlassToggleText.SubtitleKey(_c.IsStarting, _c.CanStart));
        if (on != _on)
        {
            var animate = _on is not null;
            _on = on;
            var duration = animate ? Slide : TimeSpan.Zero;
            _disc.Fill = on ? HomeUi.Solid(0xE30A17) : HomeUi.Solid(0x5C6E99);
            var slide = new DoubleAnimation(on ? TrackWidth - TrackHeight : 0, duration)
            {
                EasingFunction = new BackEase { Amplitude = 0.25, EasingMode = EasingMode.EaseOut },
            };
            _knobSlide.BeginAnimation(TranslateTransform.XProperty, slide);
            Fade(_redTrack, on ? 1 : 0, duration);
            Fade(_onText, on ? 1 : 0, duration);
            Fade(_crescent, on ? 1 : 0, duration);
            Fade(_offText, on ? 0 : 1, duration);
            Fade(_power, on ? 0 : 1, duration);
        }
        _tv.Show(on);
        _description.Show(!on);
        if (on)
        {
            _live.SetLine(LiveLineRule.Choose(_c.SessionStatus.Phase, _c.LastTranslation, _c.ConsoleStatusText,
                L.Get("home.tv.waitingNextSubtitle")));
            _source.Text = _c.LastSource ?? "";
        }
    }

    static void Fade(UIElement element, double to, TimeSpan duration) =>
        element.BeginAnimation(OpacityProperty, new DoubleAnimation(to, duration));

    /// <summary>Ay-yıldız (§6.3): b kenarlı kare, beyaz hilal ve beş köşeli yıldız.</summary>
    static FrameworkElement CrescentAndStar(double b)
    {
        var (moonCenter, moonRadius) = CrescentStar.Moon(b);
        var (cutCenter, cutRadius) = CrescentStar.Cut(b);
        var moon = new CombinedGeometry(GeometryCombineMode.Exclude,
            new EllipseGeometry(new Point(moonCenter.X, moonCenter.Y), moonRadius, moonRadius),
            new EllipseGeometry(new Point(cutCenter.X, cutCenter.Y), cutRadius, cutRadius));
        var points = CrescentStar.Star(b);
        var star = new StreamGeometry();
        using (var ctx = star.Open())
        {
            ctx.BeginFigure(new Point(points[0].X, points[0].Y), true, true);
            for (var i = 1; i < points.Count; i++) ctx.LineTo(new Point(points[i].X, points[i].Y), true, false);
        }
        var group = new GeometryGroup { Children = { moon, star } };
        group.Freeze();
        return new Path
        {
            Width = b,
            Height = b,
            Data = group,
            Fill = Brushes.White,
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center,
        };
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        _c.PropertyChanged -= OnControllerChanged;
    }
}
