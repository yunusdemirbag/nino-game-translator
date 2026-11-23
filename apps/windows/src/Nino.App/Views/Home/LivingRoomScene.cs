// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.ComponentModel;
using System.Diagnostics;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Effects;
using System.Windows.Media.Imaging;
using System.Windows.Shapes;
using System.Windows.Threading;
using Nino.App.Strings;
using Nino.App.Theme;
using Nino.RemotePlay;
using Nino.Shell;
using SceneLayout = Nino.Shell.LivingRoomScene;

namespace Nino.App.Views;

/// <summary>
/// Salon sahnesi (ana-ekran §4): duvarda TV, sehpa, konsol ve priz. Fiş prize takılınca (tıklama ya da sürükleme)
/// çeviri başlar, mavi LED'ler yanar, TV'de Nino açılır ve altyazı akar; çekilince durur. Fiş çıkıkken priz yanıp
/// söner. Ölçüler sahne pikselidir (1672 × 941); tuval alana yalnız küçültülerek sığar. Tamamı soldan sağa kalır.
/// Prizin üstünde fiş balonu (Mac'teki gibi): tek kısa satır ve prizi gösteren ok; normalde soluk, fare prize, fişe ya da
/// balona gelince belirir (<see cref="PlugHintState"/>). Balon sahnenin dışında, ölçeklenmeyen katmanda; yalnız ok ucu
/// sahneye bağlı. Sürüklerken ve açılış gösterisinde gizli.
/// </summary>
public sealed class LivingRoomScene : Grid, IDisposable
{
    /// <summary>Uygulama her açıldığında açılış gösterisi bir kez oynar (süreç boyunca tek bayrak).</summary>
    static bool _introPlayed;

    static readonly TimeSpan IntroWait = TimeSpan.FromMilliseconds(900);
    static readonly TimeSpan DownloadsEvery = TimeSpan.FromSeconds(600);

    readonly NinoController _c;
    readonly SceneLayout _layout;
    readonly Canvas _scene = new() { Width = SceneLayout.ImageWidth, Height = SceneLayout.ImageHeight };
    readonly Viewbox _viewbox = new() { Stretch = Stretch.Uniform, StretchDirection = StretchDirection.DownOnly };

    // Fiş balonu (ölçeklenmeyen katman)
    readonly Canvas _hintLayer = new() { ClipToBounds = false };
    readonly Border _hintBubble = new() { Padding = new Thickness(12, 6, 12, 6), CornerRadius = new CornerRadius(12), BorderThickness = new Thickness(1) };
    readonly TextBlock _hintText = new() { TextAlignment = TextAlignment.Center, TextWrapping = TextWrapping.Wrap, MaxHeight = 44, TextTrimming = TextTrimming.CharacterEllipsis };
    readonly TextBlock _hintArrow = new() { Text = "\uE74B", FontSize = 14, Width = 18, TextAlignment = TextAlignment.Center, IsHitTestVisible = false };
    readonly HashSet<string> _hoverParts = [];

    // Oyun odası tabelası (ölçeklenmeyen katman; açıkken sahnenin üstünde yer ayrılır)
    readonly Canvas _signLayer = new() { ClipToBounds = false, IsHitTestVisible = false };
    readonly GameRoomSignView _sign = new();
    string? _signText;
    double _signSpace;
    string? _hintKey;
    bool? _hintShown;

    // Katmanlar
    readonly Canvas _leds = new() { IsHitTestVisible = false, Opacity = 0 };
    readonly Rectangle _ledWide, _ledNarrow, _ledTable, _ledStrip;
    readonly Grid _socketGlow = new() { IsHitTestVisible = false };
    readonly Rectangle _glowWide, _glowNarrow;
    readonly Grid _tvHost = new() { ClipToBounds = true };
    readonly Grid _downloadsHost = new() { ClipToBounds = true, IsHitTestVisible = false };
    readonly Path _cable = new() { IsHitTestVisible = false };
    readonly Canvas _plug = new() { Width = 120, Height = 140, Background = Brushes.Transparent, Cursor = Cursors.Hand };
    readonly Ellipse _seatedCap;
    readonly Canvas _looseOuter = new() { Width = 120, Height = 140 };
    readonly RotateTransform _looseTurn = new(0, 60, 70);

