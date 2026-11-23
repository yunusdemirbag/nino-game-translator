// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Effects;
using Nino.App.Theme;
using Nino.Core.Design;

namespace Nino.App.Views;

/// <summary>
/// TV'nin üstündeki neon oyun odası tabelası: soldan sağa pembe → mor → mavi dolgu, pembe ve mavi ışıma. Fiş takılıyken
/// tam parlak, çıkıkken soluk ve ışımasız (0,4 sn geçiş). Ölçeklenmeyen katmanda, kutuya sığdırılır.
/// </summary>
public sealed class GameRoomSignView : Viewbox
{
    static readonly FontFamily LatinFont = new("Bahnschrift SemiBold Condensed, Bahnschrift, Arial Narrow, Segoe UI");
    static readonly FontFamily ArabicFont = new("Segoe UI Black, Segoe UI, Tahoma");

    readonly TextBlock _text = new() { TextAlignment = TextAlignment.Center };
    readonly Grid _outer = new();
    readonly DropShadowEffect _pink = new() { ShadowDepth = 0 };
    readonly DropShadowEffect _blue = new() { ShadowDepth = 0 };
    bool? _bright;
    bool _dark = true;

    public GameRoomSignView()
    {
        Stretch = Stretch.Uniform;
        StretchDirection = StretchDirection.Both;
        IsHitTestVisible = false;
        HorizontalAlignment = HorizontalAlignment.Center;
        VerticalAlignment = VerticalAlignment.Bottom;
        _text.FontSize = 78;
        _text.Margin = new Thickness(20, 6, 20, 10);
        _text.Effect = _pink;
        _outer.Effect = _blue;
        _outer.Children.Add(_text);
        Child = _outer;
        Opacity = 0;
        ApplyTheme(ThemeManager.IsDark);
        Loaded += (_, _) => ThemeManager.ThemeChanged += OnThemeChanged;
        Unloaded += (_, _) => ThemeManager.ThemeChanged -= OnThemeChanged;
    }

    void OnThemeChanged(object? sender, bool dark) => Dispatcher.BeginInvoke(() => ApplyTheme(dark));

    (uint Argb, double Radius) PinkGlow => _dark ? GameRoomSign.PinkGlow : GameRoomSign.LightPinkGlow;
    (uint Argb, double Radius) BlueGlow => _dark ? GameRoomSign.BlueGlow : GameRoomSign.LightBlueGlow;

    /// <summary>
    /// Koyu görünümde tarifteki renkler; açık görünümde tonlar koyulaşır, ışıma güçlenir, soluk hâl %60 olur.
    /// </summary>
    void ApplyTheme(bool dark)
    {
        _dark = dark;
        var stops = new GradientStopCollection();
        foreach (var (offset, rgb) in dark ? GameRoomSign.Gradient : GameRoomSign.LightGradient)
            stops.Add(new GradientStop(Color.FromRgb((byte)(rgb >> 16), (byte)(rgb >> 8), (byte)rgb), offset));
        var fill = new LinearGradientBrush(stops, new Point(0, 0.5), new Point(1, 0.5));
        fill.Freeze();
        _text.Foreground = fill;
        SetGlow(_pink, PinkGlow);
        SetGlow(_blue, BlueGlow);
        if (_bright is { } bright)
        {
            _bright = null;
            SetBright(bright, animate: false);
        }
    }

    static void SetGlow(DropShadowEffect effect, (uint Argb, double Radius) glow)
    {
        effect.Color = Color.FromRgb((byte)(glow.Argb >> 16), (byte)(glow.Argb >> 8), (byte)glow.Argb);
        effect.BlurRadius = glow.Radius * 2;
    }

    /// <summary>Metni ve biçimi kurar.</summary>
    public void SetText(GameRoomSignText sign)
    {
        _text.Text = sign.Text;
        if (sign.Script == GameRoomScript.Arabic)
        {
            _text.FontFamily = ArabicFont;
            _text.FontStyle = FontStyles.Normal;
            _text.FontWeight = FontWeights.Black;
            _text.FontStretch = FontStretches.Normal;
            _text.FlowDirection = FlowDirection.RightToLeft;
        }
        else
        {
            _text.FontFamily = LatinFont;
            _text.FontStyle = FontStyles.Italic;
            _text.FontWeight = FontWeights.Bold;
            _text.FontStretch = FontStretches.Condensed;
            _text.FlowDirection = FlowDirection.LeftToRight;
        }
        AutomationNames.Set(this, sign.Text);
    }

    /// <summary>Parlak (fiş takılı) ya da soluk.</summary>
    public void SetBright(bool bright, bool animate)
    {
        if (_bright == bright) return;
        var first = _bright is null;
        _bright = bright;
        var to = bright ? 1 : GameRoomSign.DimFor(_dark);
        var pinkTo = bright ? (PinkGlow.Argb >> 24) / 255.0 : 0;
        var blueTo = bright ? (BlueGlow.Argb >> 24) / 255.0 : 0;
        if (!animate || first || Motion.IsReduced)
        {
            BeginAnimation(OpacityProperty, null);
            _pink.BeginAnimation(DropShadowEffect.OpacityProperty, null);
            _blue.BeginAnimation(DropShadowEffect.OpacityProperty, null);
            Opacity = to;
            _pink.Opacity = pinkTo;
            _blue.Opacity = blueTo;
            return;
        }
        var d = GameRoomSign.FadeDuration;
        BeginAnimation(OpacityProperty, new DoubleAnimation(to, d));
        _pink.BeginAnimation(DropShadowEffect.OpacityProperty, new DoubleAnimation(pinkTo, d));
        _blue.BeginAnimation(DropShadowEffect.OpacityProperty, new DoubleAnimation(blueTo, d));
    }
}
