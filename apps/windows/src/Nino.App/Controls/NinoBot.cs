// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using Nino.App.Theme;

namespace Nino.App.Controls;

/// <summary>
/// "Nino" robotu: göz açık ve göz kırpan iki kare. Her 4–5 sn'de bir (4000 ms + 0–999 ms) 150 ms göz kırpar; boyunun
/// 0,05'i kadar (en az 2) 1,6 sn'lik yarım turla yukarı-aşağı süzülür. Düşünürken süzülme 0,45 sn'ye iner ve ayrıca
/// −6° ↔ +6° 0,6 sn sallanır (dönme merkezi görselin (0,5; 0,9) noktası). Ekrandan kalkınca açık göze döner,
/// hareketler durur. Hareketi azalt açıksa hiç kıpırdamaz, göz kırpmaz. Aynalanmaz.
/// </summary>
public sealed class NinoBot : Image
{
    public static ImageSource OpenFrame { get; } = Load("nino-bot-256.png");
    public static ImageSource BlinkFrame { get; } = Load("nino-bot-blink-256.png");

    public static readonly DependencyProperty BlinksProperty = DependencyProperty.Register(nameof(Blinks), typeof(bool),
        typeof(NinoBot), new PropertyMetadata(true, (d, _) => ((NinoBot)d).Restart()));

    public static readonly DependencyProperty FloatsProperty = DependencyProperty.Register(nameof(Floats), typeof(bool),
        typeof(NinoBot), new PropertyMetadata(true, (d, _) => ((NinoBot)d).Restart()));

    public static readonly DependencyProperty IsThinkingProperty = DependencyProperty.Register(nameof(IsThinking),
        typeof(bool), typeof(NinoBot), new PropertyMetadata(false, (d, _) => ((NinoBot)d).Restart()));

    private readonly TranslateTransform _float = new();
    private readonly RotateTransform _sway = new();
    private readonly DispatcherTimer _blinkTimer;
    private bool _blinkClosed;
    private bool _live;

    public NinoBot()
    {
        Source = OpenFrame;
        Stretch = Stretch.Uniform;
        FlowDirection = FlowDirection.LeftToRight;
        RenderOptions.SetBitmapScalingMode(this, BitmapScalingMode.HighQuality);
        RenderTransformOrigin = new Point(0.5, 0.9);
        RenderTransform = new TransformGroup { Children = { _sway, _float } };
        _blinkTimer = new DispatcherTimer(DispatcherPriority.Background);
        _blinkTimer.Tick += OnEyeTimer;
        Loaded += (_, _) => { _live = true; Restart(); };
        Unloaded += (_, _) => { _live = false; Stop(); };
        SizeChanged += (_, _) => Restart();
    }

    /// <summary>Göz kırpar mı (sohbet satırındaki küçük robot kırpmaz).</summary>
    public bool Blinks
    {
        get => (bool)GetValue(BlinksProperty);
        set => SetValue(BlinksProperty, value);
    }

    /// <summary>Boştayken süzülür mü.</summary>
    public bool Floats
    {
        get => (bool)GetValue(FloatsProperty);
        set => SetValue(FloatsProperty, value);
    }

    /// <summary>Cevap beklenirken: hızlı süzülme ve sallanma.</summary>
    public bool IsThinking
    {
        get => (bool)GetValue(IsThinkingProperty);
        set => SetValue(IsThinkingProperty, value);
    }

    private void Stop()
    {
        _blinkTimer.Stop();
        _blinkClosed = false;
        Source = OpenFrame;
        _float.BeginAnimation(TranslateTransform.YProperty, null);
        _sway.BeginAnimation(RotateTransform.AngleProperty, null);
        _float.Y = 0;
        _sway.Angle = 0;
    }

    private void Restart()
    {
        Stop();
        if (!_live || Motion.IsReduced) return;

        if (Blinks) ScheduleBlink();

        if (Floats || IsThinking)
        {
            var amplitude = Math.Max(2, ActualHeight * 0.05);
            var half = TimeSpan.FromSeconds(IsThinking ? 0.45 : 1.6);
            var bob = new DoubleAnimation(-amplitude / 2, amplitude / 2, half)
            {
                AutoReverse = true,
                RepeatBehavior = RepeatBehavior.Forever,
                EasingFunction = new SineEase { EasingMode = EasingMode.EaseInOut },
            };
            _float.BeginAnimation(TranslateTransform.YProperty, bob);
        }

        if (IsThinking)
        {
            var sway = new DoubleAnimation(-6, 6, TimeSpan.FromSeconds(0.6))
            {
                AutoReverse = true,
                RepeatBehavior = RepeatBehavior.Forever,
                EasingFunction = new SineEase { EasingMode = EasingMode.EaseInOut },
            };
            _sway.BeginAnimation(RotateTransform.AngleProperty, sway);
        }
    }

    private void ScheduleBlink()
    {
        _blinkTimer.Interval = TimeSpan.FromMilliseconds(4000 + Random.Shared.Next(0, 1000));
        _blinkTimer.Start();
    }

    private void OnEyeTimer(object? sender, EventArgs e)
    {
        _blinkTimer.Stop();
        if (!_live || !Blinks || Motion.IsReduced)
        {
            Source = OpenFrame;
            return;
        }
        if (_blinkClosed)
        {
            _blinkClosed = false;
            Source = OpenFrame;
            ScheduleBlink();
        }
        else
        {
            _blinkClosed = true;
            Source = BlinkFrame;
            _blinkTimer.Interval = TimeSpan.FromMilliseconds(150);
            _blinkTimer.Start();
        }
    }

    private static ImageSource Load(string file)
    {
        var image = new BitmapImage();
        image.BeginInit();
        image.UriSource = new Uri("pack://application:,,,/Assets/Bot/" + file, UriKind.Absolute);
        image.CacheOption = BitmapCacheOption.OnLoad;
        image.EndInit();
        image.Freeze();
        return image;
    }
}