    readonly DispatcherTimer _introTimer = new();
    readonly DispatcherTimer _springTimer = new(DispatcherPriority.Render) { Interval = TimeSpan.FromMilliseconds(16) };
    readonly DispatcherTimer _downloadsTimer = new() { Interval = DownloadsEvery };
    readonly Stopwatch _springClock = new();

    bool _introWaiting;
    bool _plugged;
    bool _splashFinished = true;
    bool? _poolFirst;
    bool _pulsing;
    bool _glowReady;
    TvScreenKind? _screenKind;
    TvLiveScreen? _live;
    TvSplashScreen? _splash;
    long? _badgeTotal;
    bool _badgeOnLive;
    bool _badgeShown;
    TvDownloadBadge? _badge;

    ScenePoint _offset;
    bool _springing;
    bool _dragging;
    Point _dragStart;
    bool _disposed;

    /// <param name="controller">Denetleyici.</param>
    /// <param name="xbox">Xbox'lı düzen mi.</param>
    public LivingRoomScene(NinoController controller, bool xbox)
    {
        _c = controller;
        _layout = xbox ? SceneLayout.Xbox : SceneLayout.Ps5;
        FlowDirection = FlowDirection.LeftToRight;
        PlugHintState.Attach(controller.DataFolder);

        var shift = _layout.ShiftLeft;
        var canvas = new Canvas { Width = SceneLayout.ImageWidth + shift, Height = SceneLayout.ImageHeight };
        Canvas.SetLeft(_scene, shift);
        canvas.Children.Add(_scene);
        _viewbox.Child = canvas;
        Children.Add(_viewbox);
        _signLayer.Children.Add(_sign);
        Children.Add(_signLayer);
        BuildHint();
        Children.Add(_hintLayer);
        SizeChanged += (_, _) =>
        {
            PlaceSign();
            PlaceHint();
        };

        // 1. LED'ler
        var frame = _layout.Frame;
        var table = _layout.Table;
        _ledWide = Glow(frame.Width + 40, frame.Height + 40, frame.X - 20, frame.Y - 20, 30, 90);
        _ledNarrow = Glow(frame.Width + 10, frame.Height + 10, frame.X - 5, frame.Y - 5, 10, 24);
        _ledTable = Glow(table.Width - 60, 40, table.X + 30, table.Bottom - 14, 20, 50);
        _ledStrip = Glow(table.Width - 90, 8, table.X + 45, table.Bottom - 4, 4, 8);
        foreach (var led in new[] { _ledWide, _ledNarrow, _ledTable, _ledStrip }) _leds.Children.Add(led);
        _scene.Children.Add(_leds);

        // 2. Priz ışığı (görselin arkasında; ışık kenarlarından taşar)
        var socket = _layout.Socket;
        _glowWide = new Rectangle
        {
            Width = SceneLayout.SocketSize + 26,
            Height = SceneLayout.SocketSize + 26,
            RadiusX = 16,
            RadiusY = 16,
            Fill = HomeUi.Solid(0xFF, 77, 168, 255),
            Effect = new BlurEffect { Radius = 36 },
        };
        _glowNarrow = new Rectangle
        {
            Width = 94,
            Height = 94,
            RadiusX = 12,
            RadiusY = 12,
            Fill = HomeUi.Solid(0xFF, 158, 214, 255),
            Effect = new BlurEffect { Radius = 10 },
        };
        _socketGlow.Children.Add(_glowWide);
        _socketGlow.Children.Add(_glowNarrow);
        _socketGlow.Width = 112;
        _socketGlow.Height = 112;
        Canvas.SetLeft(_socketGlow, socket.X - 56);
        Canvas.SetTop(_socketGlow, socket.Y - 56);
        _scene.Children.Add(_socketGlow);

        // 3. Salon görseli (1672 × 941'e gerilir)
        var room = new Image
        {
            Source = LoadImage(_layout.Image),
            Width = SceneLayout.ImageWidth,
            Height = SceneLayout.ImageHeight,
            Stretch = Stretch.Fill,
            IsHitTestVisible = true,
        };
        RenderOptions.SetBitmapScalingMode(room, BitmapScalingMode.HighQuality);
        _scene.Children.Add(room);

        // 4–6. TV ekranı: siyah zemin, içerik, indirme göstergesi
        var screen = _layout.Screen;
        var black = new Rectangle { Width = screen.Width, Height = screen.Height, Fill = Brushes.Black };
        Place(black, screen.X, screen.Y);
        _scene.Children.Add(black);
        _tvHost.Width = screen.Width;
        _tvHost.Height = screen.Height;
        Place(_tvHost, screen.X, screen.Y);
        _scene.Children.Add(_tvHost);
        _downloadsHost.Width = screen.Width;
        _downloadsHost.Height = screen.Height;
        Place(_downloadsHost, screen.X, screen.Y);
        _scene.Children.Add(_downloadsHost);

        // 7. Prizin tıklama alanı
        var hit = new Rectangle { Width = 120, Height = 120, Fill = Brushes.Transparent, Cursor = Cursors.Hand };
        Place(hit, socket.X - 60, socket.Y - 60);
        hit.MouseLeftButtonUp += (_, e) =>
        {
            e.Handled = true;
            _ = HomeActions.ToggleAsync(_c);
        };
        hit.MouseEnter += (_, _) => Hover("socket", true);
        hit.MouseLeave += (_, _) => Hover("socket", false);
        _scene.Children.Add(hit);

        // 8. Kablo
        _cable.Stroke = HomeUi.Solid(0x0F0F0F);
        _cable.StrokeThickness = SceneLayout.CableThickness;
        _cable.StrokeStartLineCap = PenLineCap.Round;
        _cable.StrokeEndLineCap = PenLineCap.Round;
        _cable.StrokeLineJoin = PenLineJoin.Round;
        _cable.Effect = new DropShadowEffect { ShadowDepth = 2, Direction = 270, BlurRadius = 6, Opacity = 0.25 };
        _scene.Children.Add(_cable);

        // 9. Xbox: görselde kablo yok; kablonun başında küçük fiş başı
        if (_layout.CablePath.Count == 0)
        {
            var head = new Rectangle
            {
                Width = 14,
                Height = 12,
                RadiusX = 3,
                RadiusY = 3,
                Fill = HomeUi.Solid(0x141414),
                IsHitTestVisible = false,
            };
            Place(head, _layout.CableHead.X - 7, _layout.CableHead.Y - 6);
            _scene.Children.Add(head);
        }

        // 10. Fiş
        _seatedCap = new Ellipse
        {
            Width = 58,
            Height = 58,
            Fill = new LinearGradientBrush(HomeUi.Rgb(0x3D3D3D), HomeUi.Rgb(0x0A0A0A), new Point(0, 0), new Point(1, 1)),
            Stroke = HomeUi.Solid(0x2E, 0xFF, 0xFF, 0xFF),
            StrokeThickness = 1.5,
            Effect = new DropShadowEffect { Opacity = 0.45, ShadowDepth = 4, BlurRadius = 12 },
            IsHitTestVisible = false,
        };
        Place(_seatedCap, 31, 41);
        _plug.Children.Add(_seatedCap);
        BuildLoosePlug();
        _plug.Children.Add(_looseOuter);
        _plug.MouseLeftButtonDown += OnPlugDown;
        _plug.MouseMove += OnPlugMove;
        _plug.MouseLeftButtonUp += OnPlugUp;
        _plug.MouseEnter += (_, _) => Hover("plug", true);
        _plug.MouseLeave += (_, _) => Hover("plug", false);
        _plug.LostMouseCapture += (_, _) =>
        {
            if (_dragging) EndDrag(null);
        };
        _scene.Children.Add(_plug);

        _introTimer.Tick += (_, _) =>
        {
            _introTimer.Stop();
            _introWaiting = false;
            Apply(fromIntro: true, animate: true);
        };
        _springTimer.Tick += OnSpringTick;
        _downloadsTimer.Tick += (_, _) => _c.RefreshDownloads();

        Loaded += OnLoaded;
        Unloaded += (_, _) => StopTimers();
        _c.PropertyChanged += OnControllerChanged;
        PlugHintState.Changed += OnHintVisibilityChanged;

        if (!_introPlayed)
        {
            _introPlayed = true;
            _introWaiting = true;
        }
        _plugged = PlugShouldBeIn();
        _leds.Opacity = _plugged ? 1 : 0;
        Apply(fromIntro: false, animate: false, force: true);
    }

