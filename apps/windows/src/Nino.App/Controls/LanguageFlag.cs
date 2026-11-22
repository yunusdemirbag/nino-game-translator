// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using Nino.Core.Translation;

namespace Nino.App.Controls;

/// <summary>
/// Çeviri dilinin bayrağı, şekillerle çizilir (Windows bayrak emojisini "TR" gibi harflerle gösterir). 22 × 15,
/// köşeleri 2,5 yuvarlatılarak kırpılır, her zaman soldan sağa. Kodun ilk iki harfi küçük harfle karşılaştırılır;
/// listede olmayan her kod Türk bayrağıdır.
/// </summary>
public sealed class LanguageFlag : FrameworkElement
{
    public const double FlagWidth = 22;
    public const double FlagHeight = 15;

    public static readonly DependencyProperty CodeProperty = DependencyProperty.Register(nameof(Code), typeof(string),
        typeof(LanguageFlag), new FrameworkPropertyMetadata("tr", FrameworkPropertyMetadataOptions.AffectsRender));

    private static readonly Dictionary<string, Drawing> Cache = new();

    public LanguageFlag()
    {
        FlowDirection = FlowDirection.LeftToRight;
        SnapsToDevicePixels = true;
    }

    /// <summary>Dil kodu ("tr", "ar", "tl" …).</summary>
    public string? Code
    {
        get => (string?)GetValue(CodeProperty);
        set => SetValue(CodeProperty, value);
    }

    protected override Size MeasureOverride(Size availableSize) => new(FlagWidth, FlagHeight);

    protected override void OnRender(DrawingContext dc)
    {
        dc.PushClip(new RectangleGeometry(new Rect(0, 0, FlagWidth, FlagHeight), 2.5, 2.5));
        dc.DrawDrawing(DrawingFor(Code));
        dc.Pop();
    }

    /// <summary>Bayrağın çizimi (dondurulmuş, kod başına bir kez kurulur).</summary>
    public static Drawing DrawingFor(string? code)
    {
        var key = Normalize(code);
        lock (Cache)
        {
            if (Cache.TryGetValue(key, out var cached)) return cached;
            var group = new DrawingGroup();
            using (var dc = group.Open()) Draw(dc, key);
            group.Freeze();
            Cache[key] = group;
            return group;
        }
    }

    private static string Normalize(string? code)
    {
        var c = (code ?? "").Trim().ToLowerInvariant();
        if (c.StartsWith("fil", StringComparison.Ordinal)) return "tl";
        return c.Length >= 2 ? c[..2] : "tr";
    }

    private static readonly Brush White = Frozen(Colors.White);

    private static Brush Frozen(Color color)
    {
        var b = new SolidColorBrush(color);
        b.Freeze();
        return b;
    }

    private static Brush Hex(uint rgb) =>
        Frozen(Color.FromRgb((byte)(rgb >> 16), (byte)(rgb >> 8), (byte)rgb));

    private static void Background(DrawingContext dc, Brush brush) =>
        dc.DrawRectangle(brush, null, new Rect(0, 0, FlagWidth, FlagHeight));

    private static void Box(DrawingContext dc, Brush brush, double w, double h, double x, double y) =>
        dc.DrawRectangle(brush, null, new Rect(x, y, w, h));

    // Eşit yatay şeritler, yukarıdan aşağı; ek yeri görünmesin diye 0,2 taşma payı.
    private static void Stripes(DrawingContext dc, params Brush[] brushes)
    {
        var h = FlagHeight / brushes.Length;
        for (var i = 0; i < brushes.Length; i++) Box(dc, brushes[i], FlagWidth, h + 0.2, 0, i * h);
    }

    // (x, y) sol üst köşeli, b boylu daire.
    private static void Disc(DrawingContext dc, Brush brush, double size, double x, double y) =>
        dc.DrawEllipse(brush, null, new Point(x + size / 2, y + size / 2), size / 2, size / 2);

    // Hilal: dolu daire, üstüne b×0,8 boyunda oyuk renkli daire (sol üstü x + b×0,22, y + (b − b×0,8)/2).
    private static void Crescent(DrawingContext dc, double x, double y, double size, Brush hollow, Brush? color = null)
    {
        Disc(dc, color ?? White, size, x, y);
        var inner = size * 0.8;
        Disc(dc, hollow, inner, x + size * 0.22, y + (size - inner) / 2);
    }

    // Beş köşeli yıldız: 10 nokta, i. nokta açısı 90° + i × 36°, yarıçap çift i'de r, tek i'de r × 0,42.
    private static void Star(DrawingContext dc, Brush brush, double cx, double cy, double r)
    {
        var geometry = new StreamGeometry();
        using (var ctx = geometry.Open())
        {
            for (var i = 0; i < 10; i++)
            {
                var angle = (90 + i * 36) * Math.PI / 180;
                var radius = i % 2 == 0 ? r : r * 0.42;
                var p = new Point(cx + radius * Math.Cos(angle), cy - radius * Math.Sin(angle));
                if (i == 0) ctx.BeginFigure(p, true, true);
                else ctx.LineTo(p, true, false);
            }
        }
        geometry.Freeze();
        dc.DrawGeometry(brush, null, geometry);
    }

