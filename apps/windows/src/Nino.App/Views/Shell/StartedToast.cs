// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Windows;
using System.Windows.Automation;
using System.Windows.Automation.Peers;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Threading;
using Nino.App.Strings;
using Nino.App.Theme;

namespace Nino.App.Views;

/// <summary>
/// "Çeviri başladı" balonu (ana-ekran §2.3): tam kapsül, siyah %55 zemin, beyaz %14 kenar, 17 kalın beyaz tek satır.
/// Gösterilince 7 sn sonra 0,4 sn'de söner; yeniden gösterilirse süre baştan başlar; sönme bitince ancak yeniden
/// gösterilmediyse gizlenir. Belirme: opaklık 0→1 0,3 sn ve soldan 24 px kayma 0,4 sn (kübik ease-out); sönme ikinci
/// dereceden ease-out. Hareketi azalt açıksa anında. Tıklamaları engellemez, odak almaz; ekran okuyucuya nazik canlı
/// bölge olarak bildirilir. Temadan bağımsız.
/// </summary>
public sealed class StartedToast : Border
{
    static readonly TimeSpan VisibleFor = TimeSpan.FromSeconds(7);

    readonly TranslateTransform _slide = new();
    readonly TextBlock _text;
    readonly DispatcherTimer _timer;
    int _generation;

    public StartedToast()
    {
        CornerRadius = new CornerRadius(999);
        Background = Frozen(Color.FromArgb(0x8C, 0x00, 0x00, 0x00));
        BorderBrush = Frozen(Color.FromArgb(0x24, 0xFF, 0xFF, 0xFF));
        BorderThickness = new Thickness(1);
        Padding = new Thickness { Left = 20, Top = 13, Right = 20, Bottom = 13 };
        IsHitTestVisible = false;
        Focusable = false;
        Visibility = Visibility.Collapsed;
        Opacity = 0;
        RenderTransform = _slide;
        _text = new TextBlock
        {
            Text = L.Get("home.toast.translationStarted"),
            FontSize = 17,
            FontWeight = FontWeights.Bold,
            Foreground = Brushes.White,
            TextWrapping = TextWrapping.NoWrap,
        };
        Child = _text;
        // Kenarlığın otomasyon eşi yok; ekran okuyucuya yazının kendisi bildirilir.
        AutomationProperties.SetName(_text, _text.Text);
        _text.SetValue(AutomationProperties.LiveSettingProperty, AutomationLiveSetting.Polite);
        _timer = new DispatcherTimer { Interval = VisibleFor };
        _timer.Tick += (_, _) =>
        {
            _timer.Stop();
            Hide(TimeSpan.FromSeconds(0.4));
        };
    }

    /// <summary>Balonu gösterir (süre baştan başlar).</summary>
    public void Show()
    {
        _generation++;
        _timer.Stop();
        Visibility = Visibility.Visible;
        if (Motion.IsReduced)
        {
            BeginAnimation(OpacityProperty, null);
            _slide.BeginAnimation(TranslateTransform.XProperty, null);
            Opacity = 1;
            _slide.X = 0;
        }
        else
        {
            var cubicOut = new CubicEase { EasingMode = EasingMode.EaseOut };
            BeginAnimation(OpacityProperty, new DoubleAnimation(0, 1, TimeSpan.FromSeconds(0.3)) { EasingFunction = cubicOut });
            _slide.BeginAnimation(TranslateTransform.XProperty,
                new DoubleAnimation(-24, 0, TimeSpan.FromSeconds(0.4)) { EasingFunction = cubicOut });
        }
        _timer.Start();
        try
        {
            (UIElementAutomationPeer.FromElement(_text) ?? UIElementAutomationPeer.CreatePeerForElement(_text))
                ?.RaiseAutomationEvent(AutomationEvents.LiveRegionChanged);
        }
        catch (Exception) { }
    }

    /// <summary>Balonu verilen sürede söndürür (çeviri durunca 0,25 sn).</summary>
    public void Hide(TimeSpan duration)
    {
        _timer.Stop();
        if (Visibility is not Visibility.Visible) return;
        var generation = ++_generation;
        if (Motion.IsReduced || duration <= TimeSpan.Zero)
        {
            HideNow();
            return;
        }
        var fade = new DoubleAnimation(0, duration) { EasingFunction = new QuadraticEase { EasingMode = EasingMode.EaseOut } };
        fade.Completed += (_, _) =>
        {
            if (generation == _generation) HideNow();
        };
        BeginAnimation(OpacityProperty, fade);
    }

    /// <summary>Hemen gizler (kurulum sihirbazına geçince).</summary>
    public void HideNow()
    {
        _timer.Stop();
        _generation++;
        BeginAnimation(OpacityProperty, null);
        _slide.BeginAnimation(TranslateTransform.XProperty, null);
        Opacity = 0;
        Visibility = Visibility.Collapsed;
    }

    static SolidColorBrush Frozen(Color color)
    {
        var brush = new SolidColorBrush(color);
        brush.Freeze();
        return brush;
    }
}