    // ---- Durum (§4.4) ----

    bool PlugShouldBeIn() => (_c.IsTranslating || _c.IsStarting) && !_introWaiting;

    void OnControllerChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (!_disposed) Apply(fromIntro: false, animate: true);
    }

    void Apply(bool fromIntro, bool animate, bool force = false)
    {
        var plugged = PlugShouldBeIn();
        if (plugged != _plugged || force)
        {
            var changed = plugged != _plugged;
            _plugged = plugged;
            if (changed)
            {
                _leds.BeginAnimation(OpacityProperty, new DoubleAnimation(plugged ? 1 : 0, TimeSpan.FromMilliseconds(800)));
                // Takıldıysa TV açılışı baştan oynar; çekildiyse bitmiş sayılır.
                _splashFinished = !plugged;
                if (_splash is not null) _splash.Finished -= OnSplashFinished;
                _splash = null;
            }
            UpdateSocketGlow(animate: animate && _glowReady);
            _glowReady = true;
            StopSpring();
            if (fromIntro && plugged && !Motion.IsReduced && !_dragging) StartSpring();
            else DrawPlug();
        }
        UpdateLedColors();
        UpdateTv();
        UpdateHint();
        UpdateSign(animate);
    }

    void UpdateLedColors()
    {
        var poolFirst = _c.PoolFirstLive;
        if (_poolFirst == poolFirst) return;
        _poolFirst = poolFirst;
        if (poolFirst)
        {
            var wide = Gradient((255, 61, 158), (189, 128, 245), (77, 199, 255));
            var narrow = Gradient((255, 133, 199), (214, 179, 255), (148, 224, 255));
            _ledWide.Fill = wide;
            _ledTable.Fill = wide;
            _ledNarrow.Fill = narrow;
            _ledStrip.Fill = narrow;
        }
        else
        {
            _ledWide.Fill = HomeUi.Solid(0x1F5CFF);
            _ledTable.Fill = HomeUi.Solid(0x1F5CFF);
            _ledNarrow.Fill = HomeUi.Solid(0x4D8CFF);
            _ledStrip.Fill = HomeUi.Solid(0x73A6FF);
        }
    }

    // ---- Priz ışığı (§4.7) ----

    void UpdateSocketGlow(bool animate)
    {
        var target = _plugged ? 0.0 : 1.0;
        if (!_plugged) StartPulse();
        if (animate && !Motion.IsReduced)
        {
            var fade = new DoubleAnimation(target, TimeSpan.FromMilliseconds(500));
            if (_plugged) fade.Completed += (_, _) =>
            {
                if (_plugged) StopPulse();
            };
            _socketGlow.BeginAnimation(OpacityProperty, fade);
        }
        else
        {
            _socketGlow.BeginAnimation(OpacityProperty, null);
            _socketGlow.Opacity = target;
            if (_plugged) StopPulse();
        }
    }

    void StartPulse()
    {
        if (Motion.IsReduced)
        {
            StopPulse();
            _glowWide.Opacity = 0.95;
            _glowNarrow.Opacity = 1;
            return;
        }
        if (_pulsing) return;
        _pulsing = true;
        _glowWide.BeginAnimation(OpacityProperty, Pulse(0.3, 0.95));
        _glowNarrow.BeginAnimation(OpacityProperty, Pulse(0.45, 1));
    }

    void StopPulse()
    {
        _pulsing = false;
        _glowWide.BeginAnimation(OpacityProperty, null);
        _glowNarrow.BeginAnimation(OpacityProperty, null);
        _glowWide.Opacity = 0.95;
        _glowNarrow.Opacity = 1;
    }

    static DoubleAnimation Pulse(double from, double to) => new(from, to, TimeSpan.FromSeconds(0.95))
    {
        AutoReverse = true,
        RepeatBehavior = RepeatBehavior.Forever,
        EasingFunction = PulseEase,
    };

    static readonly IEasingFunction PulseEase = new SineEase { EasingMode = EasingMode.EaseInOut };

    // ---- TV ekranı (§5.1) ----

    void UpdateTv()
    {
        var kind = TvScreenRule.Choose(_plugged, _splashFinished);
        var enteredLive = false;
        if (kind != _screenKind)
        {
            enteredLive = kind == TvScreenKind.Live;
            _screenKind = kind;
            if (_splash is not null) _splash.Finished -= OnSplashFinished;
            _splash = null;
            _live = null;
            _tvHost.Children.Clear();
            switch (kind)
            {
                case TvScreenKind.Idle:
                    _tvHost.Children.Add(new TvIdleScreen(_layout.ScreenScale));
                    break;
                case TvScreenKind.Splash:
                    _splash = new TvSplashScreen();
                    _splash.Finished += OnSplashFinished;
                    _tvHost.Children.Add(_splash);
                    break;
                default:
                    _live = new TvLiveScreen(_layout.Screen.Width, _layout.Screen.Height, 46, withSunset: true);
                    _tvHost.Children.Add(_live);
                    break;
            }
        }
        if (_live is not null)
        {
            _live.SetSunset(_c.PoolFirstLive);
            _live.SetLine(LiveLineRule.Choose(_c.SessionStatus.Phase, _c.LastTranslation, _c.ConsoleStatusText,
                L.Get("home.tv.waitingNextSubtitle")));
        }
        UpdateDownloads(enteredLive);
    }

    void OnSplashFinished()
    {
        if (_splash is null || !_plugged) return;
        _splashFinished = true;
        UpdateTv();
    }

    // ---- İndirme göstergesi (§5.4) ----

    void UpdateDownloads(bool enteredLive)
    {
        var visible = TvScreenRule.DownloadsVisible(_introWaiting, _screenKind ?? TvScreenKind.Idle);
        _downloadsHost.Show(visible);
        var total = _c.Downloads;
        var onLive = _screenKind == TvScreenKind.Live;
        var firstNumberOnLive = onLive && total is not null && _badgeTotal is null;
        if (total == _badgeTotal && onLive == _badgeOnLive && _badgeShown) return;
        _badgeTotal = total;
        _badgeOnLive = onLive;
        _badgeShown = true;
        _badge?.Dispose();
        _badge = null;
        _downloadsHost.Children.Clear();
        if (total is not { } n) return;
        var countUp = onLive && (enteredLive || firstNumberOnLive) && DownloadCountUp.Plays(n, Motion.IsReduced);
        _badge = new TvDownloadBadge(n, _layout.ScreenScale, countUp);
        _downloadsHost.Children.Add(_badge);
    }

    // ---- Fiş ve kablo (§4.8) ----

    void BuildLoosePlug()
    {
        var group = new Canvas { Width = 120, Height = 140, RenderTransform = _looseTurn };
        var neck = new Rectangle { Width = 13, Height = 14, RadiusX = 5, RadiusY = 5, Fill = HomeUi.Solid(0x0F0F0F) };
        Place(neck, 53.5, 26);
        group.Children.Add(neck);
        var body = new Rectangle
        {
            Width = 36,
            Height = 50,
            RadiusX = 9,
            RadiusY = 9,
            Fill = new LinearGradientBrush(HomeUi.Rgb(0x383838), HomeUi.Rgb(0x0A0A0A), new Point(0, 0.5), new Point(1, 0.5)),
            Stroke = HomeUi.Solid(0x24, 0xFF, 0xFF, 0xFF),
            StrokeThickness = 1,
        };
        Place(body, 42, 40);
        group.Children.Add(body);
        foreach (var x in new[] { 47.0, 67.0 })
        {
            var prong = new Rectangle
            {
                Width = 6,
                Height = 24,
                RadiusX = 3,
                RadiusY = 3,
                Fill = new LinearGradientBrush(HomeUi.Rgb(0xEBEBEB), HomeUi.Rgb(0x999999), new Point(0, 0.5), new Point(1, 0.5)),
            };
            Place(prong, x, 90);
            group.Children.Add(prong);
        }
        _looseOuter.IsHitTestVisible = false;
        _looseOuter.Effect = new DropShadowEffect { BlurRadius = 8, ShadowDepth = 3, Direction = 270, Opacity = 0.3 };
        _looseOuter.Children.Add(group);
    }

    /// <summary>Fişin yeri: (takılıysa priz, değilse dinlenme yeri) + fark.</summary>
    ScenePoint PlugPoint()
    {
        var at = _plugged ? _layout.Socket : _layout.PlugRest;
        return new ScenePoint(at.X + _offset.X, at.Y + _offset.Y);
    }

    void DrawPlug()
    {
        var point = PlugPoint();
        Canvas.SetLeft(_plug, point.X - 60);
        Canvas.SetTop(_plug, point.Y - 70);
        var seated = _plugged && !_dragging && !_springing;
        _seatedCap.Show(seated);
        _looseOuter.Show(!seated);
        if (!seated) _looseTurn.Angle = _layout.PlugRotation(point) * 180 / Math.PI;
        DrawCable(point, seated);
    }

    void DrawCable(ScenePoint plug, bool seated)
    {
        var (_, c1, c2, end) = _layout.Cable(plug, seated);
        var heads = _layout.CablePath.Count > 0 ? _layout.CablePath : [_layout.CableHead];
        var figure = new PathFigure { StartPoint = new Point(heads[0].X, heads[0].Y), IsFilled = false };
        for (var i = 1; i < heads.Count; i++) figure.Segments.Add(new LineSegment(new Point(heads[i].X, heads[i].Y), true));
        figure.Segments.Add(new BezierSegment(new Point(c1.X, c1.Y), new Point(c2.X, c2.Y), new Point(end.X, end.Y), true));
        var geometry = new PathGeometry { Figures = { figure } };
        geometry.Freeze();
        _cable.Data = geometry;
    }

    // ---- Açılış gösterisi ve yay (§4.9) ----

    void OnLoaded(object sender, RoutedEventArgs e)
    {
        if (_disposed) return;
        _c.RefreshDownloads();
        _downloadsTimer.Start();
        if (!_introWaiting || _introTimer.IsEnabled) return;
        // Açılış gösterisi: fiş bir an çekik bekler (çeviri kendiliğinden başlamış olsa da), sonra yaylanarak takılır.
        _introTimer.Interval = Motion.IsReduced ? TimeSpan.FromMilliseconds(1) : IntroWait;
        _introTimer.Start();
    }

    void StartSpring()
    {
        _springing = true;
        _springClock.Restart();
        _springTimer.Start();
        SpringStep(0);
    }

    void StopSpring()
    {
        if (!_springing) return;
        _springing = false;
        _springTimer.Stop();
        _springClock.Stop();
        _offset = default;
    }

    void OnSpringTick(object? sender, EventArgs e)
    {
        var t = _springClock.Elapsed.TotalSeconds;
        if (t >= PlugSpring.Duration)
        {
            StopSpring();
            DrawPlug();
            return;
        }
        SpringStep(t);
    }

    void SpringStep(double t)
    {
        var rest = _layout.PlugRest;
        var socket = _layout.Socket;
        var k = PlugSpring.Remaining(t);
        _offset = new ScenePoint((rest.X - socket.X) * k, (rest.Y - socket.Y) * k);
        DrawPlug();
    }

    // ---- Tıklama ve sürükleme (§4.10) ----

    void OnPlugDown(object sender, MouseButtonEventArgs e)
    {
        e.Handled = true;
        StopSpring();
        _dragStart = e.GetPosition(_scene);
        _offset = default;
        _dragging = true;
        _plug.CaptureMouse();
        DrawPlug();
        UpdateHint();
    }

    void OnPlugMove(object sender, MouseEventArgs e)
    {
        if (!_dragging) return;
        var now = e.GetPosition(_scene);
        _offset = new ScenePoint(now.X - _dragStart.X, now.Y - _dragStart.Y);
        DrawPlug();
    }

    void OnPlugUp(object sender, MouseButtonEventArgs e)
    {
        if (!_dragging) return;
        e.Handled = true;
        EndDrag(e.GetPosition(_scene));
    }

    void EndDrag(Point? at)
    {
        var offset = at is { } p ? new ScenePoint(p.X - _dragStart.X, p.Y - _dragStart.Y) : _offset;
        _dragging = false;
        if (_plug.IsMouseCaptured) _plug.ReleaseMouseCapture();
        _offset = default;
        DrawPlug();
        UpdateHint();
        if (at is null) return;
        if (PlugDrop.Decide(_layout, _plugged, offset) == PlugRelease.Toggle) _ = HomeActions.ToggleAsync(_c);
    }

    // ---- Yardımcılar ----

    static Rectangle Glow(double width, double height, double x, double y, double corner, double blur)
    {
        var rect = new Rectangle
        {
            Width = Math.Max(0, width),
            Height = Math.Max(0, height),
            RadiusX = corner,
            RadiusY = corner,
            Effect = new BlurEffect { Radius = blur },
        };
        Place(rect, x, y);
        return rect;
    }

    static LinearGradientBrush Gradient((byte R, byte G, byte B) a, (byte R, byte G, byte B) b, (byte R, byte G, byte B) c)
    {
        var brush = new LinearGradientBrush(new GradientStopCollection
        {
            new(Color.FromRgb(a.R, a.G, a.B), 0),
            new(Color.FromRgb(b.R, b.G, b.B), 0.5),
            new(Color.FromRgb(c.R, c.G, c.B), 1),
        }, new Point(0, 0.5), new Point(1, 0.5));
        brush.Freeze();
        return brush;
    }

    static void Place(UIElement element, double x, double y)
    {
        Canvas.SetLeft(element, x);
        Canvas.SetTop(element, y);
    }

    static ImageSource LoadImage(string file)
    {
        var bitmap = new BitmapImage();
        bitmap.BeginInit();
        bitmap.UriSource = new Uri("pack://application:,,,/Assets/" + file, UriKind.Absolute);
        bitmap.CacheOption = BitmapCacheOption.OnLoad;
        bitmap.EndInit();
        bitmap.Freeze();
        return bitmap;
    }

    void StopTimers()
    {
        _downloadsTimer.Stop();
        _springTimer.Stop();
        _badge?.Dispose();
        if (_introTimer.IsEnabled)
        {
            // Gösteri yarıda kaldıysa bekleme biter (yeniden kurulan sahne gösteriyi oynatmaz).
            _introTimer.Stop();
            _introWaiting = false;
            if (!_disposed) Apply(fromIntro: false, animate: false);
        }
    }

    /// <summary>Ekrandan kalkınca: zamanlayıcılar durur, denetleyiciden ayrılır.</summary>
    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        StopTimers();
        StopSpring();
        _c.PropertyChanged -= OnControllerChanged;
        PlugHintState.Changed -= OnHintVisibilityChanged;
        if (_hoverParts.Count > 0)
        {
            _hoverParts.Clear();
            PlugHintState.Hover(false);
        }
    }

    // ---- Fiş balonu (Mac ana-ekran §4.9) ----

    void BuildHint()
    {
        _hintText.SetResourceReference(StyleProperty, "Text.Callout");
        _hintText.SetResourceReference(TextBlock.ForegroundProperty, "textPrimaryBrush");
        _hintText.FlowDirection = L.IsRightToLeft ? FlowDirection.RightToLeft : FlowDirection.LeftToRight;
        _hintBubble.SetResourceReference(Border.BackgroundProperty, "surfaceBrush");
        _hintBubble.SetResourceReference(Border.BorderBrushProperty, "borderBrush");
        _hintBubble.Effect = new DropShadowEffect { BlurRadius = 10, ShadowDepth = 2, Direction = 270, Opacity = 0.12 };
        _hintBubble.Child = _hintText;
        _hintBubble.MouseEnter += (_, _) => Hover("bubble", true);
        _hintBubble.MouseLeave += (_, _) => Hover("bubble", false);
        _hintArrow.SetResourceReference(TextBlock.FontFamilyProperty, "font.icon");
        _hintArrow.SetResourceReference(TextBlock.ForegroundProperty, "accentBrush");
        _hintArrow.FontWeight = FontWeights.SemiBold;
        _hintLayer.Children.Add(_hintBubble);
        _hintLayer.Children.Add(_hintArrow);
    }

    void Hover(string part, bool inside)
    {
        var changed = inside ? _hoverParts.Add(part) : _hoverParts.Remove(part);
        if (changed) PlugHintState.Hover(_hoverParts.Count > 0);
    }

    void OnHintVisibilityChanged()
    {
        if (!_disposed) UpdateHint();
    }

    /// <summary>Balonun metni, görünürlüğü ve opaklığı; fişin ipucu ve sahnenin ekran okuyucu adı.</summary>
    void UpdateHint()
    {
        var key = _c.PlugHintKey(_plugged);
        var tip = L.Get(_plugged ? "home.plug.unplugToStop" : "home.plug.plugInToStart");
        _plug.ToolTip = tip;
        AutomationProperties.SetName(this, L.Get(_plugged ? "home.action.stop" : "home.action.start"));
        AutomationProperties.SetHelpText(this, key is null ? "" : L.Get(key));
        var shown = key is not null && !_dragging && !_introWaiting;
        if (key != _hintKey)
        {
            _hintKey = key;
            _hintText.Text = key is null ? "" : L.Get(key);
            PlaceHint();
        }
        _hintBubble.Show(shown);
        _hintArrow.Show(shown);
        var opacity = PlugHintState.Visible ? 1 : PlugHintVisibility.FadedOpacity;
        if (_hintShown != shown || Motion.IsReduced)
        {
            _hintLayer.BeginAnimation(OpacityProperty, null);
            _hintLayer.Opacity = opacity;
        }
        else if (Math.Abs(_hintLayer.Opacity - opacity) > 0.001)
        {
            var duration = PlugHintState.Visible ? PlugHintVisibility.FadeIn : PlugHintVisibility.FadeOut;
            _hintLayer.BeginAnimation(OpacityProperty, new DoubleAnimation(opacity, duration)
            {
                EasingFunction = new QuadraticEase { EasingMode = EasingMode.EaseInOut },
            });
        }
        _hintShown = shown;
    }

    /// <summary>Balonu ve oku ayrılan alana göre yerleştirir (<see cref="PlugHintPlacement"/>).</summary>
    void PlaceHint()
    {
        if (ActualWidth <= 0 || ActualHeight <= 0) return;
        var place = PlugHintPlacement.Compute(_layout, ActualWidth, Math.Max(0, ActualHeight - _signSpace));
        var box = place.Box with { Y = place.Box.Y + _signSpace };
        place = place with { ArrowTip = new ScenePoint(place.ArrowTip.X, place.ArrowTip.Y + _signSpace) };
        _hintBubble.MaxWidth = box.Width;
        _hintBubble.Measure(new Size(box.Width, double.PositiveInfinity));
        var size = _hintBubble.DesiredSize;
        Canvas.SetLeft(_hintBubble, box.Right - size.Width);
        Canvas.SetTop(_hintBubble, Math.Max(box.Y, box.Bottom - size.Height));
        _hintArrow.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity));
        Canvas.SetLeft(_hintArrow, place.ArrowTip.X - 9);
        Canvas.SetTop(_hintArrow, place.ArrowTip.Y - _hintArrow.DesiredSize.Height);
    }

    // ---- Oyun odası tabelası ----

    void UpdateSign(bool animate)
    {
        var sign = _c.GameRoomSignText;
        var text = sign?.Text;
        if (text != _signText)
        {
            _signText = text;
            if (sign is { } shown) _sign.SetText(shown);
            _sign.Visibility = sign is null ? Visibility.Collapsed : Visibility.Visible;
            PlaceSign();
            PlaceHint();
        }
        if (sign is not null) _sign.SetBright(_plugged, animate);
    }

    /// <summary>Tabelayı TV'nin üstüne yerleştirir; tabela kapalıysa sahne tüm alanı kullanır.</summary>
    void PlaceSign()
    {
        if (_signText is null || ActualWidth <= 0 || ActualHeight <= 0)
        {
            _signSpace = 0;
            _viewbox.Margin = new Thickness(0);
            return;
        }
        var place = GameRoomSignPlacement.Compute(_layout, ActualWidth, ActualHeight);
        _signSpace = place.TopSpace;
        _viewbox.Margin = new Thickness(0, _signSpace, 0, 0);
        _sign.Width = place.Box.Width;
        _sign.Height = place.Box.Height;
        Canvas.SetLeft(_sign, place.Box.X);
        Canvas.SetTop(_sign, place.Box.Y);
    }
}
