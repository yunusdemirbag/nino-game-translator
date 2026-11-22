// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Effects;
using System.Windows.Shapes;
using Nino.App.Controls;
using Nino.App.Strings;
using Nino.App.Theme;

namespace Nino.App.Views;

/// <summary>
/// "Nino'ya Sor" robot düğmesi (ana-ekran §2.4): 60 × 60, beyaz %96 daire, ince kenar, gölge; ortasında 44 × 44 süzülen
/// robot (2 px aşağıda). Üzerine gelince 1,07, basılıyken 0,95 kat (140 ms, ikinci dereceden eğri; hareketi azalt
/// açıksa anında). Klavye odağında dairenin 4 px dışında 2 px accentText halka. Temadan bağımsız (halka hariç).
/// </summary>
public sealed class RobotButton : Button
{
    /// <summary>Düğmenin kenarı.</summary>
    public const double Size = 60;

    static readonly Color CircleColor = Color.FromArgb(0xF5, 0xFF, 0xFF, 0xFF);
    static readonly Color CircleBorder = Color.FromArgb(0x1F, 0x0B, 0x16, 0x33);
    static readonly Color ShadowColor = Color.FromRgb(0x0B, 0x16, 0x33);

    readonly ScaleTransform _scale = new(1, 1);
    readonly NinoBot _bot;

    public RobotButton()
    {
        Width = Size;
        Height = Size;
        Cursor = Cursors.Hand;
        FlowDirection = FlowDirection.LeftToRight;
        var askNino = L.Get("home.robot.askNino");
        ToolTip = askNino;
        SetValue(AutomationProperties.NameProperty, askNino);
        SetValue(AutomationProperties.HelpTextProperty, askNino);
        FocusVisualStyle = RingStyle();

        _bot = new NinoBot
        {
            Width = 44,
            Height = 44,
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center,
            Margin = new Thickness(0, 4, 0, 0),
        };
        var circle = new Ellipse
        {
            Fill = Frozen(CircleColor),
            Stroke = Frozen(CircleBorder),
            StrokeThickness = 1,
            Effect = new DropShadowEffect
            {
                Color = ShadowColor,
                BlurRadius = 16,
                ShadowDepth = 3,
                Direction = 270,
                Opacity = 0.22,
            },
        };
        var face = new Grid { RenderTransformOrigin = new Point(0.5, 0.5), RenderTransform = _scale };
        face.Children.Add(circle);
        face.Children.Add(_bot);

        // Şablon yalnız içeriği gösterir (düğmenin kendi çerçevesi yok).
        Template = new ControlTemplate(typeof(Button))
        {
            VisualTree = new FrameworkElementFactory(typeof(ContentPresenter)),
        };
        Content = face;
        Background = Brushes.Transparent;
        BorderThickness = new Thickness(0);
        Padding = new Thickness(0);

        MouseEnter += (_, _) => ScaleTo(IsPressed ? 0.95 : 1.07);
        MouseLeave += (_, _) => ScaleTo(IsPressed ? 0.95 : 1);
        PreviewMouseLeftButtonDown += (_, _) => ScaleTo(0.95);
        PreviewMouseLeftButtonUp += (_, _) => ScaleTo(IsMouseOver ? 1.07 : 1);
        LostMouseCapture += (_, _) => ScaleTo(IsMouseOver ? 1.07 : 1);
    }

    /// <summary>Sohbette cevap beklenirken robot düşünür (hızlı süzülme, sallanma).</summary>
    public bool IsThinking
    {
        get => _bot.IsThinking;
        set => _bot.IsThinking = value;
    }

    void ScaleTo(double value)
    {
        if (Motion.IsReduced)
        {
            _scale.BeginAnimation(ScaleTransform.ScaleXProperty, null);
            _scale.BeginAnimation(ScaleTransform.ScaleYProperty, null);
            _scale.ScaleX = value;
            _scale.ScaleY = value;
            return;
        }
        var animation = new DoubleAnimation(value, TimeSpan.FromMilliseconds(140))
        {
            EasingFunction = new QuadraticEase { EasingMode = EasingMode.EaseOut },
        };
        _scale.BeginAnimation(ScaleTransform.ScaleXProperty, animation);
        _scale.BeginAnimation(ScaleTransform.ScaleYProperty, animation);
    }

    /// <summary>Klavye odağı: dairenin 4 px dışında 2 px accentText halka (yalnız klavyeyle gelinince).</summary>
    static Style RingStyle()
    {
        var ring = new FrameworkElementFactory(typeof(Ellipse));
        ring.SetValue(FrameworkElement.MarginProperty, new Thickness(-4));
        ring.SetValue(Shape.StrokeThicknessProperty, 2.0);
        ring.SetResourceReference(Shape.StrokeProperty, "accentTextBrush");
        ring.SetValue(UIElement.IsHitTestVisibleProperty, false);
        var style = new Style();
        style.Setters.Add(new Setter(Control.TemplateProperty, new ControlTemplate { VisualTree = ring }));
        return style;
    }

    static SolidColorBrush Frozen(Color color)
    {
        var brush = new SolidColorBrush(color);
        brush.Freeze();
        return brush;
    }
}