    private static void Draw(DrawingContext dc, string code)
    {
        switch (code)
        {
            case "ar":
            {
                Background(dc, Hex(0x006C35));
                Box(dc, White, 12, 1.2, 5, 4.2);
                Box(dc, White, 9, 1.2, 6.5, 6.6);
                Box(dc, White, 13, 1, 4.5, 10.2);
                Box(dc, White, 1, 2.4, 15.5, 9.5);
                break;
            }
            case "hi":
            {
                Stripes(dc, Hex(0xFF9933), White, Hex(0x138808));
                var pen = new Pen(Hex(0x000080), 0.9);
                pen.Freeze();
                dc.DrawEllipse(null, pen, new Point(9 + 2, 5.5 + 2), 2, 2);
                break;
            }
            case "id":
                Stripes(dc, Hex(0xCE1126), White);
                break;
            case "th":
                Background(dc, Hex(0xA51931));
                Box(dc, White, 22, 2.5, 0, 2.5);
                Box(dc, Hex(0x2D2A4A), 22, 5, 0, 5);
                Box(dc, White, 22, 2.5, 0, 10);
                break;
            case "vi":
                Background(dc, Hex(0xDA251D));
                Star(dc, Hex(0xFFFF00), 11, 7.8, 4.2);
                break;
            case "ur":
            {
                var green = Hex(0x01411C);
                Background(dc, green);
                Box(dc, White, 5.5, 15, 0, 0);
                Crescent(dc, 9.2, 3.6, 7.4, green);
                Star(dc, White, 16.4, 5.6, 1.6);
                break;
            }
            case "bn":
                Background(dc, Hex(0x006A4E));
                Disc(dc, Hex(0xF42A41), 8.4, 5.6, 3.3);
                break;
            case "ms":
            {
                Background(dc, White);
                var red = Hex(0xCC0001);
                var stripe = FlagHeight / 14;
                for (var i = 0; i <= 12; i += 2) Box(dc, red, FlagWidth, stripe + 0.1, 0, i * stripe);
                var blue = Hex(0x010066);
                var yellow = Hex(0xFFCC00);
                Box(dc, blue, 11, 8.6, 0, 0);
                Crescent(dc, 1.6, 1.6, 5.4, blue, yellow);
                Star(dc, yellow, 7.8, 4.3, 1.5);
                break;
            }
            case "tl":
            {
                Stripes(dc, Hex(0x0038A8), Hex(0xCE1126));
                var triangle = new StreamGeometry();
                using (var ctx = triangle.Open())
                {
                    ctx.BeginFigure(new Point(0, 0), true, true);
                    ctx.LineTo(new Point(11, 7.5), true, false);
                    ctx.LineTo(new Point(0, 15), true, false);
                }
                triangle.Freeze();
                dc.DrawGeometry(White, null, triangle);
                Disc(dc, Hex(0xFCD116), 3, 2.6, 6);
                break;
            }
            case "nl":
                Stripes(dc, Hex(0xAE1C28), White, Hex(0x21468B));
                break;
            default:
            {
                var red = Hex(0xE30A17);
                Background(dc, red);
                Crescent(dc, 4.2, 3.7, 7.6, red);
                Star(dc, White, 13.4, 7.5, 2.1);
                break;
            }
        }
    }
}

/// <summary>
/// Dil satırı: bayrak + 10 boşluk + dilin kendi adı (dikeyde ortalı), her zaman soldan sağa. Açılır listelerde ve
/// karşılama adımında kullanılır.
/// </summary>
public sealed class LanguageLabel : StackPanel
{
    public static readonly DependencyProperty CodeProperty = DependencyProperty.Register(nameof(Code), typeof(string),
        typeof(LanguageLabel), new PropertyMetadata("tr", (d, _) => ((LanguageLabel)d).Update()));

    private readonly LanguageFlag _flag = new() { Margin = new Thickness(0, 0, 10, 0), VerticalAlignment = VerticalAlignment.Center };
    private readonly TextBlock _name = new() { VerticalAlignment = VerticalAlignment.Center, TextWrapping = TextWrapping.NoWrap };

    public LanguageLabel()
    {
        Orientation = Orientation.Horizontal;
        FlowDirection = FlowDirection.LeftToRight;
        Children.Add(_flag);
        Children.Add(_name);
        Update();
    }

    public string? Code
    {
        get => (string?)GetValue(CodeProperty);
        set => SetValue(CodeProperty, value);
    }

    private void Update()
    {
        _flag.Code = Code;
        _name.Text = TargetLanguages.NativeName(Code);
    }
}
