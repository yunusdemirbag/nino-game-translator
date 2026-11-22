// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace Nino.App.Views;

/// <summary>Koddan kurulan görünümler için küçük yardımcılar (ortak stillere dinamik kaynakla bağlanır).</summary>
internal static class HomeUi
{
    /// <summary>Adlı yazı stiliyle (ör. "Text.Headline") yazı.</summary>
    public static TextBlock Text(string? text, string style, Thickness? margin = null)
    {
        var t = new TextBlock { Text = text ?? "" };
        t.SetResourceReference(FrameworkElement.StyleProperty, style);
        if (margin is { } m) t.Margin = m;
        return t;
    }

    /// <summary>Belirteç renkli fırçayı bağlar (ör. "warningBrush").</summary>
    public static T Brush<T>(this T element, DependencyProperty property, string brushKey) where T : FrameworkElement
    {
        element.SetResourceReference(property, brushKey);
        return element;
    }

    /// <summary>Adlı düğme stiliyle düğme (null: varsayılan ikincil).</summary>
    public static Button Button(object content, string? style = null, Thickness? padding = null, Thickness? margin = null)
    {
        var button = new Button { Content = content };
        if (style is not null) button.SetResourceReference(FrameworkElement.StyleProperty, style);
        if (padding is { } p) button.Padding = p;
        if (margin is { } m) button.Margin = m;
        return button;
    }

    /// <summary>Simge (20 px) + 8 boşluk + yazı.</summary>
    public static StackPanel IconLabel(string glyph, string label)
    {
        var panel = new StackPanel { Orientation = Orientation.Horizontal };
        var icon = new TextBlock { Text = glyph, FontSize = 20, Margin = new Thickness(0, 0, 8, 0) };
        icon.SetResourceReference(FrameworkElement.StyleProperty, "Text.Icon");
        panel.Children.Add(icon);
        panel.Children.Add(new TextBlock { Text = label, VerticalAlignment = VerticalAlignment.Center, TextWrapping = TextWrapping.NoWrap });
        return panel;
    }

    /// <summary>Görünür / gizli (yer kaplamaz).</summary>
    public static void Show(this UIElement element, bool visible) =>
        element.Visibility = visible ? Visibility.Visible : Visibility.Collapsed;

    /// <summary>Dondurulmuş düz fırça.</summary>
    public static SolidColorBrush Solid(byte a, byte r, byte g, byte b)
    {
        var brush = new SolidColorBrush(Color.FromArgb(a, r, g, b));
        brush.Freeze();
        return brush;
    }

    /// <summary>Dondurulmuş düz fırça (opak).</summary>
    public static SolidColorBrush Solid(uint rgb) =>
        Solid(0xFF, (byte)(rgb >> 16), (byte)(rgb >> 8), (byte)rgb);

    /// <summary>Opak renk.</summary>
    public static Color Rgb(uint rgb) => Color.FromRgb((byte)(rgb >> 16), (byte)(rgb >> 8), (byte)rgb);
}
